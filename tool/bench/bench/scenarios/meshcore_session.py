# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Scenario 12b: a short recorded session on the MeshCore pair.

Needs the pair set up (radio-setup-meshcore) and the app connected to the
mobile. On MeshCore the base beacon is "pulled": the mobile traces the base
on the beacon interval (`beacon_kind = 'trace'`), and a ping is the same
trace, so every answer carries a downlink SNR and the base's uplink SNR
(`packet_events.uplink_snr`). `SessionManager.startSession` throws
`SessionProbeOffError` when both the beacon and pings are off, so the
scenario puts the trace beacon in the prefs when Radio Setup left it off
and asks for pings too.

Checks: the session starts with the MeshCore protocol and the trace beacon,
a few trace outcomes arrive, at least one is `received` with both SNRs,
none is `implicit`/`throttled` (MeshCore never reports those), the DB holds
uplink SNRs, and the session ends cleanly.

Options: pings (3, outcomes to wait for), interval (10 s, ping and beacon),
lat / lon (the bench's pretend position), timeout (seconds, default
pings × interval × 3 + 60). Skips when the connected radio isn't MeshCore
or the roles aren't set.
"""

from __future__ import annotations

import time

from ..app import Event
from . import Context, Skip

Check = tuple[str, bool, str]


def check_outcomes(pings: list[dict], wanted: int) -> list[Check]:
    """What the trace outcomes of a MeshCore session must look like."""
    out: list[Check] = []
    statuses = [p.get("status") for p in pings]
    out.append((f"at least {wanted} link checks answered or timed out", len(pings) >= wanted,
                f"{len(pings)}: {statuses}"))
    received = [p for p in pings if p.get("status") == "received"]
    out.append(("at least one link check came back 'received'", len(received) >= 1, str(statuses)))
    out.append(("every received check has a downlink SNR and RSSI",
                bool(received) and all(p.get("snr") is not None and p.get("rssi") is not None for p in received),
                str([(p.get("snr"), p.get("rssi")) for p in received])))
    out.append(("every received check has the base's uplink SNR",
                bool(received) and all(p.get("uplinkSnr") is not None for p in received),
                str([p.get("uplinkSnr") for p in received])))
    out.append(("received checks are from the base, no hops",
                bool(received) and all(p.get("fromBase") and (p.get("hops") or 0) == 0 for p in received),
                str([(p.get("fromBase"), p.get("hops")) for p in received])))
    odd = [s for s in statuses if s in ("implicit", "throttled")]
    out.append(("no implicit or throttled outcomes (MeshCore never reports them)", not odd, str(odd)))
    return out


def check_session_row(row: dict | None, *, preset: str | None, interval: int) -> list[Check]:
    out: list[Check] = []
    if row is None:
        return [("session row exists", False, "no row")]
    out.append(("session protocol is meshcore", row.get("protocol") == "meshcore", str(row.get("protocol"))))
    out.append(("session beacon kind is trace", row.get("beacon_kind") == "trace", str(row.get("beacon_kind"))))
    out.append((f"session beacon interval is {interval} s", row.get("beacon_interval_sec") == interval,
                str(row.get("beacon_interval_sec"))))
    out.append(("session stores the ping interval", (row.get("ping_interval_sec") or 0) >= interval,
                str(row.get("ping_interval_sec"))))
    if preset:
        out.append(("session stores the mobile's modulation", row.get("lora_preset") == preset,
                    f"{row.get('lora_preset')} vs {preset}"))
    out.append(("session ended", row.get("ended_at") is not None, str(row.get("ended_at"))))
    return out


def run(ctx: Context) -> None:
    app, log = ctx.app, ctx.log
    wanted = int(ctx.options.get("pings", 3))
    interval = int(ctx.options.get("interval", 10))
    lat = float(ctx.options.get("lat", 33.6800))
    lon = float(ctx.options.get("lon", -116.2400))
    timeout = float(ctx.options.get("timeout", wanted * interval * 3 + 60))

    st = app.state()
    radio, roles = st["radio"], st["roles"]
    if not (radio["ready"] and radio["protocol"] == "meshcore"):
        raise Skip("the app is not connected to a MeshCore radio (run radio-setup-meshcore first)")
    if roles.get("base") is None or roles.get("mobile") is None:
        raise Skip("Radio Setup roles not set (run radio-setup-meshcore first)")
    if radio["nodeId"] != roles["mobile"]:
        raise Skip("the connected radio is not the mobile; connect it first")

    # The trace beacon: Radio Setup records it; a run with beacon_secs=0
    # or an older setup leaves it off, and then pings alone must carry it.
    if app.cmd("prefs.get", key="base_beacon_kind") != "trace" \
            or (app.cmd("prefs.get", key="base_beacon_interval_sec") or 0) <= 0:
        log(f"no trace beacon recorded; setting one every {interval} s")
        app.cmd("prefs.set", key="base_beacon_kind", value="trace")
        app.cmd("prefs.set", key="base_beacon_interval_sec", value=interval)
    ctx.check("radio is not on a public setting", radio["onPublicChannel"] is False, str(radio["onPublicChannel"]))

    map_id = app.cmd("map.create", name="Bench MeshCore", baseLat=lat, baseLon=lon, baseNodeId=roles["base"])
    app.cmd("gps.set", lat=lat + 0.0005, lon=lon, alt=100)
    app.drain()
    log(f"starting a session on map {map_id}: pings every {interval} s")
    session_id = app.cmd("session.start", timeout=60, mapId=map_id, pingIntervalSec=interval, name="bench meshcore")
    ctx.check("session started", isinstance(session_id, int), str(session_id))

    log(f"waiting for {wanted} link checks (≤ {timeout:.0f} s)")
    pings: list[Event] = []
    end = time.time() + timeout
    while len(pings) < wanted and time.time() < end:
        try:
            pings.append(app.wait_event("ping", timeout=max(1.0, end - time.time())))
        except TimeoutError:
            break
    data = [p.data for p in pings]
    for name, ok, detail in check_outcomes(data, wanted):
        ctx.check(name, ok, detail)

    uplinks = app.count(f"select count(*) from packet_events where session_id = {session_id} "
                        "and uplink_snr is not null")
    ctx.check("DB has packet events with an uplink SNR", uplinks >= 1, str(uplinks))
    trace_rows = app.count(f"select count(*) from packet_events where session_id = {session_id} "
                           "and source_kind not in ('telemetry_miss', 'log_only')")
    ctx.check("DB has sample rows for the session", trace_rows >= 1, str(trace_rows))

    log("ending the session")
    app.cmd("session.end", timeout=60)
    rows = app.query(f"select protocol, beacon_kind, beacon_interval_sec, ping_interval_sec, lora_preset, "
                     f"ended_at from sessions where id = {session_id}")
    for name, ok, detail in check_session_row(rows[0] if rows else None,
                                              preset=roles.get("mobilePreset"), interval=interval):
        ctx.check(name, ok, detail)
