# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Render the Field Report mock (1080 x 1350) from stats.py's JSON as HTML.

    python3 tool/field_report/render.py report.json > card.html
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless \
        --window-size=1080,1350 --screenshot=card.png card.html
"""

import datetime
import html
import json
import sys

GREEN, YELLOW, RED = (0x27, 0xAE, 0x60), (0xF1, 0xC4, 0x0F), (0xC0, 0x39, 0x2B)


def ramp(margin):  # SignalColorMapper.fromMargin: 0 red, 10 yellow, 20+ green
    t = max(0.0, min(1.0, margin / 20))
    a, b, u = (RED, YELLOW, t * 2) if t <= 0.5 else (YELLOW, GREEN, (t - 0.5) * 2)
    return '#%02x%02x%02x' % tuple(round(a[i] + (b[i] - a[i]) * u) for i in range(3))


def miles(m):
    return f'{m / 1609.344:.1f} mi'


def route_svg(d, w=620, h=470, pad=36):
    pts = [p for p in d['track'] if p] + [p[:2] for p in d['route_pts']] + [[0, 0]]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    span = max(max(xs) - min(xs), max(ys) - min(ys), 1)
    k = min((w - 2 * pad) / (max(xs) - min(xs) or 1), (h - 2 * pad) / (max(ys) - min(ys) or 1))
    ox = pad + ((w - 2 * pad) - (max(xs) - min(xs)) * k) / 2
    oy = pad + ((h - 2 * pad) - (max(ys) - min(ys)) * k) / 2
    X = lambda x: ox + (x - min(xs)) * k
    Y = lambda y: h - (oy + (y - min(ys)) * k)
    segs, cur = [], []
    for p in d['track']:
        if p is None:
            if len(cur) > 1:
                segs.append(cur)
            cur = []
        else:
            cur.append(p)
    if len(cur) > 1:
        segs.append(cur)
    out = [f'<svg viewBox="0 0 {w} {h}" width="{w}" height="{h}">']
    # faint grid, no streets
    for i in range(0, w, 40):
        out.append(f'<line x1="{i}" y1="0" x2="{i}" y2="{h}" class="grid"/>')
    for i in range(0, h, 40):
        out.append(f'<line x1="0" y1="{i}" x2="{w}" y2="{i}" class="grid"/>')
    r = d['hidden_near_base_m'] * k
    out.append(f'<circle cx="{X(0):.0f}" cy="{Y(0):.0f}" r="{r:.0f}" class="haze"/>')
    out.append(f'<text x="{X(0):.0f}" y="{Y(0) + 5:.0f}" class="hazelabel">BASE</text>')
    for s in segs:
        path = ' '.join(f'{X(p[0]):.1f},{Y(p[1]):.1f}' for p in s)
        out.append(f'<polyline points="{path}" class="track"/>')
    for x, y, m in d['route_pts']:
        out.append(f'<circle cx="{X(x):.1f}" cy="{Y(y):.1f}" r="9" fill="{ramp(m)}" class="dot"/>')
    bar = 100 * k  # 100 m
    bx, by = w - pad - bar, h - 22
    out.append(f'<line x1="{bx:.0f}" y1="{by}" x2="{bx + bar:.0f}" y2="{by}" class="scale"/>')
    out.append(f'<text x="{bx + bar / 2:.0f}" y="{by - 8}" class="scaletext">100 m</text>')
    out.append('</svg>')
    return '\n'.join(out)


def chart_svg(bins, w=980, h=190, pad=34, right=70):
    vals = [b for b in bins]
    n = len(vals)
    X = lambda i: pad + i * (w - pad - right) / (n - 1)
    Y = lambda v: h - pad - (max(-5, min(30, v)) + 5) / 35 * (h - 2 * pad)
    out = [f'<svg viewBox="0 0 {w} {h}" width="{w}" height="{h}">']
    for v, lab in ((20, 'Strong'), (10, 'Good'), (0, 'Limit')):
        out.append(f'<line x1="{pad}" y1="{Y(v):.0f}" x2="{w - right}" y2="{Y(v):.0f}" class="gridline"/>')
        out.append(f'<text x="{w - right + 10}" y="{Y(v) + 4:.0f}" class="axis">{lab}</text>')
    pts = [(X(i), Y(v), v) for i, v in enumerate(vals) if v is not None]
    for (x1, y1, _), (x2, y2, _) in zip(pts, pts[1:]):
        out.append(f'<line x1="{x1:.0f}" y1="{y1:.0f}" x2="{x2:.0f}" y2="{y2:.0f}" class="series"/>')
    for x, y, v in pts:
        out.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="7" fill="{ramp(v)}" class="dot"/>')
    out.append(f'<text x="{pad}" y="{h - 6}" class="axis">Start</text>')
    out.append(f'<text x="{w - right}" y="{h - 6}" class="axis" text-anchor="end">End</text>')
    out.append('</svg>')
    return '\n'.join(out)


def main(path):
    d = json.load(open(path))
    started = datetime.datetime.fromtimestamp(d['started'])
    dur = d['duration_min']
    delivery = (round(100 * d['pings_answered'] / d['pings_on_air'])
                if d['pings_on_air'] else None)
    heard = d['beacons_heard'] + d['pings_answered']
    sent = d['beacons_heard'] + d['beacons_missed'] + d['pings_on_air']
    heard_pct = round(100 * heard / sent) if sent else None
    colors = [ramp(25), ramp(15), ramp(5), ramp(-1)]  # same ramp as the dots
    rows = ''.join(
        f'<tr><td><span class="sw" style="background:{c}"></span>{b["label"]}</td>'
        f'<td class="rng">{rng}</td><td class="pct">{b["pct"]}%</td></tr>'
        for b, c, rng in zip(d['buckets'], colors,
                             ['20+ dB', '10 to 20 dB', '0 to 10 dB', 'under 0 dB']))
    mob, base = d['mobile_rig'], d['base_rig']
    html_out = f'''<!doctype html><html><head><meta charset="utf-8"><style>
:root {{ --bg:#070d1c; --panel:#0c1630; --line:#1f3a5c; --cyan:#2bd9e6; --orange:#ff7a1f;
  --ink:#eef3fa; --soft:#9db0c8; }}
* {{ box-sizing:border-box; margin:0; }}
body {{ width:1080px; height:1350px; background:radial-gradient(120% 80% at 50% 0%, #10204a 0%, var(--bg) 60%);
  color:var(--ink); font-family:'Avenir Next', 'Helvetica Neue', sans-serif; padding:44px 50px; }}
.head {{ display:flex; justify-content:space-between; align-items:flex-end; }}
.title {{ display:flex; align-items:center; gap:18px; }}
.slash {{ width:22px; height:74px; background:var(--orange); transform:skewX(-18deg); }}
h1 {{ font-size:64px; font-weight:800; font-style:italic; letter-spacing:-1px; line-height:1; }}
.kicker {{ font:600 16px Menlo, monospace; letter-spacing:6px; color:var(--soft); margin-top:6px; }}
.meta {{ text-align:right; font-size:20px; color:var(--soft); line-height:1.45; }}
.meta b {{ color:var(--ink); font-weight:700; }}
.hero {{ margin-top:30px; display:flex; gap:22px; }}
.panel {{ background:rgba(12,22,48,.85); border:2px solid var(--line); border-radius:22px; }}
.map {{ width:620px; height:470px; overflow:hidden; }}
.side {{ flex:1; display:flex; flex-direction:column; gap:22px; }}
.brag {{ padding:24px 26px; border-color:var(--cyan); box-shadow:0 0 28px rgba(43,217,230,.25); }}
.brag .big {{ font:800 68px Menlo, monospace; color:var(--cyan); line-height:1; }}
.brag .lab {{ font-size:21px; color:var(--soft); margin-top:8px; }}
.margins {{ padding:20px 24px; flex:1; }}
.margins h2, .chart h2 {{ font-size:22px; font-weight:700; }}
.margins p {{ font-size:15px; color:var(--soft); margin:2px 0 10px; }}
table {{ width:100%; border-collapse:collapse; font-size:19px; }}
td {{ padding:7px 0; border-top:1px solid var(--line); }}
.sw {{ display:inline-block; width:16px; height:16px; border-radius:50%; margin-right:10px; vertical-align:-2px; }}
.rng {{ color:var(--soft); font-size:15px; }}
.pct {{ text-align:right; font:700 21px Menlo, monospace; }}
.stats {{ margin-top:22px; display:grid; grid-template-columns:repeat(5,1fr); padding:20px 10px; }}
.stat {{ text-align:center; border-left:1px solid var(--line); }}
.stat:first-child {{ border-left:0; }}
.stat .v {{ font:800 34px Menlo, monospace; }}
.stat .l {{ font:600 13px Menlo, monospace; letter-spacing:2px; color:var(--soft); margin-top:6px; }}
.chart {{ margin-top:22px; padding:18px 24px 6px; }}
.setup {{ margin-top:22px; display:flex; gap:22px; }}
.setup .panel {{ flex:1; padding:16px 22px; font-size:18px; }}
.setup h3 {{ font-size:15px; letter-spacing:3px; color:var(--orange); font-family:Menlo, monospace; margin-bottom:6px; }}
.setup .row {{ display:flex; justify-content:space-between; padding:3px 0; color:var(--soft); }}
.setup .row b {{ color:var(--ink); }}
.foot {{ position:absolute; left:50px; right:50px; bottom:34px; display:flex; justify-content:space-between; align-items:center;
  border-top:2px solid var(--line); padding-top:18px; }}
.brand {{ font-size:38px; font-weight:800; font-style:italic; }}
.brand span {{ color:var(--orange); }}
.lines {{ height:4px; width:250px; background:var(--cyan); box-shadow:0 8px 0 #6a5cff, 0 16px 0 #ff3fd0; margin-top:4px; }}
.url {{ font-size:24px; color:var(--cyan); }}
svg .grid {{ stroke:#12264a; stroke-width:1; }}
svg .track {{ fill:none; stroke:#3d5a86; stroke-width:4; stroke-linejoin:round; }}
svg .dot {{ stroke:#071022; stroke-width:2.5; }}
svg .haze {{ fill:rgba(255,122,31,.12); stroke:rgba(255,122,31,.55); stroke-width:2; stroke-dasharray:6 6; }}
svg .hazelabel {{ fill:#ff9a55; font:700 14px Menlo, monospace; text-anchor:middle; letter-spacing:2px; }}
svg .scale {{ stroke:var(--soft); stroke-width:3; }}
svg .scaletext {{ fill:var(--soft); font:14px Menlo, monospace; text-anchor:middle; }}
svg .gridline {{ stroke:#1f3a5c; stroke-dasharray:4 6; }}
svg .series {{ stroke:var(--cyan); stroke-width:3; }}
svg .axis {{ fill:var(--soft); font:13px Menlo, monospace; }}
</style></head><body>
<div class="head"><div class="title"><div class="slash"></div><div><h1>Field Report</h1>
<div class="kicker">LORA COVERAGE SESSION</div></div></div>
<div class="meta"><b>{html.escape(d["session"])}</b><br>{started:%b %-d, %Y} · {d["preset"]}</div></div>
<div class="hero"><div class="panel map">{route_svg(d)}</div><div class="side">
<div class="panel brag"><div class="big">{miles(d["farthest_m"])}</div><div class="lab">farthest point the base was heard</div></div>
<div class="panel margins"><h2>Signal margin</h2><p>How far above the {d["preset"]} limit</p><table>{rows}</table></div>
</div></div>
<div class="panel stats">
<div class="stat"><div class="v">{miles(d["route_m"])}</div><div class="l">ROUTE</div></div>
<div class="stat"><div class="v">{dur // 60}h {dur % 60:02d}m</div><div class="l">TIME</div></div>
<div class="stat"><div class="v">{d["samples"]}</div><div class="l">READINGS</div></div>
<div class="stat"><div class="v">{d["median_margin_db"]:+.0f} dB</div><div class="l">MEDIAN MARGIN</div></div>
<div class="stat"><div class="v">{heard_pct}%</div><div class="l">BASE HEARD</div></div></div>
<div class="panel chart"><h2>Margin over the session</h2>{chart_svg(d["margin_over_time"])}</div>
<div class="setup">
<div class="panel"><h3>BASE</h3><div class="row">Radio<b>{html.escape(base.get("radioModel", ""))}</b></div>
<div class="row">Antenna<b>{html.escape(base.get("antennaName") or "stock")}</b></div></div>
<div class="panel"><h3>MOBILE</h3><div class="row">Radio<b>{html.escape(mob.get("radioModel", ""))}</b></div>
<div class="row">Antenna<b>{html.escape(mob.get("antennaName") or "stock")}</b></div></div>
<div class="panel"><h3>RANGE SETTING</h3><div class="row">Preset<b>{d["preset"]}</b></div>
<div class="row">Limit<b>{d["snr_floor_db"]:+.1f} dB SNR</b></div></div></div>
<div class="foot"><div><div class="brand">Mesh<span>urement</span></div><div class="lines"></div></div>
<div class="url">meshurement.com</div></div>
</body></html>'''
    sys.stdout.write(html_out)


if __name__ == '__main__':
    main(sys.argv[1])
