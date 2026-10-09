# 08 · Customizing: your board, your patches, your versions

[Docs](README.md) › **08 · Customizing**

> **In this guide:** where to put each kind of change so it survives rebuilds
> and updates, with recipes for the common ones: your own carrier board,
> source patches, kernel options and versions.

![Where your changes go](images/customize-map.svg)

The rule of thumb: **never rely on edits inside `build/src/`**. That tree is
disposable (`distclean`, `--update`). Put changes in this repository instead,
in one of these places:

| You want to... | Put it in | Picked up by |
| --- | --- | --- |
| change a version, URL, password, package list... | `config/local.conf` | every script |
| add/remove kernel options | `config/kernel/*.cfg` | `kernel.sh` (when `.config` is created) |
| add a device tree for your own carrier board | `custom/dts/*.dts`, `*.dtsi` | `kernel.sh` |
| change source code of U-Boot / TF-A / mkimage / kernel | `patches/{uboot,atf,mkimage,kernel}/NNNN-*.patch` | the matching step, right after checkout |

## A device tree for your carrier board

You write **layer 3** only. The SoC and SoM layers stay Variscite's:

![How a device tree is built up in layers](images/dt-layers.svg)

1. Start from the closest Variscite file, e.g. DART on Sonata:

   ```bash
   cp build/src/linux-imx/arch/arm64/boot/dts/freescale/imx8mp-var-dart-sonata.dts \
      custom/dts/imx8mp-var-dart-mycarrier.dts
   ```

2. Edit it: change `model`, enable/disable nodes (`status = "okay"`), fix
   pinmux (`fsl,pins`), add your I2C/SPI devices. Keep the
   `#include "imx8mp-var-dart.dtsi"` so the module part stays Variscite's.
3. Build: `./build.sh kernel`. It shows up as
   `build/deploy/kernel/boot/imx8mp-var-dart-mycarrier.dtb`.
4. Tell U-Boot to use it. Either:
   - per card: `/boot/uEnv.txt` containing `fdt_file=imx8mp-var-dart-mycarrier.dtb`, or
   - per board: at the U-Boot prompt run `setenv fdt_file imx8mp-var-dart-mycarrier.dtb; saveenv`, or
   - keep the auto-detection and only change the carrier part:
     `setenv carrier_name mycarrier; saveenv`. `findfdt` then builds
     `imx8mp-var-dart[-1.x|-wbe]-mycarrier.dtb`.
5. Iterate quickly: `./build.sh kernel && ./build.sh flash -d /dev/sdX --kernel-only`.

> U-Boot has its own, smaller device tree (`imx8mp-var-dart-sonataboard.dts` in
> U-Boot). You only need to touch it if U-Boot itself needs hardware your
> carrier wires differently, such as the SD card-detect pin or the Ethernet PHY
> for network boot.

## Patches

Make the change in the checkout, commit it there, export it:

```bash
cd build/src/linux-imx
# ...edit...
git add -A && git commit -m "my-board: add touchscreen"
git format-patch -1 -o ../../../patches/kernel/      # creates 0001-my-board-add-touchscreen.patch
```

Patches are applied in file-name order with `git apply`, once per checkout.
The applied list is in `.git/applied-patches`. On a fresh checkout
(`distclean`, or deleting `build/src/<component>`) they are applied again.

> `--update` refuses to run while a checkout has uncommitted changes, so work
> is never thrown away silently. Commit or export your changes first.

## Changing versions

All versions live in `config/imx8mp-var-dart.conf`. To follow a branch tip
instead of the pinned commit, empty the `*_REV`:

```bash
# config/local.conf
KERNEL_REV=
UBOOT_REV=
```

Then `./build.sh --update all`.

Moving to another **release** (for example the 6.12 LTS line) means changing
the U-Boot, TF-A, mkimage and kernel branches **together**, as one Variscite
release. See [10-versions.md](10-versions.md) for ready-made sets and how to
read them from Variscite's Yocto layer.

## Changing the SD card layout

| Variable | Default | Notes |
| --- | --- | --- |
| `IMX_BOOT_SEEK_KB` | `32` | fixed by the i.MX8M Boot ROM for SD/eMMC, don't change |
| `ROOTFS_PART_START_MB` | `8` | must stay above 7 MiB + 16 KiB (U-Boot env) |
| `ROOTFS_LABEL` | `root` | also used in `/etc/fstab` |
| `IMAGE_EXTRA_MB` | `512` | free space in the image; `--expand` makes it irrelevant |

## Other boards of the family

`imx8mp_var_dart_defconfig` already covers **VAR-SOM-MX8M-PLUS** (Symphony)
and **VAR-SMARC-MX8M-PLUS** (Echo). The same `imx-boot.bin` and kernel boot
all three: the SPL detects the module and U-Boot's `findfdt` picks the DTB.
VAR-SOM-MX8M-PLUS and VAR-SMARC-MX8M-PLUS use UART2 (`ttymxc1`) as debug
console. U-Boot sets `console=ttymxc1,115200` for them by itself. Both
rootfs flavours follow the kernel's `console=` automatically: Debian through
systemd, Alpine through `/sbin/console-getty`. So the same SD card gives a login
prompt on every module.

---

← [07 · Flashing & first boot](07-flashing-and-boot.md) · [Index](README.md) · [09 · Troubleshooting](09-troubleshooting.md) →
