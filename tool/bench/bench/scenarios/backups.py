# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Scenario 7: radio backups.

After radio-setup the app holds a backup per radio (`RadioBackupService`,
`Documents/radio_backups`); the first one per node is the `original`, the
settings from before the app touched the radio. Checks through
`backups.list`: an original for the base node and for the mobile node, both
Meshtastic, the mobile's original matching the USB snapshot radio-setup
took before it wrote anything (preset, region, channel names).

Then `backups.restoreOriginal` = "Put this radio back the way it was" on
the connected mobile: the radio reboots, the app reconnects, the mobile's
role is cleared (`RadioRoles.clearNode`), and the Mac reads the mobile over
USB to confirm it holds its original settings again (channels incl. keys,
preset/region/hop limit/tx power, device role and relaying, owner names,
telemetry broadcast).

**This undoes Radio Setup on the mobile**: it is last in `bench run all`
and every later scenario needs `bench run radio-setup` first (the scenario
says so at the end). The base is left as Radio Setup wrote it.

Options: restore (true; false only lists and checks the backups),
verify_usb (true).

Needs radio-setup (roles set, phone connected to the mobile; the cached
before-snapshot comes from radio-setup's USB read in this or an earlier
run). First hardware run 2026-11-09: the restore brought back the
original, but the mobile had changed since that backup was taken, so a
before-snapshot that differs from the original backup now switches the
checks to the backup's own preset, region, channel names and owner.
"""

from __future__ import annotations

import time
from typing import Any

from ..app import BenchCommandError
from ..radios import meshtastic as mt
from . import Context, Skip
from .common import end_session, mobile_port, seq, wait_link
from .radio_setup import cached

needs = ("radio-setup",)


def _original(backups: list[dict[str, Any]], node: int) -> dict[str, Any] | None:
    mine = [b for b in backups if b["nodeNum"] == node]
    return next((b for b in mine if b["original"]), None)


def compare_snapshot(before: mt.RadioSnapshot, after: mt.RadioSnapshot) -> list[mt.Check]:
    """What a restored radio must share with its before-Radio-Setup snapshot."""
    out: list[mt.Check] = []
    b_ch = {c["index"]: c for c in before.channels}
    a_ch = {c["index"]: c for c in after.channels}
    same = all(
        (b_ch[i]["role"], b_ch[i]["name"], b_ch[i]["psk"]) ==
        (a_ch.get(i, {}).get("role"), a_ch.get(i, {}).get("name"), a_ch.get(i, {}).get("psk"))
        for i in b_ch)
    out.append(mt.Check("channels (role, name, key) as before", same,
                        f"before {[(c['role'], c['name']) for c in before.enabled_channels]} "
                        f"after {[(c['role'], c['name']) for c in after.enabled_channels]}"))
    for key in ("modem_preset", "region", "hop_limit", "tx_power", "use_preset", "channel_num"):
        out.append(mt.Check(f"lora {key} as before", before.lora.get(key) == after.lora.get(key),
                            f"{before.lora.get(key)} vs {after.lora.get(key)}"))
    for key in ("role", "rebroadcast_mode"):
        out.append(mt.Check(f"device {key} as before",
                            before.device.get(key, "CLIENT" if key == "role" else "ALL")
                            == after.device.get(key, "CLIENT" if key == "role" else "ALL"),
                            f"{before.device.get(key)} vs {after.device.get(key)}"))
    out.append(mt.Check("owner names as before",
                        (before.owner.get("longName"), before.owner.get("shortName"))
                        == (after.owner.get("longName"), after.owner.get("shortName")),
                        f"{before.owner.get('longName')!r}/{before.owner.get('shortName')!r} vs "
                        f"{after.owner.get('longName')!r}/{after.owner.get('shortName')!r}"))
    out.append(mt.Check("telemetry broadcast as before",
                        before.telemetry.get("device_telemetry_enabled", False)
                        == after.telemetry.get("device_telemetry_enabled", False)))
    return out


def _backup_view(b: dict[str, Any]) -> dict[str, Any]:
    """What a Meshtastic backup says about the radio, in comparable form."""
    return {"preset": b.get("preset"), "region": b.get("region"),
            "channels": sorted(n.strip() for n in (b.get("channels") or "").split(",") if n.strip()),
            "owner": b.get("ownerName")}


def _snapshot_view(snap: mt.RadioSnapshot) -> dict[str, Any]:
    """The same fields from a USB snapshot (an unnamed channel is the
    backup's "(default)")."""
    return {"preset": snap.lora.get("modem_preset"), "region": snap.lora.get("region"),
            "channels": sorted(c["name"] or "(default)" for c in snap.enabled_channels),
            "owner": snap.owner.get("longName")}


def _same_as_backup(snap: mt.RadioSnapshot, b: dict[str, Any]) -> bool:
    return _snapshot_view(snap) == _backup_view(b)


def run(ctx: Context) -> None:
    app, log = ctx.app, ctx.log
    mobile = ctx.cfg.radio("mobile")
    if mobile.protocol != "meshtastic":
        raise Skip("Meshtastic mobile only (USB read-back exists for Meshtastic)")
    if app.state()["session"] is not None:
        end_session(ctx)
    roles = app.state()["roles"]
    base_node, mobile_node = roles["base"], roles["mobile"]

    backups: list[dict[str, Any]] = app.cmd("backups.list")
    log(f"  {len(backups)} backups: " + ", ".join(
        f"{b['nodeId']} {b['reason']!r}{' (original)' if b['original'] else ''}" for b in backups))
    orig_base = _original(backups, base_node)
    orig_mobile = _original(backups, mobile_node)
    ctx.check("original backup exists for the base node", orig_base is not None,
              f"node {base_node}")
    ctx.check("original backup exists for the mobile node", orig_mobile is not None,
              f"node {mobile_node}")
    ctx.check("one original per node",
              all(sum(1 for b in backups if b["nodeNum"] == n and b["original"]) <= 1
                  for n in {b["nodeNum"] for b in backups}))
    if orig_mobile is None:
        return
    ctx.check("mobile's original is a Meshtastic backup", orig_mobile["protocol"] == "meshtastic")
    before = cached(mobile.serial)
    if before is not None and not _same_as_backup(before, orig_mobile):
        # The original is the first backup this phone ever took of the
        # radio; anything since (another phone, an earlier bench run, an
        # interrupted scenario) changed the radio, so this run's USB
        # snapshot is not what a restore should bring back. Judge the
        # restore against the backup instead (bench 2026-11-09).
        log(f"  the mobile changed since its original backup ({_backup_view(orig_mobile)}; "
            f"USB before this run: {_snapshot_view(before)}): checking the restore "
            "against the backup")
        ctx.check("mobile's original region matches the radio's",
                  orig_mobile.get("region") == before.lora.get("region"),
                  f"{orig_mobile.get('region')} vs {before.lora.get('region')}")
        before = None
    elif before is not None:
        # _same_as_backup held: preset, region, channel names and owner agree.
        ctx.check("mobile's original matches the USB snapshot from before Radio Setup", True,
                  str(_backup_view(orig_mobile)))
    else:
        log("  no cached before-snapshot for the mobile (radio-setup did not run on this Mac): "
            "shape checks only")
        ctx.check("mobile's original is not this run's MeshTest setup",
                  orig_mobile.get("preset") != app.state()["radio"].get("preset")
                  or "MeshTest" not in orig_mobile["channels"],
                  orig_mobile["summary"])

    if not ctx.option("restore", True):
        return

    # Put the mobile back.
    radio = app.state()["radio"]
    if not ctx.check("connected to the mobile", radio["ready"] and radio["nodeId"] == mobile_node,
                     f"connected {radio['nodeId']} ready={radio['ready']}, mobile {mobile_node}"):
        return
    since = seq(app)
    log("restoring the mobile's original backup (the radio reboots)")
    try:
        r = app.cmd("backups.restoreOriginal", nodeNum=mobile_node, timeout=240)
    except BenchCommandError as e:
        ctx.check("backups.restoreOriginal ran", False, str(e))
        return
    ctx.check("restore reported steps", bool(r.get("steps")), str(r))
    ctx.check("restore cleared the mobile's role", r.get("rolesCleared") is True
              and app.state()["roles"]["mobile"] is None,
              str(app.state()["roles"]))
    back = wait_link(app, since, "ready", timeout=150)
    ctx.check("app reconnected to the mobile after its reboot", back is not None)
    radio = app.state()["radio"]
    if before is None and back is not None:
        ctx.check("app reads the original preset from the mobile",
                  radio["preset"] == orig_mobile.get("preset"),
                  f"{radio['preset']} vs {orig_mobile.get('preset')}")
    if before is not None and back is not None:
        ctx.check("app reads the original preset from the mobile",
                  radio["preset"] == before.lora.get("modem_preset"),
                  f"{radio['preset']} vs {before.lora.get('modem_preset')}")
        ctx.check("app's public-channel view matches the original",
                  radio["onPublicChannel"] == before.on_public_channel,
                  f"{radio['onPublicChannel']} vs {before.on_public_channel}")

    if ctx.option("verify_usb", True):
        log("waiting 20 s, then reading the mobile over USB")
        time.sleep(20)
        after = mt.snapshot(mobile_port(ctx))
        if before is not None:
            for c in compare_snapshot(before, after):
                ctx.check(f"mobile: {c.name}", c.ok, c.detail)
        else:
            got = _snapshot_view(after)
            want = _backup_view(orig_mobile)
            for key in ("preset", "region", "channels", "owner"):
                ctx.check(f"mobile: {key} as in its original backup", got[key] == want[key],
                          f"{got[key]} vs {want[key]}")
    log("NOTE: the mobile is back on its original settings and has no role; "
        "run `bench run radio-setup` before any other scenario.")
