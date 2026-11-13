# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Write the launch splash from tool/splash_art.png (logo + Meshurement
wordmark on a navy glow, 2026-11-05).

The artwork draws the logo inside a cyan rounded square on a darker tile.
Like the app icon (make_icon.py, KEEP_RING = False), the splash drops it
(Andy, 2026-11-05): the ring and the dark tile are replaced by the glow
around them, filled from just outside the ring (rows and columns blended) and softened,
and only the bright logo pixels (arcs, dots, node) are laid back on top.

Outputs: assets/brand/splash.png (the in-app SplashOverlay), the
LaunchImage set used by ios/Runner/Base.lproj/LaunchScreen.storyboard, and
Android's drawable-<density>/launch_image.png, centred on #01011A by
res/drawable*/launch_background.xml (the pre-Android 12 launch window; 12+
shows the system splash with the adaptive icon foreground instead).

    /Applications/Xcode.app/Contents/Developer/usr/bin/python3 tool/make_splash.py
"""

import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), '..')
ART = os.path.join(ROOT, 'tool', 'splash_art.png')
OUT = os.path.join(ROOT, 'assets', 'brand', 'splash.png')
LAUNCH = os.path.join(ROOT, 'ios', 'Runner', 'Assets.xcassets',
                      'LaunchImage.imageset')
ANDROID_RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
# Android densities over the @3x art (the iOS image is 1/3 of it in points,
# so the same dp size on Android). xxxhdpi uses xxhdpi rather than upscale.
ANDROID_DENSITIES = [('mdpi', 1 / 3), ('hdpi', 1.5 / 3), ('xhdpi', 2 / 3),
                     ('xxhdpi', 1)]

GLOW_MARGIN = 45   # px outside the ring that its glow reaches
INNER_MARGIN = 8   # px inside the ring kept clear of the ring's edge
CORNER = 100       # inner corner radius, px (clears the ring's curve)


def is_cyan(p):
    return p[1] > 180 and p[2] > 180 and p[0] < 120


def ring_box(im):
    """Bounding box of the cyan ring (above the wordmark's cyan stripe)."""
    w, h = im.size
    px = im.load()
    pts = [(x, y) for y in range(0, round(h * 0.58), 2) for x in range(0, w, 2)
           if is_cyan(px[x, y])]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def ring_thickness(im, box):
    px = im.load()
    x, y = box[0], (box[1] + box[3]) // 2
    t = 0
    while is_cyan(px[x + t, y]) or t < 2:
        t += 1
    return t


def main():
    im = Image.open(ART).convert('RGB')
    x0, y0, x1, y1 = ring_box(im)
    t = ring_thickness(im, (x0, y0, x1, y1))
    ox0, oy0 = x0 - GLOW_MARGIN, y0 - GLOW_MARGIN
    ox1, oy1 = x1 + GLOW_MARGIN, y1 + GLOW_MARGIN

    # Glow behind the logo: each row interpolated between the colours just
    # left and right of the ring, then blurred so it joins smoothly.
    fill = im.copy()
    src = im.load()
    dst = fill.load()
    # Row and column interpolations, weighted toward the nearer edge, so
    # the glow's gradient carries through in both directions.
    for y in range(oy0, oy1 + 1):
        a, b = src[ox0 - 3, y], src[ox1 + 3, y]
        fy = (y - oy0) / (oy1 - oy0)
        for x in range(ox0, ox1 + 1):
            fx = (x - ox0) / (ox1 - ox0)
            c, d = src[x, oy0 - 3], src[x, oy1 + 3]
            row = [a[i] + (b[i] - a[i]) * fx for i in range(3)]
            col = [c[i] + (d[i] - c[i]) * fy for i in range(3)]
            wx = min(fx, 1 - fx)  # distance to the left/right edges
            wy = min(fy, 1 - fy)
            w_row = wy / (wx + wy) if wx + wy else 0.5
            dst[x, y] = tuple(
                round(row[i] * w_row + col[i] * (1 - w_row)) for i in range(3))
    region = (ox0 - 20, oy0 - 20, ox1 + 20, oy1 + 20)
    blurred = fill.crop(region).filter(ImageFilter.GaussianBlur(14))
    soft = fill.copy()
    soft.paste(blurred, region[:2])
    box_mask = Image.new('L', im.size, 0)
    ImageDraw.Draw(box_mask).rectangle([ox0, oy0, ox1, oy1], fill=255)
    box_mask = box_mask.filter(ImageFilter.GaussianBlur(6))
    out = Image.composite(soft, im, box_mask)

    # Lay the bright logo pixels back, inside the ring only.
    inner = Image.new('L', im.size, 0)
    m = t + INNER_MARGIN
    ImageDraw.Draw(inner).rounded_rectangle(
        [x0 + m, y0 + m, x1 - m, y1 - m], radius=CORNER, fill=255)
    alpha = Image.new('L', im.size, 0)
    ap = alpha.load()
    ip = inner.load()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if ip[x, y]:
                v = max(src[x, y])
                ap[x, y] = max(0, min(255, round((v - 35) * 255 / 50)))
    out = Image.composite(im, out, alpha)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.save(OUT, optimize=True)
    for name, scale in [('LaunchImage.png', 1 / 3),
                        ('LaunchImage@2x.png', 2 / 3),
                        ('LaunchImage@3x.png', 1)]:
        size = (round(out.width * scale), round(out.height * scale))
        out.resize(size, Image.LANCZOS).save(
            os.path.join(LAUNCH, name), optimize=True)
    for density, scale in ANDROID_DENSITIES:
        folder = os.path.join(ANDROID_RES, f'drawable-{density}')
        os.makedirs(folder, exist_ok=True)
        size = (round(out.width * scale), round(out.height * scale))
        out.resize(size, Image.LANCZOS).save(
            os.path.join(folder, 'launch_image.png'), optimize=True)
    print(f'ring {x0},{y0}-{x1},{y1} thickness {t}; wrote {OUT}')


if __name__ == '__main__':
    main()
