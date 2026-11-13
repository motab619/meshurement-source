# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""firmware.resolve against a fake GitHub release list (no network)."""

from __future__ import annotations

import pytest

from bench import firmware


def _rel(tag: str, pre: bool = False, draft: bool = False) -> dict:
    return {"tag_name": tag, "prerelease": pre, "draft": draft, "published_at": "2026-11-01T00:00:00Z",
            "assets": [{"name": f"firmware-esp32s3-{tag[1:]}.zip", "browser_download_url": "u", "size": 1}]}


MT_RELEASES = [
    _rel("v2.8.2.1111111", pre=True),
    _rel("v2.8.1.8e6a88d"),
    _rel("v2.8.0.deadbee", draft=True),
    _rel("v2.7.26.abcdef0"),
    _rel("v2.7.19.0123456"),
    {"tag_name": "nightly", "prerelease": True, "assets": []},   # not a version tag
]
MC_RELEASES = [
    {"tag_name": "companion-v1.19.0", "prerelease": True, "assets": []},
    {"tag_name": "companion-v1.18.0", "prerelease": False, "assets": []},
    {"tag_name": "repeater-v1.18.0", "prerelease": False, "assets": []},
]


@pytest.fixture
def fake_github(monkeypatch):
    calls: list[str] = []

    def gh(url: str):
        calls.append(url)
        if "page=1" not in url:
            return []
        return MT_RELEASES if "meshtastic/firmware" in url else MC_RELEASES

    monkeypatch.setattr(firmware, "_gh_json", gh)
    return calls


def test_releases_skip_drafts_and_odd_tags(fake_github):
    rels = firmware.releases("meshtastic")
    assert [r.version for r in rels] == ["2.8.2.1111111", "2.8.1.8e6a88d", "2.7.26.abcdef0", "2.7.19.0123456"]
    assert rels[0].prerelease and not rels[1].prerelease
    assert rels[1].tag == "v2.8.1.8e6a88d"
    assert "firmware-esp32s3-2.8.1.8e6a88d.zip" in rels[1].assets
    mc = firmware.releases("meshcore")
    assert [(r.version, r.tag) for r in mc] == [("1.19.0", "companion-v1.19.0"), ("1.18.0", "companion-v1.18.0")]


def test_resolve_prefix_latest_pre_and_full(fake_github):
    assert firmware.resolve("meshtastic", "2.8.1").version == "2.8.1.8e6a88d"
    assert firmware.resolve("meshtastic", "2.8.1.8e6a88d").version == "2.8.1.8e6a88d"
    assert firmware.resolve("meshtastic", "2.7").version == "2.7.26.abcdef0", "newest 2.7.x"
    assert firmware.resolve("meshtastic", "latest").version == "2.8.1.8e6a88d", "newest stable"
    assert firmware.resolve("meshtastic", "pre").version == "2.8.2.1111111"
    assert firmware.resolve("meshcore", "1.18.0").tag == "companion-v1.18.0"
    assert firmware.resolve("meshcore", "latest").version == "1.18.0"
    assert firmware.resolve("meshcore", "pre").version == "1.19.0"


def test_resolve_unknown_version_names_what_exists(fake_github):
    with pytest.raises(LookupError, match="2.6.0"):
        firmware.resolve("meshtastic", "2.6.0")
    # "2.8" must not match "2.8.1" as a bare string prefix of "2.8.1..." — it should,
    # as a version prefix (2.8 → newest 2.8.x), but "2.8.1" must not match "2.8.10".
    assert firmware.resolve("meshtastic", "2.8").version == "2.8.2.1111111"


def test_prefix_match_is_by_version_component(monkeypatch):
    monkeypatch.setattr(firmware, "_gh_json",
                        lambda url: [_rel("v2.8.10.aaaaaaa"), _rel("v2.8.1.bbbbbbb")] if "page=1" in url else [])
    assert firmware.resolve("meshtastic", "2.8.1").version == "2.8.1.bbbbbbb"


def test_cached_version(tmp_path):
    (tmp_path / "meshtastic" / "2.8.1.8e6a88d").mkdir(parents=True)
    (tmp_path / "meshtastic" / "2.7.26.abcdef0").mkdir(parents=True)
    (tmp_path / "meshcore" / "companion-v1.18.0").mkdir(parents=True)
    assert firmware.cached_version(tmp_path, "meshtastic", "2.8.1") == "2.8.1.8e6a88d"
    assert firmware.cached_version(tmp_path, "meshtastic", "2.8") == "2.8.1.8e6a88d"
    assert firmware.cached_version(tmp_path, "meshtastic", "2.9") is None
    assert firmware.cached_version(tmp_path, "meshcore", "1.18.0") == "1.18.0"
    assert firmware.cached_version(tmp_path / "nope", "meshtastic", "2.8.1") is None


def test_board_of_unknown_board_is_a_clear_error():
    from bench.config import RadioConfig
    with pytest.raises(KeyError, match="rak4631"):
        firmware.board_of(RadioConfig("x", "1", "rak4631", "meshtastic", "base"))
    assert firmware.board_of(RadioConfig("x", "1", "heltec-v3", "meshtastic", "base")).mcu == "esp32s3"
