"""Concept diagrams: uboot-env.svg, linux-fs.svg, customize-map.svg (generated)."""
from kit import *

A = "#e5edf7"

# =====================================================================================
# uboot-env.svg
# =====================================================================================
W, H = 1400, 760
b = [marker_defs({"a": A, "b": "#93c5fd"})]
b.append(title("Where U-Boot's variables come from",
               "Four layers, later ones win. bootcmd, fdt_file, console, kernelargs … each one can come from any layer."))
LAY = [
    ("1", "Compiled-in default", "boot", "binary",
     "board/variscite/imx8mp_var_dart/imx8mp_var_dart.env → baked into u-boot.bin",
     ["build/deploy/u-boot-initial-env   (read it!)"], "always there; used when nothing else exists"),
    ("2", "Saved environment", "fw", "hard-drive",
     "16 KiB at 7 MiB on the boot device (CONFIG_ENV_OFFSET = 0x700000), CRC-protected",
     ["u-boot=> saveenv            (write)", "u-boot=> env default -a; saveenv   (reset)"], "if valid, REPLACES layer 1 entirely"),
    ("3", "/boot/uEnv.txt", "rootfs", "file-text",
     "plain-text name=value file on partition 1, imported by bsp_bootcmd every boot",
     ["fdt_file=imx8mp-var-som-symphony.dtb", "kernelargs=loglevel=8"], "overrides just the variables it lists"),
    ("4", "Typed at the prompt", "secure", "keyboard",
     "stop autoboot with any key, then setenv / printenv / run",
     ["u-boot=> setenv kernelargs quiet", "u-boot=> boot"], "until reset, unless you saveenv"),
]
for i, (n, name, role, ic, where, cmds, effect) in enumerate(LAY):
    strong, soft, fill, border = ROLE[role]
    y = 548 - i * 132
    x = 32 + i * 26
    b.append(rect(x, y, 900 - i * 26, 116, fill=fill, stroke=border, rx=14, sw=1.6))
    b.append(rect(x, y, 70, 116, fill=strong, rx=14))
    b.append(text(x + 35, y + 50, n, size=28, weight=800, anchor="middle", color="#fff"))
    b.append(icon(ic, x + 23, y + 66, 24, "#fff"))
    b.append(text(x + 88, y + 30, name, size=16, weight=800, color=soft))
    b.append(text(x + 88, y + 52, where, size=12, color=MUTED))
    b.append(code(x + 88, y + 62, 420, [(c, "#cbd5e1") for c in cmds], size=11.5, gap=17))
    b.append(chip(x + 530 - i * 0, y + 72, effect, role))
# precedence arrow
b.append(arrow(970, 664, 970, 132, "#93c5fd", "b", width=4))
b.append(text(988, 400, "wins", size=14, weight=800, color="#93c5fd"))
b.append(text(988, 420, "over the", size=12.5, color=MUTED))
b.append(text(988, 438, "layers below", size=12.5, color=MUTED))
# right panel: real board
b.append(rect(1100, 116, 270, 548, fill="#050a14", stroke="#334155", rx=14))
b.append(icon("square-terminal", 1118, 132, 22, "#94a3b8"))
b.append(text(1150, 149, "ON YOUR BOARD", size=12, weight=800, color=MUTED, extra=' letter-spacing="1.3"'))
b.append(lines(1118, 186, ["First boot said:"], size=12, color=TEXT))
b.append(code(1118, 196, 236, [("*** Warning - bad CRC,", "#fcd34d"), ("using default", "#fcd34d"), ("environment", "#fcd34d")], size=11))
b.append(lines(1118, 290, ["→ layer 2 is empty: nothing", "  was ever saved. Normal.", "", "Then:"], size=12, color=MUTED))
b.append(code(1118, 352, 236, [("Failed to load", "#fcd34d"), ("'/boot/uEnv.txt'", "#fcd34d")], size=11))
b.append(lines(1118, 420, ["→ no layer 3 either.", "", "So every value came from", "layer 1: the defaults", "this repo compiled.", "", "From Linux: fw_printenv", "(apt install libubootenv-tool", " + /etc/fw_env.config)"], size=12, color=MUTED))
b.append(caption(700, "Safest way to experiment: put one line in /boot/uEnv.txt (mount the card on your PC, or edit it on the board) and reboot. Delete the file to undo."))
b.append(caption(722, "Factory reset of a board whose saved environment you broke: stop autoboot, then  env default -a; saveenv; reset."))
write("uboot-env.svg", W, H,
      "The four layers of U-Boot's environment, lowest to highest priority: the compiled-in default from the board's .env file; the "
      "saved environment at 7 MiB on the boot device, which replaces the default when its CRC is valid; /boot/uEnv.txt, imported every "
      "boot to override selected variables; and values typed at the U-Boot prompt. On this board only the compiled-in default was used.",
      "".join(b))

