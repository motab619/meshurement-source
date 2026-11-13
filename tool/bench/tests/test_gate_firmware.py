# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""firmware: tags, release resolution, zip members, fetch from a fake zip."""

from __future__ import annotations

import json
import shutil
import zipfile

import pytest

from bench import firmware
from bench.firmware import BOARDS, cached_version, _mt_members, _tag_version, fetch, resolve

try:  # tests/ may or may not be a package in the merged tree
    from .gate_fixtures import no_network  # noqa: F401
except ImportError:
    from gate_fixtures import no_network  # noqa: F401

V = "2.8.1.8e6a88d"
HELTEC = BOARDS["heltec-v3"]
T1000 = BOARDS["t1000-e"]

RELEASES = [
    {"tag_name": "v2.8.2.0badc0d", "prerelease": True, "published_at": "2026-11-01T00:00:00Z",
     "assets": [{"name": f"firmware-esp32s3-2.8.2.0badc0d.zip", "browser_download_url": "https://x/a.zip", "size": 1}]},
    {"tag_name": "v9.9.9.draft00", "draft": True, "assets": []},
    {"tag_name": "nightly", "assets": []},
    {"tag_name": f"v{V}", "prerelease": False, "published_at": "2026-10-20T00:00:00Z",
     "assets": [{"name": f"firmware-esp32s3-{V}.zip", "browser_download_url": "https://x/esp.zip", "size": 2},
                {"name": f"firmware-nrf52840-{V}.zip", "browser_download_url": "https://x/nrf.zip", "size": 3}]},
    {"tag_name": "v2.7.26.abc1234", "prerelease": False, "published_at": "2026-09-01T00:00:00Z", "assets": []},
]


@pytest.fixture
def gh(monkeypatch):
    calls = []

    def fake(url):
        calls.append(url)
        return RELEASES if "page=1" in url else []

    monkeypatch.setattr(firmware, "_gh_json", fake)
    return calls


def test_tag_version():
    assert _tag_version("meshtastic", f"v{V}") == V
    assert _tag_version("meshtastic", "v2.8.1") is None          # needs the commit part
    assert _tag_version("meshtastic", "nightly") is None
    assert _tag_version("meshcore", "companion-v1.18.0") == "1.18.0"
    assert _tag_version("meshcore", "v1.18.0") is None
    assert _tag_version("meshcore", "repeater-v1.18.0") is None


def test_releases_and_resolve(gh):
    rels = firmware.releases("meshtastic")
    assert [r.version for r in rels] == ["2.8.2.0badc0d", V, "2.7.26.abc1234"]  # no draft, no odd tag
    assert rels[0].prerelease and not rels[1].prerelease
    assert rels[1].published == "2026-10-20"
    assert rels[1].assets[f"firmware-nrf52840-{V}.zip"] == {"url": "https://x/nrf.zip", "size": 3}
    assert resolve("meshtastic", "2.8.1").version == V          # short version -> full
    assert resolve("meshtastic", V).version == V
    assert resolve("meshtastic", "latest").version == V         # newest stable
    assert resolve("meshtastic", "pre").version == "2.8.2.0badc0d"
    with pytest.raises(LookupError, match="no meshtastic release '2.6'"):
        resolve("meshtastic", "2.6")
    assert "meshtastic/firmware/releases" in gh[0]


def test_mt_members():
    m = _mt_members(HELTEC, V)
    assert m["required"] == [f"littlefs-heltec-v3-{V}.bin"]
    assert f"firmware-heltec-v3-{V}.factory.bin" in m["optional"]
    assert "mt-esp32s3-ota.bin" in m["optional"] and "bleota-s3.bin" in m["optional"]
    n = _mt_members(T1000, V)
    assert n["required"] == [f"firmware-tracker-t1000-e-{V}-ota.zip"]
    assert n["optional"] == [f"firmware-tracker-t1000-e-{V}.uf2"]


def _esp_zip(path):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr(f"firmware-heltec-v3-{V}.factory.bin", b"F" * 64)
        z.writestr(f"firmware-heltec-v3-{V}.bin", b"f" * 32)
        z.writestr(f"littlefs-heltec-v3-{V}.bin", b"L" * 16)
        z.writestr("mt-esp32s3-ota.bin", b"O" * 8)
        z.writestr(f"firmware-heltec-v3-{V}.mt.json", json.dumps({"part": [
            {"subtype": "ota_0", "offset": "0x10000"},
            {"subtype": "ota_1", "offset": "0x270000"},
            {"subtype": "spiffs", "offset": "0x310000"}]}))
        z.writestr(f"firmware-other-board-{V}.bin", b"x")   # not extracted
    return path


