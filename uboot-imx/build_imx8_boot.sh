#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# ===========================================
# Variables and Paths
# ===========================================
source ./uboot_imx_env.sh

# Redirect all output to both a log file and the terminal
exec > >(tee -a "$LOGFILE") 2>&1

VERBOSE=false  # Default to minimal output
DRY_RUN=false

# ===========================================
# Log function
# ===========================================
log_step() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_and_run() {
  log_step "Running: $*"
  "$@"
}

# ===========================================
# Display usage information
# ===========================================
usage() {
  echo "Usage: $0 -w <workdir> [-d <device>] [-b <build_target>] [-n] [-v] [-h]"
  echo "  -w <workdir>      : Working directory for the build process"
  echo "  -d <device>       : Target device (e.g., /dev/sdX) for flashing the image"
  echo "  -b <build_target> : Specific build target (uboot, atf, image, flash, all, clean:<target>). Default is 'all'"
  echo "  -n                : Enable dry-run mode for flashing"
  echo "  -v                : Enable verbose output"
  echo "  -h                : Display this help message"
  exit 1
}

# ===========================================
# Parse command-line arguments
# ===========================================
BUILD_TARGET="all"
DEVICE=""
while getopts "w:d:b:nvh" opt; do
  case ${opt} in
    w ) WORKDIR=$OPTARG ;;
    d ) DEVICE=$OPTARG ;;
    b ) BUILD_TARGET=$OPTARG ;;
    n ) DRY_RUN=true ;;
    v ) VERBOSE=true ;;
    h ) usage ;;
    \? ) usage ;;
  esac
done

if [ -z "$WORKDIR" ]; then
  usage
fi

if [ ! -d "$WORKDIR" ]; then
  mkdir -p "$WORKDIR"
fi

# ===========================================
# Check for required dependencies
# ===========================================
check_dependencies() {
  local dependencies=("git" "wget" "dd" "udevadm" "make" "gcc" "tee")
  local missing=()
  for cmd in "${dependencies[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -ne 0 ]; then
    echo "The following dependencies are missing: ${missing[*]}"
    read -p "Would you like to install them? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      sudo apt-get install -y "${missing[@]}" || exit 1
    else
      echo "Dependencies not installed. Exiting."
      exit 1
    fi
  fi
}

# ===========================================
# Clone or update a repository
# ===========================================
clone_or_update_repo() {
  local repo_url=$1
  local branch=$2
  local dest_dir=${3:-.}

  if $VERBOSE; then
    echo "Cloning/updating repository: $repo_url, branch: $branch, into $dest_dir"
  fi

  if [ -d "$dest_dir" ]; then
    if [ -d "$dest_dir/.git" ]; then
      echo "Repository $dest_dir already exists. Pulling the latest changes..."
      cd "$dest_dir"
      git fetch origin
      git checkout $branch
      git pull origin $branch || { echo "Error: Failed to pull latest changes from $branch"; exit 1; }
    else
      echo "Error: Directory $dest_dir exists but is not a Git repository."
      exit 1
    fi
  else
    echo "Cloning repository $repo_url (branch: $branch) into $dest_dir..."
    git clone --branch $branch $repo_url $dest_dir || { echo "Error: Failed to clone repository $repo_url"; exit 1; }
  fi
}

# ===========================================
# Build U-Boot
# ===========================================
prepare_and_build_uboot_imx() {
  log_step "Building U-Boot..."
  local uboot_dir="$WORKDIR/uboot-imx"

  clone_or_update_repo "$UBOOT_REPO" "$UBOOT_BRANCH" "$uboot_dir"

  cd "$uboot_dir"
  make mrproper
  export ARCH=$ARCH_ARM64
  export CROSS_COMPILE=$CROSS_COMPILE_ARM64
  make $UBOOT_DEFCONFIG
  make -j$(nproc)
  log_step "U-Boot built successfully."
}

