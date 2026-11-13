# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""config.load from a temp bench.toml, with the flashed.json overlay and phones."""

from __future__ import annotations

import json

import pytest

from bench import config

try:  # tests/ may or may not be a package in the merged tree
    from .gate_fixtures import no_network  # noqa: F401
except ImportError:
    from gate_fixtures import no_network  # noqa: F401

TOML = """
[bench]
reports_dir = "{reports}"
firmware_cache = "{fw}"
region = "EU_868"

[radios.base]
serial = "0001"
board = "heltec-v3"
protocol = "meshtastic"
role = "base"

[radios.spare]
serial = 12345
board = "t1000-e"
protocol = "meshtastic"

[phone]
platform = "ios"
id = "00008030-ABCDEF"

[phones.sim]
platform = "ios-sim"
id = "iPhone 18 Pro Max"

[phones.a16]
platform = "android"
id = "R5CY52X8GVN"
demo = true
demo_screen = "map"
port = 8766
"""


@pytest.fixture
def toml(tmp_path):
    fw = tmp_path / "fw"
    fw.mkdir()
    p = tmp_path / "bench.toml"
    p.write_text(TOML.format(reports=tmp_path / "reports", fw=fw))
    return p


def test_load_basics(toml, tmp_path):
    cfg = config.load(toml)
    assert cfg.path == toml
    assert cfg.reports_dir == tmp_path / "reports"
    assert cfg.firmware_cache == tmp_path / "fw"
    assert cfg.region == "EU_868"
    base = cfg.radio("base")
    assert (base.serial, base.board, base.protocol, base.role, base.firmware) == \
        ("0001", "heltec-v3", "meshtastic", "base", None)
    spare = cfg.radio("spare")
    assert spare.serial == "12345"          # ints become strings
    assert spare.role == "spare"            # role defaults to the table name
    with pytest.raises(KeyError, match=r"no \[radios.nope\]"):
        cfg.radio("nope")


def test_flashed_overlay_wins(toml, tmp_path):
    (tmp_path / "fw" / "flashed.json").write_text(json.dumps({
        "0001": {"protocol": "meshcore", "version": "1.18.0", "at": "2026-11-08T10:00:00"}}))
    cfg = config.load(toml)
    assert cfg.radio("base").protocol == "meshcore"
    assert cfg.radio("base").firmware == "1.18.0"
    assert cfg.radio("spare").protocol == "meshtastic"   # untouched
    assert cfg.radio("spare").firmware is None


def test_phones(toml):
    cfg = config.load(toml)
    assert set(cfg.phones) == {"phone", "sim", "a16"}
    assert cfg.phone is cfg.phones["phone"]            # [phone] is the default
    assert cfg.phone_named(None) is cfg.phone
    assert cfg.phone.platform == "ios" and cfg.phone.demo is False
    assert cfg.phone.launch_args() == ["-MeshBench"]
    assert cfg.phone.tier == "T2"
    sim = cfg.phone_named("sim")
    assert sim.simulator and sim.demo is True          # simulator: demo by default
    assert sim.tier == "T1"
    assert sim.launch_args() == ["-MeshBench", "-MeshDemo"]
    assert sim.bundle_id == "com.andybrunker.meshAnalyzer"
    a16 = cfg.phone_named("a16")
    assert a16.launch_args() == ["-MeshBench", "-benchPort", "8766", "-MeshDemo", "-demoScreen", "map"]
    with pytest.raises(KeyError, match=r"no \[phones.nope\]"):
        cfg.phone_named("nope")


def test_phones_only_first_is_default(tmp_path):
    p = tmp_path / "bench.toml"
    p.write_text('[phones.sim]\nplatform = "ios-sim"\nid = "iPhone 18 Pro Max"\n'
                 '[phones.se]\nplatform = "ios"\nid = "X"\n')
    cfg = config.load(p)
    assert cfg.phone is cfg.phones["sim"]
    assert cfg.phone.name == "sim"


def test_no_phone(tmp_path):
    p = tmp_path / "bench.toml"
    p.write_text("[bench]\n")
    cfg = config.load(p)
    assert cfg.phone is None and cfg.phones == {}
    with pytest.raises(KeyError):
        cfg.phone_named(None)
    assert cfg.reports_dir.name == "reports"            # defaults expanded


def test_bad_platform(tmp_path):
    p = tmp_path / "bench.toml"
    p.write_text('[phone]\nplatform = "windows"\nid = "X"\n')
    with pytest.raises(ValueError, match="platform"):
        config.load(p)


def test_missing_file(tmp_path):
    with pytest.raises(FileNotFoundError, match="bench.toml.example"):
        config.load(tmp_path / "bench.toml")
