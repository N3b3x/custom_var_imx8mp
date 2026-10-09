# 05 · Root filesystem

[Docs](README.md) › **05 · Root filesystem**

```bash
./build.sh rootfs                    # Debian trixie (default)
./build.sh -r alpine rootfs          # Alpine minirootfs, no root needed
./build.sh -r ~/var-image.tar.zst rootfs   # your own tarball
```

The step always produces `build/deploy/rootfs.tar` (a symlink to the real
file). `./build.sh all` reuses an existing `rootfs.tar` because it rarely
changes. Run `./build.sh rootfs` or pass `-r` to rebuild it.

## Comparison

|  | `debian` (default) | `alpine` | your tarball |
| --- | --- | --- | --- |
| Size | a few hundred MB | ~10 MB | depends |
| Init | systemd | busybox init | yours |
| Packages | `apt install` anything | `apk` (configure network first) | yours |
| Network | DHCP on all wired ports (systemd-networkd) | manual (`udhcpc -i eth0`) | yours |
| SSH | yes (unique host keys generated at first boot) | no | yours |
| Build needs | `mmdebstrap`, `qemu-user-static`, sudo **or** `uidmap` | nothing special | nothing |
| Good for | development, real use | first bring-up, kernel testing | Variscite / Yocto / Buildroot images |

Default credentials for `debian` and `alpine` (change them in
`config/local.conf`!):

| User | Password | Notes |
| --- | --- | --- |
| `root` | `variscite` |  |
| `var` | `variscite` | Debian only; member of `sudo`, `dialout`, `video`, `audio`... |

## Debian, step by step

`scripts/rootfs.sh` runs one `mmdebstrap` command. Simplified:

```bash
sudo mmdebstrap --mode=root --architectures=arm64 --variant=minbase \
  --include=systemd-sysv,udev,openssh-server,sudo,...,systemd-resolved \
  --customize-hook='echo imx8mp-var-dart > "$1/etc/hostname"' \
  --customize-hook='echo "LABEL=root / ext4 defaults,noatime 0 1" > "$1/etc/fstab"' \
  --customize-hook='chroot "$1" useradd -m -s /bin/bash -G sudo,... var' \
  ... \
  trixie build/deploy/rootfs-debian-trixie.tar \
  "deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware" \
  "deb http://deb.debian.org/debian trixie-updates main ..." \
  "deb http://security.debian.org/debian-security trixie-security main ..."
```

- **`--architectures=arm64` on an x86 PC** works because `qemu-user-static`
  registers itself with the kernel's `binfmt_misc`. Any arm64 program
  (`dpkg` maintainer scripts, `useradd`...) then runs transparently through
  qemu.
- **`--variant=minbase`** installs only *Essential* packages plus apt. Everything
  else is listed explicitly in `DEBIAN_PACKAGES` in the config.
- **`--customize-hook`** runs on the host after installation, with `$1` = the
  new root directory. `chroot "$1" cmd` runs a command inside it.
- **Writing to a `.tar`** keeps correct root ownership even in rootless mode.
- **mode:** the script uses `unshare` (rootless) if `newuidmap` (package
  `uidmap`) is available, otherwise `sudo mmdebstrap --mode=root`.

What the hooks set up:

| What | How |
| --- | --- |
| hostname, `/etc/hosts` | `TARGET_HOSTNAME` |
| `/etc/fstab` | root by label `root`, `noatime` to save flash wear |
| users | `root` and `TARGET_USER`, password `TARGET_PASSWORD` (stored as SHA-512 hash) |
| network | `/etc/systemd/network/20-wired.network`: DHCP on `e*` (`end0`, `end1`) |
| ssh | host keys deleted; `ssh-keygen -A` runs before sshd starts, so every board gets its own |
| `/etc/machine-id` | emptied, so systemd generates a unique one at first boot |
| serial login | nothing to do: systemd starts `serial-getty@ttymxc0` automatically for the `console=` U-Boot passes |

Add packages by appending to `DEBIAN_PACKAGES`:

```bash
# config/local.conf
DEBIAN_PACKAGES="$DEBIAN_PACKAGES python3 gpiod network-manager"
```

