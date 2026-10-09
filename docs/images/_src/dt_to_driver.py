"""docs/images/dt-to-driver.svg - from a device-tree node to a working driver (generated)."""
from kit import *

W, H = 1400, 900
A = "#e5edf7"
b = [marker_defs({"a": A, "v": "#c4b5fd", "t": "#5eead4"})]
b.append(title("From one line of device tree to a working driver",
               "Real example from this board: the DS1337 real-time clock on I2C4. Every Linux driver on the board is found and loaded the same way."))

# bands
b.append(rect(20, 92, 1360, 330, fill="#120f2b", stroke="#4c1d95", rx=16, opacity=0.6))
b.append(text(36, 116, "ON YOUR PC · ./build.sh kernel", size=12, weight=800, color=ROLE["rootfs"][1], extra=' letter-spacing="1.4"'))
b.append(rect(20, 440, 1360, 400, fill="#06231f", stroke="#0f766e", rx=16, opacity=0.6))
b.append(text(36, 464, "ON THE BOARD · every boot", size=12, weight=800, color=ROLE["normal"][1], extra=' letter-spacing="1.4"'))

# 1 DTS
b.append(card(36, 130, 430, 278, "1  Describe the hardware", "rootfs", "file-text", "imx8mp-var-som-symphony.dts"))
b.append(code(52, 182, 398, [
    ("&i2c4 {", "#c4b5fd"),
    ("    status = \"okay\";", "#cbd5e1"),
    ("    …", "#64748b"),
    ("    rtc@68 {", "#fcd34d"),
    ("        compatible = \"dallas,ds1337\";", "#fb7185"),
    ("        reg = <0x68>;", "#93c5fd"),
    ("    };", "#fcd34d"),
    ("};", "#c4b5fd"),
]))
b.append(text(52, 384, "\"there is a DS1337 at I2C address 0x68 on bus I2C4\"", size=11.5, color=MUTED))

# 2 dtc
b.append(card(516, 130, 360, 278, "2  Compile it", "rootfs", "hammer", "dtc"))
b.append(code(532, 182, 328, [("make freescale/", "#cbd5e1"), ("  imx8mp-var-som-1.x-", "#cbd5e1"), ("  symphony.dtb", "#cbd5e1")]))
b.append(lines(532, 278, ["dtc turns text into a flat binary", "tree (FDT, \"blob\"). Includes and", "overlays are merged here:", "SoC .dtsi + SoM .dtsi + carrier .dts", "+ the 1.x revision overlay."], size=12, color=MUTED, first=TEXT))

# 3 on card
b.append(card(926, 130, 438, 278, "3  Ship it on the SD card", "rootfs", "hard-drive", "image.sh"))
b.append(code(942, 182, 406, [("/boot/Image.gz", "#5eead4"), ("/boot/imx8mp-var-som-1.x-symphony.dtb", "#c4b5fd"), ("/lib/modules/6.18.20-custom/", "#5eead4"), ("    kernel/drivers/rtc/rtc-ds1307.ko", "#fcd34d"), ("    modules.alias", "#fcd34d")]))
b.append(lines(942, 316, ["47 DTBs ship; U-Boot picks one per board.", "The driver itself is a module (=m):", "it is NOT in the kernel image."], size=12, color=MUTED, first=TEXT))

b.append(arrow(468, 270, 512, 270, A, "a"))
b.append(arrow(878, 270, 922, 270, A, "a"))
b.append(path_arrow([(1145, 410), (1145, 432), (310, 432), (310, 474)], "#c4b5fd", "v", width=3,
                    label="boot: U-Boot reads it from /boot", lx=670, ly=432))

# 4 U-Boot
b.append(card(36, 480, 318, 340, "4  U-Boot hands it over", "boot", "rocket", "booti"))
b.append(code(52, 532, 286, [("load mmc 1:1 ${fdt_addr}", "#93c5fd"), ("  /boot/${fdt_file}", "#93c5fd"), ("booti … - ${fdt_addr}", "#93c5fd")]))
b.append(lines(52, 626, ["fdt_addr = 0x4300_0000", "x0 = DTB address when", "the kernel starts. U-Boot", "also patches in RAM size", "and bootargs (/chosen)."], size=12, color=MUTED, first=TEXT))

# 5 kernel creates device
b.append(card(376, 480, 330, 340, "5  Kernel builds devices", "normal", "linux", "of_platform", filled_icon=True))
b.append(lines(392, 540, ["Parses the DTB. The I2C4 driver", "(built-in) probes and creates a", "device per child node:"], size=12, color=TEXT))
b.append(code(392, 600, 298, [("/sys/bus/i2c/devices/3-0068", "#5eead4"), ("  name    = ds1337", "#cbd5e1"), ("  modalias=", "#cbd5e1"), ("   of:NrtcT(null)C", "#fcd34d"), ("   dallas,ds1337", "#fcd34d")]))
b.append(lines(392, 762, ["\"3-0068\" = Linux bus 3 (= I2C4),", "address 0x68. No driver yet."], size=12, color=MUTED))

# 6 match
b.append(card(728, 480, 340, 340, "6  Find the matching driver", "fw", "scan-search", "modalias"))
b.append(code(744, 532, 308, [("# modules.alias (from depmod)", "#64748b"), ("alias of:N*T*Cdallas,ds1337", "#fcd34d"), ("      rtc_ds1307", "#fcd34d")]))
b.append(lines(744, 624, ["Built-in driver → probes at once.", "Module → userspace loads it:"], size=12, color=TEXT))
b.append(code(744, 652, 308, [("modprobe of:N…Cdallas,ds1337", "#fbbf24"), ("→ insmod rtc-ds1307.ko", "#cbd5e1")]))
b.append(lines(744, 726, ["Alpine: /sbin/coldplug + mdev -d", "Debian: systemd-udevd", "(without either: no RTC!)"], size=12, color=MUTED))

# 7 probe
b.append(card(1090, 480, 274, 340, "7  probe() runs", "normal", "zap", "driver"))
b.append(code(1106, 532, 242, [("static const struct", "#cbd5e1"), ("  of_device_id …[] = {", "#cbd5e1"), ("  { .compatible =", "#cbd5e1"), ("   \"dallas,ds1337\" },", "#fb7185")], size=11.5))
b.append(lines(1106, 650, ["compatible strings match,", "ds1307_probe() talks to", "the chip and registers:"], size=12, color=TEXT))
b.append(code(1106, 704, 242, [("/dev/rtc0", "#6ee7b7"), ("/sys/class/rtc/rtc0", "#6ee7b7"), ("hwclock -u   ✓", "#6ee7b7")]))

b.append(arrow(356, 650, 372, 650, A, "a"))
b.append(arrow(708, 650, 724, 650, A, "a"))
b.append(arrow(1070, 650, 1086, 650, A, "a"))

b.append(caption(868, "The key is the compatible string: the same text appears in the device tree and in the driver's of_match_table. Change the DT node, and Linux binds a different driver."))
write("dt-to-driver.svg", W, H,
      "How the DS1337 RTC on this board goes from a device-tree node to a working driver: the node in the .dts is compiled by dtc "
      "into a .dtb, shipped in /boot, loaded by U-Boot and passed to the kernel, which creates an I2C device with a modalias; "
      "modules.alias maps that to the rtc_ds1307 module, which coldplug or udev loads, and its probe function registers /dev/rtc0.",
      "".join(b))
