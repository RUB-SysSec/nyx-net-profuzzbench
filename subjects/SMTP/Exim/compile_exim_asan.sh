#!/bin/bash

set -e

rm -rf /usr/exim/configure

#Compile and install exim to collect code coverage
cd ${WORKDIR}
git clone https://github.com/Exim/exim exim-asan
cd exim-asan
git checkout 38903fb
patch -p1 < $WORKDIR/log.c.patch && \
cd src
mkdir Local
cp src/EDITME Local/Makefile
cd Local
patch -p1 < ${WORKDIR}/exim.patch
cd ..
ASAN_OPTIONS=detect_leaks=0 make -j$(nproc) CC="afl-clang-fast -fsanitize=address -fPIC" clean all install

# Configure exim
cd /usr/exim
patch -p0 < ${WORKDIR}/exim.configure.patch
chmod 1777 /var/mail