## Alpine

The [minirootfs](https://alpinelinux.org/downloads/) is a 4 MB tarball with
BusyBox, musl libc and the `apk` package manager, but **no init system**. The
script gives BusyBox's `init` a small `/etc/inittab`. This is the whole boot
sequence of the Alpine image, line by line:

```text
::sysinit:/bin/mount -t proc proc /proc                     # process info (/proc)
::sysinit:/bin/mount -t sysfs sysfs /sys                    # devices and drivers (/sys)
::sysinit:grep -q " /dev " /proc/mounts || mount -t devtmpfs devtmpfs /dev   # /dev, unless the kernel already did
::sysinit:/bin/mkdir -p /dev/pts /dev/shm /run /tmp
::sysinit:/bin/mount -t devpts devpts /dev/pts              # terminals for logins/ssh
::sysinit:/bin/mount -o remount,rw /                        # root filesystem writable
::sysinit:/bin/hostname -F /etc/hostname
::sysinit:/sbin/syslogd -C512                               # system log in a 512 KiB RAM buffer → `logread`
::sysinit:/sbin/klogd                                       # kernel messages into that log
::sysinit:/sbin/mdev -s                                     # device nodes, permissions from /etc/mdev.conf
::sysinit:/sbin/coldplug                                    # load kernel modules for the hardware found
::sysinit:/sbin/mdev -d                                     # hotplug daemon: devices plugged in later
::sysinit:/sbin/hwclock -u -s 2>/dev/null                   # system time ← RTC
::sysinit:/sbin/ip link set lo up                           # loopback network
::respawn:/sbin/console-getty                               # login on the serial console
tty1::respawn:/sbin/getty 38400 tty1                        # login on the screen
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/hwclock -u -w 2>/dev/null                  # RTC ← system time
::shutdown:/bin/umount -a -r                                # unmount cleanly on poweroff/reboot
```

- `sysinit` lines run once at boot, in order.
- `respawn` restarts the program whenever it exits, so a new `login:` appears
  after you log out.
- **`/sbin/console-getty`** reads `console=` from `/proc/cmdline` and starts the
  login there. So the same image logs in on `ttymxc0` (DART) and `ttymxc1`
  (VAR-SOM, SMARC) without configuration.
- **`/sbin/coldplug`** does what `udev` does on Debian: each device in `/sys`
  publishes a `modalias`, and `modprobe` loads the matching module. Without
  it no `=m` driver loads, so there's no RTC, no SDMA (SPI, audio), no
  sound, and no CAN.
- **`/etc/mdev.conf`** gives `/dev/null`, `/dev/zero`, `/dev/urandom`,
  `/dev/tty` and `/dev/ptmx` world access (everything else is root only).
  It also loads modules for hotplugged devices through `mdev -d`.
- Logs live in RAM: nothing is written to the SD card, and they are gone after
  a reboot.

Everything is prepared inside one `fakeroot` session, so files are owned by
root in the tarball without needing real root.

On the board, the network isn't started automatically: run
`udhcpc -i eth0`. There's no udev, so the kernel's names `eth0`/`eth1` stay.
To make it automatic, or to start your own program at boot, see
[11 · Using the board](11-using-the-board.md#13-start-your-own-program-at-boot).

## Your own tarball

Any tar archive of a complete arm64 root filesystem works. Compression is
auto-detected. Good sources:

- Variscite's prebuilt Yocto / Debian images for DART-MX8M-PLUS. Extract the
  rootfs `.tar.*` from their release, or loop-mount their `.wic` image and
  tar up partition 1.
- Your own Yocto build: `tmp/deploy/images/imx8mp-var-dart/*.rootfs.tar.zst`.
- Buildroot: `output/images/rootfs.tar`.

`image.sh` adds **this** project's kernel, DTBs and modules on top, replacing
the tarball's `/boot/Image.gz` and DTBs if present. Keep the kernel versions
in mind: a Yocto rootfs built for a different kernel still works, but its
`/lib/modules/<other-version>` will simply be unused.

---

← [04 · Kernel](04-kernel.md) · [Index](README.md) · [06 · SD card image](06-sdcard-image.md) →
