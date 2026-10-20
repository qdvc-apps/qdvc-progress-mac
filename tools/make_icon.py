#!/usr/bin/env python3
"""Generate the app icon: Resources/AppIcon.svg (vector master) and
Resources/AppIcon.icns (every macOS size, rendered natively from the vector).

The design is a white spreadsheet filling the whole icon shape, as in the
GTK 4 edition's icon (qdvc-progress-gtk4, tools/make_icon.py), so the two
editions are recognisably the same app: a light grey header row with today's
column in yellow, project titles down the left, rows of work cells in the
app's blue heat map (one bright green meeting among them), a row of
salmon-to-red totals, and a glossy navy badge carrying a rising arrow:
progress, logged day by day. The cells, today's column and the badge are
placed as in the GTK 4 icon, rescaled from its 108 x 96 card to the square
macOS tile.

Geometry follows Apple's macOS icon template: a 1024x1024 canvas holding an
824x824 tile (100 px transparent margin) with a 185.4 px continuous-curvature
("squircle") corner, plus a soft drop shadow. The corner is the curve UIKit
draws for continuous corners, as reverse-engineered and published by PaintCode
(https://www.paintcodeapp.com/blogpost/code-for-ios-7-rounded-rectangles).

Usage:

    python3 tools/make_icon.py            # writes Resources/AppIcon.{svg,icns}
    python3 tools/make_icon.py --preview  # also writes build/icon-preview.png

Requires rsvg-convert (macOS: `brew install librsvg`; Debian/Ubuntu:
`apt install librsvg2-bin`). No other dependencies; the .icns is written
directly, so Apple's iconutil is not needed.
"""

import argparse
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"

# ---------------------------------------------------------------------------
# Palette. The tile is white, shading to the faintest grey at the bottom so it
# keeps an edge on a white background; the greys are GNOME's, as in the GTK 4
# icon.

TILE_TOP, TILE_BOTTOM = "#FFFFFF", "#F3F3F5"
HEADER = "#F0EFF0"
STUB = "#C0BFBC"
RULE = "#DEDDDA"

# The grid's own colours (Sources/QDVCProgress/Grid/GridStyle.swift).
SIZES = ["#CFE8FB", "#9CCBF2", "#5A9BDB", "#2B5EA8", "#10275C"]
MEETING = "#2EDB4F"
TODAY = "#FFD60A"
TOTALS = ["#FCD2C3", "#F29C85", "#E06A55", "#C62F2F"]

# The badge: a navy sphere with a white rising arrow.
FACE_LIGHT, FACE_MID, FACE_DARK = "#7FA8E8", "#2B5EA8", "#10275C"
FEATURES = "#FFFFFF"

# ---------------------------------------------------------------------------
# Apple's template geometry.

TILE_ORIGIN, TILE_SIZE, CORNER_RADIUS = 100, 824, 185.4
SHADOW_BLUR_RADIUS, SHADOW_OFFSET_Y, SHADOW_OPACITY = 28, 12, 0.5

# Continuous-corner segments around the top-right corner, in units of the
# radius: (distance from the right edge, distance from the top edge).
_CORNER = [
    ("L", (1.52866471, 0.0)),
    ("C", (1.08849323, 0.0), (0.86840689, 0.0), (0.66993427, 0.06549600)),
    ("L", (0.63149399, 0.07491100)),
    ("C", (0.37282392, 0.16905899), (0.16906013, 0.37282401), (0.07491176, 0.63149399)),
    ("C", (0.0, 0.86840701), (0.0, 1.08849299), (0.0, 1.52866483)),
]


def continuous_rounded_rect(x, y, w, h, r):
    """SVG path of a rounded rectangle with Apple's continuous corners."""
    r = min(r, min(w, h) / 2 / 1.52866483)
    corners = [
        lambda u, v: (x + w - u * r, y + v * r),        # top-right
        lambda u, v: (x + w - v * r, y + h - u * r),    # bottom-right
        lambda u, v: (x + u * r, y + h - v * r),        # bottom-left
        lambda u, v: (x + v * r, y + u * r),            # top-left
    ]

    def fmt(p):
        return f"{p[0]:.2f},{p[1]:.2f}"

    d = [f"M{fmt((x + 1.52866483 * r, y))}"]
    for corner in corners:
        for seg in _CORNER:
            if seg[0] == "L":
                d.append("L" + fmt(corner(*seg[1])))
            else:
                d.append("C" + " ".join(fmt(corner(*p)) for p in seg[1:]))
    d.append("Z")
    return " ".join(d)


TILE = continuous_rounded_rect(TILE_ORIGIN, TILE_ORIGIN, TILE_SIZE, TILE_SIZE, CORNER_RADIUS)

