# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Read a Meshtastic radio's settings over USB and check them.

The bench's strongest assertion: after the app's Radio Setup, both radios
must really hold the MeshTest channel, preset, roles and names. Everything
here goes through the Meshtastic Python API (`meshtastic` package).

Side effects to remember (CLAUDE.md, Bench):
- opening the port resets a Heltec V3, and once a serial API client has
  connected its Bluetooth stays OFF until a reboot: call `reboot()` (or
  power-cycle, Phase 2) before the phone needs it again;
- on nRF52 the phone's BLE link drops for a few seconds per connect;
- writes need one open connection and ~20 s before reading back.
Never hold a connection open while the app is using the radio.
"""

from __future__ import annotations

import time
from contextlib import contextmanager
from dataclasses import dataclass, field
from typing import Any, Callable, Iterator

from google.protobuf.json_format import MessageToDict

from .. import firmware, live
from ..config import RadioConfig

Log = Callable[[str], None]


@dataclass
class RadioSnapshot:
    """Everything the bench asserts on, as plain dicts (JSON-friendly)."""
    port: str
    node_num: int
    node_id: str
    owner: dict[str, Any]
    firmware_version: str
    hw_model: str
    excluded_modules: list[str]
    channels: list[dict[str, Any]]      # index, role, name, psk (hex), enabled
    lora: dict[str, Any]
    device: dict[str, Any]
    security: dict[str, Any]            # admin_key as hex list, public_key hex
    telemetry: dict[str, Any]
    range_test: dict[str, Any]
    bluetooth: dict[str, Any]
    raw: dict[str, Any] = field(default_factory=dict, repr=False)

    # -- derived -----------------------------------------------------------

    @property
    def enabled_channels(self) -> list[dict[str, Any]]:
        return [c for c in self.channels if c["enabled"]]

    @property
    def primary(self) -> dict[str, Any] | None:
        return next((c for c in self.channels if c["role"] == "PRIMARY"), None)

    @property
    def on_public_channel(self) -> bool:
        """Same rule as `MeshRadio.onPublicChannel`: primary key <= 1 byte."""
        p = self.primary
        return p is None or len(bytes.fromhex(p["psk"])) <= 1

    def to_dict(self) -> dict[str, Any]:
        d = {k: v for k, v in self.__dict__.items() if k != "raw"}
        return d


def _dict(msg: Any) -> dict[str, Any]:
    """Protobuf -> dict with defaults filled in (a LONG_FAST preset or CLIENT
    role is the enum's zero value and would otherwise be missing)."""
    try:
        return MessageToDict(msg, preserving_proto_field_name=True,
                             always_print_fields_with_no_presence=True)
    except TypeError:  # protobuf < 5
        return MessageToDict(msg, preserving_proto_field_name=True,
                             including_default_value_fields=True)


def _hex(b: bytes | None) -> str:
    return (b or b"").hex()


def _excluded(node: Any, meta: Any) -> list[str]:
    """Names of the modules compiled out (`DeviceMetadata.excluded_modules`,
    firmware 2.7+; Range Test is gone on 2.8)."""
    bits = getattr(meta, "excluded_modules", 0) if meta else 0
    if not bits:
        return []
    try:
        return [str(m) for m in node.excluded_modules_list(bits)]
    except Exception:  # noqa: BLE001 - API shape differs between CLI versions
        return [f"0x{bits:x}"]


@contextmanager
def connect(port: str, *, wait_config: bool = True) -> Iterator[Any]:
    """Open the serial API, yield the interface, always close it."""
    import meshtastic.serial_interface as si  # slow import, keep local

    with live.usb(port):
        iface = si.SerialInterface(devPath=port, noProto=False)
        try:
            if wait_config:
                iface.waitForConfig()
                iface.localNode.waitForConfig()
            yield iface
        finally:
            iface.close()


def snapshot(port: str) -> RadioSnapshot:
    """Read everything over one connection."""
    with connect(port) as iface:
        node = iface.localNode
        info = iface.getMyNodeInfo() or {}
        meta = getattr(iface, "metadata", None)
        lc, mc = node.localConfig, node.moduleConfig
        channels = []
        for ch in node.channels or []:
            d = _dict(ch)
            s = d.get("settings", {})
            role = d.get("role", "DISABLED")
            channels.append({
                "index": d.get("index", 0),
                "role": role,
                "name": s.get("name", ""),
                "psk": _hex(ch.settings.psk),
                "enabled": role != "DISABLED",
                "uplink": s.get("uplink_enabled", False),
                "downlink": s.get("downlink_enabled", False),
            })
        sec = _dict(lc.security)
        sec["admin_key"] = [_hex(k) for k in lc.security.admin_key]
        sec["public_key"] = _hex(lc.security.public_key)
        sec["private_key"] = "<redacted>" if lc.security.private_key else ""
        return RadioSnapshot(
            port=port,
            node_num=info.get("num", 0),
            node_id=info.get("user", {}).get("id", ""),
            owner=info.get("user", {}),
            firmware_version=getattr(meta, "firmware_version", "") if meta else "",
            hw_model=info.get("user", {}).get("hwModel", ""),
            excluded_modules=_excluded(node, meta),
            channels=channels,
            lora=_dict(lc.lora),
            device=_dict(lc.device),
            security=sec,
            telemetry=_dict(mc.telemetry),
            range_test=_dict(mc.range_test),
            bluetooth=_dict(lc.bluetooth),
            raw={"my_node_info": info},
        )


def reboot(port: str, *, wait_s: int = 25) -> None:
    """Reboot (restores Bluetooth on ESP32 after a serial session)."""
    with connect(port) as iface:
        iface.localNode.reboot(secs=1)
    time.sleep(wait_s)


# -- the serial-vs-Bluetooth rule --------------------------------------------

def bluetooth_off_after_serial(radio: RadioConfig) -> bool:
    """True when a serial API session leaves the radio's Bluetooth OFF until
    a reboot: ESP32 firmware does that (`serialEnter` in PowerFSM.cpp; the
    Heltec V3), nRF52 only drops the phone's link for a few seconds. Decided
    by the board's MCU, not its name, so a new ESP32 board gets it too."""
    try:
        return firmware.board_of(radio).mcu.startswith("esp32")
    except KeyError:
        return radio.board.startswith("heltec")  # not in BOARDS: no mcu known


@contextmanager
def serial_session(radio: RadioConfig, log: Log | None = None, *,
                   reboot_wait_s: int = 25) -> Iterator[str]:
    """Yield the radio's serial port for reads/writes and, when the body
    finishes, reboot a radio whose Bluetooth the session turned off
    ([bluetooth_off_after_serial]) so the phone can use it again. A body
    that raises is not rebooted (its error should surface, not a second one
    from a port that may be gone). The ONE place for the Heltec rule."""
    port = radio.port()
    yield port
    if bluetooth_off_after_serial(radio):
        if log:
            log(f"rebooting {radio.name} ({radio.board}) so its Bluetooth comes back")
        reboot(port, wait_s=reboot_wait_s)


def read_then_reboot(radio: RadioConfig, log: Log | None = None) -> RadioSnapshot:
    """[snapshot] over USB, then the reboot an ESP32 needs ([serial_session])."""
    with serial_session(radio, log) as port:
        return snapshot(port)



#: The firmware's default primary key (1 byte = "LongFast", the public mesh).
DEFAULT_PSK = bytes([1])


def set_primary_psk(port: str, psk: bytes, *, name: str | None = None,
                    settle_s: int = 20) -> None:
    """Phase 1 stand-in for the attenuator: a base on a different key is
    deaf to the mobile (pings time out, beacons stop). Restore with the
    MeshTest key for re-entry. With `DEFAULT_PSK` (and name "") the radio
    is back on the public channel, which the app must refuse to test on.
    `name` also renames the channel when given."""
    with connect(port) as iface:
        node = iface.localNode
        ch = node.getChannelByChannelIndex(0)
        ch.settings.psk = psk
        if name is not None:
            ch.settings.name = name
        node.writeChannel(0)
    time.sleep(settle_s)


def set_module_enabled(port: str, module: str, enabled: bool, *, settle_s: int = 20) -> None:
    """Turn the base beacon off/on: module is 'telemetry' (device_telemetry_enabled)
    or 'range_test' (enabled)."""
    with connect(port) as iface:
        node = iface.localNode
        if module == "telemetry":
            node.moduleConfig.telemetry.device_telemetry_enabled = enabled
        elif module == "range_test":
            node.moduleConfig.range_test.enabled = enabled
        else:
            raise ValueError(module)
        node.writeConfig(module)
    time.sleep(settle_s)


def set_bluetooth_mode(port: str, mode: str = "NO_PIN", *, settle_s: int = 20) -> None:
    """Bench radios pair without a PIN prompt (RANDOM_PIN / FIXED_PIN / NO_PIN).
    The write reboots the radio; an already-bonded phone keeps working."""
    from meshtastic.protobuf import config_pb2
    with connect(port) as iface:
        node = iface.localNode
        node.localConfig.bluetooth.mode = config_pb2.Config.BluetoothConfig.PairingMode.Value(mode)
        node.writeConfig("bluetooth")
    time.sleep(settle_s)


def prepare_fresh(port: str, *, region: str = "US", bluetooth_mode: str = "NO_PIN",
                  settle_s: int = 30) -> list[str]:
    """After a flash: a LoRa region (a fresh radio has UNSET and its LoRa is
    off) and PIN-less Bluetooth. One plain `writeConfig` per setting, each
    its own serial session and reboot: a begin/commit settings transaction
    over serial to the local node was silently dropped by 2.8.1 on the Heltec
    (2026-11-08), while single writes take. The API only queues the admin
    packet, and closing the port resets a Heltec (CP2102 DTR/RTS), so each
    session sleeps before closing. On 2.8 the first region set also changes
    the node number (crc32 of the public key). Returns what was changed."""
    from meshtastic.protobuf import config_pb2
    want_region = config_pb2.Config.LoRaConfig.RegionCode.Value(region)
    want_bt = config_pb2.Config.BluetoothConfig.PairingMode.Value(bluetooth_mode)
    changed: list[str] = []
    for label, section, test, apply in (
        (f"region {region}", "lora",
         lambda c: c.lora.region != want_region,
         lambda c: setattr(c.lora, "region", want_region)),
        (f"bluetooth {bluetooth_mode}", "bluetooth",
         lambda c: c.bluetooth.mode != want_bt,
         lambda c: setattr(c.bluetooth, "mode", want_bt)),
    ):
        with connect(port) as iface:
            node = iface.localNode
            if not test(node.localConfig):
                continue
            apply(node.localConfig)
            node.writeConfig(section)
            time.sleep(8)
        changed.append(label)
        time.sleep(settle_s)
    return changed


def reset_node_db(port: str, *, keep_favorites: bool = False, settle_s: int = 20) -> None:
    """Forget every other node (PKI-recovery scenario: the radio no longer
    has the other's key, so the next DM gets a PKI NAK).

    `AdminMessage.nodedb_reset` is "keep favourites": the Python API's
    `resetNodeDb()` sends True, and Radio Setup's add_contact leaves the
    other radio as a favourite, so that reset kept the mobile's key and
    every ping was still answered (bench 2026-11-09). False clears them too.
    The sleep before the port closes: 2.8.1 drops a write when the serial
    session ends right after it (see `prepare_fresh`)."""
    from meshtastic.protobuf import admin_pb2

    with connect(port) as iface:
        node = iface.localNode
        node.ensureSessionKey()
        msg = admin_pb2.AdminMessage()
        msg.nodedb_reset = keep_favorites  # in a oneof: sent even when False
        node._sendAdmin(msg)
        time.sleep(8)
    time.sleep(settle_s)


def enter_dfu(port: str) -> None:
    """nRF52 only: drop into the UF2 bootloader (the CLI's flush error is normal)."""
    try:
        with connect(port, wait_config=False) as iface:
            iface.localNode.enterDFUMode()
    except Exception:  # noqa: BLE001 - the port vanishes mid-call, by design
        pass


# -- checks ----------------------------------------------------------------

@dataclass
class Check:
    name: str
    ok: bool
    detail: str = ""


def check_meshtest_setup(snap: RadioSnapshot, *, role: str, psk_hex: str | None,
                         preset: str | None) -> list[Check]:
    """What Radio Setup (`RadioProfileService`) must have left on a radio.

    `psk_hex`: the 32-byte MeshTest key from the phone (SharedPreferences
    `test_channel_psk`), when the bench knows it; None only checks shape.
    """
    out: list[Check] = []
    en = snap.enabled_channels
    out.append(Check("exactly one enabled channel", len(en) == 1,
                     f"{len(en)} enabled: {[c['name'] for c in en]}"))
    p = snap.primary
    out.append(Check("primary channel is MeshTest", bool(p and p["name"] == "MeshTest"),
                     p["name"] if p else "no primary"))
    out.append(Check("primary key is 32 bytes", bool(p and len(p["psk"]) == 64),
                     f"{len(p['psk']) // 2 if p else 0} bytes"))
    out.append(Check("not on the public channel", not snap.on_public_channel))
    if psk_hex and p:
        out.append(Check("key matches the phone's test_channel_psk",
                         p["psk"].lower() == psk_hex.lower()))
    if preset:
        out.append(Check(f"modem preset {preset}", snap.lora.get("modem_preset") == preset,
                         str(snap.lora.get("modem_preset"))))
    out.append(Check("role CLIENT", snap.device.get("role", "CLIENT") == "CLIENT",
                     str(snap.device.get("role"))))
    out.append(Check("rebroadcast LOCAL_ONLY",
                     snap.device.get("rebroadcast_mode") == "LOCAL_ONLY",
                     str(snap.device.get("rebroadcast_mode"))))
    want_name = {"base": ("MeshTest Base", "BASE"), "mobile": ("MeshTest Mobile", "MOBL")}.get(role)
    if want_name:
        got = (snap.owner.get("longName"), snap.owner.get("shortName"))
        out.append(Check(f"owner renamed to {want_name}", got == want_name, str(got)))
    if role == "base":
        out.append(Check("base has an admin key (remote changes from the mobile)",
                         any(k for k in snap.security.get("admin_key", [])),
                         str(snap.security.get("admin_key"))))
    if role == "mobile":
        out.append(Check("mobile telemetry broadcast off",
                         not snap.telemetry.get("device_telemetry_enabled", False)))
    return out
