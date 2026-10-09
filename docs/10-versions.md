# 10 · Versions: where they come from and how to change them

[Docs](README.md) › **10 · Versions**

## The source of truth

A Variscite BSP release is a **set** of branches that are tested together:
U-Boot, TF-A, imx-mkimage, NXP firmware and the kernel. Variscite publishes each
set in its Yocto layer **`meta-variscite-bsp-imx`**, one branch per release,
named `<yocto-codename>_<nxp-release>_varNN`. The defaults in
`config/imx8mp-var-dart.conf` are copied 1:1 from these files of branch
[`wrynose_6.18.20_2.0.0_var01`](https://github.com/varigit/meta-variscite-bsp-imx/tree/wrynose_6.18.20_2.0.0_var01):

| Setting | File in the layer |
| --- | --- |
| `UBOOT_BRANCH`, `UBOOT_REV` | `recipes-bsp/u-boot/u-boot-common.inc` |
| `UBOOT_DEFCONFIG`, `UBOOT_DTBS`, DDR firmware names, `IMXBOOT_TARGETS` | `conf/machine/imx8mp-var-dart.conf` |
| `ATF_BRANCH`, `ATF_REV` | `recipes-bsp/imx-atf/imx-atf_*.bbappend` |
| `MKIMAGE_*` | `recipes-bsp/imx-mkimage/imx-boot_1.0.bbappend` |
| `KERNEL_BRANCH`, `KERNEL_REV` | `recipes-kernel/linux/linux-variscite-imx_*.bb` |
| `KERNEL_DEFCONFIG`, `KERNEL_IMAGE` | `recipes-kernel/linux/linux-variscite.inc`, `conf/machine/include/variscite.inc` |
| `FIRMWARE_IMX_*` | NXP's [`meta-imx`](https://github.com/nxp-imx/meta-imx) branch `wrynose-6.18.20-2.0.0`, `meta-imx-bsp/recipes-bsp/firmware-imx/firmware-imx-8.32.inc` |

## Finding newer releases

```bash
# Variscite's BSP releases (newest last)
git ls-remote --heads https://github.com/varigit/meta-variscite-bsp-imx.git | sed 's#.*refs/heads/##' | sort -V | tail
# matching component branches
git ls-remote --heads https://github.com/varigit/uboot-imx.git | grep lf_v  | sed 's#.*refs/heads/##' | sort -V | tail -5
git ls-remote --heads https://github.com/varigit/linux-imx.git | grep lf-   | sed 's#.*refs/heads/##' | sort -V | tail -5
git ls-remote --heads https://github.com/varigit/imx-atf.git   | grep lf_v  | sed 's#.*refs/heads/##' | sort -V | tail -5
```

When a new `meta-variscite-bsp-imx` branch shows up:

1. Clone it (`git clone --depth 1 -b <branch> ...`) and read the files in the
   table above.
2. Copy the new values into `config/local.conf` (to try them) or into
   `config/imx8mp-var-dart.conf` (to adopt them).
3. Check `conf/machine/imx8mp-var-dart.conf` for renamed DTBs. The carrier
   was renamed from `dt8mcustomboard` to `sonata` between 6.12 and 6.18.
4. `./build.sh --update all`.

## Release history for the i.MX8MP (as of October 2026)

| Yocto | NXP release | Kernel | U-Boot | TF-A | firmware-imx |
| --- | --- | --- | --- | --- | --- |
| **wrynose (6.0)** ← default | LF6.18.20-2.0.0 | 6.18.20 | 2026.04 | 2.12 | 8.32 |
| walnascar (5.2) | LF6.12.49-2.2.0 | 6.12.49 | 2025.04 | 2.12 | 8.30 |
| scarthgap (5.0 LTS) | LF6.6.52-2.2.2 | 6.6.52 | 2024.04 | 2.10 | 8.26.1 |
| mickledore (4.2) | LF6.1.x | 6.1 | 2023.04 | 2.8 | (older) |

The old scripts in this repo used a mix of mickledore U-Boot (`lf_v2023.04_var02`),
a 6.6 kernel and an imx-mkimage from 6.6.3, which don't belong to one release.

## Ready-made sets

Paste one block into `config/local.conf`, then run
`./build.sh --update clean all`. If you switch releases back and forth,
`./build.sh distclean` first is the safest way.

### LF6.12.49-2.2.0 (walnascar)

```bash
BSP_RELEASE=walnascar-6.12.49-2.2.0
UBOOT_BRANCH=lf_v2025.04_6.12.49-2.2.0_var01;   UBOOT_REV=7cb5bd8609ce1c8125020b657a271e4de68d1a7e
UBOOT_DTBS="imx8mp-var-dart-dt8mcustomboard.dtb imx8mp-var-som-symphony.dtb"
ATF_BRANCH=lf_v2.12_6.12.49-2.2.0_var01;        ATF_REV=340d43238f75cda11e2ef2ac21fc90b4b2f120e6
MKIMAGE_REPO=https://github.com/nxp-imx/imx-mkimage.git
MKIMAGE_BRANCH=lf-6.12.49_2.2.0;                MKIMAGE_REV=
KERNEL_BRANCH=lf-6.12.y_6.12.49-2.2.0_var01;    KERNEL_REV=7dbf6439c73ed95f0930cc17b5a75a56527168f8
FIRMWARE_IMX_VERSION=8.30; FIRMWARE_IMX_HASH=3fa84fd
FIRMWARE_IMX_SHA256=154b1b5890ddebe45ca280634260a8cdaf38adc5b303aeea28a5ebad504a7912
```

This release uses NXP's plain imx-mkimage plus two Variscite patches. Copy them
from that layer branch into `patches/mkimage/`:
`recipes-bsp/imx-mkimage/imx-boot/0001-iMX8M-soc-allow-dtb-override.patch` and
`0002-iMX8M-soc-change-padding-of-DDR4-and-LPDDR4-DMEM-fir.patch`.

### LF6.6.52-2.2.2 (scarthgap)

```bash
BSP_RELEASE=scarthgap-6.6.52-2.2.2
UBOOT_BRANCH=lf_v2024.04_6.6.52-2.2.2_var01;    UBOOT_REV=67a30623a4a8ad64d89b6a10778777feeb57a256
UBOOT_DTBS="imx8mp-var-dart-dt8mcustomboard.dtb imx8mp-var-som-symphony.dtb imx8mp-var-smarc-echo.dtb"
ATF_BRANCH=lf_v2.10_6.6.52-2.2.2_var01;         ATF_REV=c7dc539a4ca1191360fa6601d7b0aaecb299ddbc
MKIMAGE_BRANCH=lf-6.6.52_2.2.2_var01;           MKIMAGE_REV=ea9b5711be09523c51c403a59bdd473b049c2c34
KERNEL_BRANCH=lf-6.6.y_6.6.52-2.2.2_var01;      KERNEL_REV=ee940cc7caf559e62afa9887591db60de979ee22
FIRMWARE_IMX_VERSION=8.26.1; FIRMWARE_IMX_HASH=410be01
FIRMWARE_IMX_SHA256=0c2e2136c1efa544409017f14f07a1412cf8c1702075ed0e4060e903b91fe313
```

> Only the **default (wrynose)** set is build-tested by this repository. The
> older sets are transcribed from Variscite's layers and should work the same
> way, but verify them on your hardware.

## Toolchain

| Option | Compiler |
| --- | --- |
| `TOOLCHAIN=arm` (default) | Arm GNU Toolchain `14.3.rel1` (GCC 14.3.1), downloaded and sha256-checked |
| `ARM_TOOLCHAIN_VERSION=15.2.rel1` + its sha256 | GCC 15.2 (what Yocto wrynose uses) |
| `TOOLCHAIN=system` | your distro's `aarch64-linux-gnu-gcc` |

Arm's release list: <https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads>
(file `arm-gnu-toolchain-<ver>-x86_64-aarch64-none-linux-gnu.tar.xz`. Its
`.sha256asc` sits next to it).

---

← [09 · Troubleshooting](09-troubleshooting.md) · [Index](README.md) · [11 · Using the board](11-using-the-board.md) →
