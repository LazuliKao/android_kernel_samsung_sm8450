FROM ubuntu:22.04

# Set non-interactive mode for apt
ENV DEBIAN_FRONTEND=noninteractive

# Set up timezone to avoid hanging on tzdata install
ENV TZ=Etc/UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Update and install general build dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    python3 \
    python-is-python3 \
    bc \
    bison \
    build-essential \
    ccache \
    cpio \
    device-tree-compiler \
    erofs-utils \
    flex \
    gcc \
    g++ \
    gnupg \
    gperf \
    grep \
    kmod \
    libarchive-tools \
    libc6-dev \
    libelf-dev \
    libncurses-dev \
    libssl-dev \
    libtinfo5 \
    libtinfo6 \
    libx11-dev \
    libxml2-utils \
    libreadline-dev \
    libgl1 \
    libgl1-mesa-dev \
    lz4 \
    make \
    openssl \
    openjdk-17-jdk \
    p7zip-full \
    pahole \
    repo \
    sudo \
    tofrodos \
    xsltproc \
    xz-utils \
    zip \
    zlib1g-dev \
    zstd \
    android-sdk-libsparse-utils \
    default-jdk \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create build user and group and setup sudo without password
RUN groupadd -r build && useradd -r -g build -m -d /home/build build && \
    mkdir -p /workspace && chown -R build:build /workspace && \
    echo "build ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/build

# Create workspace directory
WORKDIR /workspace

# Create directories for toolchains
RUN mkdir -p /home/build/toolchains && chown -R build:build /home/build

# Download and extract Clang
USER build
RUN mkdir -p /home/build/toolchains/clang-r416183b && \
    cd /home/build/toolchains/clang-r416183b && \
    curl -LO "https://github.com/ravindu644/Android-Kernel-Tutorials/releases/download/toolchains/clang-r416183b.tar.gz" && \
    tar -xf clang-r416183b.tar.gz && \
    rm clang-r416183b.tar.gz

# Download and extract ARM GNU Toolchain
RUN mkdir -p /home/build/toolchains/gcc && \
    cd /home/build/toolchains/gcc && \
    curl -LO "https://developer.arm.com/-/media/Files/downloads/gnu/14.2.rel1/binrel/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz" && \
    tar -xf arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz && \
    rm arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz

# Set environment variables
ENV PATH="${PATH}:/home/build/toolchains/clang-r416183b/bin"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/home/build/toolchains/clang-r416183b/lib64"
ENV BUILD_CROSS_COMPILE="/home/build/toolchains/gcc/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-"
ENV BUILD_CC="/home/build/toolchains/clang-r416183b/bin/clang"
ENV ARCH=arm64

# Switch back to root user for copying files
USER root

# Copy the build scripts
RUN chown -R build:build /workspace/

# Switch to build user for the rest of operations
USER build

# Set working directory
WORKDIR /workspace

# Set default command
CMD ["/bin/bash"]