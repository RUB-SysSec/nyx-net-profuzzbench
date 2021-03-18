#!/usr/bin/env bash

BASE_DIR=$1
TARGET=$2
FUZZER_TAG=$3
OUTCSV=$4

DSUDO=sudo

# Memory limit for container (in bytes)
CONT_MEM_LIMIT=$((1 * 1024 * 1024 * 1024))

NOTRAP=1

HEREDIR=$(readlink -f "$(dirname "$0")")
# shellcheck source=common.bash
source "$HEREDIR/common.bash"

function usage {
    echo "usage: $0 base-dir target fuzzer outcsv"
    echo "  fuzzer : can be any of aflnet, aflnet-no-state, nyx, nyx-balanced, etc."
    exit 1
}

[ $# -lt 4 ] && usage

if [ ! -d "$BASE_DIR" ]; then
    >&2 error "$BASE_DIR is not a directory"
    >&2 usage
fi

if [ -z "$TARGET" ] || [ -z "$FUZZER_TAG" ] || [ -z "$OUTCSV" ]; then
    >&2 usage
fi

if [ -e "$OUTCSV" ]; then
    >&2 error "Output $OUTCSV already exists"
    exit 1
fi

fuzzer=afl
crashes_dir="crashes"
case ${FUZZER_TAG} in
    nyx*)
        fuzzer=nyx
        crashes_dir="corpus/crash"
        ;;
    aflnet*)
        fuzzer=aflnet
        crashes_dir="replayable-crashes"
        ;;
    aflpp*)
        crashes_dir="default/crashes"
        ;;
esac

if [ $fuzzer = "nyx" ]; then
    if [ "$FUZZER_TAG" = "nyx" ]; then
        trial_dirs_base="$BASE_DIR/out-$TARGET-00"
    else
        trial_dirs_base="$BASE_DIR/out-$TARGET-${FUZZER_TAG/nyx-/}-00"
    fi
else
    trial_dirs_base="$BASE_DIR/out-$TARGET-$FUZZER_TAG-00"
fi
trial_dirs=("$trial_dirs_base"*/)
if [ "${#trial_dirs[@]}" -eq 0 ] || [ ! -d "${trial_dirs[0]}" ]; then
    >&2 error "No directories for $trial_dirs_base*/"
    exit 1
fi

if [ $fuzzer = "nyx" ]; then
    NYX_REPLAY=${NYX_REPLAY:-/home/kafl/nyx/Target-Components/packer_ng/nyx_net_payload_executor.py}
    if [ ! -f "$NYX_REPLAY" ]; then
        >&2 error "NYX_REPLAY = '$NYX_REPLAY' not found"
        exit 1
    fi
fi

if [ -z "${ports[$TARGET]}" ]; then
    >&2 error "Port not defined for $TARGET"
    exit 1
fi

cont_workdir="/home/ubuntu/experiments"
cont_data_dir="$cont_workdir/fuzzer-crashes"
cont_output_file="$cont_data_dir/crashes_stats.csv"

read -r -d '' cmd <<- EOF
echo -e '#!/bin/bash\necho ubuntu' > pass.sh && \
chmod +x pass.sh && \
SUDO_ASKPASS=./pass.sh sudo --askpass -- chown -R ubuntu:ubuntu $cont_data_dir && \
$cont_workdir/crashes_stats.sh $fuzzer $cont_data_dir 10 ${ports[$TARGET]}
EOF

# create container
image="pfb-$TARGET"
cont_name="$(date '+%Y%m%d%H%M')-crash-$TARGET-$FUZZER_TAG"
if ! cid=$($DSUDO docker create -it --name="$cont_name" \
    --cap-add=SYS_PTRACE --memory=$CONT_MEM_LIMIT "$image" bash -c "$cmd")
then
    >&2 error "Could not create container"
    exit 1
fi
cid=${cid::12}
info "Created container $cid : $cont_name"

idx=0
for dir in "${trial_dirs[@]}"; do
    # copy crashes
    cont_data_crashes_dir=$(printf '%s/crashes-%03d' "$cont_data_dir" "$idx")
    info "Copy $dir/$crashes_dir to $cont_data_crashes_dir"
    if ! $DSUDO docker cp "$dir/$crashes_dir" "$cid:$cont_data_crashes_dir"; then
        >&2 error "Failed copy"
        exit 1
    fi
    if [ $fuzzer = "nyx" ]; then
        # copy reproducible
        cont_data_repro_dir=$(printf '%s/reproducible-%03d' "$cont_data_dir" "$idx")
        info "Copy $dir/reproducible to $cont_data_repro_dir"
        if ! $DSUDO docker cp "$dir/reproducible" "$cid:$cont_data_repro_dir"; then
            >&2 error "Failed copy"
            exit 1
        fi
    fi
    idx=$((idx + 1))
done
# copy reproducer (nyx only)
if [ $fuzzer = "nyx" ]; then
    if ! $DSUDO docker cp "$NYX_REPLAY" "$cid:$cont_workdir/nyx_replay.py"; then
        >&2 error "Failed to copy $NYX_REPLAY"
        exit 1
    fi
fi
# start container
if ! $DSUDO docker start "$cid"; then
    >&2 error "Failed to start container..."
    exit 1
fi

user_int=0
function on_sigint {
    user_int=1
    if [ -n "$cid" ]; then
        $DSUDO docker kill "$cid"
    fi
}
trap on_sigint SIGINT

info "Waiting for container $cont_name to exit..."
if ! $DSUDO docker wait "$cid"; then
    >&2 error "Failed to wait for container..."
    exit 1
fi

if [ $user_int = 1 ]; then
    info "User interrupt"
    exit
fi

info "Container $cont_name terminated"
info "Grabbing output from $cont_output_file"
if ! $DSUDO docker cp "$cid:$cont_output_file" "$OUTCSV"; then
    >&2 error "Failed to copy $cid:$cont_output_file to $OUTCSV"
    exit 1
fi

info "All done!"
