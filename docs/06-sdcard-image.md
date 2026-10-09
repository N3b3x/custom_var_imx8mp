# 06 · Assembling the SD card image

[Docs](README.md) › **06 · SD card image**

```bash
./build.sh image
```

Inputs: `imx-boot.bin`, `kernel.tar.gz`, `rootfs.tar` (all in `build/deploy/`).
Output: `build/deploy/imx8mp-var-dart-<rootfs>-<date>.img`, plus a `.bmap`
file and the `sdcard.img` symlink.

**No sudo is needed.** Normally you would partition a loop device, `mkfs`,
mount and copy as root. Instead, the whole image is built as regular files.

## The commands, explained

```bash
D=build/deploy W=build/work

# 1) one fakeroot session: stage the tree and turn it into an ext4 image
fakeroot -- bash -c '
  tar -xpf  build/deploy/rootfs.tar     -C build/work/image-rootfs --numeric-owner
  tar -xpf  build/deploy/kernel.tar.gz  -C build/work/image-rootfs --numeric-owner --keep-directory-symlink
  cp -r firmware-imx-.../firmware/{sdma,easrc,xcvr} build/work/image-rootfs/lib/firmware/imx/
  mke2fs -t ext4 -L root -d build/work/image-rootfs build/work/rootfs.ext4 <size>M
'

# 2) the disk image
truncate -s <total>M sdcard.img                                    # sparse file
printf 'label: dos\nunit: sectors\nstart=16384, type=83, bootable\n' | sfdisk sdcard.img
dd if=imx-boot.bin  of=sdcard.img bs=1K seek=32 conv=notrunc       # bootloader at 32 KiB
dd if=rootfs.ext4   of=sdcard.img bs=1M seek=8  conv=notrunc,sparse # p1 at 8 MiB
bmaptool create -o sdcard.img.bmap sdcard.img
```

| Trick | Why it matters |
| --- | --- |
| `fakeroot` | Intercepts `chown`/`stat` so tools *believe* they run as root. Files keep uid 0 inside the image, and nothing on your PC is touched as root. Everything must happen in **one** session, because fakeroot's memory of ownership ends with it |
| `mke2fs -d DIR` | Creates the ext4 filesystem **pre-filled** with the contents of `DIR`, so there's no mount and no copy |
| `--keep-directory-symlink` | On Debian (merged-`/usr`), `/lib` is a symlink to `usr/lib`. Without this flag, unpacking `lib/modules/...` would replace the symlink with a real directory and break every program on the system |
| `--numeric-owner` | Use uid/gid numbers from the tarball, not names looked up on *your* PC |
| `truncate` + `conv=sparse` | The image file only uses disk space for real data |
| `start=16384` | 16384 sectors × 512 B = 8 MiB |
| `conv=notrunc` | Write *into* the image without cutting it off after the written data |
| `.bmap` | List of blocks that contain data. `bmaptool copy` writes only those, which is several times faster than `dd`, and verifies checksums |

### Sizing

```
ext4 size  = content + IMAGE_EXTRA_MB (512) + 10% (ext4 metadata, journal) + 64 MiB
image size = 8 MiB + ext4 size + 1 MiB
```

The image is deliberately small so it writes fast. Use
`./build.sh flash --expand` to grow partition 1 to the whole card while flashing.
You can also grow it later on the board:

```bash
# on the target, Debian (as root)
apt install cloud-guest-utils && growpart /dev/mmcblk1 1 && resize2fs /dev/mmcblk1p1
```

### Firmware added to `/lib/firmware/imx`

`sdma`, `easrc` and `xcvr` from NXP firmware-imx (already downloaded for the DDR
blobs). These are loaded by the audio/DMA drivers, as in Variscite's Yocto
images.

## Inspecting an image without flashing it

```bash
sfdisk -l build/deploy/sdcard.img                 # partition table
xxd -s 32K -l 64 build/deploy/sdcard.img          # IVT header: starts with "d1 00 20 41"

# loop-mount partition 1 read-only (needs sudo)
sudo mount -o loop,ro,offset=$((8*1024*1024)) build/deploy/sdcard.img /mnt
ls /mnt/boot; sudo umount /mnt

# without root: cut partition 1 out and browse it with debugfs
dd if=build/deploy/sdcard.img of=/tmp/p1.ext4 bs=1M skip=8 status=none
debugfs -R 'ls -l /boot' /tmp/p1.ext4
```

---

← [05 · Root filesystem](05-rootfs.md) · [Index](README.md) · [07 · Flashing & first boot](07-flashing-and-boot.md) →
