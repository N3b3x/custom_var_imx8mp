#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# ===========================================
# Variables and Paths
# ===========================================
source ./kernel_imx_env.sh

# Redirect all output to both a log file and the terminal
exec > >(tee -a "$LOGFILE") 2>&1

# Default configurations
VERBOSE=false  # Default to minimal output
DRY_RUN=false  # Dry run mode

ROOTFS_TARBALL=""

BUILD_TARGET="all"  # Default build target
CUSTOM_DTS="all"  # Default to building all DTS files

# ===========================================
# Log and Helper Functions
# ===========================================
log_step() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_and_run() {
  log_step "Running: $*"
  "$@"
}

# ===========================================
# Function to display usage
# ===========================================
usage() {
  echo "Usage: $0 -w <workdir> [-b <branch>] [-d <custom_dts>] [-c] [-f <flash_device>] [-r <rootfs_tarball>] [-n] [-v] [-h]"
  echo "       or use long options:"
  echo "       $0 --workdir <workdir> [--branch <branch>] [--custom-dts <custom-dts>] [--clean] [--flash-device <flash_device>] [--rootfs-tarball <rootfs_tarball>] [--dry-run] [--verbose] [--help]"
  echo ""
  echo "Options:"
  echo "  -w, --workdir        : Working directory (required)"
  echo "  -b, --branch         : Linux kernel branch to use (default: $LINUX_IMX_BRANCH)"
  echo "  -d, --custom-dts     : Custom DTS files to build (comma-separated). Default is all DTS files."
  echo "  -c, --clean          : Run 'make mrproper' to clean kernel build directory"
  echo "  -f, --flash-device   : Block device for the SD card (e.g., /dev/sdX) for flashing"
  echo "  -r, --rootfs-tarball : Path to the root filesystem tarball to flash to the rootfs partition"
  echo "  -n, --dry-run        : Enable dry-run mode for flashing"
  echo "  -v, --verbose        : Enable verbose output"
  echo "  -h, --help           : Display this help message"
  exit 1
}

# ===========================================
# Parse Command-line Arguments
# ===========================================
log_step "Parsing command-line arguments..."

PARSED=$(getopt -o w:b:d:cf:r:nvh --long workdir:,branch:,custom-dts:,clean,flash-device:,rootfs-tarball:,dry-run,verbose,help,build-target: -- "$@")
if [ $? -ne 0 ]; then
  usage
  exit 1
fi
eval set -- "$PARSED"

# Process arguments
while true; do
  case "$1" in
    -w|--workdir)
      WORKDIR=$(realpath "$2")
      shift 2
      ;;
    -b|--branch)
      LINUX_IMX_BRANCH=$2
      shift 2
      ;;
    --build-target)
      BUILD_TARGET=$2
      shift 2
      ;;
    -d|--custom-dts)
      CUSTOM_DTS=$2
      shift 2
      ;;
    -c|--clean)
      CLEAN_KERNEL=true
      shift
      ;;
    -f|--flash-device)
      FLASH_DEVICE=$2
      shift 2
      ;;
    -r|--rootfs-tarball)
      ROOTFS_TARBALL=$2
      shift 2
      ;;
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      break
      ;;
    *)
      log_step "Error: Invalid option '$1'"
      usage
      ;;
  esac
done

# ===========================================
# Validate Critical Variables
# ===========================================
log_step "Validating critical variables..."
if [ -z "$LINUX_IMX_REPO" ]; then
  echo "Error: LINUX_IMX_REPO is not set. Please define the Linux IMX repository URL."
  exit 1
fi

if [ -z "$LINUX_IMX_BRANCH" ]; then
  echo "Error: LINUX_IMX_BRANCH is not set. Please specify the branch to use."
  exit 1
fi

if [ -z "$WORKDIR" ]; then
  log_step "Error: Working directory (-w) is required."
  usage
fi

if [ ! -d "$WORKDIR" ]; then
  log_step "Creating working directory: $WORKDIR"
  mkdir -p "$WORKDIR"
fi

if [ "$BUILD_TARGET" = "flash" ] && [ -z "$FLASH_DEVICE" ]; then
  log_step "Error: Flash target requires a flash device (-f or --flash-device)."
  exit 1
fi

OUTPUT_DIR="$WORKDIR/linux-imx-kernel-output"


# ===========================================
# Check for Required Dependencies
# ===========================================
check_dependencies() {
  log_step "Checking for required dependencies..."
  local dependencies=("git" "make" "gcc" "lsblk" "tar" "tee" "sudo")
  local missing=()
  for cmd in "${dependencies[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -ne 0 ]; then
    log_step "The following dependencies are missing: ${missing[*]}"
    read -p "Would you like to install them? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      log_step "Installing missing dependencies..."
      sudo apt-get install -y "${missing[@]}" || exit 1
    else
      log_step "Dependencies not installed. Exiting."
      exit 1
    fi
  fi
  log_step "All required dependencies are installed."
}

