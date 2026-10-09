#!/usr/bin/env bash
# =============================================================================
#  scripts/uboot.sh - build the i.MX8M Plus boot image (imx-boot / flash.bin)
# =============================================================================
#
#  The i.MX8MP Boot ROM cannot start U-Boot directly. It loads ONE container
#  from offset 32 KiB of the SD card that holds, in boot order:
#
#    1. U-Boot SPL        - tiny loader that runs from on-chip SRAM
#    2. LPDDR4 firmware   - NXP binary blobs the SPL feeds to the DDR PHY to
#                           "train" the memory interface (from firmware-imx)
#    3. ATF / TF-A BL31   - secure monitor (EL3), provides PSCI to Linux
#    4. U-Boot proper     - the full bootloader (EL2) + its device trees
#
#  imx-mkimage glues these together into flash.bin. This script:
#
#    step 1  firmware  download + unpack NXP firmware-imx (DDR training blobs)
#    step 2  atf       build bl31.bin from Variscite's imx-atf
#    step 3  uboot     build u-boot-spl.bin, u-boot-nodtb.bin, DTBs, mkimage
#    step 4  mkimage   stage everything into imx-mkimage/iMX8M and run
#                      `make SOC=iMX8MP flash_evk`  ->  build/deploy/imx-boot.bin
#
#  Usage: scripts/uboot.sh [all|firmware|atf|uboot|mkimage|menuconfig|clean]
#         (normally called through ./build.sh uboot)
# =============================================================================
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
strict_mode
load_config

UBOOT_SRC="$SRC_DIR/uboot-imx"
ATF_SRC="$SRC_DIR/imx-atf"
MKIMAGE_SRC="$SRC_DIR/imx-mkimage"
FW_NAME="firmware-imx-${FIRMWARE_IMX_VERSION}-${FIRMWARE_IMX_HASH}"
FW_DIR="$WORK_DIR/$FW_NAME"
# imx-mkimage's "SOC_DIR" for every i.MX8M variant (8MQ/8MM/8MN/8MP)
STAGE="$MKIMAGE_SRC/iMX8M"

# -----------------------------------------------------------------------------
# Step 1: NXP firmware-imx -> LPDDR4 training firmware
# -----------------------------------------------------------------------------
do_firmware() {
  section "Step 1/4: NXP DDR training firmware ($FW_NAME)"
  explain "The SPL loads these 4 blobs into the DDR PHY so it can calibrate" \
          "the LPDDR4 timing. Without them the board cannot use its RAM."

  if [[ -d $FW_DIR/firmware/ddr/synopsys ]]; then
    info "Firmware already unpacked in $FW_DIR"
    return 0
  fi

  # firmware-imx is distributed under the NXP EULA; Yocto asks you to set
  # ACCEPT_FSL_EULA=1, we do the same.
  if [[ ${ACCEPT_FSL_EULA:-0} != 1 && $DRY_RUN != 1 ]]; then
    warn "firmware-imx is licensed under the NXP Software License Agreement (EULA)."
    warn "Read it at https://www.nxp.com/docs/en/disclaimer/LA_OPT_NXP_SW.html"
    confirm "Do you accept the NXP EULA?" || die "EULA not accepted (set ACCEPT_FSL_EULA=1 or pass --accept-eula)"
  fi

  fetch "$FIRMWARE_IMX_URL" "$DL_DIR/$FW_NAME.bin" "$FIRMWARE_IMX_SHA256"
  mkdir -p "$WORK_DIR"
  run_cd "The self-extracting archive unpacks into the current directory" "$WORK_DIR"
  run "Make the archive executable" chmod +x "$DL_DIR/$FW_NAME.bin"
  # --auto-accept skips the interactive pager because you accepted above.
  run "Run the self-extractor (creates $FW_NAME/)" "$DL_DIR/$FW_NAME.bin" --auto-accept --force
  need_file "$FW_DIR/firmware/ddr/synopsys"
}

