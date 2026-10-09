#!/usr/bin/env bash
# =============================================================================
#  scripts/rootfs.sh - produce a root filesystem tarball for the board
# =============================================================================
#
#  The result is always ONE file:  build/deploy/rootfs.tar  (symlink to the
#  real file) which scripts/image.sh unpacks into the SD card's ext4 partition.
#
#  ROOTFS=debian  (default)
#     Debian ($DEBIAN_SUITE) for arm64 built with mmdebstrap. Real distro:
#     systemd, apt, ssh, DHCP on every Ethernet port, serial login.
#     Needs: mmdebstrap, qemu-user-static + binfmt-support, and either sudo
#            or the 'uidmap' package (rootless "unshare" mode).
#
#  ROOTFS=alpine
#     Alpine minirootfs (~4 MB download, ~10 MB unpacked), busybox init with a
#     serial getty. No root rights needed. Ideal for first bring-up of a board.
#
#  ROOTFS=/path/to/your-rootfs.tar.{gz,xz,zst,bz2}
#     Bring your own (Variscite prebuilt image rootfs, Buildroot, Yocto, ...).
#     Used as-is; only kernel + modules are added by image.sh.
# =============================================================================
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
strict_mode
load_config

ROOTFS_LINK="$DEPLOY_DIR/rootfs.tar"

# SHA-512 crypt hash of the configured password, for /etc/shadow
password_hash() { openssl passwd -6 "$TARGET_PASSWORD"; }

