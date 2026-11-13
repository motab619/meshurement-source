# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Firmware: GitHub release downloads (cached) and flashing, both protocols.

Sources, cached under `[bench].firmware_cache` (downloads are untrusted data:
each release gets its own folder, nothing in it is executed on the Mac):

- Meshtastic: `meshtastic/firmware`, tag `v<version>` (versions carry the
  commit: `2.8.1.8e6a88d`). Per-platform zips `firmware-esp32s3-<ver>.zip`,
  `firmware-nrf52840-<ver>.zip`. Inside, per board: ESP32
  `firmware-<target>-<ver>.factory.bin` (whole flash image), `littlefs-…bin`,
  `mt-<mcu>-ota.bin` (2.8; `bleota-s3.bin` on 2.7) and `.mt.json` with the
  partition offsets; nRF52 `firmware-<target>-<ver>-ota.zip`, a Nordic DFU
  package (adafruit-nrfutil `dfu genpkg`), plus a `.uf2`.
- MeshCore: `meshcore-dev/MeshCore`, tag `companion-v<version>`; assets
  `<Board>_companion_radio_ble-v<ver>-<sha>-merged.bin` (ESP32, whole flash)
  and `…ble-v<ver>-<sha>.zip` (nRF52 DFU package). The `ble` build is the one
  the app talks to; the `usb` build has no Bluetooth.

Flashing (checked on the bench 2026-11-08):

- ESP32 (Heltec V3): esptool `erase-flash`, `write-flash 0x0 <factory/merged>`
  and, for Meshtastic, the OTA and littlefs images at the `.mt.json` offsets
  (what `bin/device-install.sh` does). The CP2102 pulls the chip into its
  bootloader on its own. Everything on the radio is wiped, Bluetooth bonds too.
- nRF52 (T1000-E, Wio Tracker L1): `adafruit-nrfutil dfu serial --touch 1200
  --singlebank` with the DFU package. Opening the port at 1200 baud and closing
  it drops the running app into the Adafruit bootloader in *serial-only* DFU
  mode: no UF2 volume, the USB product id changes (T1000-E 239a:8029 →
  239a:0057) and the CDC port stays. Works for Meshtastic and MeshCore (both
  on the Adafruit core); 19 s for a 300 KB image. The bootloader's own flash
  pages (settings in InternalFS) are not erased, so same-protocol reflashes
  keep the radio's settings.

After a Meshtastic flash the radio needs a region and NO_PIN Bluetooth before
it is usable: `prepare_fresh` writes both in one settings transaction. A
MeshCore `ble` build is silent on USB, so its only check is the USB id back in
app mode (the app's BLE scan sees `MeshCore-<name>` afterwards).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
import urllib.request
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from . import live, ports
from .config import RadioConfig

Log = Callable[[str], None]

_REPOS = {"meshtastic": "meshtastic/firmware", "meshcore": "meshcore-dev/MeshCore"}


@dataclass(frozen=True)
class Board:
    name: str          # bench.toml `board`
    mcu: str           # esp32s3 | nrf52840
    mt_target: str     # Meshtastic platformio target (file names)
    mt_platform: str   # Meshtastic release zip platform
    mc_name: str       # MeshCore asset prefix


BOARDS: dict[str, Board] = {
    "heltec-v3": Board("heltec-v3", "esp32s3", "heltec-v3", "esp32s3", "Heltec_v3"),
    "t1000-e": Board("t1000-e", "nrf52840", "tracker-t1000-e", "nrf52840", "t1000e"),
    "wio-tracker-l1": Board("wio-tracker-l1", "nrf52840", "seeed_wio_tracker_L1", "nrf52840",
                            "WioTrackerL1"),
}


def board_of(radio: RadioConfig) -> Board:
    try:
        return BOARDS[radio.board]
    except KeyError:
        raise KeyError(f"board {radio.board!r} not in firmware.BOARDS {list(BOARDS)}") from None


# -- GitHub ------------------------------------------------------------------

@dataclass
class Release:
    protocol: str
    version: str
    tag: str
    prerelease: bool
    published: str
    assets: dict[str, dict[str, Any]] = field(default_factory=dict)  # name -> {url, size}


def _gh_json(url: str) -> Any:
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "meshurement-bench"}
    tok = os.environ.get("GITHUB_TOKEN")
    if tok:
        headers["Authorization"] = f"Bearer {tok}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as r:
        return json.loads(r.read().decode())


