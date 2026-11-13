# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""config.py: one `[phone]` or several `[phones.<name>]`, and `--phone` lookup."""

from __future__ import annotations

from pathlib import Path

import pytest

from bench import config

HEAD = """
[bench]
reports_dir = "{d}/reports"
firmware_cache = "{d}/firmware"

[radios.base]
serial = "0001"
board = "heltec-v3"
protocol = "meshtastic"
role = "base"
"""


def _load(tmp_path: Path, body: str) -> config.BenchConfig:
    p = tmp_path / "bench.toml"
    p.write_text(HEAD.format(d=tmp_path) + body)
    return config.load(p)


def test_single_phone_table_is_the_default(tmp_path):
    cfg = _load(tmp_path, '[phone]\nplatform = "ios"\nid = "0000-UDID"\n')
    assert list(cfg.phones) == ["phone"]
    assert cfg.phone.platform == "ios"
    assert cfg.phone.bundle_id == "com.andybrunker.meshAnalyzer"
    assert cfg.phone_named(None) is cfg.phone
    assert cfg.phone_named("ios") is cfg.phone


def test_phones_tables_first_is_default_and_names_pick(tmp_path):
    cfg = _load(tmp_path, '''
[phones.se]
platform = "ios"
id = "0000-UDID"

[phones.android]
platform = "android"
id = "R5CY52X8GVN"
''')
    assert list(cfg.phones) == ["se", "android"]
    assert cfg.phone.name == "se"
    a = cfg.phone_named("android")
    assert a.platform == "android" and a.id == "R5CY52X8GVN"
    # Android gets the Android application id, never the iOS bundle id.
    assert a.bundle_id == "com.plateaunerd.meshurement"
    assert cfg.phone_named("se").bundle_id == "com.andybrunker.meshAnalyzer"


def test_legacy_phone_table_comes_before_phones(tmp_path):
    cfg = _load(tmp_path, '''
[phone]
platform = "ios"
id = "0000-UDID"

[phones.a16]
platform = "android"
id = "R5CY52X8GVN"
bundle_id = "com.example.custom"
''')
    assert list(cfg.phones) == ["phone", "a16"]
    assert cfg.phone_named("android").bundle_id == "com.example.custom"


def test_unknown_or_ambiguous_phone(tmp_path):
    cfg = _load(tmp_path, '''
[phones.a]
platform = "android"
id = "1"

[phones.b]
platform = "android"
id = "2"
''')
    with pytest.raises(KeyError, match=r"no \[phones.android\]"):
        cfg.phone_named("android")   # two Androids: the platform is ambiguous
    with pytest.raises(KeyError, match=r"no \[phones.zzz\]"):
        cfg.phone_named("zzz")


def test_no_phone(tmp_path):
    cfg = _load(tmp_path, "")
    assert cfg.phone is None
    with pytest.raises(KeyError, match="no \\[phone\\]"):
        cfg.phone_named(None)
