# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Generate the La Quinta Cove demo dataset from real terrain.

Demo mode's second site (`-demoSite cove`, the default since 2026-11-06):
a base node on a tripod at the Cove Oasis trailhead parking, La Quinta, CA,
at the foot of the Santa Rosa Mountains. Three sessions:

  1. a drive through the Cove's street grid and out behind the east ridge,
     mobile node on the dashboard with its stock stubby (the "live" one);
  2. the same drive two hours earlier with a 5.8 dBi whip on the roof
     (rig comparison, Field Report comparison);
  3. a walk up the wash into the canyon south of the trailhead.

Routes follow OpenStreetMap streets and trails. Every packet's signal comes
from a link budget over the real ground profile: log-distance path loss,
Deygout knife-edge diffraction over the 3DEP terrain between the two
antennas, location-tied shadowing, per-packet fading, a car or body loss,
and the MEDIUM_FAST decode limit (SNR -12.5 dB). A ping needs the uplink and
the base's reply both to get through (up to three tries, like want_ack); a
base beacon (device telemetry every 60 s) needs only the downlink; beacons
not heard become `telemetry_miss` rows like the app writes.

Inputs are downloaded once into a cache folder (about 3 MB, kept out of
the repo): a USGS 3DEP clip (elevation.nationalmap.gov, public domain) and
an OpenStreetMap extract from Overpass (ODbL; only coordinates of the
routes end up in the output). Outputs (committed):

  lib/demo/cove_data.dart     packet rows of the three sessions + base
  lib/demo/cove_terrain.dart  30 m elevation grid for demo terrain

    python3 tool/demo_site/gen_cove.py --cache /path/to/cache [--preview out.ppm]

