#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

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
# Functions
# ===========================================

# Function to display usage
usage() {
  echo "Usage: $0 -w <workdir> [-b <branch>] [-d <custom_dts>] [-c] [-f <flash_device>] [-h]"
  echo "  -w <workdir>       : Working directory (required)"
  echo "  -b <branch>        : Linux kernel branch to use (default: $LINUX_IMX_BRANCH)"
  echo "  -d <custom_dts>    : Custom DTS files to build (comma-separated). Default is all DTS files."
  echo "  -c                 : Run 'make mrproper' to clean kernel build directory"
  echo "  -f <flash_device>  : Block device for the SD card (e.g., /dev/sdX) for flashing"
  echo "  -h                 : Display this help message"
  exit 1
}

# Parse command-line arguments
CUSTOM_DTS="all"  # Default to building all DTS files
while getopts "w:b:d:cf:h" opt; do
  case ${opt} in
    w ) WORKDIR=$OPTARG ;;
    b ) LINUX_IMX_BRANCH=$OPTARG ;;
    d ) CUSTOM_DTS=$OPTARG ;;
    c ) CLEAN_KERNEL=true ;;
    f ) FLASH_DEVICE=$OPTARG ;;
    h ) usage ;;
    \? ) usage ;;
  esac
done

# Validate mandatory WORKDIR
if [ -z "$WORKDIR" ]; then
  echo "Error: Working directory (-w) is required."
  usage
fi

# Set OUTPUT_DIR based on WORKDIR
OUTPUT_DIR="$WORKDIR/linux-imx-kernel-output"

# Clone or update the Linux IMX repository
clone_or_update_linux_imx() {
  if [ -d "$WORKDIR/linux-imx" ]; then
    echo "linux-imx repository already exists. Pulling the latest changes..."
    cd "$WORKDIR/linux-imx"
    git fetch origin
    git checkout $LINUX_IMX_BRANCH
    git pull origin $LINUX_IMX_BRANCH
  else
    echo "Cloning linux-imx repository (branch: $LINUX_IMX_BRANCH) into $WORKDIR..."
    mkdir -p "$WORKDIR"
    git clone --branch $LINUX_IMX_BRANCH $LINUX_IMX_REPO "$WORKDIR/linux-imx"
  fi
}

# Build the kernel
build_kernel() {
  echo "Building the linux-imx kernel..."
  cd "$WORKDIR/linux-imx"
  export ARCH=$ARCH
  export CROSS_COMPILE=$CROSS_COMPILE

  # Run 'make mrproper' if CLEAN_KERNEL is true
  if [ "$CLEAN_KERNEL" = true ]; then
    echo "Running 'make mrproper' to clean kernel build directory..."
    make mrproper
  fi

  # Configure the kernel (default defconfig)
  make $LINUX_DEFCONFIG

  # Build the kernel
  make -j$CORES
  echo "Kernel build completed successfully."
}

# Build DTS files
build_dts() {
  echo "Building DTS files..."
  cd "$WORKDIR/linux-imx"
  export ARCH=$ARCH
  export CROSS_COMPILE=$CROSS_COMPILE

  if [ "$CUSTOM_DTS" = "all" ]; then
    echo "Building all DTS files..."
    make dtbs
  else
    echo "Building specific DTS files: $CUSTOM_DTS"
    IFS=',' read -ra DTS_ARRAY <<< "$CUSTOM_DTS"
    for dts_file in "${DTS_ARRAY[@]}"; do
      make "arch/$ARCH/boot/dts/$dts_file.dtb"
    done
  fi

  echo "DTS files build completed."
}

