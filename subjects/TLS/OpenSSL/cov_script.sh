#!/bin/bash

folder=$1   #fuzzer result folder
pno=$2      #port number
step=$3     #step to skip running gcovr and outputting data to covfile
            #e.g., step=5 means we run gcovr after every 5 test cases
covfile=$4  #path to coverage file
fmode=$5    #file mode -- structured or not
            #fmode = 0: the test case is a concatenated message sequence -- there is no message boundary
            #fmode = 1: the test case is a structured file keeping several request messages

# if 1 then generate html and arhive
not_after_run=$6

cd "$WORKDIR/openssl-gcov" || exit 1

#delete the existing coverage file
rm $covfile; touch $covfile

#clear gcov data
gcovr -r . -s -d > /dev/null 2>&1
# lcov -z -d . > /dev/null 2>&1
# COV_INFO="$WORKDIR/coverage.info"
# rm -rf "$COV_INFO"

#output the header of the coverage file which is in the CSV format
#Time: timestamp, l_per/b_per and l_abs/b_abs: line/branch coverage in percentage and absolutate number
echo "Time,l_per,l_abs,b_per,b_abs" >> $covfile

#files stored in replayable-* folders are structured
#in such a way that messages are separated
if [ $fmode -eq "1" ]; then
  testdir="replayable-queue"
  crashdir="replayable-crashes"
  hangsdir="replayable-hangs"
  replayer="aflnet-replay"
else
  testdir="queue"
  crashdir="crashes"
  hangsdir="hangs"
  replayer="afl-replay"
fi

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

#process seeds first
for f in $(echo $folder/$testdir/*.raw); do 
  time=$(stat -c %Y $f)
  echo "[*] $time : $f"
    
  $replayer $f TLS $pno 100 > /dev/null 2>&1 &
  timeout -k 0 3s ./apps/openssl s_server -key key.pem -cert cert.pem -4 -naccept 1 -no_anti_replay > /dev/null 2>&1
  
  wait
  dump_coverage "$time"
done

#process other testcases
count=0
for f in $(ls -tr $folder/$testdir/id* $folder/$crashdir/id* $folder/$hangsdir/id*); do
  time=$(stat -c %Y $f)
  echo "[*] $time : $f"
  
  $replayer $f TLS $pno 100 > /dev/null 2>&1 &
  timeout -k 0 3s ./apps/openssl s_server -key key.pem -cert cert.pem -4 -naccept 1 -no_anti_replay > /dev/null 2>&1

  wait
  count=$(expr $count + 1)
  rem=$(expr $count % $step)
  if [ "$rem" != "0" ]; then continue; fi
  dump_coverage "$time"
done

#ouput cov data for the last testcase(s) if step > 1
if [[ $step -gt 1 ]]
then
  time=$(stat -c %Y $f)
  dump_coverage "$time"
fi

if [ "$not_after_run" = 1 ]; then
  covoutdir=$(dirname "$covfile")
  echo "[*] Generating HTML report to $covoutdir/cov_html"
  gcovr -r . --html --html-details -o index.html
  mkdir -p "$covoutdir/cov_html/"
  cp ./*.html "$covoutdir/cov_html/"
  # genhtml -o "$covoutdir/cov_html" --branch-coverage "$COV_INFO"

  echo "[*] Making archive"
  cd "$covoutdir" && tar cvzf "$WORKDIR/coverage.tar.gz" ./*

  echo "[+] All done"
fi
