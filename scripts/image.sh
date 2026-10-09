#!/usr/bin/env bash
# =============================================================================
#  scripts/image.sh - assemble a complete, flashable SD card image
# =============================================================================
#
#  Inputs (produced by the other steps):
#    build/deploy/imx-boot.bin        bootloader       (scripts/uboot.sh)
#    build/deploy/kernel.tar.gz       kernel+dtbs+mods (scripts/kernel.sh)
#    build/deploy/rootfs.tar          root filesystem  (scripts/rootfs.sh)
#
#  Output:
#    build/deploy/imx8mp-var-dart-<rootfs>-<date>.img  (+ .bmap)
#    build/deploy/sdcard.img -> the newest one
#
#  Layout written (same as Variscite's Yocto "imx-imx-boot-singlepart" wks):
#
#    offset 0        MBR partition table (1 partition)
#    offset 32 KiB   imx-boot.bin   <- the i.MX8MP Boot ROM looks here
#    offset 7 MiB    (U-Boot saves its environment here at runtime)
#    offset 8 MiB    partition 1: ext4, label "root"
#                      /boot/Image.gz, /boot/*.dtb   <- U-Boot loads these
#                      /lib/modules/<ver>/            <- kernel modules
#                      ... the rest of the root filesystem
#
#  NO root/sudo needed: the ext4 filesystem is created from a directory with
#  `mke2fs -d` inside a `fakeroot` session, and partitioning happens on a
#  regular file.
# =============================================================================
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
strict_mode
load_config

BOOT_BIN="$DEPLOY_DIR/imx-boot.bin"
KERNEL_TAR="$DEPLOY_DIR/kernel.tar.gz"
ROOTFS_TAR="$DEPLOY_DIR/rootfs.tar"
FW_DIR="$WORK_DIR/firmware-imx-${FIRMWARE_IMX_VERSION}-${FIRMWARE_IMX_HASH}"
STAGE="$WORK_DIR/image-rootfs"
EXT4_IMG="$WORK_DIR/rootfs.ext4"