# =====================================================================================
# linux-fs.svg
# =====================================================================================
W, H = 1400, 820
b = [marker_defs({"a": A})]
b.append(title("The running system: real files vs. live kernel views",
               "/ on the SD card holds programs and config. /proc, /sys and /dev are not on any disk: the kernel generates them as you read."))
# left: on disk
b.append(card(32, 104, 430, 640, "On the SD card (ext4, mmcblk1p1)", "rootfs", "hard-drive"))
DISK = [("/boot", "Image.gz, 47 DTBs: what U-Boot loads"), ("/lib/modules/6.18.20-custom", "the .ko drivers + modules.alias"),
        ("/lib/firmware/imx", "SDMA/audio firmware the drivers request"), ("/sbin/init", "PID 1 (BusyBox or systemd)"),
        ("/etc", "inittab, fstab, hostname, network, ssh"), ("/bin  /usr", "programs and libraries"),
        ("/root  /home", "user files"), ("/var/log", "logs (Debian; Alpine logs to RAM)")]
for i, (p, d) in enumerate(DISK):
    y = 160 + i * 70
    b.append(rect(48, y, 398, 58, fill=PANEL2, stroke=LINE, rx=10))
    b.append(text(62, y + 24, p, size=13.5, weight=700, mono=True, color="#c4b5fd"))
    b.append(text(62, y + 44, d, size=12, color=MUTED))

# right: three virtual fs
VFS = [
    ("/proc", "procfs · processes + kernel state", "normal", "cpu",
     [("cat /proc/cmdline", "console=ttymxc1,115200 root=/dev/mmcblk1p1 …"), ("cat /proc/cpuinfo", "4 × Cortex-A53"),
      ("ls /proc/1/", "everything about PID 1"), ("cat /proc/meminfo", "MemTotal, CmaTotal …")]),
    ("/sys", "sysfs · the device model", "boot", "boxes",
     [("/sys/class/thermal/thermal_zone0/temp", "57000 = 57 °C"), ("/sys/bus/i2c/devices/3-0068", "the RTC, from the DTB"),
      ("/sys/class/net/eth1/carrier", "1 = cable in"), ("/sys/firmware/devicetree/base", "the DTB U-Boot passed")]),
    ("/dev", "devtmpfs + mdev/udev · device nodes", "fw", "usb",
     [("/dev/mmcblk1p1", "the SD card's root partition"), ("/dev/ttymxc1", "the serial console"),
      ("/dev/rtc0  /dev/i2c-3", "created when drivers probe"), ("/dev/null  /dev/zero", "666: usable by everyone")]),
]
for i, (p, sub, role, ic, rows) in enumerate(VFS):
    y = 104 + i * 218
    b.append(card(520, y, 848, 202, p + "   " + sub, role, ic))
    for j, (cmd, res) in enumerate(rows):
        yy = y + 58 + j * 34
        b.append(text(540, yy + 4, cmd, size=12.5, mono=True, color=TEXT))
        b.append(text(1000, yy + 4, res, size=12.5, color=ROLE[role][1]))
b.append(arrow(464, 420, 516, 420, A, "a"))
b.append(text(468, 410, "mounts", size=11.5, color=MUTED))
b.append(caption(772, "init mounts them at boot (mount -t proc / sysfs / devtmpfs). Reading a file there asks the kernel a question; writing one (e.g. echo to /sys/class/leds/…)"))
b.append(caption(792, "changes hardware state. That's how most of the commands in 11 · Using the board work: ps reads /proc, free reads /proc/meminfo, ip talks to the kernel."))
write("linux-fs.svg", W, H,
      "On the running board, the ext4 root filesystem on the SD card holds /boot, /lib/modules, /lib/firmware, /sbin/init, /etc and programs, "
      "while /proc, /sys and /dev are virtual: procfs exposes processes and kernel state, sysfs exposes the device model, and devtmpfs with "
      "mdev or udev provides device nodes such as /dev/mmcblk1p1, /dev/ttymxc1 and /dev/rtc0. Examples are real values from this board.",
      "".join(b))

