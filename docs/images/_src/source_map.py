"""docs/images/source-map.svg - the source files that run, in order (generated)."""
from kit import *

W, H = 1400, 1050
A = "#e5edf7"
b = [marker_defs({"a": A})]
b.append(title("The code that runs, in order: power-on to /sbin/init",
               "The files to open when you want to understand or change a step. Paths are inside build/src/ after a build."))

STEPS = [
    ("boot", "uboot-imx", "SPL", [
        ("board/variscite/imx8mp_var_dart/spl.c", "board_init_f(): clocks, UART, PMIC, then DRAM"),
        ("  └ spl_dram_init()", "reads the SoM EEPROM, adjusts timings, ddr_init()"),
        ("drivers/ddr/imx/imx8m/ddr_init.c", "loads the training firmware into the PHY, trains"),
        ("arch/arm/mach-imx/imx8m/soc.c", "enable_tzc380(): TZASC on, region 0 open"),
        ("common/spl/spl_fit.c", "reads the FIT, copies BL31 / U-Boot / DTB, jumps to BL31"),
    ]),
    ("secure", "imx-atf", "BL31", [
        ("bl31/bl31_main.c", "generic TF-A start-up: runtime services, then exit to BL33"),
        ("plat/imx/imx8m/imx8mp/imx8mp_bl31_setup.c", "CSU/RDC/TZASC rules, BL33 entry = 0x4020_0000 at EL2"),
        ("plat/imx/imx8m/imx8m_psci_common.c", "imx_pwr_domain_on(): how PSCI CPU_ON powers a core"),
        ("plat/imx/common/imx_sip_svc.c", "the 0xC2… NXP SiP calls (DDR DVFS, GPC, …)"),
    ]),
    ("boot", "uboot-imx", "U-Boot", [
        ("board/variscite/imx8mp_var_dart/imx8mp_var_dart.c", "board_late_init(): EEPROM → board_name, console"),
        ("board/variscite/imx8mp_var_dart/imx8mp_var_dart.env", "the default environment: bsp_bootcmd, findfdt …"),
        ("cmd/booti.c", "booti: relocate Image, pass the DTB in x0, jump"),
    ]),
    ("normal", "linux-imx", "Linux", [
        ("arch/arm64/kernel/head.S", "first kernel instructions: MMU on, EL2 stub, then C"),
        ("drivers/firmware/psci/psci.c", "psci_0_2_cpu_on() → arm_smccc_smc(): the smc to BL31"),
        ("drivers/of/platform.c · drivers/i2c/busses/i2c-imx.c", "DT nodes → devices; the I2C controller driver"),
        ("drivers/rtc/rtc-ds1307.c", "of_match_table + ds1307_probe(): the board's RTC"),
        ("init/main.c", "kernel_init(): run_init_process(\"/sbin/init\")"),
    ]),
]
y = 100
for role, repo, stage, files in STEPS:
    strong, soft, fill, border = ROLE[role]
    h = 30 + 38 * len(files)
    b.append(rect(32, y, 1336, h, fill=fill, stroke=border, rx=14, sw=1.6))
    b.append(rect(32, y, 150, h, fill=strong, rx=14))
    b.append(text(107, y + h / 2 - 4, stage, size=18, weight=800, anchor="middle", color="#fff"))
    b.append(text(107, y + h / 2 + 18, repo, size=12, mono=True, anchor="middle", color="#e2e8f0"))
    for i, (f, what) in enumerate(files):
        yy = y + 32 + i * 38
        indent = f.startswith("  ")
        b.append(rect(200, yy - 16, 560, 30, fill="#050a14", stroke="#334155", rx=8))
        b.append(text(214 + (16 if indent else 0), yy + 4, f.strip(), size=12.5, mono=True, color=soft))
        b.append(text(784, yy + 4, what, size=12.5, color=TEXT))
    if role != "normal":
        b.append(arrow(107, y + h + 2, 107, y + h + 24, A, "a", width=3))
    y += h + 28

b.append(caption(y + 10, "Each file is explained, with the real code, in docs/15-source-tour.md. Grep tips: grep -rn \"bsp_bootcmd\" build/src/uboot-imx/board/variscite/ ·"))
b.append(caption(y + 30, "grep -rn \"dallas,ds1337\" build/src/linux-imx/drivers/ · grep -rn \"IMX_SIP_\" build/src/imx-atf/plat/imx/"))
write("source-map.svg", W, H,
      "Source files that run during boot, in order: in uboot-imx the SPL's board_init_f, spl_dram_init, ddr_init, enable_tzc380 and the FIT "
      "loader; in imx-atf bl31_main, the i.MX8MP BL31 setup, the PSCI power-on code and the SiP services; back in uboot-imx the board's "
      "board_late_init, its default environment and booti; in linux-imx head.S, the PSCI driver, the device-tree platform code with the "
      "I2C and RTC drivers, and init/main.c, which starts /sbin/init.",
      "".join(b))
