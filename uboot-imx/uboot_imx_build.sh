#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# ===========================================
# Variables and Paths
# ===========================================
# Resolve the script's actual directory, following symlinks if necessary
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SOURCE" ]; do
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  # If the symlink is relative, resolve it relative to the current SCRIPT_DIR
  [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"

# Source the environment script if it exists
if [ -f "$SCRIPT_DIR/uboot_imx_env.sh" ]; then
  echo "Sourcing environment script: $SCRIPT_DIR/uboot_imx_env.sh"
  source "$SCRIPT_DIR/uboot_imx_env.sh"
else
  echo "Error: Environment script not found at $SCRIPT_DIR/uboot_imx_env.sh"
  exit 1
fi

# Continue with the rest of the script
echo "Environment script sourced successfully. Proceeding..."


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
  echo "  -b <build_target> : Specific build target (prep, uboot, atf, image, flash, all, clean:<target>). Default is 'all'"
  echo "  -d <device>       : Target device (e.g., /dev/sdX) for flashing the image"
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

# Ensure WORKDIR is set
if [ -z "$WORKDIR" ]; then
  usage
fi

# Ensure WORKDIR exists
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
  local repo_url=$1       # Repository URL
  local branch=$2         # Branch to checkout
  local dest_dir=${3:-.}  # Destination directory (default: current directory)

  if $VERBOSE; then
    echo "Cloning/updating repository: $repo_url, branch: $branch, into $dest_dir"
  fi

  if [ -d "$dest_dir" ]; then
    if [ -d "$dest_dir/.git" ]; then
      echo "Repository $dest_dir already exists. Pulling the latest changes..."
      cd "$dest_dir" || { echo "Error: Failed to change directory to $dest_dir"; exit 1; }
      git fetch origin
      git checkout $branch || { echo "Error: Failed to checkout branch $branch"; exit 1; }
      git pull origin $branch || { echo "Error: Failed to pull latest changes for branch $branch"; exit 1; }
    else
      if [ -z "$(ls -A "$dest_dir")" ]; then
        echo "Directory $dest_dir is empty. Cloning repository $repo_url (branch: $branch)..."
        git clone --branch "$branch" "$repo_url" "$dest_dir" || { echo "Error: Failed to clone repository $repo_url"; exit 1; }
      else
        echo "Error: Directory $dest_dir exists but is not empty or a Git repository."
        echo "Please resolve this issue before proceeding."
        exit 1
      fi
    fi
  else
    echo "Cloning repository $repo_url (branch: $branch) into $dest_dir..."
    git clone --branch "$branch" "$repo_url" "$dest_dir" || { echo "Error: Failed to clone repository $repo_url"; exit 1; }
  fi
}


# ===========================================
# Prepare boot tools directory
# ===========================================
prepare_boot_tools_dir() {
    echo "Creating imx-boot-tools directory..."
    mkdir -p "$WORKDIR/imx-boot-tools"
    echo "imx-boot-tools directory created successfully."
}

