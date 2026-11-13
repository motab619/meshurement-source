# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Scenario 12a: Radio Setup, base flow, on the MeshCore pair, verified
through the app.

A MeshCore `companion_radio_ble` build is silent on USB (the companion
protocol runs over BLE only), so unlike radio_setup.py nothing here reads a
radio over its serial port. The truth comes from the radio itself over BLE,
as the app reads it back after writing (SELF_INFO / DEVICE_INFO /
GET_CHANNEL): `radio.snapshot` on the mobile, then on the base over a
second connection, plus the `.mabackup` originals the setup saved
(`backups.list`). docs/design/bench-rig/README.md §5.1 says what this does
and does not prove.

Flow: scan → pick the two MeshCore devices (the ids the app remembers for
the roles, else the role word in the advert name, else the only two) →
`radio.setupBase` (ladder modulation, client repeat on, the band's relay
frequency: the firmware only relays on 433.000 / 869.495 / 918.000 MHz) →
`radio.switchToAndApplyMobile` → read back both → reconnect the mobile.

Options: preset (ladder id, default MC_SF7_BW62.5_CR5), beacon_secs (10),
frequency_mhz (918.000), tx_power (radio's own), base_name / mobile_name
(substrings that pin a scanned device to a role when the names don't say).
Skips when bench.toml has no MeshCore base + mobile.
"""

from __future__ import annotations

import base64
from typing import Any

from .. import config
from . import Context, Skip

DEFAULT_PRESET = "MC_SF7_BW62.5_CR5"
DEFAULT_FREQ_MHZ = 918.000
RELAY_MHZ = (433.000, 869.495, 918.000)
NAMES = {"base": "MeshTest Base", "mobile": "MeshTest Mobile"}

Check = tuple[str, bool, str]


def meshcore_pair(cfg: config.BenchConfig) -> tuple[config.RadioConfig, config.RadioConfig]:
    """The MeshCore base and mobile in bench.toml (by `protocol` and `role`,
    whatever the tables are called), else Skip."""
    mc = [r for r in cfg.radios.values() if r.protocol == "meshcore"]
    base = next((r for r in mc if r.role == "base"), None)
    mobile = next((r for r in mc if r.role == "mobile"), None)
    if base is None or mobile is None:
        raise Skip("no MeshCore base + mobile pair in bench.toml "
                   "(two radios with protocol = \"meshcore\", roles base and mobile)")
    return base, mobile


def find_pair(devices: list[dict], roles: dict[str, Any],
              base_hint: str | None = None, mobile_hint: str | None = None
              ) -> tuple[dict | None, dict | None, str]:
    """Pick (base, mobile, how) among the scanned devices.

    MeshCore radios advertise `MeshCore-<advert name>`; the name changes
    with every rename, so the ids the app remembers for the roles come
    first, then explicit hints, then the role word a previous setup put in
    the name ("MeshCore-MeshTest Base"), and when the scan shows exactly two
    MeshCore devices and nothing says which is which, they are taken in scan
    order (the report says so: a fresh pair has its factory names)."""
    mc = [d for d in devices if d.get("protocol") == "meshcore"]
    by_id = {d["id"]: d for d in mc}
    base = by_id.get(roles.get("baseDevice") or "")
    mobile = by_id.get(roles.get("mobileDevice") or "")
    how = []
    if base or mobile:
        how.append("remembered id")

    def by_word(word: str, taken: dict | None) -> dict | None:
        for d in mc:
            if d is taken:
                continue
            if word and word.lower() in (d.get("name") or "").lower():
                return d
        return None

    if base is None and base_hint:
        base = by_word(base_hint, mobile)
        if base:
            how.append("base_name option")
    if mobile is None and mobile_hint:
        mobile = by_word(mobile_hint, base)
        if mobile:
            how.append("mobile_name option")
    if base is None:
        base = by_word("base", mobile)
        if base:
            how.append("'base' in the name")
    if mobile is None:
        mobile = by_word("mobile", base)
        if mobile:
            how.append("'mobile' in the name")
    if (base is None or mobile is None) and len(mc) == 2:
        rest = [d for d in mc if d is not base and d is not mobile]
        if base is None and mobile is None:
            base, mobile = mc[0], mc[1]
            how.append("the only two MeshCore devices, in scan order (names don't say)")
        elif base is None:
            base = rest[0]
            how.append("the other MeshCore device as base")
        else:
            mobile = rest[0]
            how.append("the other MeshCore device as mobile")
    return base, mobile, ", ".join(how) or "not found"


def _meshtest_slots(snap_mc: dict) -> list[dict]:
    return [c for c in snap_mc.get("channels", []) if c.get("name") == "MeshTest"]


def check_meshcore_snapshot(snap: dict, *, role: str, psk_hex: str | None, preset: str,
                            freq_mhz: float, renamed: bool = True,
                            tx_power: int | None = None) -> list[Check]:
    """What a `radio.snapshot` of a radio set up as [role] must show.
    `psk_hex` is the phone's 32-byte test key; MeshCore takes its first 16
    bytes as the channel secret."""
    out: list[Check] = []
    out.append(("protocol is MeshCore", snap.get("protocol") == "meshcore", str(snap.get("protocol"))))
    mc = snap.get("meshcore") or {}
    slots = _meshtest_slots(mc)
    out.append(("one MeshTest channel slot", len(slots) == 1,
                f"{len(slots)} slots named MeshTest: {[c.get('index') for c in slots]}"))
    if slots:
        slot = slots[0]
        out.append(("MeshTest is not in slot 0", slot.get("index") != 0, str(slot.get("index"))))
        want = (psk_hex or "")[:32]
        out.append(("MeshTest secret = first 16 bytes of the phone's test key",
                    bool(want) and slot.get("secret") == want,
                    f"{slot.get('secret')} vs {want or 'no key on the phone'}"))
    out.append(("modulation is the requested ladder entry", mc.get("modulation") == preset,
                f"{mc.get('modulation')} ({mc.get('paramsLabel')}) vs {preset}"))
    want_khz = round(freq_mhz * 1000)
    out.append((f"frequency is {freq_mhz:.3f} MHz", mc.get("frequencyKHz") == want_khz,
                f"{mc.get('frequencyKHz')} kHz"))
    repeat = mc.get("clientRepeat")
    if role == "base":
        out.append(("base relays (client repeat on)", repeat is True,
                    "firmware did not report the flag" if repeat is None else str(repeat)))
    else:
        out.append(("mobile does not relay", repeat is False,
                    "firmware did not report the flag" if repeat is None else str(repeat)))
    if renamed:
        out.append((f"advert name is '{NAMES[role]}'", mc.get("name") == NAMES[role], str(mc.get("name"))))
    if tx_power is not None:
        out.append((f"TX power is {tx_power} dBm", mc.get("txPowerDbm") == tx_power, str(mc.get("txPowerDbm"))))
    out.append(("not on a public (community) setting", snap.get("onPublicChannel") is False,
                str(snap.get("onPublicChannel"))))
    return out


def check_backups(backups: list[dict], nodes: dict[str, int | None],
                  already: frozenset[str] = frozenset()) -> list[Check]:
    """Each role's node has a MeshCore `original` backup (the settings from
    before the app touched it). A role in `already` was on MeshTest before
    this run, maybe set up from another phone: the app takes no backup of a
    radio already on the test channel, so none on this phone is expected."""
    out: list[Check] = []
    for role, node in nodes.items():
        mine = [b for b in backups if b.get("nodeNum") == node]
        originals = [b for b in mine if b.get("original")]
        if role in already and not mine:
            continue
        out.append((f"{role}: an original backup exists", node is not None and len(originals) == 1,
                    f"node {node}: {len(mine)} backups, {len(originals)} original"))
        if originals:
            out.append((f"{role}: the original backup is MeshCore",
                        originals[0].get("protocol") == "meshcore", str(originals[0].get("protocol"))))
    return out


def run(ctx: Context) -> None:
    cfg, app, log = ctx.cfg, ctx.app, ctx.log
    base_cfg, mobile_cfg = meshcore_pair(cfg)
    preset = ctx.options.get("preset", DEFAULT_PRESET)
    beacon = int(ctx.options.get("beacon_secs", 10))
    freq = float(ctx.options.get("frequency_mhz", DEFAULT_FREQ_MHZ))
    tx_power = ctx.options.get("tx_power")
    tx_power = int(tx_power) if tx_power not in (None, "") else None
    if not any(abs(freq - f) < 0.0005 for f in RELAY_MHZ):
        ctx.check("test frequency is one the base can relay on", False,
                  f"{freq:.3f} MHz; MeshCore companions relay only on {RELAY_MHZ}")
        return
    log(f"MeshCore pair: base {base_cfg.name} ({base_cfg.board}), mobile {mobile_cfg.name} "
        f"({mobile_cfg.board}); {preset}, {freq:.3f} MHz, beacon {beacon}s")

    # 1. The app finds both over BLE. A connected Meshtastic radio would
    # make the base write refuse (same-protocol rule), so let go of it.
    state = app.state()
    if state["radio"]["ready"] and state["radio"]["protocol"] != "meshcore":
        log("disconnecting the Meshtastic radio first")
        app.cmd("radio.disconnect")
    roles = state["roles"]
    devices = app.cmd("radio.scan", seconds=12, timeout=40)
    log(f"  scan: {[(d['name'], d['protocol']) for d in devices]}")
    d_base, d_mobile, how = find_pair(devices, roles, ctx.options.get("base_name"),
                                      ctx.options.get("mobile_name"))
    if not ctx.check("base radio seen over BLE (MeshCore)", d_base is not None, str(devices)):
        return
    if not ctx.check("mobile radio seen over BLE (MeshCore)", d_mobile is not None, str(devices)):
        return
    log(f"  base = {d_base['name']}, mobile = {d_mobile['name']} ({how})")

    # 2. Radio Setup, base flow. No reboot on MeshCore; the pairing prompt,
    # if any, is on the phone (Phase 1).
    log(f"Radio Setup: base = {d_base['name']}")
    kwargs: dict[str, Any] = dict(id=d_base["id"], name=d_base["name"], protocol="meshcore",
                                  preset=preset, beaconSecs=beacon, frequencyMHz=freq, rename=True)
    if tx_power is not None:
        kwargs["txPowerDbm"] = tx_power
    app.cmd("radio.setupBase", timeout=240, **kwargs)
    app.drain()
    steps = [e.data["step"] for e in app.events if e.type == "setup" and e.data.get("role") == "base"]
    ctx.check("base setup reported steps", len(steps) >= 3, str(steps))
    # The app skips the backup for a radio already on the MeshTest channel
    # (RadioProfileService._backUp): its first setup saved the original,
    # which check_backups below still requires.
    backed_up = any("backup" in s.lower() or "saved" in s.lower() for s in steps)
    already = "meshtest" in d_base["name"].lower()
    ctx.check("base setup took a backup first (or was already set up)",
              backed_up or already, f"name {d_base['name']!r}; steps {steps}")

    log(f"Radio Setup: mobile = {d_mobile['name']}")
    kwargs = dict(id=d_mobile["id"], name=d_mobile["name"], protocol="meshcore",
                  preset=preset, frequencyMHz=freq, rename=True)
    if tx_power is not None:
        kwargs["txPowerDbm"] = tx_power
    app.cmd("radio.switchToAndApplyMobile", timeout=240, **kwargs)
    st = app.state()
    ctx.check("app connected to the mobile (no reboot on MeshCore)",
              st["radio"]["ready"] and st["radio"]["protocol"] == "meshcore", str(st["radio"]))
    base_node, mobile_node = st["roles"]["base"], st["roles"]["mobile"]
    ctx.check("app roles: base node remembered", base_node is not None, str(st["roles"]))
    ctx.check("app roles: mobile node is the connected radio",
              mobile_node is not None and mobile_node == st["radio"]["nodeId"],
              f"{mobile_node} vs {st['radio']['nodeId']}")
    ctx.check("app roles: two different nodes", base_node != mobile_node, f"{base_node} / {mobile_node}")
    ctx.check("connected radio reports the preset", st["radio"]["preset"] == preset, str(st["radio"]["preset"]))
    ctx.check("base beacon recorded as a trace beacon",
              app.cmd("prefs.get", key="base_beacon_kind") == "trace"
              and app.cmd("prefs.get", key="base_beacon_interval_sec") == beacon,
              f"{app.cmd('prefs.get', key='base_beacon_kind')} / "
              f"{app.cmd('prefs.get', key='base_beacon_interval_sec')}")

    psk_b64 = app.cmd("prefs.get", key="test_channel_psk")
    psk_hex = base64.b64decode(psk_b64).hex() if psk_b64 else None
    ctx.check("phone holds a 32-byte test channel key", bool(psk_hex) and len(psk_hex) == 64)

    # 3. The truth, as far as BLE gives it: the mobile's read-back.
    snap = app.cmd("radio.snapshot")
    ctx.check("mobile snapshot is the mobile node", snap.get("nodeId") == mobile_node,
              f"{snap.get('nodeId')} vs {mobile_node}")
    for name, ok, detail in check_meshcore_snapshot(snap, role="mobile", psk_hex=psk_hex, preset=preset,
                                                    freq_mhz=freq, tx_power=tx_power):
        ctx.check(f"mobile: {name}", ok, detail)

    # 4. Then the base's, over a second connection.
    log("connecting to the base to read it back")
    app.cmd("radio.connect", timeout=150, id=d_base["id"], name=d_base["name"], protocol="meshcore")
    snap = app.cmd("radio.snapshot")
    ctx.check("base snapshot is the base node", snap.get("nodeId") == base_node,
              f"{snap.get('nodeId')} vs {base_node}")
    for name, ok, detail in check_meshcore_snapshot(snap, role="base", psk_hex=psk_hex, preset=preset,
                                                    freq_mhz=freq, tx_power=tx_power):
        ctx.check(f"base: {name}", ok, detail)

    # 5. Originals saved before the writes.
    backups = app.cmd("backups.list")
    already = frozenset(r for r, d in (("base", d_base), ("mobile", d_mobile))
                        if "meshtest" in d["name"].lower())
    for role in sorted(already):
        if not any(b.get("nodeNum") == (base_node if role == "base" else mobile_node) for b in backups):
            log(f"NOTE: the {role} was already set up before this run and this phone has no backup "
                "of it (its original settings were saved on whichever phone set it up first)")
    for name, ok, detail in check_backups(backups, {"base": base_node, "mobile": mobile_node}, already):
        ctx.check(name, ok, detail)

    # 6. Back on the mobile for whatever runs next.
    log("reconnecting the mobile")
    app.cmd("radio.connect", timeout=150, id=d_mobile["id"], name=d_mobile["name"], protocol="meshcore")
    st = app.state()
    ctx.check("app back on the mobile", st["radio"]["ready"] and st["radio"]["nodeId"] == mobile_node,
              str(st["radio"]))