# ===========================================
# Prepare DDR firmware
# ===========================================
prepare_ddr_firmware() {
  log_step "Preparing DDR firmware..."
  local firmware_dir="$WORKDIR/$UBOOT_TOOLS_DIR"

  mkdir -p "$firmware_dir"
  cd "$firmware_dir"

  if [ ! -f firmware-imx-8.18.bin ]; then
    wget "$DDR_FIRMWARE_URL" -O firmware-imx-8.18.bin
    chmod +x firmware-imx-8.18.bin
    ./firmware-imx-8.18.bin --auto-accept
  fi

  cp firmware-imx-8.18/firmware/ddr/synopsys/* "$firmware_dir/"
  log_step "DDR firmware prepared successfully."
}

# ===========================================
# Build ARM Trusted Firmware (ATF)
# ===========================================
prepare_and_build_atf() {
  log_step "Building ARM Trusted Firmware (ATF)..."
  local atf_dir="$WORKDIR/$UBOOT_TOOLS_DIR/imx-atf"

  clone_or_update_repo "$ATF_REPO" "$ATF_BRANCH" "$atf_dir"

  cd "$atf_dir"
  export ARCH=$ARCH_ARM64
  export CROSS_COMPILE=$CROSS_COMPILE_ARM64
  unset LDFLAGS

  # Build ATF
  if $VERBOSE; then
    make -j$(nproc) V=1 PLAT=imx8mp bl31
  else
    make -j$(nproc) PLAT=imx8mp bl31
  fi

  # Ensure the output file exists
  if [ ! -f "build/imx8mp/release/bl31.bin" ]; then
    echo "Error: bl31.bin not found after ATF build."
    exit 1
  fi

  # Copy to the tools directory
  cp build/imx8mp/release/bl31.bin "$WORKDIR/$UBOOT_TOOLS_DIR"
  log_step "ATF built successfully."
}

# ===========================================
# Build Boot Image
# ===========================================
prepare_and_build_boot_image() {
  log_step "Building boot image..."
  local mkimage_dir="$WORKDIR/$UBOOT_TOOLS_DIR/imx-mkimage"

  clone_or_update_repo "$IMX_MKIMAGE_REPO" "$IMX_MKIMAGE_BRANCH" "$mkimage_dir"

  cd "$mkimage_dir"

  # Clean previous builds
  log_step "Cleaning previous boot image build artifacts..."
  make -f soc.mak clean

  # Build the boot image
  if $VERBOSE; then
    make -j$(nproc) V=1 -f soc.mak \
      SOC="$UBOOT_SOC_TARGET" \
      dtbs="$DTBS" \
      OUTIMG="$OUTPUT_IMAGE" \
      "$UBOOT_TARGETS"
  else
    make -j$(nproc) -f soc.mak \
      SOC="$UBOOT_SOC_TARGET" \
      dtbs="$DTBS" \
      OUTIMG="$OUTPUT_IMAGE" \
      "$UBOOT_TARGETS"
  fi

  # Ensure the output file exists
  if [ ! -f "$OUTPUT_IMAGE" ]; then
    echo "Error: Boot image ($OUTPUT_IMAGE) not generated."
    exit 1
  fi

  log_step "Boot image built successfully."
}

# ===========================================
# Clean Build Artifacts
# ===========================================
clean_build() {
  log_step "Starting cleanup..."

  for target in "$@"; do
    case "$target" in
      "uboot") rm -rf "$WORKDIR/uboot-imx"; echo "Cleaned U-Boot artifacts." ;;
      "atf") rm -rf "$WORKDIR/$UBOOT_TOOLS_DIR/imx-atf"; echo "Cleaned ATF artifacts." ;;
      "image") rm -rf "$WORKDIR/$UBOOT_TOOLS_DIR/imx-mkimage" "$WORKDIR/$UBOOT_TOOLS_DIR/$OUTPUT_IMAGE"; echo "Cleaned boot image artifacts." ;;
      "all") rm -rf "$WORKDIR/uboot-imx" "$WORKDIR/$UBOOT_TOOLS_DIR" "$LOGFILE"; echo "Cleaned all build artifacts." ;;
      *) echo "Invalid clean target specified: $target"; exit 1 ;;
    esac
  done

  log_step "Cleanup completed."
}

# ===========================================
# Flash the Built Image
# ===========================================
flash_image() {
  local boot_image="$WORKDIR/$UBOOT_TOOLS_DIR/$OUTPUT_IMAGE"

  if [ ! -f "$boot_image" ]; then
    echo "Error: Boot image '$boot_image' does not exist."
    exit 1
  fi

  if [ ! -b "$DEVICE" ]; then
    echo "Error: Target device '$DEVICE' is not a valid block device."
    echo "Available devices:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
    exit 1
  fi

  echo "Detected target device: $DEVICE"
  read -p "Are you sure you want to flash the boot image to $DEVICE? This will overwrite existing data. (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
  fi

  if $DRY_RUN; then
    echo "Dry run enabled: Flashing skipped. Command would be:"
    echo "dd if=$boot_image of=$DEVICE bs=1K seek=32 conv=fsync"
    return
  fi

  echo "Flashing boot image to $DEVICE..."
  log_and_run sudo dd if="$boot_image" of="$DEVICE" bs=1K seek=32 conv=fsync
  sync
  echo "Boot image flashed successfully to $DEVICE."
}

# ===========================================
# Main Script Execution
# ===========================================
main() {
  check_dependencies

  case $BUILD_TARGET in
    "uboot")
      prepare_and_build_uboot_imx
      ;;
    "atf")
      prepare_and_build_atf
      ;;
    "image")
      prepare_and_build_boot_image
      ;;
    "flash")
      if [ -z "$DEVICE" ]; then
        echo "Error: No device specified for flashing."
        exit 1
      fi
      flash_image
      ;;
    clean:*)
      clean_build "${BUILD_TARGET#clean:}"
      ;;
    "all")
      prepare_and_build_uboot_imx
      prepare_ddr_firmware
      prepare_and_build_atf
      prepare_and_build_boot_image
      if [ -n "$DEVICE" ]; then
        flash_image
      else
        echo "Build completed. No device specified for flashing. Skipping flashing step."
      fi
      ;;
    *)
      echo "Error: Invalid build target '$BUILD_TARGET'"
      usage
      ;;
  esac

  log_step "Process completed successfully."
}

main
