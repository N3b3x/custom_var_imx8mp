#!/usr/bin/env bash
# =============================================================================
#  scripts/kernel.sh - build the Linux kernel, device trees and modules
# =============================================================================
#
#  Output is a small "overlay" directory tree that is merged on top of the root
#  filesystem when the SD card image is assembled:
#
#    build/deploy/kernel/
#      boot/Image.gz                   <- U-Boot loads ${bootdir}/${image}
#      boot/imx8mp-var-*.dtb           <- U-Boot's findfdt picks one by module/carrier
#      lib/modules/<version>/...       <- loadable drivers (modprobe)
#    build/deploy/kernel-<version>.tar.gz  (same thing, to update an existing card)
#
#  Usage: scripts/kernel.sh [all|config|build|install|menuconfig|clean]
# =============================================================================
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
strict_mode
load_config

KSRC="$SRC_DIR/linux-imx"
KDTS="$KSRC/arch/arm64/boot/dts/freescale"
OVERLAY="$DEPLOY_DIR/kernel"
CUSTOM_DTS_DIR="$TOP_DIR/custom/dts"
FRAGMENT_DIR="$TOP_DIR/config/kernel"

# Every make call gets the same LOCALVERSION, otherwise the version string of
# the Image and of /lib/modules/<version> could differ and modules won't load.
kmake() { run_make "$1" "$KSRC" LOCALVERSION="$KERNEL_LOCALVERSION" "${@:2}"; }

