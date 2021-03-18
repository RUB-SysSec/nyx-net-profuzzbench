#!/usr/bin/env bash

# Timeout in seconds: default 1H
timeout=$((60 * 60))

export RUST_BACKTRACE=1

HEREDIR=$(readlink -f "$(dirname "$0")")
# shellcheck source=common.bash
source "$HEREDIR/common.bash"

function usage {
    echo "usage: $0 [-hnDS] (-r trials | -c core [-i index]) [-T time] [-p snap-placement] -d outdir -t target"
    usage_flag r
    usage_flag c
    usage_flag i
    echo "  -T time to run each trial"
    usage_flag t
    usage_flag d
    echo "  -p snapshot placement strategy (i.e. none, aggressive or balanced)"
    echo "  -S run without seeds"
    echo "Examples:"
    echo "  # Run 10 trials, outputs into /tmp/out-lightftp-{000,001,002,...}"
    echo "  $0 -r 10 -T 3600 -d /tmp -t lightftp"
    echo "  # Run a single trial, pin to core 0, outputs into /tmp/out-lightftp-002"
    echo "  $0 -c 0 -i 2 -T 3600 -d /tmp -t lightftp"
    exit 1
}

[ "$#" = 0 ] && usage

while getopts ":hc:i:r:t:T:nDd:p:S" opt; do
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
        T)
            validate_posnum "$OPTARG" "$opt"
            timeout=${OPTARG}
            ;;
        D)
            dodebug=1
            ;;
        n)
            dryrun=1
            ;;
        d)
            validate_outdir
            ;;
        p)
            validate_snap_placement
            ;;
        S)
            no_seeds=1
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
validate_nyx_spec

if [ -z "$single_core" ]; then
    get_free_cores
else
    runs=1
fi

# Check if destination folders already exist before committing to runs
direxist=0
for i in $(seq 0 $((runs - 1))); do
    if [ -z "$single_core" ]; then
        trial_outdir=$(get_outdir "$i" "nyx")
    else
        trial_outdir=$(get_outdir "$single_index" "nyx")
    fi
    if [ -e "$trial_outdir" ]; then
        >&2 warn "Destination $trial_outdir already exists"
        direxist=1
    fi
done
[ $dryrun = 0 ] && [ $direxist = 1 ] && exit 1

info "Compiling fuzzer"
if [ $dryrun = 0 ]; then
    cd_and_cargo "$NYX_NET_FUZZER_DIR"
fi

# Actually start runs in the background
starttime=$(date +%s)
for i in $(seq 0 $((runs - 1))); do
    if [ -z "$single_core" ]; then
        core=${free[$i]}
        trial_outdir=$(get_outdir "$i" "nyx")
    else
        core=$single_core
        trial_outdir=$(get_outdir "$single_index" "nyx")
    fi
    info "Starting trial $i on core $core, output '$trial_outdir'"
    if [ $dryrun = 0 ]; then
    timeout -k 15 --preserve-status "$timeout" \
        cargo run --release -- \
            -s "$targetdir" \
            -c "$core" \
            -t 1 \
            -w "$trial_outdir" \
            -p "$snap_placement" \
            > "$trial_outdir.log" 2>&1 &
    else
    (echo \
        cargo run --release -- \
            -s "$targetdir" \
            -c "$core" \
            -t 1 \
            -w "$trial_outdir" \
            -p "$snap_placement" \
        && sleep "$timeout"
    )&
    fi
    pids[$!]=
done

# Wait for runs to complete
wait_all_children

endtime=$(date +%s)
info "All done in $((endtime - starttime)) seconds"
info "Start: $starttime"
info "End:   $endtime"
