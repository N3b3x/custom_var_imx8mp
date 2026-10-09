"""Place icons into the hand-drawn diagrams (idempotent: replaces <g id="icons">)."""
import os
import re
from kit import icon

W = "#ffffff"
ROSE, TEAL, BLUE, AMBER, VIOLET, SLATE = "#fb7185", "#5eead4", "#93c5fd", "#fcd34d", "#c4b5fd", "#cbd5e1"

ICONS = {
    "boot-chain.svg": [
        ("microchip", 192, 163, 24, W), ("memory-stick", 420, 163, 24, W), ("shield-check", 648, 163, 24, W),
        ("lock", 876, 163, 24, "#fecdd3"), ("rocket", 1104, 163, 24, W), ("linux", 1332, 163, 24, W, True),
    ],
    "build-pipeline.svg": [
        ("hammer", 250, 126, 20, SLATE), ("binary", 248, 212, 22, AMBER), ("shield-check", 248, 280, 22, ROSE),
        ("rocket", 248, 348, 22, BLUE), ("package", 248, 416, 22, SLATE), ("linux", 248, 516, 22, TEAL, True),
        ("debian", 222, 628, 20, "#f472b6", True), ("alpinelinux", 250, 628, 20, BLUE, True),
        ("file-archive", 978, 410, 22, BLUE), ("package", 978, 512, 22, TEAL), ("layers", 978, 622, 22, VIOLET),
        ("hard-drive", 1340, 400, 20, W),
    ],
    "exception-levels.svg": [
        ("shield-check", 888, 131, 30, W), ("lock", 384, 352, 24, ROSE), ("key-round", 384, 462, 24, ROSE),
        ("rocket", 794, 243, 24, BLUE), ("linux", 794, 352, 24, W, True), ("square-terminal", 794, 462, 24, TEAL),
        ("scroll-text", 1334, 132, 22, "#94a3b8"),
    ],
    "imx-boot-anatomy.svg": [
        ("memory-stick", 1338, 128, 20, SLATE), ("zap", 1338, 410, 20, AMBER), ("memory-stick", 1338, 476, 20, SLATE),
        ("file-archive", 470, 92, 22, SLATE),
    ],
    "trustzone.svg": [
        ("cpu", 432, 130, 26, W), ("network", 594, 266, 24, SLATE), ("shield", 286, 360, 24, AMBER),
        ("shield", 596, 360, 24, AMBER), ("memory-stick", 54, 529, 20, TEAL), ("usb", 364, 529, 20, TEAL),
        ("lock-open", 972, 128, 24, "#6ee7b7"), ("lock", 1332, 128, 24, ROSE),
    ],
    "uboot-bootcmd.svg": [
        ("clock", 406, 128, 22, W), ("hard-drive", 406, 197, 22, BLUE), ("scroll-text", 406, 266, 22, SLATE),
        ("file-cog", 406, 334, 22, SLATE), ("download", 406, 400, 22, BLUE), ("memory-stick", 406, 481, 22, BLUE),
        ("settings-2", 406, 548, 22, BLUE), ("scan-search", 406, 628, 22, VIOLET), ("file-text", 406, 739, 22, BLUE),
        ("rocket", 406, 808, 22, W), ("square-terminal", 1336, 130, 22, "#94a3b8"),
    ],
    "linux-to-login.svg": [
        ("alpinelinux", 748, 295, 22, TEAL, True), ("debian", 1336, 295, 22, "#f472b6", True),
        ("hard-drive", 216, 352, 18, SLATE), ("scroll-text", 216, 408, 18, SLATE), ("usb", 216, 464, 18, SLATE),
        ("package", 216, 520, 18, SLATE), ("clock", 216, 576, 18, SLATE), ("network", 216, 632, 18, SLATE),
        ("square-terminal", 216, 691, 18, W),
    ],
    "storage-map.svg": [
        ("wifi", 186, 116, 24, "#94a3b8"), ("hard-drive", 546, 116, 24, TEAL), ("microchip", 976, 116, 24, BLUE),
    ],
    "memory-map.svg": [
        ("memory-stick", 1334, 98, 22, SLATE),
    ],
}

here = os.path.dirname(os.path.abspath(__file__))
for name, items in ICONS.items():
    path = os.path.join(here, "..", name)
    s = open(path).read()
    s = re.sub(r'<g id="icons">.*?</g><!--/icons-->', "", s, flags=re.S)
    g = "".join(icon(i[0], i[1], i[2], i[3], i[4], filled=(len(i) > 5 and i[5])) for i in items)
    s = s.replace("</svg>", '<g id="icons">%s</g><!--/icons--></svg>' % g)
    open(path, "w").write(s)
    print("icons ->", name, len(items))
