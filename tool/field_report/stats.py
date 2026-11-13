# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Field Report numbers for one session, from a copy of the app database.

Prototype for docs/design/field-report.md: the same rules the card would
use in the app, so the mock shows real numbers. Prints JSON with only
relative positions (metres from the base, rotated and trimmed), never
coordinates.

    python3 tool/field_report/stats.py phone.sqlite 30 > report.json
    python3 tool/field_report/stats.py phone.sqlite 32 --base-map 11

--base-map measures from another map's base location (for a session filed
on the wrong map: its track is far from its own map's base).
"""

import json
import math
import random
import sqlite3
import statistics
import sys

PRESETS = {  # id: (display name, spreading factor)
    'SHORT_TURBO': ('Short Turbo', 7), 'SHORT_FAST': ('Short Fast', 7),
    'SHORT_SLOW': ('Short Slow', 8), 'MEDIUM_FAST': ('Medium Fast', 9),
    'MEDIUM_SLOW': ('Medium Slow', 10), 'LONG_TURBO': ('Long Turbo', 11),
    'LONG_FAST': ('Long Fast', 11), 'LONG_MODERATE': ('Long Moderate', 11),
    'LONG_SLOW': ('Long Slow', 12),
}
NOT_SAMPLES = ('telemetry_miss', 'log_only')
HIDE_NEAR_BASE_M = 120   # privacy: nothing drawn this close to the base
BUCKETS = [('Strong', 20), ('Good', 10), ('Weak', 0), ('Below limit', None)]


def snr_floor(sf):
    return -7.5 - 2.5 * (sf - 7)


def metres(lat0, lon0, lat, lon):
    k = 111_320.0
    return ((lon - lon0) * k * math.cos(math.radians(lat0)), (lat - lat0) * k)


def main(db_path, session_id, base_map=None):
    db = sqlite3.connect(db_path)
    db.row_factory = sqlite3.Row
    s = db.execute('select * from sessions where id=?', (session_id,)).fetchone()
    m = db.execute('select * from coverage_maps where id=?',
                   (base_map or s['coverage_map_id'],)).fetchone()
    name, sf = PRESETS.get(s['lora_preset'], (s['lora_preset'], 11))
    floor = snr_floor(sf)
    base = (m['base_lat'], m['base_lon'])

    events = db.execute(
        'select * from packet_events where session_id=? order by timestamp',
        (session_id,)).fetchall()
    fixes = [e for e in events if e['rx_lat'] is not None
             and e['source_kind'] != 'telemetry_miss']
    route = 0.0
    for a, b in zip(fixes, fixes[1:]):
        dx, dy = metres(a['rx_lat'], a['rx_lon'], b['rx_lat'], b['rx_lon'])
        d = math.hypot(dx, dy)
        if d >= 3:
            route += d

    samples = [e for e in events if e['direction'] != 'tx'
               and e['rx_lat'] is not None and e['rx_snr'] is not None
               and e['source_kind'] not in NOT_SAMPLES]
    margins = [e['rx_snr'] - floor for e in samples]
    snrs = [e['rx_snr'] for e in samples]
    rssis = [e['rx_rssi'] for e in samples if e['rx_rssi'] is not None]

    def dist_from_base(e):
        return math.hypot(*metres(*base, e['rx_lat'], e['rx_lon']))

    pings = db.execute(
        '''select c.ack_status, t.rx_lat, t.rx_lon from ping_correlations c
           join packet_events t on t.id=c.tx_event_id
           where t.session_id=?''', (session_id,)).fetchall()
    on_air = [p for p in pings if not p['ack_status'].startswith('error')
              and p['ack_status'] != 'throttled']
    answered = [p for p in on_air if p['ack_status'] in ('received', 'implicit')]
    farthest = max((dist_from_base(e) for e in samples), default=0)
    beacons = [e for e in events if e['source_kind'] in ('telemetry', 'range_test')]
    misses = [e for e in events if e['source_kind'] == 'telemetry_miss']

    buckets = []
    for i, (label, lo) in enumerate(BUCKETS):
        hi = BUCKETS[i - 1][1] if i else None
        n = sum(1 for x in margins
                if (lo is None or x >= lo) and (hi is None or x < hi))
        buckets.append({'label': label, 'from': lo, 'to': hi,
                        'pct': round(100 * n / len(margins)) if margins else 0})

    # Margin over time, 12 bins.
    t0, t1 = samples[0]['timestamp'], samples[-1]['timestamp']
    bins = []
    for i in range(12):
        a = t0 + (t1 - t0) * i / 12
        b = t0 + (t1 - t0) * (i + 1) / 12
        xs = [x for e, x in zip(samples, margins) if a <= e['timestamp'] <= b]
        bins.append(round(statistics.median(xs), 1) if xs else None)

    # Route for the card: metres from the base, rotated by a random angle so
    # the street layout can't be matched, points near the base dropped.
    rot = random.Random(session_id).uniform(0, 2 * math.pi)
    pts = []
    for e, x in zip(samples, margins):
        dx, dy = metres(*base, e['rx_lat'], e['rx_lon'])
        if math.hypot(dx, dy) < HIDE_NEAR_BASE_M:
            continue
        rx = dx * math.cos(rot) - dy * math.sin(rot)
        ry = dx * math.sin(rot) + dy * math.cos(rot)
        pts.append([round(rx), round(ry), round(x, 1)])

    track = []
    for e in fixes:
        dx, dy = metres(*base, e['rx_lat'], e['rx_lon'])
        if math.hypot(dx, dy) < HIDE_NEAR_BASE_M:
            track.append(None)  # a gap in the drawn line
            continue
        track.append([round(dx * math.cos(rot) - dy * math.sin(rot)),
                      round(dx * math.sin(rot) + dy * math.cos(rot))])

    rig = lambda j: json.loads(j) if j else {}
    out = {
        'session': s['name'], 'started': s['started_at'],
        'duration_min': round((s['ended_at'] - s['started_at']) / 60),
        'preset': name, 'sf': sf, 'snr_floor_db': floor,
        'route_m': round(route), 'farthest_m': round(farthest),
        'samples': len(samples),
        'median_margin_db': round(statistics.median(margins), 1),
        'median_snr_db': round(statistics.median(snrs), 1),
        'snr_range_db': [min(snrs), max(snrs)],
        'rssi_range_dbm': [min(rssis), max(rssis)] if rssis else None,
        'pings_on_air': len(on_air), 'pings_answered': len(answered),
        'beacons_heard': len(beacons), 'beacons_missed': len(misses),
        'buckets': buckets, 'margin_over_time': bins,
        'air_tx_pct': s['radio_air_util_tx'],
        'channel_util_pct': s['radio_channel_util'],
        'mobile_rig': rig(s['mobile_rig_json']), 'base_rig': rig(s['base_rig_json']),
        'tx_power_dbm': s['tx_power_dbm'], 'region': s['region'],
        'frequency_mhz': s['frequency_mhz'],
        'route_pts': pts, 'track': track, 'hidden_near_base_m': HIDE_NEAR_BASE_M,
    }
    json.dump(out, sys.stdout, indent=1)


if __name__ == '__main__':
    bm = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[3] == '--base-map' else None
    main(sys.argv[1], int(sys.argv[2]), bm)