# ===========================================
# Clone or Update Linux IMX Repository
# ===========================================
clone_or_update_linux_imx() {
  if [ -d "$WORKDIR/linux-imx" ]; then
    if [ -d "$WORKDIR/linux-imx/.git" ]; then
      log_step "Repository already exists. Pulling the latest changes..."
      cd "$WORKDIR/linux-imx"
      log_and_run git fetch origin
      log_and_run git checkout $LINUX_IMX_BRANCH
      log_and_run git pull origin $LINUX_IMX_BRANCH
    else
      log_step "Error: $WORKDIR/linux-imx exists but is not a valid Git repository."
      exit 1
    fi
  else
    log_step "Cloning repository..."
    log_and_run git clone --branch $LINUX_IMX_BRANCH $LINUX_IMX_REPO "$WORKDIR/linux-imx"
  fi
  log_step "Linux IMX repository is up to date."
}

# ===========================================
# Build Kernel
# ===========================================
build_kernel() {
  log_step "Starting kernel build process..."
  cd "$WORKDIR/linux-imx"
  export ARCH=$ARCH
  export CROSS_COMPILE=$CROSS_COMPILE

  if [ "$CLEAN_KERNEL" = true ]; then
    log_step "Cleaning kernel build directory with 'make mrproper'..."
    log_and_run make mrproper
  fi

  log_step "Configuring the kernel using defconfig..."
  log_and_run make $LINUX_DEFCONFIG

  log_step "Compiling the kernel..."
  log_and_run make -j$CORES
  log_step "Kernel build completed successfully."
}

# ===========================================
# Build DTS Files
# ===========================================
build_dts() {
  log_step "Starting DTS build process..."
  cd "$WORKDIR/linux-imx"
  export ARCH=$ARCH
  export CROSS_COMPILE=$CROSS_COMPILE

  if [ "$CUSTOM_DTS" = "all" ]; then
    log_step "Building all DTS files..."
    log_and_run make dtbs
  else
    log_step "Building specified DTS files: $CUSTOM_DTS"
    IFS=',' read -ra DTS_ARRAY <<< "$CUSTOM_DTS"
    for dts_file in "${DTS_ARRAY[@]}"; do
      if [ ! -f "arch/$ARCH/boot/dts/$dts_file.dts" ]; then
        log_step "Error: DTS file $dts_file does not exist."
        exit 1
      fi
      log_and_run make "arch/$ARCH/boot/dts/$dts_file.dtb"
    done
  fi
  log_step "DTS build process completed."
}

# ===========================================
# Validate output directory
# ===========================================

validate_output() {
  log_step "Validating build output..."
  if [ ! -f "$OUTPUT_DIR/Image" ] && [ ! -f "$OUTPUT_DIR/Image.gz" ]; then
    log_step "Error: Kernel image not found in $OUTPUT_DIR."
    exit 1
  fi
  if [ ! -d "$OUTPUT_DIR/dts" ]; then
    log_step "Error: DTBs not found in $OUTPUT_DIR."
    exit 1
  fi
  log_step "Build output validation passed."
}


# ===========================================
# Install Kernel and DTBs
# ===========================================
install_kernel_and_dtb() {
  log_step "Installing kernel, modules, and DTBs..."
  
  # Create output directory if it doesn't exist
  if [ ! -d "$OUTPUT_DIR" ]; then
    log_step "Creating output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
  elif [ ! -w "$OUTPUT_DIR" ]; then
    log_step "Error: Output directory '$OUTPUT_DIR' is not writable."
    exit 1
  fi

  for kernel_image in Image Image.gz; do
    if [ -f "$WORKDIR/linux-imx/arch/$ARCH/boot/$kernel_image" ]; then
      log_step "Copying $kernel_image to $OUTPUT_DIR..."
      cp "$WORKDIR/linux-imx/arch/$ARCH/boot/$kernel_image" "$OUTPUT_DIR/"
    fi
  done

  if [ "$CUSTOM_DTS" = "all" ]; then
    log_step "Copying all DTBs to output directory..."
    cp -r "$WORKDIR/linux-imx/arch/$ARCH/boot/dts" "$OUTPUT_DIR/"
  else
    log_step "Copying specified DTBs..."
    mkdir -p "$OUTPUT_DIR/dts"
    IFS=',' read -ra DTS_ARRAY <<< "$CUSTOM_DTS"
    for dts_file in "${DTS_ARRAY[@]}"; do
      cp "$WORKDIR/linux-imx/arch/$ARCH/boot/dts/$dts_file.dtb" "$OUTPUT_DIR/dts/"
    done
  fi

  log_step "Installing kernel modules to root filesystem..."
  ROOTFS_DIR="$WORKDIR/linux-imx-kernel-output/rootfs"
  rm -rf "$ROOTFS_DIR"
  mkdir -p "$ROOTFS_DIR"
  log_and_run make ARCH=$ARCH INSTALL_MOD_PATH="$ROOTFS_DIR" modules_install

  cp -r "$ROOTFS_DIR" "$OUTPUT_DIR/"
  validate_output
  log_step "Kernel, modules, and DTBs installed successfully."
}