# Install or package the kernel and DTBs
install_kernel_and_dtb() {
  echo "Installing the built kernel, modules, and DTBs..."

  # Set up the output directory
  mkdir -p "$OUTPUT_DIR"

  # Copy the kernel images
  echo "Copying kernel images..."
  if [ -f "$WORKDIR/linux-imx/arch/$ARCH/boot/Image" ]; then
    cp "$WORKDIR/linux-imx/arch/$ARCH/boot/Image" "$OUTPUT_DIR/"
  fi

  if [ -f "$WORKDIR/linux-imx/arch/$ARCH/boot/zImage" ]; then
    cp "$WORKDIR/linux-imx/arch/$ARCH/boot/zImage" "$OUTPUT_DIR/"
  fi

  if [ -f "$WORKDIR/linux-imx/arch/$ARCH/boot/Image.gz" ]; then
    cp "$WORKDIR/linux-imx/arch/$ARCH/boot/Image.gz" "$OUTPUT_DIR/"
  fi

  if [ -f "$WORKDIR/linux-imx/arch/$ARCH/boot/uImage" ]; then
    cp "$WORKDIR/linux-imx/arch/$ARCH/boot/uImage" "$OUTPUT_DIR/"
  fi

  # Handle DTBs
  if [ "$CUSTOM_DTS" = "all" ]; then
    echo "Copying all DTBs..."
    cp -r "$WORKDIR/linux-imx/arch/$ARCH/boot/dts" "$OUTPUT_DIR/"
  else
    echo "Copying specific DTBs..."
    mkdir -p "$OUTPUT_DIR/dts"
    IFS=',' read -ra DTS_ARRAY <<< "$CUSTOM_DTS"
    for dts_file in "${DTS_ARRAY[@]}"; do
      cp "$WORKDIR/linux-imx/arch/$ARCH/boot/dts/$dts_file.dtb" "$OUTPUT_DIR/dts/"
    done
  fi

  # Create and clean up the rootfs directory
  echo "Setting up temporary root filesystem for modules installation..."
  ROOTFS_DIR="$WORKDIR/linux-imx-kernel-output/rootfs"
  rm -rf "$ROOTFS_DIR"  # Clean up any previous rootfs
  mkdir -p "$ROOTFS_DIR"

  # Install kernel modules to rootfs
  echo "Installing kernel modules to $ROOTFS_DIR..."
  cd "$WORKDIR/linux-imx"
  make ARCH=$ARCH \
    INSTALL_MOD_STRIP=1 \
    INSTALL_MOD_PATH="$ROOTFS_DIR" \
    modules_install

  # Copy rootfs to the output directory
  cp -r "$ROOTFS_DIR" "$OUTPUT_DIR/"

  echo "Kernel, modules, and DTBs installed successfully in $OUTPUT_DIR."
}

# Flash the SD card if specified
flash_sd_card() {
  echo "Flashing SD card..."
  BOOT_PART=$(lsblk -o LABEL,NAME | awk -v label="$BOOT_LABEL_PATTERN" '$1 ~ label {print "/dev/" $2}')
  ROOTFS_PART=$(lsblk -o LABEL,NAME | awk -v label="$ROOTFS_LABEL" '$1 ~ label {print "/dev/" $2}')

  if [ -z "$BOOT_PART" ] || [ -z "$ROOTFS_PART" ]; then
    echo "Error: Could not find BOOT or rootfs partitions on $FLASH_DEVICE."
    exit 1
  fi

  echo "Mounting BOOT partition..."
  BOOT_MOUNT=$(mktemp -d)
  sudo mount "$BOOT_PART" "$BOOT_MOUNT"

  echo "Mounting rootfs partition..."
  ROOTFS_MOUNT=$(mktemp -d)
  sudo mount "$ROOTFS_PART" "$ROOTFS_MOUNT"

  echo "Copying kernel and DTBs to BOOT partition..."
  sudo cp "$OUTPUT_DIR/zImage" "$BOOT_MOUNT/"
  sudo cp "$OUTPUT_DIR/dts/*.dtb" "$BOOT_MOUNT/"

  echo "Copying modules to rootfs partition..."
  sudo cp -r "$OUTPUT_DIR/rootfs/*" "$ROOTFS_MOUNT/"

  echo "Unmounting partitions..."
  sudo umount "$BOOT_MOUNT"
  sudo umount "$ROOTFS_MOUNT"
  rm -rf "$BOOT_MOUNT" "$ROOTFS_MOUNT"

  echo "SD card flashing completed."
}

# ===========================================
# Main Execution
# ===========================================
main() {
  echo "Starting the linux-imx build process..."
  clone_or_update_linux_imx
  build_kernel
  build_dts
  install_kernel_and_dtb

  # Flash the SD card if specified
  if [ -n "$FLASH_DEVICE" ]; then
    flash_sd_card
  fi

  echo "Build process completed. Kernel, DTBs, and modules are ready in $OUTPUT_DIR."
}

main
