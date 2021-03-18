#!/usr/bin/env bash

HEREDIR=$(readlink -f "$(dirname "$0")")
# shellcheck source=common.bash
source "$HEREDIR/common.bash"

function usage {
    echo "usage: $0 [-hea] [-r trials] -f fuzzer [-p snap-placement] -d outdir -t target -o csvfile"
    echo "    -e : extract archives (for aflnet, aflnwe)"
    echo "    -a : append to existing CSV"
    echo ""
    echo "  Stats are searched in:"
    echo "    - aflnet: \$outdir/\$target/out-\$target-\$fuzzer-x"
    echo "    - nyx   : \$outdir/out-\$target-\$snap_placement-xxx"
    exit 1
}

extract=0
append=0
while getopts ":hr:t:f:d:o:eap:" opt; do
    case ${opt} in
        h)
            usage
            ;;
        r)
            validate_posnum "$OPTARG" "$opt"
            runs=${OPTARG}
            ;;
        t)
            target=${OPTARG}
            ;;
        d)
            validate_outdir
            ;;
        f)
            fuzzer_name=${OPTARG}
            ;;
        o)
            outcsv=${OPTARG}
            ;;
        e)
            extract=1
            ;;
        a)
            append=1
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

if [ -z "$target" ] || [ -z "$outdir" ] || [ -z "$fuzzer_name" ] || [ -z "$outcsv" ]; then
    >&2 error "Required arguments missing."
    >&2 usage
fi

fuzzer="$fuzzer_name"
if [[ "$fuzzer_name" =~ ^nyx ]]; then
    fuzzer="nyx"
fi

if [ $append = 1 ]; then
    if [ ! -f "$outcsv" ] || [ ! -w "$outcsv" ]; then
        >&2 error "Output is not writable or existent (append mode)"
        exit 1
    fi
else
    if ! truncate -s 0 "$outcsv"; then
        >&2 error "Could not truncate '$outcsv'"
        exit 1
    fi
    # Init file with header
    echo "subject,fuzzer,run,execs" >> "$outcsv"
fi

# echo -e "runs : $runs\ntarget : $target\noutdir : $outdir\nfuzzer : $fuzzer"

fuzzer_tag="$fuzzer_name"
if [ "$snap_placement" != "none" ]; then
    fuzzer_tag="$fuzzer_name-$snap_placement"
fi

for run_i in $(seq 0 $((runs - 1))); do
    trial_outdir=$(get_outdir "$run_i" "$fuzzer")
    info "Trial $trial_outdir"
    if [[ "$fuzzer" =~ ^afl ]]; then
        if [ $extract = 1 ] || [ ! -d "$trial_outdir" ]; then
            if [ -d "$trial_outdir" ]; then
                info "Removing old dir $trial_outdir"
                rm -rf "$trial_outdir"
            fi
            trial_archive="$trial_outdir.tar.gz"
            info "Extracting $trial_archive"
            if ! tmpdir=$(mktemp -d); then
                >&2 warn "Failed to create temporary directory"
                continue
            fi
            if tar -xf "$trial_archive" -C "$tmpdir"; then
                if ! (mv "$tmpdir/out-$target-$fuzzer" "$trial_outdir" && rm -r "$tmpdir"); then
                    >&2 warn "Failed to move from $tmpdir to $trial_outdir"
                    continue
                fi
            else
                >&2 warn "Could not extract archive, skipping"
                continue
            fi
        fi
        if [[ "$fuzzer" =~ ^aflpp ]]; then
            execs=$(awk '/execs_per_sec/ {print $3}' "$trial_outdir/default/fuzzer_stats")
        else
            execs=$(awk '/execs_per_sec/ {print $3}' "$trial_outdir/fuzzer_stats")
        fi
    else
        execs=$(python /home/kafl/nyx_show_performance.py "$trial_outdir/thread_stats_0.msgp" \
            | awk '/overall_execs_per_sec:/ {print $2}')
    fi
    if [ -z "$execs" ]; then
        >&2 warn "Could not find execs in $trial_outdir"
        continue
    fi
    info "execs_per_sec : $execs"
    echo "$target,$fuzzer_tag,$run_i,$execs" >> "$outcsv"
done
