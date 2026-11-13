# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""The MeshCore scenarios' pure parts: device matching, snapshot and backup
checks, outcome checks, and the Skip rules. No phone, no radio."""

from __future__ import annotations

from pathlib import Path

import pytest

from bench import config
from bench.scenarios import Context, Skip, meshcore_session, radio_setup_meshcore as rs

PSK_HEX = "00112233445566778899aabbccddeeff" + "ff" * 16
PRESET = "MC_SF7_BW62.5_CR5"


def cfg_with(*radios: tuple[str, str, str]) -> config.BenchConfig:
    c = config.BenchConfig(path=Path("bench.toml"), reports_dir=Path("/tmp"), firmware_cache=Path("/tmp"))
    for name, protocol, role in radios:
        c.radios[name] = config.RadioConfig(name=name, serial=name, board="t1000-e", protocol=protocol, role=role)
    return c


_ROLE = object()  # "repeat as the role wants": True for a base, False for a mobile


def snapshot(role: str, *, name=None, slot=1, secret=PSK_HEX[:32], modulation=PRESET, khz=918000,
             repeat=_ROLE, public=False, extra_slots=()) -> dict:
    repeat = (role == "base") if repeat is _ROLE else repeat
    channels = [{"index": 0, "name": "Public", "secret": "8b" * 16, "empty": False},
                {"index": slot, "name": "MeshTest", "secret": secret, "empty": False}]
    for i in extra_slots:
        channels.append({"index": i, "name": "MeshTest", "secret": secret, "empty": False})
    return {
        "protocol": "meshcore", "nodeId": 1, "nodeIdHex": "!00000001", "onPublicChannel": public,
        "meshcore": {
            "name": name or rs.NAMES[role], "txPowerDbm": 22, "frequencyKHz": khz,
            "modulation": modulation, "paramsLabel": "SF7 / 62.5 kHz / 4/5",
            "clientRepeat": repeat, "channels": channels,
        },
    }


def failures(checks):
    return [name for name, ok, _ in checks if not ok]


# -- pair from bench.toml -----------------------------------------------------

def test_meshcore_pair_picks_by_protocol_and_role_whatever_the_table_names():
    c = cfg_with(("base", "meshtastic", "base"), ("mobile", "meshtastic", "mobile"),
                 ("mc_base", "meshcore", "base"), ("mc_mobile", "meshcore", "mobile"))
    base, mobile = rs.meshcore_pair(c)
    assert (base.name, mobile.name) == ("mc_base", "mc_mobile")


def test_meshcore_pair_skips_without_two_meshcore_radios():
    with pytest.raises(Skip):
        rs.meshcore_pair(cfg_with(("base", "meshtastic", "base"), ("mobile", "meshtastic", "mobile")))
    with pytest.raises(Skip):
        rs.meshcore_pair(cfg_with(("mc_base", "meshcore", "base")))


def test_scenario_run_is_a_skip_when_the_bench_has_no_meshcore_pair():
    class NoApp:
        def __getattr__(self, name):  # any call would be a bug: Skip must come first
            raise AssertionError(f"app.{name} called")

    ctx = Context(cfg=cfg_with(("base", "meshtastic", "base")), app=NoApp(), log=lambda s: None)
    with pytest.raises(Skip):
        rs.run(ctx)


# -- device matching ----------------------------------------------------------

L1 = {"id": "A", "name": "MeshCore-L1", "protocol": "meshcore", "rssi": -50}
T1000 = {"id": "B", "name": "MeshCore-T1000", "protocol": "meshcore", "rssi": -60}
HELTEC = {"id": "C", "name": "BASE_3e9c", "protocol": "meshtastic", "rssi": -40}


def test_find_pair_prefers_the_ids_the_app_remembers():
    base, mobile, how = rs.find_pair([HELTEC, T1000, L1], {"baseDevice": "A", "mobileDevice": "B"})
    assert (base["id"], mobile["id"]) == ("A", "B")
    assert "remembered id" in how


def test_find_pair_uses_the_role_word_after_a_rename():
    renamed = [{"id": "A", "name": "MeshCore-MeshTest Mobile", "protocol": "meshcore"},
               {"id": "B", "name": "MeshCore-MeshTest Base", "protocol": "meshcore"}, HELTEC]
    base, mobile, how = rs.find_pair(renamed, {})
    assert (base["id"], mobile["id"]) == ("B", "A")
    assert "'base' in the name" in how


def test_find_pair_takes_the_only_two_meshcore_devices_and_says_so():
    base, mobile, how = rs.find_pair([HELTEC, L1, T1000], {})
    assert (base["id"], mobile["id"]) == ("A", "B")
    assert "only two" in how


def test_find_pair_hints_pin_a_fresh_pair():
    base, mobile, how = rs.find_pair([L1, T1000], {}, base_hint="T1000", mobile_hint="L1")
    assert (base["id"], mobile["id"]) == ("B", "A")
    assert "base_name option" in how


def test_find_pair_never_uses_a_meshtastic_device_and_fails_with_three():
    third = {"id": "D", "name": "MeshCore-Spare", "protocol": "meshcore"}
    base, mobile, how = rs.find_pair([HELTEC, L1, T1000, third], {})
    assert base is None and mobile is None
    assert how == "not found"
    base, mobile, _ = rs.find_pair([HELTEC], {"baseDevice": "C", "mobileDevice": "C"})
    assert base is None and mobile is None


def test_find_pair_remembered_base_plus_the_other_device_as_mobile():
    base, mobile, how = rs.find_pair([L1, T1000], {"baseDevice": "B"})
    assert (base["id"], mobile["id"]) == ("B", "A")
    assert "other MeshCore device as mobile" in how


# -- snapshot checks ----------------------------------------------------------

def test_good_base_and_mobile_snapshots_pass_every_check():
    for role in ("base", "mobile"):
        checks = rs.check_meshcore_snapshot(snapshot(role), role=role, psk_hex=PSK_HEX, preset=PRESET,
                                            freq_mhz=918.0, tx_power=22)
        assert failures(checks) == [], role


def test_snapshot_checks_catch_each_mistake():
    def bad(snap, role="mobile", **kw):
        return failures(rs.check_meshcore_snapshot(snap, role=role, psk_hex=PSK_HEX, preset=PRESET,
                                                   freq_mhz=918.0, **kw))

    assert bad(snapshot("mobile", secret="00" * 16)) == ["MeshTest secret = first 16 bytes of the phone's test key"]
    assert bad(snapshot("mobile", slot=0)) == ["MeshTest is not in slot 0"]
    assert bad(snapshot("mobile", extra_slots=(2,))) == ["one MeshTest channel slot"]
    assert bad(snapshot("mobile", modulation="MC_SF8_BW62.5_CR5")) == ["modulation is the requested ladder entry"]
    assert bad(snapshot("mobile", khz=910525)) == ["frequency is 918.000 MHz"]
    assert bad(snapshot("mobile", repeat=True)) == ["mobile does not relay"]
    assert bad(snapshot("base", repeat=False), role="base") == ["base relays (client repeat on)"]
    assert bad(snapshot("base", repeat=None), role="base") == ["base relays (client repeat on)"]
    assert bad(snapshot("mobile", name="L1")) == ["advert name is 'MeshTest Mobile'"]
    assert bad(snapshot("mobile", name="L1"), renamed=False) == []
    assert bad(snapshot("mobile", public=True)) == ["not on a public (community) setting"]
    assert bad(snapshot("mobile"), tx_power=20) == ["TX power is 20 dBm"]
    meshtastic = {"protocol": "meshtastic", "meshtastic": {}, "onPublicChannel": False}
    assert "protocol is MeshCore" in bad(meshtastic)
    assert "one MeshTest channel slot" in bad(meshtastic)


def test_snapshot_check_without_a_phone_key_fails_the_secret_only():
    assert failures(rs.check_meshcore_snapshot(snapshot("mobile"), role="mobile", psk_hex=None,
                                               preset=PRESET, freq_mhz=918.0)) == \
        ["MeshTest secret = first 16 bytes of the phone's test key"]


# -- backups ------------------------------------------------------------------

def test_backup_checks_want_one_meshcore_original_per_node():
    backups = [
        {"nodeNum": 1, "protocol": "meshcore", "original": True},
        {"nodeNum": 1, "protocol": "meshcore", "original": False},
        {"nodeNum": 2, "protocol": "meshcore", "original": True},
    ]
    assert failures(rs.check_backups(backups, {"base": 1, "mobile": 2})) == []
    assert failures(rs.check_backups(backups, {"base": 1, "mobile": 3})) == ["mobile: an original backup exists"]
    assert failures(rs.check_backups(backups, {"base": None})) == ["base: an original backup exists"]
    # already on MeshTest before the run, no backup on this phone: not a failure
    assert failures(rs.check_backups(backups, {"base": 1, "mobile": 3}, frozenset({"mobile"}))) == []
    wrong = [{"nodeNum": 1, "protocol": "meshtastic", "original": True}]
    assert failures(rs.check_backups(wrong, {"base": 1})) == ["base: the original backup is MeshCore"]


# -- session outcomes ---------------------------------------------------------

def received(**kw):
    d = {"status": "received", "snr": 8.5, "rssi": -70, "fromBase": True, "hops": 0, "uplinkSnr": 7.25}
    d.update(kw)
    return d


def test_good_trace_outcomes_pass():
    pings = [received(), {"status": "timeout", "snr": None, "rssi": None, "fromBase": False, "hops": 0,
                          "uplinkSnr": None}, received(snr=3.0)]
    assert failures(meshcore_session.check_outcomes(pings, 3)) == []


def test_trace_outcome_checks_catch_missing_uplink_snr_and_odd_statuses():
    assert failures(meshcore_session.check_outcomes([received(uplinkSnr=None)], 1)) == \
        ["every received check has the base's uplink SNR"]
    assert failures(meshcore_session.check_outcomes([received(), received(status="implicit")], 2)) == \
        ["no implicit or throttled outcomes (MeshCore never reports them)"]
    assert failures(meshcore_session.check_outcomes([received(hops=1)], 1)) == \
        ["received checks are from the base, no hops"]
    only_timeouts = [{"status": "timeout", "fromBase": False, "hops": 0}] * 3
    fails = failures(meshcore_session.check_outcomes(only_timeouts, 3))
    assert "at least one link check came back 'received'" in fails
    assert "at least 3 link checks answered or timed out" not in fails
    assert "at least 3 link checks answered or timed out" in failures(meshcore_session.check_outcomes([received()], 3))


def test_session_row_checks():
    row = {"protocol": "meshcore", "beacon_kind": "trace", "beacon_interval_sec": 10, "ping_interval_sec": 10,
           "lora_preset": PRESET, "ended_at": 1700000000}
    assert failures(meshcore_session.check_session_row(row, preset=PRESET, interval=10)) == []
    assert failures(meshcore_session.check_session_row(None, preset=PRESET, interval=10)) == ["session row exists"]
    bad = dict(row, beacon_kind="telemetry", ended_at=None, lora_preset="MC_USA")
    assert failures(meshcore_session.check_session_row(bad, preset=PRESET, interval=10)) == \
        ["session beacon kind is trace", "session stores the mobile's modulation", "session ended"]
    # Without a recorded preset the modulation row is not asked for.
    assert failures(meshcore_session.check_session_row(bad, preset=None, interval=10)) == \
        ["session beacon kind is trace", "session ended"]


def test_session_scenario_skips_when_not_on_a_set_up_meshcore_mobile():
    class App:
        def __init__(self, st):
            self.st = st

        def state(self):
            return self.st

    def ctx(radio, roles):
        return Context(cfg=cfg_with(), app=App({"radio": radio, "roles": roles}), log=lambda s: None)

    mc = {"ready": True, "protocol": "meshcore", "nodeId": 7, "onPublicChannel": False}
    with pytest.raises(Skip):
        meshcore_session.run(ctx(dict(mc, protocol="meshtastic"), {"base": 1, "mobile": 7}))
    with pytest.raises(Skip):
        meshcore_session.run(ctx(mc, {"base": None, "mobile": None}))
    with pytest.raises(Skip):
        meshcore_session.run(ctx(mc, {"base": 7, "mobile": 1}))


def test_scenarios_are_registered():
    from bench import scenarios
    assert {"radio-setup", "radio-setup-meshcore", "meshcore-session"} <= set(scenarios.ALL)
