#!/bin/bash

folder=$1   #fuzzer result folder
pno=$2      #port number
step=$3     #step to skip running gcovr and outputting data to covfile
            #e.g., step=5 means we run gcovr after every 5 test cases
covoutdir=$4

covfile="$covoutdir/coverage.csv"

$WORKDIR/compile_exim_gcov.sh

#delete the existing coverage file
rm "$covfile" > /dev/null 2>&1; touch "$covfile"

replayer="$WORKDIR/nyx_replay_fast.py"
cd "$WORKDIR/exim-gcov" || exit 1

#clear gcov data
gcovr -r . -s -d > /dev/null 2>&1
# lcov -z -d . > /dev/null 2>&1
# COV_INFO="$WORKDIR/coverage.info"
# rm -rf "$COV_INFO"

#output the header of the coverage file which is in the CSV format
#Time: timestamp, l_per/b_per and l_abs/b_abs: line/branch coverage in percentage and absolutate number
echo "Time,l_per,l_abs,b_per,b_abs" >> "$covfile"

pkill -9 exim
#start exim daemon
# TODO: kill exim!
exim -bd -oX "$pno"

function dump_coverage {
    local time=$1
    local cov_data l_per l_abs b_per b_abs
    set -e
    cov_data=$(gcovr -r . -s | grep "[lb][a-z]*:")
    l_per=$(echo "$cov_data" | grep lines | cut -d" " -f2 | rev | cut -c2- | rev)
    l_abs=$(echo "$cov_data" | grep lines | cut -d" " -f3 | cut -c2-)
    b_per=$(echo "$cov_data" | grep branch | cut -d" " -f2 | rev | cut -c2- | rev)
    b_abs=$(echo "$cov_data" | grep branch | cut -d" " -f3 | cut -c2-)
    # lcov -c -d . -o "$COV_INFO" > /dev/null
    # cov_data=$(lcov --summary "$COV_INFO" | grep -E '^\s*(branches|lines)\.*:')
    # l_per=$(echo "$cov_data" | grep lines | sed -e 's,^[[:space:]]*,,g' | cut -d' ' -f2 | tr -d '%')
    # b_per=$(echo "$cov_data" | grep branches | sed -e 's,^[[:space:]]*,,g' | cut -d' ' -f2 | tr -d '%')
    # l_abs=$(echo "$cov_data" | grep lines | sed -e 's,^[[:space:]]*,,g' | cut -d' ' -f3 | tr -d '(')
    # b_abs=$(echo "$cov_data" | grep branches | sed -e 's,^[[:space:]]*,,g' | cut -d' ' -f3 | tr -d '(')
    echo "=== $b_abs"
    echo "$time,$l_per,$l_abs,$b_per,$b_abs" >> "$covfile"
    set +e
}

count=0
# shellcheck disable=SC2045
#for f in $(ls -tr "$folder/"*.py); do
for f in $(ls -tr /home/ubuntu/experiments/corpus/*/*.py); do
    time=$(stat -c %Y "$f")
    echo "[*] $time : $f"
    sh /home/ubuntu/experiments/clean.sh
    python /home/ubuntu/experiments/nyx2aflnet.py $f /tmp/aflnet.raw

    #du -b /tmp/aflnet.raw


    /home/ubuntu/aflnet/aflnet-replay /tmp/aflnet.raw SMTP $pno 100 > /dev/null 2>&1

    #python "$replayer" "$f" tcp "$pno"

    count=$((count + 1))
    rem=$((count % step))
    [ "$rem" != "0" ] && continue
    dump_coverage "$time"
done

#ouput cov data for the last testcase(s) if step > 1
if [ "$step" -gt 1 ]; then
    time=$(stat -c %Y "$f")
    dump_coverage "$time"
fi

echo "[*] Generating HTML report to $covoutdir/cov_html"
gcovr -r . --html --html-details -o index.html
mkdir -p "$covoutdir/cov_html/"
cp ./*.html "$covoutdir/cov_html/"
# genhtml -o "$covoutdir/cov_html" --branch-coverage "$COV_INFO"

echo "[*] Making archive"
cd "$covoutdir" && tar cvzf "$WORKDIR/coverage.tar.gz" ./*

echo "[+] All done for Nyx"

