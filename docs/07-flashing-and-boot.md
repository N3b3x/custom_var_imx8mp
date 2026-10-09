# 07 · Flashing the SD card and first boot

[Docs](README.md) › **07 · Flashing & first boot**

## 1. Find your card

Insert the card and look for it:

```bash
lsblk -po NAME,SIZE,RM,TRAN,MODEL
```

You'll see something like `/dev/sdb  29.7G  1  usb  STORAGE DEVICE` for a USB
reader, or `/dev/mmcblk0` for a built-in reader. **Use the whole disk**
(`/dev/sdb`), never a partition (`/dev/sdb1`).

## 2. Write it

```bash
./build.sh flash -d /dev/sdb --expand
```

What happens, step by step:

| Step | Command | Why |
| --- | --- | --- |
| safety checks | `lsblk`, `findmnt` | refuse partitions, disks holding `/`, `/home`, ...; refuse non-removable or >256 GB disks unless `--force`; show model and size and ask you |
| unmount | `sudo umount /dev/sdb1 ...` | desktops auto-mount cards; writing under a mounted fs corrupts it |
| write | `sudo bmaptool copy --bmap sdcard.img.bmap sdcard.img /dev/sdb` | writes only the used blocks and verifies them (falls back to `dd bs=4M conv=fsync status=progress`) |
| reread | `sudo blockdev --rereadpt /dev/sdb` | the kernel picks up the new partition table |
| `--expand` | `echo ', +' \| sudo sfdisk -N 1 /dev/sdb` | partition 1 = from its start to the end of the card |
|  | `sudo e2fsck -fy /dev/sdb1` | resize2fs requires a freshly checked filesystem |
|  | `sudo resize2fs /dev/sdb1` | grow ext4 into the new space |
| finish | `sync` | flush everything before you pull the card |

Partial updates for faster iteration:

```bash
./build.sh flash -d /dev/sdb --bootloader-only   # dd imx-boot.bin to 32 KiB only
./build.sh flash -d /dev/sdb --kernel-only       # mount p1, untar kernel.tar.gz, umount
```

Writing a card by hand works too:

```bash
sudo dd if=build/deploy/sdcard.img of=/dev/sdb bs=4M conv=fsync status=progress
```

Windows and macOS users can flash `sdcard.img` with balenaEtcher or Raspberry
Pi Imager ("use custom").

## 3. Boot the board

1. **Boot switch → SD.** Every carrier (Sonata, Symphony, Echo) has a
   boot-select switch. Set it to *SD card*; the exact position is in your
   carrier board's user guide. In the eMMC position, the Boot ROM ignores the
   card and boots the module's eMMC.
2. **Serial console.** Connect the carrier's debug USB/UART to your PC:

   ```bash
   sudo usermod -aG dialout $USER     # once, then log out and back in
   picocom -b 115200 /dev/ttyUSB0      # quit with Ctrl+A Ctrl+X
   # alternatives: screen /dev/ttyUSB0 115200 · minicom -D /dev/ttyUSB0 -b 115200
   ```

   Settings: **115200 baud, 8N1, no flow control**. The board-side port
   depends on the module, and U-Boot picks it automatically:

   | Module | Linux console |
   | --- | --- |
   | DART-MX8M-PLUS | `ttymxc0` (UART1) |
   | VAR-SOM-MX8M-PLUS, VAR-SMARC-MX8M-PLUS | `ttymxc1` (UART2) |

3. **Optional:** a monitor (HDMI/LVDS) and a USB keyboard for a second login on screen.
4. Insert the card and power on.

## 4. What a good boot looks like

This is a **real boot log** from a VAR-SOM-MX8M-PLUS rev 1.2 on a Symphony
board with this repository's Alpine image, shortened and annotated.

#### Stage 1: SPL + TF-A (first second)

```text
U-Boot SPL 2026.04-g9ee215f6a578 (Oct 08 2026 - 18:41:40 -0600)   ← our SPL is running
SEC0:  RNG instantiated
Normal Boot
Trying to boot from BOOTROM                                       ← SPL loads the rest via the Boot ROM API
Boot Stage: Primary boot
image offset 0x8000, pagesize 0x200, ivt offset 0x0               ← 0x8000 = 32 KiB: the imx-boot position
```

DDR training happens silently here. If it failed, the output would stop
right after these lines.

#### Stage 2: U-Boot (detects the hardware, finds the kernel)

