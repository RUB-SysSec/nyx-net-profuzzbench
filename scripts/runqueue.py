#!/usr/bin/env python3

import argparse
import json
import os
import signal
import subprocess
import sys
import threading
from datetime import timedelta
from enum import Enum, auto
from pathlib import Path
from queue import Queue
from time import time
from typing import Dict, Iterable, List, Sequence, Union

SCRIPTS_PATH = None


def die(s: str, code: int = 1):
    print(s, file=os.stderr)
    sys.exit(code)


class StrEnum(Enum):
    def __str__(self):
        return self.name.lower()

    @classmethod
    def fromstr(cls, s: str):
        return cls[s.upper()]


class FuzzerType(StrEnum):
    """ The supported fuzzers. """
    NYX = auto()
    AFLNET = auto()
    AFLNWE = auto()
    AFLPP = auto()


class SnapshotPlacement(StrEnum):
    """ Snapshot placement strategy for Nyx """
    NONE = auto()
    BALANCED = auto()
    AGGRESSIVE = auto()


class Target:
    """ A target server to fuzz (a subject in PFB lingo). """
    def __init__(self, name: str):
        self.name = name

    def __str__(self):
        return self.name


class Fuzzer:
    def __init__(self,
                 typ: Union[FuzzerType, str],
                 no_state: bool = False,
                 no_seeds: bool = False,
                 snap_placement: SnapshotPlacement = SnapshotPlacement.NONE):
        self.type = typ if type(typ) == FuzzerType else FuzzerType.fromstr(typ)
        self.no_seeds = no_seeds
        # This sets AFLNet to not use state-awareness (-E flag)
        self.no_state = no_state
        # Incremental snapshots strategy for Nyx
        self.snap_placement = snap_placement

        if self.type == FuzzerType.AFLNET:
            if self.no_state:
                # yapf: disable
                self.__opts = {  # noqa: E122
                "forked-daapd": "-P HTTP -D 2000000 -m 1000 -t 50000+ -K",
                "dcmtk":        "-P DICOM -D 10000 -K",
                "dnsmasq":      "-P DNS -D 10000 -K",
                "tinydtls":     "-P DTLS12 -D 10000 -K -W 30",
                "bftpd":        "-t 1000+ -m none -P FTP -D 10000 -K -c clean",
                "lightftp":     "-P FTP -D 10000 -K -c ./ftpclean.sh",
                "proftpd":      "-t 1000+ -m none -P FTP -D 10000 -K -c clean",
                "pure-ftpd":    "-t 1000+ -m none -P FTP -D 10000 -K -c clean",
                "live555":      "-P RTSP -D 10000 -K -R",
                "kamailio":     "-m 200 -t 3000+ -P SIP -l 5061 -D 50000 -K -c run_pjsip",  # noqa: E501
                "exim":         "-P SMTP -D 10000 -K -W 100",
                "openssh":      "-P SSH -D 10000 -K -W 10",
                "openssl":      "-P TLS -D 10000 -K -R -W 100"}
                # yapf: enable
            else:
                SA = "-q 3 -s 3 -E"  # default state-awareness parameters
                # yapf: disable
                self.__opts = {  # noqa: E122
                "forked-daapd": f"-P HTTP -D 2000000 -m 1000 -t 50000+ {SA} -K",  # noqa: E501
                "dcmtk":         "-P DICOM -D 10000 -E -K",
                # dnsmasq does not run with -E by default?
                "dnsmasq":       "-P DNS -D 10000 -K",
                "tinydtls":     f"-P DTLS12 -D 10000 {SA} -K -W 30",
                "bftpd":        f"-t 1000+ -m none -P FTP -D 10000 {SA} -K -c clean",  # noqa: E501
                "lightftp":     f"-P FTP -D 10000 {SA} -K -c ./ftpclean.sh",  # noqa: E501
                "proftpd":      f"-t 1000+ -m none -P FTP -D 10000 {SA} -K -c clean",  # noqa: E501
                "pure-ftpd":    f"-t 1000+ -m none -P FTP -D 10000 {SA} -K -c clean",  # noqa: E501
                "live555":      f"-P RTSP -D 10000 {SA} -K -R",
                "kamailio":     f"-m 200 -t 3000+ -P SIP -l 5061 -D 50000 {SA} -K -c run_pjsip",  # noqa: E501
                "exim":         f"-P SMTP -D 10000 {SA} -K -W 100",
                "openssh":      f"-P SSH -D 10000 {SA} -K -W 10",
                "openssl":      f"-P TLS -D 10000 {SA} -K -R -W 100"}
                # yapf: enable
        elif self.type == FuzzerType.AFLNWE:
            # yapf: disable
            self.__opts = {  # noqa: E122
            "forked-daapd": "-D 2000000 -m 1000 -t 50000+ -K",
            "dcmtk":        "-D 10000 -K",
            "dnsmasq":      "-D 10000 -K",
            "tinydtls":     "-D 10000 -K -W 30",
            "bftpd":        "-t 1000+ -m none -D 10000 -K -c clean",
            "lightftp":     "-D 10000 -K -c ./ftpclean.sh",
            "proftpd":      "-t 1000+ -m none -D 10000 -K -c clean",
            "pure-ftpd":    "-t 1000+ -m none -D 10000 -K -c clean",
            "live555":      "-D 10000 -K",
            "kamailio":     "-m 200 -t 3000+ -D 50000 -K -c run_pjsip",
            "exim":         "-D 10000 -K -W 100",
            "openssh":      "-D 10000 -K -W 10",
            "openssl":      "-D 10000 -K -W 100"}
            # yapf: enable
        elif self.type == FuzzerType.AFLPP:
            # yapf: disable
            self.__opts = {  # noqa: E122
            "forked-daapd": "-m 1000 -t 50000+",
            "dcmtk":        "",
            "dnsmasq":      "",
            "tinydtls":     "",
            "bftpd":        "-t 1000+ -m none",
            "lightftp":     "",
            "proftpd":      "-t 1000+ -m none",
            "pure-ftpd":    "-t 1000+ -m none",
            "live555":      "",
            "kamailio":     "-m 200 -t 3000+",
            "exim":         "",
            "openssh":      "",
            "openssl":      ""}
            # yapf: enable
        else:
            self.__opts = {}

    def __str__(self):
        s = str(self.type)
        if self.no_state:
            s += "-no-state"
        if self.snap_placement != SnapshotPlacement.NONE:
            s += "-" + str(self.snap_placement)
        if self.no_seeds:
            s += "-no-seeds"
        return s

    def as_str_scripts(self) -> str:
        """String representation of this fuzzer for -f in scripts"""
        s = str(self.type)
        if self.no_state:
            s += "-no-state"
        if self.no_seeds:
            s += "-no-seeds"
        return s

    def getopts(self, target: Target) -> str:
        return self.__opts[target.name]


