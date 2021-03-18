FROM ubuntu:16.04

RUN chmod 777 /tmp
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
    nano \
    net-tools \
    netcat \
    vim \
    ftp \
    wget

# Add a new user ubuntu, pass: ubuntu
RUN groupadd ubuntu && \
    useradd -rm -d /home/ubuntu -s /bin/bash -g ubuntu -G sudo -u 1000 ubuntu -p "$(openssl passwd -1 ubuntu)"

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
ENV PATH="${PATH}:${AFLNET}:/home/ubuntu/.local/bin:${WORKDIR}:${WORKDIR}/bftpd"
ENV AFL_PATH="${AFLNET}"
ENV AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
    AFL_SKIP_CPUFREQ=1 \
    AFL_NO_AFFINITY=1

RUN mkdir $WORKDIR && \
    mkdir /home/ubuntu/ftpshare && \
    chown -R ubuntu:ubuntu /home/ubuntu/ftpshare && \
    pip install gcovr==4.2

COPY --chown=ubuntu:ubuntu fuzzing.patch ${WORKDIR}/fuzzing.patch
COPY --chown=ubuntu:ubuntu gcov.patch ${WORKDIR}/gcov.patch

# Set up Bftpd for fuzzing
RUN cd ${WORKDIR} && \
    wget https://phoenixnap.dl.sourceforge.net/project/bftpd/bftpd/bftpd-5.7/bftpd-5.7.tar.gz && \
    tar -zxvf bftpd-5.7.tar.gz && \
    mv bftpd bftpd-gcov && \
    tar -zxvf bftpd-5.7.tar.gz && \
    cd bftpd && \
    patch -p1 < ${WORKDIR}/fuzzing.patch && \
    CC=afl-clang-fast make clean all

# Set up Bftpd for coverage analysis
RUN cd ${WORKDIR}/bftpd-gcov && \
    patch -p1 < ${WORKDIR}/gcov.patch && \
    make

RUN cd "$WORKDIR" \
 && tar -xf "bftpd-5.7.tar.gz" -C /tmp \
 && mv /tmp/bftpd ./bftpd-asan \
 && cd bftpd-asan \
 && patch -p1 < "$WORKDIR/fuzzing.patch" \
 && CC="afl-clang-fast -fsanitize=address" make clean all

COPY --chown=ubuntu:ubuntu basic.conf ${WORKDIR}/
COPY --chown=ubuntu:ubuntu in-ftp ${WORKDIR}/in-ftp
COPY --chown=ubuntu:ubuntu ftp.dict ${WORKDIR}/ftp.dict
COPY --chown=ubuntu:ubuntu run.sh ${WORKDIR}/run
COPY --chown=ubuntu:ubuntu clean.sh ${WORKDIR}/clean
COPY --chown=ubuntu:ubuntu cov_script.sh ${WORKDIR}/cov_script
COPY --chown=ubuntu:ubuntu cov_script_nyx.sh ${WORKDIR}/cov_script_nyx
COPY --chown=ubuntu:ubuntu crashes_stats.sh ${WORKDIR}/crashes_stats.sh

RUN mkdir "${WORKDIR}/in-ftp-empty" \
 && /bin/echo -n 'A' > "${WORKDIR}/in-ftp-empty/seed.raw" \
 && mkdir "$WORKDIR/fuzzer-crashes"

# Switch default user to root
USER root
WORKDIR /home/ubuntu

RUN cd $WORKDIR \
 && wget "https://github.com/linux-test-project/lcov/releases/download/v1.15/lcov-1.15.tar.gz" \
 && tar xf "lcov-1.15.tar.gz" \
 && cd "lcov-1.15" \
 && make install \
 && echo "lcov_branch_coverage = 1" > ~/.lcovrc \
 && echo "lcov_branch_coverage = 1" > /home/ubuntu/.lcovrc

RUN pip install gcovr==4.2
