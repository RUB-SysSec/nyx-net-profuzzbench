#!/usr/bin/env bash

set -ex
grep -v nyx "split/$1.csv" > "$1.csv"
grep nyx "split/$1_snaps.csv" >> "$1.csv"
