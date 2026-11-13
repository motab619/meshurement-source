# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""A fake bench for the scenario tests: a scripted phone app (`FakeApp`,
the `AppLink` interface), a tiny simulation of the app's recording rules
(`Sim`: pings, out-of-range after three misses, re-entry after two
answers, beacon absent after three silent slots, radio lost on a mobile
reboot) and fake serial helpers patched into `bench.radios.meshtastic`.
Time is faked too, so computed waits never sleep."""

from __future__ import annotations

import base64
import copy
from datetime import datetime
from pathlib import Path
from typing import Any, Callable

import pytest

from bench import config
from bench.app import BenchCommandError, Event
from bench.radios import meshtastic as mt
from bench.scenarios import Context, common

PSK = bytes(range(32))
BASE_NODE, MOBILE_NODE = 0xA385, 0x1234
BASE_PORT, MOBILE_PORT = "/dev/cu.base", "/dev/cu.mobile"


class FakeClock:
    """`time.time()` advances a second per call; `sleep` is free."""

    def __init__(self) -> None:
        self.now = 1_000_000.0

    def time(self) -> float:
        self.now += 1
        return self.now

    def sleep(self, s: float) -> None:
        self.now += s

    def strftime(self, fmt: str, *a: Any) -> str:
        return "12:00:00"


class FakeApp:
    """The `AppLink` surface the scenarios use, scripted."""

    def __init__(self, state: dict[str, Any]) -> None:
        self.state_data = state
        self.events: list[Event] = []
        self._pending: list[tuple[str, dict[str, Any]]] = []
        self.calls: list[tuple[str, dict[str, Any]]] = []
        self.handlers: dict[str, Callable[[dict[str, Any]], Any]] = {}
        self.query_handler: Callable[[str], list[dict[str, Any]]] | None = None
        self.on_poll: Callable[[], None] | None = None
        self.log: Callable[[str], None] = lambda s: None

    def state(self) -> dict[str, Any]:
        return copy.deepcopy(self.state_data)

    def cmd(self, _cmd: str, timeout: float = 60, **args: Any) -> Any:
        self.calls.append((_cmd, args))
        h = self.handlers.get(_cmd)
        if h is None:
            raise BenchCommandError(f"{_cmd}: no fake handler")
        return h(args)

    def emit(self, type_: str, **data: Any) -> None:
        self._pending.append((type_, data))

    def _release(self) -> list[Event]:
        out = []
        for t, d in self._pending:
            e = Event(seq=len(self.events) + 1, t=datetime.now().isoformat(), type=t, data=d)
            self.events.append(e)
            out.append(e)
        self._pending.clear()
        return out

    def poll_events(self) -> list[Event]:
        out = self._release()
        if not out and self.on_poll:
            self.on_poll()
            out = self._release()
        return out

    def drain(self) -> None:
        self._release()

    def query(self, sql: str) -> list[dict[str, Any]]:
        self.calls.append(("db.query", {"sql": sql}))
        return self.query_handler(sql) if self.query_handler else []

    def count(self, sql: str) -> int:
        rows = self.query(sql)
        return int(next(iter(rows[0].values()))) if rows else 0

    def called(self, name: str) -> list[dict[str, Any]]:
        return [a for c, a in self.calls if c == name]


def base_state(*, roles: bool = True) -> dict[str, Any]:
    return {
        "app": {"bench": True},
        "radio": {"state": "ready", "ready": True, "protocol": "meshtastic", "nodeId": MOBILE_NODE,
                  "preset": "MEDIUM_FAST", "primaryChannel": "MeshTest", "onPublicChannel": False},
        "roles": {"base": BASE_NODE if roles else None, "mobile": MOBILE_NODE if roles else None,
                  "baseDevice": "B", "mobileDevice": "M"},
        "session": None,
        "range": "unknown",
        "beacon": {"active": False, "kind": "none", "intervalSec": 0, "heard": 0, "seqMissed": 0,
                   "traceMissed": 0, "absent": False},
        "seq": 0,
    }


class Sim:
    """The app's recording rules, one tick per `poll_events`."""

    def __init__(self, app: FakeApp, *, beacon_kind: str = "telemetry", beacon_sec: int = 60,
                 link_drops: bool = True, pki_nak: bool = True) -> None:
        self.app = app
        self.beacon_kind, self.beacon_sec = beacon_kind, beacon_sec
        self.link_drops, self.pki_nak = link_drops, pki_nak
        self.base_key = PSK
        self.mobile_key, self.mobile_name = PSK, "MeshTest"
        self.beacon_on = True
        self.base_knows_mobile = True
        self.mobile_up = True
        self.mobile_down_ticks = 0
        self.prefs: dict[str, Any] = {"test_channel_psk": base64.b64encode(PSK).decode()}
        self.sessions: list[dict[str, Any]] = []
        self.session: dict[str, Any] | None = None
        self.statuses: list[str] = []
        self.samples = self.misses = 0
        self.consec_timeouts = self.received_since_out = 0
        self.range = "unknown"
        self.absent = False
        self.silent = 0
        self.serial: list[tuple[str, str, Any]] = []
        self.backups: list[dict[str, Any]] = []
        app.on_poll = self.tick
        app.query_handler = self.query
        app.handlers.update({
            "prefs.get": lambda a: self.prefs.get(a["key"]),
            "prefs.set": self._prefs_set,
            "map.create": lambda a: 1,
            "gps.set": lambda a: True,
            "session.start": self.start,
            "session.end": self.end,
            "radio.reconnect": self.reconnect,
            "backups.list": lambda a: list(self.backups),
            "backups.restoreOriginal": self.restore_original,
        })

    # -- state -------------------------------------------------------------

    def _prefs_set(self, a: dict[str, Any]) -> bool:
        if a["value"] is None:
            self.prefs.pop(a["key"], None)
        else:
            self.prefs[a["key"]] = a["value"]
        return True

    @property
    def on_public(self) -> bool:
        return len(self.mobile_key) <= 1

    @property
    def reachable(self) -> bool:
        return self.base_key == self.mobile_key and self.mobile_up

    def refresh_state(self) -> None:
        st = self.app.state_data
        st["radio"].update({"ready": self.mobile_up, "state": "ready" if self.mobile_up else "disconnected",
                            "onPublicChannel": self.on_public if self.mobile_up else None,
                            "primaryChannel": self.mobile_name})
        st["session"] = None if self.session is None else {"id": self.session["id"]}
        st["range"] = self.range
        st["beacon"] = {"active": self.session is not None, "kind": self.beacon_kind,
                        "intervalSec": self.beacon_sec, "heard": self.samples, "seqMissed": 0,
                        "traceMissed": 0, "absent": self.absent}

    # -- commands ----------------------------------------------------------

    def start(self, a: dict[str, Any]) -> int:
        if self.on_public:
            raise BenchCommandError("session.start: Radio is on the public channel — run "
                                    "Settings → Radio Setup first")
        row = {"id": len(self.sessions) + 1, "coverage_map_id": a["mapId"], "name": a.get("name", ""),
               "ping_interval_sec": max(int(a.get("pingIntervalSec", 0)), 7),
               "lora_preset": "MEDIUM_FAST", "protocol": "meshtastic", "region": "US",
               "tx_power_dbm": 27, "beacon_kind": self.beacon_kind,
               "beacon_interval_sec": self.beacon_sec, "ended_at": None}
        self.sessions.append(row)
        self.session = row
        self.range = "unknown"
        self.consec_timeouts = self.received_since_out = 0
        self.app.emit("session", id=row["id"], active=True)
        self.refresh_state()
        return row["id"]

    def end(self, a: dict[str, Any]) -> bool:
        if self.session is not None:
            self.session["ended_at"] = 1_700_000_000
            self.app.emit("session", id=self.session["id"], active=False)
        self.session = None
        self.range = "unknown"
        self.absent = False
        self.refresh_state()
        return True

    def reconnect(self, a: dict[str, Any]) -> dict[str, Any]:
        self.app.emit("link", state="disconnected")
        self.app.emit("link", state="ready")
        self.refresh_state()
        return dict(self.app.state_data["radio"])

    def restore_original(self, a: dict[str, Any]) -> dict[str, Any]:
        node = a.get("nodeNum", MOBILE_NODE)
        orig = next((b for b in self.backups if b["nodeNum"] == node and b["original"]), None)
        if orig is None:
            raise BenchCommandError(f"backups.restoreOriginal: No original backup for {node}")
        self.app.emit("restore", nodeNum=node, step="Restoring channels…")
        self.app.emit("link", state="disconnected")
        self.app.emit("link", state="ready")
        self.app.state_data["roles"]["mobile"] = None
        self.mobile_key, self.mobile_name = bytes([1]), ""
        self.app.state_data["radio"]["preset"] = "LONG_FAST"
        self.refresh_state()
        return {"backup": orig, "steps": ["Restoring channels…", "Done"], "reboots": True,
                "rolesCleared": True, "revokedMobileKey": False}

    # -- the recording rules, one tick = one ping slot ----------------------

    def tick(self) -> None:
        if self.mobile_down_ticks:
            self.mobile_down_ticks -= 1
            if self.mobile_down_ticks == 0:
                self.mobile_up = True
                self.app.emit("link", state="ready")
                self.refresh_state()
            return
        if self.session is None or not self.mobile_up:
            return
        if self.base_key != self.mobile_key:
            status = "timeout"
        elif not self.base_knows_mobile:
            status = "error:PKI_UNKNOWN_PUBKEY" if self.pki_nak else "timeout"
            self.base_knows_mobile = True  # the app's key exchange after the NAK
        else:
            status = "received"
        self.statuses.append(status)
        self.app.emit("ping", status=status, fromBase=status == "received")
        if status == "received":
            self.consec_timeouts = 0
            if self.range == "outOfRange":
                self.received_since_out += 1
                if self.received_since_out >= common.REENTRY_ANSWERS:
                    self._range("inRange")
            elif self.range != "inRange":
                self._range("inRange")
        elif status == "timeout":
            self.consec_timeouts += 1
            if self.consec_timeouts >= 3 and self.range != "outOfRange":
                self.received_since_out = 0
                self._range("outOfRange")
        # Beacon slot.
        if self.beacon_sec > 0:
            if self.reachable and self.base_knows_mobile:
                if self.beacon_on:
                    self.samples += 1
                    self.silent = 0
                    if self.absent:
                        self.absent = False
                        self.app.emit("beacon", absent=False)
                else:
                    self.silent += 1
                    if self.silent >= common.ABSENT_INTERVALS and not self.absent:
                        self.absent = True
                        self.app.emit("beacon", absent=True)
            elif self.beacon_kind == "telemetry":
                self.misses += 1
        self.refresh_state()

    def _range(self, s: str) -> None:
        self.range = s
        self.app.emit("range", state=s)

    def reboot_mobile(self) -> None:
        self.mobile_up = False
        self.mobile_down_ticks = 2
        self.app.emit("link", state="disconnected")
        self._range("radioLost")
        self.refresh_state()

    # -- the database ------------------------------------------------------

    def query(self, sql: str) -> list[dict[str, Any]]:
        s = " ".join(sql.split()).lower()
        if "from sessions where id =" in s:
            sid = int(s.split("where id =")[1].split()[0])
            rows = [r for r in self.sessions if r["id"] == sid]
            if "select ended_at" in s:
                return [{"ended_at": r["ended_at"]} for r in rows]
            return [dict(r) for r in rows]
        if "from sessions where coverage_map_id" in s:
            return [dict(r) for r in self.sessions]
        if "from sessions where ended_at is not null" in s:
            done = [r for r in self.sessions if r["ended_at"] is not None]
            return [dict(done[-1])] if done else []
        pings = len(self.statuses)
        if "ack_status in ('timeout', 'error:MAX_RETRANSMIT')" in s:
            return [{"n": sum(st in ("timeout", "error:MAX_RETRANSMIT") for st in self.statuses)}]
        if "e.source_node_id = s.base_node_id" in s:
            # packets from the base: ping replies and beacon samples
            return [{"n": self.statuses.count("received") + self.samples}]
        if "ack_status = 'timeout'" in s:
            return [{"n": self.statuses.count("timeout")}]
        if "ack_status = 'received'" in s:
            return [{"n": self.statuses.count("received")}]
        if "telemetry_miss'" in s and "not in" not in s:
            return [{"n": self.misses}]
        if "source_kind in" in s:
            return [{"n": self.samples}]
        if "direction = 'rx'" in s and "source_kind not in" in s:
            return [{"n": self.samples}]  # received samples only
        if "source_kind not in" in s:
            return [{"n": pings + self.samples}]
        if "direction = 'tx'" in s or "ping_correlations" in s:
            return [{"n": pings}]
        if "count(*) from packet_events" in s:
            return [{"n": pings + self.samples + self.misses}]
        raise AssertionError(f"fake DB: no answer for {sql!r}")


