"""docs/images/smc-flow.svg - what happens on an smc (generated)."""
from kit import *

W, H = 1400, 1120
SVC, SMC, ERET = "#2dd4bf", "#fb7185", "#e5edf7"
LX = {"app": 215, "linux": 545, "bl31": 875, "tee": 1205}   # lane centres
LW = 270

b = [marker_defs({"svc": SVC, "smc": SMC, "eret": ERET})]
b.append(title("What happens on an smc",
               "smc is a deliberate trap into EL3. BL31 reads the function ID in x0 and either answers itself (PSCI, SiP) or forwards to OP-TEE."))

# world columns
b.append(rect(70, 92, 640, 990, fill="#06231f", stroke="#0f766e", rx=16, sw=1, opacity=0.55))
b.append(text(86, 116, "NORMAL WORLD", size=12, color=ROLE["normal"][1], weight=800, extra=' letter-spacing="1.5"'))
b.append(rect(730, 92, 640, 990, fill="#2a0f1d", stroke="#9f1239", rx=16, sw=1, opacity=0.55))
b.append(text(746, 116, "SECURE WORLD", size=12, color=ROLE["secure"][1], weight=800, extra=' letter-spacing="1.5"'))


def lane(key, name, sub, role, ic, filled=False, dashed=False):
    cx = LX[key]
    strong, soft, fill, border = ROLE[role]
    out = rect(cx - LW / 2, 128, LW, 62, fill=strong if not dashed else fill, stroke=border, rx=14, sw=2,
               dash="7 5" if dashed else None)
    out += icon(ic, cx - LW / 2 + 16, 143, 30, "#ffffff" if not dashed else soft, filled=filled)
    out += text(cx - LW / 2 + 58, 156, name, size=16, weight=800, color="#ffffff" if not dashed else soft)
    out += text(cx - LW / 2 + 58, 176, sub, size=12, color="#e2e8f0" if not dashed else soft)
    # lifeline
    out += '<line x1="%d" y1="192" x2="%d" y2="1060" stroke="%s" stroke-width="2" stroke-dasharray="2 7" stroke-linecap="round"/>' % (
        cx, cx, border)
    return out


b.append(lane("app", "Application", "EL0 · your program", "normal", "square-terminal"))
b.append(lane("linux", "Linux kernel", "EL1 · drivers", "normal", "linux", filled=True))
b.append(lane("bl31", "TF-A · BL31", "EL3 · secure monitor", "secure", "shield-check"))
b.append(lane("tee", "OP-TEE · BL32", "S-EL1 · optional", "secure", "lock", dashed=True))


def note(cx, y, w, lines, role, ic=None, h=None):
    strong, soft, fill, border = ROLE[role]
    h = h or 18 + 18 * len(lines)
    out = rect(cx - w / 2, y, w, h, fill=PANEL, stroke=border, rx=10, sw=1.5)
    tx = cx - w / 2 + 14
    if ic:
        out += icon(ic, tx, y + h / 2 - 11, 22, soft)
        tx += 32
    for i, ln in enumerate(lines):
        out += text(tx, y + 23 + 18 * i, ln, size=12.5, color=TEXT if i == 0 else MUTED, weight=600 if i == 0 else 400)
    return out


def regs(cx, y, rows, accent):
    w, h = 300, 16 + 19 * len(rows)
    out = rect(cx - w / 2, y, w, h, fill="#050a14", stroke="#334155", rx=10, sw=1.2)
    for i, (r, v, c) in enumerate(rows):
        out += text(cx - w / 2 + 14, y + 24 + 19 * i, r, size=12, mono=True, color=accent if i == 0 else "#cbd5e1", weight=700 if i == 0 else 400)
        out += text(cx - w / 2 + 160, y + 24 + 19 * i, c, size=11.5, mono=False, color=MUTED)
    return out


def msg(frm, to, y, label, kind, n):
    color = {"svc": SVC, "smc": SMC, "eret": ERET}[kind]
    x1, x2 = LX[frm], LX[to]
    d = 1 if x2 > x1 else -1
    out = arrow(x1 + d * 14, y, x2 - d * 10, y, color, kind)
    out += pill((x1 + x2) / 2, y - 18, label, color)
    out += badge(x1 + d * 14, y, n, color)
    return out


