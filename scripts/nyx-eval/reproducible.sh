#!/usr/bin/env bash

export RUST_BACKTRACE=1

HEREDIR=$(readlink -f "$(dirname "$0")")
# shellcheck source=common.bash
source "$HEREDIR/common.bash"

function usage {
    echo "usage: $0 [-hnDS] (-r trials | -c core [-i index]) [-p snap-placement] -d outdir -t target"
    usage_flag r
    usage_flag c
    usage_flag i
    usage_flag t
    usage_flag d
    echo "  -p snapshot placement strategy; only used for computing the path here"
    echo "  -S run without seeds"
    exit 1
}

[ "$#" = 0 ] && usage

while getopts ":hr:c:i:t:nDd:p:S" opt; do
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

info "Compiling reproducer"
if [ $dryrun = 0 ]; then
    cd_and_cargo "$NYX_NET_FUZZER_DEBUG_DIR"
fi

starttime=$(date +%s)
for i in $(seq 0 $((runs - 1))); do
    if [ -z "$single_core" ]; then
        core=${free[$i]}
        trial_outdir=$(get_outdir "$i" "nyx")
    else
        core=$single_core
        trial_outdir=$(get_outdir "$single_index" "nyx")
    fi
    info "Starting run $trial_outdir on core $core"
    if [ $dryrun = 0 ]; then
    cargo run --release -- \
        -s "$targetdir" \
        -c "$core" \
        -q \
        -d "$trial_outdir/corpus" \
        -t "$trial_outdir/reproducible" > "$trial_outdir/reproducible.log" 2>&1 &
    else
    echo \
        cargo run --release -- \
            -s "$targetdir" \
            -c "$core" \
            -q \
            -d "$trial_outdir/corpus" \
            -t "$trial_outdir/reproducible" &
    fi
    pids[$!]=
done

wait_all_children

endtime=$(date +%s)
info "All done in $((endtime - starttime)) seconds"
info "Start: $starttime"
info "End:   $endtime"