def test_fetch_meshtastic_esp32(tmp_path, gh, monkeypatch):
    src = _esp_zip(tmp_path / "src.zip")
    downloads = []

    def fake_download(url, dest, log):
        downloads.append(url)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(src, dest)
        return dest

    monkeypatch.setattr(firmware, "_download", fake_download)
    cache = tmp_path / "cache"
    img = fetch(cache, "meshtastic", "2.8.1", HELTEC, lambda s: None)
    assert downloads == ["https://x/esp.zip"]
    assert img.protocol == "meshtastic" and img.version == V and img.board is HELTEC
    out = cache / "meshtastic" / V / "heltec-v3"
    assert img.files["main"] == out / f"firmware-heltec-v3-{V}.factory.bin"
    assert img.files["littlefs"] == out / f"littlefs-heltec-v3-{V}.bin"
    assert img.files["ota"] == out / "mt-esp32s3-ota.bin"
    assert img.files["meta"].exists()
    assert img.offsets == {"ota": 0x270000, "littlefs": 0x310000}     # from .mt.json
    assert not (out / f"firmware-other-board-{V}.bin").exists()
    assert "factory.bin" in img.summary and "heltec-v3" in img.summary

    # Second fetch: cached, no GitHub, no download, same answer (offline use).
    monkeypatch.setattr(firmware, "_gh_json", lambda url: pytest.fail("network"))
    again = fetch(cache, "meshtastic", "2.8", HELTEC, lambda s: None)
    assert downloads == ["https://x/esp.zip"]
    assert again.files == img.files and again.offsets == img.offsets


def test_fetch_meshtastic_default_offsets_without_meta(tmp_path, gh, monkeypatch):
    src = tmp_path / "src.zip"
    with zipfile.ZipFile(src, "w") as z:
        z.writestr(f"firmware-heltec-v3-{V}.bin", b"f")
        z.writestr(f"littlefs-heltec-v3-{V}.bin", b"L")
        z.writestr("bleota-s3.bin", b"O")                 # 2.7-style OTA image
    monkeypatch.setattr(firmware, "_download", lambda url, dest, log: (dest.parent.mkdir(parents=True, exist_ok=True), shutil.copy(src, dest), dest)[2])
    img = fetch(tmp_path / "cache", "meshtastic", V, HELTEC, lambda s: None)
    assert img.files["main"].name == f"firmware-heltec-v3-{V}.bin"   # no factory image
    assert img.files["ota"].name == "bleota-s3.bin"
    assert img.offsets == {"ota": 0x260000, "littlefs": 0x300000}
    assert "meta" not in img.files


def test_fetch_meshtastic_nrf52(tmp_path, gh, monkeypatch):
    src = tmp_path / "src.zip"
    with zipfile.ZipFile(src, "w") as z:
        z.writestr(f"firmware-tracker-t1000-e-{V}-ota.zip", b"PK")
        z.writestr(f"firmware-tracker-t1000-e-{V}.uf2", b"UF2")
    monkeypatch.setattr(firmware, "_download", lambda url, dest, log: (dest.parent.mkdir(parents=True, exist_ok=True), shutil.copy(src, dest), dest)[2])
    img = fetch(tmp_path / "cache", "meshtastic", "2.8.1", T1000, lambda s: None)
    assert list(img.files) == ["main"]
    assert img.files["main"].name == f"firmware-tracker-t1000-e-{V}-ota.zip"
    assert img.offsets == {}


def test_fetch_missing_required_member(tmp_path, gh, monkeypatch):
    src = tmp_path / "src.zip"
    with zipfile.ZipFile(src, "w") as z:
        z.writestr("readme.txt", b"nothing useful")
    monkeypatch.setattr(firmware, "_download", lambda url, dest, log: (dest.parent.mkdir(parents=True, exist_ok=True), shutil.copy(src, dest), dest)[2])
    with pytest.raises(LookupError, match="lacks"):
        fetch(tmp_path / "cache", "meshtastic", "2.8.1", HELTEC, lambda s: None)


def test_fetch_missing_asset(tmp_path, gh):
    with pytest.raises(LookupError, match="has no asset"):
        fetch(tmp_path / "cache", "meshtastic", "2.8.2", T1000, lambda s: None)  # 2.8.2 ships no nrf52840 zip


def testcached_version(tmp_path):
    cache = tmp_path / "cache"
    (cache / "meshtastic" / "2.7.26.abc1234").mkdir(parents=True)
    (cache / "meshtastic" / V).mkdir()
    (cache / "meshcore" / "companion-v1.18.0").mkdir(parents=True)
    assert cached_version(cache, "meshtastic", "2.8.1") == V
    assert cached_version(cache, "meshtastic", "2.8") == V
    assert cached_version(cache, "meshtastic", V) == V
    assert cached_version(cache, "meshtastic", "2.7") == "2.7.26.abc1234"
    assert cached_version(cache, "meshtastic", "2.9") is None
    assert cached_version(cache, "meshcore", "1.18.0") == "1.18.0"
    assert cached_version(cache, "meshcore", "1.18") == "1.18.0"
    assert cached_version(tmp_path / "empty", "meshcore", "1") is None
