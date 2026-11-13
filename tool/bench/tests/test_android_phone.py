# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""phones/android.py: the adb commands it builds, with subprocess faked."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from bench.phones import android
from bench.phones.android import AndroidPhone, extras_for, find_pairing_button

PKG = "com.plateaunerd.meshurement"


class FakeRun:
    """Records every subprocess.run call; answers from `replies` by a
    substring of the joined command (first match wins), else returncode 0."""

    def __init__(self, replies: dict[str, tuple[int, str]] | None = None) -> None:
        self.calls: list[list[str]] = []
        self.replies = replies or {}

    def __call__(self, cmd, **kw):
        self.calls.append(list(cmd))
        joined = " ".join(cmd)
        for key, (rc, out) in self.replies.items():
            if key in joined:
                return subprocess.CompletedProcess(cmd, rc, stdout=out if kw.get("text", False) else out.encode(), stderr="" if kw.get("text", False) else b"")
        return subprocess.CompletedProcess(cmd, 0, stdout="" if kw.get("text", False) else b"", stderr="" if kw.get("text", False) else b"")


@pytest.fixture
def phone(monkeypatch) -> tuple[AndroidPhone, FakeRun]:
    fake = FakeRun()
    monkeypatch.setattr(subprocess, "run", fake)
    monkeypatch.setattr(android, "adb_path", lambda: "adb")
    return AndroidPhone("R5CY52X8GVN", PKG), fake


# -- launch arguments -> Intent extras --------------------------------------

def test_extras_bare_flag_is_boolean():
    assert extras_for(["-MeshBench"]) == ["--ez", "MeshBench", "true"]


def test_extras_number_is_int_and_text_is_string():
    assert extras_for(["-MeshBench", "-benchPort", "8765"]) == [
        "--ez", "MeshBench", "true", "--ei", "benchPort", "8765"]
    assert extras_for(["-MeshDemo", "-demoScreen", "map", "-demoSite", "cove"]) == [
        "--ez", "MeshDemo", "true", "--es", "demoScreen", "map", "--es", "demoSite", "cove"]


def test_extras_two_flags_in_a_row_stay_flags():
    assert extras_for(["-MeshDemo", "-MeshBench"]) == [
        "--ez", "MeshDemo", "true", "--ez", "MeshBench", "true"]


def test_extras_reject_a_value_without_a_flag():
    with pytest.raises(ValueError):
        extras_for(["map"])


# -- adb commands ---------------------------------------------------------------

def test_launch_force_stops_and_passes_extras(phone):
    p, fake = phone
    p.launch("-MeshBench", "-benchPort", "9000")
    assert fake.calls == [[
        "adb", "-s", "R5CY52X8GVN", "shell", "am", "start", "-S", "-W", "-n",
        f"{PKG}/.MainActivity", "--ez", "MeshBench", "true", "--ei", "benchPort", "9000"]]


def test_launch_ignores_env(phone):
    p, fake = phone
    p.launch("-MeshBench", env={"MESH_BENCH": "1"})
    assert fake.calls[0][-3:] == ["--ez", "MeshBench", "true"]


def test_install_grants_runtime_permissions(phone):
    p, fake = phone
    p.install(Path("/tmp/app-release.apk"))
    assert fake.calls[0] == ["adb", "-s", "R5CY52X8GVN", "install", "-r", "-g", "/tmp/app-release.apk"]
    grants = [c for c in fake.calls[1:] if c[3:6] == ["shell", "pm", "grant"]]
    assert [c[-1] for c in grants] == list(android.PERMISSIONS)
    assert all(c[6] == PKG for c in grants)


def test_grant_permissions_reports_refusals(monkeypatch):
    fake = FakeRun({"POST_NOTIFICATIONS": (255, "Unknown permission")})
    monkeypatch.setattr(subprocess, "run", fake)
    monkeypatch.setattr(android, "adb_path", lambda: "adb")
    p = AndroidPhone("S", PKG)
    assert p.grant_permissions() == ["android.permission.POST_NOTIFICATIONS"]