# The grid, as in the GTK 4 icon: rows top to bottom, five day columns; an
# index into SIZES, "m" for a meeting, or None for an empty cell. TOTAL_ROW
# indexes TOTALS.
WORK = [
    [3, 2, None, 1, 0],
    [None, "m", 2, 3, None],
    [1, None, 4, 2, 1],
]
TOTAL_ROW = [2, 1, 3, 3, 1]
TODAY_COL = 2

# Layout inside the tile, in canvas pixels.
HEADER_H = 168          # the header row's height
PROJECT_W = 176         # the project column, left of the days
RIGHT_PAD = 40
ROW_H = 130             # work and totals rows
CELL_INSET = 12         # gap between a cell and its row/column bounds
SEAL_RADIUS = 122


def _grid():
    """The spreadsheet filling the tile. Returns (elements, seal centre)."""
    x0 = y0 = TILE_ORIGIN
    size = TILE_SIZE
    left = x0 + PROJECT_W
    cw = (size - PROJECT_W - RIGHT_PAD) / len(WORK[0])
    top = y0 + HEADER_H + 34
    tot_y = top + len(WORK) * ROW_H + 30
    parts = [
        # Header row, with a hairline under it.
        f'<rect x="{x0}" y="{y0}" width="{size}" height="{HEADER_H}" fill="{HEADER}"/>',
        f'<rect x="{x0}" y="{y0 + HEADER_H - 3}" width="{size}" height="3" fill="{RULE}"/>',
    ]

    # Today's column: a pale yellow band down the grid, solid in the header.
    tx = left + TODAY_COL * cw
    parts.append(f'<rect x="{tx + 8:.1f}" y="{y0 + 40}" width="{cw - 16:.1f}" '
                 f'height="{tot_y + ROW_H + 10 - (y0 + 40):.1f}" rx="26" fill="{TODAY}" fill-opacity="0.28"/>')
    parts.append(f'<rect x="{tx + 8:.1f}" y="{y0 + 40}" width="{cw - 16:.1f}" height="{HEADER_H - 76}" '
                 f'rx="26" fill="{TODAY}"/>')
    for c in range(len(WORK[0])):
        if c != TODAY_COL:
            parts.append(f'<rect x="{left + c * cw + cw / 2 - 30:.1f}" y="{y0 + HEADER_H / 2 - 12:.1f}" '
                         f'width="60" height="24" rx="12" fill="{STUB}"/>')

    # Project titles, then the work cells.
    for r, row in enumerate(WORK):
        yy = top + r * ROW_H
        parts.append(f'<rect x="{x0 + 54}" y="{yy + ROW_H / 2 - 16:.1f}" width="108" height="32" rx="16" '
                     f'fill="{STUB}"/>')
        for c, v in enumerate(row):
            if v is None:
                continue
            fill = MEETING if v == "m" else SIZES[v]
            parts.append(f'<rect x="{left + c * cw + CELL_INSET:.1f}" y="{yy + CELL_INSET}" '
                         f'width="{cw - 2 * CELL_INSET:.1f}" height="{ROW_H - 2 * CELL_INSET}" rx="24" '
                         f'fill="{fill}"/>')

    # Totals, under a rule.
    parts.append(f'<rect x="{x0 + 40}" y="{tot_y - 18}" width="{size - 80}" height="6" rx="3" fill="{RULE}"/>')
    for c, v in enumerate(TOTAL_ROW):
        parts.append(f'<rect x="{left + c * cw + CELL_INSET:.1f}" y="{tot_y + CELL_INSET}" '
                     f'width="{cw - 2 * CELL_INSET:.1f}" height="{ROW_H - 2 * CELL_INSET}" rx="24" '
                     f'fill="{TOTALS[v]}"/>')

    # The badge sits over the lower right of the grid, inside the tile.
    return parts, (x0 + size - 176, y0 + size - 166)


def _seal(cx, cy, r):
    """A glossy navy seal with a white rising arrow, in a white ring that
    parts it from the cells beneath."""
    s = r * 0.62
    pts = [(cx - s, cy + s * 0.55), (cx - s * 0.3, cy - s * 0.05), (cx + s * 0.1, cy + s * 0.3),
           (cx + s * 0.78, cy - s * 0.45)]
    line = " ".join(f"{px:.1f},{py:.1f}" for px, py in pts)
    tip = pts[-1]
    head = (f'M{tip[0] + s * 0.18:.1f},{tip[1] - s * 0.18:.1f} '
            f'L{tip[0] - s * 0.42:.1f},{tip[1] - s * 0.14:.1f} '
            f'L{tip[0] + s * 0.12:.1f},{tip[1] + s * 0.42:.1f} Z')
    return [
        f'<circle cx="{cx}" cy="{cy}" r="{r + 12}" fill="#FFFFFF"/>',
        f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#face)"/>',
        f'<polyline points="{line}" fill="none" stroke="{FEATURES}" stroke-width="{r * 0.15:.1f}" '
        'stroke-linecap="round" stroke-linejoin="round"/>',
        f'<path d="{head}" fill="{FEATURES}" stroke="{FEATURES}" stroke-width="{r * 0.05:.1f}" stroke-linejoin="round"/>',
        # specular highlight
        f'<ellipse cx="{cx - r * 0.30:.1f}" cy="{cy - r * 0.55:.1f}" rx="{r * 0.38:.1f}" '
        f'ry="{r * 0.18:.1f}" fill="#FFFFFF" opacity="0.40"/>',
    ]