Needs numpy. Deterministic for a given cache (fixed seeds).
"""

import argparse
import base64
import heapq
import json
import math
import os
import struct
import subprocess
import sys
import urllib.parse
import urllib.request

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

# Area of the DEM / OSM downloads (lon/lat box).
WEST, SOUTH, EAST, NORTH = -116.335, 33.625, -116.260, 33.685
DEM_W, DEM_H = 750, 600  # 0.0001 deg pixels, ~10 m

# Base node: tripod at the Cove Oasis trailhead parking (public lot at the
# south end of Calle Tecate). 3 m mast.
BASE = (33.64905, -116.31130)
BASE_MAST_M = 3.0

# --- Radio -----------------------------------------------------------------
FREQ_MHZ = 906.875           # US, MEDIUM_FAST default slot
LAMBDA = 299.792458 / FREQ_MHZ
TX_DBM = 22.0                # T1000-E maximum
BASE_GAIN = 5.8              # fiberglass collinear
BASE_CABLE_DB = 0.65 + 0.4   # 3 m LMR-240 + 2 connectors
NOISE_DBM = -174 + 10 * math.log10(250e3) + 6.0  # 250 kHz, NF 6 dB
SNR_FLOOR = -12.5            # SF9 demodulation limit
PING_EVERY = 15
BEACON_EVERY = 60

# Path loss: free space to 100 m, then exponent 3.6 (low antennas over
# suburban desert ground), plus clutter (houses, walls, palms) growing with
# distance past 300 m, up to 12 dB.
PL_D0 = 100.0
PL_N = 3.6
CLUTTER_DB_PER_M = 0.004
CLUTTER_MAX_DB = 12.0

# LoRa SNR reports saturate around +10..+13 dB close in.
SNR_CEILING = 12.0

# Mobile setups: (antenna gain dBi, extra loss dB, antenna height m).
# The extra loss includes the small tracker's antenna efficiency.
STUBBY_CAR = (2.0, 13.0, 1.3)   # stock stubby on the dashboard
WHIP_ROOF = (5.8, 6.0, 1.7)     # 5.8 dBi whip, magnet mount on the roof
STUBBY_HAND = (2.0, 13.0, 1.3)  # in hand, body in the way half the time


# --- Inputs ------------------------------------------------------------------
def fetch(cache):
    os.makedirs(cache, exist_ok=True)
    dem = os.path.join(cache, 'dem.tif')
    if not os.path.exists(dem):
        q = urllib.parse.urlencode({
            'bbox': f'{WEST},{SOUTH},{EAST},{NORTH}', 'bboxSR': 4326,
            'imageSR': 4326, 'size': f'{DEM_W},{DEM_H}', 'format': 'tiff',
            'pixelType': 'F32',
            'interpolation': 'RSP_BilinearInterpolation', 'f': 'image'})
        url = ('https://elevation.nationalmap.gov/arcgis/rest/services/'
               '3DEPElevation/ImageServer/exportImage?' + q)
        urllib.request.urlretrieve(url, dem)
    bil = os.path.join(cache, 'dem.bil')
    if not os.path.exists(bil):
        subprocess.check_call(['gdal_translate', '-q', '-of', 'ENVI', dem, bil])
    osm = os.path.join(cache, 'osm.json')
    if not os.path.exists(osm):
        b = f'{SOUTH},{WEST},{NORTH},{EAST}'
        query = (f'[out:json][timeout:60];(way["highway"]({b}););out geom;')
        req = urllib.request.Request(
            'https://overpass-api.de/api/interpreter',
            data=urllib.parse.urlencode({'data': query}).encode(),
            headers={'User-Agent': 'meshurement-demo-tool'})
        with urllib.request.urlopen(req, timeout=120) as r, open(osm, 'wb') as f:
            f.write(r.read())
    z = np.fromfile(bil, dtype='<f4').reshape(DEM_H, DEM_W).astype(np.float64)
    return z, json.load(open(osm))


class Dem:
    def __init__(self, z):
        self.z = z

    def at(self, lat, lon):
        x = (lon - WEST) / 1e-4 - 0.5
        y = (NORTH - lat) / 1e-4 - 0.5
        x = min(max(x, 0), DEM_W - 1.001)
        y = min(max(y, 0), DEM_H - 1.001)
        i, j = int(y), int(x)
        fy, fx = y - i, x - j
        z = self.z
        return ((z[i, j] * (1 - fx) + z[i, j + 1] * fx) * (1 - fy)
                + (z[i + 1, j] * (1 - fx) + z[i + 1, j + 1] * fx) * fy)


M_LAT = 111132.0
M_LON = 111320.0 * math.cos(math.radians(BASE[0]))


def en(lat, lon):
    return ((lon - BASE[1]) * M_LON, (lat - BASE[0]) * M_LAT)


def dist(a, b):
    return math.hypot((a[1] - b[1]) * M_LON, (a[0] - b[0]) * M_LAT)


# --- Routing -----------------------------------------------------------------
CAR = {'secondary', 'tertiary', 'residential', 'unclassified',
       'secondary_link', 'tertiary_link'}
FOOT = {'path', 'footway', 'track', 'service', 'residential', 'tertiary'}


def graph(osm, classes):
    g = {}
    for e in osm['elements']:
        t = e.get('tags', {})
        geo = e.get('geometry')
        if not geo or t.get('highway') not in classes:
            continue
        if t.get('access') in ('private', 'no'):
            continue
        pts = [(round(p['lat'], 7), round(p['lon'], 7)) for p in geo]
        for a, b in zip(pts, pts[1:]):
            d = dist(a, b)
            g.setdefault(a, []).append((b, d, t['highway']))
            g.setdefault(b, []).append((a, d, t['highway']))
    return g


def nearest(g, p):
    return min(g, key=lambda q: dist(p, q))


def shortest(g, a, b):
    best = {a: 0.0}
    prev = {}
    heap = [(0.0, a)]
    while heap:
        d, u = heapq.heappop(heap)
        if u == b:
            break
        if d > best[u]:
            continue
        for v, w, _ in g[u]:
            nd = d + w
            if nd < best.get(v, 1e18):
                best[v] = nd
                prev[v] = u
                heapq.heappush(heap, (nd, v))
    path = [b]
    while path[-1] != a:
        path.append(prev[path[-1]])
    return path[::-1]


def reachable(g, a):
    seen = {a}
    todo = [a]
    while todo:
        for v, _, _ in g[todo.pop()]:
            if v not in seen:
                seen.add(v)
                todo.append(v)
    return seen


def route(g, waypoints):
    first = nearest(g, waypoints[0])
    part = reachable(g, first)
    nodes = [first] + [min(part, key=lambda q: dist(w, q))
                       for w in waypoints[1:]]
    out = [nodes[0]]
    for a, b in zip(nodes, nodes[1:]):
        out += shortest(g, a, b)[1:]
    return out


def densify(path, step):
    """Points every `step` metres along the polyline."""
    out = [path[0]]
    for a, b in zip(path, path[1:]):
        d = dist(a, b)
        n = max(1, int(d / step))
        for k in range(1, n + 1):
            f = k / n
            out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
    return out


def timed_drive(path, rng):
    """(t, lat, lon) every second for a car: ~25 mph, slower into turns,
    a few seconds at stop signs."""
    pts = densify(path, 2.0)
    out = []
    t = 0.0
    nxt = 0.0
    for i in range(1, len(pts)):
        a, b = pts[i - 1], pts[i]
        turn = 0.0
        if i + 5 < len(pts) and i >= 5:
            h1 = math.atan2((pts[i][1] - pts[i - 5][1]) * M_LON,
                            (pts[i][0] - pts[i - 5][0]) * M_LAT)
            h2 = math.atan2((pts[i + 5][1] - pts[i][1]) * M_LON,
                            (pts[i + 5][0] - pts[i][0]) * M_LAT)
            turn = abs((h2 - h1 + math.pi) % (2 * math.pi) - math.pi)
        v = 11.0 if turn < 0.4 else 4.0
        if turn > 1.0 and rng.random() < 0.6:
            t += rng.uniform(2, 6)   # stop sign
        t += dist(a, b) / v
        while nxt <= t:
            out.append((nxt, b[0], b[1]))
            nxt += 1.0
    return out


def timed_walk(path, dem, pause_at_end=90):
    """Out along `path` and back, Tobler's hiking speed, a pause at the
    turnaround."""
    pts = densify(path, 2.0)
    legs = pts + [pts[-1]] * 0 + pts[::-1]
    out = []
    t = 0.0
    nxt = 0.0
    turn_i = len(pts)
    for i in range(1, len(legs)):
        a, b = legs[i - 1], legs[i]
        if i == turn_i:
            t += pause_at_end
        d = dist(a, b)
        s = (dem.at(*b) - dem.at(*a)) / max(d, 0.1)
        v = 6 * math.exp(-3.5 * abs(s + 0.05)) / 3.6 * 0.9
        t += d / max(v, 0.3)
        while nxt <= t:
            out.append((nxt, b[0], b[1]))
            nxt += 1.0
    return out


# --- Propagation -------------------------------------------------------------
def knife(v):
    if v <= -0.78:
        return 0.0
    return 6.9 + 20 * math.log10(math.sqrt((v - 0.1) ** 2 + 1) + v - 0.1)


def profile(dem, a, b, ha, hb, step=15.0):
    d = dist(a, b)
    n = max(2, int(d / step))
    xs = np.linspace(0, d, n + 1)
    lat = np.linspace(a[0], b[0], n + 1)
    lon = np.linspace(a[1], b[1], n + 1)
    z = np.array([dem.at(la, lo) for la, lo in zip(lat, lon)])
    # 4/3 earth bulge
    z = z + xs * (d - xs) / (2 * 8.5e6)
    z[0] += ha
    z[-1] += hb
    return xs, z


def deygout(xs, z, lo, hi, depth=0):
    """Loss over the terrain between indices lo and hi (Deygout, 3 edges)."""
    if hi - lo < 2 or depth > 2:
        return 0.0
    d = xs[hi] - xs[lo]
    best, bi = -9.0, None
    for i in range(lo + 1, hi):
        d1 = xs[i] - xs[lo]
        d2 = xs[hi] - xs[i]
        los = z[lo] + (z[hi] - z[lo]) * d1 / d
        h = z[i] - los
        v = h * math.sqrt(2 * d / (LAMBDA * d1 * d2))
        if v > best:
            best, bi = v, i
    if bi is None or best <= -0.78:
        return 0.0
    loss = knife(best)
    if depth < 2:
        loss += 0.6 * (deygout(xs, z, lo, bi, depth + 1)
                       + deygout(xs, z, bi, hi, depth + 1))
    return loss


class Shadow:
    """Location-tied shadowing: value noise on a 45 m grid, sigma ~3.5 dB.
    Both drives see the same field, so laps agree where they should."""

    def __init__(self, seed):
        r = np.random.default_rng(seed)
        self.g = r.normal(0, 3.5, (400, 400))

    def at(self, lat, lon):
        e, n = en(lat, lon)
        x = e / 45 + 200
        y = n / 45 + 200
        i, j = int(math.floor(y)), int(math.floor(x))
        fy, fx = y - i, x - j
        g = self.g
        return ((g[i, j] * (1 - fx) + g[i, j + 1] * fx) * (1 - fy)
                + (g[i + 1, j] * (1 - fx) + g[i + 1, j + 1] * fx) * fy)


class Link:
    def __init__(self, dem, shadow):
        self.dem = dem
        self.shadow = shadow
        self.cache = {}

    def mean_prx(self, lat, lon, setup):
        """Mean received power at the mobile (dBm), and the terrain loss."""
        gain, extra, h = setup
        key = (round(lat, 5), round(lon, 5), h)
        if key not in self.cache:
            d = max(dist(BASE, (lat, lon)), 5.0)
            xs, z = profile(self.dem, BASE, (lat, lon), BASE_MAST_M, h)
            diff = deygout(xs, z, 0, len(xs) - 1)
            fspl0 = 20 * math.log10(4 * math.pi * PL_D0 / LAMBDA)
            if d <= PL_D0:
                pl = 20 * math.log10(4 * math.pi * d / LAMBDA)
            else:
                pl = fspl0 + 10 * PL_N * math.log10(d / PL_D0)
            pl += min(CLUTTER_MAX_DB, max(0.0, d - 300) * CLUTTER_DB_PER_M)
            self.cache[key] = (pl, diff, d)
        pl, diff, d = self.cache[key]
        prx = (TX_DBM + BASE_GAIN - BASE_CABLE_DB + gain - extra
               - pl - min(diff, 60) - self.shadow.at(lat, lon))
        return prx, diff, d


def decodes(snr, rng):
    p = 1 / (1 + math.exp(-(snr - (SNR_FLOOR + 1.0)) / 0.9))
    return rng.random() < p


def reading(prx, rng, noise_rise):
    n = NOISE_DBM + noise_rise
    s = prx + rng.normal(0, 2.2)          # per-packet fading
    snr = s - n + rng.normal(0, 0.6)
    rssi = 10 * math.log10(10 ** (s / 10) + 10 ** (n / 10))
    # Soft ceiling: reports flatten out near SNR_CEILING.
    snr = SNR_CEILING - math.log1p(math.exp(SNR_CEILING - snr)) \
        + rng.normal(0, 0.4)
    snr = round(min(max(snr, -21.5), SNR_CEILING + 1) * 4) / 4
    return s, snr, int(round(max(rssi, -126)))


# --- Session -----------------------------------------------------------------
def simulate(track, setup, link, dem, rng, accuracy, ping_offset=7,
             beacon_offset=13):
    """Packet rows for one session: dicts in the DemoRow column order."""
    rows = []
    pos = {int(t): (la, lo) for t, la, lo in track}
    end = int(track[-1][0])

    def at(t):
        t = min(max(int(t), 0), end)
        return pos[t]

    def alt(la, lo):
        return round(dem.at(la, lo) + 1.2 + rng.normal(0, 1.5), 1)

    def acc():
        return round(max(2.0, rng.normal(*accuracy)), 1)

    def row(t, la, lo, snr, rssi, type_, direction, from_base, status=None,
            rtt=None, with_signal=True):
        rows.append(dict(t=int(t), lat=la, lon=lo, alt=alt(la, lo),
                         acc=acc(), snr=snr if with_signal else None,
                         rssi=rssi if with_signal else None, type=type_,
                         dir=direction, base=from_base, status=status,
                         rtt=rtt))

    def link_at(t):
        la, lo = at(t)
        # Noise rises a little in town (more electronics, other LoRa).
        town = 1.0 if dist(BASE, (la, lo)) > 600 else 0.0
        prx, diff, d = link.mean_prx(la, lo, setup)
        return la, lo, prx, town + rng.normal(0, 0.5)

    la, lo, prx, nr = link_at(0)
    s, snr, rssi = reading(prx, rng, nr)
    row(0, la, lo, snr, rssi, 'nodeinfo', 'rx', True)

    t = beacon_offset
    while t <= end:
        la, lo, prx, nr = link_at(t)
        s, snr, rssi = reading(prx, rng, nr)
        if decodes(snr, rng):
            row(t, la, lo, snr, rssi, 'range_test', 'rx', True)
        else:
            row(t, la, lo, None, None, 'miss', 'rx', True, with_signal=False)
        t += BEACON_EVERY

    t = ping_offset
    while t <= end - 5:
        la, lo, prx, nr = link_at(t)
        status, rtt, ack = 'timeout', None, None
        clock = 0.0
        for attempt in range(3):
            clock += rng.uniform(1.4, 2.2) if attempt == 0 else rng.uniform(5.5, 9.0)
            ta = t + clock
            if ta > end:
                break
            la2, lo2, prx2, nr2 = link_at(ta)
            up_s, up_snr, _ = reading(prx2, rng, rng.normal(0, 0.5))
            if not decodes(up_snr, rng):
                continue
            clock += rng.uniform(1.6, 3.2)
            tb = t + clock
            la3, lo3, prx3, nr3 = link_at(tb)
            s, snr, rssi = reading(prx3, rng, nr3)
            if not decodes(snr, rng):
                continue
            status, rtt = 'received', int(clock * 1000)
            ack = (tb, la3, lo3, snr, rssi)
            break
        row(t, la, lo, None, None, 'ping', 'tx', False, status, rtt,
            with_signal=False)
        if ack:
            tb, la3, lo3, snr, rssi = ack
            row(round(tb), la3, lo3, snr, rssi, 'ack', 'ack', True)
        t += PING_EVERY

    # Occasional position broadcasts from the base, heard or not.
    for t in range(170, end, 290):
        la, lo, prx, nr = link_at(t)
        s, snr, rssi = reading(prx, rng, nr)
        if decodes(snr, rng):
            row(t, la, lo, snr, rssi, 'position', 'rx', True)

    rows.sort(key=lambda r: (r['t'], r['dir'] != 'tx'))
    return rows


# --- Output ------------------------------------------------------------------
HEADER = """// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

