#!/usr/bin/env python3
# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

"""Writes a tiny synthetic raster PMTiles (stdlib only, no GDAL) to test the
app's PMTiles path without real data.

  python3 tool/tiles/make_sample.py OUT.pmtiles [--kind terrain|streets]
      [--bbox W,S,E,N] [--minzoom 10] [--maxzoom 13]

terrain: transparent PNGs with a dark diagonal "ridge" pattern (looks like
an overlay); streets: opaque PNGs with a grid and the tile id drawn as a
checker so you can see tiles come from the file. Not real map data.
"""

import argparse
import gzip
import math
import struct
import zlib


def png(width, height, rgba_rows):
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))
    raw = b"".join(b"\x00" + row for row in rgba_rows)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def tile_png(kind, z, x, y, size=256):
    rows = []
    for py in range(size):
        row = bytearray()
        for px in range(size):
            # World pixel position, so the pattern continues across tiles.
            wx = (x * size + px) / 2 ** z
            wy = (y * size + py) / 2 ** z
            if kind == "terrain":
                v = math.sin(wx * 600) * math.cos(wy * 450)
                a = int(max(0.0, v) * 140)
                row += bytes((20, 25, 40, a))
            else:
                grid = px % 64 == 0 or py % 64 == 0
                check = ((px // 32) + (py // 32) + z) % 2 == 0
                c = (200, 190, 175) if grid else ((236, 232, 224) if check else (244, 242, 238))
                row += bytes((*c, 255))
        rows.append(bytes(row))
    return png(size, size, rows)


def zxy_to_tileid(z, x, y):
    acc = ((1 << (2 * z)) - 1) // 3
    n = 1 << z
    d = 0
    s = n >> 1
    while s > 0:
        rx = 1 if x & s else 0
        ry = 1 if y & s else 0
        d += s * s * ((3 * rx) ^ ry)
        if ry == 0:
            if rx == 1:
                x = s - 1 - x
                y = s - 1 - y
            x, y = y, x
        s >>= 1
    return acc + d


def varint(v):
    out = bytearray()
    while v >= 0x80:
        out.append((v & 0x7F) | 0x80)
        v >>= 7
    out.append(v)
    return bytes(out)


def lon2x(lon, z):
    return int((lon + 180) / 360 * 2 ** z)


def lat2y(lat, z):
    r = math.radians(lat)
    return int((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * 2 ** z)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--kind", default="terrain", choices=["terrain", "streets"])
    ap.add_argument("--bbox", default="-116.60,33.55,-116.05,33.95")
    ap.add_argument("--minzoom", type=int, default=10)
    ap.add_argument("--maxzoom", type=int, default=13)
    a = ap.parse_args()
    w, s, e, n = map(float, a.bbox.split(","))

    tiles = {}
    for z in range(a.minzoom, a.maxzoom + 1):
        for x in range(lon2x(w, z), lon2x(e, z) + 1):
            for y in range(lat2y(n, z), lat2y(s, z) + 1):
                tiles[zxy_to_tileid(z, x, y)] = tile_png(a.kind, z, x, y)
    ids = sorted(tiles)
    data = bytearray()
    offsets = []
    for i in ids:
        offsets.append(len(data))
        data += tiles[i]
    d = bytearray(varint(len(ids)))
    last = 0
    for i in ids:
        d += varint(i - last)
        last = i
    for _ in ids:
        d += varint(1)
    for i in ids:
        d += varint(len(tiles[i]))
    for off in offsets:
        d += varint(off + 1)
    root = gzip.compress(bytes(d), 9)  # gzip, like `pmtiles`
    meta = gzip.compress(b'{"name":"sample","attribution":"synthetic"}', 9)
    hdr = bytearray(b"PMTiles") + bytes([3])
    o_root = 127
    o_meta = o_root + len(root)
    o_leaf = o_meta + len(meta)
    o_data = o_leaf
    hdr += struct.pack("<QQQQQQQQ", o_root, len(root), o_meta, len(meta),
                       o_leaf, 0, o_data, len(data))
    hdr += struct.pack("<QQQ", len(ids), len(ids), len(ids))
    hdr += bytes([1, 2, 1, 2, a.minzoom, a.maxzoom])  # clustered, gzip dirs, raw tiles, png
    hdr += struct.pack("<iiii", int(w * 1e7), int(s * 1e7), int(e * 1e7), int(n * 1e7))
    hdr += bytes([a.minzoom + 2])
    hdr += struct.pack("<ii", int((w + e) / 2 * 1e7), int((s + n) / 2 * 1e7))
    assert len(hdr) == 127
    with open(a.out, "wb") as f:
        f.write(hdr + root + meta + data)
    print(f"{a.out}: {len(ids)} tiles z{a.minzoom}-{a.maxzoom}, "
          f"{(127 + len(root) + len(meta) + len(data)) / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
