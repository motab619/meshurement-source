# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Scenario `smoke`: the bench server end to end, no radios needed.

Made for T1 (the iOS simulator with `-MeshBench -MeshDemo`: the demo's
pretend radio on the MeshTest channel and the demo database), but it also
runs on a phone whose radio is connected and set up. Checks /state, a map,
a scripted GPS fix, a recorded session start/end through `SessionManager`
(the same refusals the UI gets: public channel, no base, radio not ready),
database counts, the session events, the prefs round trip and that
`db.query` refuses writes.

Options: base=<node num> (default: the BASE node in the nodes table),
lat/lon (default: the Cove demo site's base).
"""

from __future__ import annotations

import json
import time

from ..app import BenchCommandError
from . import Context


def run(ctx: Context) -> None:
    app, log = ctx.app, ctx.log

    st = app.state()
    ctx.check("/state: bench mode on", st["app"].get("bench") is True, json.dumps(st["app"]))
    demo = st["app"].get("demo")
    log(f"  {st['app'].get('name')} on {st['app'].get('platform')} "
        f"{st['app'].get('osVersion')}, demo {demo}")
    radio = st["radio"]
    ctx.check("radio ready", radio.get("ready") is True, json.dumps(radio))
    ctx.check("radio off the public channel", radio.get("onPublicChannel") is False,
              json.dumps(radio))
    if demo:
        ctx.check("demo session attached at launch", st["session"] is not None,
                  json.dumps(st["session"]))
    ctx.check("cmd ping", app.cmd("ping") == "pong")

    # The base node: the demo seeds "BASE"; on a phone Radio Setup set it.
    base = ctx.options.get("base")
    if base is None:
        base = st["roles"].get("base")
    if base is None:
        rows = app.query("SELECT node_id FROM nodes WHERE short_name = 'BASE' ORDER BY id LIMIT 1")
        base = rows[0]["node_id"] if rows else None
    base = int(base) if base is not None else None
    if not ctx.check("a base node to record against", base is not None,
                     "no roles.base and no BASE node in the nodes table"):
        return
    ctx.check("base node is not the radio in hand", base != radio.get("nodeId"),
              f"{base} == {radio.get('nodeId')}")

    lat = float(ctx.options.get("lat", 33.6416))
    lon = float(ctx.options.get("lon", -116.3101))

    maps_before = app.count("SELECT count(*) FROM coverage_maps")
    map_id = app.cmd("map.create", name="Bench smoke", baseLat=lat, baseLon=lon, baseNodeId=base)
    ctx.check("map.create returns an id", isinstance(map_id, int) and map_id > 0, str(map_id))
    ctx.check("coverage_maps grew by one",
              app.count("SELECT count(*) FROM coverage_maps") == maps_before + 1)

    app.cmd("gps.set", lat=lat + 0.001, lon=lon, alt=12)
    gps = app.state().get("gps") or {}
    ctx.check("gps.set shows in /state as a fix",
              gps.get("status") == "fix" and gps.get("lat") is not None
              and abs(gps["lat"] - (lat + 0.001)) < 1e-6, json.dumps(gps))

    sessions_before = app.count("SELECT count(*) FROM sessions")
    try:
        sid = app.cmd("session.start", timeout=60, mapId=map_id, baseNodeId=base,
                      name="bench smoke", pingIntervalSec=0)
    except BenchCommandError as e:
        # A refusal is itself the finding (public channel, no base, GPS off...).
        ctx.check("session.start accepted", False, str(e))
        return
    ctx.check("session.start returns an id", isinstance(sid, int) and sid > 0, str(sid))
    st = app.state()
    ctx.check("/state shows the session active on the new map",
              bool(st["session"]) and st["session"]["id"] == sid
              and st["session"]["mapId"] == map_id, json.dumps(st["session"]))
    ctx.check("sessions grew by one",
              app.count("SELECT count(*) FROM sessions") == sessions_before + 1)
    row = app.query(f"SELECT is_active, coverage_map_id FROM sessions WHERE id = {sid}")
    ctx.check("session row active on the map",
              bool(row) and bool(row[0]["is_active"]) and row[0]["coverage_map_id"] == map_id,
              json.dumps(row))
    time.sleep(1)
    app.drain()
    ctx.check("session event seen",
              any(e.type == "session" and e.data.get("id") == sid and e.data.get("active")
                  for e in app.events),
              str([str(e) for e in app.events if e.type == "session"]))

    app.cmd("session.end")
    st = app.state()
    ctx.check("/state: no session after end", st["session"] is None, json.dumps(st["session"]))
    row = app.query(f"SELECT is_active, ended_at FROM sessions WHERE id = {sid}")
    ctx.check("session row ended",
              bool(row) and not row[0]["is_active"] and row[0]["ended_at"] is not None,
              json.dumps(row))
    app.drain()
    ctx.check("session ended event seen",
              any(e.type == "session" and e.data.get("active") is False for e in app.events))

    key, val = "bench_smoke_v1", f"smoke-{int(time.time())}"
    app.cmd("prefs.set", key=key, value=val)
    ctx.check("prefs.set / prefs.get round trip", app.cmd("prefs.get", key=key) == val)
    app.cmd("prefs.set", key=key, value=None)
    ctx.check("prefs.set null removes the key", app.cmd("prefs.get", key=key) is None)

    try:
        app.query(f"DELETE FROM sessions WHERE id = {sid}")
        ctx.check("db.query refuses non-SELECT", False, "DELETE went through")
    except BenchCommandError as e:
        ctx.check("db.query refuses non-SELECT", "SELECT only" in str(e), str(e))