class Task:
    def __init__(self,
                 fuzzer: Fuzzer,
                 target: Target,
                 outdir: Path,
                 timeout: int,
                 trial_idx: int = 0,
                 covskip: int = 5,
                 only_cov: bool = False):
        self.fuzzer = fuzzer
        self.target = target
        self.outdir = outdir
        self.timeout = timeout
        self.trial_idx = trial_idx
        self.covskip = covskip
        self.only_cov = only_cov

        # Running subprocesses
        self.__procs: Sequence[subprocess.Popen] = []
        self._terminating = False

    def __str__(self):
        return f"{self.fuzzer}:{self.target}:{self.trial_idx}"

    def _cmds(self, core: int) -> List[List[str]]:
        cmds = []
        if self.fuzzer.type in (FuzzerType.AFLNET, FuzzerType.AFLNWE,
                                FuzzerType.AFLPP):
            opts = self.fuzzer.getopts(self.target)
            # yapf: disable
            if self.only_cov:
                cmds.append([
                    f"{SCRIPTS_PATH}/nyx-eval/coverage.sh",
                    "-c", str(core), "-i", str(self.trial_idx),
                    "-t", self.target.name, "-d", self.outdir,
                    "-s", str(self.covskip),
                    "-f", self.fuzzer.as_str_scripts()])
            else:
                cmds.append([
                    f"{SCRIPTS_PATH}/execution/profuzzbench_exec_common.sh",
                    "-c", str(core), "-i", str(self.trial_idx),
                    "-t", self.target.name, "-d", self.outdir,
                    "-f", self.fuzzer.as_str_scripts(), "-O", opts,
                    "-T", str(self.timeout * 60), "-S", str(self.covskip)])
            # yapf: enable
        elif self.fuzzer.type == FuzzerType.NYX:
            # yapf: disable
            if not self.only_cov:
                add_noseeds = ["-S"] if self.fuzzer.no_seeds else []
                cmds.append([
                    f"{SCRIPTS_PATH}/nyx-eval/start.sh",
                    "-c", str(core), "-i", str(self.trial_idx),
                    "-p", str(self.fuzzer.snap_placement),
                    "-t", self.target.name, "-d", self.outdir,
                    "-T", str(self.timeout * 60)] + add_noseeds)
                cmds.append([
                    f"{SCRIPTS_PATH}/nyx-eval/reproducible.sh",
                    "-c", str(core), "-i", str(self.trial_idx),
                    "-p", str(self.fuzzer.snap_placement),
                    "-t", self.target.name, "-d", self.outdir] + add_noseeds)
            cmds.append([
                f"{SCRIPTS_PATH}/nyx-eval/coverage.sh",
                "-c", str(core), "-i", str(self.trial_idx),
                "-p", str(self.fuzzer.snap_placement),
                "-t", self.target.name, "-d", self.outdir,
                "-s", str(self.covskip), "-f", "nyx"])
            # yapf: enable
        else:
            assert False, f"Unhandled fuzzer type {self.fuzzer.type}"
        return cmds

    def run(self, core: int):
        log_path = self.outdir.absolute().joinpath(
            f"out-{self.target}-{self.fuzzer}-{self.trial_idx:03d}-task.log")
        print(f"{self}: logging to {log_path}")
        self.log_file = log_path.open("w")
        for cmd in self._cmds(core):
            print(f"{self}: running {cmd}")
            p = subprocess.Popen(cmd,
                                 stdout=self.log_file,
                                 stderr=subprocess.STDOUT,
                                 preexec_fn=os.setsid)
            self.__procs.append(p)
            p.communicate()
            if self._terminating:
                break
            if p.returncode != 0:
                print(f"FATAL-{self}: {cmd[0]} returned status {p.returncode}")
                break

    def kill(self):
        self._terminating = True
        for p in self.__procs:
            try:
                p.send_signal(signal.SIGINT)
                gid = os.getpgid(p.pid)
                os.killpg(gid, signal.SIGINT)
                # os.killpg(gid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def parse_config(d: Dict) -> Iterable[Task]:
    trials = d["trials"]
    timeout = d["timeout"]
    only_cov = d.get("only_cov", False)

    def check_dir(p: Path, s: str):
        if not p.exists() or not p.is_dir():
            raise ValueError(f"{s} directory '{p}' "
                             "does not exists or is not a directory")

    nyx_outdir = Path(d["nyx_outdir"])
    check_dir(nyx_outdir, "nyx_outdir")
    afl_outdir = Path(d["afl_outdir"])
    check_dir(afl_outdir, "afl_outdir")

    targets = [Target(t) for t in d["targets"]]
    for f in d["fuzzers"]:
        outdir = None
        if type(f) == str:
            fuzzer = Fuzzer(f)
        elif type(f) == dict:
            outdir = f.get("path", None)
            fuzzer = Fuzzer(f["type"],
                            no_state=f.get("no_state", False),
                            no_seeds=f.get("no_seeds", False),
                            snap_placement=SnapshotPlacement.fromstr(
                                f.get("snaps", "none")))
        else:
            raise ValueError(f"Unrecognized value type for fuzzer: {f}")
        if outdir is None:
            outdir = nyx_outdir if fuzzer.type == FuzzerType.NYX else \
                     afl_outdir
        else:
            outdir = Path(outdir)
        for t in targets:
            for i in range(trials):
                yield Task(fuzzer,
                           t,
                           outdir,
                           timeout,
                           trial_idx=i,
                           only_cov=only_cov)


