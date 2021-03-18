FROM ubuntu:16.04

# Install common dependencies
RUN apt-get -y update && \
    apt-get -y install sudo \ 
    apt-utils \
    build-essential \
    openssl \
    clang \
    graphviz-dev \
    git \
    libgnutls-dev \
    python-pip \
    python-jinja2 \
    wget \
    nano \
    net-tools \
    vim \
    bison \
    flex

# Add a new user ubuntu, pass: ubuntu
RUN groupadd ubuntu && \
    useradd -rm -d /home/ubuntu -s /bin/bash -g ubuntu -G sudo -u 1000 ubuntu -p "$(openssl passwd -1 ubuntu)"

# Use ubuntu as default username
USER ubuntu
WORKDIR /home/ubuntu

# Download and compile AFLNet
ENV LLVM_CONFIG="llvm-config-3.8"

# Set up fuzzers
RUN git clone https://github.com/profuzzbench/aflnet.git && \
    cd aflnet && \
    make clean all && \
    cd llvm_mode && make

RUN git clone https://github.com/profuzzbench/aflnwe.git && \
    cd aflnwe && \
    make clean all && \
    cd llvm_mode && make

RUN wget "https://github.com/AFLplusplus/AFLplusplus/archive/refs/tags/3.12c.tar.gz" \
        -O AFLplusplus-3.12c.tar.gz \
 && tar xf AFLplusplus-3.12c.tar.gz \
 && mv AFLplusplus-3.12c aflpp \
 && cd aflpp && make all

RUN git clone "https://github.com/zardus/preeny.git" \
 && cd preeny && git checkout --detach 73d8404 \
 && cd src && make desock.so

# Set up environment variables for AFLNet
ENV WORKDIR="/home/ubuntu/experiments"
ENV AFLNET="/home/ubuntu/aflnet"
ENV PATH="${PATH}:${AFLNET}:/home/ubuntu/.local/bin:${WORKDIR}"
ENV AFL_PATH="${AFLNET}"
ENV AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
    AFL_SKIP_CPUFREQ=1 \
    AFL_NO_AFFINITY=1

RUN mkdir $WORKDIR && \
    pip install gcovr==4.2

COPY --chown=ubuntu:ubuntu kamailio.patch ${WORKDIR}/kamailio.patch

# Download and compile Kamalio for fuzzing
RUN cd $WORKDIR && \
    git clone https://github.com/kamailio/kamailio.git && \
    cd kamailio && \
    git checkout 2648eb3 && \
    patch -p1 < $WORKDIR/kamailio.patch && \
    CC=afl-clang-fast make cfg && \
    CC=afl-clang-fast make -j$(nproc) all

COPY --chown=ubuntu:ubuntu kamailio-gcov.patch ${WORKDIR}/kamailio-gcov.patch

# Download and compile Kamalio for code coverage analysis
RUN cd $WORKDIR && \
    git clone https://github.com/kamailio/kamailio.git kamailio-gcov && \
    cd kamailio-gcov && \
    git checkout 2648eb3 && \
    patch -p1 < $WORKDIR/kamailio-gcov.patch && \
    make CC_EXTRA_OPTS="-fprofile-arcs -ftest-coverage" LD_EXTRA_OPTS="-fprofile-arcs -ftest-coverage" cfg && \
    make  -j$(nproc) CC_EXTRA_OPTS="-fprofile-arcs -ftest-coverage" LD_EXTRA_OPTS="-fprofile-arcs -ftest-coverage" all


COPY --chown=ubuntu:ubuntu pjsip.patch ${WORKDIR}/pjsip.patch

RUN cd $WORKDIR && \
    git clone https://github.com/pjsip/pjproject.git && \
    cd pjproject && \
    git checkout bba95b8 && \
    patch -p1 < $WORKDIR/pjsip.patch && \
    ./configure && \
    make dep && make clean && make

RUN cd $WORKDIR && \
    git clone https://github.com/kamailio/kamailio.git kamailio-asan && \
    cd kamailio-asan && \
    git checkout 2648eb3 && \
    patch -p1 < $WORKDIR/kamailio.patch && \
    CC="afl-clang-fast -fsanitize=address" make cfg && \
    CC="afl-clang-fast -fsanitize=address" make -j$(nproc) all

RUN cd $WORKDIR \
 && wget "https://github.com/linux-test-project/lcov/releases/download/v1.15/lcov-1.15.tar.gz" \
 && tar xf "lcov-1.15.tar.gz" \
 && cd "lcov-1.15" \
 && make PREFIX=~/.local install \
 && echo "lcov_branch_coverage = 1" > ~/.lcovrc

RUN mkdir "${WORKDIR}/in-sip-empty" \
 && /bin/echo -n 'A' > "${WORKDIR}/in-sip-empty/seed.raw" \
 && mkdir "$WORKDIR/fuzzer-crashes"

COPY --chown=ubuntu:ubuntu kamailio-basic.cfg ${WORKDIR}/kamailio-basic.cfg
COPY --chown=ubuntu:ubuntu in-sip ${WORKDIR}/in-sip
COPY --chown=ubuntu:ubuntu StarWars3.wav ${WORKDIR}/StarWars3.wav
COPY --chown=ubuntu:ubuntu cov_script.sh ${WORKDIR}/cov_script
COPY --chown=ubuntu:ubuntu cov_script_nyx.sh ${WORKDIR}/cov_script_nyx
COPY --chown=ubuntu:ubuntu run.sh ${WORKDIR}/run
COPY --chown=ubuntu:ubuntu run_pjsip.sh ${WORKDIR}/run_pjsip
COPY --chown=ubuntu:ubuntu crashes_stats.sh ${WORKDIR}/crashes_stats.sh
