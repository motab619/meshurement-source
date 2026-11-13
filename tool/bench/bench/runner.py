# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Run scenarios against the phone and write one report: the body of
`bench run`, shared with `bench matrix` (one call per firmware combo)."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Callable

from . import live, report
from .config import BenchConfig

REPO = Path(__file__).resolve().parents[3]
Log = Callable[[str], None]


class PhoneNotReady(RuntimeError):
    pass


def check_scenarios(names: list[str]) -> list[str]:
    """`all` → every scenario except `scenarios.SEPARATE`; raises KeyError naming
    unknown ones."""
    from . import scenarios
    out = ([n for n in scenarios.ALL if n not in scenarios.SEPARATE] if names == ["all"]
           else list(names))
    unknown = [n for n in out if n not in scenarios.ALL]
    if unknown:
        raise KeyError(f"unknown scenario(s) {unknown}; have {list(scenarios.ALL)}")
    return out


def parse_options(kvs: list[str] | None) -> dict[str, Any]:
    return dict(kv.split("=", 1) for kv in (kvs or []))


def run_scenarios(cfg: BenchConfig, names: list[str], options: dict[str, Any], log: Log,
                  *, launch: bool = True, verbose: bool = False,
                  phone: str | None = None) -> report.Report:
    """Launch the app in bench mode (unless it already runs), run `names` in
    order, write the report to `cfg.reports_dir` and return it (its
    `passed` is the verdict). Raises [PhoneNotReady] before touching anything."""
    from . import phones, scenarios
    from .app import AppLink, Forward

    names = check_scenarios(names)
    try:
        pcfg = cfg.phone_named(phone)
    except KeyError as e:
        raise PhoneNotReady(str(e)) from None
    dev = phones.for_config(pcfg)
    ok, why = dev.ready()
    if not ok:
        raise PhoneNotReady(f"phone not ready: {why}")
    # A simulator run (T1) uses no radios: the report says so.
    radios = {} if pcfg.simulator else {
        n: {"board": r.board, "protocol": r.protocol, "serial": r.serial, "firmware": r.firmware}
        for n, r in cfg.radios.items()}
    rep = report.new_report(REPO, {"name": pcfg.name, "platform": pcfg.platform, "id": pcfg.id,
                                   "desc": why}, radios, tier=pcfg.tier)
    if live.active():
        _live_start(cfg, pcfg, why, names, rep.commit)
    if launch:
        log(f"launching the app ({pcfg.name}: {' '.join(pcfg.launch_args())})")
        dev.launch(*pcfg.launch_args())
    with Forward(pcfg.platform, pcfg.id, pcfg.port):
        link = AppLink(port=pcfg.port, log=log if verbose else None)
        st = link.wait_up(timeout=90)
        log(f"app up: {st['app']}")
        for n in names:
            log(f"=== {n}")
            ctx = scenarios.Context(cfg=cfg, app=link, log=log, options=dict(options),
                                    phone=dev, scenario=n)
            live.emit("scenario_start", name=n)
            res = scenarios.ALL[n](ctx)
            rep.scenarios.append(res)
            live.emit("scenario_end", name=n, passed=res.passed, skipped=res.skipped,
                      seconds=round(res.seconds, 1))
            log(f"=== {n}: {'skipped: ' + res.skipped if res.skipped else 'PASS' if res.passed else 'FAIL'} "
                f"({res.seconds:.0f}s)")
    path = rep.write(cfg.reports_dir)
    log(f"report: {path} {'PASS' if rep.passed else 'FAIL'}")
    live.emit("run_end", passed=rep.passed, report=str(path))
    return rep


def _live_start(cfg: BenchConfig, pcfg: Any, desc: str, names: list[str], commit: str) -> None:
    """Tell the live page what is on the bench and what will run."""
    radios: dict[str, Any] = {}
    ports: dict[str, str] = {}
    if not pcfg.simulator:
        for n, r in cfg.radios.items():
            radios[n] = {"board": r.board, "protocol": r.protocol, "role": r.role,
                         "firmware": r.firmware}
            try:
                ports[r.port()] = n
            except Exception:  # noqa: BLE001 - unplugged: the page shows it idle
                radios[n]["unplugged"] = True
    live.map_ports(ports)
    live.emit("run_start", phone={"name": pcfg.name, "platform": pcfg.platform,
                                  "tier": pcfg.tier, "desc": desc},
              radios=radios, scenarios=names, commit=commit,
              expected=live.last_checks(cfg.reports_dir, names))