def section(y, h, label, role, dashed=False):
    strong, soft, fill, border = ROLE[role]
    return (rect(40, y, 1320, h, fill="none", stroke=soft, rx=14, sw=1.4, dash="8 6" if dashed else None)
            + rect(56, y - 13, len(label) * 7.6 + 24, 26, fill=BG, stroke=soft, rx=13, sw=1.4)
            + text(68, y + 5, label, size=12.5, weight=800, color=soft))


# ---- A: PSCI CPU_ON (real, every boot) ----------------------------------------
b.append(section(220, 380, "A · EVERY BOOT OF THIS BOARD: Linux starts CPUs 1-3 through PSCI", "normal"))
b.append(note(LX["linux"], 244, 290, ["smp_init(): bring up CPU 1", "kernel needs the other 3 cores"], "normal", "cpu"))
b.append(regs(LX["linux"], 306, [("x0 = 0xC400_0003", "", "PSCI CPU_ON"), ("x1 = 0x1", "", "target core"),
                                 ("x2 = entry", "", "where it starts"), ("x3 = context", "", "passed to it")], SMC))
b.append(msg("linux", "bl31", 420, "smc #0", "smc", 1))
b.append(note(LX["bl31"], 438, 320, ["CPU traps to EL3", "saves ELR_EL3/SPSR_EL3 → VBAR_EL3"], "secure", "zap"))
b.append(note(LX["bl31"], 502, 320, ["PSCI handler", "powers up core 1 via the GPC"], "secure", "power"))
b.append(msg("bl31", "linux", 580, "eret · x0 = 0  SUCCESS", "eret", 2))
b.append(rect(80, 520, 270, 46, fill="#050a14", stroke="#14b8a6", rx=10, sw=1.4))
b.append(icon("square-terminal", 92, 532, 22, "#5eead4"))
b.append(text(122, 541, "dmesg, real output:", size=11.5, color=MUTED))
b.append(text(122, 558, "CPU1: Booted secondary processor", size=11.5, mono=True, color="#6ee7b7"))

# ---- B: OP-TEE call (only with OP-TEE) ---------------------------------------
b.append(section(640, 410, "B · ONLY WITH OP-TEE BUILT IN: an app uses a key it never sees", "secure", dashed=True))
b.append(msg("app", "linux", 690, "ioctl(/dev/tee0) · svc", "svc", 1))
b.append(regs(LX["linux"], 708, [("x0 = 0x3200_0004", "", "CALL_WITH_ARG"), ("x1,x2 = buffer", "", "shared memory")], SMC))
b.append(msg("linux", "bl31", 800, "smc #0", "smc", 2))
b.append(note(LX["bl31"], 814, 320, ["opteed dispatcher", "saves Linux regs, SCR_EL3.NS = 0"], "secure", "arrow-right-left"))
b.append(msg("bl31", "tee", 906, "eret → S-EL1", "eret", 3))
b.append(note(LX["tee"], 922, 290, ["Trusted Application", "uses the key in secure-only RAM"], "secure", "key-round"))
b.append(msg("tee", "bl31", 1004, "smc · done", "smc", 4))
b.append(msg("bl31", "linux", 1030, "eret · NS = 1 · result in x0-x3", "eret", 5))
b.append(msg("linux", "app", 1030, "ioctl returns", "svc", 6))

# ---- legend ---------------------------------------------------------------------
lx = 40
b.append(text(lx, 1092, "Arrows:", size=12.5, weight=700, color=MUTED))
for i, (k, c, t) in enumerate([("svc", SVC, "svc · app → kernel (system call)"),
                               ("smc", SMC, "smc · into EL3 (BL31)"),
                               ("eret", ERET, "eret · back down to the caller's level")]):
    x = 110 + i * 330
    b.append(arrow(x, 1088, x + 46, 1088, c, k, width=3))
    b.append(text(x + 58, 1092, t, size=12.5, color=TEXT))

open(__file__.replace("_src/smc_flow.py", "smc-flow.svg"), "w").write(svg(W, H,
    "Sequence of an SMC call. Case A, on every boot: the Linux kernel puts PSCI CPU_ON in x0 and executes smc; the CPU traps "
    "to BL31 at EL3, which powers up the next core and returns success with eret. Case B, only with OP-TEE: an application's "
    "ioctl reaches the kernel's OP-TEE driver, which executes smc; BL31 saves the normal-world context and enters OP-TEE at "
    "S-EL1, the trusted application uses a key in secure memory, and the result returns through BL31 to the kernel and the "
    "application.", "".join(b)))
print("wrote smc-flow.svg")
