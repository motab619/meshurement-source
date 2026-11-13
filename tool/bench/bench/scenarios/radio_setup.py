# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Scenario 2: Radio Setup, base flow, verified over USB.

The app (bench server) runs `RadioProfileService.applyToBase` on the base
radio, then `switchToAndApplyMobile` on the mobile, exactly as the Radio
Setup screen does. Then the Mac reads both radios over their serial ports
and checks what the firmware actually holds: one MeshTest channel with the
phone's 32-byte key, the preset, roles, names, admin key.

Options: preset (default MEDIUM_FAST), beacon_secs (60), before=fresh (re-read
the Heltec over USB instead of using the cached snapshot).

Both Meshtastic radios must be on `bluetooth.mode = NO_PIN` (`bench prepare`):
with a PIN the first admin write failed with "Encryption is insufficient"
(2026-11-08), and even with NO_PIN iOS asks once per radio to confirm the
pairing (the app went inactive 1 s after connecting while the alert was up,
and the admin ACK timed out). Once confirmed the bond persists across runs
and reinstalls. First full pass: 2026-11-08 12:44, 31 checks, 196 s.
"""

from __future__ import annotations

import base64
import json
import tempfile
import time
from pathlib import Path

from ..app import BenchCommandError
from ..radios import meshtastic as mt
from . import Context, Skip


def _find(devices: list[dict], snap: mt.RadioSnapshot, remembered: str | None,
          taken: tuple[dict, ...] = ()) -> dict | None:
    """Pick the BLE descriptor for a radio: the id the app remembers for the
    role, else by name. Meshtastic advertises `<shortName>_<4 hex>`; the hex is
    the node id's tail on nRF52 (MOBL_d5b5 for !73eed5b5) but the Bluetooth
    MAC's on ESP32 (BASE_3e9c for !68e178cb, seen 2026-11-08), so the short
    name is the reliable part."""
    if remembered:
        for d in devices:
            if d["id"] == remembered:
                return d
    short = (snap.owner.get("shortName") or "").lower()
    tail = snap.node_id.lstrip("!")[-4:].lower()
    mesht = [d for d in devices if d["protocol"] == "meshtastic" and d not in taken]
    for d in mesht:
        if short and d["name"].lower().startswith(short + "_"):
            return d
    for d in mesht:
        if d["name"].lower().endswith(tail):
            return d
    # iOS sometimes delivers a truncated name ("BA" for BASE_3e9c, 2026-11-08).
    for d in mesht:
        n = d["name"].lower()
        if short and len(n) >= 2 and (short + "_").startswith(n):
            return d
    if len(mesht) == 1:
        return mesht[0]
    return None


def _lost_bond(err: str) -> bool:
    """A connect refused because the phone's pairing no longer matches the
    radio's keys. Android (2026-11-08, A16 + a factory-flashed Heltec): the
    link comes up, the stack fails to encrypt ("Encryption failure 6", key
    missing, in logcat) and drops it before the plugin's requestMtu, so the
    app sees only "requestMtu, device is disconnected"."""
    t = err.lower().replace("_", " ")
    return ("device is disconnected" in t or "peer removed pairing" in t
            or "insufficient authentication" in t or "insufficient encryption" in t
            or "pin or key missing" in t)


def _with_bond_retry(ctx: Context, android: bool, dev: dict, label: str, fn) -> None:
    """Run a connect-and-configure command; on Android, when it fails like a
    stale bond, drop the phone's side (`ble.removeBond`) and try once more,
    so the next connect pairs afresh (the pairing watch answers the dialog)."""
    try:
        fn()
    except BenchCommandError as e:
        if not android or not _lost_bond(str(e)):
            raise
        ctx.log(f"  {label}: connect failed ({e}); dropping the phone's bond with "
                f"{dev['name']} and retrying once")
        had = ctx.app.cmd("ble.removeBond", id=dev["id"], timeout=60)
        ctx.check(f"{label}: phone had a stale bond to drop", bool(had), str(had))
        time.sleep(3)
        fn()


_CACHE = Path(tempfile.gettempdir()) / "meshurement-bench-snapshots"


def _cache(serial: str, snap: mt.RadioSnapshot) -> None:
    _CACHE.mkdir(exist_ok=True)
    (_CACHE / f"{serial}.json").write_text(json.dumps(snap.to_dict()))


def invalidate(serial: str) -> None:
    """Forget a radio's cached snapshot (after `bench flash`: new node id)."""
    (_CACHE / f"{serial}.json").unlink(missing_ok=True)


def cached(serial: str) -> mt.RadioSnapshot | None:
    """The snapshot taken before Radio Setup touched a radio, if any."""
    return _cached(serial)


def _cached(serial: str) -> mt.RadioSnapshot | None:
    p = _CACHE / f"{serial}.json"
    if not p.exists():
        return None
    d = json.loads(p.read_text())
    return mt.RadioSnapshot(**d)


