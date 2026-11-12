FROM arm64v8/ubuntu:18.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# bionic 已 EOL，但 ports.ubuntu.com 仍提供 arm64 包
RUN printf 'deb http://ports.ubuntu.com/ubuntu-ports bionic main restricted universe multiverse\n\
deb http://ports.ubuntu.com/ubuntu-ports bionic-updates main restricted universe multiverse\n\
deb http://ports.ubuntu.com/ubuntu-ports bionic-security main restricted universe multiverse\n' > /etc/apt/sources.list

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc-8 g++-8 ninja-build pkg-config git \
        ca-certificates curl wget xz-utils \
        zlib1g-dev libwebp-dev libcurl4-openssl-dev libssl-dev \
        libdrm-dev libgbm-dev libudev-dev libasound2-dev libpulse-dev \
    && rm -rf /var/lib/apt/lists/*

# bionic 的 cmake 只有 3.10，wiliwili 要求 >= 3.13
RUN wget -q https://github.com/Kitware/CMake/releases/download/v3.25.2/cmake-3.25.2-linux-aarch64.tar.gz -O /tmp/cmake.tgz \
    && mkdir -p /opt && tar -xzf /tmp/cmake.tgz -C /opt \
    && ln -sf /opt/cmake-3.25.2-linux-aarch64/bin/cmake /usr/local/bin/cmake \
    && ln -sf /opt/cmake-3.25.2-linux-aarch64/bin/ctest /usr/local/bin/ctest \
    && ln -sf /opt/cmake-3.25.2-linux-aarch64/bin/cpack /usr/local/bin/cpack \
    && rm -f /tmp/cmake.tgz

RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-8 100 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-8 100

RUN cmake --version && gcc --version | head -1 && g++ --version | head -1 && ninja --version

WORKDIR /work