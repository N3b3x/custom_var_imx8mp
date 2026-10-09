"""Tiny SVG drawing kit for the docs diagrams (dark theme, inline icons).

Icons: Lucide (ISC license, https://lucide.dev) and the Linux mark from
Simple Icons (CC0, https://simpleicons.org), embedded inline from icons/.
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))

# ---- theme -----------------------------------------------------------------
BG = "#0b1220"
PANEL = "#121c33"
PANEL2 = "#0f192d"
LINE = "#26344f"
TEXT = "#e5edf7"
MUTED = "#9fb0c6"
FAINT = "#64748b"

# role colours: (strong, soft text, tinted fill, border)
ROLE = {
    "secure": ("#e11d48", "#fda4af", "#2a0f1d", "#f43f5e"),
    "normal": ("#0d9488", "#5eead4", "#06231f", "#14b8a6"),
    "boot":   ("#2563eb", "#93c5fd", "#0c1d3d", "#3b82f6"),
    "fw":     ("#d97706", "#fcd34d", "#2a1b05", "#f59e0b"),
    "rootfs": ("#7c3aed", "#c4b5fd", "#1d1640", "#8b5cf6"),
    "hw":     ("#475569", "#cbd5e1", "#141f35", "#64748b"),
}

FONT = '"Segoe UI", "Helvetica Neue", Arial, "DejaVu Sans", sans-serif'
MONO = '"SFMono-Regular", Consolas, "Liberation Mono", "DejaVu Sans Mono", monospace'


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# ---- icons -----------------------------------------------------------------
_icon_cache = {}


def _icon_body(name):
    if name not in _icon_cache:
        src = open(os.path.join(HERE, "icons", name + ".svg")).read()
        src = re.sub(r"<!--.*?-->", "", src, flags=re.S)
        body = re.search(r"<svg[^>]*>(.*)</svg>", src, flags=re.S).group(1)
        body = re.sub(r"<title>.*?</title>", "", body)
        _icon_cache[name] = re.sub(r"\s+", " ", body).strip()
    return _icon_cache[name]


def icon(name, x, y, size=24, color=TEXT, filled=False):
    """Place a 24x24 icon with its top-left corner at (x, y)."""
    s = size / 24.0
    if filled:  # Simple Icons: filled paths
        return ('<g transform="translate(%g,%g) scale(%g)" fill="%s">%s</g>'
                % (x, y, s, color, _icon_body(name)))
    return ('<g transform="translate(%g,%g) scale(%g)" fill="none" stroke="%s" '
            'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">%s</g>'
            % (x, y, s, color, _icon_body(name)))


# ---- primitives --------------------------------------------------------------
def text(x, y, s, size=13, color=TEXT, weight=400, anchor="start", mono=False, extra=""):
    fam = MONO if mono else FONT
    return ('<text x="%g" y="%g" font-family=\'%s\' font-size="%g" font-weight="%s" '
            'text-anchor="%s" style="fill:%s;white-space:pre"%s>%s</text>'
            % (x, y, fam, size, weight, anchor, color, extra, esc(s)))


def rect(x, y, w, h, fill=PANEL, stroke=None, rx=12, sw=1.2, dash=None, opacity=None):
    a = 'x="%g" y="%g" width="%g" height="%g" rx="%g" fill="%s"' % (x, y, w, h, rx, fill)
    if stroke:
        a += ' stroke="%s" stroke-width="%g"' % (stroke, sw)
    if dash:
        a += ' stroke-dasharray="%s"' % dash
    if opacity is not None:
        a += ' fill-opacity="%g"' % opacity
    return "<rect %s/>" % a


def pill(cx, cy, s, color, bg=BG, size=12, mono=True, pad=10):
    w = len(s) * size * (0.62 if mono else 0.56) + 2 * pad
    return (rect(cx - w / 2, cy - size + 1, w, size + 10, fill=bg, stroke=color, rx=(size + 10) / 2, sw=1.5)
            + text(cx, cy + 4, s, size=size, color=color, weight=700, anchor="middle", mono=mono))


def marker_defs(colors):
    out = ["<defs>"]
    for name, c in colors.items():
        out.append('<marker id="m-%s" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="5" '
                   'markerHeight="5" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="%s"/></marker>'
                   % (name, c))
    out.append("</defs>")
    return "".join(out)


def arrow(x1, y1, x2, y2, color, mname, width=3.2, dash=None):
    d = ' stroke-dasharray="%s"' % dash if dash else ""
    return ('<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="%s" stroke-width="%g"%s '
            'stroke-linecap="round" marker-end="url(#m-%s)"/>' % (x1, y1, x2, y2, color, width, d, mname))


def badge(cx, cy, n, color, r=11):
    return ('<circle cx="%g" cy="%g" r="%g" fill="%s" stroke="%s" stroke-width="2"/>' % (cx, cy, r, color, BG)
            + text(cx, cy + 4.5, str(n), size=12, color="#0b1220", weight=800, anchor="middle"))


def svg(w, h, label, body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" '
            'role="img" aria-label="%s">' % (w, h, w, h, esc(label))
            + rect(0, 0, w, h, fill=BG, stroke="#1e2a44", rx=18) + body + "</svg>\n")


def title(t, sub):
    return text(32, 46, t, size=26, weight=700) + text(32, 72, sub, size=14, color=MUTED)


# ---- higher-level pieces -------------------------------------------------------
def card(x, y, w, h, title_s, role="hw", ic=None, sub=None, filled_icon=False, dashed=False, head=40):
    """Card with a coloured header strip (icon + title) and a dark body."""
    strong, soft, fill, border = ROLE[role]
    out = rect(x, y, w, h, fill=PANEL, stroke=border, rx=12, sw=1.6, dash="7 5" if dashed else None)
    out += ('<path d="M%g,%g a12,12 0 0 1 12,-12 h%g a12,12 0 0 1 12,12 v%g h%g z" fill="%s"/>'
            % (x, y + 12, w - 24, head - 12, -w, fill if dashed else strong))
    tx = x + 14
    if ic:
        out += icon(ic, x + 12, y + (head - 22) / 2, 22, soft if dashed else "#ffffff", filled=filled_icon)
        tx = x + 44
    out += text(tx, y + head / 2 + 5, title_s, size=14.5, weight=800, color=soft if dashed else "#ffffff")
    if sub:
        out += text(x + w - 12, y + head / 2 + 5, sub, size=11.5, color=soft if dashed else "#e2e8f0", anchor="end")
    return out


def lines(x, y, rows, size=12.5, gap=19, color=TEXT, mono=False, first=None):
    out = ""
    for i, r in enumerate(rows):
        c = first if (first and i == 0) else color
        out += text(x, y + i * gap, r, size=size, color=c, mono=mono)
    return out


def code(x, y, w, rows, accent="#93c5fd", size=12, gap=18, title_s=None):
    """Dark code block; rows are strings or (text, colour) tuples."""
    h = 16 + gap * len(rows) + (24 if title_s else 0)
    out = rect(x, y, w, h, fill="#050a14", stroke="#334155", rx=10, sw=1.2)
    yy = y + 22
    if title_s:
        out += text(x + 14, yy, title_s, size=11, color=FAINT, weight=700, mono=True)
        yy += 24
    for r in rows:
        t, c = (r, "#cbd5e1") if isinstance(r, str) else r
        out += text(x + 14, yy, t, size=size, mono=True, color=c)
        yy += gap
    return out


def path_arrow(points, color, mname, width=3, dash=None, label=None, lx=None, ly=None):
    d = "M" + " L".join("%g,%g" % p for p in points)
    a = ('<path d="%s" fill="none" stroke="%s" stroke-width="%g" stroke-linejoin="round" '
         'stroke-linecap="round"%s marker-end="url(#m-%s)"/>' % (d, color, width,
                                                                  ' stroke-dasharray="%s"' % dash if dash else "", mname))
    if label:
        a += pill(lx, ly, label, color)
    return a


def chip(x, y, s, role, size=11.5):
    strong, soft, fill, border = ROLE[role]
    w = len(s) * size * 0.6 + 20
    return rect(x, y, w, size + 12, fill=fill, stroke=border, rx=(size + 12) / 2, sw=1.2) + \
        text(x + w / 2, y + size + 3, s, size=size, color=soft, weight=700, anchor="middle")


def caption(y, s):
    return text(32, y, s, size=12.5, color=MUTED)


def write(name, w, h, label, body):
    path = os.path.join(HERE, "..", name)
    open(path, "w").write(svg(w, h, label, body))
    print("wrote", name)