def icon_svg():
    sigma = SHADOW_BLUR_RADIUS / 2
    defs = [
        '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{TILE_TOP}"/><stop offset="1" stop-color="{TILE_BOTTOM}"/></linearGradient>',
        '<linearGradient id="edge" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#000000" stop-opacity="0.04"/>'
        '<stop offset="1" stop-color="#000000" stop-opacity="0.12"/></linearGradient>',
        '<radialGradient id="face" cx="0.38" cy="0.30" r="0.8">'
        f'<stop offset="0" stop-color="{FACE_LIGHT}"/><stop offset="0.55" stop-color="{FACE_MID}"/>'
        f'<stop offset="1" stop-color="{FACE_DARK}"/></radialGradient>',
        f'<clipPath id="clip"><path d="{TILE}"/></clipPath>',
        # Apple template shadow: black, 28 px blur radius, 12 px down, 50 %.
        '<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">'
        f'<feGaussianBlur in="SourceAlpha" stdDeviation="{sigma}"/><feOffset dy="{SHADOW_OFFSET_Y}"/>'
        f'<feComponentTransfer><feFuncA type="linear" slope="{SHADOW_OPACITY}"/></feComponentTransfer>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
        # A soft navy shadow under the badge, lifting it off the grid.
        '<filter id="objshadow" x="-30%" y="-30%" width="160%" height="160%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="12"/><feOffset dx="0" dy="12"/>'
        f'<feFlood flood-color="{FACE_DARK}" flood-opacity="0.35"/><feComposite operator="in" in2="SourceAlpha"/>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
    ]
    grid, (cx, cy) = _grid()
    parts = [
        f'<g filter="url(#shadow)"><path d="{TILE}" fill="url(#bg)"/></g>',
        '<g clip-path="url(#clip)">',
        *grid,
        '<g filter="url(#objshadow)">', *_seal(cx, cy, SEAL_RADIUS), '</g>',
        '</g>',
        # A hairline edge, so the white tile holds its shape on white.
        f'<path d="{TILE}" fill="none" stroke="url(#edge)" stroke-width="3"/>',
    ]
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{"".join(defs)}</defs>{"".join(parts)}</svg>\n')


# ---------------------------------------------------------------------------
# .icns writing. These are the element types `iconutil` emits for a standard
# .iconset; all of them hold PNG data.

ICNS_ELEMENTS = [
    ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64),
    ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512),
    ("ic09", 512), ("ic10", 1024),
]


def render_png(svg_path, size, out_path):
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(svg_path), "-o", str(out_path)],
                   check=True)


def write_icns(pngs_by_size, out_path):
    chunks = b""
    for code, size in ICNS_ELEMENTS:
        data = pngs_by_size[size]
        chunks += code.encode("ascii") + struct.pack(">I", len(data) + 8) + data
    out_path.write_bytes(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def main():
    parser = argparse.ArgumentParser(description="Generate Resources/AppIcon.svg and AppIcon.icns.")
    parser.add_argument("--preview", action="store_true",
                        help="also write build/icon-preview.png (1024 px)")
    args = parser.parse_args()

    try:
        subprocess.run(["rsvg-convert", "--version"], check=True, capture_output=True)
    except (OSError, subprocess.CalledProcessError):
        sys.exit("error: rsvg-convert not found (macOS: brew install librsvg)")

    RESOURCES.mkdir(exist_ok=True)
    svg_path = RESOURCES / "AppIcon.svg"
    svg_path.write_text(icon_svg())

    with tempfile.TemporaryDirectory() as tmp:
        pngs = {}
        for size in sorted({s for _, s in ICNS_ELEMENTS}):
            png = Path(tmp) / f"icon_{size}.png"
            render_png(svg_path, size, png)
            pngs[size] = png.read_bytes()
        write_icns(pngs, RESOURCES / "AppIcon.icns")

    if args.preview:
        (ROOT / "build").mkdir(exist_ok=True)
        render_png(svg_path, 1024, ROOT / "build" / "icon-preview.png")
    print(f"Wrote {svg_path.relative_to(ROOT)} and Resources/AppIcon.icns")


if __name__ == "__main__":
    main()