# -----------------------------------------------------------------------------
# Step 2: ARM Trusted Firmware (BL31)
# -----------------------------------------------------------------------------
do_atf() {
  section "Step 2/4: ARM Trusted Firmware (TF-A) $ATF_BRANCH"
  explain "BL31 stays resident in on-chip RAM after boot. Linux calls into it" \
          "(PSCI) to start the secondary Cortex-A53 cores, reboot and suspend."
  setup_toolchain
  git_checkout "imx-atf" "$ATF_REPO" "$ATF_BRANCH" "$ATF_REV" "$ATF_SRC"
  apply_patches atf "$ATF_SRC"

  # ATF must NOT see the host's CFLAGS/LDFLAGS (it builds bare-metal code).
  unset CFLAGS LDFLAGS CPPFLAGS
  local v=(); [[ $VERBOSE == 1 ]] && v=(V=1)
  # PLAT=imx8mp            : i.MX8M Plus platform port
  # bl31                   : only build the BL31 stage (the only one i.MX uses)
  # IMX_BOOT_UART_BASE=auto: print on whatever UART the SPL already set up
  #                          (UART1/ttymxc0 on DART, UART2 on SOM/SMARC)
  # E=0                    : don't turn compiler warnings into errors; vendor
  #                          trees often lag behind new GCC releases
  # LDFLAGS=               : same reasoning for the linker's RWX-segment warning
  run "Build BL31 for $ATF_PLATFORM" \
    make -C "$ATF_SRC" -j"$JOBS" CROSS_COMPILE="$CROSS_COMPILE" \
      PLAT="$ATF_PLATFORM" IMX_BOOT_UART_BASE=auto E=0 "${v[@]}" bl31

  need_file "$ATF_SRC/build/$ATF_PLATFORM/release/bl31.bin"
  info "bl31.bin: $(hsize "$ATF_SRC/build/$ATF_PLATFORM/release/bl31.bin")"
}

# -----------------------------------------------------------------------------
# Step 3: U-Boot (SPL + proper)
# -----------------------------------------------------------------------------
do_uboot() {
  section "Step 3/4: U-Boot $UBOOT_BRANCH"
  setup_toolchain
  git_checkout "uboot-imx" "$UBOOT_REPO" "$UBOOT_BRANCH" "$UBOOT_REV" "$UBOOT_SRC"
  apply_patches uboot "$UBOOT_SRC"

  # Only write the defconfig the first time (or after `clean`), so that
  # changes made with `./build.sh uboot-menuconfig` survive rebuilds.
  if [[ ! -f $UBOOT_SRC/.config ]]; then
    run "Generate .config from $UBOOT_DEFCONFIG (board, DDR, env location, boot command)" \
      make -C "$UBOOT_SRC" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" "$UBOOT_DEFCONFIG"
  else
    info "Keeping existing $UBOOT_SRC/.config (run 'clean' to reset to the defconfig)"
  fi

  # Variscite enables signed UEFI capsule updates; the build converts
  # CRT.crt into an EFI signature list with a tool from the 'efitools' package.
  if [[ $DRY_RUN != 1 ]] && grep -q '^CONFIG_EFI_CAPSULE_AUTHENTICATE=y' "$UBOOT_SRC/.config" &&
     ! command -v cert-to-efi-sig-list >/dev/null; then
    die "U-Boot needs 'cert-to-efi-sig-list':  sudo apt install efitools   (or ./build.sh deps)"
  fi

  # U-Boot uses ARCH=arm for both 32- and 64-bit (it is NOT the kernel's
  # ARCH=arm64), so make is called directly here instead of via run_make.
  local cc=(); [[ -n $CC_WRAPPER ]] && cc=(CC="${CC_WRAPPER}${CROSS_COMPILE}gcc")
  local v=(); [[ $VERBOSE == 1 ]] && v=(V=1)
  run "Compile SPL, U-Boot proper, its device trees and the host 'mkimage' tool" \
    make -C "$UBOOT_SRC" -j"$JOBS" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" "${cc[@]}" "${v[@]}"

  # A plain-text dump of the compiled-in default environment (bootcmd,
  # mmcargs, findfdt, ...). Very useful to read; see docs/03-uboot.md.
  run "Export the default U-Boot environment as text (u-boot-initial-env)" \
    make -C "$UBOOT_SRC" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" "${cc[@]}" u-boot-initial-env

  need_file "$UBOOT_SRC/spl/u-boot-spl.bin" "$UBOOT_SRC/u-boot-nodtb.bin" "$UBOOT_SRC/tools/mkimage"
  info "u-boot-spl.bin: $(hsize "$UBOOT_SRC/spl/u-boot-spl.bin"), u-boot-nodtb.bin: $(hsize "$UBOOT_SRC/u-boot-nodtb.bin")"
}

uboot_menuconfig() {
  setup_toolchain
  [[ -f $UBOOT_SRC/.config ]] || do_uboot
  run "Open U-Boot's interactive configuration menu" \
    make -C "$UBOOT_SRC" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" menuconfig
  info "Save a defconfig with:  make -C $UBOOT_SRC savedefconfig  (writes $UBOOT_SRC/defconfig)"
}

