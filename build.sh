#!/bin/bash
official_source="SM-S9080_CHN_14_Opensource.zip" # change it with you downloaded file
build_root=$(pwd)
kernel_root="$build_root/kernel_source"
toolchains_root="$build_root/toolchains"
SUSFS_REPO="https://github.com/ShirkNeko/susfs4ksu.git"
KERNELSU_INSTALL_SCRIPT="https://raw.githubusercontent.com/pershoot/KernelSU-Next/next-susfs/kernel/setup.sh"
kernel_su_next_branch="next-susfs"
susfs_branch="gki-android12-5.10"
container_name="sm8450-kernel-builder"

kernel_build_script="scripts/build_kernel_5.10.sh"
support_kernel="5.10" # only support 5.10 kernel
kernel_source_link="https://opensource.samsung.com/uploadSearch?searchValue=SM-S90"

custom_config_name="custom_gki_defconfig"
custom_config_file="$kernel_root/arch/arm64/configs/$custom_config_name"

# Load utility functions
lib_file="$build_root/scripts/utils/lib.sh"
if [ -f "$lib_file" ]; then
    source "$lib_file"
else
    echo "[-] Error: Library file not found: $lib_file"
    echo "[-] Please ensure lib.sh exists in the build directory"
    exit 1
fi
core_file="$build_root/scripts/utils/core.sh"
if [ -f "$core_file" ]; then
    source "$core_file"
else
    echo "[-] Error: Core file not found: $core_file"
    echo "[-] Please ensure lib.sh exists in the build directory"
    exit 1
fi

function prepare_toolchains() {
    mkdir -p "$toolchains_root"
    # init clang-r416183b
    if [ ! -d "$toolchains_root/clang-r416183b" ]; then
        echo -e "\n[INFO] Cloning Clang-r416183b...\n"
        mkdir -p "$toolchains_root/clang-r416183b"
        cd "$toolchains_root/clang-r416183b"
        curl -LO "https://github.com/ravindu644/Android-Kernel-Tutorials/releases/download/toolchains/clang-r416183b.tar.gz"
        tar -xf clang-r416183b.tar.gz
        rm clang-r416183b.tar.gz
        cd - >/dev/null
    fi
    # init arm gnu toolchain
    if [ ! -d "$toolchains_root/gcc" ]; then
        echo -e "\n[INFO] Cloning ARM GNU Toolchain\n"
        mkdir -p "$toolchains_root/gcc"
        cd "$toolchains_root/gcc"
        curl -LO "https://developer.arm.com/-/media/Files/downloads/gnu/14.2.rel1/binrel/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz"
        tar -xf arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
        cd - >/dev/null
    fi
}

function __fix_patch() {
    echo "[+] Fixing patch..."
    cd "$kernel_root"
    _apply_patch_strict "fix_patch.patch"
    if [ $? -ne 0 ]; then
        echo "[-] Failed to apply fix patch."
        exit 1
    fi
    echo "[+] Fix patch applied successfully."
}

function __restore_fix_patch() {
    echo "[+] Restoring fix patch..."
    cd "$kernel_root"
    _apply_patch_strict "fix_patch_reverse.patch"
    if [ $? -ne 0 ]; then
        echo "[-] Failed to restore fix patch."
        exit 1
    fi
    echo "[+] Fix patch restored successfully."
}

function add_susfs() {
    add_susfs_prepare
    echo "[+] Applying SuSFS patches..."
    cd "$kernel_root"
    __fix_patch # remove some samsung's changes, then susfs can be applied
    local patch_result=$(patch -p1 <50_add_susfs_in_$susfs_branch.patch)
    if [ $? -ne 0 ]; then
        echo "$patch_result"
        echo "[-] Failed to apply SuSFS patches."
        echo "$patch_result" | grep -q ".rej"
        exit 1
    else
        echo "[+] SuSFS patches applied successfully."
        echo "$patch_result" | grep -q ".rej"
    fi
    __restore_fix_patch # restore removed samsung's changes
    echo "[+] SuSFS added successfully."
}

function print_usage() {
    echo "Usage: $0 [container|clean|prepare]"
    echo "  container: Build the Docker container for kernel compilation"
    echo "  clean: Clean the kernel source directory"
    echo "  prepare: Prepare the kernel source directory"
    echo "  (default): Run the main build process"
}

function main() {
    echo "[+] Starting kernel build process..."

    # Validate environment before proceeding
    if ! validate_environment; then
        echo "[-] Environment validation failed"
        exit 1
    fi

    prepare_toolchains
    clean
    prepare_source
    extract_kernel_config

    show_config_summary

    add_kernelsu_next
    add_susfs
    fix_kernel_su_next_susfs
    apply_kernelsu_manual_hooks_for_next
    apply_wild_kernels_config
    apply_wild_kernels_fix_for_next
    fix_driver_check
    fix_samsung_securities
    add_build_script

    echo "[+] All done. You can now build the kernel."
    echo "[+] Please 'cd $kernel_root'"
    echo "[+] Run the build script with ./build.sh"
    echo ""

    if docker images | grep -q "$container_name"; then
        print_docker_usage
    else
        echo "To build using Docker container instead:"
        echo "./build.sh container"
    fi
}

case "${1:-}" in
"container")
    build_container
    exit $?
    ;;
"clean")
    clean
    echo "[+] Cleaned kernel source directory."
    exit 0
    ;;
"prepare")
    prepare_source
    echo "[+] Prepared kernel source directory."
    exit 0
    ;;
"?" | "help" | "--help" | "-h")
    print_usage
    exit 0
    ;;
"kernel")
    main
    # build container if not exists
    if ! docker images | grep -q "$container_name"; then
        build_container
        if [ $? -ne 0 ]; then
            echo "[-] Failed to build Docker container."
            exit 1
        fi
    fi
    echo "[+] Building kernel using Docker container..."
    docker run --rm -it -v "$kernel_root:/workspace" -v "$toolchains_root:/toolchains" $container_name /workspace/build.sh

    exit 0
    ;;
"")
    main
    ;;
*)
    echo "[-] Unknown option: $1"
    print_usage
    exit 1
    ;;
esac
