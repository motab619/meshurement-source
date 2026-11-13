# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""What is plugged in, without opening anything.

Opening a radio's serial port has side effects (a Heltec V3 resets; its
Bluetooth stays off until a reboot once an API client connects), so this
module only reads USB descriptors.
"""

from __future__ import annotations

from dataclasses import dataclass

from serial.tools import list_ports as _lp

# USB vendor/product ids seen on the bench (2026-11-07). Guesses only;
# bench.toml decides what a serial number is.
_KNOWN: dict[tuple[int, int | None], str] = {
    (0x10C4, 0xEA60): "heltec-v3 (CP2102)",
    # A running T1000-E app (Meshtastic or MeshCore, both on the Adafruit core)
    # shows the Adafruit app id 8029 and even a "T1000_E_BOOT" product string
    # (seen 2026-11-08). Seeed's bootloader is 0057: in serial-only DFU mode
    # (after a 1200-baud touch) there is no volume, only the CDC port; after a
    # double-tap reset it also mounts a "T1000-E" volume.
    (0x239A, 0x8029): "t1000-e (app running: Meshtastic or MeshCore)",
    (0x239A, 0x0057): "t1000-e BOOTLOADER (serial DFU)",
    (0x239A, None): "nRF52, Adafruit/TinyUSB ids",
    (0x2886, 0x1667): "wio-tracker-l1 (Seeed ids: MeshCore or stock)",
    (0x2886, None): "Seeed nRF52 (T1000-E / Wio Tracker L1)",
    (0x04E8, None): "Samsung phone",
    (0x05AC, None): "Apple device",
}


@dataclass
class Port:
    device: str
    serial_number: str
    vid: int | None
    pid: int | None
    description: str
    guess: str

    @property
    def in_bootloader(self) -> bool:
        """Adafruit bootloader: Seeed's DFU product id, or a UF2 volume mounted."""
        import os
        if self.vid == 0x239A and self.pid == 0x0057:
            return True
        return self.vid == 0x239A and any(
            v in ("T1000-E", "TRACKER L1", "L1") for v in os.listdir("/Volumes"))


def list_ports() -> list[Port]:
    out: list[Port] = []
    for p in _lp.comports():
        if p.vid is None:
            continue  # debug-console, Bluetooth-Incoming-Port
        guess = _KNOWN.get((p.vid, p.pid)) or _KNOWN.get((p.vid, None)) or "?"
        out.append(Port(
            device=p.device, serial_number=p.serial_number or "",
            vid=p.vid, pid=p.pid, description=p.description or "", guess=guess))
    return sorted(out, key=lambda x: x.device)


def format_table(items: list[Port]) -> str:
    if not items:
        return "no USB serial ports"
    w = max(len(p.device) for p in items)
    lines = [f"{'port':<{w}}  {'serial':<18} {'vid:pid':<9} guess / description"]
    for p in items:
        lines.append(f"{p.device:<{w}}  {p.serial_number:<18} "
                     f"{p.vid:04x}:{p.pid:04x}  {p.guess} / {p.description}")
    return "\n".join(lines)
