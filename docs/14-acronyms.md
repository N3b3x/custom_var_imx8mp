# 14 · Acronyms & terms: what they stand for and why they exist

[Docs](README.md) › **14 · Acronyms**

> **How to use this page:** every acronym that appears in the boot log, the
> device trees, the scripts or these docs, grouped from the silicon up to the
> shell. Each row says what it **stands for**, what it **is on this board**,
> and **why it exists**, the problem it solves. Search with Ctrl+F.

![Inside the i.MX 8M Plus](images/soc-map.svg)

**Groups:** [The chip and the board](#1-the-chip-and-the-board) ·
[Memory](#2-memory) · [Storage](#3-storage) · [Buses and I/O](#4-buses-and-io) ·
[Multimedia](#5-multimedia-and-ai) · [Security](#6-security-and-trustzone) ·
[Boot and firmware](#7-boot-and-firmware) · [CPU privilege and calls](#8-cpu-privilege-levels-and-calls) ·
[Device tree](#9-device-tree) · [Linux](#10-linux-kernel-and-userspace) ·
[Building](#11-building-and-tooling) · [Release names](#12-release-and-version-names)

---

## 1. The chip and the board

| Term | Stands for | On this board | Why it exists |
| --- | --- | --- | --- |
| **SoC** | System on Chip | the NXP i.MX 8M Plus | puts CPUs, GPU, memory controller and peripherals on one die: small, cheap, low-power |
| **SoM** | System on Module | the Variscite VAR-SOM-MX8M-PLUS / DART-MX8M-PLUS | the hard part (SoC + DDR + PMIC + eMMC, high-speed routing) done once, so your own board can be simple |
| **Carrier board** | – | Symphony, Sonata, Echo, or yours | connectors, power input and board-specific chips around the SoM |
| **BSP** | Board Support Package | this repo's output: firmware + bootloader + kernel + config | the board-specific software every OS needs before it can run on new hardware |
| **Cortex-A53** | Arm Cortex-A series, model 53 | 4 cores, up to 1.8 GHz, run Linux | efficient 64-bit application cores (Armv8.0-A) |
| **Cortex-M7** | Arm Cortex-M series, model 7 | 1 core, 800 MHz, idle unless you load firmware (the `-m7` DTBs) | hard real-time work (motor control, sensors) that Linux can't guarantee |
| **GIC** | Generic Interrupt Controller | routes ~160 hardware interrupts to the 4 cores | one standard Arm design so every OS handles interrupts the same way |
| **PMIC** | Power Management IC | PCA9450C on the SoM (`0-0025` on I2C1) | generates the ~10 voltages the SoC and DDR need, in the right order |
| **EEPROM** | Electrically Erasable Programmable ROM | on SoM and carrier: part number, revision, MAC, DDR info | lets one bootloader recognise many module and carrier variants |
| **GPC** | General Power Controller | powers cores and blocks on/off (used by BL31's PSCI) | saves power: unused blocks are switched off |
| **CCM** | Clock Control Module | generates every clock in the SoC | each block needs its own frequency, and some must change at runtime |
| **WDOG** | Watchdog | `/dev/watchdog0` | resets a hung system automatically, essential for unattended devices |

## 2. Memory

| Term | Stands for | On this board | Why it exists |
| --- | --- | --- | --- |
| **ROM** | Read-Only Memory | the Boot ROM inside the SoC | the first code after reset must exist before anything is loaded |
| **OCRAM** | On-Chip RAM | 576 KiB at `0x0090_0000`: SPL, then BL31 | usable immediately after reset, unlike DDR, which needs training |
| **DDR / LPDDR4** | (Low-Power) Double Data Rate SDRAM, generation 4 | 4 GiB at `0x4000_0000` | large, fast, cheap main memory; "LP" = phone-class low power |
| **DDRC** | DDR Controller | turns CPU reads/writes into DDR commands | DDR has a complex protocol (refresh, banks, timing) |
| **PHY** | Physical layer | DDR PHY, Ethernet PHY, USB PHY … | the analog part that drives the actual wires, separate from the digital controller |
| **Training** | – | `lpddr4_pmu_train_*_202006.bin` run on the DDR PHY | every board's traces differ slightly; timing must be calibrated at each power-up |
| **MT/s** | Mega-Transfers per second | the i.MX 8M Plus supports LPDDR4 up to 4000 MT/s | DDR moves data on both clock edges, so transfers ≠ MHz |
| **CMA** | Contiguous Memory Allocator | `cma=704M` | GPU/VPU/camera need large *physically contiguous* buffers; CMA reserves them yet lends them to Linux when unused |
| **SWIOTLB** | Software I/O Translation Lookaside Buffer | 64 MiB of bounce buffers | lets devices that can only address 32 bits use memory above 4 GiB |
| **MMU** | Memory Management Unit | in each A53 core | virtual memory: process isolation, `mmap`, protection |

## 3. Storage

| Term | Stands for | On this board | Why it exists |
| --- | --- | --- | --- |
| **uSDHC** | Ultra Secured Digital Host Controller | uSDHC1 Wi-Fi, uSDHC2 SD card, uSDHC3 eMMC | NXP's SD/MMC controller block |
| **SD** | Secure Digital (card) | the card you flash, `mmcblk1` | removable, easy to reflash: ideal for development |
| **eMMC** | embedded MultiMediaCard | 29 GiB chip on the SoM, `mmcblk2` | soldered, more reliable flash for products |
| **SDIO** | SD Input/Output | the Wi-Fi/BT module interface (uSDHC1) | reuses the SD bus for non-storage devices |
| **boot0 / boot1** | eMMC boot partitions | `mmcblk2boot0/1`, 4 MiB each | hardware-separate areas for the bootloader, safe from partition edits |
| **RPMB** | Replay Protected Memory Block | `mmcblk2rpmb` | authenticated storage for secure counters/keys (used by OP-TEE) |
| **MBR** | Master Boot Record | the partition table in the first 512 bytes of `sdcard.img` | simplest table, understood by every tool and by U-Boot |
| **ext4** | fourth extended filesystem | partition 1, label `root` | Linux's standard journaled filesystem, readable by U-Boot |
| **bmap** | block map | `sdcard.img.bmap` | lists which blocks hold data, so flashing skips the empty ones |

## 4. Buses and I/O

| Term | Stands for | On this board | Why it exists |
| --- | --- | --- | --- |
| **I2C** | Inter-Integrated Circuit | 6 controllers; `i2c-0/2/3` in use: PMIC, RTC, expanders, touch, codec | 2 wires, many slow chips, each with an address |
| **SPI / ECSPI** | Serial Peripheral Interface / Enhanced Configurable SPI | resistive touch controller | faster than I2C, 4 wires, one chip-select per device |
| **UART** | Universal Asynchronous Receiver-Transmitter | 4: `ttymxc0-3`; console on `ttymxc1` (SOM) | the simplest serial port, so it works before anything else does |
| **GPIO** | General-Purpose Input/Output | 5 banks + expanders, `/dev/gpiochipN` | pins software can read or drive: LEDs, buttons, resets |
| **PCA9534 / PCAL6408** | NXP I2C GPIO expander parts | `2-0020` works, `3-0021` absent on your carrier | more GPIOs when the SoC runs out of pins |
| **CAN / FlexCAN** | Controller Area Network / NXP's CAN block | `can0` | robust bus for vehicles and industry |
| **USB** | Universal Serial Bus | 2× USB 3.0 | – |
| **PCIe** | Peripheral Component Interconnect Express | 1 lane, Gen3 (waits for `3-0021` here) | high-speed expansion: Wi-Fi 6, NVMe, FPGAs |
| **EQoS** | Ethernet Quality-of-Service (Synopsys DWMAC) | `eth0`, its PHY is absent on your SoM | Ethernet with **TSN** (Time-Sensitive Networking) for deterministic traffic |
| **FEC** | Fast Ethernet Controller (NXP; gigabit despite the name) | `eth1` + ADIN1300 PHY on the carrier | the classic i.MX Ethernet MAC |
| **MAC** | Media Access Control | the Ethernet controller and its address `f8:dc:7a:…` | – |
| **MDIO** | Management Data Input/Output | "MDIO device at address 4 is missing" | the bus the MAC uses to configure its PHY |
| **RGMII** | Reduced Gigabit Media-Independent Interface | `phy-mode = "rgmii"` | the wires between MAC and PHY |
| **SDMA** | Smart Direct Memory Access | needs firmware `sdma-imx7d.bin` | copies data for SPI/UART/audio without the CPU |
| **DMA** | Direct Memory Access | – | devices move data to RAM themselves; the CPU stays free |
| **PWM** | Pulse-Width Modulation | backlight, buzzer | analog-like control from a digital pin |

## 5. Multimedia and AI

| Term | Stands for | On this board | Why it exists |
| --- | --- | --- | --- |
| **GPU** | Graphics Processing Unit | Vivante GC7000UL 3D + GC520L 2D, driver `galcore` | 3D/2D drawing, compositing, OpenGL ES/Vulkan |
| **VPU** | Video Processing Unit | Hantro H.264/H.265 decoder + VC8000E encoder (`/dev/mxc_hantro*`) | plays and records video without burning CPU |
| **NPU** | Neural Processing Unit | 2.3 TOPS | runs AI models (TOPS = Tera Operations Per Second) |
| **ISP** | Image Signal Processor | 2× | turns raw camera sensor data into a usable picture |
| **ISI** | Image Sensing Interface | `mxc_isi.0` | camera capture path / colour conversion |
| **MIPI CSI / DSI** | Mobile Industry Processor Interface, Camera / Display Serial Interface | camera in / display out | phone-industry standard high-speed links |
| **LVDS** | Low-Voltage Differential Signalling | the 800×480 panel (`LVDS-1 connected`) | robust, cheap link for industrial displays |
| **HDMI** | High-Definition Multimedia Interface | `HDMI-A-1` | monitors and TVs |
| **LCDIF** | LCD Interface | 3 display engines | reads the framebuffer and sends pixels to a display link |
| **DSP** | Digital Signal Processor | Cadence HiFi4, reserved memory `dsp@92400000` | audio processing offloaded from the A53s |
| **SAI / PDM** | Synchronous Audio Interface / Pulse-Density Modulation | the WM8904 codec / digital microphones | audio in and out |

## 6. Security and TrustZone

| Term | Stands for | On this board | Why it exists |
| --- | --- | --- | --- |
| **TrustZone** | Arm's security extension | secure vs. normal world on every bus access | lets one chip run untrusted (Linux) and trusted code isolated from each other |
| **TZASC / TZC-380** | TrustZone Address Space Controller (Arm part TZC-380) | enabled, region 0 open | marks DDR regions secure-only; blocks Linux from them |
| **CSU** | Central Security Unit | all peripherals open to both worlds here | per-peripheral secure/non-secure access |
| **RDC** | Resource Domain Controller | – | which master (A53, M7, DMA) may use which peripheral |
| **AIPSTZ** | AHB-to-IP-bus bridge with TrustZone | – | peripheral bus bridges enforcing access rules |
| **CAAM** | Cryptographic Acceleration and Assurance Module | `caam` driver, hardware RNG | fast AES/SHA/RSA and a true random generator |
| **SNVS** | Secure Non-Volatile Storage | power key `snvs-powerkey`, secure RTC | security state that survives a power-off |
| **HAB** | High Assurance Boot | not enabled (empty CSF slot) | the Boot ROM checks a signature before running `imx-boot`: secure boot |
| **CSF** | Command Sequence File | the empty slot in `imx-boot.bin` | carries HAB signatures and certificates |
| **OTP / OCOTP / eFuse** | One-Time Programmable / On-Chip OTP controller | MAC address, boot settings, HAB key hash | settings that can be burned once, permanently |
| **TEE / REE** | Trusted / Rich Execution Environment | none / Linux | the secure world's OS (OP-TEE) vs. the normal OS |
| **TA** | Trusted Application | – | small programs that run inside OP-TEE on secrets |
| **RNG** | Random Number Generator | CAAM | keys need real randomness |

## 7. Boot and firmware

| Term | Stands for | On this board | Why it exists |
| --- | --- | --- | --- |
| **SPL** | Secondary Program Loader | `u-boot-spl.bin`, 107 KiB, in OCRAM | U-Boot proper is too big for OCRAM; a small first stage brings up DDR |
| **IVT** | Image Vector Table | first bytes of `imx-boot.bin` (`d1 00 20 41`) | tells the Boot ROM where the code is and where to load it |
| **FIT / ITB / ITS** | Flattened Image Tree / Image Tree Blob / Image Tree Source | `u-boot.itb`: U-Boot + BL31 + 3 DTBs | one container for several images, with hashes and load addresses |
| **TF-A / ATF** | Trusted Firmware-A / Arm Trusted Firmware (old name) | `varigit/imx-atf` | Arm's reference secure-world firmware |
| **BL1 / BL2 / BL31 / BL32 / BL33** | Boot Loader stage 1 … 3-3 | ROM / SPL / TF-A / OP-TEE / U-Boot | TF-A's names for the boot stages; **not** privilege levels |
| **OP-TEE** | Open Portable Trusted Execution Environment | not built (optional) | open-source trusted OS for the secure world |
| **SPD** | Secure Payload Dispatcher | `SPD=opteed` when OP-TEE is used | the BL31 part that starts BL32 and forwards its calls |
| **PSCI** | Power State Coordination Interface | v1.1, method `smc` | one standard way for any OS to start/stop CPUs and reboot |
| **SMCCC** | SMC Calling Convention | v1.5 | how function IDs and arguments go into registers for an `smc` |
| **SiP** | Silicon Provider (service) | NXP's `0xC2…` calls: DDR DVFS, GPC … | chip-vendor-specific firmware services |
| **DVFS** | Dynamic Voltage and Frequency Scaling | CPU 1.2/1.6/1.8 GHz, DDR frequency | lower voltage and clock when idle, which saves power and heat |
| **EULA** | End-User License Agreement | NXP's, for `firmware-imx` | the DDR blobs are proprietary |
| **bootcmd** | – | `run bsp_bootcmd` | the U-Boot command run automatically after the countdown |

## 8. CPU privilege levels and calls

| Term | Stands for | On this board | Why it exists |
| --- | --- | --- | --- |
| **EL** | Exception Level | the CPU's current privilege "floor", hardware state (`PSTATE.EL`, readable as `CurrentEL`) | lets untrusted code run without being able to take over the machine. Full story: [13 §2](13-secure-world.md#2-who-runs-where-exception-levels-and-worlds) |
| **EL0** | Exception Level 0: application | `sh`, BusyBox, your program | no privileges, so a bug only crashes that process; asks the kernel for everything (`svc`) |
| **EL1** | Exception Level 1: OS kernel | Linux 6.18 | owns page tables, devices and interrupts for all apps; protects apps from each other |
| **EL2** | Exception Level 2: hypervisor | U-Boot during boot; Linux's KVM stub at runtime | second-stage page tables and traps let it run several OSes isolated from each other |
| **EL3** | Exception Level 3: secure monitor | TF-A BL31, forever | the only level that can switch secure ↔ normal world and route interrupts, so the secure world can be protected even from a compromised OS |
| **S-EL1** | Secure EL1 | where OP-TEE would run | an OS level inside the secure world |
| **svc** | Supervisor Call | every system call | how an app asks the kernel for something |
| **hvc** | Hypervisor Call | KVM | kernel → hypervisor |
| **smc** | Secure Monitor Call | PSCI CPU_ON at boot, `reboot` | kernel → BL31; the only door into the secure world |
| **eret** | Exception Return | BL31 → U-Boot at EL2 | the only way to go *down* a level |
| **SCR_EL3.NS** | Secure Configuration Register, Non-Secure bit | 1 while Linux runs | the single bit that selects the world; only EL3 can write it |
| **KVM / nVHE** | Kernel-based Virtual Machine / non-Virtualization Host Extensions mode | `kvm [1]: Hyp nVHE mode initialized` | Linux can host VMs; on Armv8.0 it keeps a stub at EL2 |
| **MPIDR** | Multiprocessor Affinity Register | CPU id in PSCI CPU_ON | identifies which core to start |

## 9. Device tree

| Term | Stands for | On this board | Why it exists |
| --- | --- | --- | --- |
| **DT** | Device Tree | `/proc/device-tree` | describes hardware that can't be auto-detected, so one kernel runs on many boards |
| **DTS / DTSI** | Device Tree Source / Source Include | `imx8mp-var-som-symphony.dts`, `imx8mp.dtsi` | human-readable; `.dtsi` = shared layers |
| **DTB / FDT** | Device Tree Blob / Flattened Device Tree | `/boot/*.dtb` | the compiled binary the kernel parses |
| **DTBO / DTSO** | Device Tree Blob/Source Overlay | `imx8mp-var-som-1.x.dtso` | patch a base DT without copying it (revisions, cameras) |
| **dtc** | Device Tree Compiler | runs during `./build.sh kernel` | DTS → DTB |
| **compatible** | – | `"dallas,ds1337"` | the string that binds a DT node to a driver |
| **pinctrl / IOMUX** | pin control / I/O multiplexer | `pinctrl-0 = <&pinctrl_usdhc2>` | each pin can serve several functions; the DT chooses one |

## 10. Linux kernel and userspace

| Term | Stands for | On this board | Why it exists |
| --- | --- | --- | --- |
| **Image / Image.gz** | the arm64 kernel binary / gzip-compressed | `/boot/Image.gz`, 15 MB → 34 MB | – |
| **LTS** | Long-Term Support | Linux 6.18 | years of security fixes for one version |
| **.ko** | kernel object (module) | `rtc-ds1307.ko`, ~27 loaded | drivers that load only when their hardware exists |
| **modalias** | module alias | `of:N…Cdallas,ds1337` | maps a device to the module that drives it |
| **depmod** | dependency module tool | writes `modules.dep`, `modules.alias` | lets `modprobe` resolve names and dependencies |
| **rootfs** | root filesystem | partition 1 | everything in `/` besides the kernel |
| **init / PID 1** | process ID 1 | BusyBox init or systemd | the first process; starts all others, can never exit |
| **getty / tty** | "get teletype" / teletypewriter | `getty` on `ttymxc1`, `tty1` | prints `login:` on a terminal |
| **ttymxc** | tty for the MXC (NXP i.MX) UART | `ttymxc1` = UART2 | the i.MX UART driver's device name |
| **BusyBox** | – | ~300 commands in one binary | tiny userspace for embedded systems |
| **musl / glibc** | C libraries | Alpine / Debian | the layer between programs and the kernel |
| **udev / mdev** | userspace device manager / mini-dev (BusyBox) | Debian / Alpine | create `/dev` nodes and load modules for hardware |
| **procfs / sysfs / devtmpfs** | process / system / device filesystems | `/proc`, `/sys`, `/dev` | the kernel's live views (see [11](11-using-the-board.md)) |
| **DHCP** | Dynamic Host Configuration Protocol | `udhcpc -i eth1` | gets an IP address automatically |
| **NTP** | Network Time Protocol | `ntpd -q -p pool.ntp.org` | sets the clock from the internet |
| **RTC** | Real-Time Clock | DS1337 → `/dev/rtc0` | keeps time while powered off |
| **SSH** | Secure Shell | Debian image | remote login |

## 11. Building and tooling

| Term | Stands for | On this board / repo | Why it exists |
| --- | --- | --- | --- |
| **Cross-compiler / toolchain** | – | `aarch64-none-linux-gnu-gcc` 14.3 | builds ARM64 code on an x86 PC |
| **GCC** | GNU Compiler Collection | 14.3 | – |
| **CROSS_COMPILE / ARCH** | make variables | `aarch64-none-linux-gnu-` / `arm64` | tell U-Boot/kernel/TF-A which compiler and architecture |
| **defconfig** | default configuration | `imx8_var_defconfig`, `imx8mp_var_dart_defconfig` | a saved, known-good `.config` |
| **Kconfig / menuconfig** | kernel configuration system / its menu UI | `./build.sh kernel-menuconfig` | thousands of options with dependencies |
| **ccache** | compiler cache | automatic | rebuilds are mostly cache hits |
| **fakeroot** | – | `image.sh`, Alpine rootfs | pretend to be root, so files are owned by root without sudo |
| **mmdebstrap** | – | Debian rootfs | builds a Debian root filesystem from packages |
| **qemu-user / binfmt** | QEMU user-mode emulator / binary format handler | runs arm64 binaries on the PC | package install scripts must run during the Debian build |
| **Yocto / BitBake** | – | what Variscite ships; this repo replaces it | a full distribution builder; heavy, but standard for products |

## 12. Release and version names

| Name | Meaning |
| --- | --- |
| `lf-6.18.20-2.0.0` | NXP i.MX Linux release naming: kernel **6.18.20**, NXP BSP release **2.0.0** |
| `_var01` | Variscite's first revision on top of that NXP release |
| `wrynose`, `walnascar`, `scarthgap`, `mickledore` | Yocto Project release code names (6.0, 5.2, 5.0 LTS, 4.2) |
| `lf_v2026.04` | U-Boot version 2026.04 (U-Boot uses year.month) |
| `lf_v2.12` | TF-A version 2.12 |
| `8.32-1991416` | firmware-imx version 8.32, NXP git hash `1991416` |
| `6.18.20-custom` | your kernel: version + `KERNEL_LOCALVERSION` |

---

← [13 · Secure world](13-secure-world.md) · [Index](README.md) · [15 · Source tour](15-source-tour.md) →