// GENERATED by tool/demo_site/gen_cove.py - do not edit by hand.
"""


def dart_rows(name, rows, doc):
    def f(v, nd):
        return 'null' if v is None else f'{v:.{nd}f}'

    def s(v):
        return 'null' if v is None else f"'{v}'"
    out = [f'/// {doc}', f'const {name} = <DemoRow>[']
    for r in rows:
        out.append(
            f"  DemoRow({r['t']}, {r['lat']:.7f}, {r['lon']:.7f}, "
            f"{f(r['alt'], 1)}, {f(r['acc'], 1)}, {f(r['snr'], 2)}, "
            f"{'null' if r['rssi'] is None else r['rssi']}, 0, "
            f"'{r['type']}', '{r['dir']}', {'true' if r['base'] else 'false'}, "
            f"{s(r['status'])}, {'null' if r['rtt'] is None else r['rtt']}),")
    out.append('];')
    return '\n'.join(out)


def write_data(sessions, profile_target):
    parts = [HEADER, """// La Quinta Cove demo site: synthetic readings computed from real terrain
// (USGS 3DEP) along real streets and trails (OpenStreetMap contributors,
// ODbL). Base: tripod at the Cove Oasis trailhead parking. See the
// generator's docstring for the model.

import 'demo_walk.dart';

