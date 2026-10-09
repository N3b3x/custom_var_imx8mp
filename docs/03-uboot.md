# 03 · The bootloader: firmware, TF-A, U-Boot, imx-mkimage

[Docs](README.md) › **03 · U-Boot**

```bash
./build.sh uboot              # all four steps → build/deploy/imx-boot.bin
./build.sh uboot atf          # or one step at a time: firmware | atf | uboot | mkimage
./build.sh --dry-run uboot    # print every command with its explanation
```

The rest of this page shows what `scripts/uboot.sh` does, by hand. It's the
same sequence the script prints in `--dry-run` mode, so you can follow it in a
plain shell. It is also exactly what Variscite's Yocto recipes (`u-boot-variscite`,
`imx-atf`, `imx-boot`) do.

## 0. Environment

```bash
export B=$PWD/build                      # where everything goes
export PATH=$B/toolchain/arm-gnu-toolchain-14.3.rel1-x86_64-aarch64-none-linux-gnu/bin:$PATH
export CROSS_COMPILE=aarch64-none-linux-gnu-
```

`CROSS_COMPILE` is the prefix put in front of `gcc`, `ld`, `objcopy`, and so on.
Every Makefile below uses it to find the ARM64 tools.

## 1. DDR training firmware

```bash
cd $B/work
wget https://www.nxp.com/lgfiles/NMG/MAD/YOCTO/firmware-imx-8.32-1991416.bin
echo '11396e5798b62cd61963db806c0c05500887bc62a98e1d16dbc3014aa0c21a2a  firmware-imx-8.32-1991416.bin' | sha256sum -c
chmod +x firmware-imx-8.32-1991416.bin
./firmware-imx-8.32-1991416.bin --auto-accept      # shows/accepts the NXP EULA, unpacks a directory
ls firmware-imx-8.32-1991416/firmware/ddr/synopsys/lpddr4_pmu_train_*_202006.bin
```

The DART-MX8M-PLUS uses **LPDDR4**. The DDR PHY is a Synopsys IP that has to be
trained (signal timing calibrated) at every power-up. The SPL does this by
loading these four firmware blobs into the PHY's microcontroller:
1D/2D training × instruction/data memory. `_202006` is the firmware version
that `soc.mak` expects for the i.MX8MP (`LPDDR_FW_VERSION = _202006`).

## 2. TF-A (BL31)

```bash
git clone --depth 1 -b lf_v2.12_6.18.2-1.0.0_var01 https://github.com/varigit/imx-atf.git $B/src/imx-atf
make -C $B/src/imx-atf -j$(nproc) CROSS_COMPILE=$CROSS_COMPILE \
     PLAT=imx8mp IMX_BOOT_UART_BASE=auto E=0 bl31
ls $B/src/imx-atf/build/imx8mp/release/bl31.bin
```

| Argument | Meaning |
| --- | --- |
| `PLAT=imx8mp` | i.MX 8M Plus platform port (memory map, power domains, GPC) |
| `bl31` | build only BL31; i.MX does not use BL1/BL2 (the Boot ROM and SPL do their job) |
| `IMX_BOOT_UART_BASE=auto` | print on the UART the SPL already set up. The default is UART2 (0x30890000), but the DART debug console is UART1 |
| `E=0` | warnings are not errors. Vendor trees often lag behind new GCC warnings |

TF-A has no `CC=ccache` here on purpose. Its toolchain auto-detection looks at
`$(CC)` and gets confused by a wrapper. The old scripts had this bug.

## 3. U-Boot

```bash
git clone --depth 1 -b lf_v2026.04_6.18.20-2.0.0_var01 https://github.com/varigit/uboot-imx.git $B/src/uboot-imx
cd $B/src/uboot-imx
make ARCH=arm CROSS_COMPILE=$CROSS_COMPILE imx8mp_var_dart_defconfig
make ARCH=arm CROSS_COMPILE=$CROSS_COMPILE -j$(nproc)
make ARCH=arm CROSS_COMPILE=$CROSS_COMPILE u-boot-initial-env
```

- `ARCH=arm` is correct for U-Boot even on 64-bit. U-Boot keeps arm and arm64
  in one `arch/arm` directory, which is not how Linux does it.
- `imx8mp_var_dart_defconfig` covers **DART-MX8M-PLUS, VAR-SOM-MX8M-PLUS and
  VAR-SMARC-MX8M-PLUS**. The SPL reads the module's EEPROM and adapts
  (DDR size, PMIC, which DTB).
- The build needs `cert-to-efi-sig-list` (package `efitools`), because the
  defconfig enables authenticated EFI capsule updates.

Outputs used in the next step:

| File | What |
| --- | --- |
| `spl/u-boot-spl.bin` | the SPL |
| `u-boot-nodtb.bin` | U-Boot proper without a device tree |
| `arch/arm/dts/imx8mp-var-dart-sonataboard.dtb` | U-Boot's DTB for DART on the Sonata (ex-DT8MCustomBoard) |
| `arch/arm/dts/imx8mp-var-som-symphony.dtb` | ... for VAR-SOM-MX8M-PLUS on Symphony |
| `arch/arm/dts/imx8mp-var-smarc-echo.dtb` | ... for VAR-SMARC-MX8M-PLUS on Echo |
| `tools/mkimage` | host tool that builds FIT images |
| `u-boot-initial-env` | the default environment as text |

