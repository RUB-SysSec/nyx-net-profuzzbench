#!/bin/bash
#prog=$1        #name of the subject program (e.g., lightftp)
#runs=$2        #total number of runs
#fuzzer=$3     #fuzzer name (e.g., aflnet) -- this name must match the name of the fuzzer folder inside the Docker container
#covfile=$4     #output CSV file
#append=$5      #append mode
##enable this mode when the results of different fuzzers need to be merged

function usage {
    echo "usage: $0 [-ha] -t target -f fuzzer [-r trials] -d outdir -o csvfile"
    echo "  -h prints this help"
    echo "  -a append to existing CSV file given by -o"
    echo "  -t target to operate on (pattern \$outdir/out-\$target-\$fuzzer-\$n)"
    echo "  -f \$fuzzer for pattern above"
    echo "  -d \$outdir for pattern above"
    echo "  -r number of trials, > 0 (pattern 000,001,002...)"
    echo "  -o CSV file to dump coverage from trials into"
    exit 1
}

runs=10
append=0

while getopts ":hat:r:o:d:f:" opt; do
    case ${opt} in
        h)
            usage
            ;;
        a)
            append=1
            ;;
        t)
            target=${OPTARG}
            ;;
        r)
            if ! [[ ( "$OPTARG" =~ [0-9]+ ) && ( "$OPTARG" -gt 0 ) ]]; then
                >&2 echo "-r expects a number > 0"
                exit 1
            fi
            runs=${OPTARG}
            ;;
        o)
            outcsv=${OPTARG}
            ;;
        d)
            if [ ! -d "$OPTARG" ]; then
                >&2 echo "Output dir $OPTARG does not exist"
                exit 1
            fi
            outdir=${OPTARG}
            ;;
        f)
            fuzzer=${OPTARG}
            ;;
        *)
            >&2 usage
            ;;
    esac
done

if [ -z "$target" ] || [ -z "$outdir" ] || [ -z "$outcsv" ] || [ -z "$fuzzer" ]; then
    >&2 echo "Required arguments missing."
    >&2 usage
fi

if [ $append = 1 ]; then
    if [ ! -f "$outcsv" ] || [ ! -w "$outcsv" ]; then
        >&2 echo "Output is not writable or existent (append mode)"
        exit 1
    fi
else
    if ! truncate -s 0 "$outcsv"; then
        >&2 echo "Could not truncate '$outcsv'"
        exit 1
    fi
    # Init file with header
    echo "time,subject,fuzzer,run,cov_type,cov" >> "$outcsv"
fi

#remove space(s) 
#it requires that there is no space in the middle
strim() {
    trimmedStr=$1
    echo "${trimmedStr##*( )}"
}

#original format: time,l_per,l_abs,b_per,b_abs
#converted format: time,subject,fuzzer,run,cov_type,cov
convert() {
    local run_index=$1 ifile=$2 line
    tail -n +2 "$ifile" | while read -r line; do
        time=$(strim "$(echo "$line" | cut -d',' -f1)")
        l_per=$(strim "$(echo "$line" | cut -d',' -f2)")
        l_abs=$(strim "$(echo "$line" | cut -d',' -f3)")
        b_per=$(strim "$(echo "$line" | cut -d',' -f4)")
        b_abs=$(strim "$(echo "$line" | cut -d',' -f5)")
        {
            echo "$time,$target,$fuzzer,$run_index,l_per,$l_per"
            echo "$time,$target,$fuzzer,$run_index,l_abs,$l_abs"
            echo "$time,$target,$fuzzer,$run_index,b_per,$b_per"
            echo "$time,$target,$fuzzer,$run_index,b_abs,$b_abs"
        } >> "$outcsv"
    done
}


#extract tar files & process the data
for i in $(seq 0 $((runs - 1))); do
    trial_outdir="$outdir/out-$target-$fuzzer"
    trial_outdir_idx=$(printf '%s-%03d' "$trial_outdir" "$i")
    echo "Processing $trial_outdir_idx ..."
    [ -e "$trial_outdir_idx" ] && rm -r "$trial_outdir_idx"
    if ! tar -xf "$trial_outdir_idx.tar.gz" -C "$outdir"; then
        >&2 echo "Failed to extract $trial_outdir_idx.tar.gz"
        exit 1
    fi
    mv "$trial_outdir" "$trial_outdir_idx"
    convert $((i + 1)) "$trial_outdir_idx/cov_over_time.csv"
done
