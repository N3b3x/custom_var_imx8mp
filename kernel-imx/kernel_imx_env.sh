#!/bin/bash
# Kernel Environment Variables

# ===========================================
# Variables and Paths
# ===========================================

# Linux repository for the IMX chips
LINUX_IMX_REPO="https://github.com/varigit/linux-imx.git"
LINUX_IMX_BRANCH="lf-6.6.y_var01"  # Change this as per your requirement

# Cross Compiling settings
CROSS_COMPILE="aarch64-linux-gnu-"
ARCH="arm64"

# U-Boot defconfig for Variscite VAR-SOM-MX8M-PLUS
LINUX_DEFCONFIG="imx_v8_defconfig"

# Number of cores for parallel build
CORES=$(nproc)

# WORKDIR (Mandatory)
WORKDIR=""
OUTPUT_DIR=""

# CLEAN_KERNEL flag (default: false)
CLEAN_KERNEL=false

# Flashing variables
FLASH_DEVICE=""
ROOTFS_LABEL="rootfs"
BOOT_LABEL_PATTERN="BOOT*"

# ===========================================
# ===========================================