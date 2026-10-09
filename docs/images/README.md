# Diagrams

All diagrams are SVG, so they render sharply on GitHub and in any browser,
and their text is searchable. They use one dark theme with a fixed role palette:

| Colour | Means |
| --- | --- |
| rose | secure world: TF-A BL31, OP-TEE, `smc` |
| teal | normal world: Linux, applications, `svc` |
| blue | boot stages: SPL, U-Boot |
| amber | firmware blobs, image assembly |
| violet | device trees, root filesystem |
| dashed outline | optional / not part of the default build |

| File | Shows | Used in |
| --- | --- | --- |
| `boot-chain.svg` | every boot stage: EL, address, job, source file, what stays resident | README, 01, 13 |
| `build-pipeline.svg` | what `./build.sh all` does, sources → SD card | README, 06 |
| `imx-boot-anatomy.svg` | inside `imx-boot.bin` and who copies each part where | README, 01, 03, 13 |
| `exception-levels.svg` | EL0–EL3 × secure/normal world, with boot-log proof | README, 13 |
| `smc-flow.svg` | sequence of an `smc`: PSCI CPU_ON and an OP-TEE call | README, 13 |
| `trustzone.svg` | how TZASC/CSU enforce TrustZone, this build vs. OP-TEE | README, 13 |
| `memory-map.svg` | the 4 GiB DDR at runtime and the `booti` zoom | 01, 03 |
| `uboot-bootcmd.svg` | U-Boot's `bsp_bootcmd` decision flow with real values | README, 03 |
| `linux-to-login.svg` | kernel timeline to PID 1, Alpine vs Debian | README, 05 |
| `storage-map.svg` | uSDHC1-3 ↔ U-Boot `mmc N` ↔ Linux `mmcblkN` | 01, 06, 07 |
| `soc-map.svg` | every block of the i.MX 8M Plus with its acronym | README, 14 |
| `dt-layers.svg` | how SoC/SoM/carrier/revision layers compose one DTB; why 47 DTBs | README, 04, 08 |
| `dt-to-driver.svg` | from a DT node to a probed driver, with the real RTC | README, 04, 15 |
| `uboot-env.svg` | the four layers of U-Boot variables and which wins | README, 03 |
| `linux-fs.svg` | the SD card's files vs. /proc, /sys, /dev | README, 11 |
| `customize-map.svg` | where each kind of change goes and where it ends up | README, 08 |
| `source-map.svg` | the source files that run at boot, in order | README, 15 |
| `el-powers.svg` | the four exception levels: who lives there, superpowers, limits, and the hardware walls | README, 13 |
| `el-timeline.svg` | which EL the boot CPU is on over time, incl. runtime svc/smc/IRQ trips | README, 01, 13 |

## Editing

- **Generated** (edit the Python, then run it in `docs/images/_src/`):
  `smc_flow.py` → smc-flow · `dt_to_driver.py` · `dt_layers.py` · `soc_map.py` ·
  `source_map.py` · `el_powers.py` · `el_timeline.py` · `concepts.py` → uboot-env, linux-fs, customize-map.
  They share the theme and helpers in `kit.py`.
- **Hand-written** SVG: boot-chain, build-pipeline, imx-boot-anatomy, exception-levels, trustzone, memory-map, uboot-bootcmd, linux-to-login, storage-map. Edit them directly; keep colours from
  `_src/kit.py` (`ROLE`), and put text colour in `style="fill:…"` (inline
  styles win over the stylesheet).
- Icons are placed by `_src/add_icons.py` (`python3 add_icons.py`, idempotent).
- Preview: open the `.svg` in a browser, or
  `google-chrome --headless --screenshot=out.png --window-size=1400,900 file.svg`.

## Credits

- Icons: [Lucide](https://lucide.dev) v1.53.0, ISC License, © Lucide Contributors
  (`_src/icons/*.svg` except the three below).
- Linux, Debian and Alpine Linux marks: [Simple Icons](https://simpleicons.org),
  CC0 1.0. The trademarks belong to their owners and are used only to identify
  the software.
