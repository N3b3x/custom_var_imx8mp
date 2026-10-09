"""docs/images/el-powers.svg - what each exception level can do, and what separates them (generated)."""
from kit import *

W, H = 1400, 1010
UP, DOWN = "#fb7185", "#e5edf7"
b = [marker_defs({"up": UP, "down": DOWN})]
b.append(title("Exception levels: four floors, each with powers the floor below doesn't have",
               "The CPU is always on exactly one floor. Higher floors configure and can override the ones below; lower floors can only ask."))

FLOORS = [
    ("EL3", "Secure monitor", "secure", "shield-check",
     ["TF-A BL31", "always, from power-on", "to power-off"],
     ["flip the world: SCR_EL3.NS", "route interrupts + errors (SCR_EL3.IRQ/FIQ/EA)",
      "answer every smc: PSCI, SiP, OP-TEE", "reach secure and normal memory"],
     ["nothing above it:", "a bug at EL3 owns", "the whole chip"]),
    ("EL2", "Hypervisor", "boot", "rocket",
     ["U-Boot during boot", "Linux KVM stub (nVHE)", "while Linux runs"],
     ["stage-2 tables: choose the RAM an OS sees", "trap OS instructions (HCR_EL2.TSC/TWI/TVM)",
      "virtual interrupts + timers for guests"],
     ["can't switch worlds", "no secure memory", "EL3 can trap it"]),
    ("EL1", "OS kernel", "normal", "linux",
     ["Linux kernel 6.18", "drivers, scheduler,", "filesystems"],
     ["page tables for itself + apps (TTBR0/1_EL1)", "program device registers (MMIO), DMA",
      "mask interrupts, handle svc + page faults", "run, pause and kill processes"],
     ["sees what EL2 maps", "secure RAM: bus error", "EL2/EL3 can trap it"]),
    ("EL0", "Applications", "normal", "square-terminal",
     ["init, getty, sh", "BusyBox tools", "your program"],
     ["none, by design: own code, own memory,", "~only as the kernel allows. That's what",
      "~makes an app crash harmless to the rest."],
     ["no system registers", "no hardware unless", "the kernel maps it", "must ask: svc"]),
]
FY, FH, GAP = 100, 176, 12
for i, (el, role_name, role, ic, who, powers, limits) in enumerate(FLOORS):
    strong, soft, fill, border = ROLE[role]
    y = FY + i * (FH + GAP)
    b.append(rect(32, y, 900, FH, fill=fill, stroke=border, rx=14, sw=1.8))
    # badge
    b.append(rect(32, y, 120, FH, fill=strong, rx=14))
    b.append(text(92, y + 72, el, size=34, weight=800, anchor="middle", color="#fff"))
    b.append(text(92, y + 98, role_name, size=12.5, weight=700, anchor="middle", color="#f1f5f9"))
    b.append(text(92, y + 150, ["most", "", "", "least"][i] + (" privileged" if i in (0, 3) else ""), size=11, anchor="middle", color="#e2e8f0"))
    # who
    b.append(text(172, y + 28, "LIVES HERE ON YOUR BOARD", size=10.5, weight=800, color=MUTED, extra=' letter-spacing="1.1"'))
    b.append(icon(ic, 172, y + 44, 28, soft, filled=(ic == "linux")))
    b.append(lines(210, y + 60, who, size=12.5, gap=18, color=TEXT, first=soft))
    # powers
    b.append(text(376, y + 28, "SUPERPOWERS · only this floor and above", size=10.5, weight=800, color=MUTED, extra=' letter-spacing="1.1"'))
    for j, p in enumerate(powers):
        yy = y + 54 + j * 26
        if not p.startswith("~"):
            b.append(icon("zap", 376, yy - 13, 15, soft))
        b.append(text(398, yy, p.lstrip("~"), size=12.5, color=TEXT))
    # limits
    b.append(text(790, y + 28, "LIMITS", size=10.5, weight=800, color=MUTED, extra=' letter-spacing="1.1"'))
    b.append(lines(790, y + 54, limits, size=11.5, gap=19, color="#cbd5e1"))

