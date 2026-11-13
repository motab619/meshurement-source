# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Scenario 3: public channel refusal.

Over USB the mobile's primary channel goes back to the firmware default
(the 1-byte LongFast key); the app, reconnected, must report
`onPublicChannel` and `session.start` must refuse with the public-channel
message (`SessionManager.startSession`). Then the MeshTest key is written
back (read from the phone: `prefs.get test_channel_psk`), the app
reconnects, a session starts and is ended.

Options: name (primary channel name written with the default key, default
"" = the firmware default; "LongFast" also works), ping_secs (10), lat/lon
(map location).

Needs radio-setup (roles set, phone connected to the mobile). The mobile is
an nRF52 on the bench: a serial client only drops its BLE link for a few
seconds; when the link holds, `radio.reconnect` makes the app re-read the
channel. Nothing here has run on hardware yet (written 2026-11-08).
"""

from __future__ import annotations

from ..app import BenchCommandError
from ..radios import meshtastic as mt
from . import Context, Skip
from .common import (
    create_map, end_session, mobile_port, reconnect_if_needed, seq, start_session, test_psk,
)

needs = ("radio-setup",)


def run(ctx: Context) -> None:
    app, log = ctx.app, ctx.log
    mobile = ctx.cfg.radio("mobile")
    if mobile.protocol != "meshtastic":
        raise Skip("Meshtastic mobile only (the serial stand-in writes a Meshtastic channel)")
    if app.state()["session"] is not None:
        end_session(ctx)
    psk = test_psk(app)
    ping_secs = ctx.option("ping_secs", 10)
    name = ctx.option("name", "")
    map_id = create_map(ctx, "Bench refusal")
    port = mobile_port(ctx)

    # 1. Default key on the mobile.
    since = seq(app)
    log(f"mobile over USB: primary channel -> default 1-byte key, name {name!r}")
    mt.set_primary_psk(port, mt.DEFAULT_PSK, name=name)
    reconnect_if_needed(ctx, since)
    radio = app.state()["radio"]
    ctx.check("app sees the mobile on the public channel",
              radio["onPublicChannel"] is True,
              f"onPublicChannel={radio['onPublicChannel']} primary={radio['primaryChannel']!r}")

    # 2. A session must not start there.
    try:
        sid = app.cmd("session.start", mapId=map_id, pingIntervalSec=ping_secs,
                      name="bench refusal", timeout=60)
        ctx.check("session.start refuses on the public channel", False,
                  f"started session {sid}")
        end_session(ctx)
    except BenchCommandError as e:
        ctx.check("session.start refuses on the public channel",
                  "public channel" in str(e), str(e))
    ctx.check("no session is running", app.state()["session"] is None)

    # 3. MeshTest key back.
    since = seq(app)
    log("mobile over USB: primary channel -> MeshTest key")
    mt.set_primary_psk(port, psk, name="MeshTest")
    reconnect_if_needed(ctx, since)
    radio = app.state()["radio"]
    ctx.check("mobile back on the MeshTest channel",
              radio["onPublicChannel"] is False and radio["primaryChannel"] == "MeshTest",
              f"onPublicChannel={radio['onPublicChannel']} primary={radio['primaryChannel']!r}")

    # 4. Now a session starts.
    try:
        row = start_session(ctx, map_id, ping_sec=ping_secs, name="bench refusal ok")
    except BenchCommandError as e:
        ctx.check("session starts on the test channel", False, str(e))
        return
    ctx.check("session starts on the test channel", True)
    ctx.check("session row records the preset", bool(row.get("lora_preset")),
              str(row.get("lora_preset")))
    end_session(ctx)
    ctx.check("session ended", app.state()["session"] is None)
