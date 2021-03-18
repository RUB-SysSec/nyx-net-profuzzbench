# README for profuzzbench-plus

## Building Docker containers

You can use the utility `scripts/buildall.sh` to build all images in parallel;
remember to change the number of parallel jobs inside the script as needed
(default is 20).

Otherwise you can manually build selected images with, e.g.:

```bash
docker build -t pfb-kamailio subjects/SIP/Kamailio
```

**N.B.**: the framework assumes that docker images are named `pfb-$target`.

## Running fuzzers

**When running the following two scripts with the `-r` flag, dont't start them
in parallel or core-pinning may fail to assign a core to a single process!**
Just start one, wait for all the sub-processes to start, and only then start
the next script.

### AFL-based

Example running 10 trials of 360 seconds each of aflnet on kamailio (will
search for free cores and assign each run to one free core):

```bash
execution/profuzzbench_exec_common.sh -r 10 -t kamailio -d outdir -f aflnet \
    -O '-m 200 -t 3000+ -P SIP -l 5061 -D 50000 -q 3 -s 3 -E -K -c run_pjsip' \
    -T 360 -S 5
```

the output will be in `outdir/out-kamailio-aflnet-00{0...9}.tar.gz`.

The following instead will run a single trial (with index 7) pinned on core 3:

```bash
execution/profuzzbench_exec_common.sh -c 3 -i 7 -t kamailio -d outdir -f aflnet [...]
```

the output will be in `outdir/out-kamailio-aflnet-007.tar.gz`

Flags are described in the README's tutorial and the help:
`execution/profuzzbench_exec_common.sh -h`.

**N.B.**: this script interacts with Docker and has a variable inside named
`DSUDO`; set it to the empty string if your Docker setup does not require root.

This script essentially calls the `run.sh` entrypoint for the specified target;
also computes coverage in the same container after running the fuzzer.

### Running Nyx-Net

The script responsible for this is `scripts/nyx-eval/start.sh`. Try `-h` for a
description of flags. It works in a similar way as
`profuzzbench_exec_common.sh`. Example to run 10 trials of Nyx-Net for 360
seconds each, on kamailio (will auto-assign to free cores):

```bash
export NYX_NET_FUZZER_DIR=/path/to/nyx-net/fuzzer/rust_fuzzer
nyx-eval/start.sh -r 10 -t kamailio -d /tmp -p none -T 360
```

the output will be in `/tmp/out-kamailio-00{0...9}`. Flags `-c` and `-i` work
the same as `profuzzbench_exec_common.sh`.

**The script expects specs in `$NYX_NET_TARGETS_DIR/nyx_$target`.**

The `-p` flag selects the incremental snapshot placement policy; `none` is for
no incremental snapshots. For values other than `none`, the output path will
be, e.g.: `$outdir/out-$target-${snaps_policy}-000`. Standard output from the
fuzzer is piped into, e.g., `$outdir/out-$target-000.log`.

## Gathering coverage

Gathering coverage is generally accomplished with the `nyx-eval/coverage.sh`
script. In case of Nyx-Net you may want to first extract *replayable* test
cases.

### Replayable inputs (Nyx-Net only)

The `nyx-eval/reproducible.sh` script works similarly to `start.sh`. Example:

```bash
export NYX_NET_FUZZER_DEBUG_DIR=/path/to/nyx-net/fuzzer/rust_fuzzer_debug
nyx-eval/reproducible.sh -r 10 -t kamailio -d /tmp -p none
```

will create replayable inputs inside the run directory, e.g.:
`/tmp/out-kamailio-000/reproducible`. The `-p` flag here is only used to
determine the paths. Standard output from each run of the tool is piped into,
e.g., `$outdir/out-kamailio-000/reproducible.log`.

### Computing coverage

Now that you have reproducible inputs you can run the `nyx-eval/coverage.sh`
script. Again, this has a similar interface as the other scripts:

```bash
nyx-eval/coverage.sh -r 10 -t kamailio -d outdir -f aflnet -s 5
```

The example above will extract all the aflnet archives from 10 trials (e.g.
`outdir/out-kamailio-aflnet-000.tar.gz`) after **deleting the older folders**
(i.e. `outdir/out-kamailio-aflnet` and `outdir/out-kamailio-aflnet-000`).

Then it will start the target's specific `cov_script` inside a container where
it also copies the reproducible inputs, crashes and hangs. The `-s` flag
selects after how many test cases the script should invoke gcovr/lcov and dump
coverage progress into the CSV (i.e. determines temporal resolution of plots).

This script produces an archive `coverage.tar.gz` with the coverage CSV and
HTML report which is copied out of the container into, e.g.
`outdir/out-kamailio-aflnet-000/coverage.tar.gz`.

In the case of Nyx-Net, the following example command will start the
`cov_script_nyx` of the specific target, similarly to AFL-based fuzzers:

```bash
export NYX_NET_REPLAYER=/path/to/nyx-net/packer/packer/nyx_net_payload_executor.py
nyx-eval/coverage.sh -r 10 -t kamailio -d outdir -f nyx -p balanced -s 5
```

The additional environment variable `NYX_NET_REPLAYER` can be used to point to
the replayer script. Determining the path of the trials is done in the same way
as the `start.sh` and `reproducible.sh` scripts. The `-p` flag is only used to
determine the paths.

As for AFL-based fuzzers, the output (CSV and HTML) will be in the trials
folders, in an archive named `coverage.tar.gz`.

Because this scripts interacts with Docker, there's an internal variable
(`DSUDO`) that you can set to empty to avoid using sudo if your setup does not
require root.

### Collecting coverage from trials into one CSV

The script `nyx-eval/convert_coverage.sh` can be used to aggregate the coverage
CSV from different runs and fuzzers into a single CSV (which can later be used
for analysis and plotting).
