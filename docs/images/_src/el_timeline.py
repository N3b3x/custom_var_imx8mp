"""docs/images/el-timeline.svg - which EL the boot CPU is on, over time (generated)."""
from kit import *

W, H = 1400, 660
b = [marker_defs({"u": "#fb7185", "d": "#e5edf7"})]
b.append(title("The boot CPU's elevator log: which level it's on, over time",
               "Boot only ever goes down. At runtime the CPU pops up for a moment (syscall, smc, interrupt) and eret brings it back."))

LV = {3: 150, 2: 250, 1: 350, 0: 450}
COL = {3: ROLE["secure"][0], 2: ROLE["boot"][0], 1: ROLE["normal"][0], 0: "#14b8a6"}
for el, y in LV.items():
    b.append(text(40, y + 6, "EL%d" % el, size=20, weight=800, color=["#5eead4", "#5eead4", "#93c5fd", "#fda4af"][el]))
    b.append('<line x1="96" y1="%d" x2="1370" y2="%d" stroke="#1e2a44" stroke-dasharray="3 6"/>' % (y, y))
b.append(text(40, 516, "time →", size=12, color=MUTED))

# boot segments: (x0, x1, el, label, sub)
SEG = [(100, 230, 3, "Boot ROM", "silicon"), (230, 370, 3, "SPL", "DDR training"), (370, 470, 3, "BL31", "set up EL3"),
       (470, 610, 2, "U-Boot", "load kernel"), (610, 680, 2, "Linux", "head.S"),
       (680, 980, 1, "Linux kernel", "drivers probe"), (980, 1370, 0, "/sbin/init → login → your app", "")]
prev = None
for x0, x1, el, lab, sub in SEG:
    y = LV[el]
    if prev is not None and prev != y:
        b.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#e5edf7" stroke-width="3" marker-end="url(#m-d)"/>' % (x0, prev, x0, y - 6))
    b.append(rect(x0 + 2, y - 15, x1 - x0 - 4, 30, fill=COL[el], rx=8))
    b.append(text((x0 + x1) / 2, y + 5, lab, size=12.5, weight=800, anchor="middle", color="#fff"))
    if sub:
        b.append(text((x0 + x1) / 2, y + 34, sub, size=11.5, anchor="middle", color=MUTED))
    prev = y


def spike(x, frm, to, label, color_up="#fb7185", w=26):
    yf, yt = LV[frm], LV[to]
    out = '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="3" marker-end="url(#m-u)"/>' % (x, yf - 16, x, yt + 18, color_up)
    out += rect(x - w / 2 + 13, yt - 13, w, 26, fill=COL[to], rx=6)
    out += '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#e5edf7" stroke-width="3" marker-end="url(#m-d)"/>' % (x + 26, yt + 18, x + 26, yf - 16)
    out += pill(x + 13, yt - 30, label, color_up, size=11)
    return out


# runtime excursions
b.append(spike(800, 1, 3, "smc PSCI CPU_ON ×3"))
b.append(spike(1060, 0, 1, "svc: read()", color_up="#2dd4bf"))
b.append(spike(1160, 0, 1, "IRQ: timer", color_up="#fbbf24"))
# reboot: up and never back down
b.append('<line x1="1270" y1="434" x2="1270" y2="368" stroke="#2dd4bf" stroke-width="3" marker-end="url(#m-u)"/>')
b.append(rect(1257, 337, 26, 26, fill=COL[1], rx=6))
b.append(pill(1270, 320, "svc: reboot", "#2dd4bf", size=11))
b.append('<line x1="1270" y1="334" x2="1270" y2="168" stroke="#fb7185" stroke-width="3" marker-end="url(#m-u)"/>')
b.append(rect(1257, 137, 26, 26, fill=COL[3], rx=6))
b.append(pill(1150, 120, "smc SYSTEM_RESET → chip resets → Boot ROM", "#fb7185", size=11))

# legend
b.append(rect(32, 548, 1336, 92, fill=PANEL, stroke=LINE, rx=14))
L = [("#e5edf7", "eret / boot hand-off: down a level", 52), ("#fb7185", "smc: into EL3 (BL31)", 420),
     ("#2dd4bf", "svc: app → kernel", 690), ("#fbbf24", "interrupt: hardware → kernel", 930)]
for c, t, x in L:
    b.append('<line x1="%d" y1="580" x2="%d" y2="580" stroke="%s" stroke-width="3.4"/>' % (x, x + 34, c))
    b.append(text(x + 44, 585, t, size=12.5, color=TEXT))
b.append(text(52, 620, "Real numbers from this board: CPUs 1-3 started by smc PSCI CPU_ON at 0.005 s; /sbin/init at 3.44 s. "
               "After boot BL31 is only ever entered through smc (or a secure interrupt). Every app instruction runs at EL0.", size=12, color=MUTED))
write("el-timeline.svg", W, H,
      "Step chart of the boot CPU's exception level over time: Boot ROM, SPL and BL31 at EL3; U-Boot and the start of Linux at EL2; "
      "the Linux kernel at EL1; init and applications at EL0. At runtime the CPU briefly rises for PSCI smc calls to EL3, for system "
      "calls and interrupts to EL1, and a reboot goes from EL0 by svc to EL1 and by smc SYSTEM_RESET to EL3, which resets the chip.",
      "".join(b))
