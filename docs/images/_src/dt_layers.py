"""docs/images/dt-layers.svg - how one board's device tree is composed (generated)."""
from kit import *

W, H = 1400, 820
A = "#e5edf7"
b = [marker_defs({"a": A, "v": "#c4b5fd"})]
b.append(title("How a device tree is built up in layers",
               "Each layer describes only what it adds. Later layers switch nodes on (status = \"okay\") or change them through &labels."))

LAYERS = [
    ("SoC", "imx8mp.dtsi", "NXP · 2403 lines", "hw", "microchip",
     ["every block inside the i.MX 8M Plus:", "CPUs, GIC, clocks, i2c1-6, usdhc1-3,", "ethernet, GPU, VPU … mostly", "status = \"disabled\" (65 nodes)"],
     [("i2c4: i2c@30a50000 {", "#cbd5e1"), ("    compatible = \"fsl,imx8mp-i2c\";", "#cbd5e1"), ("    status = \"disabled\";", "#fb7185"), ("};", "#cbd5e1")]),
    ("SoM", "imx8mp-var-som.dtsi", "Variscite · 567 lines", "boot", "memory-stick",
     ["what is soldered on the module:", "PMIC, eMMC, Ethernet PHY, Wi-Fi,", "pin muxing for its own parts"],
     [("&usdhc3 {          /* eMMC */", "#93c5fd"), ("    bus-width = <8>;", "#cbd5e1"), ("    status = \"okay\";", "#6ee7b7"), ("};", "#cbd5e1")]),
    ("Carrier", "imx8mp-var-som-symphony.dts", "Variscite · 685 lines", "normal", "hard-drive",
     ["what the carrier board wires up:", "SD slot, GPIO expanders, RTC,", "touch, LVDS panel, CAN, audio"],
     [("&i2c4 {", "#5eead4"), ("    status = \"okay\";", "#6ee7b7"), ("    rtc@68 { compatible =", "#cbd5e1"), ("      \"dallas,ds1337\"; … };", "#cbd5e1")]),
    ("Revision", "imx8mp-var-som-1.x.dtso", "overlay · 29 lines", "fw", "layers",
     ["differences of SoM revision 1.x,", "applied as an overlay (.dtso):", "older Wi-Fi/BT chip"],
     [("&bluetooth_iw61x {", "#fcd34d"), ("    status = \"disabled\";", "#fb7185"), ("};", "#cbd5e1"), ("&usdhc1 { … bcm4329-fmac … };", "#cbd5e1")]),
]

y = 108
for i, (lvl, fname, meta, role, ic, desc, snippet) in enumerate(LAYERS):
    strong, soft, fill, border = ROLE[role]
    x = 32 + i * 34
    b.append(rect(x, y, 820 - i * 34, 132, fill=fill, stroke=border, rx=14, sw=1.6))
    b.append(rect(x, y, 120, 132, fill=strong, rx=14))
    b.append(icon(ic, x + 44, y + 24, 32, "#ffffff"))
    b.append(text(x + 60, y + 84, lvl, size=15, weight=800, color="#ffffff", anchor="middle"))
    b.append(text(x + 60, y + 104, "layer %d" % (i + 1), size=11, color="#e2e8f0", anchor="middle"))
    b.append(text(x + 138, y + 30, fname, size=14, weight=800, color=soft, mono=True))
    b.append(text(x + 138, y + 50, meta, size=11.5, color=MUTED))
    b.append(lines(x + 138, y + 74, desc, size=12, color=TEXT, gap=17))
    b.append(code(x + 420 - i * 0, y + 14, 370 - i * 34, snippet, size=11.5, gap=17))
    if i < 3:
        b.append(arrow(x + 60, y + 134, x + 60 + 34, y + 152, A, "a", width=2.4))
    y += 152

# result
b.append(rect(890, 108, 478, 590, fill="#120f2b", stroke="#8b5cf6", rx=16, sw=1.8))
b.append(icon("binary", 910, 126, 28, "#c4b5fd"))
b.append(text(948, 147, "= one compiled board file", size=16, weight=800, color="#c4b5fd"))
b.append(code(910, 170, 438, [("# arch/arm64/boot/dts/freescale/Makefile", "#64748b"),
                              ("imx8mp-var-som-1.x-symphony-dtbs :=", "#c4b5fd"),
                              ("    imx8mp-var-som-symphony.dtb", "#5eead4"),
                              ("    imx8mp-var-som-1.x.dtbo", "#fcd34d")]))
b.append(text(910, 300, "dtc merges layers 1–3 into the base .dtb, then fdtoverlay", size=12.5, color=TEXT))
b.append(text(910, 320, "applies layer 4. Result: what the kernel sees.", size=12.5, color=TEXT))
b.append(text(910, 358, "WHY 47 DTB FILES?", size=12, weight=800, color=MUTED, extra=' letter-spacing="1.2"'))
rows = [("module", "dart · som · smarc"), ("revision", "base · -1.x · -wbe"), ("carrier", "sonata · symphony · echo"),
        ("camera", "none · basler-isp0/isi0 · 2nd-ov5640"), ("M7 core", "none · -m7 (reserves RAM/clocks)")]
for j, (k, v) in enumerate(rows):
    b.append(rect(910, 372 + j * 40, 438, 32, fill=PANEL, stroke=LINE, rx=8))
    b.append(text(924, 393 + j * 40, k, size=12, weight=700, color="#c4b5fd"))
    b.append(text(1010, 393 + j * 40, v, size=12, color=TEXT, mono=True))
b.append(text(910, 594, "Each combination is a different board, so a different DTB.", size=12.5, color=TEXT))
b.append(text(910, 616, "U-Boot's findfdt picks yours at boot:", size=12.5, color=TEXT))
b.append(code(910, 630, 438, [("fdt_file=imx8mp-var-som-1.x-symphony.dtb", "#6ee7b7")]))

b.append(caption(740, "Rule of thumb: describe the chip once (SoC), the module once (SoM), and each carrier once. To support your own carrier board, you"))
b.append(caption(760, "write only layer 3: copy the Symphony .dts into custom/dts/, keep #include \"imx8mp-var-som.dtsi\", and change what your board wires differently."))
b.append(caption(792, "See it compiled: dtc -I dtb -O dts /boot/imx8mp-var-som-1.x-symphony.dtb | less     ·     on the board: ls /proc/device-tree"))
write("dt-layers.svg", W, H,
      "How the device tree of this board is composed: the SoC layer imx8mp.dtsi describes the chip with most nodes disabled; the "
      "SoM layer imx8mp-var-som.dtsi adds the module's parts; the carrier layer imx8mp-var-som-symphony.dts enables and adds what the "
      "carrier wires; the revision overlay imx8mp-var-som-1.x.dtso adjusts for SoM revision 1.x. The Makefile merges them into "
      "imx8mp-var-som-1.x-symphony.dtb. 47 DTB files exist because module, revision, carrier, camera and M7 options combine.",
      "".join(b))
