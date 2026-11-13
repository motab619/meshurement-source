# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""The serial-then-reboot rule lives in one place (no radios: port, snapshot
and reboot are stubbed)."""

from __future__ import annotations

import pytest

from bench.config import RadioConfig
from bench.radios import meshtastic as mt

HELTEC = RadioConfig("base", "H1", "heltec-v3", "meshtastic", "base")
T1000 = RadioConfig("mobile", "T1", "t1000-e", "meshtastic", "mobile")
L1 = RadioConfig("obs", "L1", "wio-tracker-l1", "meshtastic", "observer")
UNKNOWN_ESP = RadioConfig("x", "X1", "heltec-v4", "meshtastic", "base")


def test_bluetooth_off_after_serial_is_by_mcu():
    assert mt.bluetooth_off_after_serial(HELTEC)
    assert not mt.bluetooth_off_after_serial(T1000)
    assert not mt.bluetooth_off_after_serial(L1)
    assert mt.bluetooth_off_after_serial(UNKNOWN_ESP), "unknown board named heltec-*: assume ESP32"


@pytest.fixture
def stubs(monkeypatch):
    calls: list[tuple] = []
    monkeypatch.setattr(RadioConfig, "port", lambda self: f"/dev/cu.{self.serial}")
    monkeypatch.setattr(mt, "reboot", lambda port, wait_s=25: calls.append(("reboot", port, wait_s)))
    monkeypatch.setattr(mt, "snapshot", lambda port: calls.append(("snapshot", port)) or f"snap:{port}")
    return calls


def test_serial_session_reboots_only_an_esp32(stubs):
    logs: list[str] = []
    with mt.serial_session(HELTEC, logs.append) as port:
        assert port == "/dev/cu.H1"
    assert stubs == [("reboot", "/dev/cu.H1", 25)]
    assert logs and "Bluetooth comes back" in logs[0]
    stubs.clear()
    with mt.serial_session(T1000) as port:
        assert port == "/dev/cu.T1"
    assert stubs == []


def test_serial_session_does_not_reboot_after_a_failed_body(stubs):
    with pytest.raises(ValueError):
        with mt.serial_session(HELTEC):
            raise ValueError("read failed")
    assert stubs == [], "the read's error surfaces, not a second one from the reboot"


def test_read_then_reboot(stubs):
    assert mt.read_then_reboot(HELTEC) == "snap:/dev/cu.H1"
    assert stubs == [("snapshot", "/dev/cu.H1"), ("reboot", "/dev/cu.H1", 25)]
    stubs.clear()
    assert mt.read_then_reboot(T1000) == "snap:/dev/cu.T1"
    assert stubs == [("snapshot", "/dev/cu.T1")]


def test_no_scattered_heltec_checks_remain():
    """The rule is the helper's; nothing else keys on the board name."""
    import re
    from pathlib import Path
    root = Path(mt.__file__).resolve().parents[1]
    offenders = []
    for p in root.rglob("*.py"):
        if p.name == "meshtastic.py":
            continue
        for i, line in enumerate(p.read_text().splitlines(), 1):
            if re.search(r'startswith\("heltec"\)|startswith\("esp32"\)', line) and "mcu" not in line:
                offenders.append(f"{p.relative_to(root)}:{i}: {line.strip()}")
    assert offenders == []
