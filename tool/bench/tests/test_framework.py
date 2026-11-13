# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""`timed` with `needs`, the canonical order, options."""

from __future__ import annotations

from bench import scenarios
from bench.scenarios import Context, Skip, timed

from .conftest import FakeApp, base_state, fake_config


def _ctx(roles: bool) -> Context:
    return Context(cfg=fake_config(), app=FakeApp(base_state(roles=roles)), log=lambda s: None)


def test_needs_radio_setup_fails_fast_without_roles() -> None:
    ran = []
    run = timed("x", lambda ctx: ran.append(1), needs=("radio-setup",))
    res = run(_ctx(roles=False))
    assert not res.passed and not ran
    assert len(res.checks) == 1
    assert "radio-setup" in res.checks[0]["name"]
    assert "bench run radio-setup" in res.checks[0]["detail"]


def test_needs_satisfied_runs_the_scenario() -> None:
    run = timed("x", lambda ctx: ctx.check("did it", True), needs=("radio-setup",))
    res = run(_ctx(roles=True))
    assert res.passed and [c["name"] for c in res.checks] == ["did it"]


def test_skip_and_crash() -> None:
    def boom(ctx: Context) -> None:
        raise RuntimeError("no")
    res = timed("x", boom)(_ctx(True))
    assert not res.passed and "RuntimeError: no" in res.checks[0]["detail"]

    def skip(ctx: Context) -> None:
        raise Skip("no attenuator")
    res = timed("x", skip)(_ctx(True))
    assert res.skipped == "no attenuator" and res.passed


def test_all_order_and_needs() -> None:
    names = [n for n in scenarios.ALL if n not in scenarios.SEPARATE]
    assert names[0] == "radio-setup" and names[-1] == "backups"
    assert set(names) == {"radio-setup", "public-channel-refusal", "recorded-session",
                          "pki-recovery", "remote-base-change", "exports", "backups"}
    assert scenarios.SEPARATE <= set(scenarios.ALL)
    for n in names[1:]:
        assert scenarios.ALL[n].needs == ("radio-setup",), n  # type: ignore[attr-defined]
    assert scenarios.ALL["radio-setup"].needs == ()  # type: ignore[attr-defined]


def test_ordered() -> None:
    assert scenarios.ordered(["backups", "radio-setup", "exports"]) == \
        ["radio-setup", "exports", "backups"]
    assert scenarios.ordered(["exports", "nope", "exports"]) == ["exports", "nope"]


def test_options_convert_to_default_type() -> None:
    ctx = Context(cfg=fake_config(), app=FakeApp(base_state()), log=lambda s: None,
                  options={"ping_secs": "7", "beacon_off": "false", "lat": "1.5", "name": "LongFast"})
    assert ctx.option("ping_secs", 10) == 7
    assert ctx.option("beacon_off", True) is False
    assert ctx.option("lat", 33.0) == 1.5
    assert ctx.option("name", "") == "LongFast"
    assert ctx.option("missing", 3) == 3
