#!/bin/bash
# U-Boot Environment Variables

# ===========================================
# DEFINE REPOSITORIES AND BRANCHES
# ===========================================

# U-Boot repository details
UBOOT_REPO="https://github.com/varigit/uboot-imx.git"
UBOOT_BRANCH="lf_v2023.04_var02"

# ARM Trusted Firmware repository details
ATF_REPO="https://github.com/varigit/imx-atf.git"
ATF_BRANCH="lf_v2.8_var03"

# Variscite's BSP repository details
META_VARISCITE_BSP_REPO="https://github.com/varigit/meta-variscite-bsp.git"
META_VARISCITE_BSP_BRANCH="mickledore-var02"

# i.MX mkimage tool repository details
IMX_MKIMAGE_REPO="https://github.com/nxp-imx/imx-mkimage.git"
IMX_MKIMAGE_BRANCH="lf-6.6.3_1.0.0"

# DDR firmware URL for i.MX8MP
DDR_FIRMWARE_URL="https://www.nxp.com/lgfiles/NMG/MAD/YOCTO/firmware-imx-8.18.bin"

# ===========================================
# CROSS COMPILER
# ===========================================

# Cross-compiler and architecture for ARM64
CROSS_COMPILE_ARM64="ccache aarch64-linux-gnu-"
ARCH_ARM64="arm64"

# Enable ccache for faster builds
ccache --max-size=20G

# Log file to keep compilation log
LOGFILE="${LOGFILE:-./build.log}"

# ===========================================
# UBOOT DTS and DTB
# ===========================================

# Set U-Boot DTB
UBOOT_DTB_NAME="imx8mp-var-dart-dt8mcustomboard.dtb"
UBOOT_DTB_EXTRA="imx8mp-var-dart-dt8mcustomboard-legacy.dtb imx8mp-var-som-symphony.dtb"

# Device Tree Blobs (DTBs) for Variscite boards
DTBS="$UBOOT_DTB_NAME $UBOOT_DTB_EXTRA"

# ===========================================
# UBOOT BUILDING
# ===========================================

# Default directory for boot tools
UBOOT_TOOLS_DIR="${UBOOT_TOOLS_DIR:-imx-boot-tools}"

# Set imx-mkimage boot target
UBOOT_SOC_TARGET="iMX8MP"
UBOOT_TARGETS="flash_evk"

# Compiler CC
UBOOT_MAKE_CC="gcc"

# Output boot image filename
OUTPUT_IMAGE="imx-boot-sd.bin"

# U-Boot defconfig for Variscite VAR-SOM-MX8M-PLUS
UBOOT_DEFCONFIG="imx8mp_var_dart_defconfig"

# ===========================================
# ===========================================