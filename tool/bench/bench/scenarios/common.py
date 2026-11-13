# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Shared steps for the session scenarios: the test key, a map and a
session through the bench server, waiting on events, serial writes to the
base, and the app's timing rules written out so waits are computed, not
guessed.

Timing (Meshtastic DM pings; `lib/services`):
- a ping waits `REPLY_TIMEOUT_SEC` = 30 s for its ACK
  (`ActiveProbeService.pingTimeoutSecFor`, `AppConstants.defaultAckTimeoutSec`);
- the out-of-range window is the user's setting but at least
  3 × interval + reply timeout (`SessionManager.outOfRangeTimeoutSecFor`):
  three misses, not two;
- leaving out-of-range takes `REENTRY_ANSWERS` = 2 answers inside one window
  (`OutOfRangeMonitor.reentryAnswers`);
- the beacon counts as absent after `ABSENT_INTERVALS` = 3 beacon intervals
  with the base still heard (`BeaconTracker.absentIntervals`);
- a Heltec resets when its serial port opens and keeps Bluetooth off until a
  reboot, so every base write here ends with `mt.reboot` (`HELTEC_REBOOT_SEC`).
"""

from __future__ import annotations

import base64
import time
from typing import Any, Callable

from ..app import AppLink, Event
from ..radios import meshtastic as mt
from . import Context

REPLY_TIMEOUT_SEC = 30
REENTRY_ANSWERS = 2
ABSENT_INTERVALS = 3
#: `mt.reboot`'s default wait plus the Heltec's own boot.
HELTEC_REBOOT_SEC = 30
#: `settle_s` of the serial write helpers.
SERIAL_SETTLE_SEC = 20
#: Slack on every computed wait (BLE and firmware jitter).
MARGIN_SEC = 30

#: A map where nothing is: the bench phone never moves, the position only
#: has to exist so events land on the map (La Quinta Cove trailhead).
DEFAULT_LAT, DEFAULT_LON = 33.6478, -116.3079


def out_of_range_window_sec(interval_sec: int, *, pref_sec: int = 0,
                            beacon_sec: int = 0) -> int:
    """`SessionManager.outOfRangeTimeoutSecFor`."""
    cands = [pref_sec]
    if interval_sec > 0:
        cands.append(3 * interval_sec + REPLY_TIMEOUT_SEC)
    if interval_sec == 0 and beacon_sec > 0:
        cands.append(2 * beacon_sec + 30)
    return max(cands)


def reentry_window_sec(interval_sec: int) -> int:
    """Two answers after the base is back: two pings plus one reply time."""
    return REENTRY_ANSWERS * interval_sec + REPLY_TIMEOUT_SEC


def base_write_sec(ctx: Context) -> int:
    """How long a serial write to the base keeps it off the air: the write's
    settle time, plus the reboot on a Heltec."""
    base = ctx.cfg.radio("base")
    return SERIAL_SETTLE_SEC + (HELTEC_REBOOT_SEC if mt.bluetooth_off_after_serial(base) else 0)


# -- app ---------------------------------------------------------------

def test_psk(app: AppLink) -> bytes:
    """The phone's 32-byte MeshTest key (`test_channel_psk`, base64)."""
    b64 = app.cmd("prefs.get", key="test_channel_psk")
    if not b64:
        raise RuntimeError("the phone has no test_channel_psk: run radio-setup first")
    psk = base64.b64decode(b64)
    if len(psk) != 32:
        raise RuntimeError(f"test_channel_psk is {len(psk)} bytes, not 32")
    return psk


def create_map(ctx: Context, name: str = "Bench") -> int:
    lat, lon = ctx.option("lat", DEFAULT_LAT), ctx.option("lon", DEFAULT_LON)
    map_id = ctx.app.cmd("map.create", name=name, baseLat=lat, baseLon=lon)
    # The phone "stands" 100 m north of the base.
    ctx.app.cmd("gps.set", lat=lat + 0.0009, lon=lon, alt=0)
    return int(map_id)


def start_session(ctx: Context, map_id: int, *, ping_sec: int, name: str) -> dict[str, Any]:
    """Start a session and return its row (`sessions`), whose
    `ping_interval_sec` is the floored interval actually in use.

    Needs the phone connected to the mobile (bench 2026-11-09, "Radio not
    connected"): a USB read of the T1000-E at the end of radio-setup drops
    the Bluetooth link for a few seconds, and a scenario run on its own
    starts a fresh app that does not reconnect by itself. So: wait a
    little, then connect to the mobile role's radio (`radio.reconnect`)."""
    ensure_connected(ctx)
    sid = ctx.app.cmd("session.start", mapId=map_id, pingIntervalSec=ping_sec, name=name,
                      timeout=60)
    rows = ctx.app.query(f"select * from sessions where id = {int(sid)}")
    if not rows:
        raise RuntimeError(f"session {sid} started but has no row")
    return rows[0]


