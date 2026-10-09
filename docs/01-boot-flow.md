# 01 · How the i.MX 8M Plus boots

[Docs](README.md) › **01 · Boot flow**

> **In this guide:** the full chain from power-on to `login:`, what each stage
> does and where in memory it runs, what is inside `imx-boot.bin`, how the RAM
> is laid out, and how storage is named in each layer. Once you have this
> picture, every later step is obvious: why there are four repositories, why
> the image goes at 32 KiB, and why the kernel lives in `/boot` on an ext4
> partition.

**Contents:** [The chain](#1-the-chain) · [Each stage](#2-each-stage-in-detail) ·
[Inside imx-boot.bin](#3-inside-imx-bootbin) · [RAM](#4-where-things-live-in-ram) ·
[Storage and the card](#5-storage-the-sd-card-and-the-names) ·
[Which repo builds what](#6-which-repository-builds-what) · [Watch it happen](#7-watch-it-happen)

---

## 1. The chain

![How the i.MX 8M Plus boots](images/boot-chain.svg)

Three ideas explain the whole picture:

1. **Each stage exists because the previous one can't do the job.** The Boot
   ROM can't use DDR, so a tiny SPL that fits in 576 KiB of on-chip RAM trains
   the DDR first. Only then can the big pieces (U-Boot, Linux) be loaded.
2. **The CPU starts in the most privileged, secure state (EL3) and works its
   way down.** Boot ROM, SPL and BL31 run at EL3 in the secure world. BL31
   then drops to EL2 in the normal world for U-Boot, and Linux continues from
   there.
3. **Almost everything exits; one thing stays.** The Boot ROM, SPL and U-Boot
   are gone once Linux runs. **TF-A BL31 stays resident** at EL3 for the life
   of the system. Linux calls it to start CPUs, reboot, and change DDR
   frequency. See [13 · Secure world](13-secure-world.md).

## 2. Each stage in detail

| # | Stage | Runs | Reads | Does | Hands off by |
| --- | --- | --- | --- | --- | --- |
| 1 | **Boot ROM** | in the SoC, EL3 | boot switch / fuses, then the IVT header at **32 KiB** on SD or eMMC | copies SPL + DDR firmware to OCRAM `0x0092_0000` | jump |
| 2 | **U-Boot SPL** | OCRAM, EL3 | the module EEPROM (DART / SOM / SMARC, RAM size, revision) | trains LPDDR4, then reads the FIT: BL31 → OCRAM `0x0097_0000`, U-Boot + the matching DTB → DDR `0x4020_0000` | jump to BL31 |
| 3 | **TF-A BL31** | OCRAM, EL3 | – | installs the secure monitor (`smc` vector), programs TZASC/CSU/RDC, starts OP-TEE if present | `eret` to EL2, non-secure |
| 4 | **U-Boot proper** | DDR, EL2 | its environment, `/boot` on partition 1 | `bsp_bootcmd`: picks the kernel DTB, sets `bootargs`, loads + unzips `Image.gz` ([flow](03-uboot.md#the-boot-decision-flow)) | `booti` |
| 5 | **Linux** | DDR, EL2 → EL1 | the DTB and `root=` | starts CPUs 1–3 through BL31 (PSCI), probes drivers, mounts `mmcblk1p1` | exec `/sbin/init` |
| 6 | **init** | EL0 | `/etc/inittab` (Alpine) or systemd units (Debian) | mounts, logging, modules, network, `login:` ([flow](05-rootfs.md)) | – |

## 3. Inside imx-boot.bin

![Inside imx-boot.bin](images/imx-boot-anatomy.svg)

`imx-boot.bin` (also called `flash.bin`) is NXP's container: an **IVT header**
the Boot ROM understands, then the SPL with the DDR firmware appended, then a
**FIT image**, U-Boot's own container format, holding U-Boot, BL31 and one
device tree per supported module. The SPL picks the FIT configuration that
matches the module it detected.

List the FIT yourself after a build:

```bash
build/src/uboot-imx/tools/dumpimage -l build/src/imx-mkimage/iMX8M/u-boot.itb
xxd -l 16 build/deploy/imx-boot.bin      # d100 2041 … = IVT tag 0xD1, length 0x2000, version 0x41
```

## 4. Where things live in RAM

![Where things live in RAM](images/memory-map.svg)

- **On-chip RAM (OCRAM, 576 KiB)** holds the SPL during boot and **BL31 forever**.
- **DDR starts at `0x4000_0000`.** The first 64 MiB is U-Boot's scratch area
  during boot: it loads `Image.gz` to `img_addr`, unzips it to `loadaddr`, and
  `booti` moves it to its final 2 MiB-aligned home at `0x4060_0000`.
- At runtime Linux reserves **256 MiB for the GPU**, **~31 MiB for the audio
  DSP**, **64 MiB of bounce buffers**, and a **704 MiB CMA pool** for
  camera/video/GPU buffers. That's why `free -m` shows 3.6 of the 4 GiB.

## 5. Storage, the SD card and the names

![Storage across the layers](images/storage-map.svg)

| Offset on the card | Content | Why there |
| --- | --- | --- |
| 0 | MBR, one partition entry | standard PC partition table |
| **32 KiB** | `imx-boot.bin` (~1.7 MB) | fixed by the i.MX8M Boot ROM for SD/eMMC user area (`IMX_BOOT_SEEK = "32"`) |
| **7 MiB** | U-Boot environment (16 KiB) | `CONFIG_ENV_OFFSET = 0x700000`, written by `saveenv` |
| **8 MiB** → end | partition 1, ext4, label `root` | starts past both of the above, so they can never overlap |

U-Boot works out which device it booted from (`mmcautodetect=yes`) and passes
the matching `root=/dev/mmcblkXp1`. So the same image works on the SD card
(`mmcblk1`) and on the eMMC (`mmcblk2`).

## 6. Which repository builds what

| Stage | File | Built from | Command |
| --- | --- | --- | --- |
| DDR training FW | `lpddr4_pmu_train_{1d,2d}_{imem,dmem}_202006.bin` | NXP `firmware-imx` 8.32 (binary, EULA) | `./build.sh uboot firmware` |
| BL31 | `bl31.bin` | `varigit/imx-atf` | `./build.sh uboot atf` |
| SPL + U-Boot | `u-boot-spl.bin`, `u-boot-nodtb.bin`, 3 DTBs | `varigit/uboot-imx` | `./build.sh uboot uboot` |
| the container | `imx-boot.bin` | `varigit/imx-mkimage` | `./build.sh uboot mkimage` |
| kernel, DTBs, modules | `/boot/Image.gz`, `/boot/*.dtb`, `/lib/modules` | `varigit/linux-imx` | `./build.sh kernel` |
| userspace | everything else in `/` | Debian / Alpine / your tarball | `./build.sh rootfs` |
| the card | `sdcard.img` | this repo (`scripts/image.sh`) | `./build.sh image` |

## 7. Watch it happen

On the serial console during boot, each stage announces itself. This is the
real sequence from a VAR-SOM-MX8M-PLUS, annotated in
[07 · Flashing & first boot](07-flashing-and-boot.md#4-what-a-good-boot-looks-like):

```text
U-Boot SPL 2026.04-g9ee215f6a578 …            ← stage 2 (DDR training is silent)
Trying to boot from BOOTROM                    ← SPL reads the FIT via the Boot ROM API
U-Boot 2026.04-g9ee215f6a578 …                 ← stage 4 (BL31 runs silently in between)
Model: Variscite VAR-SOM-MX8M-PLUS on Symphony-Board
fdt_file=imx8mp-var-som-1.x-symphony.dtb
Starting kernel ...
[    0.000000] Booting Linux on physical CPU 0x0000000000 [0x410fd034]
[    0.005832] CPU: All CPU(s) started at EL2
[    3.440270] Run /sbin/init as init process  ← stage 6
```

---

← [Main README](../README.md) · [Index](README.md) · [02 · Host setup](02-host-setup.md) →
