# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Scenario 10 (data half): exports.

`export.session` renders the session CSV (v2) on the phone and returns the
text; `export.mapsJson` the `maps.json` of the "export everything" zip for
one map. Checks: the CSV header holds every v2 column (radio settings,
beacon columns, `uplink_snr` last), one row per `packet_events` row of the
session (misses included), `ping_status` counts equal to
`ping_correlations`, the Meshtastic range-test CSV and GeoJSON render,
`maps.json` lists the map's sessions with the DB's preset / protocol /
region and `event_count` = heard events (no `telemetry_miss`, no
`log_only`).

Uses the newest ended session on the phone; with none it records a short
one first (two ping outcomes) so the scenario stands alone after
radio-setup. The Field Report PNG (the other half of §5.10) is not here.

Options: session (a session id to export instead of the newest),
ping_secs (10) for the fallback session, lat/lon.

Needs radio-setup (only for the fallback session). Nothing here has run on
hardware yet (written 2026-11-08).
"""

from __future__ import annotations

import csv
import io
import json

from ..app import BenchCommandError
from . import Context
from .common import (
    MARGIN_SEC, REPLY_TIMEOUT_SEC, create_map, end_session, seq, start_session, wait_pings,
)

needs = ("radio-setup",)

#: `csvV2Columns` (lib/services/export/csv_v2.dart), the ones the bench
#: insists on; the full header is compared for order of these.
REQUIRED_COLUMNS = (
    "event_id", "session_id", "map_id", "timestamp_utc", "timestamp_local", "unix_ms",
    "direction", "packet_type", "mesh_packet_id", "source_node_id", "source_node_num",
    "rx_lat", "rx_lon", "rx_snr", "rx_rssi", "hop_count", "ping_status", "round_trip_ms",
    "lora_preset", "ping_interval_sec", "protocol", "seq", "source_kind", "base_channel_util",
    "beacon_kind", "beacon_interval_sec", "session_distance_m", "session_region",
    "session_frequency_slot", "session_frequency_mhz", "session_tx_power_dbm",
    "session_hop_limit", "uplink_snr",
)
NOT_SAMPLES = "('telemetry_miss', 'log_only')"


def check_csv(ctx: Context, text: str, counts: dict[str, int], label: str = "csv") -> None:
    """Header and row checks for one session's CSV v2; `counts` has
    `events`, `pings` and `timeout`/`received` from the DB."""
    rows = list(csv.reader(io.StringIO(text)))
    if not ctx.check(f"{label}: has a header and rows", len(rows) >= 1, f"{len(rows)} lines"):
        return
    header = rows[0]
    missing = [c for c in REQUIRED_COLUMNS if c not in header]
    ctx.check(f"{label}: every v2 column present", not missing, f"missing {missing}")
    ctx.check(f"{label}: uplink_snr is the last column", header and header[-1] == "uplink_snr",
              str(header[-3:]))
    ctx.check(f"{label}: columns in v2 order",
              [c for c in header if c in REQUIRED_COLUMNS] == [c for c in REQUIRED_COLUMNS if c in header])
    body = rows[1:]
    ctx.check(f"{label}: one row per packet event (misses included)",
              len(body) == counts["events"], f"{len(body)} rows vs {counts['events']} events")
    if "ping_status" in header and body:
        i = header.index("ping_status")
        statuses = [r[i] for r in body if len(r) > i and r[i]]
        ctx.check(f"{label}: ping_status rows match ping_correlations",
                  len(statuses) == counts["pings"], f"{len(statuses)} vs {counts['pings']}")
        for st in ("timeout", "received"):
            if st in counts:
                ctx.check(f"{label}: {st} count matches the DB",
                          statuses.count(st) == counts[st],
                          f"{statuses.count(st)} vs {counts[st]}")
    if "session_id" in header and body:
        i = header.index("session_id")
        ctx.check(f"{label}: every row is this session",
                  len({r[i] for r in body}) == 1, str({r[i] for r in body}))


def check_maps_json(ctx: Context, text: str, map_id: int, sessions: list[dict],
                    heard: dict[int, int]) -> None:
    """`maps.json` against the DB: `sessions` are the map's session rows,
    `heard` the heard-event count per session id."""
    try:
        j = json.loads(text)
    except json.JSONDecodeError as e:
        ctx.check("maps.json parses", False, str(e))
        return
    maps = j.get("maps", [])
    if not ctx.check("maps.json has the one map", len(maps) == 1 and maps[0].get("id") == map_id,
                     str([m.get("id") for m in maps])):
        return
    m = maps[0]
    got = {s["id"]: s for s in m.get("sessions", [])}
    ctx.check("maps.json lists every session of the map",
              set(got) == {s["id"] for s in sessions}, f"{sorted(got)} vs {sorted(s['id'] for s in sessions)}")
    for s in sessions:
        g = got.get(s["id"])
        if g is None:
            continue
        ctx.check(f"session {s['id']}: preset/protocol/region as in the DB",
                  (g.get("lora_preset"), g.get("protocol"), g.get("region"))
                  == (s["lora_preset"], s["protocol"], s.get("region")),
                  f"{g.get('lora_preset'), g.get('protocol'), g.get('region')} vs "
                  f"{s['lora_preset'], s['protocol'], s.get('region')}")
        ctx.check(f"session {s['id']}: event_count = heard events",
                  g.get("event_count") == heard.get(s["id"]),
                  f"{g.get('event_count')} vs {heard.get(s['id'])}")
        ctx.check(f"session {s['id']}: beacon kind/interval exported",
                  g.get("beacon_kind") == s["beacon_kind"]
                  and g.get("beacon_interval_sec") == s["beacon_interval_sec"])
    ctx.check("maps.json carries the base location",
              m.get("base_lat") is not None and m.get("base_lon") is not None)


def _pick_session(ctx: Context) -> dict | None:
    app = ctx.app
    want = ctx.options.get("session")
    if want is not None:
        rows = app.query(f"select * from sessions where id = {int(want)}")
        return rows[0] if rows else None
    rows = app.query("select * from sessions where ended_at is not null "
                     "order by id desc limit 1")
    return rows[0] if rows else None


def run(ctx: Context) -> None:
    app, log = ctx.app, ctx.log
    if app.state()["session"] is not None:
        end_session(ctx)
    row = _pick_session(ctx)
    if row is None:
        log("no ended session on the phone: recording a short one")
        map_id = create_map(ctx, "Bench exports")
        since = seq(app)
        try:
            row = start_session(ctx, map_id, ping_sec=int(ctx.option("ping_secs", 10)),
                                name="bench exports")
        except BenchCommandError as e:
            ctx.check("fallback session starts", False, str(e))
            return
        interval = int(row["ping_interval_sec"])
        wait_pings(app, since, 2, timeout=2 * interval + REPLY_TIMEOUT_SEC + MARGIN_SEC)
        end_session(ctx)
        row = app.query(f"select * from sessions where id = {row['id']}")[0]
    sid, map_id = int(row["id"]), int(row["coverage_map_id"])
    log(f"exporting session {sid} of map {map_id}")

    def n(sql: str) -> int:
        return app.count(sql)

    counts = {
        "events": n(f"select count(*) from packet_events where session_id = {sid}"),
        "pings": n("select count(*) from ping_correlations p join packet_events e "
                   f"on e.id = p.tx_event_id where e.session_id = {sid}"),
    }
    for st in ("timeout", "received"):
        counts[st] = n("select count(*) from ping_correlations p join packet_events e "
                       f"on e.id = p.tx_event_id where e.session_id = {sid} and p.ack_status = '{st}'")
    ctx.check("session has packet events to export", counts["events"] > 0, str(counts))

    text = app.cmd("export.session", sessionId=sid, format="csvV2", timeout=120)
    check_csv(ctx, text, counts)

    # The range-test layout lists every received sample (header only when
    # the session heard nothing, e.g. a session of pings: 2026-11-09).
    rt = app.cmd("export.session", sessionId=sid, format="meshtasticCsv", timeout=120)
    rx = n(f"select count(*) from packet_events where session_id = {sid} "
           f"and direction = 'rx' and source_kind not in {NOT_SAMPLES}")
    rt_rows = [ln for ln in (rt or "").splitlines()[1:] if ln.strip()]
    ctx.check("range-test CSV renders", bool(rt) and rt.startswith("time,from,"), (rt or "")[:80])
    ctx.check("range-test CSV: one row per received sample", len(rt_rows) == rx,
              f"{len(rt_rows)} rows vs {rx} rx samples")
    geo = app.cmd("export.session", sessionId=sid, format="geoJson", timeout=120)
    try:
        ctx.check("GeoJSON is a FeatureCollection",
                  json.loads(geo).get("type") == "FeatureCollection")
    except json.JSONDecodeError as e:
        ctx.check("GeoJSON is a FeatureCollection", False, str(e))

    sessions = app.query(f"select * from sessions where coverage_map_id = {map_id} order by id")
    heard = {
        s["id"]: n(f"select count(*) from packet_events where session_id = {s['id']} "
                   f"and source_kind not in {NOT_SAMPLES}")
        for s in sessions
    }
    text = app.cmd("export.mapsJson", mapId=map_id, timeout=120)
    check_maps_json(ctx, text, map_id, sessions, heard)
