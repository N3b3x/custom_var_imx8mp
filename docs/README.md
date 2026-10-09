# Documentation

The manual for building, flashing, understanding and customizing the
i.MX 8M Plus BSP in this repository. New here? Start with the
[main README](../README.md) quick start, then pick a path below.

## Pick your path

### "I just want a working board"

1. [02 · Host setup](02-host-setup.md): prepare your PC (5 min)
2. `./build.sh --accept-eula all` (~30 min, see the [README](../README.md#quick-start))
3. [07 · Flashing & first boot](07-flashing-and-boot.md): card, boot switch, serial console
4. [11 · Using the board](11-using-the-board.md): log in, get online, explore
5. [12 · Board tour](12-board-tour.md): real output from a real board, and what's normal

### "I want to understand how it works"

1. [14 · Acronyms](14-acronyms.md): SoC, SPL, BL31, TZASC … what they stand for and why they exist
2. [01 · Boot flow](01-boot-flow.md): what happens between power-on and the login prompt
3. [13 · Secure world](13-secure-world.md): TF-A, OP-TEE, exception levels, `smc`, TrustZone
4. [03 · U-Boot](03-uboot.md): the boot container, built by hand
5. [04 · Kernel](04-kernel.md): kernel, device trees, how drivers bind
6. [05 · Root filesystem](05-rootfs.md): what the OS around the kernel is made of
7. [06 · SD card image](06-sdcard-image.md): how the parts become one flashable file
8. [15 · Source tour](15-source-tour.md): read the real code behind each step

### "I'm building a product on it"

1. [08 · Customizing](08-customizing.md): your carrier board, patches, settings
2. [10 · Versions](10-versions.md): pinning, upgrading, older LTS releases
3. [09 · Troubleshooting](09-troubleshooting.md): symptom → cause → fix

## All guides

| # | Guide | Covers |
| --- | --- | --- |
| 01 | [Boot flow](01-boot-flow.md) | Boot ROM, SPL, DDR training, TF-A, U-Boot, Linux; the SD card memory map; SD vs eMMC |
| 02 | [Host setup](02-host-setup.md) | supported PCs, packages and why each is needed, toolchain, EULA, `local.conf` |
| 03 | [U-Boot](03-uboot.md) | firmware, TF-A, U-Boot, imx-mkimage by hand; the boot environment; `uEnv.txt` |
| 04 | [Kernel](04-kernel.md) | building, the 47 device trees and their names, custom DTS, config fragments |
| 05 | [Root filesystem](05-rootfs.md) | Debian vs Alpine vs your own; users, network, ssh, console handling |
| 06 | [SD card image](06-sdcard-image.md) | rootless image assembly (fakeroot, `mke2fs -d`), inspecting images |
| 07 | [Flashing & first boot](07-flashing-and-boot.md) | writing cards safely, boot switch, serial console, an annotated real boot log |
| 08 | [Customizing](08-customizing.md) | device tree for your carrier, patches, layout, other modules |
| 09 | [Troubleshooting](09-troubleshooting.md) | build errors and boot problems |
| 10 | [Versions](10-versions.md) | where versions come from, ready-made 6.12 / 6.6 sets, upgrading |
| 11 | [Using the board](11-using-the-board.md) | processes, resources, logs, drivers, buses, network, every command explained |
| 12 | [Board tour](12-board-tour.md) | a live VAR-SOM-MX8M-PLUS explained: CPU, thermal, I2C map, display, what isn't working and why |
| 13 | [Secure world](13-secure-world.md) | ATF/TF-A, BL31/32/33, OP-TEE, exception levels, `smc`, TrustZone, what this build protects |
| 14 | [Acronyms](14-acronyms.md) | every acronym: what it stands for, what it is on this board, why it exists |
| 15 | [Source tour](15-source-tour.md) | the files that run at boot, with real code excerpts |

## Diagrams

All diagrams, with what each shows: [images/README.md](images/README.md).

## Glossary

The full list (what each term stands for, what it is here, and why it exists)
is **[14 · Acronyms](14-acronyms.md)**.
