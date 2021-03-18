#!/usr/bin/env bash

# Skip count for dumping coverage (i.e. invoking gcovr).
step=5

fuzzer=nyx

# Don't use the default trap in common.bash
NOTRAP=1
# Run docker commands with sudo
DSUDO=sudo

HEREDIR=$(readlink -f "$(dirname "$0")")
# shellcheck source=common.bash
source "$HEREDIR/common.bash"

function usage {
    echo -n "usage: $0 [-hnD] (-r trials | -c core [-i index]) [-s step] "
    echo "-d outdir -t target [-f fuzzer] [-p snap-placement]"
    usage_flag r
    usage_flag c
    usage_flag i
    echo "  -s invoke dumping coverage (e.g. gcovr) every this many inputs"
    usage_flag t
    usage_flag d
    echo "  -f fuzzer that ran; one of nyx, aflnet or aflnwe"
    echo "  -p snapshot placement strategy; only used for path here"
    exit 1
}

[ "$#" = 0 ] && usage

while getopts ":hr:c:i:t:nDs:d:f:p:" opt; do
    case ${opt} in
        h)
            usage
            ;;
        c)
            validate_posnum_z "$OPTARG" "$opt"
            single_core=${OPTARG}
            ;;
        i)
            validate_posnum_z "$OPTARG" "$opt"
            single_index=${OPTARG}
            ;;
        r)
            validate_posnum "$OPTARG" "$opt"
            runs=${OPTARG}
            ;;
        t)
            target=${OPTARG}
            ;;
        D)
            dodebug=1
            ;;
        n)
            dryrun=1
            ;;
        s)
            validate_posnum "$OPTARG" "$opt"
            step=${OPTARG}
            ;;
        d)
            validate_outdir
            ;;
        f)
            fuzzer=${OPTARG}
            if [[ ! "$fuzzer" =~ ^(nyx|aflnet|aflnwe|aflpp) ]]; then
                >&2 error "Invalid fuzzer. Needs one of 'nyx', 'aflpp', 'aflnet' or 'aflnwe'."
                >&2 usage
            fi
            ;;
        p)
            validate_snap_placement
            ;;
        :)
            no_arg_error
            ;;
        ?)
            invalid_arg_error
            ;;
    esac
done

if [ -z "$target" ] || [ -z "$outdir" ]; then
    >&2 error "Required arguments missing."
    >&2 usage
fi

validate_core_or_runs

if [ -z "$single_core" ]; then
    get_free_cores
else
    runs=1
fi

# declare -A prot
# prot['forked-daapd']='daap'
# prot['dcmtk']='dicom'
# prot['dnsmasq']='dns'
# prot['tinydtls']='dtls'
# prot['bftpd']='ftp'
# prot['lightftp']='ftp'
# prot['proftpd']='ftp'
# prot['pure-ftpd']='ftp'
# prot['live555']='rtsp'
# prot['kamailio']='sip'
# prot['exim']='smtp'
# prot['openssh']='ssh'
# prot['openssl']='tls'
# if [ -z "${prot[$target]}" ]; then
#     >&2 error "Protocol not declared for $target"
#     exit 1
# fi

if [ -z "${ports[$target]}" ]; then
    >&2 error "Port not declared for $target"
    exit 1
fi

# Working directory in container
cont_workdir="/home/ubuntu/experiments"

# inputs_dirname: name of directory with reproducible inputs
# afl_replay_fmode: parameter to cov_script (only afl)
case ${fuzzer} in
    nyx*)
        inputs_dirname="reproducible"
	inputs_dirname_old="corpus"
        ;;
    aflnet*)
        inputs_dirname="replayable-queue"
        crashes_dirname="replayable-crashes"
        hangs_dirname="replayable-hangs"
        afl_replay_fmode=1
        ;;
    aflnwe*)
        inputs_dirname="queue"
        crashes_dirname="crashes"
        hangs_dirname="hangs"
        afl_replay_fmode=0
        ;;
    aflpp*)
        inputs_dirname="default/queue"
        crashes_dirname="default/crashes"
        hangs_dirname="default/hangs"
        afl_replay_fmode=0
        ;;
    *)
        >&2 error "Wrong fuzzer '$fuzzer'"
        exit 1
        ;;
esac

# Reproducible folder in container
cont_inputs="$cont_workdir/$inputs_dirname"

cont_inputs_old="$cont_workdir/$inputs_dirname_old"

# Coverage output folder in container
cont_output="$cont_workdir/coverage-out"
# Docker image name
image="pfb-$target"
# Nyx reproducer source
NYX_NET_REPLAY=${NYX_NET_REPLAY:-"$HOME/nyx-net/packer/packer/nyx_net_payload_executor.py"}
cont_replay="$cont_workdir/nyx_replay.py"

# Entry command for containers
if [[ "$fuzzer" =~ "nyx" ]]; then
    read -r -d '' cmd <<- EOF
echo -e '#!/bin/bash\necho ubuntu' > pass.sh && \
chmod +x pass.sh && \
SUDO_ASKPASS=./pass.sh sudo --askpass -- chown -R ubuntu:ubuntu $cont_inputs $cont_inputs_old  $cont_replay && \
mkdir -p $cont_output && \
cov_script_nyx $cont_inputs ${ports[$target]} $step $cont_output
EOF
else
    read -r -d '' cmd <<- EOF
