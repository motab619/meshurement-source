# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Scenario: change the base from a distance (guided test, CLAUDE.md "Remote
base changes (Meshtastic only)"), verified over USB.

Depends on `radio-setup` having run on this phone + radio pair: Radio Setup
leaves the roles in the app (`/state` roles.base / roles.mobile), the
mobile's public key in the base's `security.admin_key`, and the phone
connected to the mobile. Without roles the scenario fails fast.

Sequence, the guided plan's changeRadios order (base first, then the
mobile, so they can hear each other again; then the same back):

  1. bench command `radio.setRemoteLora` on the connected mobile ->
     `MeshtasticRadio.setRemoteLora(base)`: get_config(LORA) for the
     session passkey, begin/set/commit PKI-encrypted to the base, waiting
     for the base's own ACKs (a lost ACK on the commit = sent: the base
     reboots). `confirmed` says whether the commit was acknowledged.
  2. Wait for the base to restart, read it over USB (an ESP32 base is
     rebooted afterwards, `serial_session`), check the preset (and power).
  3. The mobile follows over Bluetooth (`radio.setupConnected`, role
     mobile, no rename) so both are on the new preset.
  4. Back the same way, both verified again.

Options: preset (target; default: MEDIUM_SLOW, or MEDIUM_FAST when the base
is already on MEDIUM_SLOW), tx_power (dBm, optional, 0 = firmware max),
settle_secs (30: the base's reboot). Not yet run on hardware (2026-11-08).
"""

from __future__ import annotations

import time

from ..radios import meshtastic as mt
from . import Context, Skip

REQUIRES = ("radio-setup",)

_DEFAULT_TARGET = "MEDIUM_SLOW"
_FALLBACK_TARGET = "MEDIUM_FAST"


def pick_target(current: str | None, wanted: str | None) -> str:
    """The preset to switch to: the option, else one that differs from
    what the base is on now (a change to the same preset proves nothing)."""
    if wanted:
        if wanted == current:
            raise ValueError(f"preset {wanted} is what the base is on already")
        return wanted
    return _FALLBACK_TARGET if current == _DEFAULT_TARGET else _DEFAULT_TARGET


def run(ctx: Context) -> None:
    cfg, app, log = ctx.cfg, ctx.app, ctx.log
    base, mobile = cfg.radio("base"), cfg.radio("mobile")
    if base.protocol != "meshtastic" or mobile.protocol != "meshtastic":
        raise Skip("Meshtastic pair only (MeshCore companions have no remote admin)")

    # 0. Preconditions from radio-setup: roles in the app, the mobile connected.
    st = app.state()
    roles = st["roles"]
    if not ctx.check("roles set by radio-setup (base and mobile node)",
                     roles.get("base") is not None and roles.get("mobile") is not None,
                     f"roles {roles}; run `bench run radio-setup` first"):
        return
    radio = st["radio"]
    if not ctx.check("phone connected to the mobile radio",
                     radio.get("ready") and radio.get("nodeId") == roles["mobile"],
                     f"radio {radio.get('state')} node {radio.get('nodeId')} vs mobile {roles['mobile']}"):
        return
    before = roles.get("basePreset") or radio.get("preset")
    try:
        target = pick_target(before, ctx.options.get("preset"))
    except ValueError as e:
        ctx.check("a preset that differs from the base's", False, str(e))
        return
    tx_power = ctx.options.get("tx_power")
    tx_power = int(tx_power) if tx_power is not None else None
    settle = int(ctx.options.get("settle_secs", 30))
    log(f"base {roles['base']} on {before}; changing to {target}"
        + (f" at {tx_power} dBm" if tx_power is not None else "") + " and back")

    for leg, preset, power in (("there", target, tx_power), ("back", before, None)):
        if preset is None:
            ctx.check("the base's previous preset is known", False, "roles.basePreset and radio.preset empty")
            return
        # 1. Over the mesh, from the mobile.
        value = app.cmd("radio.setRemoteLora", timeout=180, nodeNum=roles["base"],
                        preset=preset, **({"txPower": power} if power is not None else {}))
        steps = value.get("steps", [])
        log(f"  steps: {steps}")
        ctx.check(f"{leg}: remote change to {preset} sent", bool(steps) and steps[-1] == "Done", str(steps))
        if not value.get("confirmed", True):
            log("  the base did not acknowledge the commit (reboot ate the ACK): verifying over USB")

        # 2. The truth: the base over USB (reboots an ESP32 afterwards).
        log(f"  waiting {settle}s for the base to restart, then reading it over USB")
        time.sleep(settle)
        snap = mt.read_then_reboot(base, log)
        ctx.check(f"{leg}: base holds modem preset {preset}", snap.lora.get("modem_preset") == preset,
                  str(snap.lora.get("modem_preset")))
        if power is not None:
            ctx.check(f"{leg}: base tx power {power}", snap.lora.get("tx_power") == power,
                      str(snap.lora.get("tx_power")))
        ctx.check(f"{leg}: base kept the MeshTest channel", not snap.on_public_channel,
                  str([c["name"] for c in snap.enabled_channels]))

        # 3. The mobile follows over Bluetooth, so the next leg can reach the base.
        app.cmd("radio.setupConnected", timeout=240, role="mobile", preset=preset, rename=False,
                **({"txPower": power} if power is not None else {}))
        try:
            app.wait_link("ready", timeout=120)
        except TimeoutError as e:
            ctx.check(f"{leg}: mobile back after its restart", False, str(e))
            return
        st = app.state()
        ctx.check(f"{leg}: mobile on {preset} too", st["radio"].get("preset") == preset,
                  str(st["radio"].get("preset")))
        ctx.check(f"{leg}: app remembers the base on {preset}", st["roles"].get("basePreset") == preset,
                  str(st["roles"].get("basePreset")))
