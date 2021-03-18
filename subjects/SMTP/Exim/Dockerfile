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
    autoconf \
    libssl-dev \
    libpcre3-dev \
    pkg-config \
    libdb-dev \
    libgdbm-dev \
    nano \
    net-tools \
    vim \
    python-jinja2 \
    wget \
    python-pip

# Add a new user ubuntu, pass: ubuntu
RUN groupadd ubuntu && \
    useradd -rm -d /home/ubuntu -s /bin/bash -g ubuntu -G sudo -u 1000 ubuntu -p "$(openssl passwd -1 ubuntu)"

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
ENV PATH="/usr/exim/bin:${PATH}:${AFLNET}:/home/ubuntu/.local/bin:${WORKDIR}"
ENV AFL_PATH="${AFLNET}"
ENV AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
    AFL_SKIP_CPUFREQ=1 \
    AFL_NO_AFFINITY=1

RUN mkdir $WORKDIR && \
    pip install gcovr==4.2

COPY --chown=ubuntu:ubuntu in-smtp ${WORKDIR}/in-smtp
COPY --chown=ubuntu:ubuntu smtp.dict ${WORKDIR}/smtp.dict
COPY --chown=ubuntu:ubuntu exim.patch ${WORKDIR}/exim.patch

# Download, compile and install Exim for fuzzing
RUN cd ${WORKDIR} && \
    git clone https://github.com/Exim/exim && \
    cd exim && \
    git checkout 38903fb && \
    cd src; mkdir Local; cp src/EDITME Local/Makefile && \
    cd Local; patch -p1 < ${WORKDIR}/exim.patch; cd .. && \
    make CC=afl-clang-fast clean all install

RUN cd ${WORKDIR} && \
    git clone https://github.com/Exim/exim exim-gcov_checkout

# Configure exim
COPY --chown=ubuntu:ubuntu exim.configure.patch ${WORKDIR}/exim.configure.patch
RUN cd /usr/exim && \
    patch -p1 < ${WORKDIR}/exim.configure.patch && \
    chmod 1777 /var/mail

RUN cd $WORKDIR \
 && wget "https://github.com/linux-test-project/lcov/releases/download/v1.15/lcov-1.15.tar.gz" \
 && tar xf "lcov-1.15.tar.gz" \
 && cd "lcov-1.15" \
 && make install \
 && echo "lcov_branch_coverage = 1" > ~/.lcovrc \
 && echo "lcov_branch_coverage = 1" > /home/ubuntu/.lcovrc

RUN mkdir "${WORKDIR}/in-smtp-empty" \
 && /bin/echo -n 'A' > "${WORKDIR}/in-smtp-empty/seed.raw" \
 && mkdir "$WORKDIR/fuzzer-crashes"

COPY --chown=ubuntu:ubuntu exim.configure.cov.patch ${WORKDIR}/exim.configure.cov.patch
COPY --chown=ubuntu:ubuntu compile_exim_gcov.sh ${WORKDIR}/compile_exim_gcov.sh
COPY --chown=ubuntu:ubuntu compile_exim_asan.sh ${WORKDIR}/compile_exim_asan.sh
COPY --chown=ubuntu:ubuntu cov_script.sh ${WORKDIR}/cov_script
COPY --chown=ubuntu:ubuntu cov_script_nyx.sh ${WORKDIR}/cov_script_nyx
COPY --chown=ubuntu:ubuntu run.sh ${WORKDIR}/run
COPY --chown=ubuntu:ubuntu nyx_replay_fast.py ${WORKDIR}/nyx_replay_fast.py
COPY --chown=ubuntu:ubuntu clean.sh ${WORKDIR}/clean.sh
COPY --chown=ubuntu:ubuntu exim_coverage.patch ${WORKDIR}/exim_coverage.patch
COPY --chown=ubuntu:ubuntu nyx2aflnet.py ${WORKDIR}/nyx2aflnet.py
COPY --chown=ubuntu:ubuntu log.c.patch ${WORKDIR}/log.c.patch
COPY --chown=ubuntu:ubuntu crashes_stats.sh ${WORKDIR}/crashes_stats.sh