echo -e '#!/bin/bash\necho ubuntu' > pass.sh && \
chmod +x pass.sh && \
SUDO_ASKPASS=./pass.sh sudo --askpass -- chown -R ubuntu:ubuntu $cont_workdir && \
mkdir -p $cont_output && \
cov_script $cont_workdir ${ports[$target]} $step $cont_output/cov_over_time.csv $afl_replay_fmode 1
EOF
fi

# Container IDs
cids=()

function on_sigint {
    if [ $dryrun = 0 ] && [ "${#cids[@]}" -gt 0 ]; then
        info "Killing containers"
        $DSUDO docker kill "${cids[@]}"
        info "Waiting for containers to quit"
        $DSUDO docker wait "${cids[@]}"
    fi
    info "Killed by user"
    exit 1
}

trap on_sigint SIGINT

for i in $(seq 0 $((runs - 1))); do
    if [ -z "$single_core" ]; then
        core=${free[$i]}
    else
        core=$single_core
        i=$single_index
    fi
    trial_outdir=$(get_outdir "$i" "$fuzzer")

    info "Starting to get coverage for $trial_outdir on core $core"
    if [ $dryrun = 0 ]; then
        if [ "$snap_placement" = "none" ]; then
            cont_name="$(date '+%Y%m%d%H%M')-cov-$target-$fuzzer-$i"
        else
            cont_name="$(date '+%Y%m%d%H%M')-cov-$target-$fuzzer-$snap_placement-$i"
        fi
        if ! cid=$($DSUDO docker create -it --cpus=1 --cpuset-cpus="$core" \
            --name="$cont_name" --cap-add=SYS_PTRACE "$image" bash -c "$cmd")
        then
            >&2 error "Could not create container"
            exit 1
        fi
        cid=${cid::12}

        info "Created container $cid"

        if [[ "$fuzzer" =~ "nyx" ]]; then
            if ! $DSUDO docker cp "$NYX_NET_REPLAY" "$cid:$cont_replay"; then
                >&2 error "Failed to copy reproducer script"
                exit 1
            fi
        else
            info "Removing old dirs"
            [ -d "$trial_outdir" ] && rm -rf "$trial_outdir"
            info "Extracting archive for $trial_outdir"
            if ! tmpdir=$(mktemp -d); then
                >&2 error "Failed to create temporary directory"
                exit 1
            fi
            if ! tar -xf "$trial_outdir.tar.gz" -C "$tmpdir"; then
                >&2 error "Failed to extract archive"
                exit 1
            fi
            set -e
            mv "$tmpdir/out-$target-$fuzzer" "$trial_outdir"
            rm -r "$tmpdir"
            set +e
        fi

        if ! $DSUDO docker cp "$trial_outdir/$inputs_dirname" "$cid:$cont_inputs"; then
            >&2 error "Failed to copy reproducible inputs"
            exit 1
        fi

	if ! $DSUDO docker cp "$trial_outdir/$inputs_dirname_old" "$cid:$cont_inputs_old"; then
            >&2 error "Failed to copy reproducible inputs"
            #exit 1
        fi

        if [ -n "$crashes_dirname" ]; then
            if ! $DSUDO docker cp "$trial_outdir/$crashes_dirname" \
                "$cid:$cont_workdir/$crashes_dirname"
            then
                >&2 error "Failed to copy reproducible crashes"
                exit 1
            fi
        fi

        if [ -n "$hangs_dirname" ]; then
            if ! $DSUDO docker cp "$trial_outdir/$hangs_dirname" \
                "$cid:$cont_workdir/$hangs_dirname"
            then
                >&2 error "Failed to copy reproducible hangs"
                exit 1
            fi
        fi

        if ! $DSUDO docker start "$cid"; then
            >&2 error "Failed to start container $cid"
            exit 1
        fi

        info "Started container $cid"
        cids+=("$cid")
    else
        >&2 warn "Be careful of quotes in the 'docker create' command when copying!"
        echo docker create -it --cpus=1 --cpuset-cpus="$core" "$image" bash -c "$cmd"
        echo docker cp "$NYX_NET_REPLAY" "container:$cont_replay"
        echo docker cp "$trial_outdir/reproducible" "container:$cont_inputs"
        echo docker start container
    fi
done

info "Waiting for containers to exit"
if [ $dryrun = 0 ]; then
    info "${cids[*]}"
    $DSUDO docker wait "${cids[@]}"
fi

info "Containers terminated, copying coverage"
if [ $dryrun = 0 ]; then
    for i in $(seq 0 $((runs - 1))); do
        cid=${cids[$i]}
        from="$cid:$cont_workdir/coverage.tar.gz"
        if [ -z "$single_core" ]; then
            dest_prefix=$(get_outdir "$i" "$fuzzer")
        else
            dest_prefix=$(get_outdir "$single_index" "$fuzzer")
        fi
        dest="$dest_prefix/coverage.tar.gz"
        if ! $DSUDO docker cp "$from" "$dest"; then
            >&2 warn "Could not copy from $from to $dest"
            continue
        fi
        info "Coverage for run in $dest"
    done
fi

info "All done!"
