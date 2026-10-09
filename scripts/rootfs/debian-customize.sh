#!/bin/sh
# =============================================================================
#  scripts/rootfs/debian-customize.sh - turn a fresh Debian bootstrap into a
#  bootable system for the board
# =============================================================================
#
#  Called by mmdebstrap (scripts/rootfs.sh) as a --customize-hook, i.e. AFTER
#  all packages are installed and BEFORE the tarball is written:
#
#     debian-customize.sh <rootdir> <hostname> <user> <fs-label> <shadow-file>
#
#  It runs on the build PC with root rights (sudo or a user namespace).
#  Paths are always prefixed with "$ROOT" so we only ever touch the new
#  filesystem. `chroot "$ROOT" <cmd>` runs an arm64 program inside it; on an
#  x86 PC qemu-user-static executes it transparently.
#
#  Edit this file to customise the Debian image (extra config files, services
#  to enable, ...). Packages are better added via DEBIAN_PACKAGES.
# =============================================================================
set -eu

ROOT=$1        # the new root filesystem
HOSTNAME=$2    # e.g. imx8mp-var-dart
NEWUSER=$3     # e.g. var
LABEL=$4       # ext4 label of the root partition, e.g. root
SHADOW=$5      # file with "user:<sha512-hash>" lines (never a clear-text password)

echo "debian-customize: configuring $ROOT"

# --- Identity ----------------------------------------------------------------
# The name shown in the shell prompt and announced via DHCP.
echo "$HOSTNAME" > "$ROOT/etc/hostname"
# Make the hostname resolvable locally (sudo complains otherwise).
printf '127.0.0.1\tlocalhost\n127.0.1.1\t%s\n::1\t\tlocalhost ip6-localhost ip6-loopback\n' \
  "$HOSTNAME" > "$ROOT/etc/hosts"

# --- Filesystems -------------------------------------------------------------
# Mount the root partition by its label, so the same image works on SD
# (mmcblk1) and eMMC (mmcblk2). noatime avoids a write on every file read.
echo "LABEL=$LABEL / ext4 defaults,noatime 0 1" > "$ROOT/etc/fstab"

# --- Users -------------------------------------------------------------------
# A normal user that can use sudo, serial ports, audio, video, USB devices.
chroot "$ROOT" useradd --create-home --shell /bin/bash \
  --groups sudo,adm,dialout,audio,video,plugdev "$NEWUSER"
# Set root's and the user's password hashes (chpasswd -e = already encrypted).
chroot "$ROOT" chpasswd -e < "$SHADOW"

# --- Network -----------------------------------------------------------------
# systemd-networkd: DHCP on every wired interface. Their names on this board
# are end0/end1 (systemd's naming for device-tree Ethernet ports).
mkdir -p "$ROOT/etc/systemd/network"
cat > "$ROOT/etc/systemd/network/20-wired.network" <<'EOF'
[Match]
Name=e*

[Network]
DHCP=yes
EOF
# Start networkd and the DNS resolver at boot.
chroot "$ROOT" systemctl enable systemd-networkd systemd-resolved

# --- SSH ---------------------------------------------------------------------
# Host keys generated now would be identical on every board made from this
# image. Delete them and let sshd generate fresh ones on first start.
rm -f "$ROOT"/etc/ssh/ssh_host_*
mkdir -p "$ROOT/etc/systemd/system/ssh.service.d"
cat > "$ROOT/etc/systemd/system/ssh.service.d/keygen.conf" <<'EOF'
[Service]
ExecStartPre=/usr/bin/ssh-keygen -A
EOF

# --- First boot --------------------------------------------------------------
# An empty machine-id makes systemd generate a unique one on first boot
# (used for DHCP client IDs, journal, ...).
: > "$ROOT/etc/machine-id"

# --- Size --------------------------------------------------------------------
# Package lists and caches are re-downloaded by `apt update` on the board.
rm -rf "$ROOT"/var/lib/apt/lists/* "$ROOT"/var/cache/apt/*.bin

echo "debian-customize: done"