# -----------------------------------------------------------------------------
fetch_sources() {
  section "Linux kernel source: $KERNEL_BRANCH"
  git_checkout "linux-imx" "$KERNEL_REPO" "$KERNEL_BRANCH" "$KERNEL_REV" "$KSRC"
  apply_patches kernel "$KSRC"

  # Out-of-tree device trees: drop your *.dts / *.dtsi in custom/dts/ and
  # they are copied next to Variscite's files so they can #include them.
  if compgen -G "$CUSTOM_DTS_DIR/*.dts*" >/dev/null; then
    local f
    for f in "$CUSTOM_DTS_DIR"/*.dts*; do
      run "Copy custom device tree $(basename "$f") into the kernel tree" cp "$f" "$KDTS/"
    done
  fi
}

# -----------------------------------------------------------------------------
do_config() {
  setup_toolchain
  fetch_sources
  section "Kernel configuration ($KERNEL_DEFCONFIG)"
  if [[ -f $KSRC/.config && ${FORCE_CONFIG:-0} != 1 ]]; then
    info "Keeping existing .config (run './build.sh kernel-clean' or FORCE_CONFIG=1 to regenerate)"
    return 0
  fi
  # imx8_var_defconfig = NXP's imx_v8_defconfig + Variscite board drivers
  # (PMIC, Wi-Fi/BT, cameras, display bridges, ...).
  kmake "Create .config from arch/arm64/configs/$KERNEL_DEFCONFIG" "$KERNEL_DEFCONFIG"

  # Optional config fragments: config/kernel/*.cfg, one CONFIG_FOO=y per line.
  if compgen -G "$FRAGMENT_DIR/*.cfg" >/dev/null; then
    run "Merge config fragments from config/kernel/ on top of the defconfig" \
      env ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" \
      "$KSRC/scripts/kconfig/merge_config.sh" -m -O "$KSRC" "$KSRC/.config" "$FRAGMENT_DIR"/*.cfg
    kmake "Resolve dependencies of the merged options (new symbols get defaults)" olddefconfig
  fi
}

# -----------------------------------------------------------------------------
# Work out which .dtb targets to build. "all" = every imx8mp Variscite board.
#
# They are read from the freescale/Makefile rather than globbing *.dts: many
# Variscite DTBs are *composite* (base .dtb + overlay .dtbo merged at build
# time), e.g.
#   imx8mp-var-dart-1.x-sonata-dtbs := imx8mp-var-dart-sonata.dtb imx8mp-var-dart-1.x.dtbo
# and U-Boot's findfdt picks those "-1.x-" / "-wbe-" variants by SOM revision.
dtb_targets() {
  local list=() f
  if [[ $KERNEL_DTBS == all ]]; then
    [[ -f $KDTS/Makefile ]] || { [[ $DRY_RUN == 1 ]] && return 0; die "kernel source missing"; }
    # \.dtb\b matches ".dtb" but not ".dtbo"
    while read -r f; do list+=("freescale/$f"); done \
      < <(grep -oE 'imx8mp-var-[A-Za-z0-9._-]+\.dtb\b' "$KDTS/Makefile")
  else
    for f in $KERNEL_DTBS; do list+=("freescale/${f%.dtb}.dtb"); done
  fi
  # Custom device trees are always built.
  if compgen -G "$CUSTOM_DTS_DIR/*.dts" >/dev/null; then
    for f in "$CUSTOM_DTS_DIR"/*.dts; do list+=("freescale/$(basename "${f%.dts}").dtb"); done
  fi
  ((${#list[@]})) || return 0
  printf '%s\n' "${list[@]}" | sort -u
}

do_build() {
  [[ -f $KSRC/.config ]] || do_config
  setup_toolchain
  section "Compiling kernel ($KERNEL_IMAGE + modules + device trees) with $JOBS jobs"
  explain "First build takes ~25 min on 12 cores; rebuilds only recompile what changed."
  kmake "Compile the kernel image and all modules" "$KERNEL_IMAGE" modules

  local dtbs=()
  mapfile -t dtbs < <(dtb_targets)
  ((${#dtbs[@]})) || [[ $DRY_RUN == 1 ]] || die "no device trees selected (KERNEL_DTBS='$KERNEL_DTBS')"
  # -j1 on purpose: kbuild starts one sub-make per .dtb named on the command
  # line, and composite DTBs share overlays (*.dtbo); in parallel two
  # sub-makes would write the same overlay at once and corrupt it.
  # Each DTB takes well under a second, so this costs little.
  kmake "Compile ${#dtbs[@]} device tree(s) for the i.MX8MP Variscite boards (serially, see comment)" "${dtbs[@]}" -j1
}

# -----------------------------------------------------------------------------
do_install() {
  setup_toolchain
  section "Installing kernel into $OVERLAY"
  local kver
  if [[ $DRY_RUN == 1 ]]; then kver="<version>"; else
    kver=$(make -s -C "$KSRC" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" LOCALVERSION="$KERNEL_LOCALVERSION" kernelrelease)
  fi
  info "Kernel release: $kver"

  run "Start from an empty overlay so removed files do not linger" rm -rf "$OVERLAY"
  run "Create /boot in the overlay" mkdir -p "$OVERLAY/boot"
  run "Install the compressed kernel image" \
    cp "$KSRC/arch/arm64/boot/$KERNEL_IMAGE" "$OVERLAY/boot/$KERNEL_IMAGE"
  run "Keep the matching .config for reference (also handy for out-of-tree modules)" \
    cp "$KSRC/.config" "$OVERLAY/boot/config-$kver"

  local d
  while read -r d; do
    run "Install device tree $(basename "$d")" cp "$KSRC/arch/arm64/boot/dts/$d" "$OVERLAY/boot/"
  done < <(dtb_targets)

  # INSTALL_MOD_STRIP=1 strips debug symbols: ~10x smaller modules.
  # DEPMOD runs on the host to produce modules.dep etc. for the target.
  kmake "Install modules into <overlay>/lib/modules/$kver" modules_install \
    INSTALL_MOD_PATH="$OVERLAY" INSTALL_MOD_STRIP=1
  # The 'build' and 'source' links point into this PC; they are useless and
  # dangling on the board.
  run "Remove host-only build/source symlinks" \
    rm -f "$OVERLAY/lib/modules/$kver/build" "$OVERLAY/lib/modules/$kver/source"

  run "Pack the overlay as a tarball (to update an existing SD card in place)" \
    tar -C "$OVERLAY" --owner=0 --group=0 --mode=go-w -czf "$DEPLOY_DIR/kernel-$kver.tar.gz" .
  [[ $DRY_RUN == 1 ]] || ln -sfn "kernel-$kver.tar.gz" "$DEPLOY_DIR/kernel.tar.gz"
  [[ $DRY_RUN == 1 ]] || info "Kernel $kver installed: $(ls "$OVERLAY"/boot/*.dtb | wc -l) DTBs, modules $(du -sh "$OVERLAY/lib/modules" | cut -f1)"
}

do_menuconfig() {
  [[ -f $KSRC/.config ]] || do_config
  setup_toolchain
  kmake "Open the kernel's interactive configuration menu" menuconfig
  info "To keep your changes in git, save a minimal fragment, e.g.:"
  info "  diff <(sort build/src/linux-imx/.config.old) <(sort build/src/linux-imx/.config) | grep '^>' | cut -c3- > config/kernel/my.cfg"
}

do_clean() {
  section "Cleaning kernel build (sources are kept)"
  [[ -d $KSRC ]] && run_make "Remove all build output and .config" "$KSRC" mrproper
  run "Remove the installed overlay" rm -rf "$OVERLAY" "$DEPLOY_DIR"/kernel*.tar.gz
}

main() {
  local target=${1:-all}
  [[ $target == menuconfig ]] || start_log "kernel-$target"
  case $target in
    all)        do_config; do_build; do_install ;;
    config)     do_config ;;
    build)      do_build ;;
    install)    do_install ;;
    menuconfig) do_menuconfig ;;
    clean)      do_clean ;;
    *) die "unknown target '$target' (all|config|build|install|menuconfig|clean)" ;;
  esac
}

main "$@"