def run(ctx: Context) -> None:
    cfg, app, log = ctx.cfg, ctx.app, ctx.log
    base, mobile = cfg.radio("base"), cfg.radio("mobile")
    if base.protocol != "meshtastic" or mobile.protocol != "meshtastic":
        raise Skip("Meshtastic pair only (MeshCore verification needs the USB build)")
    preset = ctx.options.get("preset", "MEDIUM_FAST")
    beacon = int(ctx.options.get("beacon_secs", 60))

    # 1. Before: who the radios are (node ids for BLE matching). The mobile
    # (nRF52) is read now; the Heltec only when nothing cached it, because a
    # serial read costs it a reboot (`mt.read_then_reboot`; option
    # before=fresh forces it).
    log("reading the radios over USB (before)")
    before_mobile = mt.read_then_reboot(mobile, log)
    _cache(mobile.serial, before_mobile)  # the `backups` scenario compares against it
    before_base = None if ctx.options.get("before") == "fresh" else _cached(base.serial)
    if before_base is None:
        before_base = mt.read_then_reboot(base, log)
        _cache(base.serial, before_base)
    log(f"  base {before_base.node_id} fw {before_base.firmware_version}; "
        f"mobile {before_mobile.node_id} fw {before_mobile.firmware_version}")

    # 2. The app finds both over BLE.
    state = app.state()
    roles = state["roles"]
    devices = app.cmd("radio.scan", seconds=12, timeout=40)
    log(f"  scan: {[d['name'] for d in devices]}")
    d_mobile = _find(devices, before_mobile, roles.get("mobileDevice"))
    d_base = _find(devices, before_base, roles.get("baseDevice"),
                   taken=(d_mobile,) if d_mobile else ())
    if not ctx.check("base radio seen over BLE", d_base is not None, str(devices)):
        return
    if not ctx.check("mobile radio seen over BLE", d_mobile is not None, str(devices)):
        return

    # 3. Radio Setup, base flow. The pairing watch answers Android's
    # "Pair with ...?" dialog while the app connects (iOS: manual, once).
    android = state["app"]["platform"] == "android"
    log(f"Radio Setup: base = {d_base['name']} ({preset}, beacon {beacon}s)")
    try:
        with ctx.pairing_watch() as taps:
            _with_bond_retry(ctx, android, d_base, "base", lambda: app.cmd(
                "radio.setupBase", timeout=240, id=d_base["id"], name=d_base["name"],
                protocol="meshtastic", preset=preset, beaconSecs=beacon, rename=True))
        if taps:
            log(f"  base: pairing dialog answered at {taps}")
    except BenchCommandError as e:
        if "Peer removed pairing information" in str(e):
            ctx.check("phone's Bluetooth bond matches the base radio", False,
                      f"{d_base['name']}: the radio lost its bond (an ESP32 erase does that; "
                      "nRF52 keeps bonds across a DFU) while iOS kept its side. Settings → "
                      "Bluetooth → Forget This Device, then rerun.")
            return
        raise
    app.drain()
    steps = [e.data["step"] for e in app.events if e.type == "setup"]
    ctx.check("base setup reported steps", len(steps) >= 3, str(steps))

    log(f"Radio Setup: mobile = {d_mobile['name']}")
    with ctx.pairing_watch() as taps:
        _with_bond_retry(ctx, android, d_mobile, "mobile", lambda: app.cmd(
            "radio.switchToAndApplyMobile", timeout=240, id=d_mobile["id"],
            name=d_mobile["name"], protocol="meshtastic", preset=preset, rename=True))
        log("waiting for the mobile to come back after its reboot")
        try:
            app.wait_link("ready", timeout=120)
            ctx.check("app reconnected to the mobile after reboot", True)
        except TimeoutError as e:
            ctx.check("app reconnected to the mobile after reboot", False, str(e))
    if taps:
        log(f"  mobile: pairing dialog answered at {taps}")

    st = app.state()
    ctx.check("app roles: base node", st["roles"]["base"] == before_base.node_num,
              f"{st['roles']['base']} vs {before_base.node_num}")
    ctx.check("app roles: mobile node", st["roles"]["mobile"] == before_mobile.node_num,
              f"{st['roles']['mobile']} vs {before_mobile.node_num}")
    ctx.check("connected radio reports the preset", st["radio"]["preset"] == preset,
              str(st["radio"]["preset"]))
    ctx.check("connected radio not on the public channel",
              st["radio"]["onPublicChannel"] is False, str(st["radio"]["onPublicChannel"]))

    psk_b64 = app.cmd("prefs.get", key="test_channel_psk")
    psk_hex = base64.b64decode(psk_b64).hex() if psk_b64 else None
    ctx.check("phone holds a 32-byte test channel key", bool(psk_hex) and len(psk_hex) == 64)

    # 4. The truth: read both radios over USB.
    log("waiting 20 s for the radios to settle, then reading them over USB")
    time.sleep(20)
    for name, rcfg, role in (("base", base, "base"), ("mobile", mobile, "mobile")):
        snap = mt.read_then_reboot(rcfg, log)
        for c in mt.check_meshtest_setup(snap, role=role, psk_hex=psk_hex, preset=preset):
            ctx.check(f"{name}: {c.name}", c.ok, c.detail)
        if role == "base":
            admin = snap.security.get("admin_key", [])
            ctx.check("base admin key is the mobile's public key",
                      before_mobile.security.get("public_key") in admin,
                      f"{admin} vs {before_mobile.security.get('public_key')}")
            ctx.check("base beacon interval", snap.telemetry.get("device_update_interval") == beacon
                      or snap.range_test.get("sender") == beacon,
                      f"telemetry {snap.telemetry.get('device_update_interval')} rangetest {snap.range_test.get('sender')}")
