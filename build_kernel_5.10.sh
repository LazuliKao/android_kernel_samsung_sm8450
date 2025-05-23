#!/bin/bash

export KERNEL_ROOT="$(pwd)"
export ARCH=arm64
export KBUILD_BUILD_USER="@lk"
LOCALVERSION=-android12-lk
TARGET_DEFCONFIG=${1:-gki_defconfig}

function prepare_toolchain() {
    # Install the requirements for building the kernel when running the script for the first time
    if [ ! -f ".requirements" ]; then
        sudo apt update && sudo apt install -y git device-tree-compiler lz4 xz-utils zlib1g-dev openjdk-17-jdk gcc g++ python3 python-is-python3 p7zip-full android-sdk-libsparse-utils erofs-utils \
            default-jdk git gnupg flex bison gperf build-essential zip curl libc6-dev libncurses-dev libx11-dev libreadline-dev libgl1 libgl1-mesa-dev \
            python3 make sudo gcc g++ bc grep tofrodos python3-markdown libxml2-utils xsltproc zlib1g-dev python-is-python3 libc6-dev libtinfo6 \
            make repo cpio kmod openssl libelf-dev pahole libssl-dev libarchive-tools zstd --fix-missing && wget http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb && sudo dpkg -i libtinfo5_6.3-2ubuntu0.1_amd64.deb && touch .requirements
    fi

    # Create necessary directories
    mkdir -p "${KERNEL_ROOT}/out" "${KERNEL_ROOT}/build" "${HOME}/toolchains"

    # init clang-r416183b
    if [ ! -d "${HOME}/toolchains/clang-r416183b" ]; then
        echo -e "\n[INFO] Cloning Clang-r416183b...\n"
        mkdir -p "${HOME}/toolchains/clang-r416183b" && cd "${HOME}/toolchains/clang-r416183b"
        curl -LO "https://github.com/ravindu644/Android-Kernel-Tutorials/releases/download/toolchains/clang-r416183b.tar.gz"
        tar -xf clang-r416183b.tar.gz && rm clang-r416183b.tar.gz
        cd "${KERNEL_ROOT}"
    fi

    # init arm gnu toolchain
    if [ ! -d "${HOME}/toolchains/gcc" ]; then
        echo -e "\n[INFO] Cloning ARM GNU Toolchain\n"
        mkdir -p "${HOME}/toolchains/gcc" && cd "${HOME}/toolchains/gcc"
        curl -LO "https://developer.arm.com/-/media/Files/downloads/gnu/14.2.rel1/binrel/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz"
        tar -xf arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
        cd "${KERNEL_ROOT}"
    fi
    # Export toolchain paths
    export PATH="${PATH}:${HOME}/toolchains/clang-r416183b/bin"
    export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${HOME}/toolchains/clang-r416183b/lib64"

    # Set cross-compile environment variables
    export BUILD_CROSS_COMPILE="${HOME}/toolchains/gcc/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-"
    export BUILD_CC="${HOME}/toolchains/clang-r416183b/bin/clang"
}
function prepare_config() {
    if [ "$LTO" == "thin" ]; then
        LOCALVERSION+="-thin"
    fi
    # Build options for the kernel
    export BUILD_OPTIONS="
-C ${KERNEL_ROOT} \
O=${KERNEL_ROOT}/out \
-j$(nproc) \
ARCH=arm64 \
LLVM=1 \
LLVM_IAS=1 \
CROSS_COMPILE=${BUILD_CROSS_COMPILE} \
CC=${BUILD_CC} \
CLANG_TRIPLE=aarch64-linux-gnu- \
LOCALVERSION=$LOCALVERSION \
"
    # Make default configuration.
    make ${BUILD_OPTIONS} $TARGET_DEFCONFIG

    # Configure the kernel (GUI)
    make ${BUILD_OPTIONS} menuconfig

    # Set the kernel configuration, Disable unnecessary features
    ./scripts/config --file out/.config \
        -d UH \
        -d RKP \
        -d KDP \
        -d SECURITY_DEFEX \
        -d INTEGRITY \
        -d FIVE \
        -d TRIM_UNUSED_KSYMS

    # use thin lto
    if [ "$LTO" = "thin" ]; then
        ./scripts/config --file out/.config -e LTO_CLANG_THIN -d LTO_CLANG_FULL
    fi
}

function repack_stock_img() {
    local stock_boot_img="$KERNEL_ROOT/stock/boot.img"
    if [ ! -f "$stock_boot_img" ]; then
        echo "[-] boot.img not found. Skipping repack."
        return 0
    fi
    local build_dir="${KERNEL_ROOT}/build"
    local output_kernel_build="$build_dir/out"
    if [ ! -d "$output_kernel_build" ]; then
        mkdir -p "$output_kernel_build"
    fi
    # local image="$output_kernel_build/boot.img"
    # cp "$stock_boot_img" "$image"
    local output_kernel_build_tools="$build_dir/tools"
    # download magiskboot
    local magiskboot="$output_kernel_build_tools/magiskboot"
    if [ ! -f "$magiskboot" ]; then
        echo "[-] magiskboot not found. Downloading..."
        mkdir -p "$output_kernel_build_tools"
        local magiskzip="$output_kernel_build/magisk.zip"
        wget https://github.com/topjohnwu/Magisk/releases/download/v29.0/Magisk-v29.0.apk -O "$magiskzip"
        local output_kernel_build_tools="${KERNEL_ROOT}/build/tools"
        if [ ! -d "$output_kernel_build_tools" ]; then
            mkdir -p "$output_kernel_build_tools"
        fi
        local magiskboot_path="lib/x86_64/libmagiskboot.so"
        unzip -o "$magiskzip" "$magiskboot_path" -d "$output_kernel_build_tools"
        mv "$output_kernel_build_tools/$magiskboot_path" "$magiskboot"
        rm -rf "$output_kernel_build_tools/lib"
        chmod +x "$magiskboot"
    fi
    # Set PATCHVBMETAFLAG to enable patching of vbmeta header flags in boot image
    export PATCHVBMETAFLAG=true
    # unpack the boot.img
    cd "$output_kernel_build"
    echo "[+] Unpacking boot.img..."
    "$magiskboot" cleanup
    "$magiskboot" unpack "$stock_boot_img"
    # copy the new kernel to the boot.img
    local new_kernel="$build_dir/kernel"
    if [ ! -f "$new_kernel" ]; then
        echo "[-] Kernel not found. Skipping repack."
        return 0
    fi
    echo "[-] Old kernel: $(file kernel)"
    rm kernel
    cp "$new_kernel" kernel
    echo "[+] New kernel: $(file kernel)"
    # repack the boot.img
    echo "[+] Repacking boot.img..."
    "$magiskboot" repack "$stock_boot_img" ../boot.img
    cd -
    echo "[+] Repacked boot.img: $(file $build_dir/boot.img)"
    echo "[+] Repack: ./build/boot.img, you can flash it using odin."
    echo "[+] Repacked boot.img successfully."
}

function build_kernel() {
    # Build the kernel
    make ${BUILD_OPTIONS} Image || exit 1
    # Copy the built kernel to the build directory
    local output_kernel="${KERNEL_ROOT}/build/kernel"
    cp "${KERNEL_ROOT}/out/arch/arm64/boot/Image" "$output_kernel"
    echo -e "\n[INFO]: Kernel built successfully and copied to $output_kernel\n"
}

main() {
    echo -e "\n[INFO]: BUILD STARTED..!\n"
    prepare_toolchain
    prepare_config
    build_kernel
    echo -e "\n[INFO]: BUILD FINISHED..!"
}
main