def _tag_version(protocol: str, tag: str) -> str | None:
    if protocol == "meshtastic":
        return tag[1:] if re.fullmatch(r"v\d+\.\d+\.\d+\.[0-9a-f]+", tag) else None
    m = re.fullmatch(r"companion-v(\d+\.\d+\.\d+)", tag)
    return m.group(1) if m else None


def releases(protocol: str, *, limit: int = 30) -> list[Release]:
    """Published releases of the protocol's firmware, newest first."""
    out: list[Release] = []
    page = 1
    while len(out) < limit and page <= 3:
        raw = _gh_json(f"https://api.github.com/repos/{_REPOS[protocol]}/releases"
                       f"?per_page=50&page={page}")
        if not raw:
            break
        for r in raw:
            if r.get("draft"):
                continue
            v = _tag_version(protocol, r["tag_name"])
            if v is None:
                continue
            out.append(Release(protocol, v, r["tag_name"], bool(r.get("prerelease")),
                               (r.get("published_at") or "")[:10],
                               {a["name"]: {"url": a["browser_download_url"], "size": a["size"]}
                                for a in r.get("assets", [])}))
        page += 1
    return out[:limit]


def resolve(protocol: str, version: str) -> Release:
    """`2.8.1` → the 2.8.1.<commit> release; `latest` = newest stable, `pre` = newest."""
    rels = releases(protocol)
    if version == "latest":
        stable = [r for r in rels if not r.prerelease]
        return stable[0] if stable else rels[0]
    if version == "pre":
        return rels[0]
    for r in rels:
        if r.version == version or r.version.startswith(version + "."):
            return r
    raise LookupError(f"no {protocol} release {version!r}; have {[r.version for r in rels[:8]]}…")


def _download(url: str, dest: Path, log: Log) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        return dest
    tmp = dest.with_suffix(dest.suffix + ".part")
    log(f"downloading {dest.name} from {url.split('/releases/')[0]}")
    req = urllib.request.Request(url, headers={"User-Agent": "meshurement-bench"})
    with urllib.request.urlopen(req, timeout=120) as r, tmp.open("wb") as f:
        total = int(r.headers.get("Content-Length") or 0)
        done = 0
        while chunk := r.read(1 << 20):
            f.write(chunk)
            done += len(chunk)
            if total and done % (32 << 20) < (1 << 20):
                log(f"  {done / 1e6:.0f} / {total / 1e6:.0f} MB")
    tmp.rename(dest)
    log(f"  {dest.stat().st_size / 1e6:.1f} MB")
    return dest


# -- images ------------------------------------------------------------------

@dataclass
class Image:
    protocol: str
    version: str
    board: Board
    files: dict[str, Path]      # role -> path: main (+ ota, littlefs, meta on Meshtastic ESP32)
    offsets: dict[str, int] = field(default_factory=dict)  # ota, littlefs (ESP32)

    @property
    def summary(self) -> str:
        return f"{self.protocol} {self.version} for {self.board.name}: " + ", ".join(
            p.name for p in self.files.values())


def cached_version(cache: Path, protocol: str, version: str) -> str | None:
    """A fully qualified version already in the cache (offline use)."""
    root = cache / protocol
    if not root.exists():
        return None
    for d in sorted(root.iterdir(), reverse=True):
        v = d.name.removeprefix("companion-v")
        if v == version or v.startswith(version + "."):
            return v
    return None


def fetch(cache: Path, protocol: str, version: str, board: Board, log: Log) -> Image:
    """Download (if needed) and unpack what `flash` needs for one board."""
    if protocol == "meshtastic":
        return _fetch_meshtastic(cache, version, board, log)
    if protocol == "meshcore":
        return _fetch_meshcore(cache, version, board, log)
    raise ValueError(protocol)


