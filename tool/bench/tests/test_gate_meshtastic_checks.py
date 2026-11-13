# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""radios.meshtastic.check_meshtest_setup over hand-built snapshots."""

from __future__ import annotations

import copy

import pytest

from bench.radios import meshtastic as mt

try:  # tests/ may or may not be a package in the merged tree
    from .gate_fixtures import no_network  # noqa: F401
except ImportError:
    from gate_fixtures import no_network  # noqa: F401

KEY = "ab" * 32
MOBILE_PUB = "cd" * 32


def _snap(role="base", **over) -> mt.RadioSnapshot:
    d = dict(
        port="/dev/cu.x", node_num=0x68E178CB, node_id="!68e178cb",
        owner={"longName": "MeshTest Base", "shortName": "BASE", "id": "!68e178cb"},
        firmware_version="2.8.1.8e6a88d", hw_model="HELTEC_V3",
        excluded_modules=["RANGETEST_CONFIG"],
        channels=[{"index": 0, "role": "PRIMARY", "name": "MeshTest", "psk": KEY, "enabled": True}]
                 + [{"index": i, "role": "DISABLED", "name": "", "psk": "", "enabled": False}
                    for i in range(1, 8)],
        lora={"modem_preset": "MEDIUM_FAST", "region": "US", "tx_power": 0, "hop_limit": 3},
        device={"role": "CLIENT", "rebroadcast_mode": "LOCAL_ONLY"},
        security={"admin_key": [MOBILE_PUB], "public_key": "ef" * 32},
        telemetry={"device_telemetry_enabled": True, "device_update_interval": 60},
        range_test={"enabled": False, "sender": 0},
        bluetooth={"mode": "NO_PIN"},
    )
    if role == "mobile":
        d["owner"] = {"longName": "MeshTest Mobile", "shortName": "MOBL"}
        d["security"] = {"admin_key": [], "public_key": MOBILE_PUB}
        d["telemetry"] = {"device_telemetry_enabled": False}
    d.update(over)
    return mt.RadioSnapshot(**d)


def _failed(checks):
    return {c.name for c in checks if not c.ok}


def test_snapshot_derived():
    s = _snap()
    assert len(s.enabled_channels) == 1 and s.primary["name"] == "MeshTest"
    assert not s.on_public_channel
    assert "raw" not in s.to_dict() and s.to_dict()["node_id"] == "!68e178cb"
    lf = _snap(channels=[{"index": 0, "role": "PRIMARY", "name": "LongFast", "psk": "01", "enabled": True}])
    assert lf.on_public_channel                      # 1-byte key = default psk
    assert _snap(channels=[]).on_public_channel      # no primary at all


@pytest.mark.parametrize("role", ["base", "mobile"])
def test_all_checks_pass(role):
    checks = mt.check_meshtest_setup(_snap(role), role=role, psk_hex=KEY, preset="MEDIUM_FAST")
    assert _failed(checks) == set(), [c for c in checks if not c.ok]
    names = [c.name for c in checks]
    assert "key matches the phone's test_channel_psk" in names
    assert "modem preset MEDIUM_FAST" in names
    if role == "base":
        assert "owner renamed to ('MeshTest Base', 'BASE')" in names
        assert "base has an admin key (remote changes from the mobile)" in names
    else:
        assert "mobile telemetry broadcast off" in names


def test_without_psk_and_preset_skips_those_checks():
    names = [c.name for c in mt.check_meshtest_setup(_snap(), role="base", psk_hex=None, preset=None)]
    assert not any("test_channel_psk" in n or n.startswith("modem preset") for n in names)
    assert "primary key is 32 bytes" in names


def test_unknown_role_has_no_name_check():
    names = [c.name for c in mt.check_meshtest_setup(_snap(), role="observer", psk_hex=KEY, preset=None)]
    assert not any(n.startswith("owner renamed") for n in names)


def _check(snap, role="base"):
    return _failed(mt.check_meshtest_setup(snap, role=role, psk_hex=KEY, preset="MEDIUM_FAST"))


def test_second_enabled_channel():
    s = _snap()
    ch = copy.deepcopy(s.channels)
    ch[1] = {"index": 1, "role": "SECONDARY", "name": "admin", "psk": "01", "enabled": True}
    assert _check(_snap(channels=ch)) == {"exactly one enabled channel"}


def test_wrong_channel_name():
    ch = [{"index": 0, "role": "PRIMARY", "name": "LongFast", "psk": KEY, "enabled": True}]
    assert _check(_snap(channels=ch)) == {"primary channel is MeshTest"}


def test_short_key():
    ch = [{"index": 0, "role": "PRIMARY", "name": "MeshTest", "psk": "11" * 16, "enabled": True}]
    assert _check(_snap(channels=ch)) == {"primary key is 32 bytes",
                                          "key matches the phone's test_channel_psk"}


def test_default_key_is_public():
    ch = [{"index": 0, "role": "PRIMARY", "name": "MeshTest", "psk": "01", "enabled": True}]
    assert _check(_snap(channels=ch)) == {"primary key is 32 bytes", "not on the public channel",
                                          "key matches the phone's test_channel_psk"}


def test_other_32_byte_key():
    ch = [{"index": 0, "role": "PRIMARY", "name": "MeshTest", "psk": "ff" * 32, "enabled": True}]
    assert _check(_snap(channels=ch)) == {"key matches the phone's test_channel_psk"}
    # Case-insensitive hex.
    ch[0]["psk"] = KEY.upper()
    assert _check(_snap(channels=ch)) == set()


def test_wrong_preset():
    assert _check(_snap(lora={"modem_preset": "LONG_FAST"})) == {"modem preset MEDIUM_FAST"}


def test_role_and_rebroadcast():
    assert _check(_snap(device={"role": "ROUTER", "rebroadcast_mode": "LOCAL_ONLY"})) == {"role CLIENT"}
    assert _check(_snap(device={"role": "CLIENT", "rebroadcast_mode": "ALL"})) == {"rebroadcast LOCAL_ONLY"}
    # A missing role is the enum's zero value, CLIENT.
    assert _check(_snap(device={"rebroadcast_mode": "LOCAL_ONLY"})) == set()


def test_owner_not_renamed():
    s = _snap(owner={"longName": "Meshtastic 78cb", "shortName": "78cb"})
    assert _check(s) == {"owner renamed to ('MeshTest Base', 'BASE')"}
    m = _snap("mobile", owner={"longName": "MeshTest Mobile", "shortName": "MOBX"})
    assert _check(m, "mobile") == {"owner renamed to ('MeshTest Mobile', 'MOBL')"}


def test_base_without_admin_key():
    assert _check(_snap(security={"admin_key": ["", "", ""], "public_key": "ef" * 32})) == \
        {"base has an admin key (remote changes from the mobile)"}
    assert _check(_snap(security={"public_key": "ef" * 32})) == \
        {"base has an admin key (remote changes from the mobile)"}


def test_mobile_telemetry_on():
    m = _snap("mobile", telemetry={"device_telemetry_enabled": True})
    assert _check(m, "mobile") == {"mobile telemetry broadcast off"}
    # The base may broadcast telemetry (it is the beacon).
    assert _check(_snap(telemetry={"device_telemetry_enabled": True})) == set()
