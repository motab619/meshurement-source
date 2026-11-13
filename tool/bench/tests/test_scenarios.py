# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Each Phase 1 scenario end to end against the fake bench (conftest):
every check passes when the simulated app and radios behave as the real
ones should, and the right check fails when they do not."""

from __future__ import annotations

import json

from bench.radios import meshtastic as mt
from bench.scenarios import (
    Context, backups, exports, pki_recovery, public_channel_refusal, recorded_session,
)

from .conftest import (
    BASE_NODE, BASE_PORT, MOBILE_NODE, MOBILE_PORT, PSK, Sim, failed, make_snapshot,
)


# -- public-channel-refusal --------------------------------------------------

def test_public_channel_refusal_passes(ctx: Context, sim: Sim) -> None:
    public_channel_refusal.run(ctx)
    assert failed(ctx) == []
    writes = [(p, a) for k, p, a in sim.serial if k == "set_primary_psk"]
    assert writes == [(MOBILE_PORT, (bytes([1]), "")), (MOBILE_PORT, (PSK, "MeshTest"))]
    starts = sim.app.called("session.start")
    assert len(starts) == 2 and sim.session is None
    assert sim.app.called("radio.reconnect") == []  # the nRF52 link dropped by itself


def test_public_channel_refusal_reconnects_when_the_link_holds(ctx: Context, sim: Sim) -> None:
    sim.link_drops = False
    ctx.options["name"] = "LongFast"
    public_channel_refusal.run(ctx)
    assert failed(ctx) == []
    assert len(sim.app.called("radio.reconnect")) == 2
    assert sim.serial[0][2] == (bytes([1]), "LongFast")


def test_public_channel_refusal_catches_an_app_that_does_not_refuse(ctx: Context, sim: Sim) -> None:
    real_start = sim.start

    def lax_start(a):
        sim.mobile_key = PSK  # pretend the check passed
        sid = real_start(a)
        sim.mobile_key = bytes([1])
        return sid
    sim.app.handlers["session.start"] = lax_start
    public_channel_refusal.run(ctx)
    bad = failed(ctx)
    assert any("refuses on the public channel" in f for f in bad)


# -- recorded-session ------------------------------------------------------------

def test_recorded_session_passes(ctx: Context, sim: Sim) -> None:
    recorded_session.run(ctx)
    assert failed(ctx) == []
    kinds = [k for k, _, _ in sim.serial]
    # key away, key back, module off, module on: each followed by the Heltec reboot.
    base_writes = [(k, a) for k, p, a in sim.serial if p == BASE_PORT and k != "reboot"]
    assert [k for k, _ in base_writes] == ["set_primary_psk", "set_primary_psk",
                                           "set_module_enabled", "set_module_enabled"]
    assert base_writes[1][1] == (PSK, None)
    assert base_writes[2][1] == ("telemetry", False) and base_writes[3][1] == ("telemetry", True)
    assert kinds.count("reboot") == 5  # 4 Heltec reboots + the mobile reboot
    assert ("reboot", MOBILE_PORT, 0) in sim.serial
    # The out-of-range pref was set for the run and put back.
    assert "out_of_range_timeout_sec" not in sim.prefs
    assert sim.session is None and sim.sessions[0]["ended_at"] is not None
    assert [e.data["state"] for e in sim.app.events if e.type == "range"] == \
        ["inRange", "outOfRange", "inRange", "radioLost", "inRange"]


def test_recorded_session_range_test_beacon_uses_the_range_test_module(ctx: Context, sim: Sim) -> None:
    sim.beacon_kind, sim.beacon_sec = "rangeTest", 30
    recorded_session.run(ctx)
    assert failed(ctx) == []
    mods = [a for k, _, a in sim.serial if k == "set_module_enabled"]
    assert mods == [("range_test", False), ("range_test", True)]
    assert not any("telemetry_miss" in c["name"] for c in ctx.checks)


def test_recorded_session_options_skip_phases(ctx: Context, sim: Sim) -> None:
    ctx.options.update({"beacon_off": "false", "radio_lost": "false", "n_pings": "3"})
    recorded_session.run(ctx)
    assert failed(ctx) == []
    assert not any(k == "set_module_enabled" for k, _, _ in sim.serial)
    assert ("reboot", MOBILE_PORT, 0) not in sim.serial


def test_recorded_session_flags_a_premature_alert(ctx: Context, sim: Sim) -> None:
    # An app that alarms after two misses fails exactly that check.
    orig_tick = sim.tick

    def eager_tick() -> None:
        orig_tick()
        if sim.consec_timeouts == 2 and sim.range != "outOfRange":
            sim.received_since_out = 0
            sim._range("outOfRange")
    sim.app.on_poll = eager_tick
    recorded_session.run(ctx)
    bad = failed(ctx)
    assert any("three pings timed out before the alert" in f for f in bad)
    assert all("three pings" in f or "timeouts recorded" in f for f in bad), bad


def test_recorded_session_without_a_beacon_setup_fails_that_check(ctx: Context, sim: Sim) -> None:
    sim.beacon_kind, sim.beacon_sec = "", 0
    recorded_session.run(ctx)
    bad = failed(ctx)
    assert bad and all("knows the base beacon" in f for f in bad), bad


# -- pki-recovery ----------------------------------------------------------------

def test_pki_recovery_passes(ctx: Context, sim: Sim) -> None:
    pki_recovery.run(ctx)
    assert failed(ctx) == []
    assert ("reset_node_db", BASE_PORT, None) in sim.serial
    # The Heltec reboot comes last: a booting base asks every node for its
    # NodeInfo and would get the mobile's key back before any NAK.
    assert sim.serial[-1] == ("reboot", BASE_PORT, 25)
    assert sim.serial.index(("reset_node_db", BASE_PORT, None)) == len(sim.serial) - 2
    i = sim.statuses.index("error:PKI_UNKNOWN_PUBKEY")
    assert "received" in sim.statuses[:i] and "received" in sim.statuses[i + 1:]
    assert sim.session is None


def test_pki_recovery_without_a_nak(ctx: Context, sim: Sim) -> None:
    # Default: a base that answers without the key passes (2.8.1, bench 2026-11-09).
    sim.pki_nak = False
    sim.base_knows_mobile = True
    pki_recovery.run(ctx)
    assert failed(ctx) == []
    assert any(c["name"] == "pings answered after the base forgot the mobile" for c in ctx.checks)
    # require_nak=true makes the missing NAK a failure.
    ctx.checks.clear()
    ctx.options["require_nak"] = "true"
    pki_recovery.run(ctx)
    bad = failed(ctx)
    assert len(bad) == 1 and "PKI NAK" in bad[0]


# -- backups --------------------------------------------------------------------

def _backup(node: int, *, original: bool, preset: str = "LONG_FAST", channels: str = "(default)",
            owner: str = "Pocket") -> dict:
    return {"path": f"/x/{node:08x}.mabackup", "nodeNum": node, "nodeId": f"!{node:08x}",
            "radioName": owner, "ownerName": owner, "protocol": "meshtastic",
            "reason": "Before Radio Setup" if original else "After Radio Setup",
            "original": original, "savedAt": "2026-11-08T12:00:00Z", "summary": f"{preset} · {channels}",
            "channels": channels, "preset": preset, "region": "US"}


def test_backups_passes_with_the_cached_snapshot(ctx: Context, sim: Sim, monkeypatch) -> None:
    sim.backups = [_backup(MOBILE_NODE, original=False, preset="MEDIUM_FAST", channels="MeshTest",
                           owner="MeshTest Mobile"),
                   _backup(MOBILE_NODE, original=True), _backup(BASE_NODE, original=True)]
    monkeypatch.setattr(backups, "cached", lambda serial: make_snapshot())
    backups.run(ctx)
    assert failed(ctx) == []
    assert sim.app.called("backups.restoreOriginal") == [{"nodeNum": MOBILE_NODE}]
    assert sim.app.state_data["roles"]["mobile"] is None
    assert any(c["name"].startswith("mobile: channels") for c in ctx.checks)


def test_backups_detects_a_radio_not_put_back(ctx: Context, sim: Sim, monkeypatch) -> None:
    sim.backups = [_backup(MOBILE_NODE, original=True), _backup(BASE_NODE, original=True)]
    monkeypatch.setattr(backups, "cached", lambda serial: make_snapshot())
    # The USB read-back still shows Radio Setup's preset and name.
    import bench.radios.meshtastic as mt
    monkeypatch.setattr(mt, "snapshot", lambda port: make_snapshot(
        lora={"modem_preset": "MEDIUM_FAST", "region": "US", "hop_limit": 3, "tx_power": 27,
              "use_preset": True, "channel_num": 0},
        owner={"longName": "MeshTest Mobile", "shortName": "MOBL"}))
    backups.run(ctx)
    bad = failed(ctx)
    assert any("lora modem_preset" in f for f in bad) and any("owner names" in f for f in bad)
    assert not any("channels" in f for f in bad)


def test_backups_without_originals_fails_and_stops(ctx: Context, sim: Sim, monkeypatch) -> None:
    sim.backups = [_backup(MOBILE_NODE, original=False)]
    monkeypatch.setattr(backups, "cached", lambda serial: None)
    backups.run(ctx)
    bad = failed(ctx)
    assert any("mobile node" in f for f in bad) and sim.app.called("backups.restoreOriginal") == []


def test_backups_restore_off_only_lists(ctx: Context, sim: Sim, monkeypatch) -> None:
    sim.backups = [_backup(MOBILE_NODE, original=True), _backup(BASE_NODE, original=True)]
    monkeypatch.setattr(backups, "cached", lambda serial: None)
    ctx.options["restore"] = "false"
    backups.run(ctx)
    assert failed(ctx) == [] and sim.app.called("backups.restoreOriginal") == []


def test_compare_snapshot() -> None:
    before = make_snapshot()
    assert all(c.ok for c in backups.compare_snapshot(before, make_snapshot()))
    after = make_snapshot(device={"role": "CLIENT", "rebroadcast_mode": "LOCAL_ONLY"},
                          telemetry={"device_telemetry_enabled": False})
    bad = [c.name for c in backups.compare_snapshot(before, after) if not c.ok]
    assert bad == ["device rebroadcast_mode as before", "telemetry broadcast as before"]


# -- exports --------------------------------------------------------------------

def _csv(header: list[str], rows: list[dict]) -> str:
    lines = [",".join(header)]
    for r in rows:
        lines.append(",".join(str(r.get(c, "")) for c in header))
    return "\n".join(lines) + "\n"


def _wire_exports(sim: Sim, *, header: list[str] | None = None, drop_rows: int = 0,
                  event_count_off: int = 0) -> None:
    header = header or list(exports.REQUIRED_COLUMNS)

    def export_session(a: dict) -> str:
        sid = a["sessionId"]
        if a.get("format") == "geoJson":
            return json.dumps({"type": "FeatureCollection", "features": []})
        if a.get("format") == "meshtasticCsv":
            return "time,from,to,snr\n" + "".join(f"{i},2,3,4\n" for i in range(sim.samples))
        rows = [{"event_id": i + 1, "session_id": sid, "direction": "tx", "packet_type": "ping",
                 "ping_status": s} for i, s in enumerate(sim.statuses)]
        rows += [{"event_id": 100 + i, "session_id": sid, "source_kind": "telemetry"}
                 for i in range(sim.samples)]
        rows += [{"event_id": 200 + i, "session_id": sid, "source_kind": "telemetry_miss"}
                 for i in range(sim.misses)]
        return _csv(header, rows[drop_rows:])

    def maps_json(a: dict) -> str:
        return json.dumps({"maps": [{
            "id": a["mapId"], "name": "Bench", "base_lat": 33.6, "base_lon": -116.3,
            "sessions": [{
                "id": s["id"], "lora_preset": s["lora_preset"], "protocol": s["protocol"],
                "region": s["region"], "beacon_kind": s["beacon_kind"],
                "beacon_interval_sec": s["beacon_interval_sec"],
                "event_count": len(sim.statuses) + sim.samples + event_count_off,
            } for s in sim.sessions]}]})
    sim.app.handlers["export.session"] = export_session
    sim.app.handlers["export.mapsJson"] = maps_json


def test_exports_records_a_session_when_none_exists(ctx: Context, sim: Sim) -> None:
    _wire_exports(sim)
    exports.run(ctx)
    assert failed(ctx) == []
    assert len(sim.sessions) == 1 and sim.sessions[0]["ended_at"] is not None
    assert sim.app.called("export.session")[0]["format"] == "csvV2"
    assert sim.app.called("export.mapsJson") == [{"mapId": 1}]


def test_exports_uses_the_newest_ended_session(ctx: Context, sim: Sim) -> None:
    sim.start({"mapId": 1, "pingIntervalSec": 10})
    for _ in range(4):
        sim.tick()
    sim.end({})
    _wire_exports(sim)
    exports.run(ctx)
    assert failed(ctx) == [] and len(sim.sessions) == 1
    assert sim.app.called("export.session")[0]["sessionId"] == 1


def test_exports_catches_a_missing_column_and_a_short_csv(ctx: Context, sim: Sim) -> None:
    header = [c for c in exports.REQUIRED_COLUMNS if c != "session_tx_power_dbm"]
    header.insert(3, "uplink_snr")
    header.remove("uplink_snr")
    header.append("uplink_snr")
    _wire_exports(sim, header=header, drop_rows=1, event_count_off=1)
    exports.run(ctx)
    bad = failed(ctx)
    assert any("every v2 column present" in f and "session_tx_power_dbm" in f for f in bad)
    assert any("one row per packet event" in f for f in bad)
    assert any("event_count" in f for f in bad)


def test_check_csv_column_order_and_last_column(ctx: Context) -> None:
    header = list(exports.REQUIRED_COLUMNS)
    header[0], header[1] = header[1], header[0]
    exports.check_csv(ctx, _csv(header, [{"event_id": 1, "session_id": 1}]),
                      {"events": 1, "pings": 0})
    names = [c["name"] for c in ctx.checks if not c["ok"]]
    assert names == ["csv: columns in v2 order"]


def test_backups_judges_the_restore_by_the_backup_when_the_radio_changed(
        ctx: Context, sim: Sim, monkeypatch) -> None:
    """The original backup is older than this run (the radio was changed
    since): the restore is checked against the backup, not the snapshot."""
    sim.backups = [_backup(MOBILE_NODE, original=True, channels="MeshTest", owner="MeshTest Mobile"),
                   _backup(BASE_NODE, original=True)]
    changed = make_snapshot(lora={"modem_preset": "MEDIUM_FAST", "region": "US"})
    restored = make_snapshot(owner={"longName": "MeshTest Mobile", "shortName": "MOBL"},
                             channels=[{"index": 0, "role": "PRIMARY", "name": "MeshTest",
                                        "psk": "07" * 32, "enabled": True}])
    monkeypatch.setattr(backups, "cached", lambda serial: changed)
    monkeypatch.setattr(mt, "snapshot", lambda port: restored)
    backups.run(ctx)
    assert failed(ctx) == []
    assert any(c["name"] == "mobile: preset as in its original backup" for c in ctx.checks)