# -----------------------------------------------------------------------------
# Debian via mmdebstrap
# -----------------------------------------------------------------------------
build_debian() {
  section "Building Debian $DEBIAN_SUITE arm64 root filesystem (mmdebstrap)"
  need_cmd mmdebstrap
  local out="$DEPLOY_DIR/rootfs-debian-$DEBIAN_SUITE.tar"

  # Running arm64 binaries (dpkg maintainer scripts) on an x86 PC needs
  # qemu-user-static registered with binfmt_misc. Check it early.
  if [[ $(uname -m) != aarch64 && ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
    die "arm64 binfmt handler missing: sudo apt install qemu-user-static binfmt-support"
  fi

  # Pick how mmdebstrap gets root rights for the chroot:
  #   root    - we are root already
  #   unshare - rootless, via user namespaces (needs newuidmap from 'uidmap')
  #   sudo    - fall back to running mmdebstrap itself with sudo
  local mode sudo=()
  if [[ $EUID == 0 ]]; then mode=root
  elif command -v newuidmap >/dev/null && unshare --user true 2>/dev/null; then mode=unshare
  else mode=root; sudo=(sudo); fi
  info "mmdebstrap mode: $mode${sudo:+ (via sudo)}"

  # Debian's signing keys, so mmdebstrap can verify every downloaded package
  # even on hosts (Ubuntu!) that do not ship the Debian keyring.
  local kr_deb="$DL_DIR/${DEBIAN_KEYRING_URL##*/}" kr_dir="$WORK_DIR/debian-keyring"
  fetch "$DEBIAN_KEYRING_URL" "$kr_deb" "$DEBIAN_KEYRING_SHA256"
  run "Unpack the keyring package (no installation, just the files)" dpkg-deb -x "$kr_deb" "$kr_dir"
  local keyring="$kr_dir/usr/share/keyrings/debian-archive-keyring.gpg"

  # Password hashes go into a file that the customize script feeds to
  # `chpasswd -e`; the clear-text password never reaches the image.
  local shadow="$WORK_DIR/debian-passwords"
  mkdir -p "$WORK_DIR"
  explain "Writing SHA-512 hashes of TARGET_PASSWORD for root and $TARGET_USER to \$B/work/debian-passwords"
  if [[ $DRY_RUN != 1 ]]; then
    ( umask 077
      printf 'root:%s\n%s:%s\n' "$(password_hash)" "$TARGET_USER" "$(password_hash)" > "$shadow" )
  fi

  # Everything that makes the bootstrap a bootable board image (hostname,
  # fstab, users, network, ssh) is in scripts/rootfs/debian-customize.sh -
  # read it, it is commented line by line. mmdebstrap runs it with "$1" set
  # to the new root directory.
  local hook="\"$TOP_DIR/scripts/rootfs/debian-customize.sh\" \"\$1\" $TARGET_HOSTNAME $TARGET_USER $ROOTFS_LABEL \"$shadow\""

  # One mirror line per suite: main archive, -updates and security.
  local comps="main contrib non-free non-free-firmware"
  local srcs=(
    "deb $DEBIAN_MIRROR $DEBIAN_SUITE $comps"
    "deb $DEBIAN_MIRROR $DEBIAN_SUITE-updates $comps"
    "deb http://security.debian.org/debian-security $DEBIAN_SUITE-security $comps"
  )

  mkdir -p "$DEPLOY_DIR"
  # --variant=minbase : only Essential + apt, we add what we need explicitly
  # --include         : extra packages (DEBIAN_PACKAGES in the config)
  # The output file name ending in .tar makes mmdebstrap write a tarball
  # with correct root ownership, even in rootless mode.
  run "Bootstrap Debian $DEBIAN_SUITE for arm64 into a tarball" \
    "${sudo[@]}" mmdebstrap --mode="$mode" --architectures=arm64 --variant=minbase \
      --keyring="$keyring" \
      --include="${DEBIAN_PACKAGES// /,},systemd-resolved" \
      --customize-hook="$hook" \
      "$DEBIAN_SUITE" "$out" "${srcs[@]}"
  ((${#sudo[@]})) && run "Give the tarball back to your user" sudo chown "$(id -u):$(id -g)" "$out"
  run "Delete the password-hash file" rm -f "$shadow"
  run "Point rootfs.tar at it" ln -sfn "$(basename "$out")" "$ROOTFS_LINK"
}

# -----------------------------------------------------------------------------
# Alpine minirootfs (rootless)
# -----------------------------------------------------------------------------
build_alpine() {
  section "Preparing Alpine $ALPINE_VERSION minirootfs (busybox init)"
  need_cmd fakeroot
  local branch="v${ALPINE_VERSION%.*}"
  local name="alpine-minirootfs-${ALPINE_VERSION}-aarch64.tar.gz"
  local url="https://dl-cdn.alpinelinux.org/alpine/$branch/releases/aarch64/$name"
  local sha
  # Alpine publishes a .sha256 next to every release file.
  if [[ $DRY_RUN == 1 ]]; then sha="<sha256>"; else
    sha=$(wget -qO- "$url.sha256" | cut -d' ' -f1) || die "cannot fetch $url.sha256"
  fi
  fetch "$url" "$DL_DIR/$name" "$sha"

  local stage="$WORK_DIR/alpine-rootfs" out="$DEPLOY_DIR/rootfs-alpine-$ALPINE_VERSION.tar"
  local pwhash; pwhash=$(password_hash)
  mkdir -p "$DEPLOY_DIR"
  run "Start from an empty staging dir" rm -rf "$stage"
  run "Create it" mkdir -p "$stage"

  # Everything happens inside ONE fakeroot session: fakeroot pretends we are
  # root so files keep uid/gid 0 in the final tarball, without real root.
  explain "The minirootfs has no OpenRC, so we give busybox init its own inittab" \
          "that mounts /proc,/sys,/dev/pts and starts a login on the serial console" \
          "the kernel was given (works on DART, VAR-SOM and SMARC alike)."
  run "Unpack, configure and re-pack the rootfs as fake-root" \
    fakeroot -- bash -euc '
      stage=$1 tarball=$2 out=$3 host=$4 console=$5 pw=$6 label=$7
      tar -xzpf "$tarball" -C "$stage"
      echo "$host" > "$stage/etc/hostname"
      printf "127.0.0.1\tlocalhost %s\n" "$host" > "$stage/etc/hosts"
      echo "LABEL=$label / ext4 defaults,noatime 0 1" > "$stage/etc/fstab"
      sed -i "s|^root:[^:]*:|root:$pw:|" "$stage/etc/shadow"
      # Allow root logins on every i.MX UART (login checks /etc/securetty).
      for t in ttymxc0 ttymxc1 ttymxc2 ttymxc3; do
        grep -qx "$t" "$stage/etc/securetty" || echo "$t" >> "$stage/etc/securetty"
      done
      # Login prompt on the serial console U-Boot handed to the kernel:
      # console=ttymxc0 on DART, ttymxc1 on VAR-SOM / SMARC. One image fits
      # every module; TARGET_CONSOLE is only the fallback.
      cat > "$stage/sbin/console-getty" <<"EOF"
#!/bin/sh
# Start getty on the kernel console from /proc/cmdline (last console= wins).
tty=$(sed -n "s/.*console=\([^, ]*\).*/\1/p" /proc/cmdline)
exec /sbin/getty -L 115200 "${tty:-FALLBACK}" vt100
EOF
      sed -i "s/FALLBACK/$console/" "$stage/sbin/console-getty"
      chmod 0755 "$stage/sbin/console-getty"
      # Kernel modules: Debian has udev to load drivers; BusyBox needs this.
      # Without it nothing in "=m" loads: no RTC, no SDMA (SPI), no audio...
      cat > "$stage/sbin/coldplug" <<"EOF"
#!/bin/sh
# Load the kernel module for every device the kernel found at boot.
# Each device publishes a "modalias" in /sys; modprobe maps it to a module.
# Two passes: drivers from pass 1 can reveal more devices (SDMA -> SPI ...).
for pass in 1 2; do
  find /sys/devices -name modalias -exec cat {} + 2>/dev/null | sort -u |
    xargs modprobe -q -a -b 2>/dev/null
  sleep 1
done
EOF
      chmod 0755 "$stage/sbin/coldplug"
      # mdev rules: sane permissions (without a config mdev makes /dev/null
      # root-only) and module loading for devices plugged in later (USB...).
      cat > "$stage/etc/mdev.conf" <<"EOF"
# /etc/mdev.conf - BusyBox mdev rules: device nodes and hotplug
# Format: <name regex> <uid>:<gid> <mode> [@command-after-create]
# A leading "-" means: apply this rule and keep matching the next ones.

# Load the driver of any device that appears later (USB stick, adapter...)
-$MODALIAS=.*  0:0 660 @modprobe -q -b "$MODALIAS"

# Usable by everyone
null     0:0 666
zero     0:0 666
full     0:0 666
random   0:0 666
urandom  0:0 666
tty      0:5 666
ptmx     0:5 666

# Everything else: root only
.*       0:0 660
EOF
      chmod 0644 "$stage/etc/mdev.conf"
      # The kernel already mounts /dev (DEVTMPFS_MOUNT), hence the check.
      # tty1 = the HDMI/LVDS screen: a second login for monitor + USB keyboard.
      # syslogd -C512 keeps system logs in a 512 KiB RAM ring buffer (read
      # them with `logread`, no SD card wear); klogd feeds it kernel messages.
      # coldplug loads drivers for the hardware found at boot, mdev -d keeps
      # listening for hotplugged devices, hwclock syncs time with the RTC.
      cat > "$stage/etc/inittab" <<EOF
::sysinit:/bin/mount -t proc proc /proc
::sysinit:/bin/mount -t sysfs sysfs /sys
::sysinit:grep -q " /dev " /proc/mounts || /bin/mount -t devtmpfs devtmpfs /dev
::sysinit:/bin/mkdir -p /dev/pts /dev/shm /run /tmp
::sysinit:/bin/mount -t devpts devpts /dev/pts
::sysinit:/bin/mount -o remount,rw /
::sysinit:/bin/hostname -F /etc/hostname
::sysinit:/sbin/syslogd -C512
::sysinit:/sbin/klogd
::sysinit:/sbin/mdev -s
::sysinit:/sbin/coldplug
::sysinit:/sbin/mdev -d
::sysinit:/sbin/hwclock -u -s 2>/dev/null
::sysinit:/sbin/ip link set lo up
::respawn:/sbin/console-getty
tty1::respawn:/sbin/getty 38400 tty1
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/hwclock -u -w 2>/dev/null
::shutdown:/bin/umount -a -r
EOF
      tar -C "$stage" --numeric-owner -cpf "$out" .
    ' _ "$stage" "$DL_DIR/$name" "$out" "$TARGET_HOSTNAME" "$TARGET_CONSOLE" "$pwhash" "$ROOTFS_LABEL"
  run "Point rootfs.tar at it" ln -sfn "$(basename "$out")" "$ROOTFS_LINK"
  run "Remove the staging dir" rm -rf "$stage"
}

# -----------------------------------------------------------------------------
# User supplied tarball
# -----------------------------------------------------------------------------
use_tarball() {
  local src
  src=$(realpath "$ROOTFS")
  [[ -f $src ]] || die "ROOTFS='$ROOTFS' is neither debian, alpine nor an existing file"
  section "Using your root filesystem tarball: $src"
  mkdir -p "$DEPLOY_DIR"
  run "Point rootfs.tar at it (image.sh auto-detects the compression)" ln -sfn "$src" "$ROOTFS_LINK"
}

main() {
  start_log "rootfs"
  case $ROOTFS in
    debian) build_debian ;;
    alpine) build_alpine ;;
    *)      use_tarball ;;
  esac
  [[ $DRY_RUN == 1 ]] || info "Root filesystem ready: $ROOTFS_LINK -> $(readlink "$ROOTFS_LINK") ($(hsize "$(readlink -f "$ROOTFS_LINK")"))"
}

main "$@"