class Worker(threading.Thread):
    def __init__(self, q: Queue, core: int):
        super().__init__()
        self._q = q
        self.core = core
        self._terminating = False
        self._current_task = None

    def run(self):
        while not self._terminating:
            self._current_task = self._q.get()
            if self._current_task is None:
                break

            start = time()
            task_str = str(self._current_task)
            print(f"Work-{self.core}: Starting task {task_str}")
            self._current_task.run(self.core)

            end = time()
            self._current_task = None

            delta = timedelta(seconds=end - start)
            print(f"Work-{self.core}: {task_str} done in {delta}")
            self._q.task_done()

    def kill(self):
        self._terminating = True
        if self._current_task is not None:
            self._current_task.kill()


def run_queue(q: Queue, par: int):
    workers = []
    for i in range(par):
        w = Worker(q, i)
        w.start()
        workers.append(w)

    try:
        q.join()
        # Gracefully terminate workers
        for _ in range(par):
            q.put(None)
    except KeyboardInterrupt:
        print("Received keyboard interrupt, killing workers...")
        for w in workers:
            w.kill()
            q.put(None)

    for w in workers:
        w.join()
    print("All done!")


def main():
    parser = argparse.ArgumentParser(description="Run experiments in a queue")
    parser.add_argument("-j",
                        "--par",
                        help=("How many experiments (fuzzer+target trials) "
                              "to run in parallel"),
                        type=int,
                        default=52)
    parser.add_argument("config",
                        help="Config files",
                        type=Path,
                        metavar="config.json")

    args = parser.parse_args()

    global SCRIPTS_PATH
    SCRIPTS_PATH = os.path.abspath(os.path.dirname(sys.argv[0]))

    q = Queue()
    with args.config.open() as f:
        d = json.load(f)
    if type(d) != dict:
        die(f"Expected top level dict, got '{type(d)}'")
    for t in parse_config(d):
        q.put(t)

    run_queue(q, args.par)


if __name__ == "__main__":
    main()
