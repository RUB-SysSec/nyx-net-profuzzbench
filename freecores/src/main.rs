use io::prelude::*;
use regex::Regex;
use std::{collections::HashSet, fs, io};
use structopt::StructOpt;

#[derive(StructOpt)]
struct Opts {
    /// Number of parallel jobs
    #[structopt(short = "j", long, default_value = "1")]
    par: u8,
    /// How to join the resulting cores when printing
    #[structopt(short = "J", long, default_value = " ")]
    join: String,
    /// Join with newlines
    #[structopt(short = "n", long)]
    newline: bool,
    /// Print PIDs for each taken core
    #[structopt(short, long)]
    processes: bool,
    /// Available cores to consider
    available: Vec<u32>,
}

fn main() {
    let opts = Opts::from_args();
    if opts.available.is_empty() {
        std::process::exit(1);
    }
    let free = get(&opts)
        .unwrap()
        .map(ToString::to_string)
        .collect::<Vec<_>>();
    if free.is_empty() {
        std::process::exit(1);
    }
    println!(
        "{}",
        free.join(if opts.newline { "\n" } else { &opts.join })
    );
}

fn get(opts: &Opts) -> io::Result<impl Iterator<Item = &u32>> {
    let core_re = Regex::new(r"^Cpus_allowed_list:\s+(\d+)$").unwrap();
    let mut taken = HashSet::<u32>::new();

    let mut paths = Vec::new();
    for entry in fs::read_dir("/proc")? {
        let entry = entry?;
        let st_path = entry.path().join("status");
        if !st_path.exists() {
            continue;
        }
        paths.push((entry.file_name(), st_path));
    }

    let cs = paths.len() as f64 / opts.par as f64;
    let cs = cs.ceil() as usize;
    let chunks = paths.chunks(cs);
    assert_eq!(chunks.len(), opts.par.into());

    let mut th_handles = Vec::new();
    let (tx, rx) = std::sync::mpsc::channel();
    for chunk in chunks {
        let tx = tx.clone();
        let re = core_re.clone();
        let chunk = chunk.to_vec();
        let handle = std::thread::spawn(move || {
            for (proc, path) in chunk {
                if let Some(core) = taken_core(&re, path).unwrap() {
                    tx.send((proc, core)).unwrap();
                }
            }
        });
        th_handles.push(handle);
    }

    drop(tx);
    for th in th_handles {
        th.join().expect("failed to join thread");
    }

    while let Ok((proc, core)) = rx.recv() {
        taken.insert(core);
        if opts.processes {
            println!("{:3} : {}", core, proc.to_string_lossy())
        }
    }

    let free = opts.available.iter().filter(move |av| !taken.contains(av));
    Ok(free)
}

fn taken_core(re: &Regex, path: impl AsRef<std::path::Path>) -> io::Result<Option<u32>> {
    let file = match fs::File::open(path) {
        Ok(file) => file,
        Err(e) if e.kind() == io::ErrorKind::NotFound => {
            return Ok(None);
        }
        Err(e) => return Err(e),
    };
    let rd = io::BufReader::new(file);
    let mut has_vmsize = false;
    let mut core = None::<u32>;
    for line in rd.lines() {
        let line = line?;
        if line.starts_with("VmSize:") {
            has_vmsize = true;
            continue;
        }
        if let Some(cap) = re.captures(&line) {
            core = Some(
                cap[1]
                    .parse()
                    .map_err(|e| io::Error::new(io::ErrorKind::Other, e))?,
            );
            if has_vmsize {
                break;
            }
        }
    }
    Ok(core.and_then(|core| if has_vmsize { Some(core) } else { None }))
}
