#!/usr/bin/env bash

FUZZER=$1
CORPUS=$2
TRIALS=$3
PORT=$4

cd "$WORKDIR" || exit 1

case ${FUZZER} in
    nyx*)
        replayer="$WORKDIR/nyx_replay.py"
        ;;
    aflnet*)
        replayer=aflnet-replay
        ;;
    *)
        replayer=afl-replay
        ;;
esac

asan_code=42
export ASAN_OPTIONS="exitcode=$asan_code:allocator_may_return_null=1"

output_file="$CORPUS/crashes_stats.csv"
echo "run,crashes,inputs" > "$output_file"

for idx in $(seq 0 $((TRIALS - 1))); do
    crashes_dir=$(printf '%s/crashes-%03d' "$CORPUS" "$idx")
    reproducible_dir=$(printf '%s/reproducible-%03d' "$CORPUS" "$idx")
    if [ "$FUZZER" = "nyx" ]; then
        crash_inputs=("$crashes_dir/"*.py)
    else
        crash_inputs=("$crashes_dir/id"*)
    fi
    count_crashes=0
    total_inputs=0
    for crash_input in "${crash_inputs[@]}"; do
        [ -f "$crash_input" ] || continue
        total_inputs=$((total_inputs + 1))
        echo "[+] $total_inputs/${#crash_inputs[@]} : $crash_input"

        if [ "$FUZZER" = "nyx" ]; then
            # need to use the input in reproducible
            rep_input=${crash_input/$crashes_dir/$reproducible_dir}
            if [ ! -f "$rep_input" ]; then
                echo "Could not map $crash_input to $rep_input"
                continue
            fi
            python $replayer "$rep_input" udp "$PORT" > /dev/null 2>&1 &
        else
            $replayer "$crash_input" SIP "$PORT" 1 > /dev/null 2>&1 &
        fi

        ./run_pjsip > /dev/null 2>&1 &
        timeout -k 1s 3s ./kamailio-asan/src/kamailio \
            -f ./kamailio-basic.cfg -L ./kamailio-asan/src/modules -Y ./kamailio-asan/runtime_dir/ \
            -n 1 -D -E > /dev/null 2>&1

        code=$?
        wait
        if [ $code = 137 ] || [ $code = 124 ]; then
            echo "[-] timed out ($code)"
        elif [ $code -gt 128 ]; then
            count_crashes=$((count_crashes + 1))
            signal=$((code - 128))
            echo "[-] crashed ($code : $(kill -l $signal))"
        elif [ $code = $asan_code ]; then
            count_crashes=$((count_crashes + 1))
            echo "[-] crashed ($code : asan)"
        else
            echo "[-] normal ($code)"
        fi
    done
    echo "$idx,$count_crashes,$total_inputs" >> "$output_file"
done
