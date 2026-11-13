# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""ports.list_ports over a faked pyserial, in_bootloader rules."""

from __future__ import annotations

import os
from types import SimpleNamespace

import pytest

from bench import ports

try:  # tests/ may or may not be a package in the merged tree
    from .gate_fixtures import no_network  # noqa: F401
except ImportError:
    from gate_fixtures import no_network  # noqa: F401


def _fake(device, serial, vid, pid, desc="USB Serial"):
    return SimpleNamespace(device=device, serial_number=serial, vid=vid, pid=pid,
                           description=desc)


@pytest.fixture
def no_volumes(monkeypatch):
    monkeypatch.setattr(os, "listdir", lambda p: ["Macintosh HD"])


def test_list_ports_guesses_and_order(monkeypatch, no_volumes):
    monkeypatch.setattr(ports._lp, "comports", lambda: [
        _fake("/dev/cu.usbserial-0001", "0001", 0x10C4, 0xEA60, "CP2102N"),
        _fake("/dev/cu.usbmodem1234", "24DC", 0x239A, 0x8029, "T1000_E_BOOT"),
        _fake("/dev/cu.debug-console", None, None, None),
        _fake("/dev/cu.other", None, 0x1234, 0x5678),
        _fake("/dev/cu.l1", "4AE3", 0x2886, 0x1667),
        _fake("/dev/cu.nrf", "X", 0x239A, 0x1111),
    ])
    items = ports.list_ports()
    assert [p.device for p in items] == sorted(p.device for p in items)
    assert all(p.vid is not None for p in items)          # debug-console dropped
    by = {p.device: p for p in items}
    assert by["/dev/cu.usbserial-0001"].guess.startswith("heltec-v3")
    assert by["/dev/cu.usbmodem1234"].guess.startswith("t1000-e (app running")
    assert by["/dev/cu.other"].guess == "?"
    assert by["/dev/cu.other"].serial_number == ""       # None -> ""
    assert by["/dev/cu.l1"].guess.startswith("wio-tracker-l1")
    assert by["/dev/cu.nrf"].guess == "nRF52, Adafruit/TinyUSB ids"   # vid-only fallback
    assert not any(p.in_bootloader for p in items)


def test_in_bootloader_by_product_id(no_volumes):
    p = ports.Port("/dev/cu.x", "S", 0x239A, 0x0057, "", "")
    assert p.in_bootloader


def test_in_bootloader_by_mounted_volume(monkeypatch):
    monkeypatch.setattr(os, "listdir", lambda p: ["Macintosh HD", "T1000-E"])
    assert ports.Port("/dev/cu.x", "S", 0x239A, 0x8029, "", "").in_bootloader
    # Only Adafruit-id devices count; a Heltec next to a mounted UF2 volume does not.
    assert not ports.Port("/dev/cu.h", "S", 0x10C4, 0xEA60, "", "").in_bootloader


def test_format_table(monkeypatch, no_volumes):
    assert ports.format_table([]) == "no USB serial ports"
    monkeypatch.setattr(ports._lp, "comports",
                        lambda: [_fake("/dev/cu.a", "0001", 0x10C4, 0xEA60)])
    text = ports.format_table(ports.list_ports())
    assert "port" in text.splitlines()[0]
    assert "10c4:ea60" in text and "0001" in text
