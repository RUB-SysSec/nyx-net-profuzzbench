#!/bin/bash

FUZZER=$1     #fuzzer name (e.g., aflnet) -- this name must match the name of the fuzzer folder inside the Docker container
OUTDIR=$2     #name of the output folder
OPTIONS=$3    #all configured options -- to make it flexible, we only fix some options (e.g., -i, -o, -N) in this script
TIMEOUT=$4    #time for fuzzing
SKIPCOUNT=$5  #used for calculating cov over time. e.g., SKIPCOUNT=5 means we run gcovr after every 5 test cases

strstr() {
  [ "${1#*$2*}" = "$1" ] && return 1
  return 0
}

#Commands for afl-based fuzzers (e.g., aflnet, aflnwe)
if $(strstr $FUZZER "afl"); then
  #Step-1. Do Fuzzing
  #Move to fuzzing folder
  cd $WORKDIR/dnsmasq/src
  timeout -k 0 $TIMEOUT /home/ubuntu/${FUZZER}/afl-fuzz -d -i ${WORKDIR}/in-dns -o $OUTDIR -N tcp://127.0.0.1/5353 $OPTIONS ./dnsmasq
  #Wait for the fuzzing process
  wait 

  #Step-2. Collect code coverage over time
  #Move to gcov folder
  cd $WORKDIR/dnsmasq-gcov/src

  #The last argument passed to cov_script should be 0 if the fuzzer is afl/nwe and it should be 1 if the fuzzer is based on aflnet
  #0: the test case is a concatenated message sequence -- there is no message boundary
  #1: the test case is a structured file keeping several request messages
  if [ $FUZZER = "aflnwe" ]; then
    cov_script ${WORKDIR}/dnsmasq/src/${OUTDIR}/ 5353 ${SKIPCOUNT} ${WORKDIR}/dnsmasq/src/${OUTDIR}/cov_over_time.csv 0
  else
    #As Dnsmasq is a kind-of stateless server, we use the test cases stored in queue folder and afl-replay instead of aflnet-replay
    #to calculate code coverage
    cov_script ${WORKDIR}/dnsmasq/src/${OUTDIR}/ 5353 ${SKIPCOUNT} ${WORKDIR}/dnsmasq/src/${OUTDIR}/cov_over_time.csv 0
  fi

  gcovr -r . --html --html-details -o index.html
  mkdir ${WORKDIR}/dnsmasq/src/${OUTDIR}/cov_html/
  cp *.html ${WORKDIR}/dnsmasq/src/${OUTDIR}/cov_html/

  #Step-3. Save the result to the ${WORKDIR} folder
  #Tar all results to a file
  cd ${WORKDIR}/dnsmasq/src
  tar -zcvf ${WORKDIR}/${OUTDIR}.tar.gz ${OUTDIR}
fi