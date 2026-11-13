# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""The timing rules and event helpers in `scenarios/common.py`."""

from __future__ import annotations

import base64

import pytest

from bench.app import BenchCommandError
from bench.scenarios import Context, common

from .conftest import PSK, FakeApp, Sim, base_state, fake_config


def test_out_of_range_window_matches_session_manager() -> None:
    # The Dart test in test/out_of_range_monitor_test.dart, same numbers.
    assert common.out_of_range_window_sec(30, pref_sec=30) == 120
    assert common.out_of_range_window_sec(60, pref_sec=90) == 210
    assert common.out_of_range_window_sec(30, pref_sec=600) == 600
    assert common.out_of_range_window_sec(0, pref_sec=30, beacon_sec=60) == 150


def test_reentry_window() -> None:
    assert common.reentry_window_sec(10) == 2 * 10 + 30


def test_other_key_differs_and_is_32_bytes() -> None:
    k = common.other_key(PSK)
    assert len(k) == 32 and k != PSK and common.other_key(k) == PSK


def test_test_psk(sim: Sim) -> None:
    assert common.test_psk(sim.app) == PSK
    sim.prefs["test_channel_psk"] = base64.b64encode(b"short").decode()
    with pytest.raises(RuntimeError, match="not 32"):
        common.test_psk(sim.app)
    del sim.prefs["test_channel_psk"]
    with pytest.raises(RuntimeError, match="radio-setup"):
        common.test_psk(sim.app)


def test_base_write_reboots_a_heltec(ctx: Context, sim: Sim) -> None:
    common.base_write(ctx, "x", lambda p: sim.serial.append(("fn", p, None)))
    assert [s[0] for s in sim.serial] == ["fn", "reboot"]
    assert sim.serial[1][1] == "/dev/cu.base"
    ctx.cfg.radios["base"].board = "t1000-e"
    sim.serial.clear()
    common.base_write(ctx, "x", lambda p: None)
    assert sim.serial == []
    assert common.base_write_sec(ctx) == common.SERIAL_SETTLE_SEC


def test_events_and_pings(sim: Sim) -> None:
    app = sim.app
    since = common.seq(app)
    assert since == 0
    app.emit("ping", status="received")
    app.emit("range", state="inRange")
    app.emit("ping", status="timeout")
    app.poll_events()
    assert common.pings_after(app, since) == ["received", "timeout"]
    assert [e.data["state"] for e in common.events_after(app, since, "range")] == ["inRange"]
    mark = common.seq(app)
    assert mark == 3 and common.pings_after(app, mark) == []


def test_wait_helpers_use_the_simulation(clock, ctx: Context, sim: Sim) -> None:
    app = sim.app
    sim.start({"mapId": 1, "pingIntervalSec": 10})
    since = common.seq(app)
    got = common.wait_pings(app, since, 3, timeout=100)
    assert got[:3] == ["received"] * 3
    assert common.wait_range(app, since, "inRange", timeout=30) is not None
    # A deaf base: three timeouts, then out of range.
    sim.base_key = b"x" * 32
    mark = common.seq(app)
    ev = common.wait_range(app, mark, "outOfRange", timeout=100)
    assert ev is not None
    before = [e.data["status"] for e in common.events_after(app, mark, "ping") if e.seq < ev.seq]
    assert before.count("timeout") == 3
    # Nothing arrives: the wait gives up at the (fake) timeout, no exception.
    sim.session = None
    assert common.wait_beacon(app, common.seq(app), True, timeout=5) is None


def test_reconnect_if_needed(clock, ctx: Context, sim: Sim) -> None:
    app = sim.app
    # The link dropped and came back: no reconnect command.
    since = common.seq(app)
    app.emit("link", state="disconnected")
    app.emit("link", state="ready")
    common.reconnect_if_needed(ctx, since, wait=5)
    assert app.called("radio.reconnect") == []
    # The link held: reconnect on purpose.
    since = common.seq(app)
    common.reconnect_if_needed(ctx, since, wait=5)
    assert len(app.called("radio.reconnect")) == 1


def test_create_map_and_session(ctx: Context, sim: Sim) -> None:
    assert common.create_map(ctx) == 1
    gps = sim.app.called("gps.set")[0]
    assert gps["lat"] > common.DEFAULT_LAT and gps["lon"] == common.DEFAULT_LON
    row = common.start_session(ctx, 1, ping_sec=3, name="t")
    # The row carries the interval the app actually uses (floored).
    assert row["ping_interval_sec"] >= 3
    assert sim.session is not None and sim.session["id"] == row["id"]
    common.end_session(ctx)
    assert sim.session is None


def test_fake_app_without_handler_is_a_command_error() -> None:
    app = FakeApp(base_state())
    with pytest.raises(BenchCommandError, match="no fake handler"):
        app.cmd("nope")
    assert fake_config().radio("base").board == "heltec-v3"