```text
U-Boot 2026.04-g9ee215f6a578 (Oct 08 2026 - 18:41:40 -0600)
CPU:   NXP i.MX8MP[8] Rev1.1 A53 at 1200 MHz
Model: Variscite VAR-SOM-MX8M-PLUS on Symphony-Board              ← DTB picked from the FIT for this module
DRAM:  4 GiB
MMC:   FSL_SDHC: 1, FSL_SDHC: 2                                   ← 1 = SD card, 2 = eMMC
Loading Environment from MMC... *** Warning - bad CRC, using default environment   ← normal on a fresh card
Part number: VSM-MX8MP-249B                                       ← read from the module's EEPROM
SOM revision: 1.2
Hit any key to stop autoboot: 0                                   ← press a key here for the U-Boot prompt
Running BSP bootcmd ...
Failed to load '/boot/boot.scr'                                   ← optional, normal
Failed to load '/boot/uEnv.txt'                                   ← optional, normal
15647614 bytes read in 648 ms (23 MiB/s)                          ← /boot/Image.gz
Uncompressed size: 35887616 = 0x2239A00
fdt_file=imx8mp-var-som-1.x-symphony.dtb                          ← findfdt: module + revision (1.x) + carrier
80018 bytes read in 5 ms (15.3 MiB/s)                             ← the DTB
Starting kernel ...
```

#### Stage 3: Linux (~3.5 s to the root filesystem)

```text
[    0.000000] Linux version 6.18.20-custom (...) (aarch64-none-linux-gnu-gcc ... 14.3.1 ...)
[    0.000000] Machine model: Variscite VAR-SOM-MX8M-PLUS on Symphony-Board
[    0.000000] Kernel command line: console=ttymxc1,115200 root=/dev/mmcblk1p1 rootwait rw cma=704M ...
[    0.005800] smp: Brought up 1 node, 4 CPUs                    ← TF-A's PSCI started the other 3 cores
[    0.005810] CPU: All CPU(s) started at EL2                    ← Linux entered at the hypervisor level (EL2), then drops to EL1
[    2.799076] Console: switching to colour frame buffer device 100x30   ← penguins appear on the screen
[    3.375122] mmc1: new UHS-I speed SDR104 SDHC card at address 5048
[    3.400754] EXT4-fs (mmcblk1p1): mounted filesystem ... r/w   ← the SD card's root partition
[    3.440270] Run /sbin/init as init process                    ← hand-over to userspace
```

#### Stage 4: login

```text
Welcome to Alpine Linux 3.24
imx8mp-var-dart login:
```

Messages you can ignore on a first boot:

| Message | Why it's harmless |
| --- | --- |
| `bad CRC, using default environment` | no U-Boot environment saved yet (`saveenv` creates one) |
| `optee optee: OP-TEE api uid mismatch` | OP-TEE (optional secure OS) isn't part of this build |
| `Failed to load '/boot/boot.scr'` / `uEnv.txt` | optional override files; see [03-uboot.md](03-uboot.md#overriding-things-without-rebuilding-bootuenvtxt) |
| `Fixed dependency cycle(s) with ...` | kernel device-link bookkeeping, informational |
| `mmc0: Failed to initialize a non-removable card` | the SDIO slot for an optional Wi-Fi module is empty |
| `deferred probe pending: ...` at ~13 s | a driver waits for a part that didn't respond. Often carrier-specific (see [09](09-troubleshooting.md)) |

**On a monitor** you only see **penguins**, one per CPU core: the kernel's
boot logo. Boot messages go to the serial console only. The screen shows a
`login:` once userspace is up. Penguins alone never mean it's stuck: check the
serial console.

## 5. First things to check on the board

```sh
uname -a                         # 6.18.20-custom, aarch64
cat /proc/device-tree/model; echo   # which DTB U-Boot chose
cat /proc/cmdline                # console=, root= as passed by U-Boot
ls /lib/modules/$(uname -r)      # modules match the running kernel
dmesg | grep -iE 'error|fail'    # anything broken?
df -h /                          # the whole card, if you flashed with --expand
```

Everything else, including network, processes, hardware and every available
command, is in **[11 · Using the board](11-using-the-board.md)**. If
something's off, see [09 · Troubleshooting](09-troubleshooting.md).

## Installing to the on-module eMMC

Booted from SD, the eMMC is `/dev/mmcblk2`. You can write the same image to it:

```bash
# on the board, copy sdcard.img over first (scp, USB stick...)
dd if=sdcard.img of=/dev/mmcblk2 bs=4M conv=fsync
```

Then set the boot switch to eMMC. U-Boot detects it booted from eMMC (mmc 2)
and passes `root=/dev/mmcblk2p1` by itself.

---

← [06 · SD card image](06-sdcard-image.md) · [Index](README.md) · [08 · Customizing](08-customizing.md) →