# ===========================================
# Prepare Environment
# ===========================================
prepare() {
  log_step "Preparing environment..."
  
  # Prepare U-Boot
  clone_or_update_repo "$UBOOT_REPO" "$UBOOT_BRANCH" "$WORKDIR/uboot-imx"

  # Prepare boot tools directory
  prepare_boot_tools_dir

  local tools_dir="$WORKDIR/$UBOOT_TOOLS_DIR"

  # Prepare ATF
  clone_or_update_repo "$ATF_REPO" "$ATF_BRANCH" "$tools_dir/imx-atf"

  # Prepare META BSP
  clone_or_update_repo "$META_BSP_REPO" "$META_BSP_BRANCH" "$tools_dir/meta-bsp"

  # Prepare imx-mkimage
  clone_or_update_repo "$IMX_MKIMAGE_REPO" "$IMX_MKIMAGE_BRANCH" "$tools_dir/imx-mkimage"

  # Prepare DDR firmware
  prepare_ddr_firmware

  log_step "Environment prepared successfully."
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

  # Download and execute the firmware if not already present
  if [ ! -f "firmware-imx-${DDR_FIRMWARE_VERSION}.bin" ]; then
    echo "Downloading DDR firmware from $DDR_FIRMWARE_URL"
    wget "$DDR_FIRMWARE_URL" -O "firmware-imx-${DDR_FIRMWARE_VERSION}.bin"
    chmod +x "firmware-imx-${DDR_FIRMWARE_VERSION}.bin"
    "./firmware-imx-${DDR_FIRMWARE_VERSION}.bin" --auto-accept
  else
    echo "Firmware firmware-imx-${DDR_FIRMWARE_VERSION}.bin already exists. Skipping download."
  fi


  cp $firmware_dir/firmware-imx-${DDR_FIRMWARE_VERSION}/firmware/ddr/synopsys/* "$firmware_dir/"
  log_step "DDR firmware prepared successfully."
}

# ===========================================
# Prepare and build ARM Trusted Firmware (ATF)
# ===========================================
prepare_and_build_atf() {
  log_step "Preparing and building ARM Trusted Firmware (ATF)..."

  local boot_tools_dir="$WORKDIR/$UBOOT_TOOLS_DIR"
  local atf_dir="$boot_tools_dir/imx-atf"
  local bsp_dir="$boot_tools_dir/meta-variscite-bsp"
  local mkimage_dir="$boot_tools_dir/imx-mkimage"

  # Ensure imx-boot-tools directory exists
  mkdir -p "$boot_tools_dir"

  # Clone or update repositories
  clone_or_update_repo "$ATF_REPO" "$ATF_BRANCH" "$atf_dir"
  clone_or_update_repo "$META_VARISCITE_BSP_REPO" "$META_VARISCITE_BSP_BRANCH" "$bsp_dir"

  # Apply patches to imx-mkimage
  log_step "Preparing and patching imx-mkimage..."
  clone_or_update_repo "$IMX_MKIMAGE_REPO" "$IMX_MKIMAGE_BRANCH" "$mkimage_dir"

  cd "$mkimage_dir"
  local patches=(
    "$bsp_dir/recipes-bsp/imx-mkimage/imx-boot/0001-iMX8M-soc-allow-dtb-override.patch"
    "$bsp_dir/recipes-bsp/imx-mkimage/imx-boot/0002-iMX8M-soc-change-padding-of-DDR4-and-LPDDR4-DMEM-fir.patch"
  )

  # Apply each patch if not already applied
  for patch in "${patches[@]}"; do
    if git apply --check "$patch" &>/dev/null; then
      log_step "Applying patch: $(basename "$patch")"
      git apply "$patch"
    else
      log_step "Patch $(basename "$patch") has already been applied or cannot be applied."
    fi
  done

  # Copy soc.mak to the parent directory if required
  log_step "Copying soc.mak to parent directory..."
  cp "$mkimage_dir/iMX8M/soc.mak" "$boot_tools_dir"

  # Build ATF
  log_step "Building ATF..."
  cd "$atf_dir"
  export ARCH=$ARCH_ARM64
  export CROSS_COMPILE=$CROSS_COMPILE_ARM64
  unset LDFLAGS

  make -j$(nproc) PLAT=imx8mp bl31

  # Check and copy the generated bl31.bin
  if [ -f "build/imx8mp/release/bl31.bin" ]; then
    cp "build/imx8mp/release/bl31.bin" "$boot_tools_dir"
    log_step "ATF built and bl31.bin copied successfully."
  else
    echo "Error: ATF build failed, bl31.bin not found."
    exit 1
  fi
}

# ===========================================
# Prepare i.MX mkimage
# ===========================================
prepare_mkimage() {
    log_step "Preparing i.MX mkimage..."

    local boot_tools_dir="$WORKDIR/$UBOOT_TOOLS_DIR"
    local mkimage_dir="$boot_tools_dir/imx-mkimage"

    # Ensure imx-boot-tools directory exists
    mkdir -p "$boot_tools_dir"

    # Clone or update the imx-mkimage repository
    clone_or_update_repo "$IMX_MKIMAGE_REPO" "$IMX_MKIMAGE_BRANCH" "$mkimage_dir"

    # Change to the imx-mkimage directory
    cd "$mkimage_dir" || { echo "Error: Failed to change to $mkimage_dir"; exit 1; }

    # Copy necessary .c files from iMX8M directory
    log_step "Copying .c files from iMX8M directory..."
    for file in iMX8M/*.c; do
        if [ -e "$file" ]; then
            cp "$file" "$boot_tools_dir/"
        else
            log_step "No .c files found in iMX8M directory."
            break
        fi
    done

    # Copy necessary .sh files from iMX8M directory
    log_step "Copying .sh files from iMX8M directory..."
    for file in iMX8M/*.sh; do
        if [ -e "$file" ]; then
            cp "$file" "$boot_tools_dir/"
        else
            log_step "No .sh files found in iMX8M directory."
            break
        fi
    done

    # Copy necessary .sh files from scripts directory
    log_step "Copying .sh files from scripts directory..."
    for file in scripts/*.sh; do
        if [ -e "$file" ]; then
            cp "$file" "$boot_tools_dir/"
        else
            log_step "No .sh files found in scripts directory."
            break
        fi
    done

    # Ensure the scripts directory exists in the parent directory
    mkdir -p "$WORKDIR/scripts"
    cd "$boot_tools_dir"

    # Copy dtb_check.sh to the scripts directory
    if [ -e "dtb_check.sh" ]; then
        log_step "Copying dtb_check.sh to scripts directory..."
        cp "dtb_check.sh" "$WORKDIR/scripts/"
    else
        log_step "dtb_check.sh not found."
    fi

    # Copy mkimage to mkimage_uboot
    if [ -e "../uboot-imx/tools/mkimage" ]; then
        log_step "Copying mkimage to mkimage_uboot..."
        cp "../uboot-imx/tools/mkimage" mkimage_uboot
    else
        log_step "Error: mkimage not found in ../uboot-imx/tools/"
        exit 1
    fi

    # Copy u-boot.bin
    if [ -e "../uboot-imx/u-boot.bin" ]; then
        log_step "Copying u-boot.bin..."
        cp "../uboot-imx/u-boot.bin" .
    else
        log_step "Error: u-boot.bin not found in ../uboot-imx/"
        exit 1
    fi

    # Copy other necessary binaries and dtb files
    local files_to_copy=(
        "../uboot-imx/u-boot-nodtb.bin"
        "../uboot-imx/spl/u-boot-spl.bin"
        "../uboot-imx/arch/arm/dts/imx8mp-var-dart-dt8mcustomboard.dtb"
        "../uboot-imx/arch/arm/dts/imx8mp-var-som-symphony.dtb"
    )
    
    for file in "${files_to_copy[@]}"; do
        if [ -e "$file" ]; then
            log_step "Copying $(basename "$file")..."
            cp "$file" .
        else
            log_step "Error: $(basename "$file") not found."
            exit 1
        fi
    done


    log_step "i.MX mkimage prepared successfully."
}

# ===========================================
# Build Boot Image
# ===========================================
prepare_and_build_boot_image() {
  log_step "Building boot image..."
  local boot_tools_dir="$WORKDIR/$UBOOT_TOOLS_DIR"

  cd "$boot_tools_dir"

  # Clean previous builds
  log_step "Cleaning previous boot image build artifacts..."
  make -f soc.mak clean

  log_step "Building image ..."

  # Build the boot image
  if $VERBOSE; then
    make -j$(nproc) V=1 -f soc.mak CC=gcc \
      SOC="$UBOOT_SOC_TARGET" \
      SOC_DIR="$UBOOT_TOOLS_DIR" \
      dtbs="$DTBS" \
      MKIMG=./mkimage_imx8 \
      PAD_IMAGE=./pad_image.sh \
      OUTIMG="$OUTPUT_IMAGE" \
      "$UBOOT_TARGETS"
  else
    make -j$(nproc) -f soc.mak CC=gcc \
      SOC="$UBOOT_SOC_TARGET" \
      SOC_DIR="$UBOOT_TOOLS_DIR" \
      dtbs="$DTBS" \
      MKIMG=./mkimage_imx8 \
      PAD_IMAGE=./pad_image.sh \
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
    "prep")
      prepare
      ;;
    "uboot")
      prepare_and_build_uboot_imx
      ;;
    "atf")
      prepare_and_build_atf
      ;;
    "image")
      prepare_and_build_uboot_imx
      prepare_ddr_firmware
      prepare_and_build_atf
      prepare_mkimage
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
      prepare_mkimage
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