# -----------------------------------------------------------------------------
# Step 4: imx-mkimage -> flash.bin
# -----------------------------------------------------------------------------
do_mkimage() {
  section "Step 4/4: imx-mkimage -> imx-boot.bin"
  git_checkout "imx-mkimage" "$MKIMAGE_REPO" "$MKIMAGE_BRANCH" "$MKIMAGE_REV" "$MKIMAGE_SRC"
  apply_patches mkimage "$MKIMAGE_SRC"

  explain "imx-mkimage expects every input inside $STAGE (its 'SOC_DIR')."
  local f
  for f in $DDR_FIRMWARE_FILES; do
    run "Stage DDR firmware $f" cp "$FW_DIR/firmware/ddr/synopsys/$f" "$STAGE/"
  done
  run "Stage TF-A BL31" cp "$ATF_SRC/build/$ATF_PLATFORM/release/bl31.bin" "$STAGE/bl31.bin"
  run "Stage U-Boot SPL" cp "$UBOOT_SRC/spl/u-boot-spl.bin" "$STAGE/"
  run "Stage U-Boot proper without its DTB (DTBs are added separately to the FIT)" \
    cp "$UBOOT_SRC/u-boot-nodtb.bin" "$STAGE/"
  run "Stage u-boot.bin (used by some imx-mkimage targets)" cp "$UBOOT_SRC/u-boot.bin" "$STAGE/"
  # soc.mak calls this to build the FIT image (u-boot.itb) holding ATF + U-Boot + DTBs
  run "Stage U-Boot's 'mkimage' host tool as mkimage_uboot" cp "$UBOOT_SRC/tools/mkimage" "$STAGE/mkimage_uboot"
  local dtb
  for dtb in $UBOOT_DTBS; do
    # U-Boot >= 2024 builds board DTBs into arch/arm/dts; fall back to dts/upstream.
    local src="$UBOOT_SRC/arch/arm/dts/$dtb"
    [[ -f $src || $DRY_RUN == 1 ]] || src=$(find "$UBOOT_SRC" -name "$dtb" -path '*dts*' -print -quit)
    run "Stage U-Boot device tree $dtb" cp "$src" "$STAGE/"
  done

  run "Remove a stale flash.bin so a failed run cannot be mistaken for success" rm -f "$STAGE/flash.bin"
  # SOC=iMX8MP : selects PLAT=imx8mp, load addresses, LPDDR4 firmware names
  # dtbs="..." : the U-Boot DTBs to put in the FIT; SPL picks one at runtime
  # MKIMAGE=   : which mkimage builds the FIT (ours, from U-Boot)
  # flash_evk  : LPDDR4 SD/eMMC boot image (the target Variscite uses)
  # imx-mkimage's Makefile uses the shell's $(PWD), so it must be run from
  # inside its tree (`make -C` would build mkimage_imx8 in the wrong place).
  run_cd "imx-mkimage must be run from its own top directory" "$MKIMAGE_SRC"
  run "Assemble SPL + DDR FW + BL31 + U-Boot into flash.bin" \
    make SOC="$MKIMAGE_SOC" dtbs="$UBOOT_DTBS" MKIMAGE=./mkimage_uboot "$MKIMAGE_TARGET"
  run_cd "Back to the repository" "$TOP_DIR"

  need_file "$STAGE/flash.bin"
  mkdir -p "$DEPLOY_DIR"
  run "Publish the boot image" cp "$STAGE/flash.bin" "$DEPLOY_DIR/imx-boot.bin"
  # Also keep U-Boot's default environment for reference / fw_setenv users.
  [[ -f $UBOOT_SRC/u-boot-initial-env ]] && run "Publish the default U-Boot environment" \
    cp "$UBOOT_SRC/u-boot-initial-env" "$DEPLOY_DIR/u-boot-initial-env"
  [[ $DRY_RUN == 1 ]] || info "Boot image ready: $DEPLOY_DIR/imx-boot.bin ($(hsize "$DEPLOY_DIR/imx-boot.bin"))"
  explain "Write it to an SD card on its own with:  ./build.sh flash --bootloader-only -d /dev/sdX"
}

do_clean() {
  section "Cleaning bootloader build outputs (sources are kept)"
  [[ -d $UBOOT_SRC ]] && run "Remove all U-Boot build files incl. .config" make -C "$UBOOT_SRC" mrproper
  [[ -d $ATF_SRC ]] && run "Remove the TF-A build directory" rm -rf "$ATF_SRC/build"
  [[ -d $MKIMAGE_SRC ]] && run "Reset imx-mkimage's staging dir to the pristine git state" \
    git -C "$MKIMAGE_SRC" clean -fdxq
  run "Remove the published boot image" rm -f "$DEPLOY_DIR/imx-boot.bin" "$DEPLOY_DIR/u-boot-initial-env"
}

main() {
  local target=${1:-all}
  # menuconfig needs a real terminal, so it is not piped through the logger
  [[ $target == menuconfig ]] || start_log "uboot-$target"
  case $target in
    all)        do_firmware; do_atf; do_uboot; do_mkimage ;;
    firmware)   do_firmware ;;
    atf)        do_atf ;;
    uboot)      do_uboot ;;
    mkimage)    do_mkimage ;;
    menuconfig) uboot_menuconfig ;;
    clean)      do_clean ;;
    *) die "unknown target '$target' (all|firmware|atf|uboot|mkimage|menuconfig|clean)" ;;
  esac
}

main "$@"
