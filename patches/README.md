# patches/

Put `*.patch` files (from `git format-patch`) in the subfolder of the component they change:

| Folder | Applied to | When |
| --- | --- | --- |
| `uboot/` | `build/src/uboot-imx` | `./build.sh uboot` (step 3) |
| `atf/` | `build/src/imx-atf` | `./build.sh uboot` (step 2) |
| `mkimage/` | `build/src/imx-mkimage` | `./build.sh uboot` (step 4) |
| `kernel/` | `build/src/linux-imx` | `./build.sh kernel` |

They are applied in file-name order, once per checkout. See `docs/08-customizing.md`.