def fake_config() -> config.BenchConfig:
    cfg = config.BenchConfig(path=Path("/dev/null"), reports_dir=Path("/tmp"),
                             firmware_cache=Path("/tmp"))
    cfg.radios["base"] = config.RadioConfig(name="base", serial="B1", board="heltec-v3",
                                            protocol="meshtastic", role="base")
    cfg.radios["mobile"] = config.RadioConfig(name="mobile", serial="M1", board="t1000-e",
                                              protocol="meshtastic", role="mobile")
    return cfg


def make_snapshot(**over: Any) -> mt.RadioSnapshot:
    d: dict[str, Any] = dict(
        port=MOBILE_PORT, node_num=MOBILE_NODE, node_id=f"!{MOBILE_NODE:08x}",
        owner={"longName": "Pocket", "shortName": "PKT"}, firmware_version="2.7.26",
        hw_model="TRACKER_T1000_E", excluded_modules=[],
        channels=[{"index": 0, "role": "PRIMARY", "name": "", "psk": "01", "enabled": True,
                   "uplink": False, "downlink": False}]
                 + [{"index": i, "role": "DISABLED", "name": "", "psk": "", "enabled": False,
                     "uplink": False, "downlink": False} for i in range(1, 8)],
        lora={"modem_preset": "LONG_FAST", "region": "US", "hop_limit": 3, "tx_power": 27,
              "use_preset": True, "channel_num": 0},
        device={"role": "CLIENT", "rebroadcast_mode": "ALL"},
        security={"admin_key": [], "public_key": "aa" * 32},
        telemetry={"device_telemetry_enabled": True, "device_update_interval": 1800},
        range_test={}, bluetooth={"mode": "NO_PIN"})
    d.update(over)
    return mt.RadioSnapshot(**d)


