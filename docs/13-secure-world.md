# 13 · The secure world: TF-A, OP-TEE and TrustZone

[Docs](README.md) › **13 · Secure world**

> **In this guide:** what "ATF", "BL31", "BL32", "BL33" and "OP-TEE" really
> are; how the CPU's privilege levels and the two worlds fit together; what an
> `smc` does; how the hardware enforces TrustZone; and what is (and isn't)
> protected in this build. Every claim is backed by this repository's sources
> or a real boot log.

**Contents:** [The names](#1-the-names-untangled) ·
[Who runs where](#2-who-runs-where-exception-levels-and-worlds) ·
[Boot hand-offs](#3-the-boot-hand-offs-who-loads-what) ·
[What an smc does](#4-what-an-smc-does) ·
[How TrustZone is enforced](#5-how-trustzone-is-enforced) ·
[What this build protects](#6-what-this-build-protects-and-what-it-doesnt) ·
[Adding OP-TEE](#7-adding-op-tee-roadmap) · [See it on the board](#8-see-it-on-your-board)

---

## 1. The names, untangled

| Name | What it actually is | In this repo |
| --- | --- | --- |
| **ATF** | old name for **TF-A**, Trusted Firmware-A, Arm's reference secure firmware | `varigit/imx-atf` |
| **BL31** | TF-A's *runtime* stage: the **secure monitor**, running at EL3 | `build/src/imx-atf/build/imx8mp/release/bl31.bin` |
| **BL32** | the slot for a *secure payload*, usually **OP-TEE**, a trusted OS at S-EL1 | **not built** (optional) |
| **BL33** | the *non-secure* bootloader that BL31 hands off to: **U-Boot proper** | `u-boot-nodtb.bin` |
| BL1 / BL2 | TF-A's early stages. **Not used on i.MX**: the Boot ROM plays BL1, U-Boot SPL plays BL2 | – |
| **OP-TEE** | an open-source Trusted Execution Environment OS that runs Trusted Applications (TAs) | optional |
| **SPL** | U-Boot's tiny first stage: trains DDR, loads the FIT | `spl/u-boot-spl.bin` |

> **"BL" numbers are boot-stage names, not privilege levels.** BL31 happens to
> run at EL3 and BL33 at EL2, but "BL32" doesn't mean "EL3-2". They are just
> labels from the TF-A architecture.

In one sentence each:

- **TF-A BL31** is the *secure monitor*. It is the only code at EL3, it owns
  the switch between worlds, and it stays resident forever, answering `smc` calls.
- **OP-TEE (BL32)** is the *secure operating system*. It runs trusted
  applications next to Linux, in memory Linux cannot touch.
- **U-Boot (BL33)** is the *normal-world bootloader*. It loads Linux and is
  gone afterwards.

## 2. Who runs where: exception levels and worlds

![Exception levels and the two worlds](images/exception-levels.svg)

The Cortex-A53 has four **exception levels**: EL0 (least privileged) to EL3
(most). Orthogonal to that, it is in one of two **security states**, also
called **worlds**:

| | Secure world | Normal world |
| --- | --- | --- |
| EL3 | TF-A BL31 (EL3 belongs to neither world; it is the gate between them) | ← same |
| EL2 | *(no S-EL2 on Armv8.0)* | U-Boot during boot · Linux's KVM stub at runtime |
| EL1 | OP-TEE OS *(if built)* | Linux kernel |
| EL0 | Trusted Applications *(if built)* | your applications |

Three things are easy to get wrong:

1. **The Linux kernel enters at EL2, not EL1.** BL31 enters U-Boot at EL2
   (`get_spsr_for_bl33_entry()` in imx-atf), U-Boot boots Linux at EL2, and
   Linux keeps a tiny hypervisor stub there for KVM before dropping to EL1.
   Your boot log proves it: `CPU: All CPU(s) started at EL2` and
   `kvm [1]: Hyp nVHE mode initialized successfully`.
2. **Applications can never call `smc`.** Only EL1 and above can. An app asks
   the kernel (`ioctl`), and the kernel's driver issues the `smc`.
3. **U-Boot is not in the runtime path.** After `booti` it is gone. BL31 (and
   OP-TEE, if present) are the only firmware left running.

## 3. The boot hand-offs: who loads what

![Boot chain](images/boot-chain.svg)

![Inside imx-boot.bin](images/imx-boot-anatomy.svg)

The exact sequence on the i.MX8MP:

| # | Who | Does | Then |
| --- | --- | --- | --- |
| 1 | **Boot ROM** (EL3, secure) | reads `imx-boot.bin` at 32 KiB, copies the SPL (+ DDR firmware) into OCRAM `0x920000` | jumps to SPL |
| 2 | **SPL** (EL3, secure) | trains LPDDR4, reads the FIT: **BL31 → OCRAM `0x970000`**, **U-Boot + DTB → DDR `0x40200000`**, *(OP-TEE → `0x56000000`)* | jumps to BL31 |
| 3 | **BL31** (EL3) | sets up the secure monitor, TZASC/CSU/RDC. *If a BL32 exists:* ERETs into OP-TEE at S-EL1, which initialises and returns to BL31 | ERETs to BL33 at **EL2, non-secure** |
| 4 | **U-Boot** (EL2, NS) | loads Image.gz + DTB, `booti` | gone |
| 5 | **Linux** (EL2 → EL1) | starts CPUs 1–3 via PSCI `smc` → BL31 | runs |

> **BL31 does not load OP-TEE.** The SPL copies *all* images out of the FIT.
> BL31 only *starts* OP-TEE (through its "secure payload dispatcher", `SPD=opteed`)
> before handing off to U-Boot.

## 4. What an smc does

![What happens on an smc](images/smc-flow.svg)

`smc #0` (Secure Monitor Call) is a **deliberate, synchronous exception**, not
an error. The CPU saves the return address in `ELR_EL3` and the state in
`SPSR_EL3`, then jumps to BL31's exception vector. BL31 reads the **function
ID in `x0`**, which follows Arm's SMC Calling Convention (SMCCC; this firmware
implements v1.5):

| `x0` range | Owner | Handled by | Examples on this board |
| --- | --- | --- | --- |
| `0x84xx_xxxx` / `0xC4xx_xxxx` | **PSCI** (standard service) | BL31 itself | `0xC400_0003` CPU_ON (starts CPUs 1–3 at boot), `0x8400_0009` SYSTEM_RESET (`reboot`), `0x8400_0008` SYSTEM_OFF |
| `0xC2xx_xxxx` | **SiP**: NXP-specific | BL31 itself | `0xC200_0004` DDR frequency scaling, `0xC200_0001` CPU frequency, `0xC200_0000` power domains (GPC), `0xC200_0002` RTC/watchdog |
| `0x32xx_xxxx` / `0xB2xx_xxxx` | **Trusted OS** | forwarded to OP-TEE | `0x3200_0004` CALL_WITH_ARG *(only with OP-TEE)* |

BL31 answers PSCI and SiP calls itself and returns with `eret`, results in
`x0`–`x3`. For a Trusted-OS call it saves the whole normal-world register
context, flips `SCR_EL3.NS` to 0, and enters OP-TEE. On the way back it restores
Linux's context. Linux never sees secure memory or secure registers.

## 5. How TrustZone is enforced

![How TrustZone is enforced](images/trustzone.svg)

TrustZone is **hardware**:

1. The CPU's world is one bit, `SCR_EL3.NS`, and **only EL3 can change it**.
2. Every bus transaction carries that bit as **`AxPROT[1]`**.
3. Checkers sit between the bus and the resources:
   - **TZASC (TZC-380)** in front of DDR: up to 16 regions, each with secure /
     non-secure read/write permissions.
   - **CSU** per peripheral (CAAM, SNVS, UARTs …), and **RDC** per bus master
     (A53 cluster, Cortex-M7, DMA engines).
4. A denied access gets a **bus error**: the CPU takes an abort. Being root, or
   running kernel code, doesn't matter; the bus refuses.

## 6. What this build protects, and what it doesn't

Read straight from the code this repository builds:

| Where | Code | Effect |
| --- | --- | --- |
| SPL | `board/variscite/imx8mp_var_dart/spl.c` → `enable_tzc380()` | TZASC **enabled and locked**, region 0 = **all DDR, secure + non-secure RW** |
| BL31 | `imx8mp_bl31_setup.c` → `bl31_tzc380_setup()` | programs the same open region 0 |
| BL31 | `bl31_early_platform_setup2()` → CSU `0x00ff00ff` × 64 | **every peripheral** accessible from both worlds |

So in this build:

- ✅ **BL31 is isolated** in on-chip RAM and is the only code at EL3.
- ✅ **PSCI/SiP** go through a narrow, well-defined interface.
- ❌ **No DDR region is secure-only.** There is nothing secret to protect yet.
- ❌ **No secure boot.** The HAB signature slot in `imx-boot.bin` is empty, so
  anyone with the SD card can replace any stage.

That is the normal starting point for development. To actually *protect*
something (keys, credentials), you need **both**:

1. **OP-TEE**, which adds a secure-only TZASC region and a place to run code
   on secrets, and
2. **HAB secure boot**: signed `imx-boot.bin` and fused keys, so the firmware
   that sets up the protection can't be swapped.

## 7. Adding OP-TEE: roadmap

Not automated in this repository yet. These are the moving parts, matching
what NXP's and Variscite's Yocto layers do when `MACHINE_FEATURES` contains `optee`:

| Step | Component | Change |
| --- | --- | --- |
| 1 | **OP-TEE OS** | build `nxp-imx/imx-optee-os` @ `lf-6.18.20_2.0.0` with `PLATFORM=imx-mx8mpevk CFG_DDR_SIZE=0x100000000` → `tee.bin` (Variscite's layer adds only `CFG_DDR_SIZE` for the 8M Plus) |
| 2 | **TF-A** | rebuild BL31 with `SPD=opteed`, so BL31 dispatches Trusted-OS calls and starts BL32 at `BL32_BASE = 0x56000000` |
| 3 | **imx-mkimage** | put `tee.bin` in `iMX8M/`. `mkimage_fit_atf.sh` adds a `tee-1` image to the FIT, loaded at `TEE_LOAD_ADDR = 0x56000000` |
| 4 | **U-Boot** | detects OP-TEE and adds the `/firmware/optee` node and a reserved-memory region to the kernel's device tree |
| 5 | **Linux** | `CONFIG_OPTEE=y`: the driver appears as `/dev/tee0` and `/dev/teepriv0` |
| 6 | **Userspace** | `optee-client` (`tee-supplicant`, `libteec`), and your Trusted Applications built with the OP-TEE TA dev kit |

Afterwards the `optee` line in the U-Boot log changes from
`OP-TEE api uid mismatch` to a version banner, and the kernel prints
`optee: initialized driver`.

## 8. See it on your board

```sh
# PSCI conduit and version the kernel negotiated with BL31
dmesg | grep -iE "psci|SMC Calling"
cat /sys/firmware/devicetree/base/psci/compatible; echo     # arm,psci-1.0
cat /sys/firmware/devicetree/base/psci/method; echo         # smc

# The kernel entered at EL2 and kept a KVM stub there
dmesg | grep -E "started at EL|Hyp"

# No OP-TEE: no firmware node, no /dev/tee*
ls /sys/firmware/devicetree/base/firmware 2>/dev/null; ls /dev/tee* 2>/dev/null

# Every reboot / poweroff is an smc to BL31 (PSCI SYSTEM_RESET / SYSTEM_OFF)
reboot
```

Real output from the VAR-SOM-MX8M-PLUS used for these docs:

```text
psci: probing for conduit method from DT.
psci: PSCIv1.1 detected in firmware.
psci: Using standard PSCI v0.2 function IDs
psci: SMC Calling Convention v1.5
CPU: All CPU(s) started at EL2
kvm [1]: Hyp nVHE mode initialized successfully
arm,psci-1.0
smc
```

---

← [12 · Board tour](12-board-tour.md) · [Index](README.md) · [14 · Acronyms](14-acronyms.md) →