## 4. imx-mkimage → flash.bin

```bash
git clone --depth 1 -b lf-6.18.20_2.0.0_var01 https://github.com/varigit/imx-mkimage.git $B/src/imx-mkimage
S=$B/src/imx-mkimage/iMX8M          # the "SOC_DIR" for all i.MX8M variants
cp $B/work/firmware-imx-8.32-1991416/firmware/ddr/synopsys/lpddr4_pmu_train_*_202006.bin $S/
cp $B/src/imx-atf/build/imx8mp/release/bl31.bin  $S/
cp $B/src/uboot-imx/spl/u-boot-spl.bin           $S/
cp $B/src/uboot-imx/u-boot-nodtb.bin             $S/
cp $B/src/uboot-imx/u-boot.bin                   $S/
cp $B/src/uboot-imx/tools/mkimage                $S/mkimage_uboot
cp $B/src/uboot-imx/arch/arm/dts/imx8mp-var-{dart-sonataboard,som-symphony,smarc-echo}.dtb $S/

cd $B/src/imx-mkimage      # must be cd, not make -C: its Makefile uses $(PWD)
make SOC=iMX8MP \
     dtbs="imx8mp-var-dart-sonataboard.dtb imx8mp-var-som-symphony.dtb imx8mp-var-smarc-echo.dtb" \
     MKIMAGE=./mkimage_uboot flash_evk
cp $S/flash.bin $B/deploy/imx-boot.bin
```

What `flash_evk` does (see `iMX8M/soc.mak`):

1. Pads `u-boot-spl.bin` and appends the four DDR blobs → `u-boot-spl-ddr.bin`.
2. `mkimage_fit_atf.sh` writes `u-boot.its`, a FIT description holding
   U-Boot, BL31 (load address 0x970000) and one configuration per DTB.
3. `mkimage_uboot -f u-boot.its u-boot.itb` builds the FIT.
4. `mkimage_imx8` (compiled from `mkimage_imx8.c` on the fly) adds the
   i.MX8M IVT/boot-data headers the Boot ROM understands, and concatenates
   SPL-ddr and the FIT into `flash.bin`.

Its output ends with an "IVT HEADER" and "OFFSET dump", which is normal.
`csf_off`/`sld_csf_off` are where HAB signatures would go for secure boot.

## Writing just the bootloader

```bash
sudo dd if=build/deploy/imx-boot.bin of=/dev/sdX bs=1K seek=32 conv=fsync
# or
./build.sh flash --bootloader-only -d /dev/sdX
```

This leaves the partition table and partition 1 untouched (they start at
8 MiB). Only the 32 KiB to ~1.8 MiB region is rewritten.

## The U-Boot environment, and how the kernel is found

Read `build/deploy/u-boot-initial-env`. The important variables are:

```
bootcmd=run bsp_bootcmd
bootdir=/boot
image=Image.gz
mmcpart=1
console=ttymxc0,115200
loadimage=load mmc ${mmcdev}:${mmcpart} ${img_addr} ${bootdir}/${image}; unzip ${img_addr} ${loadaddr}
findfdt=...  sets fdt_file=<module><suffix>-<carrier>.dtb
mmcargs=setenv bootargs ... console=${console} root=/dev/mmcblk${mmcblk}p${mmcpart} rootwait rw ...
```

So the boot sequence is:

1. `mmc dev ${mmcdev}`: the device it booted from (1 = SD, 2 = eMMC).
2. If `/boot/boot.scr` exists, run it (full control, see below).
3. Otherwise, if `/boot/uEnv.txt` exists, import variables from it.
4. Load `/boot/Image.gz` and decompress it (`unzip`). The i.MX8M can't boot a compressed `Image` directly.
5. `findfdt` builds the DTB name from what the SPL detected:
   - module: `imx8mp-var-dart` / `imx8mp-var-som` / `imx8mp-var-smarc`
   - suffix: `-1.x` for SOM revision < 2.0, `-wbe` for WBE modules, else none
   - carrier: `sonata` / `symphony` / `echo`, or `${carrier_name}` if set
   - e.g. `imx8mp-var-dart-sonata.dtb`
6. Load `/boot/${fdt_file}`, set `bootargs`, then `booti`.

### Overriding things without rebuilding: `/boot/uEnv.txt`

Put `name=value` lines in `/boot/uEnv.txt` on the card's root partition:

```
# use a camera variant of the device tree
fdt_file=imx8mp-var-dart-sonata-basler-isp0.dtb
# add kernel command-line arguments
kernelargs=loglevel=7 systemd.log_level=debug
```

`kernelargs` is appended by `optargs`. You can also stop autoboot (press any
key on the serial console) and use `printenv`, `setenv`, `saveenv`. `saveenv`
writes to 7 MiB on the same card. To return to the defaults, run
`env default -a; saveenv`.

---

← [02 · Host setup](02-host-setup.md) · [Index](README.md) · [04 · Kernel](04-kernel.md) →
