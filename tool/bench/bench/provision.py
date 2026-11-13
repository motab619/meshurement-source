# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Put a radio on a firmware and make it usable: what `bench flash` and
`bench matrix` share (fetch → flash → record → prepare → verify).

After a Meshtastic flash the radio needs a LoRa region and PIN-less
Bluetooth (`meshtastic.prepare_fresh`); the version it reports over USB is
checked against the image. An ESP32 read over USB ends with a reboot
(`meshtastic.serial_session`). The radio-setup scenario's cached "before"
snapshot is dropped: a flashed radio has a new node id on 2.8.
"""

from __future__ import annotations

import time
from dataclasses import dataclass

from . import firmware
from .config import BenchConfig, RadioConfig

Log = firmware.Log


class PrepareError(RuntimeError):
    """The radio came back from the flash but does not report the version."""


@dataclass
class Provisioned:
    flash: firmware.FlashResult
    prepared: list[str]            # what prepare_fresh changed
    reported_version: str | None   # what the radio says over USB (Meshtastic)
    bond_lost: bool                # ESP32 erase: iOS must Forget This Device


def bond_lost_by_flash(radio: RadioConfig) -> bool:
    """An ESP32 `erase-flash` wipes the Bluetooth bond and iOS then refuses
    to connect (`Peer removed pairing information`) until the user forgets
    the device on the phone; nRF52 DFU keeps bonds (bench 2026-11-08)."""
    return firmware.board_of(radio).mcu.startswith("esp32")


def flash_radio(cfg: BenchConfig, radio: RadioConfig, protocol: str, version: str,
                log: Log, *, boot_wait: int = 30, prepare: bool = True,
                dry_run: bool = False) -> Provisioned | firmware.Image:
    """Fetch (cached) and flash `protocol version` onto `radio`, record it in
    flashed.json, then (Meshtastic) set the region + NO_PIN and read the
    version back. `dry_run` stops after the fetch and returns the Image."""
    from .radios import meshtastic as mt
    from .scenarios import radio_setup

    board = firmware.board_of(radio)
    image = firmware.fetch(cfg.firmware_cache, protocol, version, board, log)
    log(f"{radio.name} ({board.name}, now {radio.protocol} {radio.firmware or '?'}) "
        f"<- {image.summary}")
    if dry_run:
        return image
    res = firmware.flash(radio, image, log)
    log(f"flashed in {res.seconds:.0f}s; {res.verified}")
    firmware.record_flash(cfg.firmware_cache, radio, res)
    radio_setup.invalidate(radio.serial)
    out = Provisioned(res, [], None, bond_lost_by_flash(radio))
    if protocol == "meshtastic" and prepare:
        log(f"waiting {boot_wait}s for the first boot, then region {cfg.region} + Bluetooth NO_PIN")
        time.sleep(boot_wait)
        with mt.serial_session(radio, log) as port:
            out.prepared = mt.prepare_fresh(port, region=cfg.region)
            log(f"prepared: {out.prepared or 'nothing to change'}")
            snap = mt.snapshot(port)
        out.reported_version = snap.firmware_version or ""
        ok = out.reported_version.startswith(image.version.rsplit(".", 1)[0])
        log(f"radio reports {snap.node_id} fw {snap.firmware_version} region "
            f"{snap.lora.get('region')} bluetooth {snap.bluetooth.get('mode')}: "
            f"{'matches' if ok else 'VERSION MISMATCH'}")
        if not ok:
            raise PrepareError(f"{radio.name} reports firmware {snap.firmware_version!r}, "
                               f"flashed {image.version}")
    elif protocol == "meshcore":
        log("MeshCore ble build is silent on USB: check the app's scan for MeshCore-<name>")
    if out.bond_lost:
        log(f"{radio.name} is an ESP32: its Bluetooth bond is gone; on the phone, Settings → "
            "Bluetooth → Forget This Device before the app connects to it again")
    return out
