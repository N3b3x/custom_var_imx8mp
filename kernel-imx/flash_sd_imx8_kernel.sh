#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# ===========================================
# Variables
# ===========================================

ROOTFS_LABEL="rootfs"
BOOT_LABEL_PATTERN="BOOT*"  # Pattern to detect BOOT partitions

MEDIA_DEVICE=""
WORKDIR=""
LINUX_BUILD_DIR=""

ARCH="arm64"
KERNEL_IMAGE="zImage"

CUSTOM_DTS="imx6ul*var*.dtb"

# ===========================================
# Functions
# ===========================================

# Function to display usage
usage() {
  echo "Usage: $0 -m <media_device> -w <workdir> [-k <kernel_image>] [-d <custom_dts>] [-h]"
  echo "  -m <media_device> : The block device for the SD card (e.g., /dev/sdX)"
  echo "  -w <workdir>      : Working directory containing the build artifacts"
  echo "  -k <kernel_image> : Kernel image to copy (default: $KERNEL_IMAGE)"
  echo "  -d <custom_dts>   : Custom DTS files to copy (default: $CUSTOM_DTS)"
  echo "  -h                : Display this help message"
  exit 1
}

# Parse command-line arguments
while getopts "m:w:k:d:h" opt; do
  case ${opt} in
    m ) MEDIA_DEVICE=$OPTARG ;;
    w ) WORKDIR=$OPTARG ;;
    k ) KERNEL_IMAGE=$OPTARG ;;
    d ) CUSTOM_DTS=$OPTARG ;;
    h ) usage ;;
    \? ) usage ;;
  esac
done

# Ensure required arguments are provided
if [ -z "$MEDIA_DEVICE" ] || [ -z "$WORKDIR" ]; then
  echo "Error: Media device (-m) and working directory (-w) are required."
  usage
fi

# Ensure the media device exists
if [ ! -b "$MEDIA_DEVICE" ]; then
  echo "Error: Media device $MEDIA_DEVICE not found."
  exit 1
fi

# Ensure the working directory exists
LINUX_BUILD_DIR="$WORKDIR/linux-imx"
if [ ! -d "$LINUX_BUILD_DIR" ]; then
  echo "Error: Linux build directory $LINUX_BUILD_DIR not found."
  exit 1
fi

# Find partitions by label pattern
find_partition_by_label() {
  local label_pattern=$1
  lsblk -o LABEL,NAME | awk -v pattern="$label_pattern" '$1 ~ pattern {print "/dev/" $2}'
}

# Create and mount partitions if they don't exist
create_and_mount_partitions() {
  echo "Checking and preparing partitions on $MEDIA_DEVICE..."

  # Detect existing partitions by labels
  BOOT_PART=$(find_partition_by_label "$BOOT_LABEL_PATTERN")
  ROOTFS_PART=$(find_partition_by_label "$ROOTFS_LABEL")

  # Create BOOT and rootfs partitions if not present
  if [ -z "$BOOT_PART" ]; then
    echo "Creating BOOT partition..."
    sudo parted "$MEDIA_DEVICE" --script mklabel msdos
    sudo parted "$MEDIA_DEVICE" --script mkpart primary fat32 1MiB 256MiB
    sudo mkfs.vfat -n "BOOT" "${MEDIA_DEVICE}1"
    BOOT_PART="${MEDIA_DEVICE}1"
  fi

  if [ -z "$ROOTFS_PART" ]; then
    echo "Creating rootfs partition..."
    sudo parted "$MEDIA_DEVICE" --script mkpart primary ext4 256MiB 100%
    sudo mkfs.ext4 -L "$ROOTFS_LABEL" "${MEDIA_DEVICE}2"
    ROOTFS_PART="${MEDIA_DEVICE}2"
  fi

  # Mount the partitions
  BOOT_MOUNT=$(mktemp -d)
  ROOTFS_MOUNT=$(mktemp -d)
  sudo mount "$BOOT_PART" "$BOOT_MOUNT"
  sudo mount "$ROOTFS_PART" "$ROOTFS_MOUNT"
}

# Flash the kernel image and modules
flash_kernel_and_modules() {
  echo "Flashing kernel image and modules to SD card..."
  cd "$LINUX_BUILD_DIR"

  # Copy the kernel image to the BOOT partition
  echo "Copying $KERNEL_IMAGE to BOOT partition..."
  sudo cp "arch/$ARCH/boot/$KERNEL_IMAGE" "$BOOT_MOUNT/"

  # Install modules to the rootfs partition
  echo "Installing kernel modules to rootfs..."
  sudo cp -r "$WORKDIR/linux-imx-kernel-output/rootfs/*" "$ROOTFS_MOUNT/"
}

# Flash the device tree blobs
flash_device_trees() {
  echo "Flashing device tree blobs to BOOT partition..."
  cd "$LINUX_BUILD_DIR"

  # Copy DTS files
  echo "Copying device tree blobs: $CUSTOM_DTS..."
  sudo cp "arch/$ARCH/boot/dts/$CUSTOM_DTS" "$BOOT_MOUNT/"
}

# Unmount partitions
unmount_partitions() {
  echo "Unmounting partitions..."
  sudo umount "$BOOT_MOUNT"
  sudo umount "$ROOTFS_MOUNT"
  rm -rf "$BOOT_MOUNT"
  rm -rf "$ROOTFS_MOUNT"
}

# ===========================================
# Main Execution
# ===========================================
main() {
  create_and_mount_partitions
  flash_kernel_and_modules
  flash_device_trees
  unmount_partitions
  echo "Flashing completed successfully."
}

main