def _fetch_meshtastic(cache: Path, version: str, board: Board, log: Log) -> Image:
    v = cached_version(cache, "meshtastic", version)
    rel: Release | None = None
    if v is None or not (cache / "meshtastic" / v / board.mt_target).exists():
        rel = resolve("meshtastic", version)
        v = rel.version
    root = cache / "meshtastic" / v
    out = root / board.mt_target
    want = _mt_members(board, v)
    if not all((out / n).exists() for n in want["required"]):
        zname = f"firmware-{board.mt_platform}-{v}.zip"
        zpath = root / zname
        if not zpath.exists():
            rel = rel or resolve("meshtastic", v)
            if zname not in rel.assets:
                raise LookupError(f"{rel.tag} has no asset {zname}")
            _download(rel.assets[zname]["url"], zpath, log)
        out.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(zpath) as z:
            names = set(z.namelist())
            for n in want["required"] + want["optional"]:
                if n in names and not (out / n).exists():
                    z.extract(n, out)
        missing = [n for n in want["required"] if not (out / n).exists()]
        if missing:
            raise LookupError(f"{zname} lacks {missing}")
    files: dict[str, Path] = {}
    offsets: dict[str, int] = {}
    if board.mcu.startswith("esp32"):
        fac = out / f"firmware-{board.mt_target}-{v}.factory.bin"
        files["main"] = fac if fac.exists() else out / f"firmware-{board.mt_target}-{v}.bin"
        files["littlefs"] = out / f"littlefs-{board.mt_target}-{v}.bin"
        for ota in (f"mt-{board.mcu}-ota.bin", "bleota-s3.bin" if board.mcu == "esp32s3" else "bleota.bin"):
            if (out / ota).exists():
                files["ota"] = out / ota
                break
        offsets = {"ota": 0x260000, "littlefs": 0x300000}
        meta = out / f"firmware-{board.mt_target}-{v}.mt.json"
        if meta.exists():
            files["meta"] = meta
            for part in json.loads(meta.read_text()).get("part", []):
                if part.get("subtype") == "ota_1":
                    offsets["ota"] = int(part["offset"], 16)
                elif part.get("subtype") == "spiffs":
                    offsets["littlefs"] = int(part["offset"], 16)
    else:
        files["main"] = out / f"firmware-{board.mt_target}-{v}-ota.zip"
    return Image("meshtastic", v, board, files, offsets)


def _mt_members(board: Board, v: str) -> dict[str, list[str]]:
    t = board.mt_target
    if board.mcu.startswith("esp32"):
        return {"required": [f"littlefs-{t}-{v}.bin"],
                "optional": [f"firmware-{t}-{v}.factory.bin", f"firmware-{t}-{v}.bin",
                             f"firmware-{t}-{v}.mt.json", f"mt-{board.mcu}-ota.bin",
                             "bleota-s3.bin", "bleota.bin"]}
    return {"required": [f"firmware-{t}-{v}-ota.zip"], "optional": [f"firmware-{t}-{v}.uf2"]}


def _fetch_meshcore(cache: Path, version: str, board: Board, log: Log) -> Image:
    v = cached_version(cache, "meshcore", version) or version
    root = cache / "meshcore" / f"companion-v{v}"
    ext = "-merged.bin" if board.mcu.startswith("esp32") else ".zip"
    pat = f"{board.mc_name}_companion_radio_ble-v{v}-*{ext}"
    have = sorted(root.glob(pat)) if root.exists() else []
    if not have:
        rel = resolve("meshcore", version)
        v, root = rel.version, cache / "meshcore" / rel.tag
        rx = re.compile(re.escape(f"{board.mc_name}_companion_radio_ble-v{v}-") + r"[0-9a-f]+"
                        + re.escape(ext) + "$")
        names = [n for n in rel.assets if rx.match(n)]
        if not names:
            raise LookupError(f"{rel.tag} has no {board.mc_name} ble asset ({ext})")
        have = [_download(rel.assets[names[0]]["url"], root / names[0], log)]
    return Image("meshcore", v, board, {"main": have[0]})


