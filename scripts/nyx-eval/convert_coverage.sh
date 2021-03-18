#!/usr/bin/env bash

# Don't use the default trap in common.bash
NOTRAP=1

HEREDIR=$(readlink -f "$(dirname "$0")")
# shellcheck source=common.bash
source "$HEREDIR/common.bash"

function usage {
    echo "usage: $0 [FLAGS] [-r trials] [-f fuzzer-name] [-p snaps-placement] -d outdir -o output-csv -t target"
    echo "  -h print this help"
    echo "  -a append to existing output"
    echo "  -e extract afl* trial data archives first; overwrites previous separate coverage.sh run"
    exit 1
}

fuzzer_name=nyx
outcsv=
append=0
extract=0
while getopts ":haer:o:t:d:f:p:" opt; do
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
        o)
            outcsv=${OPTARG}
            ;;
        a)
            append=1
            ;;
        e)
            extract=1
            ;;
        f)
            fuzzer_name=${OPTARG}
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

if [ -z "$target" ] || [ -z "$outdir" ] || [ -z "$outcsv" ]; then
    >&2 error "Required arguments missing."
    >&2 usage
fi

if [ -z "$fuzzer_name" ]; then
    >&2 error "Fuzzer parameter is empty"
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
    echo "time,subject,fuzzer,run,cov_type,cov" >> "$outcsv"
fi

# Remove space(s); it requires that there is no space in the middle
strim() {
    trimmedStr=$1
    echo "${trimmedStr##*( )}"
}

#original format: time,l_per,l_abs,b_per,b_abs
#converted format: time,subject,fuzzer,run,cov_type,cov
convert() {
    local run_index=$1 ifile=$2 line
    local fuzzer_tag="$fuzzer_name"
    if [ "$snap_placement" != "none" ]; then
        fuzzer_tag="$fuzzer_name-$snap_placement"
    fi
    tail -n +2 "$ifile" | while read -r line; do
        time=$(strim "$(echo "$line" | cut -d',' -f1)")
        l_per=$(strim "$(echo "$line" | cut -d',' -f2)")
        l_abs=$(strim "$(echo "$line" | cut -d',' -f3)")
        b_per=$(strim "$(echo "$line" | cut -d',' -f4)")
        b_abs=$(strim "$(echo "$line" | cut -d',' -f5)")
        {
            echo "$time,$target,$fuzzer_tag,$run_index,l_per,$l_per"
            echo "$time,$target,$fuzzer_tag,$run_index,l_abs,$l_abs"
            echo "$time,$target,$fuzzer_tag,$run_index,b_per,$b_per"
            echo "$time,$target,$fuzzer_tag,$run_index,b_abs,$b_abs"
        } >> "$outcsv"
    done
}

main() {
    local i trial_outdir trial_archive trial_cov_archive runcsv
    local is_afl=0
    [[ "$fuzzer" =~ ^afl ]] && is_afl=1
    for i in $(seq 0 $((runs - 1))); do
        trial_outdir=$(get_outdir "$i" "$fuzzer")

        if [ $extract = 1 ] && [ $is_afl = 1 ]; then
            trial_archive="$trial_outdir.tar.gz"
            info "Extracting $trial_archive"
            [ -d "$trial_outdir" ] && rm -rf "$trial_outdir"
            if ! tmpdir=$(mktemp -d); then
                >&2 error "Failed to create temporary directory"
                exit 1
            fi
            if tar -xf "$trial_archive" -C "$tmpdir"; then
                set -e
                mv "$tmpdir/out-$target-$fuzzer" "$trial_outdir"
                rm -r "$tmpdir"
                set +e
            else
                >&2 error "Failed to extract trial archive"
                exit 1
            fi
        fi

        trial_cov_archive="$trial_outdir/coverage.tar.gz"
        if [ -e "$trial_cov_archive" ]; then
            info "Extracting coverage archive $trial_cov_archive"
            if ! tar -xf "$trial_cov_archive" -C "$trial_outdir"; then
                >&2 error "Failed to extract coverage archive $trial_cov_archive"
                exit 1
            fi
        fi

        if [ "$is_afl" = 1 ]; then
            runcsv="$trial_outdir/cov_over_time.csv"
        else
            runcsv="$trial_outdir/coverage.csv"
        fi

        info "Converting from $runcsv to $outcsv"
        if [ ! -f "$runcsv" ] || [ ! -r "$runcsv" ]; then
            >&2 warn "CSV not a file or not readable"
            continue
        fi
        convert $((i + 1)) "$runcsv"
    done
}

main
info "All done!"
