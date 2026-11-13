# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Bench scenarios (docs/design/bench-rig/README.md §5). Each is a function
`run(ctx) -> ScenarioResult`; `ALL` maps the CLI name to it, in the order
`bench run all` uses: `radio-setup` first (it puts both radios on the
MeshTest channel and sets the roles everything else needs), `backups` last
(it puts the mobile back on its original settings, undoing Radio Setup).

A scenario module may declare `needs = ("radio-setup",)`: `timed` then
checks the precondition on /state before running it, so `bench run
recorded-session` on a phone without roles fails fast with one clear check
instead of a confusing BLE or session error."""

from __future__ import annotations

import contextlib
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Iterator

from .. import config, live
from ..app import AppLink
from ..report import ScenarioResult


@dataclass
class Context:
    cfg: config.BenchConfig
    app: AppLink
    log: Callable[[str], None]
    options: dict[str, Any] = field(default_factory=dict)
    checks: list[dict[str, Any]] = field(default_factory=list)
    # The phone backend (phones/ios.py, phones/android.py), for what the app
    # can't do itself: the system Bluetooth pairing dialog. None in tests.
    phone: Any = None
    scenario: str = ""   # for the live page

    def check(self, name: str, ok: bool, detail: str = "") -> bool:
        self.checks.append({"name": name, "ok": bool(ok), "detail": detail})
        live.emit("check", scenario=self.scenario, name=name, ok=bool(ok), detail=str(detail)[:300])
        self.log(f"{'ok  ' if ok else 'FAIL'} {name}" + (f"  [{detail}]" if detail and not ok else ""))
        return bool(ok)

    def option(self, key: str, default: Any) -> Any:
        """A `-o key=value` option, converted to `default`'s type."""
        v = self.options.get(key)
        if v is None:
            return default
        if isinstance(default, bool):
            return str(v).lower() in ("1", "true", "yes", "on")
        if isinstance(default, (int, float)) and not isinstance(v, (int, float)):
            return type(default)(v)
        return v

    @contextlib.contextmanager
    def pairing_watch(self, every: float = 1.5) -> Iterator[list[float]]:
        """While the app connects to a radio, keep answering the system's
        Bluetooth pairing dialog (`phone.accept_pairing()`, Android; a no-op
        on iOS). Yields the list of times (s since entry) a dialog was tapped."""
        taps: list[float] = []
        phone = self.phone
        if phone is None or not hasattr(phone, "accept_pairing"):
            yield taps
            return
        stop = threading.Event()
        t0 = time.time()

        def loop() -> None:
            while not stop.wait(every):
                try:
                    if phone.accept_pairing():
                        taps.append(round(time.time() - t0, 1))
                        self.log(f"  pairing dialog: tapped Pair ({taps[-1]:.0f}s)")
                        live.emit("pairing", at=taps[-1])
                except Exception as e:  # noqa: BLE001 - never fail the scenario from here
                    self.log(f"  pairing watch: {type(e).__name__}: {e}")

        th = threading.Thread(target=loop, daemon=True)
        th.start()
        try:
            yield taps
        finally:
            stop.set()
            th.join(timeout=every * 2 + 30)



class Skip(Exception):
    """Raise to mark a scenario as skipped (missing hardware, firmware...)."""


class Precondition(Exception):
    """A `needs` entry is not satisfied; the scenario is not run."""


def _roles_set(ctx: Context) -> None:
    roles = ctx.app.state().get("roles", {})
    if roles.get("base") is None or roles.get("mobile") is None:
        raise Precondition(
            "Radio Setup has not run on this phone (/state shows no base/mobile "
            f"roles: {roles.get('base')}/{roles.get('mobile')}); run "
            "`bench run radio-setup` first")


#: What each `needs` name means on the phone.
PRECONDITIONS: dict[str, Callable[[Context], None]] = {
    "radio-setup": _roles_set,
}


def timed(name: str, fn: Callable[[Context], None],
          needs: tuple[str, ...] = ()) -> Callable[[Context], ScenarioResult]:
    def run(ctx: Context) -> ScenarioResult:
        t0 = time.time()
        skipped = ""
        try:
            for need in needs:
                PRECONDITIONS[need](ctx)
            fn(ctx)
        except Precondition as p:
            ctx.check(f"{name}: needs {', '.join(needs)}", False, str(p))
        except Skip as s:
            skipped = str(s)
        except Exception as e:  # noqa: BLE001 - a crash is a failed scenario
            ctx.check(f"{name} ran to the end", False, f"{type(e).__name__}: {e}")
        return ScenarioResult(name=name, passed=all(c["ok"] for c in ctx.checks),
                              seconds=time.time() - t0, checks=ctx.checks, skipped=skipped)
    run.needs = needs  # type: ignore[attr-defined]
    return run


from . import (  # noqa: E402
    backups, exports, meshcore_session, pki_recovery, public_channel_refusal, radio_setup,
    radio_setup_meshcore, recorded_session, remote_base_change, smoke,
)

ALL: dict[str, Callable[[Context], ScenarioResult]] = {
    "smoke": timed("smoke", smoke.run),
    "radio-setup": timed("radio-setup", radio_setup.run),
    "public-channel-refusal": timed("public-channel-refusal", public_channel_refusal.run,
                                    needs=public_channel_refusal.needs),
    "recorded-session": timed("recorded-session", recorded_session.run,
                              needs=recorded_session.needs),
    "pki-recovery": timed("pki-recovery", pki_recovery.run, needs=pki_recovery.needs),
    "remote-base-change": timed("remote-base-change", remote_base_change.run,
                                needs=remote_base_change.REQUIRES),
    "exports": timed("exports", exports.run, needs=exports.needs),
    # MeshCore pair (own Radio Setup; verified through the app, design §5.1).
    "radio-setup-meshcore": timed("radio-setup-meshcore", radio_setup_meshcore.run),
    "meshcore-session": timed("meshcore-session", meshcore_session.run),
    # Simulator (T1): no radios, demo mode.
    "smoke": timed("smoke", smoke.run),
    # Last: it undoes Radio Setup on the mobile.
    "backups": timed("backups", backups.run, needs=backups.needs),
}


#: Runnable by name but not part of `bench run all`: they need the other
#: protocol's pair (MeshCore) or no radios at all (simulator smoke), and
#: `radio-setup-meshcore` replaces the Meshtastic roles.
SEPARATE: frozenset[str] = frozenset({"radio-setup-meshcore", "meshcore-session", "smoke"})

# What each scenario needs to have run first (the matrix and `bench run` warn
# when the order is off).
REQUIRES: dict[str, tuple[str, ...]] = {
    n: getattr(f, "needs", ()) for n, f in ALL.items() if getattr(f, "needs", ())
}


def ordered(names: list[str]) -> list[str]:
    """`names` in `ALL`'s order (radio-setup first, backups last), duplicates
    dropped. Unknown names are kept at the end for the CLI to reject."""
    known = [n for n in ALL if n in names]
    return known + [n for n in names if n not in ALL]
