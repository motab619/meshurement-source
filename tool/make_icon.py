# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Write every size of the app icon into the iOS AppIcon set and the
Android launcher icons (android/app/src/main/res: legacy mipmap PNGs, the
adaptive icon's foreground and monochrome layers per density, and its
background colour in values/ic_launcher_colors.xml) and the white
status-bar notification icon drawable-<density>/ic_stat_notify.png.

The icon is the pixel-art artwork in tool/icon_art.png (2026-11-05,
Meshurement: base node with an orange ring, signal arcs and green → red
dots inside a cyan rounded square, on near-black). The script finds the
rounded square against the artwork's background (the corner colour; the
2026-11-04 art was on white), crops to it, trims ART_TRIM and fills what is
left outside its corner radius with the edge colour (the cyan ring), so the
system's own corner mask never shows background. Without that file the
older drawn icon (below) is used instead.

    python3 tool/make_icon.py
    PREVIEW=out.png python3 tool/make_icon.py   # 1024 px preview only
"""

import json
import math
import os

from PIL import Image, ImageDraw

SIZE = 1024
ART = os.path.join(os.path.dirname(__file__), 'icon_art.png')

# Fraction of the artwork's rounded square cut from each edge. 0 keeps the
# cyan ring whole: it is part of the 2026-11-05 design (the 2026-11-04 art
# had a dark outline meant to be cut, at 0.02).
ART_TRIM = 0.0

# Keep the artwork's cyan rounded-square ring? Off since 2026-11-05 (it
# read as a heavy border on the home screen): the ring and everything
# outside it become the dark colour just inside it.
KEEP_RING = False
RING_MARGIN = 10      # px past the ring's inner edge (its soft glow)
RING_RADIUS = 0.30    # the ring's outer corner radius / side
SS = 4  # supersampling factor
ANDROID_RES = os.path.join(
    os.path.dirname(__file__), '..', 'android', 'app', 'src', 'main', 'res')
# Android densities: name, scale over mdpi (1 dp = 1 px).
DENSITIES = [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3),
             ('xxxhdpi', 4)]
LEGACY_DP = 48       # pre-adaptive launcher icon
ADAPTIVE_DP = 108    # adaptive layer canvas; the launcher shows the middle 72
# Side of the square the logo is fitted into on the adaptive canvas. The
# guaranteed-visible safe zone is a 66 dp circle; the logo's corners are
# mostly empty, but the node and the top arc sit in them, so 50 dp keeps
# them whole under a round mask (60 clipped the node).
LOGO_DP = 50
LEGACY_RADIUS = 0.18  # corner radius / side of the legacy square icon
NOTIFY_DP, NOTIFY_LIVE_DP = 24, 22  # status-bar icon canvas / live area
ICONSET = os.path.join(
    os.path.dirname(__file__), '..', 'ios', 'Runner', 'Assets.xcassets',
    'AppIcon.appiconset')

BG_CENTER = (0x0E, 0x1C, 0x2C)
BG_EDGE = (0x05, 0x0A, 0x18)

NODE_FILL = (0xFA, 0xF8, 0xF4)
NODE_RING = (0xFF, 0x60, 0x00)
NODE_R, RING_R = 62, 76

# Arcs around the node: radius, colour (lighter = closer).
ARCS = [
    (174, (0x7E, 0xAC, 0xE6)),
    (327, (0x68, 0x8E, 0xBE)),
    (481, (0x52, 0x70, 0x96)),
    (635, (0x3C, 0x52, 0x6E)),
]
ARC_WIDTH = 22
ARC_FROM, ARC_TO = -95, 5  # degrees, 0 = right, negative = up

# Signal dots: offset from the node, colour (strong → weak).
DOTS = [
    ((133, -113), (0x27, 0xAE, 0x60)),
    ((226, -195), (0x78, 0xBE, 0x46)),
    ((307, -266), (0xF1, 0xC4, 0x0F)),
    ((389, -338), (0xF3, 0x9C, 0x12)),
    ((461, -410), (0xE6, 0x6E, 0x28)),
    ((522, -472), (0xC0, 0x39, 0x2B)),
]
DOT_R, DOT_OUTLINE = 39, 3
DOT_OUTLINE_COLOR = (0x0C, 0x14, 0x2A)

# Artwork size relative to the measurements above, so the node clears the
# rounded corner the system masks the icon with.
ART_SCALE = 0.86


def artwork_box():
    """Bounding box of everything drawn, relative to the node centre."""
    outer = ARCS[-1][0] + ARC_WIDTH / 2
    xs = [-RING_R, RING_R, outer]
    ys = [-outer, RING_R]
    # Arc ends a few degrees past horizontal / vertical.
    for r, _ in ARCS:
        for a in (ARC_FROM, ARC_TO):
            xs.append(r * math.cos(math.radians(a)))
            ys.append(r * math.sin(math.radians(a)) + ARC_WIDTH / 2)
    for (dx, dy), _ in DOTS:
        xs += [dx - DOT_R, dx + DOT_R]
        ys += [dy - DOT_R, dy + DOT_R]
    return min(xs), min(ys), max(xs), max(ys)


def draw(size=SIZE):
    k = size * SS / SIZE * ART_SCALE  # design units → canvas pixels
    canvas = size * SS

    # Radial background, darker toward the corners (smooth, so drawn at
    # 256 px and scaled up).
    bg = Image.new('RGB', (256, 256))
    px = bg.load()
    maxd = math.hypot(128, 128)
    for y in range(256):
        for x in range(256):
            t = min(1.0, math.hypot(x + 0.5 - 128, y + 0.5 - 128) / maxd) ** 1.3
            px[x, y] = tuple(
                round(a + (b - a) * t) for a, b in zip(BG_CENTER, BG_EDGE))
    img = bg.resize((canvas, canvas), Image.BICUBIC)

    # Centre the artwork's bounding box on the canvas (in design units,
    # where the canvas is SIZE / ART_SCALE wide).
    x0, y0, x1, y1 = artwork_box()
    half = SIZE / ART_SCALE / 2
    nx = half - (x0 + x1) / 2
    ny = half - (y0 + y1) / 2

    d = ImageDraw.Draw(img)

    def circle(cx, cy, r, fill):
        d.ellipse([(cx - r) * k, (cy - r) * k, (cx + r) * k, (cy + r) * k],
                  fill=fill)

    for r, color in ARCS:
        outer = r + ARC_WIDTH / 2
        d.arc([(nx - outer) * k, (ny - outer) * k,
               (nx + outer) * k, (ny + outer) * k],
              start=ARC_FROM, end=ARC_TO, fill=color,
              width=round(ARC_WIDTH * k))

    for (dx, dy), color in DOTS:
        circle(nx + dx, ny + dy, DOT_R + DOT_OUTLINE, DOT_OUTLINE_COLOR)
        circle(nx + dx, ny + dy, DOT_R, color)

    circle(nx, ny, RING_R, NODE_RING)
    circle(nx, ny, NODE_R, NODE_FILL)

    return img.resize((size, size), Image.LANCZOS)


def from_art(path=ART):
    """The artwork's rounded square, trimmed and scaled to a SIZE square."""
    im = Image.open(path).convert('RGB')
    w, h = im.size
    back = im.getpixel((0, 0))

    def ink(p):
        return sum(abs(a - b) for a, b in zip(p, back)) > 90

    px = im.load()
    xs = [x for x in range(w) if any(ink(px[x, y]) for y in range(0, h, 4))]
    ys = [y for y in range(h) if any(ink(px[x, y]) for x in range(0, w, 4))]
    left, right, top, bottom = xs[0], xs[-1] + 1, ys[0], ys[-1] + 1
    side = min(right - left, bottom - top)
    trim = round(side * ART_TRIM)
    box = (left + trim, top + trim, left + side - trim, top + side - trim)
    sq = im.crop(box)
    if not KEEP_RING:
        return _drop_ring(sq).resize((SIZE, SIZE), Image.LANCZOS)
    # White left outside the artwork's corner radius takes the outline's
    # colour (sampled at an edge midpoint) so nothing pale shows through.
    bg = sq.getpixel((sq.width // 2, 2))
    for corner in [(0, 0), (sq.width - 1, 0), (0, sq.height - 1),
                   (sq.width - 1, sq.height - 1)]:
        if not ink(sq.getpixel(corner)):
            ImageDraw.floodfill(sq, corner, bg, thresh=60)
    return sq.resize((SIZE, SIZE), Image.LANCZOS)


def _drop_ring(sq):
    """Replace the artwork's own rounded-square ring (and everything
    outside it) with the colour just inside it, so the icon is the dark
    square edge to edge and iOS's mask gives the shape (2026-11-05: the
    cyan ring read as a heavy border on the home screen)."""
    side = sq.width
    mid = side // 2
    def is_ring(p):  # the bright cyan
        return p[1] > 160 and p[2] > 160 and p[0] < 140

    # Where the ring ends along the left edge's middle row (past any faint
    # glow outside it), then the colour just inside it.
    t = 0
    while t < side // 4 and not is_ring(sq.getpixel((t, mid))):
        t += 1
    while t < side // 4 and is_ring(sq.getpixel((t, mid))):
        t += 1
    inside = sq.getpixel((t + 12, mid))
    inset = t + RING_MARGIN
    radius = max(0, round(side * RING_RADIUS) - inset)
    mask = Image.new('L', sq.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [inset, inset, side - 1 - inset, side - 1 - inset],
        radius=radius, fill=255)
    out = Image.new('RGB', sq.size, inside)
    out.paste(sq, (0, 0), mask)
    return out


def main():
    master = from_art() if os.path.exists(ART) else draw()
    if os.environ.get('PREVIEW'):
        master.save(os.environ['PREVIEW'])
        return
    with open(os.path.join(ICONSET, 'Contents.json')) as f:
        images = json.load(f)['images']
    for entry in images:
        name = entry.get('filename')
        if not name:
            continue
        pts = float(entry['size'].split('x')[0])
        scale = int(entry['scale'].rstrip('x'))
        px = round(pts * scale)
        out = master if px == SIZE else master.resize((px, px), Image.LANCZOS)
        out.save(os.path.join(ICONSET, name))
        print(f'{name}: {px}px')
    write_android(master)


def _logo_layer(master):
    """The logo on transparency: alpha from each pixel's distance to the
    flat navy background, cropped to the logo. Returns (rgba, navy)."""
    navy = master.getpixel((4, master.height // 2))
    rgb = master.convert('RGB')
    alpha = Image.new('L', rgb.size, 0)
    src, ap = rgb.load(), alpha.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            d = max(abs(a - b) for a, b in zip(src[x, y], navy))
            ap[x, y] = max(0, min(255, (d - 6) * 255 // 40))
    layer = rgb.convert('RGBA')
    layer.putalpha(alpha)
    return layer.crop(alpha.getbbox()), navy


def write_android(master):
    logo, navy = _logo_layer(master)
    white = Image.new('RGBA', logo.size, (255, 255, 255, 255))
    white.putalpha(logo.getchannel('A'))
    for density, k in DENSITIES:
        folder = os.path.join(ANDROID_RES, f'mipmap-{density}')
        os.makedirs(folder, exist_ok=True)
        # Legacy icon: the full square with rounded corners.
        px = round(LEGACY_DP * k)
        icon = master.resize((px, px), Image.LANCZOS).convert('RGBA')
        mask = Image.new('L', (px * SS, px * SS), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, px * SS - 1, px * SS - 1],
            radius=round(px * SS * LEGACY_RADIUS), fill=255)
        icon.putalpha(mask.resize((px, px), Image.LANCZOS))
        icon.save(os.path.join(folder, 'ic_launcher.png'), optimize=True)
        # Status-bar notification icon: white silhouette, 24 dp canvas with
        # the logo in the 22 dp live area (drawable-<density>/ic_stat_notify).
        stat = round(NOTIFY_DP * k)
        f = NOTIFY_LIVE_DP * k / max(white.size)
        size = (round(white.width * f), round(white.height * f))
        out = Image.new('RGBA', (stat, stat), (0, 0, 0, 0))
        out.paste(white.resize(size, Image.LANCZOS),
                  ((stat - size[0]) // 2, (stat - size[1]) // 2))
        drawable = os.path.join(ANDROID_RES, f'drawable-{density}')
        os.makedirs(drawable, exist_ok=True)
        out.save(os.path.join(drawable, 'ic_stat_notify.png'), optimize=True)
        # Adaptive layers: logo centred on a transparent 108 dp canvas.
        canvas = round(ADAPTIVE_DP * k)
        side = LOGO_DP * k
        f = side / max(logo.size)
        size = (round(logo.width * f), round(logo.height * f))
        at = ((canvas - size[0]) // 2, (canvas - size[1]) // 2)
        for name, layer in [('ic_launcher_foreground', logo),
                            ('ic_launcher_monochrome', white)]:
            out = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
            out.paste(layer.resize(size, Image.LANCZOS), at)
            out.save(os.path.join(folder, f'{name}.png'), optimize=True)
        print(f'android {density}: {px}px, adaptive {canvas}px')
    values = os.path.join(ANDROID_RES, 'values')
    os.makedirs(values, exist_ok=True)
    with open(os.path.join(values, 'ic_launcher_colors.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<!-- Written by tool/make_icon.py: the icon\'s navy. -->\n'
                '<resources>\n'
                '    <color name="ic_launcher_background">'
                '#%02X%02X%02X</color>\n'
                '</resources>\n' % navy[:3])


if __name__ == '__main__':
    main()
