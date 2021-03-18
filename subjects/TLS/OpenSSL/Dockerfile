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
    vim

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

COPY --chown=ubuntu:ubuntu key.pem ${WORKDIR}/key.pem
COPY --chown=ubuntu:ubuntu cert.pem ${WORKDIR}/cert.pem
# Download and compile OpenSSL for fuzzing
RUN cd ${WORKDIR} && \
    git clone https://github.com/openssl/openssl.git && \
    cd openssl && \
    cp ${WORKDIR}/*.pem ./ && \
    git checkout 0437435a && \
    CC=afl-gcc ./config no-shared && \
    CC=afl-gcc make -j$(nproc)

# Download and compile OpenSSL for coverage analysis
COPY --chown=ubuntu:ubuntu gcov.patch ${WORKDIR}/gcov.patch
RUN cd ${WORKDIR} && \
    git clone https://github.com/openssl/openssl.git openssl-gcov && \
    cd openssl-gcov && \
    cp ${WORKDIR}/*.pem ./ && \
    git checkout 0437435a && \
    patch -p1 < ${WORKDIR}/gcov.patch && \
    CFLAGS="-fprofile-arcs -ftest-coverage" LDFLAGS="-fprofile-arcs -ftest-coverage" ./config no-shared && \
    CFLAGS="-fprofile-arcs -ftest-coverage" LDFLAGS="-fprofile-arcs -ftest-coverage" make -j$(nproc)

RUN cd $WORKDIR \
 && wget "https://github.com/linux-test-project/lcov/releases/download/v1.15/lcov-1.15.tar.gz" \
 && tar xf "lcov-1.15.tar.gz" \
 && cd "lcov-1.15" \
 && make PREFIX=~/.local install \
 && echo "lcov_branch_coverage = 1" > ~/.lcovrc

RUN mkdir "${WORKDIR}/in-tls-empty" \
 && /bin/echo -n 'A' > "${WORKDIR}/in-tls-empty/seed.raw"

COPY --chown=ubuntu:ubuntu in-tls ${WORKDIR}/in-tls
COPY --chown=ubuntu:ubuntu tls.dict ${WORKDIR}/tls.dict
COPY --chown=ubuntu:ubuntu cov_script.sh ${WORKDIR}/cov_script
COPY --chown=ubuntu:ubuntu cov_script_nyx.sh ${WORKDIR}/cov_script_nyx
COPY --chown=ubuntu:ubuntu run.sh ${WORKDIR}/run