# -- flashing ----------------------------------------------------------------

class FlashError(RuntimeError):
    pass


@dataclass
class FlashResult:
    radio: str
    protocol: str
    version: str
    seconds: float
    verified: str   # how we know it took


def _run(cmd: list[str], log: Log, *, timeout: int = 600) -> str:
    log("$ " + " ".join(cmd[cmd.index("-m") + 1:] if "-m" in cmd else cmd))
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        raise FlashError(f"{cmd[-1] if len(cmd) < 3 else cmd[cmd.index('-m') + 1]} failed:\n"
                         f"{(r.stdout + r.stderr).strip()[-2000:]}")
    return r.stdout


def flash(radio: RadioConfig, image: Image, log: Log) -> FlashResult:
    """Write `image` to `radio` and wait for it to come back on USB."""
    t0 = time.time()
    port = radio.port()
    log(f"flashing {radio.name} on {port}: {image.summary}")
    live.emit("flash", radio=radio.name, phase="start", protocol=image.protocol,
              version=image.version)
    ok = False
    try:
        if image.board.mcu.startswith("esp32"):
            _flash_esp32(port, image, log)
        else:
            _flash_nrf52(port, image, log)
        port = _wait_port(radio, log)
        ok = True
    finally:
        live.emit("flash", radio=radio.name, phase="end", protocol=image.protocol,
                  version=image.version, ok=ok)
    verified = f"usb back in app mode on {port}"
    return FlashResult(radio.name, image.protocol, image.version, time.time() - t0, verified)


def _flash_esp32(port: str, image: Image, log: Log) -> None:
    base = [sys.executable, "-m", "esptool", "--chip", image.board.mcu, "--port", port,
            "--baud", "921600"]
    _run(base + ["erase-flash"], log)
    writes = [("0x0", image.files["main"])]
    if image.protocol == "meshtastic":
        if "ota" in image.files:
            writes.append((hex(image.offsets["ota"]), image.files["ota"]))
        writes.append((hex(image.offsets["littlefs"]), image.files["littlefs"]))
    args: list[str] = []
    for off, path in writes:
        args += [off, str(path)]
    _run(base + ["write-flash", *args], log)


def _flash_nrf52(port: str, image: Image, log: Log) -> None:
    pkg = image.files["main"]
    with zipfile.ZipFile(pkg) as z:
        man = json.loads(z.read("manifest.json"))["manifest"]["application"]["init_packet_data"]
    log(f"DFU package: device_type {man.get('device_type')} softdevice_req "
        f"{[hex(x) for x in man.get('softdevice_req', [])]}")
    _run([sys.executable, "-m", "nordicsemi", "dfu", "serial", "--package", str(pkg),
          "-p", port, "-b", "115200", "--singlebank", "--touch", "1200"], log, timeout=300)


def _wait_port(radio: RadioConfig, log: Log, timeout: float = 60) -> str:
    """The radio's serial port, once it is back and not in a bootloader."""
    end = time.time() + timeout
    while time.time() < end:
        for p in ports.list_ports():
            if p.serial_number == radio.serial and not p.in_bootloader:
                return p.device
        time.sleep(1)
    raise FlashError(f"{radio.name} did not come back on USB within {timeout}s")


# -- what is flashed where ---------------------------------------------------

def flashed_state_path(cache: Path) -> Path:
    return cache / "flashed.json"


def record_flash(cache: Path, radio: RadioConfig, res: FlashResult) -> None:
    """`flashed.json` in the cache: serial -> {protocol, version, at}; `config.load`
    overlays it on bench.toml so the rest of the bench knows what a radio runs."""
    p = flashed_state_path(cache)
    state = json.loads(p.read_text()) if p.exists() else {}
    state[radio.serial] = {"protocol": res.protocol, "version": res.version,
                           "at": time.strftime("%Y-%m-%dT%H:%M:%S")}
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(state, indent=2) + "\n")