# ===========================================
# Helper Functions
# ===========================================
find_partition_by_label() {
  local label_pattern=$1
  lsblk -o LABEL,NAME | awk -v pattern="$label_pattern" '$1 ~ pattern {print "/dev/" $2}'
}

create_and_mount_partitions() {
  log_step "Checking and preparing partitions on $FLASH_DEVICE..."

  BOOT_PART=$(find_partition_by_label "$BOOT_LABEL_PATTERN")
  ROOTFS_PART=$(find_partition_by_label "$ROOTFS_LABEL")

  if [ -z "$BOOT_PART" ]; then
    log_step "Creating BOOT partition..."
    sudo parted "$FLASH_DEVICE" --script mklabel msdos
    sudo parted "$FLASH_DEVICE" --script mkpart primary fat32 1MiB 256MiB
    sudo mkfs.vfat -n "BOOT" "${FLASH_DEVICE}1"
    BOOT_PART="${FLASH_DEVICE}1"
  fi

  if [ -z "$ROOTFS_PART" ]; then
    log_step "Creating rootfs partition..."
    sudo parted "$FLASH_DEVICE" --script mkpart primary ext4 256MiB 100%
    sudo mkfs.ext4 -L "$ROOTFS_LABEL" "${FLASH_DEVICE}2"
    ROOTFS_PART="${FLASH_DEVICE}2"
  fi

  BOOT_MOUNT=$(mktemp -d)
  ROOTFS_MOUNT=$(mktemp -d)
  log_and_run sudo mount "$BOOT_PART" "$BOOT_MOUNT"
  log_and_run sudo mount "$ROOTFS_PART" "$ROOTFS_MOUNT"
}

# Flash the kernel image and modules
flash_kernel_and_modules() {
  log_step "Flashing kernel image and modules to SD card..."
  cd "$WORKDIR/linux-imx"

  # Copy the kernel image to the BOOT partition
  echo "Copying $KERNEL_IMAGE to BOOT partition..."
  echo "Copying Kernel Image [$KERNEL_IMAGE] to BOOT partition..."
  sudo cp "arch/$ARCH/boot/$KERNEL_IMAGE" "$BOOT_MOUNT/"

  # Install modules to the rootfs partition
  log_step "Installing kernel modules to rootfs..."
  sudo cp -r "$OUTPUT_DIR/rootfs/"* "$ROOTFS_MOUNT/"
}

# Flash the device tree blobs
flash_device_trees() {
  log_step "Flashing device tree blobs to BOOT partition..."
  sudo cp "$OUTPUT_DIR/dts/"*.dtb "$BOOT_MOUNT/"
}

unmount_partitions() {
  log_step "Unmounting partitions..."
  log_and_run sudo umount "$BOOT_MOUNT"
  log_and_run sudo umount "$ROOTFS_MOUNT"
  rm -rf "$BOOT_MOUNT" "$ROOTFS_MOUNT"
}

# ===========================================
# Flash SD Card
# ===========================================

flash_sd_card() {
  create_and_mount_partitions
  flash_kernel_and_modules
  flash_device_trees
  unmount_partitions
  log_step "SD card flashing completed successfully."
}

# ===========================================
# Clean Build Artifacts
# ===========================================
clean_build() {
  log_step "Cleaning build artifacts..."
  rm -rf "$WORKDIR/linux-imx" "$OUTPUT_DIR"
  log_step "Build artifacts cleaned successfully."
}

# ===========================================
# Summary of Build Process
# ===========================================
summary() {
  log_step "Build Summary:"
  echo "  Working Directory: $WORKDIR"
  echo "  Output Directory: $OUTPUT_DIR"
  echo "  Build Target: $BUILD_TARGET"
  [ -n "$FLASH_DEVICE" ] && echo "  Flash Device: $FLASH_DEVICE"
  [ -n "$ROOTFS_TARBALL" ] && echo "  RootFS Tarball: $ROOTFS_TARBALL"
  log_step "Linux IMX build process completed successfully."
}

# ===========================================
# Main Execution
# ===========================================
main() {
  log_step "Starting the Linux IMX build process..."
  check_dependencies

  case $BUILD_TARGET in
    "kernel")
      build_kernel
      ;;
    "dts")
      build_dts
      ;;
    "build")
      build_kernel
      build_dts
      install_kernel_and_dtb
      ;;
    "flash")
      if [ -z "$FLASH_DEVICE" ]; then
        log_step "Error: Flash target requires a flash device (-f or --flash-device)."
        exit 1
      fi
      flash_sd_card
      ;;
    "clean")
      clean_build
      ;;
    "all")
      clone_or_update_linux_imx
      build_kernel
      build_dts
      install_kernel_and_dtb
      if [ -n "$FLASH_DEVICE" ]; then
        flash_sd_card
      else
        log_step "Build completed. No flash device specified; skipping flashing step."
      fi
      ;;
    *)
      log_step "Error: Invalid build target '$BUILD_TARGET'"
      usage
      ;;
  esac

  log_step "Linux IMX build process completed successfully."
  summary
}

main
