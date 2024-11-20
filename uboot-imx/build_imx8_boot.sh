#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# ===========================================
# Define repositories and branches
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

# Cross-compiler and architecture for ARM64
CROSS_COMPILE_ARM64="ccache aarch64-none-linux-gnu-"
ARCH_ARM64="arm64"

# Device Tree Blobs (DTBs) for Variscite boards
DTBS="imx8mp-var-dart-dt8mcustomboard.dtb imx8mp-var-som-symphony.dtb"

# Output boot image filename
OUTPUT_IMAGE="imx-boot-sd.bin"

# Enable ccache for faster builds
ccache --max-size=20G

# U-Boot defconfig for Variscite VAR-SOM-MX8M-PLUS
UBOOT_DEFCONFIG="imx8mp_var_dart_defconfig"

# Dynamically determine the current script directory
SCRIPT_DIR=$(realpath "$(dirname "$0")")

# External flash script path
FLASH_SCRIPT="$SCRIPT_DIR/flash_sd_imx8_boot.sh"

# ===========================================
# Function to display usage information
# ===========================================
usage() {
  echo "Usage: $0 -w <workdir> -d <device> [-h]"
  echo "  -w <workdir>  : Working directory for the build process"
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
# Check for required dependencies
# ===========================================
check_dependencies() {
  local dependencies=("git" "wget" "dd" "udevadm")
  for cmd in "${dependencies[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      echo "Error: Required command '$cmd' is not installed."
      exit 1
    fi
  done
}

# ===========================================
# Clone or update a repository
# ===========================================
clone_or_update_repo() {
  local repo_url=$1  # Repository URL
  local branch=$2    # Branch to checkout
  local dest_dir=${3:-.}  # Destination directory; defaults to current directory if not specified

  if [ -d "$dest_dir" ]; then
    if [ -d "$dest_dir/.git" ]; then
      echo "Repository $dest_dir already exists. Pulling the latest changes..."
      cd "$dest_dir"
      git fetch origin
      git checkout $branch
      git pull origin $branch
    else
      if [ "$dest_dir" = "." ]; then
        if [ -z "$(ls -A "$dest_dir")" ]; then
          echo "Cloning repository $repo_url (branch: $branch) into the current directory..."
          git clone --branch $branch $repo_url .
        else
          echo "Error: Current directory is not empty. Cannot clone into it."
          exit 1
        fi
      else
        echo "Directory $dest_dir exists but is not a Git repository. Removing it..."
        rm -rf "$dest_dir"
        echo "Cloning repository $repo_url (branch: $branch) into $dest_dir..."
        git clone --branch $branch $repo_url $dest_dir
      fi
    fi
  else
    echo "Cloning repository $repo_url (branch: $branch) into $dest_dir..."
    git clone --branch $branch $repo_url $dest_dir
  fi
}

# ===========================================
# Build U-Boot
# ===========================================
prepare_and_build_uboot_imx() {
  echo "Building U-Boot..."

  cd "$WORKDIR"

  # Clone or update the uboot-imx repository
  clone_or_update_repo "$UBOOT_REPO" "$UBOOT_BRANCH" "$WORKDIR/uboot-imx"

  cd "$WORKDIR/uboot-imx"
  make mrproper
  export ARCH=$ARCH_ARM64
  export CROSS_COMPILE=$CROSS_COMPILE_ARM64
  make $UBOOT_DEFCONFIG  # Use environment variable for defconfig
  make -j$(nproc)
  
  echo "U-Boot built successfully."
}


# ===========================================
# Prepare boot tools directory
# ===========================================
prepare_boot_tools_dir() {
    echo "Creating and navigating to imx-boot-tools directory..."
    mkdir -p "$WORKDIR/imx-boot-tools"
    echo "imx-boot-tools directory created and navigated successfully."
}

# ===========================================
# Download and prepare DDR firmware
# ===========================================
prepare_ddr_firmware() {
    echo "Preparing DDR firmware..."
    cd "$WORKDIR/imx-boot-tools"
    if [ ! -f firmware-imx-8.18.bin ]; then
        wget "$DDR_FIRMWARE_URL" -O firmware-imx-8.18.bin
        chmod +x firmware-imx-8.18.bin
        ./firmware-imx-8.18.bin --auto-accept
    fi
    cp firmware-imx-8.18/firmware/ddr/synopsys/* .
    echo "DDR firmware prepared successfully."
}

# ===========================================
# Prepare i.MX mkimage
# ===========================================
prepare_mkimage() {
    echo "Preparing i.MX mkimage..."
    cd "$WORKDIR/imx-boot-tools"

    # Clone or update the imx-mkimage repository
    clone_or_update_repo "$IMX_MKIMAGE_REPO" "$IMX_MKIMAGE_BRANCH" "$WORKDIR/imx-boot-tools/imx-mkimage"

    cd "$WORKDIR/imx-boot-tools/imx-mkimage" || { echo "Failed to change directory"; exit 1; }

    # Copy necessary .c files from iMX8M directory
    for file in iMX8M/*.c; do
        if [ -e "$file" ]; then
            cp "$file" "$WORKDIR/imx-boot-tools/"
        else
            echo "No .c files found in iMX8M directory."
            break
        fi
    done

    # Copy necessary .sh files from iMX8M directory
    for file in iMX8M/*.sh; do
        if [ -e "$file" ]; then
            cp "$file" "$WORKDIR/imx-boot-tools/"
        else
            echo "No .sh files found in iMX8M directory."
            break
        fi
    done

    # Copy necessary .sh files from scripts directory
    for file in scripts/*.sh; do
        if [ -e "$file" ]; then
            cp "$file" "$WORKDIR/imx-boot-tools/"
        else
            echo "No .sh files found in scripts directory."
            break
        fi
    done

    # Ensure the scripts directory exists in the parent directory
    mkdir -p "$WORKDIR/scripts"

    # Copy dtb_check.sh to the scripts directory
    if [ -e dtb_check.sh ]; then
        cp dtb_check.sh "$WORKDIR/scripts/"
    else
        echo "dtb_check.sh not found."
    fi

    echo "i.MX mkimage prepared successfully."
}


# ===========================================
# Prepare and build ARM Trusted Firmware (ATF)
# ===========================================
prepare_and_build_atf() {
  echo "Preparing and building ARM Trusted Firmware (ATF)..."

  cd "$WORKDIR/imx-boot-tools"

  # Clone or update the imx-atf repository
  clone_or_update_repo "$ATF_REPO" "$ATF_BRANCH" "$WORKDIR/imx-boot-tools/imx-atf"

  # Clone or update the meta-variscite-bsp repository
  clone_or_update_repo "$META_VARISCITE_BSP_REPO" "$META_VARISCITE_BSP_BRANCH" "$WORKDIR/imx-boot-tools/meta-variscite-bsp"

  # Apply patches to imx-mkimage
  cd "$WORKDIR/imx-boot-tools/imx-mkimage"

  # Define an array of patch files
  patches=(
    "$WORKDIR/imx-boot-tools/meta-variscite-bsp/recipes-bsp/imx-mkimage/imx-boot/0001-iMX8M-soc-allow-dtb-override.patch"
    "$WORKDIR/imx-boot-tools/meta-variscite-bsp/recipes-bsp/imx-mkimage/imx-boot/0002-iMX8M-soc-change-padding-of-DDR4-and-LPDDR4-DMEM-fir.patch"
  )

  # Apply each patch if it hasn't been applied yet
  for patch in "${patches[@]}"; do
    if git apply --check "$patch" &>/dev/null; then
      echo "Applying patch: $(basename "$patch")"
      git apply "$patch"
    else
      echo "Patch $(basename "$patch") has already been applied or cannot be applied."
    fi
  done

  # Copy soc.mak to the parent directory
  cp "$WORKDIR/imx-boot-tools/imx-mkimage/iMX8M/soc.mak" "$WORKDIR/imx-boot-tools"

  # Build ATF
  cd "$WORKDIR/imx-boot-tools/imx-atf"
  export ARCH=$ARCH_ARM64
  export CROSS_COMPILE=$CROSS_COMPILE_ARM64
  unset LDFLAGS
  make PLAT=imx8mp bl31
  cp build/imx8mp/release/bl31.bin "$WORKDIR/imx-boot-tools"

  echo "ATF prepared and built successfully."
}


# ===========================================
# Build the boot image
# ===========================================
prepare_and_build_boot_image() {
  echo "Building boot image..."

  # Go to the boot tools directory
  cd "$WORKDIR/imx-boot-tools"

  # Copy required files
  cp "$WORKDIR/uboot-imx/tools/mkimage" mkimage_uboot
  cp "$WORKDIR/uboot-imx/u-boot.bin" .
  cp "$WORKDIR/uboot-imx/u-boot-nodtb.bin" .
  cp "$WORKDIR/uboot-imx/spl/u-boot-spl.bin" .

  # Dynamically copy DTBs
  for dtb in $DTBS; do
    cp "$WORKDIR/uboot-imx/arch/arm/dts/$dtb" .
  done

  # Build the image
  make -f soc.mak clean
  make -f soc.mak \
    SOC=iMX8MP \
    SOC_DIR=imx-boot-tools \
    dtbs="$DTBS" \
    MKIMG=./mkimage_imx8 \
    PAD_IMAGE=./pad_image.sh \
    CC=gcc \
    OUTIMG="$OUTPUT_IMAGE" \
    flash_evk

  echo "Boot image built successfully."
}

# ===========================================
# Main script execution
# ===========================================
main() {
    check_dependencies
    mkdir -p "$WORKDIR"

    # Prepare and build U-Boot imx version
    prepare_and_build_uboot_imx
    
    # Prepare and build DDR and ARM Trusted Firmware (ATF)
    prepare_boot_tools_dir
    prepare_ddr_firmware
    prepare_mkimage
    prepare_and_build_atf

    # Prepare and build boot image
    prepare_and_build_boot_image

    ls -l

    # Check if external flash script exists
    if [ ! -f "$FLASH_SCRIPT" ]; then
        echo "Error: Flash script '$FLASH_SCRIPT' not found."
        exit 1
    fi

    # Call the external flash script
    echo "Delegating flashing to $FLASH_SCRIPT..."
    bash "$FLASH_SCRIPT" -w "$WORKDIR" -d "$DEVICE"
}

main