# up / down rail
rx_ = 18
b.append(text(16, FY - 8, "", size=10))
# right panel: the walls
PX = 960
b.append(rect(PX, 100, 408, 740, fill="#050a14", stroke="#334155", rx=14))
b.append(icon("shield", PX + 18, 116, 24, "#cbd5e1"))
b.append(text(PX + 52, 134, "What makes the walls", size=16, weight=800))
b.append(text(PX + 52, 154, "all of it is CPU hardware, not software", size=12, color=MUTED))
WALLS = [
    ("1", "The level is CPU state", ["PSTATE.EL holds the current floor.", "No instruction can raise it. Read it", "with  mrs x0, CurrentEL  (head.S does)."]),
    ("2", "Registers belong to a level", ["Names end in _EL1/_EL2/_EL3. Touching a", "higher level's register from below traps", "as an undefined instruction."]),
    ("3", "Entry points are fixed", ["Each level's vector table (VBAR_ELx) and", "stack (SP_ELx): going up always lands in", "code the higher level chose."]),
    ("4", "Each level has its own MMU view", ["EL1 page tables for apps + kernel; EL2", "adds stage 2 on top; EL3 has its own."]),
    ("5", "The level above sets the rules", ["SCR_EL3 configures EL2/EL1 (world,", "routing); HCR_EL2 configures EL1/EL0", "(traps). Lower levels can't undo them."]),
    ("6", "Plus the second axis: worlds", ["SCR_EL3.NS rides on every bus access as", "AxPROT[1]; TZASC/CSU enforce it.", "→ 13 · Secure world, §5"]),
]
yy = 184
for n, head, rows in WALLS:
    b.append('<circle cx="%d" cy="%d" r="12" fill="#1e293b" stroke="#64748b"/>' % (PX + 30, yy + 2))
    b.append(text(PX + 30, yy + 7, n, size=12.5, weight=800, anchor="middle"))
    b.append(text(PX + 52, yy + 7, head, size=13.5, weight=800, color="#93c5fd"))
    b.append(lines(PX + 52, yy + 28, rows, size=12, gap=17, color="#cbd5e1"))
    yy += 34 + 17 * len(rows) + 14

# bottom: moving between floors
by = 860
b.append(rect(32, by, 1336, 112, fill=PANEL, stroke=LINE, rx=14))
b.append(text(52, by + 28, "MOVING BETWEEN FLOORS", size=12, weight=800, color=MUTED, extra=' letter-spacing="1.3"'))
b.append(arrow(70, by + 92, 70, by + 44, UP, "up", width=3.4))
b.append(text(92, by + 56, "Up = an exception, never a jump.", size=13.5, weight=800, color=UP))
b.append(text(92, by + 77, "svc (app→kernel) · hvc (→EL2) · smc (→EL3) · or an interrupt / fault.", size=12.5, color=TEXT))
b.append(text(92, by + 97, "The CPU saves where you were (ELR_ELx, SPSR_ELx) and enters the higher floor at its own vector.", size=12.5, color=MUTED))
b.append(arrow(760, by + 44, 760, by + 92, DOWN, "down", width=3.4))
b.append(text(782, by + 56, "Down = eret only.", size=13.5, weight=800, color=DOWN))
b.append(text(782, by + 77, "Returns to the saved address and level. That's how BL31", size=12.5, color=TEXT))
b.append(text(782, by + 97, "enters U-Boot at EL2, and how every syscall returns to EL0.", size=12.5, color=MUTED))

write("el-powers.svg", W, H,
      "The four Arm exception levels as floors. EL3, the secure monitor, is TF-A BL31: it can switch worlds, route interrupts and "
      "answer every smc. EL2, the hypervisor, is U-Boot during boot and Linux's KVM stub at runtime: it controls stage-2 page "
      "tables and can trap the OS. EL1 is the Linux kernel: it owns page tables, devices and interrupts. EL0 is applications, with "
      "no privileges. The walls are hardware: the current level is CPU state that only exceptions raise and only eret lowers, "
      "registers and vector tables belong to a level, each level has its own MMU view, and the level above configures the one below.",
      "".join(b))