const coveBaseLat = %.6f;
const coveBaseLon = %.6f;

/// A point behind the east ridge for the `-demoScreen profile` screenshot.
const coveProfileLat = %.6f;
const coveProfileLon = %.6f;
""" % (BASE[0], BASE[1], profile_target[0], profile_target[1])]
    for name, rows, doc in sessions:
        parts.append(dart_rows(name, rows, doc))
        parts.append('')
    path = os.path.join(ROOT, 'lib', 'demo', 'cove_data.dart')
    open(path, 'w').write('\n'.join(parts))
    return path


def write_terrain(dem):
    # 30 m grid (every third DEM pixel), metres x 4 as little-endian int16.
    step = 3
    sub = dem.z[1::step, 1::step]
    h, w = sub.shape
    q = np.clip(np.round(sub * 4), -32768, 32767).astype('<i2')
    b64 = base64.b64encode(q.tobytes()).decode()
    lines = [b64[i:i + 76] for i in range(0, len(b64), 76)]
    north = NORTH - 1.5 * 1e-4
    west = WEST + 1.5 * 1e-4
    body = HEADER + f"""
// Ground elevation around the La Quinta Cove demo site, from USGS 3DEP
// (public domain), resampled to 0.0003 deg (~30 m). Row 0 is the north
// edge; values are metres x 4, little-endian int16, base64.

