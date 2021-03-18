#!/usr/bin/env bash

ROOTDIR=$(readlink -f "$(dirname "$0")/../")
subjectsdir="$ROOTDIR/subjects"

if [ ! -d "$subjectsdir" ]; then
    >&2 echo "'$subjectsdir' is not a directory"
    exit 1
fi

tmp=$(mktemp)
for subject_dir in "$subjectsdir"/*; do
    subject=$(basename "$subject_dir")
    echo "* Subj: $subject"
    for target_dir in "$subject_dir"/*; do
        target=$(basename "$target_dir")
        echo "  + $target"
        echo "    $target_dir"
        target_tag="${target,,}"
        if [ "$target" = PureFTPD ]; then
            target_tag='pure-ftpd'
        fi
        image="pfb-$target_tag"
        echo "sudo docker build -t $image $target_dir" >> "$tmp"
    done
done

echo "Running commands from $tmp"
parallel -j20 < "$tmp"
rm "$tmp"