def ensure_connected(ctx: Context, *, grace: float = 20) -> None:
    """The phone's link to a radio is up: waits `grace` seconds for one
    that is coming back, else connects to the mobile role's radio."""
    app = ctx.app
    if wait_until(app, lambda: bool(app.state()["radio"]["ready"]), timeout=grace,
                  what="radio link ready"):
        return
    ctx.log("phone not connected to a radio: connecting to the mobile")
    app.cmd("radio.reconnect", timeout=150, timeoutSec=120)


def end_session(ctx: Context) -> None:
    ctx.app.cmd("session.end", timeout=60)


def seq(app: AppLink) -> int:
    """Sequence number of the newest event seen (a marker for `events_after`)."""
    app.drain()
    return app.events[-1].seq if app.events else 0


def events_after(app: AppLink, since: int, type_: str) -> list[Event]:
    return [e for e in app.events if e.seq > since and e.type == type_]


def pings_after(app: AppLink, since: int) -> list[str]:
    return [e.data["status"] for e in events_after(app, since, "ping")]


def wait_until(app: AppLink, pred: Callable[[], bool], *, timeout: float,
               what: str) -> bool:
    """Poll events until `pred()` holds; False on timeout (no exception, so
    the scenario can record a failed check and carry on)."""
    end = time.time() + timeout
    while time.time() < end:
        if pred():
            return True
        try:
            app.poll_events()  # long-polls up to 20 s when idle
        except Exception:  # noqa: BLE001 - transport hiccup; keep waiting
            time.sleep(1)
    return pred()


def wait_pings(app: AppLink, since: int, n: int, *, timeout: float,
               status: str | None = None) -> list[str]:
    """Wait for `n` ping outcomes after `since` (optionally of one status);
    returns the outcomes seen, which may be fewer on timeout."""
    def have() -> list[str]:
        out = pings_after(app, since)
        return [s for s in out if status is None or s == status] if status else out
    wait_until(app, lambda: len(have()) >= n, timeout=timeout, what=f"{n} pings")
    return pings_after(app, since)


def wait_range(app: AppLink, since: int, state: str, *, timeout: float) -> Event | None:
    """The first `range` event with `state` after `since`, or None."""
    def found() -> Event | None:
        return next((e for e in events_after(app, since, "range")
                     if e.data.get("state") == state), None)
    wait_until(app, lambda: found() is not None, timeout=timeout, what=f"range {state}")
    return found()


def wait_beacon(app: AppLink, since: int, absent: bool, *, timeout: float) -> Event | None:
    def found() -> Event | None:
        return next((e for e in events_after(app, since, "beacon")
                     if e.data.get("absent") is absent), None)
    wait_until(app, lambda: found() is not None, timeout=timeout, what="beacon")
    return found()


def wait_link(app: AppLink, since: int, state: str, *, timeout: float) -> Event | None:
    def found() -> Event | None:
        return next((e for e in events_after(app, since, "link")
                     if e.data.get("state") == state), None)
    wait_until(app, lambda: found() is not None, timeout=timeout, what=f"link {state}")
    return found()


def reconnect_if_needed(ctx: Context, since: int, *, wait: float = 30) -> None:
    """After a serial write to the *mobile*: the nRF52 drops the phone's BLE
    link for a few seconds, and the app re-reads the radio's settings when it
    comes back. If no link event shows up in `wait` seconds the link held, so
    reconnect on purpose (the app only learns a channel change on connect)."""
    app = ctx.app
    if wait_until(app, lambda: bool(events_after(app, since, "link")), timeout=wait,
                  what="link drop"):
        ok = wait_link(app, since, "ready", timeout=120)
        if ok is not None:
            return
        ctx.log("link dropped but did not come back: reconnecting")
    else:
        ctx.log("link held through the serial write: reconnecting so the app re-reads the channel")
    app.cmd("radio.reconnect", timeout=150, timeoutSec=120)


# -- serial ------------------------------------------------------------

def base_write(ctx: Context, what: str, fn: Callable[[str], None], *,
               reboot: bool = True) -> float:
    """Run `fn(port)` against the base over USB and, on a Heltec, reboot it
    so its Bluetooth comes back (`reboot=False` leaves that to the caller,
    `reboot_base`). Returns the seconds it took."""
    base = ctx.cfg.radio("base")
    t0 = time.time()
    port = base.port()
    ctx.log(f"base over USB: {what}")
    fn(port)
    if reboot and mt.bluetooth_off_after_serial(base):
        ctx.log("rebooting the Heltec so its Bluetooth comes back")
        mt.reboot(port)
    return time.time() - t0


def reboot_base(ctx: Context) -> None:
    """The Heltec reboot a `base_write(reboot=False)` skipped."""
    base = ctx.cfg.radio("base")
    if mt.bluetooth_off_after_serial(base):
        ctx.log("rebooting the Heltec so its Bluetooth comes back")
        mt.reboot(base.port())


def mobile_port(ctx: Context) -> str:
    return ctx.cfg.radio("mobile").port()


def other_key(psk: bytes) -> bytes:
    """A 32-byte key that is not `psk` (the base goes deaf on it)."""
    return bytes(b ^ 0xA5 for b in psk)