const coveTerrainNorth = {north:.6f};
const coveTerrainWest = {west:.6f};
const coveTerrainStepDeg = {step * 1e-4:.4f};
const coveTerrainRows = {h};
const coveTerrainCols = {w};

const coveTerrainB64 =
""" + '\n'.join(f"    '{ln}'" for ln in lines) + ';\n'
    path = os.path.join(ROOT, 'lib', 'demo', 'cove_terrain.dart')
    open(path, 'w').write(body)
    return path


def summary(name, rows, link, setup):
    pings = [r for r in rows if r['dir'] == 'tx']
    ok = [r for r in pings if r['status'] == 'received']
    beacons = [r for r in rows if r['type'] in ('range_test', 'miss')]
    heard = [r for r in beacons if r['type'] == 'range_test']
    snrs = [r['snr'] for r in rows if r['snr'] is not None]
    far = max(dist(BASE, (r['lat'], r['lon'])) for r in rows)
    print(f'{name}: {rows[-1]["t"] // 60} min, pings {len(ok)}/{len(pings)}, '
          f'beacons {len(heard)}/{len(beacons)}, SNR '
          f'{min(snrs):.1f}..{max(snrs):.1f} (median {np.median(snrs):.1f}), '
          f'farthest {far:.0f} m')


def preview(path, dem, sessions):
    z = dem.z
    gy, gx = np.gradient(z, 11.1, 9.25)
    hs = np.clip(0.7 - 0.6 * (gx - gy) / np.hypot(gx, gy).clip(0.05) * np.tanh(np.hypot(gx, gy)), 0, 1)
    img = np.stack([hs * 200 + 30] * 3, -1)
    def put(la, lo, col, r=1):
        i = int((NORTH - la) / 1e-4)
        j = int((lo - WEST) / 1e-4)
        img[max(i - r, 0):i + r + 1, max(j - r, 0):j + r + 1] = col
    for _, rows, _ in sessions:
        for r in rows:
            if r['dir'] == 'tx':
                put(r['lat'], r['lon'], [255, 0, 255] if r['status'] != 'received' else [0, 0, 0], 1)
            elif r['snr'] is not None:
                m = r['snr'] - SNR_FLOOR
                col = [0, 200, 0] if m > 15 else [230, 210, 0] if m > 8 else [255, 140, 0] if m > 3 else [220, 0, 0]
                put(r['lat'], r['lon'], col, 2)
    put(*BASE, [0, 120, 255], 4)
    with open(path, 'wb') as f:
        f.write(b'P6 %d %d 255\n' % (DEM_W, DEM_H))
        f.write(np.clip(img, 0, 255).astype(np.uint8).tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cache', required=True,
                    help='folder for the DEM and OSM downloads')
    ap.add_argument('--preview', help='write a PPM preview of the readings')
    args = ap.parse_args()
    z, osm = fetch(args.cache)
    dem = Dem(z)
    shadow = Shadow(5)
    link = Link(dem, shadow)

    car = graph(osm, CAR)
    foot = graph(osm, FOOT)
    drive_path = route(car, [
        (33.64905, -116.31050),   # Calle Tecate at the trailhead
        (33.6600, -116.3100),     # north up the Cove
        (33.6781, -116.3045),     # Avenida Bermudas at Calle Tampico
        (33.6782, -116.2862),     # east on Calle Tampico to Park Ave
        (33.6730, -116.2780),     # Avenue 52 east
        (33.6600, -116.2700),     # Jefferson St south, behind the ridge
        (33.6730, -116.3036),     # Avenue 52 back west
        (33.6660, -116.3080),     # Eisenhower south
        (33.6544, -116.3120),     # Calle Madrid
        (33.64905, -116.31050),   # back to the trailhead
    ])
    # Across the open fan from the parking to the Bear Creek footway, then
    # up the canyon.
    walk_path = [(33.64870, -116.31160)] + route(foot, [
        (33.6455, -116.3167),
        (33.6400, -116.3200),     # into the canyon mouth
    ])

    rng = np.random.default_rng(42)
    drive = timed_drive(drive_path, rng)
    walk = timed_walk(walk_path, dem)

    r1 = simulate(drive, STUBBY_CAR, link, dem, np.random.default_rng(1),
                  (4.5, 1.0))
    r2 = simulate(drive, WHIP_ROOF, link, dem, np.random.default_rng(2),
                  (4.5, 1.0), ping_offset=4, beacon_offset=31)
    r3 = simulate(walk, STUBBY_HAND, link, dem, np.random.default_rng(3),
                  (4.0, 1.2), ping_offset=9, beacon_offset=20)
    summary('drive stubby', r1, link, STUBBY_CAR)
    summary('drive whip', r2, link, WHIP_ROOF)
    summary('walk', r3, link, STUBBY_HAND)

    # Profile target: the drive point 2.5-4 km out (behind the east ridge)
    # with the most terrain loss.
    cands = []
    for t, la, lo in drive[::10]:
        d = dist(BASE, (la, lo))
        if 2500 < d < 4000:
            _, diff, _ = link.mean_prx(la, lo, STUBBY_CAR)
            cands.append((diff, la, lo))
    _, pla, plo = max(cands)

    sessions = [
        ('coveDriveStubby', r1, 'Drive through the Cove, stock stubby on '
         'the dashboard (the live session).'),
        ('coveDriveWhip', r2, 'The same drive two hours earlier, 5.8 dBi '
         'whip on the roof.'),
        ('coveCanyonWalk', r3, 'Walk up the wash into the canyon south of '
         'the trailhead and back.'),
    ]
    print(write_data(sessions, (pla, plo)))
    print(write_terrain(dem))
    if args.preview:
        preview(args.preview, dem, sessions)


if __name__ == '__main__':
    sys.exit(main())