@pytest.fixture
def clock(monkeypatch: pytest.MonkeyPatch) -> FakeClock:
    c = FakeClock()
    monkeypatch.setattr(common, "time", c)
    from bench.scenarios import backups
    monkeypatch.setattr(backups, "time", c)
    return c


@pytest.fixture
def ports(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(config.RadioConfig, "port",
                        lambda self: BASE_PORT if self.role == "base" else MOBILE_PORT)


@pytest.fixture
def sim(clock: FakeClock, ports: None, monkeypatch: pytest.MonkeyPatch) -> Sim:
    app = FakeApp(base_state())
    s = Sim(app)

    def set_primary_psk(port: str, psk: bytes, *, name: str | None = None, settle_s: int = 20) -> None:
        s.serial.append(("set_primary_psk", port, (psk, name)))
        if port == BASE_PORT:
            s.base_key = psk
        else:
            s.mobile_key = psk
            if name is not None:
                s.mobile_name = name
            if s.link_drops:
                app.emit("link", state="disconnected")
                app.emit("link", state="ready")
                s.refresh_state()

    def set_module_enabled(port: str, module: str, enabled: bool, *, settle_s: int = 20) -> None:
        s.serial.append(("set_module_enabled", port, (module, enabled)))
        s.beacon_on = enabled

    def reboot(port: str, *, wait_s: int = 25) -> None:
        s.serial.append(("reboot", port, wait_s))
        if port == MOBILE_PORT:
            s.reboot_mobile()

    def reset_node_db(port: str, *, settle_s: int = 20) -> None:
        s.serial.append(("reset_node_db", port, None))
        s.base_knows_mobile = False

    monkeypatch.setattr(mt, "set_primary_psk", set_primary_psk)
    monkeypatch.setattr(mt, "set_module_enabled", set_module_enabled)
    monkeypatch.setattr(mt, "reboot", reboot)
    monkeypatch.setattr(mt, "reset_node_db", reset_node_db)
    monkeypatch.setattr(mt, "snapshot", lambda port: make_snapshot())
    return s


@pytest.fixture
def ctx(sim: Sim) -> Context:
    return Context(cfg=fake_config(), app=sim.app, log=lambda s: None)


def failed(ctx: Context) -> list[str]:
    return [f"{c['name']} [{c['detail']}]" for c in ctx.checks if not c["ok"]]


# -- matrix / firmware fixtures (bench/matrix agent) ---------------------------
"""Shared fixtures: a bench with a Heltec base and a T1000-E mobile, no hardware."""


import json
from pathlib import Path

import pytest

from bench import config


def write_bench_toml(tmp_path: Path, *, flashed: dict | None = None,
                     matrix: str = "") -> Path:
    cache = tmp_path / "firmware"
    cache.mkdir(exist_ok=True)
    if flashed is not None:
        (cache / "flashed.json").write_text(json.dumps(flashed))
    toml = tmp_path / "bench.toml"
    toml.write_text(f'''
[bench]
reports_dir = "{tmp_path / 'reports'}"
firmware_cache = "{cache}"
region = "US"

[radios.base]
serial = "HELTEC1"
board = "heltec-v3"
protocol = "meshtastic"
role = "base"

[radios.mobile]
serial = "T1000E1"
board = "t1000-e"
protocol = "meshtastic"
role = "mobile"

[phone]
platform = "ios"
id = "PHONE"
{matrix}
''')
    return toml


MATRIX = '''
[matrix]
scenarios = ["radio-setup", "remote-base-change"]
combos = [
  { base = "meshtastic 2.8.1", mobile = "meshtastic 2.7.26" },
  { base = "meshtastic 2.8.1", mobile = "meshtastic 2.8.1" },
  { base = "meshtastic latest", mobile = "meshcore 1.18.0", scenarios = ["radio-setup"] },
]
'''


@pytest.fixture
def bench(tmp_path: Path) -> config.BenchConfig:
    """Base flashed 2.8.1 by the bench, mobile on 2.7.26."""
    toml = write_bench_toml(
        tmp_path,
        flashed={"HELTEC1": {"protocol": "meshtastic", "version": "2.8.1.8e6a88d", "at": "x"},
                 "T1000E1": {"protocol": "meshtastic", "version": "2.7.26.abcdef0", "at": "x"}},
        matrix=MATRIX)
    return config.load(toml)


@pytest.fixture
def fresh_bench(tmp_path: Path) -> config.BenchConfig:
    """No flashed.json: bench.toml's protocols, no versions."""
    d = tmp_path / "fresh"
    d.mkdir()
    return config.load(write_bench_toml(d, matrix=MATRIX))
