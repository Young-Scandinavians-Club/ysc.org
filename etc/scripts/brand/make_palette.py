#!/usr/bin/env python3
"""Write the YSC palette (served on /brand) as CSS variables, JSON, GIMP/Inkscape
.gpl and Adobe .ase files into priv/static/documents/brand.

Keep COLORS in sync with assets/tailwind.config.js and lib/ysc_web/brand_guide.ex.
Run from anywhere: python3 etc/scripts/brand/make_palette.py
"""
import json
import os
import struct

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "priv", "static", "documents", "brand")
os.makedirs(OUT, exist_ok=True)

COLORS = [
    ("Denmark Red", "denmark-red", "#C8102E"),
    ("Finland Blue", "finland-blue", "#002F6C"),
    ("Iceland Blue", "iceland-blue", "#02529C"),
    ("Iceland Red", "iceland-red", "#DC1E35"),
    ("Norway Red", "norway-red", "#BA0C2F"),
    ("Norway Blue", "norway-blue", "#00205B"),
    ("Sweden Blue", "sweden-blue", "#005293"),
    ("Sweden Yellow", "sweden-yellow", "#FECB00"),
    ("Brand Blue (web)", "brand-blue", "#144993"),
    ("Ink", "ink", "#18181B"),
    ("Secondary Text", "gray", "#52525B"),
    ("Border", "border", "#E4E4E7"),
    ("Page Gray", "page", "#F4F5F7"),
    ("White", "white", "#FFFFFF"),
]


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


# CSS
with open(os.path.join(OUT, "ysc-palette.css"), "w") as f:
    f.write("/* Young Scandinavians Club palette. All five Nordic countries share equal weight. */\n:root {\n")
    for name, slug, hexv in COLORS:
        f.write(f"  --ysc-{slug}: {hexv.lower()};\n")
    f.write("}\n")

# JSON
with open(os.path.join(OUT, "ysc-palette.json"), "w") as f:
    json.dump(
        [{"name": n, "id": s, "hex": h, "rgb": list(rgb(h))} for n, s, h in COLORS],
        f,
        indent=2,
    )
    f.write("\n")

# GIMP / Inkscape palette
with open(os.path.join(OUT, "ysc-palette.gpl"), "w") as f:
    f.write("GIMP Palette\nName: YSC\nColumns: 4\n#\n")
    for n, _, h in COLORS:
        r, g, b = rgb(h)
        f.write(f"{r:3d} {g:3d} {b:3d}\t{n}\n")

# Adobe Swatch Exchange (.ase): flat list of RGB global swatches
blocks = b""
for n, _, h in COLORS:
    r, g, b = [c / 255 for c in rgb(h)]
    name = (n + "\x00").encode("utf-16-be")
    body = struct.pack(">H", len(n) + 1) + name + b"RGB " + struct.pack(">fff", r, g, b) + struct.pack(">H", 0)
    blocks += struct.pack(">HI", 0x0001, len(body)) + body
with open(os.path.join(OUT, "ysc-palette.ase"), "wb") as f:
    f.write(b"ASEF" + struct.pack(">HHI", 1, 0, len(COLORS)) + blocks)

print("Wrote palette files to", OUT)
