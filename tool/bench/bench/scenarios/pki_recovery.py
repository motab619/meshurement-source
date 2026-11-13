# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Scenario 6 (base side): PKI recovery.

A session pings the base until one is `received`. Then the base's node
list is cleared over USB (`reset_node_db`, favourites too; the Heltec's
reboot waits until the end, because a booting node asks every node for its
NodeInfo and would learn the key straight back): it no
longer holds the mobile's public key, so the next DM it gets is a
`PKI_UNKNOWN_PUBKEY` NAK (the app records `error:PKI_UNKNOWN_PUBKEY`). On
that NAK `MeshtasticRadio` re-adds the saved key (`ensureContact`) and
resends our NodeInfo to the base, at most once a minute, so a later ping
is `received` again. The check is the outcome sequence of the `ping`
events: received → error:PKI_* → received.

The mirror case (the *mobile* forgets the base: a local
`PKI_SEND_FAIL_PUBLIC_KEY` NAK on firmware ≥ 2.7.19) is not here: clearing
the mobile's node list over USB drops the phone's link and is a separate
scenario.

Options: ping_secs (10), lat/lon, require_nak (false: a firmware that
answers without the mobile's key passes when pings keep being answered;
true makes a missing PKI NAK a failure). Bench 2026-11-09, base Heltec
2.8.1 + mobile T1000-E 2.7.26: the base's list no longer held the mobile
(read over USB) and it answered all 13 pings, no NAK, so on this pair the
app's key recovery is never needed. When a NAK does come, the
NAK-then-received sequence is still checked.

Needs radio-setup. First hardware runs 2026-11-09: no NAK, because the
reset kept favourites and the reboot after it re-learned the key; both
changed.
"""

from __future__ import annotations

from ..app import BenchCommandError
from ..radios import meshtastic as mt
from . import Context, Skip
from .common import (
    MARGIN_SEC, REPLY_TIMEOUT_SEC, base_write, create_map, end_session, pings_after, reboot_base,
    seq,
    start_session, test_psk, wait_pings, wait_until,
)

needs = ("radio-setup",)

#: `MeshtasticRadio._lastKeyExchange`: a key exchange at most once a minute.
KEY_EXCHANGE_THROTTLE_SEC = 60


def run(ctx: Context) -> None:
    app, log = ctx.app, ctx.log
    base = ctx.cfg.radio("base")
    if base.protocol != "meshtastic":
        raise Skip("Meshtastic base only (PKI is a Meshtastic feature)")
    if app.state()["session"] is not None:
        end_session(ctx)
    test_psk(app)  # the phone did run Radio Setup
    map_id = create_map(ctx, "Bench PKI")
    since0 = seq(app)
    try:
        row = start_session(ctx, map_id, ping_sec=int(ctx.option("ping_secs", 10)),
                            name="bench pki")
    except BenchCommandError as e:
        ctx.check("session starts", False, str(e))
        return
    interval = int(row["ping_interval_sec"])
    try:
        outcomes = wait_pings(app, since0, 1, status="received",
                              timeout=3 * interval + REPLY_TIMEOUT_SEC + MARGIN_SEC)
        if not ctx.check("baseline ping received by the base", "received" in outcomes,
                         str(outcomes)):
            return

        since = seq(app)
        # No reboot here: a booting node broadcasts its NodeInfo asking every
        # node to answer, so the base had the mobile's key back before the
        # next ping (bench 2026-11-09, 16 pings all received). The phone
        # never talks to the base over Bluetooth here; it reboots at the end.
        write_s = base_write(ctx, "node list reset (forgets the mobile's key)",
                             lambda p: mt.reset_node_db(p), reboot=False)
        # The base is deaf while it reboots; afterwards our DM is a NAK.
        budget = 3 * interval + REPLY_TIMEOUT_SEC + MARGIN_SEC
        wait_until(app, lambda: any(s.startswith("error:PKI") for s in pings_after(app, since)),
                   timeout=budget, what="PKI NAK")
        seen = pings_after(app, since)
        nak = next((s for s in seen if s.startswith("error:PKI")), None)
        if ctx.option("require_nak", False):
            ctx.check(f"a PKI NAK came back (write took {write_s:.0f}s)", nak is not None,
                      f"outcomes: {seen}")
        else:
            log(f"PKI NAK: {nak or 'none (this firmware answers without the key)'}; "
                f"outcomes so far {seen}")
            ctx.check("pings answered after the base forgot the mobile",
                      nak is not None or seen.count("received") >= 2, f"outcomes: {seen}")
        # Recovery: the key goes back and our NodeInfo is resent (≤ 1/min).
        wait_until(app, lambda: _recovered(pings_after(app, since)),
                   timeout=KEY_EXCHANGE_THROTTLE_SEC + 3 * interval + REPLY_TIMEOUT_SEC + MARGIN_SEC,
                   what="recovery")
        seen = pings_after(app, since)
        ctx.check("a later ping is received again", _recovered(seen), f"outcomes: {seen}")
        if nak is not None:
            ctx.check("sequence is NAK then received",
                      seen.index(nak) < len(seen) - 1 - seen[::-1].index("received")
                      if "received" in seen else False, str(seen))
    finally:
        end_session(ctx)
        reboot_base(ctx)


def _recovered(outcomes: list[str]) -> bool:
    """A `received` after the last error (or after anything, when no
    error was ever reported)."""
    errors = [i for i, s in enumerate(outcomes) if s.startswith("error:")]
    start = errors[-1] + 1 if errors else 0
    return "received" in outcomes[start:]
