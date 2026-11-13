# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""scenarios.radio_setup._find: matching BLE scan results to USB snapshots."""

from __future__ import annotations

from bench.radios import meshtastic as mt
from bench.scenarios.radio_setup import _find

try:  # tests/ may or may not be a package in the merged tree
    from .gate_fixtures import no_network  # noqa: F401
except ImportError:
    from gate_fixtures import no_network  # noqa: F401


def _snap(node_id="!68e178cb", short="BASE"):
    return mt.RadioSnapshot(
        port="/dev/cu.x", node_num=int(node_id[1:], 16), node_id=node_id,
        owner={"shortName": short} if short else {}, firmware_version="", hw_model="",
        excluded_modules=[], channels=[], lora={}, device={}, security={}, telemetry={},
        range_test={}, bluetooth={})


def _d(id_, name, protocol="meshtastic"):
    return {"id": id_, "name": name, "protocol": protocol, "rssi": -60}


BASE = _d("AA", "BASE_3e9c")          # ESP32: hex tail is the BT MAC, not the node id
MOBILE = _d("BB", "MOBL_d5b5")        # nRF52: hex tail is the node id's tail
MESHCORE = _d("CC", "MeshCore-L1", "meshcore")
DEVICES = [MESHCORE, MOBILE, BASE]


def test_remembered_id_wins_over_names():
    assert _find(DEVICES, _snap("!73eed5b5", "MOBL"), remembered="AA") is BASE


def test_remembered_id_gone_falls_back_to_name():
    assert _find(DEVICES, _snap(), remembered="ZZ") is BASE


def test_short_name_prefix():
    assert _find(DEVICES, _snap(), None) is BASE
    assert _find(DEVICES, _snap("!73eed5b5", "MOBL"), None) is MOBILE


def test_node_id_tail_when_short_name_unknown():
    assert _find(DEVICES, _snap("!73eed5b5", short=None), None) is MOBILE


def test_truncated_ios_name():
    devices = [MOBILE, _d("AA", "BA")]
    assert _find(devices, _snap(), None)["id"] == "AA"
    # One letter is too little to go on.
    assert _find([MOBILE, _d("AA", "B")], _snap(), None) is None


def test_sole_remaining_meshtastic_device():
    devices = [MESHCORE, _d("AA", "Meshtastic_1234")]
    assert _find(devices, _snap("!deadbeef", "XXXX"), None)["id"] == "AA"


def test_taken_excludes_the_mobile():
    devices = [MESHCORE, MOBILE, _d("AA", "Meshtastic_1234")]
    snap = _snap("!deadbeef", "XXXX")
    # Without `taken` two candidates remain, so nothing is picked...
    assert _find(devices, snap, None) is None
    # ...with the mobile taken, the other one is the sole remaining radio.
    assert _find(devices, snap, None, taken=(MOBILE,))["id"] == "AA"


def test_meshcore_devices_never_match():
    assert _find([MESHCORE], _snap("!deadbeef", "Mesh"), None) is None
    assert _find([], _snap(), None) is None
