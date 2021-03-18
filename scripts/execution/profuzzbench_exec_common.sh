#!/bin/bash

ROOTDIR=$(readlink -f "$(dirname "$0")/../..")

# DOCIMAGE=$1   #name of the docker image
# RUNS=$2       #number of runs
# SAVETO=$3     #path to folder keeping the results

# FUZZER=$4     #fuzzer name (e.g., aflnet) -- this name must match the name of the fuzzer folder inside the Docker container
# OUTDIR=$5     #name of the output folder created inside the docker container
# OPTIONS=$6    #all configured options for fuzzing
# TIMEOUT=$7    #time for fuzzing
# SKIPCOUNT=$8  #used for calculating coverage over time. e.g., SKIPCOUNT=5 means we run gcovr after every 5 test cases

# Run Docker through sudo
DSUDO=sudo

# 1h in seconds
TIMEOUT=$((60 * 60))
SKIPCOUNT=1
SINGLE_INDEX=0
NO_SEEDS=0

function usage {
    echo -n "usage: $0 [-h] (-c core -i index | -r trials) -t target -d outdir -f fuzzer "
    echo "-O fuzz-opts [-T time] [-S gcov-skip]"
    echo "  -c do a single run on the given core"
    echo "  -i index of the single run to do (i.e. determines the name of the output archive)"
    echo "  -r number of trials / runs"
    echo "  -t target to run"
    echo "  -d directory where to place the output archive (it'll be \$outdir/out-\$target-\$fuzzer-\$n.tar.gz)"
    echo "  -f one of aflnet, aflnet-no-state or aflnwe"
    echo "  -O additional options to pass to the fuzzer (quote as a single string)"
    echo "  -T time to run each trial"
    echo "  -S skip count to \"sample\" while computing coverage"
    exit 1
}

function assert_posnum_z {
    if ! [[ ( "$1" =~ [0-9]+ ) && ( "$1" -ge 0 ) ]]; then
        echo "-$2 needs a number greater or equal zero"
        exit 1
    fi
}

function assert_posnum {
    if ! [[ ( "$1" =~ [0-9]+ ) && ( "$1" -gt 0 ) ]]; then
        echo "-$2 needs a number greater than zero"
        exit 1
    fi
}

while getopts ":hc:i:r:t:d:f:O:T:S:" opt; do
    case ${opt} in
        h)
            usage
            ;;
        c)
            assert_posnum_z "$OPTARG" "$opt"
            CORE=${OPTARG}
            ;;
        i)
            assert_posnum_z "$OPTARG" "$opt"
            SINGLE_INDEX=${OPTARG}
            ;;
        r)
            assert_posnum "$OPTARG" "$opt"
            RUNS=${OPTARG}
            ;;
        t)
            TARGET=${OPTARG}
            ;;
        d)
            SAVETO=${OPTARG}
            ;;
        f)
            FUZZER=${OPTARG}
            ;;
        O)
            OPTIONS=${OPTARG}
            ;;
        T)
            assert_posnum "$OPTARG" "$opt"
            TIMEOUT=${OPTARG}
            ;;
        S)
            assert_posnum "$OPTARG" "$opt"
            SKIPCOUNT=${OPTARG}
            ;;
        *)
            >&2 usage
            ;;
    esac
done

if [ -z "$TARGET" ] || [ -z "$SAVETO" ] || [ -z "$FUZZER" ]; then
    echo "Required parameters are missing"
    usage
fi

if [ -z "$CORE" ] && [ -z "$RUNS" ]; then
    echo "Parameters -r or -c are required"
    usage
elif [ -n "$CORE" ] && [ -n "$RUNS" ]; then
    echo "Parameters -c and -r are mutually exclusive"
    usage
fi

DOCIMAGE="pfb-$TARGET"
OUTDIR="out-$TARGET-$FUZZER"
FUZZER_TAG=$FUZZER
if [[ "$FUZZER" =~ "no-seeds" ]]; then
    FUZZER="${FUZZER/-no-seeds/}"
    NO_SEEDS=1
fi
if [ "$FUZZER" = "aflnet-no-state" ]; then
    FUZZER=aflnet
fi

if [ -z "$CORE" ]; then
    # Set the available cores: 0-51
    mapfile -t cores < <(seq 0 51)

    # Find free cores
    FREECORESBIN="$ROOTDIR/freecores/target/release/freecores"
    if [ ! -x "$FREECORESBIN" ]; then
        echo "Compiling freecores utility"
        if ! (cd "$ROOTDIR/freecores" && cargo build --release > /dev/null 2>&1); then
            >&2 echo "FATAL: could not compile freecores"
            exit 1
        fi
    fi
    mapfile -t free < <($FREECORESBIN -j10 -n "${cores[@]}" 2> /dev/null)
    if [ "${#free[@]}" -lt "$RUNS" ]; then
        >&2 echo "FATAL: not enought free cores (${#free[@]})"
        exit 1
    fi
else
    RUNS=1
fi

#keep all container ids
cids=()

function on_sigint {
    if [ "${#cids[@]}" -gt 0 ]; then
        echo "Killing containers"
        $DSUDO docker kill "${cids[@]}"
        echo "Waiting for containers to quit"
        $DSUDO docker wait "${cids[@]}"
    fi
    echo "Killed by user"
    exit 1
}

trap on_sigint SIGINT

#create one container for each run
for i in $(seq 0 $((RUNS - 1))); do
    if [ -z "$CORE" ]; then
        core=${free[$i]}
    else
        core=$CORE
        i=$SINGLE_INDEX
    fi
    cmd="cd ${WORKDIR} && run ${FUZZER} ${OUTDIR} '${OPTIONS}' ${TIMEOUT} ${SKIPCOUNT} ${NO_SEEDS}"
    id=$($DSUDO docker run --cpus=1 --cpuset-cpus="$core" -d -it \
        --name="$(date '+%Y%m%d%H%M')-$TARGET-$FUZZER_TAG-$i" \
        "$DOCIMAGE" /bin/bash -c "$cmd")
    cids+=("${id::12}") #store only the first 12 characters of a container ID
done

#wait until all these dockers are stopped
echo "${FUZZER^^}: Fuzzing in progress ..."
echo "${FUZZER^^}: Waiting for the following containers to stop:" "${cids[@]}"
$DSUDO docker wait "${cids[@]}" > /dev/null

#collect the fuzzing results from the containers
echo -en "\n${FUZZER^^}: Collecting results and save them to ${SAVETO}"
if [ -z "$SINGLE_INDEX" ]; then
    index=0
else
    index=$SINGLE_INDEX
fi
for id in "${cids[@]}"; do
    echo "${FUZZER^^}: Collecting results from container ${id}"
    index_str=$(printf "%03d" "$index")
    $DSUDO docker cp "${id}:/home/ubuntu/experiments/${OUTDIR}.tar.gz" \
        "${SAVETO}/${OUTDIR}-${index_str}.tar.gz" > /dev/null
    index=$((index+1))
done

echo -e "\n${FUZZER^^}: I am done!"