# =====================================================================================
# customize-map.svg
# =====================================================================================
W, H = 1400, 700
b = [marker_defs({"a": A})]
b.append(title("Where your changes go, and where they end up",
               "Never edit build/src/ directly (it's disposable). Put changes in these places; the build picks them up."))
ROWS = [
    ("config/local.conf", "versions, passwords, packages, hostname, BUILD_DIR", "fw", "settings-2", "every script", "everything"),
    ("patches/uboot/*.patch", "U-Boot source changes (git format-patch)", "boot", "git-branch", "uboot.sh step 3", "imx-boot.bin @ 32 KiB"),
    ("patches/atf/*.patch", "TF-A source changes", "secure", "git-branch", "uboot.sh step 2", "imx-boot.bin → BL31"),
    ("patches/kernel/*.patch", "kernel / driver source changes", "normal", "git-branch", "kernel.sh", "/boot/Image.gz, modules"),
    ("config/kernel/*.cfg", "kernel options (CONFIG_FOO=y)", "normal", "file-cog", "kernel.sh config", "/boot/Image.gz, modules"),
    ("custom/dts/*.dts", "your carrier board's device tree", "rootfs", "file-text", "kernel.sh dtbs", "/boot/<name>.dtb"),
    ("scripts/rootfs/debian-customize.sh", "users, network, services (Debian)", "rootfs", "scroll-text", "rootfs.sh", "/ on partition 1"),
    ("/boot/uEnv.txt (on the card)", "boot-time overrides: fdt_file, kernelargs", "boot", "file-text", "U-Boot at boot", "no rebuild needed"),
]
b.append(text(52, 112, "YOU EDIT", size=12, weight=800, color=MUTED, extra=' letter-spacing="1.3"'))
b.append(text(700, 112, "CONSUMED BY", size=12, weight=800, color=MUTED, extra=' letter-spacing="1.3"'))
b.append(text(1000, 112, "ENDS UP IN", size=12, weight=800, color=MUTED, extra=' letter-spacing="1.3"'))
for i, (f, d, role, ic, by, where) in enumerate(ROWS):
    strong, soft, fill, border = ROLE[role]
    y = 126 + i * 64
    b.append(rect(32, y, 600, 52, fill=fill, stroke=border, rx=12, sw=1.4))
    b.append(icon(ic, 46, y + 14, 24, soft))
    b.append(text(82, y + 22, f, size=13.5, weight=800, mono=True, color=soft))
    b.append(text(82, y + 41, d, size=12, color=MUTED))
    b.append(arrow(636, y + 26, 690, y + 26, A, "a", width=2.6))
    b.append(rect(694, y + 8, 260, 36, fill=PANEL, stroke=LINE, rx=10))
    b.append(text(710, y + 31, by, size=12.5, mono=True, color=TEXT))
    b.append(arrow(958, y + 26, 994, y + 26, A, "a", width=2.6))
    b.append(rect(998, y + 8, 370, 36, fill=PANEL, stroke=border, rx=10))
    b.append(text(1014, y + 31, where, size=12.5, color=soft, weight=700))
b.append(caption(660, "Then rebuild only what changed: ./build.sh uboot | kernel | rootfs, then ./build.sh image, or update a card in place with flash --kernel-only / --bootloader-only."))
write("customize-map.svg", W, H,
      "Where to make changes and where they end up: config/local.conf affects every script; patches for U-Boot, TF-A and the kernel are "
      "applied by their build steps and end up in imx-boot.bin or the kernel; kernel config fragments and custom device trees go through "
      "kernel.sh into /boot; debian-customize.sh shapes the Debian root filesystem; /boot/uEnv.txt on the card changes boot settings "
      "without rebuilding.",
      "".join(b))
