# Meshurement website - images for meshurement.com.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Build the web images in site/public from Andy's artwork.

Usage (Xcode's python3 has Pillow with WebP):
  /Applications/Xcode.app/Contents/Developer/usr/bin/python3 \
      site/scripts/make_images.py site/art/icon.webp site/art/splash.webp site/public
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw


def key_out(im, bg, soft=70.0):
    """Turn pixels near the background colour transparent (soft edge), for glow text."""
    im = im.convert("RGB")
    out = Image.new("RGBA", im.size)
    src = im.load()
    dst = out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b = src[x, y]
            d = max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2]))
            a = min(1.0, max(0.0, (d - 22) / soft))
            if a <= 0:
                dst[x, y] = (0, 0, 0, 0)
                continue
            c = [min(255, max(0, round((v - bv * (1 - a)) / a))) for v, bv in ((r, bg[0]), (g, bg[1]), (b, bg[2]))]
            dst[x, y] = (c[0], c[1], c[2], round(a * 255))
    return out


def clear_corners(im):
    """Make the dark field outside the icon's rounded square transparent."""
    im = im.convert("RGBA")
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, im.width - 1, im.height - 1), radius=int(im.width * 0.2), fill=255)
    im.putalpha(mask)
    return im

icon_src, splash_src, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
img = out / "img"
img.mkdir(parents=True, exist_ok=True)

icon = Image.open(icon_src).convert("RGB")
# The artwork is a cyan rounded square on a near-black field; keep a little margin.
w, h = icon.size
m = int(w * 0.058)
square = clear_corners(icon.crop((m, m, w - m, h - m)))

for size in (512, 256):
    square.resize((size, size), Image.LANCZOS).save(img / f"icon-{size}.webp", quality=90)
square.resize((512, 512), Image.LANCZOS).save(img / "icon-512.png", optimize=True)
# apple-touch-icon: iOS rounds it itself, so give it the full square on navy.
touch = Image.new("RGB", square.size, (2, 8, 30))
touch.paste(square, (0, 0), square)
touch.resize((180, 180), Image.LANCZOS).save(out / "apple-touch-icon.png", optimize=True)
for size in (32, 16):
    square.resize((size, size), Image.LANCZOS).save(img / f"favicon-{size}.png", optimize=True)
square.resize((48, 48), Image.LANCZOS).save(
    out / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])

splash = Image.open(splash_src).convert("RGB")
sw, sh = splash.size
# Wordmark band: "Meshurement" plus its three speed lines.
band = splash.crop((int(sw * 0.03), int(sh * 0.585), int(sw * 0.97), int(sh * 0.71)))
corners = [band.getpixel(c) for c in ((0, 0), (band.width - 1, 0), (0, band.height - 1), (band.width - 1, band.height - 1))]
band = key_out(band, tuple(sum(c[i] for c in corners) // 4 for i in range(3)))
bw = 900
band.resize((bw, round(band.height * bw / band.width)), Image.LANCZOS).save(
    img / "wordmark.webp", quality=90)
band.resize((bw, round(band.height * bw / band.width)), Image.LANCZOS).save(
    img / "wordmark.png", optimize=True)

# Open Graph card 1200x630: icon left, wordmark right, on the splash's navy.
bg = splash.getpixel((sw // 2, 20))
card = Image.new("RGB", (1200, 630), bg)
ic = square.resize((400, 400), Image.LANCZOS)
card.paste(ic, (70, 115), ic)
wm = band.resize((640, round(band.height * 640 / band.width)), Image.LANCZOS)
card.paste(wm, (510, (630 - wm.height) // 2), wm)
card.save(img / "og-card.png", optimize=True)
print("ok", sorted(p.name for p in img.iterdir()))
