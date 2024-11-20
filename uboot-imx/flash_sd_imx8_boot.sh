#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# ===========================================
# Define constants
# ===========================================

# Output boot image filename
OUTPUT_IMAGE="imx-boot-sd.bin"

# ===========================================
# Usage function to display help message
# ===========================================
usage() {
  echo "Usage: $0 -w <workdir> -d <device> [-h]"
  echo "  -w <workdir>  : Working directory where the boot image is located"
  echo "  -d <device>   : Target device (e.g., /dev/sdX) for flashing the image"
  echo "  -h            : Display this help message"
  exit 1
}

# ===========================================
# Parse command-line arguments
# ===========================================
while getopts "w:d:h" opt; do
  case ${opt} in
    w )
      WORKDIR=$OPTARG  # Working directory
      ;;
    d )
      DEVICE=$OPTARG  # Target device
      ;;
    h )
      usage
      ;;
    \? )
      usage
      ;;
  esac
done

# Ensure mandatory arguments are provided
if [ -z "$WORKDIR" ] || [ -z "$DEVICE" ]; then
  usage
fi

# ===========================================
# Validate inputs and flash the boot image
# ===========================================
flash_boot_image() {
  local workdir="$1"
  local target_device="$2"

  # Check if the boot image exists
  if [ ! -f "$workdir/imx-boot-tools/$OUTPUT_IMAGE" ]; then
    echo "Error: Boot image '$workdir/imx-boot-tools/$OUTPUT_IMAGE' does not exist."
    exit 1
  fi

  # Verify that the target device exists and is a block device
  if [ ! -b "$target_device" ]; then
    echo "Error: Target device '$target_device' is not a valid block device."
    exit 1
  fi

  # Determine if the device is an SD card or USB drive
  local device_type
  if udevadm info --query=property --name="$target_device" | grep -q "ID_DRIVE_FLASH_SD"; then
    device_type="SD card"
  elif udevadm info --query=property --name="$target_device" | grep -q "ID_BUS=usb"; then
    device_type="USB drive"
  else
    device_type="unknown"
  fi

  # Confirm with the user before flashing
  echo "Detected $device_type: $target_device"
  read -p "Are you sure you want to flash the boot image to $target_device? This will overwrite existing data. (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
  fi

  # Flash the boot image to the target device
  echo "Flashing boot image to $target_device..."
  if sudo dd if="$workdir/imx-boot-tools/$OUTPUT_IMAGE" of="$target_device" bs=1K seek=32 conv=fsync; then
    sync
    echo "Boot image flashed successfully to $target_device."
  else
    echo "Error: Failed to flash the boot image to $target_device."
    exit 1
  fi
}

# ===========================================
# Main execution
# ===========================================
flash_boot_image "$WORKDIR" "$DEVICE"
