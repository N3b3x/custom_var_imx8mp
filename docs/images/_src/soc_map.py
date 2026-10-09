"""docs/images/soc-map.svg - the i.MX 8M Plus at a glance, with every acronym (generated)."""
from kit import *

W, H = 1400, 940
b = []
b.append(title("Inside the i.MX 8M Plus: the blocks behind the acronyms",
               "One chip, many processors and controllers. Every name you meet in logs, device trees and these docs is one of these blocks."))

# chip outline
b.append(rect(24, 92, 1352, 790, fill="#0d1628", stroke="#475569", rx=20, sw=2))
b.append(text(44, 120, "NXP i.MX 8M Plus SoC", size=15, weight=800, color="#cbd5e1"))
b.append(text(250, 120, "(the chip on the Variscite module)", size=12.5, color=MUTED))


def group(x, y, w, h, name, role, ic, items, cols=1):
    strong, soft, fill, border = ROLE[role]
    out = rect(x, y, w, h, fill=fill, stroke=border, rx=14, sw=1.6)
    out += icon(ic, x + 14, y + 12, 22, soft)
    out += text(x + 44, y + 29, name, size=14, weight=800, color=soft)
    cw = (w - 28 - (cols - 1) * 10) / cols
    for i, (abbr, full) in enumerate(items):
        c, r = i % cols, i // cols
        bx, by = x + 14 + c * (cw + 10), y + 46 + r * 50
        out += rect(bx, by, cw, 42, fill=PANEL, stroke=LINE, rx=9)
        out += text(bx + 12, by + 18, abbr, size=13, weight=800, color=TEXT)
        out += text(bx + 12, by + 34, full, size=11, color=MUTED)
    return out


b.append(group(44, 136, 430, 300, "Compute", "secure", "cpu", [
    ("4× Cortex-A53", "Arm application cores, up to 1.8 GHz · run Linux"),
    ("EL0-EL3 · TrustZone", "privilege levels + secure/normal worlds"),
    ("Cortex-M7", "real-time microcontroller core, 800 MHz"),
    ("GIC", "Generic Interrupt Controller (Arm)"),
    ("PSCI", "Power State Coordination Interface (via BL31)"),
]))
b.append(group(490, 136, 430, 300, "Memory & boot", "boot", "memory-stick", [
    ("ROM", "Boot ROM: first code after reset (fixed)"),
    ("OCRAM", "On-Chip RAM, 576 KiB: SPL, then BL31"),
    ("DDRC + DDR PHY", "LPDDR4 controller + PHY (needs training FW)"),
    ("TZASC (TZC-380)", "TrustZone Address Space Controller"),
    ("OCOTP", "On-Chip OTP fuses: MAC, boot cfg, keys"),
]))
b.append(group(936, 136, 424, 300, "Security", "fw", "shield-check", [
    ("CAAM", "Cryptographic Acceleration & Assurance Module"),
    ("HAB", "High Assurance Boot: signed-image check in ROM"),
    ("SNVS", "Secure Non-Volatile Storage: RTC, power key"),
    ("CSU · RDC", "Central Security Unit · Resource Domain Ctrl"),
    ("AIPSTZ", "peripheral bus bridges with TrustZone checks"),
]))
b.append(group(44, 452, 430, 250, "Storage & system control", "hw", "hard-drive", [
    ("uSDHC1-3", "Ultra Secured Digital Host Controllers: SD/eMMC/SDIO"),
    ("GPC · CCM", "General Power Controller · Clock Control Module"),
    ("SDMA", "Smart DMA engines (load firmware, feed SPI/audio)"),
    ("WDOG · GPIO", "watchdog timers · 5 banks of general-purpose I/O"),
]))
b.append(group(490, 452, 430, 250, "Connectivity", "normal", "network", [
    ("EQoS · FEC", "Ethernet: QoS/TSN controller (eth0) · Fast Ethernet Ctrl (eth1)"),
    ("USB 3.0 · PCIe", "2× USB 3.0 dual-role · PCI Express Gen3 ×1"),
    ("FlexCAN ×2", "CAN-FD bus controllers (can0, can1)"),
    ("UART · I2C · ECSPI", "4 UARTs (ttymxcN) · 6 I2C · 3 SPI"),
]))
b.append(group(936, 452, 424, 250, "Multimedia & AI", "rootfs", "monitor", [
    ("GPU 3D/2D", "Vivante GC7000UL + GC520L (galcore)"),
    ("VPU", "Video Processing Unit: H.264/H.265 (Hantro)"),
    ("NPU", "Neural Processing Unit, 2.3 TOPS"),
    ("ISP · HiFi4 DSP", "Image Signal Processor ×2 · audio DSP"),
]))
b.append(group(44, 718, 1316, 150, "Display, camera & audio interfaces", "boot", "monitor", [
    ("LCDIF ×3", "LCD interface engines (scan-out)"), ("HDMI TX", "HDMI 2.0a output + eARC"),
    ("LVDS · MIPI DSI", "panel links (the 800×480 LVDS panel)"), ("MIPI CSI ×2 · ISI", "camera input · Image Sensing Interface"),
    ("SAI · PDM", "Synchronous Audio Interface · digital mics"), ("PWM", "Pulse-Width Modulation (backlight, buzzer)"),
], cols=3))

b.append(caption(906, "Full names, what each block does and why it exists: docs/14-acronyms.md. In Linux, most blocks appear as a node in the device tree and a driver in dmesg."))
write("soc-map.svg", W, H,
      "Block map of the NXP i.MX 8M Plus SoC grouped by function with each acronym expanded: compute (Cortex-A53, Cortex-M7, GIC, PSCI), "
      "memory and boot (ROM, OCRAM, DDR controller and PHY, TZASC, OCOTP), security (CAAM, HAB, SNVS, CSU, RDC, AIPSTZ), storage and system "
      "control (uSDHC, GPC, CCM, SDMA, watchdog, GPIO), connectivity (EQoS, FEC, USB, PCIe, FlexCAN, UART, I2C, ECSPI), multimedia and AI "
      "(GPU, VPU, NPU, ISP, DSP) and display, camera and audio interfaces.",
      "".join(b))