def test_ready_parses_adb_devices(monkeypatch):
    fake = FakeRun({
        "adb devices": (0, "List of devices attached\nR5CY52X8GVN  device usb:1 model:SM_A166U\n"),
        "ro.product.model": (0, "SM-A166U\n"),
        "ro.build.version.release": (0, "16\n"),
    })
    monkeypatch.setattr(subprocess, "run", fake)
    monkeypatch.setattr(android, "adb_path", lambda: "adb")
    assert AndroidPhone("R5CY52X8GVN", PKG).ready() == (True, "SM-A166U Android 16")
    assert AndroidPhone("OTHER", PKG).ready() == (False, "not in `adb devices`")


def test_ready_unauthorized(monkeypatch):
    fake = FakeRun({"adb devices": (0, "List of devices attached\nR5CY52X8GVN\tunauthorized\n")})
    monkeypatch.setattr(subprocess, "run", fake)
    monkeypatch.setattr(android, "adb_path", lambda: "adb")
    ok, why = AndroidPhone("R5CY52X8GVN", PKG).ready()
    assert not ok and "unauthorized" in why


def test_adb_failure_raises_with_stderr(monkeypatch):
    def run(cmd, **kw):
        return subprocess.CompletedProcess(cmd, 1, stdout="", stderr="error: device offline")
    monkeypatch.setattr(subprocess, "run", run)
    monkeypatch.setattr(android, "adb_path", lambda: "adb")
    with pytest.raises(RuntimeError, match="device offline"):
        AndroidPhone("S", PKG).terminate()


# -- pairing dialog -------------------------------------------------------------

PAIR_DUMP = """<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" package="com.android.settings" bounds="[0,0][1080,2340]">
    <node index="0" text="Pair with BASE_3e9c?" class="android.widget.TextView" package="com.android.settings" clickable="false" bounds="[100,900][980,1000]" />
    <node index="1" text="Cancel" class="android.widget.Button" package="com.android.settings" clickable="true" bounds="[500,1300][700,1400]" />
    <node index="2" text="Pair" class="android.widget.Button" package="com.android.settings" clickable="true" bounds="[720,1300][980,1400]" />
  </node>
</hierarchy>
UI hierchary dumped to: /dev/tty"""

APP_DUMP = """<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="Pair" class="android.widget.Button" package="com.plateaunerd.meshurement" clickable="true" bounds="[0,0][100,100]" />
</hierarchy>"""


def test_find_pairing_button_centre():
    xml = PAIR_DUMP[:PAIR_DUMP.rfind("</hierarchy>") + len("</hierarchy>")]
    assert find_pairing_button(xml) == (850, 1350)


def test_find_pairing_button_ignores_the_app_and_garbage():
    assert find_pairing_button(APP_DUMP) is None
    assert find_pairing_button("") is None
    assert find_pairing_button("not xml") is None


def test_accept_pairing_taps_when_a_dialog_is_up(monkeypatch):
    fake = FakeRun({"uiautomator dump": (0, PAIR_DUMP)})
    monkeypatch.setattr(subprocess, "run", fake)
    monkeypatch.setattr(android, "adb_path", lambda: "adb")
    p = AndroidPhone("S", PKG)
    assert p.accept_pairing() is True
    assert fake.calls[-1] == ["adb", "-s", "S", "shell", "input", "tap", "850", "1350"]


def test_accept_pairing_does_nothing_without_a_dialog(monkeypatch):
    fake = FakeRun({"uiautomator dump": (0, APP_DUMP + "\nUI hierchary dumped to: /dev/tty")})
    monkeypatch.setattr(subprocess, "run", fake)
    monkeypatch.setattr(android, "adb_path", lambda: "adb")
    p = AndroidPhone("S", PKG)
    assert p.accept_pairing() is False
    assert all("tap" not in c for c in fake.calls)


# -- radio-setup: stale bond detection ----------------------------------------

def test_lost_bond_text():
    from bench.scenarios.radio_setup import _lost_bond
    assert _lost_bond("radio.setupBase: Bad state: Bluetooth connect: "
                      "PlatformException(requestMtu, device is disconnected, null, null)")
    assert _lost_bond("FlutterBluePlusException | connect | apple-code 14 | Peer removed pairing information")
    assert _lost_bond("GATT_INSUFFICIENT_AUTHENTICATION")
    assert not _lost_bond("radio.setupBase: TimeoutException after 0:02:00")
