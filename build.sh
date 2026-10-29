#!/bin/bash
# Copyright (c) 2026 ravindu644 <droidcasts@protonmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Linux 4.9 arm64 kernel build script for SM-A015F/G

set -euo pipefail

# cd to the repo root
KERNEL_ROOT="$(dirname "$(readlink -f "$0")")"
cd "${KERNEL_ROOT}"

# init submodules
git submodule update --init --recursive || true

# create build folders
mkdir -p out dist

# export toolchain path and core variables
export PATH="${HOME}/toolchains/llvm-arm-toolchain-ship/10.0.9/bin:${PATH}"
export KBUILD_BUILD_USER="@ravindu644"
BUILD_CROSS_COMPILE="${HOME}/toolchains/aarch64-linux-android-4.9/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
MAGISKBOOT="${KERNEL_ROOT}/prebuilts/magiskboot"
STOCK_BOOT="${KERNEL_ROOT}/prebuilts/boot.img"
STOCK_VBMETA="${KERNEL_ROOT}/prebuilts/vbmeta.img"

# generate localversion
BUILD_VERSION=$(git log -1 --pretty=%h 2>/dev/null)
if [ -z "$BUILD_VERSION" ]; then
    export BUILD_VERSION="dev"
fi
cat << EOF > "${KERNEL_ROOT}/arch/arm64/configs/version.config"
CONFIG_LOCALVERSION_AUTO=n
CONFIG_LOCALVERSION="-Miracle-10/2026"
EOF

# download the toolchains if they aren't there yet
download_toolchains(){
    local base="https://github.com/ravindu644/Android-Kernel-Tutorials/releases/download/toolchains"
    if [ ! -x "${HOME}/toolchains/llvm-arm-toolchain-ship/10.0.9/bin/clang" ]; then
        echo "[INFO]: downloading llvm-arm-toolchain-ship-10.0.9..."
        mkdir -p "${HOME}/toolchains"
        wget -q --show-progress -O- "${base}/llvm-arm-toolchain-ship-10.0.9.tar.gz" | tar -xz -C "${HOME}/toolchains"
    fi
    if [ ! -x "${BUILD_CROSS_COMPILE}gcc" ]; then
        echo "[INFO]: downloading aarch64-linux-android-4.9..."
        mkdir -p "${HOME}/toolchains/aarch64-linux-android-4.9"
        wget -q --show-progress -O- "${base}/aarch64-linux-android-4.9.tar.gz" | tar -xz -C "${HOME}/toolchains/aarch64-linux-android-4.9"
    fi
}

# build options for the kernel
BUILD_OPTIONS=(
    -C "${KERNEL_ROOT}"
    O="${KERNEL_ROOT}/out"
    -j"$(nproc)"
    ARCH=arm64
    DTC_EXT="${KERNEL_ROOT}/tools/dtc"
    CONFIG_BUILD_ARM64_DT_OVERLAY=y
    CROSS_COMPILE="${BUILD_CROSS_COMPILE}"
    CC=clang
    CLANG_TRIPLE=aarch64-linux-gnu-
    LOCALVERSION=
)

build_kernel(){
    # cleanup
    # make "${BUILD_OPTIONS[@]}" clean && make "${BUILD_OPTIONS[@]}" mrproper
    
    # make default configuration.
    make "${BUILD_OPTIONS[@]}" sdm439_sec_a01q_swa_ins_defconfig version.config custom.config droidspaces.config

    # menuconfig, only when someone is at a terminal (skipped in CI)
    [ -t 0 ] && make "${BUILD_OPTIONS[@]}" menuconfig

    # Build the kernel
    make "${BUILD_OPTIONS[@]}" || exit 1

    # Copy the built kernel to the build directory
    cp "${KERNEL_ROOT}/out/arch/arm64/boot/Image" "${KERNEL_ROOT}/dist/Image"
}

build_boot(){
    # unpack stock boot.img, swap in our kernel, repack.
    # magiskboot re-gzips the raw Image like stock and keeps the stock
    # dtb, ramdisk, cmdline and os_version/os_patch_level header fields.
    local work="${KERNEL_ROOT}/dist/boot_work"
    rm -rf "${work}" && mkdir -p "${work}" && cd "${work}"
    "${MAGISKBOOT}" unpack "${STOCK_BOOT}"
    cp "${KERNEL_ROOT}/dist/Image" kernel
    "${MAGISKBOOT}" repack "${STOCK_BOOT}" "${KERNEL_ROOT}/dist/boot.img"
    cd "${KERNEL_ROOT}" && rm -rf "${work}"
}

build_vbmeta(){
    # must be the stock vbmeta: the bootloader hands its security_patch to
    # keymaster, and a generic one with an older date breaks FBE key decryption.
    # only set flags (offset 123) = 0x03: verity + verification disabled.
    cp "${STOCK_VBMETA}" "${KERNEL_ROOT}/dist/vbmeta.img"
    printf '\x03' | dd of="${KERNEL_ROOT}/dist/vbmeta.img" bs=1 seek=123 conv=notrunc status=none
}

build_tar(){
    # Odin-flashable tar
    cd "${KERNEL_ROOT}/dist"
    tar -cvf "Miracle-MSM8953.tar" boot.img vbmeta.img && \
        echo -e "\n[INFO]: TAR BUILT SUCCESSFULLY..!\n"
    cd "${KERNEL_ROOT}"
}

download_toolchains
build_kernel
build_boot
build_vbmeta
build_tar