main() {
  start_log "image"
  need_cmd fakeroot mke2fs sfdisk dd truncate tar
  section "Assembling SD card image"
  need_file "$BOOT_BIN" "$KERNEL_TAR" "$ROOTFS_TAR"

  # The Boot ROM reads imx-boot from 32 KiB and U-Boot keeps its environment
  # at 7 MiB, so the boot image must fit in between.
  if [[ $DRY_RUN != 1 ]]; then
    local boot_max=$(( 7*1024*1024 - IMX_BOOT_SEEK_KB*1024 ))
    (( $(stat -c %s "$BOOT_BIN") <= boot_max )) || die "imx-boot.bin is larger than $boot_max bytes and would overwrite the U-Boot environment"
  fi

  local rootfs_name
  rootfs_name=$(basename "$(readlink -f "$ROOTFS_TAR")"); rootfs_name=${rootfs_name%%.tar*}; rootfs_name=${rootfs_name#rootfs-}
  local img
  img="$DEPLOY_DIR/imx8mp-var-dart-${rootfs_name}-$(date +%Y%m%d-%H%M).img"

  # ---------------------------------------------------------------------------
  # 1) Stage the full root filesystem and turn it into an ext4 image.
  #    One fakeroot session = files are owned by root:root in the image.
  # ---------------------------------------------------------------------------
  run "Start from an empty staging directory" rm -rf "$STAGE" "$EXT4_IMG"
  run "Create it" mkdir -p "$STAGE"

  explain "Inside fakeroot:" \
          "  - unpack the rootfs tarball (tar detects gz/xz/zst/bz2 by itself)" \
          "  - unpack the kernel overlay on top. --keep-directory-symlink matters:" \
          "    on Debian /lib is a symlink to /usr/lib and must stay one" \
          "  - add NXP firmware for SDMA/audio blocks (/lib/firmware/imx)" \
          "  - size the filesystem (content + ${IMAGE_EXTRA_MB} MiB + 10% ext4 overhead)" \
          "  - mke2fs -d copies the staged tree into a new ext4 image"
  run "Build the ext4 root filesystem image (as fake root)" \
    fakeroot -- bash -euc '
      stage=$1 rootfs=$2 kernel=$3 fw=$4 img=$5 extra=$6 label=$7
      tar -xpf "$rootfs" -C "$stage" --numeric-owner
      tar -xpf "$kernel" -C "$stage" --numeric-owner --keep-directory-symlink
      if [ -d "$fw/firmware" ]; then
        mkdir -p "$stage/lib/firmware/imx"
        for d in sdma easrc xcvr; do
          [ -d "$fw/firmware/$d" ] && cp -r "$fw/firmware/$d" "$stage/lib/firmware/imx/"
        done
        chown -R 0:0 "$stage/lib/firmware/imx"; chmod -R go-w "$stage/lib/firmware/imx"
      fi
      used=$(du -s --block-size=1M "$stage" | cut -f1)
      size=$(( used + extra + used / 10 + 64 ))
      echo "  rootfs content: ${used} MiB -> ext4 size: ${size} MiB"
      mke2fs -q -F -t ext4 -L "$label" -d "$stage" "$img" "${size}M"
    ' _ "$STAGE" "$ROOTFS_TAR" "$KERNEL_TAR" "$FW_DIR" "$EXT4_IMG" "$IMAGE_EXTRA_MB" "$ROOTFS_LABEL"

  # ---------------------------------------------------------------------------
  # 2) Create the disk image file: partition table + bootloader + filesystem
  # ---------------------------------------------------------------------------
  local start_sector=$(( ROOTFS_PART_START_MB * 1024 * 1024 / 512 ))
  local fs_bytes=0
  [[ $DRY_RUN == 1 ]] || fs_bytes=$(stat -c %s "$EXT4_IMG")
  local total_mb=$(( ROOTFS_PART_START_MB + (fs_bytes + 1024*1024 - 1) / (1024*1024) + 1 ))

  run "Remove a previous image with the same name" rm -f "$img"
  run "Create an empty (sparse) ${total_mb} MiB image file" truncate -s "${total_mb}M" "$img"
  # sfdisk reads a small script: DOS/MBR label, one Linux (type 83) partition
  # from 8 MiB to the end of the image, marked bootable.
  run_sh "Write the MBR partition table (p1 = Linux, starts at ${ROOTFS_PART_START_MB} MiB)" \
    "printf 'label: dos\\nunit: sectors\\nstart=$start_sector, type=83, bootable\\n' | sfdisk --quiet '$img'"
  # conv=notrunc : write into the existing file instead of truncating it
  run "Write the bootloader at ${IMX_BOOT_SEEK_KB} KiB (where the Boot ROM looks for it)" \
    dd if="$BOOT_BIN" of="$img" bs=1K seek="$IMX_BOOT_SEEK_KB" conv=notrunc status=none
  # conv=sparse : skip writing blocks of zeros, keeps the file small on disk
  run "Copy the ext4 filesystem into partition 1" \
    dd if="$EXT4_IMG" of="$img" bs=1M seek="$ROOTFS_PART_START_MB" conv=notrunc,sparse status=none

  # ---------------------------------------------------------------------------
  # 3) Helpers for fast flashing and housekeeping
  # ---------------------------------------------------------------------------
  if command -v bmaptool >/dev/null; then
    # A block map lists only the blocks that contain data, so
    # `bmaptool copy` writes ~the used size instead of the full image.
    run "Create a block map (.bmap) for fast flashing with bmaptool" \
      bmaptool -q create -o "$img.bmap" "$img"
  fi
  run "Point sdcard.img at the newest image" ln -sfn "$(basename "$img")" "$DEPLOY_DIR/sdcard.img"
  [[ -f $img.bmap ]] && run "...and sdcard.img.bmap at its block map" ln -sfn "$(basename "$img").bmap" "$DEPLOY_DIR/sdcard.img.bmap"
  run "Free the staging area" rm -rf "$STAGE" "$EXT4_IMG"

  if [[ $DRY_RUN != 1 ]]; then
    section "Done"
    sfdisk -l "$img" | sed 's/^/  /'
    info "SD card image: $img ($(hsize "$img") on disk, $(du -h --apparent-size "$img" | cut -f1) apparent)"
    info "Flash it with:  ./build.sh flash -d /dev/sdX"
  fi
}

main "$@"
