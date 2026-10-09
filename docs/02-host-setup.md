# 02 · Host setup

[Docs](README.md) › **02 · Host setup**

## Supported hosts

Built and verified end-to-end on **Ubuntu 22.04** (x86-64). Ubuntu 24.04 and
Debian 12 / 13 use the same package names and are expected to work the same.
Any reasonably modern Linux works if you install the equivalent packages
yourself, because `./build.sh deps` only automates apt.

| Resource | Needed |
| --- | --- |
| Disk | ~12 GB (kernel tree + objects ~7 GB, toolchain 1 GB, U-Boot/ATF 1 GB, images) |
| RAM | 8 GB minimum, 16 GB+ comfortable with `-j$(nproc)` |
| CPU | Any. Measured on 12 cores: U-Boot+TF-A ~1.5 min, kernel ~25 min the first time; an unchanged `./build.sh all` takes ~30 s |
| Network | GitHub, developer.arm.com, nxp.com, deb.debian.org / dl-cdn.alpinelinux.org |

## Packages

```bash
./build.sh deps            # lists what is missing
./build.sh deps --install  # sudo apt-get install the missing ones
```

What each package is for:

| Package(s) | Why |
| --- | --- |
| `build-essential git make bc bison flex` | basic build of U-Boot and Linux (Kconfig uses bison/flex, the kernel uses bc) |
| `libssl-dev libelf-dev libgnutls28-dev uuid-dev` | host tools: kernel module signing, `mkimage`, `mkeficapsule` |
| `efitools` | `cert-to-efi-sig-list`. Variscite's U-Boot enables signed UEFI capsule updates (`CONFIG_EFI_CAPSULE_AUTHENTICATE`), and the build turns `CRT.crt` into an EFI signature list |
| `python3 python3-dev python3-setuptools python3-pyelftools swig` | U-Boot's Python helpers (binman, pylibfdt) |
| `libncurses-dev` | `menuconfig` |
| `kmod` | `depmod`, used by `make modules_install` |
| `cpio rsync xz-utils zstd` | kernel build helpers, archives |
| `fakeroot e2fsprogs fdisk` | building the SD image **without root**: `fakeroot`, `mke2fs -d`, `sfdisk` |
| `bmap-tools` | `.bmap` files: flashing writes only used blocks and verifies them |
| `mmdebstrap qemu-user-static binfmt-support uidmap` | building the Debian arm64 rootfs on an x86 PC (`uidmap` enables the rootless mode) |
| `ccache` | caches compiler output, so rebuilds are much faster |

## The cross toolchain

By default the scripts download the **Arm GNU Toolchain 14.3.rel1**
(`aarch64-none-linux-gnu-`, GCC 14.3) into `build/toolchain/` and check its
sha256. That gives the same compiler on every machine and needs no root.

On an **ARM64 host** (e.g. an ARM laptop or a Raspberry Pi 5 running Debian),
the script switches to the native `aarch64-linux-gnu-gcc` automatically,
because Arm publishes this cross toolchain for x86-64 hosts only.

```bash
# use Ubuntu's cross compiler instead
sudo apt install gcc-aarch64-linux-gnu
TOOLCHAIN=system ./build.sh all
```

To try GCC 15, change these lines in `config/local.conf`:

```bash
ARM_TOOLCHAIN_VERSION=15.2.rel1
ARM_TOOLCHAIN_SHA256=9a685b335bd709d683a8c782253c37e8c36c10e6924e59e39d4769b02132eb43
```

## NXP EULA

The LPDDR4 training firmware is in NXP's `firmware-imx` package, which is
covered by the [NXP Software License Agreement](https://www.nxp.com/docs/en/disclaimer/LA_OPT_NXP_SW.html).
The first `uboot` build asks you to accept it. To accept it non-interactively,
do one of these:

```bash
./build.sh --accept-eula all
echo 'ACCEPT_FSL_EULA=1' >> config/local.conf
```

## Personal settings: `config/local.conf`

`build.sh` sources `config/local.conf` (git-ignored) **before** the defaults
in `config/imx8mp-var-dart.conf`. Any variable set there wins:

```bash
# config/local.conf
ACCEPT_FSL_EULA=1
ROOTFS=alpine
TARGET_PASSWORD='something-better'
BUILD_DIR=/fast/ssd/imx8mp-build     # put the build tree somewhere else
JOBS=8
```

A single run can also take overrides on the command line:
`KERNEL_LOCALVERSION=-test ./build.sh kernel`. The order of precedence is
`local.conf` (plain assignments) > environment / command line > defaults.
To let the command line override a value in `local.conf`, write it there as
`: "${VAR:=value}"`.

---

← [01 · Boot flow](01-boot-flow.md) · [Index](README.md) · [03 · U-Boot](03-uboot.md) →
