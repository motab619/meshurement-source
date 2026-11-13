# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Scenario 4 (Phase 1): a recorded session with the serial stand-ins.

A map, a scripted position, a session with short pings; then, over the
base's USB port (`docs/design/bench-rig/README.md` §12):

  (a) base on a different key   = out of range: pings time out, beacons
                                  stop, `range` goes outOfRange after three
                                  misses + the reply timeout
  (b) MeshTest key back         = re-entry after two answers
  (c) beacon module off / on    = `beacon` absent then back (the base still
                                  answers pings)
  (d) reboot of the mobile      = radio lost: `link` drops, `range` is
                                  radioLost, the app reconnects by itself

and finally `session.end` plus DB counts: pings and their outcomes
(timeouts as `timeout`), beacon samples, `telemetry_miss` rows.

Every wait is computed from the session's own interval (the row's
`ping_interval_sec`, floored by the app) and the app's rules in
`common.py`, plus the serial write time, plus `MARGIN_SEC`.

Options: ping_secs (10; the app may floor it), n_pings (5), oor_pref (30;
the out-of-range setting written for the run, below the floor so the floor
decides), beacon_off (true), radio_lost (true), lat/lon.

Needs radio-setup. Expect ~8 to 12 minutes with a Heltec base (each base
write costs ~50 s with the reboot that brings its Bluetooth back). Nothing
here has run on hardware yet (written 2026-11-08).
"""

from __future__ import annotations

import time
from typing import Any

from ..app import BenchCommandError
from ..radios import meshtastic as mt
from . import Context, Skip
from .common import (
    ABSENT_INTERVALS, MARGIN_SEC, REPLY_TIMEOUT_SEC, base_write, create_map, end_session,
    events_after, mobile_port, other_key, out_of_range_window_sec, pings_after,
    reentry_window_sec, seq, start_session, test_psk, wait_beacon, wait_link, wait_pings,
    wait_range, wait_until,
)

needs = ("radio-setup",)

OOR_PREF_KEY = "out_of_range_timeout_sec"
BEACON_KINDS = "('telemetry', 'range_test')"


def run(ctx: Context) -> None:
    app = ctx.app
    base, mobile = ctx.cfg.radio("base"), ctx.cfg.radio("mobile")
    if base.protocol != "meshtastic" or mobile.protocol != "meshtastic":
        raise Skip("Meshtastic pair only (the serial stand-ins write Meshtastic settings)")
    if app.state()["session"] is not None:
        end_session(ctx)
    psk = test_psk(app)
    oor_pref = int(ctx.option("oor_pref", 30))
    old_pref = app.cmd("prefs.get", key=OOR_PREF_KEY)
    app.cmd("prefs.set", key=OOR_PREF_KEY, value=oor_pref)
    try:
        _run(ctx, psk, oor_pref)
    finally:
        app.cmd("prefs.set", key=OOR_PREF_KEY, value=old_pref)
        if app.state()["session"] is not None:
            end_session(ctx)


def _count(ctx: Context, where: str, sid: int) -> int:
    return ctx.app.count(
        "select count(*) from packet_events e "
        "left join ping_correlations p on p.tx_event_id = e.id "
        f"where e.session_id = {sid} and {where}")


def _missed(status: str) -> bool:
    """A ping that went on air and got no answer. Builds before 2026-11-09
    report the firmware's MAX_RETRANSMIT NAK as an error instead of a
    timeout (AckStatus.noReplyReasons in the app)."""
    return status in ("timeout", "error:MAX_RETRANSMIT")


def _base_packets(ctx: Context, sid: int, t0: float, t1: float) -> int:
    """Packets from the session's base recorded between two Mac times
    (drift stores timestamps as Unix seconds)."""
    return ctx.app.count(
        "select count(*) from packet_events e join sessions s on s.id = e.session_id "
        f"where e.session_id = {sid} and e.source_node_id = s.base_node_id "
        f"and e.direction in ('rx', 'ack') and e.timestamp between {int(t0)} and {int(t1) + 1}")


def _run(ctx: Context, psk: bytes, oor_pref: int) -> None:
    app, log = ctx.app, ctx.log
    ping_opt = int(ctx.option("ping_secs", 10))
    n_pings = int(ctx.option("n_pings", 5))

    # -- A. start, pings, beacons -----------------------------------------
    map_id = create_map(ctx, "Bench recorded")
    since0 = seq(app)
    try:
        row = start_session(ctx, map_id, ping_sec=ping_opt, name="bench recorded")
    except BenchCommandError as e:
        ctx.check("session starts", False, str(e))
        return
    sid = int(row["id"])
    interval = int(row["ping_interval_sec"])
    bkind, bsec = row["beacon_kind"], int(row["beacon_interval_sec"])
    ctx.check("session has a ping interval", interval > 0, f"{interval}s (asked {ping_opt}s)")
    ctx.check("session records preset and protocol",
              bool(row["lora_preset"]) and row["protocol"] == "meshtastic",
              f"{row['lora_preset']!r} {row['protocol']!r}")
    ctx.check("session records radio settings (region, tx power)",
              bool(row.get("region")) and row.get("tx_power_dbm") is not None,
              f"region {row.get('region')!r} tx {row.get('tx_power_dbm')}")
    ctx.check("session knows the base beacon from Radio Setup",
              bkind in ("telemetry", "rangeTest") and bsec > 0, f"{bkind!r} every {bsec}s")
    oor = out_of_range_window_sec(interval, pref_sec=oor_pref, beacon_sec=bsec)
    log(f"session {sid}: pings every {interval}s, beacon {bkind} every {bsec}s, "
        f"out-of-range window {oor}s, re-entry {reentry_window_sec(interval)}s")

    outcomes = wait_pings(app, since0, n_pings,
                          timeout=n_pings * interval + REPLY_TIMEOUT_SEC + MARGIN_SEC)
    ctx.check(f"{n_pings} pings had outcomes", len(outcomes) >= n_pings, str(outcomes))
    ctx.check("the base answered pings", "received" in outcomes, str(outcomes))
    ctx.check("base reported in range",
              wait_range(app, since0, "inRange", timeout=REPLY_TIMEOUT_SEC) is not None,
              f"range events: {[e.data['state'] for e in events_after(app, since0, 'range')]}")
    if bsec > 0:
        got = wait_until(app, lambda: _count(ctx, f"e.source_kind in {BEACON_KINDS}", sid) >= 2,
                         timeout=ABSENT_INTERVALS * bsec + MARGIN_SEC, what="beacon samples")
        ctx.check("two base beacon samples recorded", got,
                  f"{_count(ctx, f'e.source_kind in {BEACON_KINDS}', sid)} after {ABSENT_INTERVALS} intervals")
        b = app.state()["beacon"]
        ctx.check("beacon tracker is following the base", b["active"] and b["heard"] >= 1, str(b))

    # -- B. out of range: the base on another key --------------------------
    since_b = seq(app)
    write_s = base_write(ctx, "primary key -> a different key (deaf base)",
                         lambda p: mt.set_primary_psk(p, other_key(psk)))
    ev = wait_range(app, since_b, "outOfRange", timeout=oor + MARGIN_SEC)
    ctx.check(f"out of range reported (window {oor}s, write took {write_s:.0f}s)", ev is not None,
              f"pings: {pings_after(app, since_b)}")
    if ev is not None:
        before = [e.data["status"] for e in events_after(app, since_b, "ping") if e.seq < ev.seq]
        ctx.check("three pings timed out before the alert (not two)",
                  sum(_missed(s) for s in before) >= 3, str(before))
    if bkind == "telemetry":
        got = wait_until(app, lambda: _count(ctx, "e.source_kind = 'telemetry_miss'", sid) >= 1,
                         timeout=2 * bsec + MARGIN_SEC, what="telemetry_miss")
        ctx.check("telemetry_miss rows synthesized while the base is silent", got)

    # -- C. re-entry: the MeshTest key back --------------------------------
    since_c = seq(app)
    t_c = time.time()
    base_write(ctx, "primary key -> MeshTest key (base back)",
               lambda p: mt.set_primary_psk(p, psk))
    ev = wait_range(app, since_c, "inRange",
                    timeout=reentry_window_sec(interval) + interval + MARGIN_SEC)
    ctx.check("back in range after the key is restored", ev is not None,
              f"pings: {pings_after(app, since_c)}")
    if ev is not None:
        # The monitor counts every packet heard from the base (ping replies,
        # beacons, NodeInfo), not only ping answers (OutOfRangeMonitor.
        # onPacketReceived; bench 2026-11-09: one reply + one beacon).
        heard = _base_packets(ctx, sid, t_c, time.time())
        before = [e.data["status"] for e in events_after(app, since_c, "ping") if e.seq < ev.seq]
        ctx.check("re-entry took two packets from the base", heard >= 2,
                  f"{heard} base packets in the DB; pings {before}")

    # -- D. beacon off / on ------------------------------------------------
    if bsec > 0 and ctx.option("beacon_off", True):
        module = "telemetry" if bkind == "telemetry" else "range_test"
        since_d = seq(app)
        base_write(ctx, f"{module} module off (beacon stops)",
                   lambda p: mt.set_module_enabled(p, module, False))
        ev = wait_beacon(app, since_d, True,
                         timeout=(ABSENT_INTERVALS + 1) * bsec + MARGIN_SEC)
        ctx.check(f"beacon reported absent after {ABSENT_INTERVALS} silent intervals",
                  ev is not None, str(app.state()["beacon"]))
        ctx.check("pings still answered while the beacon is off",
                  "received" in pings_after(app, since_d), str(pings_after(app, since_d)))
        since_d2 = seq(app)
        base_write(ctx, f"{module} module on", lambda p: mt.set_module_enabled(p, module, True))
        ev = wait_beacon(app, since_d2, False, timeout=2 * bsec + MARGIN_SEC)
        ctx.check("beacon back once the module is on again", ev is not None,
                  str(app.state()["beacon"]))

    # -- E. radio lost: reboot the mobile ------------------------------------
    if ctx.option("radio_lost", True):
        since_e = seq(app)
        log("mobile over USB: reboot (radio lost)")
        mt.reboot(mobile_port(ctx), wait_s=0)
        dropped = wait_until(
            app, lambda: any(e.data.get("state") != "ready"
                             for e in events_after(app, since_e, "link")),
            timeout=60, what="link drop")
        ctx.check("link dropped when the mobile rebooted", dropped,
                  str([e.data.get("state") for e in events_after(app, since_e, "link")]))
        ctx.check("range state radioLost while the link is down",
                  wait_range(app, since_e, "radioLost", timeout=60) is not None,
                  str([e.data["state"] for e in events_after(app, since_e, "range")]))
        back = wait_link(app, since_e, "ready", timeout=180)
        ctx.check("app reconnected to the mobile by itself", back is not None)
        if back is not None:
            ctx.check("back in range after the radio returned",
                      wait_range(app, back.seq, "inRange",
                                 timeout=reentry_window_sec(interval) + interval + MARGIN_SEC)
                      is not None,
                      f"pings: {pings_after(app, back.seq)}")

    # -- end + database --------------------------------------------------
    log(f"range states this run: {[e.data['state'] for e in events_after(app, since0, 'range')]}")
    end_session(ctx)
    ctx.check("session ended", app.state()["session"] is None)
    rows: list[dict[str, Any]] = app.query(f"select ended_at from sessions where id = {sid}")
    ctx.check("session row has ended_at", bool(rows) and rows[0]["ended_at"] is not None)
    ping_events = len(events_after(app, since0, "ping"))
    pings = _count(ctx, "e.direction = 'tx' and e.packet_type = 'ping'", sid)
    ctx.check("every ping has a DB row", pings >= ping_events and pings >= n_pings,
              f"{pings} rows, {ping_events} events")
    # (rows from builds before the MAX_RETRANSMIT fix say error:MAX_RETRANSMIT)
    timeouts = _count(ctx, "p.ack_status in ('timeout', 'error:MAX_RETRANSMIT')", sid)
    ctx.check("timeouts recorded as such", timeouts >= 3, str(timeouts))
    received = _count(ctx, "p.ack_status = 'received'", sid)
    ctx.check("received pings recorded", received >= 3, str(received))
    if bsec > 0:
        ctx.check("beacon samples in the DB",
                  _count(ctx, f"e.source_kind in {BEACON_KINDS}", sid) >= 2)
    if bkind == "telemetry":
        ctx.check("telemetry_miss rows in the DB",
                  _count(ctx, "e.source_kind = 'telemetry_miss'", sid) >= 1)
