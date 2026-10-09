# custom/dts/

Drop your own `*.dts` / `*.dtsi` files here. They are copied into
`arch/arm64/boot/dts/freescale/` of the kernel and every `*.dts` is built into a
`.dtb` that ends up in `/boot` on the SD card. You can `#include` any Variscite
file, e.g. `#include "imx8mp-var-dart.dtsi"`.

Select it at boot with `fdt_file=<name>.dtb` in `/boot/uEnv.txt`.
See `docs/08-customizing.md`.
