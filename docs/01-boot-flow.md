# 01 · How the i.MX 8M Plus boots

[Docs](README.md) › **01 · Boot flow**

Knowing the boot chain makes every later step obvious. You will know why
there are four repositories, why the image is written at 32 KiB, and why the
kernel lives in `/boot` on an ext4 partition.

## The chain

```
 power on
    │
    ▼
┌──────────────┐  burned into the SoC. Reads the BOOT_MODE pins / fuses
│  Boot ROM    │  (your carrier's boot switch) to choose SD, eMMC, USB, QSPI...
└──────┬───────┘  On SD/eMMC it reads the image header at offset 32 KiB.
       │ loads SPL into on-chip RAM (OCRAM - DDR is not usable yet!)
       ▼
┌──────────────┐  U-Boot SPL (Secondary Program Loader), ~180 KiB
│  U-Boot SPL  │  * detects the module (DART / SOM / SMARC) from its EEPROM
│              │  * loads the LPDDR4 PHY training firmware and trains DDR
└──────┬───────┘  * loads the FIT image (u-boot.itb) that follows it
       │ copies BL31 + U-Boot into DDR
       ▼
┌──────────────┐  Trusted Firmware-A, BL31, runs at EL3 (most privileged)
│  TF-A BL31   │  Stays resident. Linux calls it ("PSCI") to power CPUs
└──────┬───────┘  on/off, reboot, suspend. Then drops to EL2 → U-Boot.
       ▼
┌──────────────┐  U-Boot proper, EL2
│   U-Boot     │  * picks its device tree from the FIT (per detected module)
│              │  * runs bootcmd = "run bsp_bootcmd" (see 03-uboot.md)
│              │  * loads /boot/Image.gz and /boot/<module>-<carrier>.dtb
└──────┬───────┘    from partition 1 of the boot device, then `booti`
       ▼
┌──────────────┐  Linux 6.18. root=/dev/mmcblk1p1 (SD) or mmcblk2p1 (eMMC)
│    Linux     │  mounts the ext4 root filesystem and starts /sbin/init
└──────┬───────┘
       ▼
   systemd (Debian) / busybox init (Alpine)  →  login on ttymxc0
```

## Which repository provides what

| Stage | File in the image | Built from | Script step |
| --- | --- | --- | --- |
| SPL | `u-boot-spl.bin` | `varigit/uboot-imx` | `./build.sh uboot uboot` |
| DDR training FW | `lpddr4_pmu_train_{1d,2d}_{imem,dmem}_202006.bin` | NXP `firmware-imx` (binary, EULA) | `./build.sh uboot firmware` |
| BL31 | `bl31.bin` | `varigit/imx-atf` | `./build.sh uboot atf` |
| U-Boot | `u-boot-nodtb.bin` + DTBs | `varigit/uboot-imx` | `./build.sh uboot uboot` |
| Glue → `flash.bin` | `imx-boot.bin` | `varigit/imx-mkimage` | `./build.sh uboot mkimage` |
| Kernel + DTBs + modules | `/boot/Image.gz`, `/boot/*.dtb`, `/lib/modules` | `varigit/linux-imx` | `./build.sh kernel` |
| Userspace | everything else in `/` | Debian / Alpine / yours | `./build.sh rootfs` |

## Inside `imx-boot.bin`

`imx-mkimage` produces this (offsets relative to the start of the file, so
add 32 KiB for the position on the card):

```
0x00000  IVT + boot data header        ← what the Boot ROM parses
0x00040  u-boot-spl.bin
  ...    LPDDR4 1D imem/dmem + 2D imem/dmem (padded to 32K/4K each)
0x58000  FIT image "u-boot.itb":
           uboot-1  U-Boot (64-bit)
           atf-1    ARM Trusted Firmware (loaded at 0x970000)
           fdt-1    imx8mp-var-dart-sonataboard   ← config-1 (default)
           fdt-2    imx8mp-var-som-symphony       ← config-2
           fdt-3    imx8mp-var-smarc-echo         ← config-3
```

You can list the FIT yourself after a build:

```bash
build/src/uboot-imx/tools/dumpimage -l build/src/imx-mkimage/iMX8M/u-boot.itb
```

## The SD card memory map

```
byte offset   content
───────────   ─────────────────────────────────────────────────────────
0             MBR (partition table, 1 entry)
32 KiB        imx-boot.bin  (~1.7 MB)      ← Boot ROM reads here
7 MiB         U-Boot environment (16 KiB, written by `saveenv`)
8 MiB         partition 1: ext4, label "root"
                 /boot/Image.gz
                 /boot/imx8mp-var-*.dtb
                 /lib/modules/6.18.20-custom/
                 /sbin/init, /etc, /usr ...
end of card
```

The 32 KiB offset is fixed by the i.MX8M Boot ROM for SD and eMMC user-area
boot. Variscite's machine config says `IMX_BOOT_SEEK = "32"`. The environment
offset comes from U-Boot's `CONFIG_ENV_OFFSET=0x700000`. The first partition
starts at 8 MiB so it can never overlap either of them.

## SD vs eMMC device numbers

| Device | U-Boot | Linux |
| --- | --- | --- |
| SD card slot (uSDHC2) | `mmc 1` (`sd_dev=1`) | `/dev/mmcblk1` |
| On-module eMMC (uSDHC3) | `mmc 2` (`emmc_dev=2`) | `/dev/mmcblk2` |

U-Boot works out which one it booted from (`mmcautodetect=yes`). It then
passes the matching `root=/dev/mmcblkXp1` to Linux, so the same card works no
matter which slot it later gets copied to.

---

← [Main README](../README.md) · [Index](README.md) · [02 · Host setup](02-host-setup.md) →
