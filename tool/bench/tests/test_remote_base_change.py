# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""The remote-base-change scenario against a scripted app and radio."""

from __future__ import annotations

import pytest

from bench import scenarios
from bench.config import BenchConfig
from bench.radios import meshtastic as mt
from bench.scenarios import remote_base_change as rbc


def test_pick_target():
    assert rbc.pick_target("MEDIUM_FAST", None) == "MEDIUM_SLOW"
    assert rbc.pick_target("MEDIUM_SLOW", None) == "MEDIUM_FAST"
    assert rbc.pick_target(None, None) == "MEDIUM_SLOW"
    assert rbc.pick_target("LONG_FAST", "SHORT_TURBO") == "SHORT_TURBO"
    with pytest.raises(ValueError):
        rbc.pick_target("LONG_FAST", "LONG_FAST")


class FakeApp:
    """The bench server as the scenario sees it: /state, commands, link events."""

    def __init__(self, *, roles=True, connected=True, confirmed=True):
        self.base_preset = "MEDIUM_FAST"
        self.mobile_preset = "MEDIUM_FAST"
        self.roles_set = roles
        self.connected = connected
        self.confirmed = confirmed
        self.cmds: list[tuple[str, dict]] = []

    def state(self):
        return {
            "roles": {"base": 0x20 if self.roles_set else None, "mobile": 0x10 if self.roles_set else None,
                      "basePreset": self.base_preset if self.roles_set else None},
            "radio": {"ready": self.connected, "state": "ready" if self.connected else "disconnected",
                      "nodeId": 0x10 if self.connected else None, "preset": self.mobile_preset},
        }

    def cmd(self, name, timeout=60, **args):
        self.cmds.append((name, args))
        if name == "radio.setRemoteLora":
            self.base_preset = args["preset"]
            return {"nodeNum": args["nodeNum"], "confirmed": self.confirmed,
                    "steps": ["Asking MeshTest Base for its settings…", "MeshTest Base: saving — it restarts…",
                              *([] if self.confirmed else ["MeshTest Base did not confirm the save; it is restarting"]),
                              "Done"]}
        if name == "radio.setupConnected":
            self.mobile_preset = args["preset"]
            return True
        raise AssertionError(name)

    def wait_link(self, state="ready", timeout=120):
        return None


class FakeBase:
    """What the base reports over USB: follows the app's remote change."""

    def __init__(self, app: FakeApp, *, honest=True):
        self.app, self.honest = app, honest
        self.reads: list[str] = []

    def read(self, radio, log=None):
        self.reads.append(radio.name)
        preset = self.app.base_preset if self.honest else "LONG_FAST"
        return mt.RadioSnapshot(port="p", node_num=0x20, node_id="!20", owner={}, firmware_version="2.8.1",
                                hw_model="HELTEC_V3", excluded_modules=[],
                                channels=[{"index": 0, "role": "PRIMARY", "name": "MeshTest",
                                           "psk": "11" * 32, "enabled": True}],
                                lora={"modem_preset": preset, "tx_power": 20}, device={}, security={},
                                telemetry={}, range_test={}, bluetooth={})


@pytest.fixture
def quick(monkeypatch):
    monkeypatch.setattr(rbc.time, "sleep", lambda s: None)


def run(bench: BenchConfig, app: FakeApp, base: FakeBase, monkeypatch, **options):
    monkeypatch.setattr(mt, "read_then_reboot", base.read)
    ctx = scenarios.Context(cfg=bench, app=app, log=lambda s: None, options=options)
    return scenarios.ALL["remote-base-change"](ctx)


def test_happy_path_there_and_back(bench, monkeypatch, quick):
    app, base = FakeApp(), FakeBase(FakeApp())
    base.app = app
    res = run(bench, app, base, monkeypatch, tx_power="20")
    assert res.passed, [c for c in res.checks if not c["ok"]]
    names = [c["name"] for c in res.checks]
    assert "there: base holds modem preset MEDIUM_SLOW" in names
    assert "back: base holds modem preset MEDIUM_FAST" in names
    assert "there: base tx power 20" in names and "back: base tx power 20" not in names
    assert [c for c in app.cmds if c[0] == "radio.setRemoteLora"] == [
        ("radio.setRemoteLora", {"nodeNum": 0x20, "preset": "MEDIUM_SLOW", "txPower": 20}),
        ("radio.setRemoteLora", {"nodeNum": 0x20, "preset": "MEDIUM_FAST"}),
    ]
    mobile = [c[1]["preset"] for c in app.cmds if c[0] == "radio.setupConnected"]
    assert mobile == ["MEDIUM_SLOW", "MEDIUM_FAST"], "the mobile follows each leg"
    assert base.reads == ["base", "base"], "the base is read over USB after each leg"
    assert app.base_preset == app.mobile_preset == "MEDIUM_FAST"


def test_lost_commit_ack_still_verified_over_usb(bench, monkeypatch, quick):
    app = FakeApp(confirmed=False)
    res = run(bench, app, FakeBase(app), monkeypatch)
    assert res.passed


def test_base_that_ignored_the_change_fails(bench, monkeypatch, quick):
    app = FakeApp()
    res = run(bench, app, FakeBase(app, honest=False), monkeypatch)
    assert not res.passed
    bad = [c["name"] for c in res.checks if not c["ok"]]
    assert "there: base holds modem preset MEDIUM_SLOW" in bad


def test_fails_fast_without_roles(bench, monkeypatch, quick):
    app = FakeApp(roles=False)
    res = run(bench, app, FakeBase(app), monkeypatch)
    assert not res.passed
    assert len(res.checks) == 1
    assert "run `bench run radio-setup` first" in res.checks[0]["detail"]
    assert app.cmds == [], "nothing sent"
    assert scenarios.REQUIRES["remote-base-change"] == ("radio-setup",)


def test_fails_fast_when_the_phone_is_not_on_the_mobile(bench, monkeypatch, quick):
    app = FakeApp(connected=False)
    res = run(bench, app, FakeBase(app), monkeypatch)
    assert not res.passed and app.cmds == []
    assert res.checks[-1]["name"] == "phone connected to the mobile radio"


def test_same_preset_option_is_refused(bench, monkeypatch, quick):
    app = FakeApp()
    res = run(bench, app, FakeBase(app), monkeypatch, preset="MEDIUM_FAST")
    assert not res.passed and app.cmds == []


def test_meshcore_pair_is_skipped(bench, monkeypatch, quick):
    bench.radios["base"].protocol = "meshcore"
    res = run(bench, FakeApp(), FakeBase(FakeApp()), monkeypatch)
    assert res.skipped and not res.checks
