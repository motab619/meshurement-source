# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""`bench matrix`: the firmware matrix (docs/design/bench-rig/README.md §6).

`[matrix]` in bench.toml lists combos (one firmware per radio) and the
scenarios to run on each. For every combo the bench flashes only what
differs from what `flashed.json` says a radio runs (`config.load` overlays
it as `radio.protocol` / `radio.firmware`), pauses for the operator when an
ESP32 was flashed (its Bluetooth bond is gone: Settings → Bluetooth →
Forget This Device on the phone), runs the scenarios like `bench run` and
appends a row to ONE matrix report. The report is rewritten after every
combo, so an interrupted run can `--resume`: combos the last report passed
are skipped and carried over.

Hardware state is never assumed from bench.toml alone: the "already on"
decision reads `flashed.json`, so a radio flashed outside `bench flash`
(a UF2 copied by hand) must be flashed once by the bench (or `--reflash`).
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from . import config, firmware, live, report
from .config import BenchConfig, RadioConfig

Log = Callable[[str], None]

PROTOCOLS = ("meshtastic", "meshcore")


# -- what bench.toml asks for -------------------------------------------------

@dataclass(frozen=True)
class Target:
    protocol: str
    version: str   # as written: 2.8.1 | 2.8.1.8e6a88d | 1.18.0 | latest | pre

    def __str__(self) -> str:
        return f"{self.protocol} {self.version}"


def parse_target(text: str) -> Target:
    """`"meshtastic 2.8.1"` → Target. Protocol and version, one space."""
    parts = str(text).split()
    if len(parts) != 2 or parts[0] not in PROTOCOLS:
        raise ValueError(f"firmware {text!r}: want '<meshtastic|meshcore> <version>'")
    return Target(parts[0], parts[1])


@dataclass(frozen=True)
class Combo:
    index: int                       # 1-based position in [matrix].combos
    radios: dict[str, Target]        # radio name -> target
    scenarios: tuple[str, ...]

    @property
    def key(self) -> str:
        """Stable id for --resume: the targets as written, in radio order."""
        return " ".join(f"{n}={t.protocol}:{t.version}" for n, t in sorted(self.radios.items()))

    @property
    def label(self) -> str:
        return " ".join(f"{n}={t}" for n, t in self.radios.items())

    def __hash__(self) -> int:
        return hash(self.key)


def combos_from(cfg: BenchConfig) -> list[Combo]:
    """The matrix cells, validated against `[radios.*]` and the scenario list."""
    from . import scenarios
    m = cfg.matrix
    if m is None or not m.combos:
        raise ValueError(f"no [matrix] combos in {cfg.path}; see bench.toml.example")
    out: list[Combo] = []
    for i, raw in enumerate(m.combos, 1):
        names = list(raw.get("scenarios", m.scenarios))
        if not names:
            raise ValueError(f"[matrix] combo {i}: no scenarios (set [matrix].scenarios)")
        unknown = [n for n in names if n not in scenarios.ALL]
        if unknown:
            raise ValueError(f"[matrix] combo {i}: unknown scenario(s) {unknown}; "
                             f"have {list(scenarios.ALL)}")
        radios: dict[str, Target] = {}
        for k, v in raw.items():
            if k == "scenarios":
                continue
            if k not in cfg.radios:
                raise ValueError(f"[matrix] combo {i}: no [radios.{k}] in {cfg.path}")
            radios[k] = parse_target(v)
        if not radios:
            raise ValueError(f"[matrix] combo {i}: names no radio")
        # bench.toml order of [radios.*], not the inline table's.
        ordered = {n: radios[n] for n in cfg.radios if n in radios}
        out.append(Combo(i, ordered, tuple(names)))
    return out


# -- versions ----------------------------------------------------------------

def version_matches(current: str | None, want: str) -> bool:
    """Is a radio on `current` (fully qualified, from flashed.json) already
    on `want` as written in [matrix]? `2.8.1` matches `2.8.1.8e6a88d`."""
    if not current:
        return False
    return current == want or current.startswith(want + ".")


class Resolver:
    """`latest` / `pre` / a prefix → the release's full version, asked once
    per (protocol, version) from GitHub (read-only); offline, the newest
    matching download in the firmware cache; else None (shown as such)."""

    def __init__(self, cache: Path, lookup: Callable[[str, str], str | None] | None = None):
        self.cache = cache
        self._lookup = lookup or self._github
        self._memo: dict[Target, str | None] = {}
        self.errors: dict[Target, str] = {}

    def _github(self, protocol: str, version: str) -> str | None:
        try:
            return firmware.resolve(protocol, version).version
        except Exception as e:  # noqa: BLE001 - offline, rate limit, unknown version
            self.errors[Target(protocol, version)] = f"{type(e).__name__}: {e}"
            return firmware.cached_version(self.cache, protocol, version)

    def full_version(self, t: Target) -> str | None:
        if t not in self._memo:
            self._memo[t] = self._lookup(t.protocol, t.version)
        return self._memo[t]


# -- the plan ----------------------------------------------------------------

@dataclass
class FlashStep:
    radio: str
    target: Target
    resolved: str | None          # full version the target resolves to (None: unknown)
    reason: str                   # "now meshtastic 2.7.26.abc" | "never flashed by the bench" | "--reflash"
    bond_lost: bool               # ESP32: operator must Forget This Device afterwards


@dataclass
class ComboPlan:
    combo: Combo
    flashes: list[FlashStep] = field(default_factory=list)
    reused: dict[str, str] = field(default_factory=dict)    # radio -> "meshtastic 2.8.1.8e6a88d"
    skipped: str = ""             # --resume: passed in the previous run

    @property
    def needs_operator(self) -> bool:
        return any(f.bond_lost for f in self.flashes)


def plan(cfg: BenchConfig, combos: list[Combo], resolver: Resolver, *,
         reflash: bool = False, passed_before: dict[str, Any] | None = None) -> list[ComboPlan]:
    """What each combo would flash and what it reuses, from the radios'
    recorded state (`cfg.radios[].protocol/firmware`). The state is NOT
    carried from one combo to the next here: `run_matrix` re-plans each
    combo after reloading the config, so this is the picture at the start
    (what `--dry-run` prints), per combo against the radios as they are."""
    out: list[ComboPlan] = []
    for c in combos:
        cp = ComboPlan(c)
        if passed_before and c.key in passed_before:
            cp.skipped = "passed in the previous run (--resume)"
            out.append(cp)
            continue
        plan_combo(cfg, c, resolver, cp, reflash=reflash)
        out.append(cp)
    return out


def plan_combo(cfg: BenchConfig, c: Combo, resolver: Resolver, cp: ComboPlan | None = None,
               *, reflash: bool = False) -> ComboPlan:
    """The flash steps for one combo against the radios' current state."""
    from .provision import bond_lost_by_flash
    cp = cp or ComboPlan(c)
    cp.flashes.clear()
    cp.reused.clear()
    for name, t in c.radios.items():
        r: RadioConfig = cfg.radio(name)
        full = resolver.full_version(t) if t.version in ("latest", "pre") else None
        want_versions = [v for v in (t.version, full) if v]
        on_it = r.protocol == t.protocol and any(version_matches(r.firmware, v) for v in want_versions)
        if on_it and not reflash:
            cp.reused[name] = f"{r.protocol} {r.firmware}"
            continue
        if reflash and on_it:
            reason = "--reflash"
        elif r.firmware is None:
            reason = f"never flashed by the bench (bench.toml says {r.protocol})"
        else:
            reason = f"now {r.protocol} {r.firmware}"
        resolved = full if full else resolver.full_version(t)
        cp.flashes.append(FlashStep(name, t, resolved, reason, bond_lost_by_flash(r)))
    return cp


def format_plan(plans: list[ComboPlan], resolver: Resolver) -> str:
    lines: list[str] = []
    for cp in plans:
        c = cp.combo
        lines.append(f"combo {c.index}: {c.label}  scenarios {list(c.scenarios)}")
        if cp.skipped:
            lines.append(f"  skip: {cp.skipped}")
            continue
        for name, have in cp.reused.items():
            lines.append(f"  {name}: keep, already {have}")
        for f in cp.flashes:
            res = f.resolved or "UNRESOLVED (offline and not cached?)"
            lines.append(f"  {f.radio}: flash {f.target} -> {res}  ({f.reason})"
                         + ("  [then Forget This Device on the phone]" if f.bond_lost else ""))
    if resolver.errors:
        lines.append("")
        lines.append("lookups that failed (GitHub unreachable or no such release):")
        for t, e in resolver.errors.items():
            lines.append(f"  {t}: {e}")
    return "\n".join(lines)


# -- running -----------------------------------------------------------------

Prompt = Callable[[str], None]


def run_matrix(cfg: BenchConfig, combos: list[Combo], options: dict[str, Any], log: Log, *,
               reflash: bool = False, resume: bool = False, unattended: bool = False,
               only: list[int] | None = None, boot_wait: int = 30, verbose: bool = False,
               prompt: Prompt | None = None,
               flash_fn: Callable[..., Any] | None = None,
               run_fn: Callable[..., report.Report] | None = None,
               reload_fn: Callable[[Path], BenchConfig] | None = None,
               resolver: Resolver | None = None) -> report.MatrixReport:
    """Flash, pause, run, record: one row per combo. The `*_fn` seams are
    for tests; the defaults talk to real radios and the phone."""
    from .provision import flash_radio
    from .runner import REPO, run_scenarios

    flash_fn = flash_fn or flash_radio
    run_fn = run_fn or run_scenarios
    reload_fn = reload_fn or config.load
    resolver = resolver or Resolver(cfg.firmware_cache)
    prompt = prompt or _stdin_prompt
    phone = {"platform": cfg.phone.platform, "id": cfg.phone.id} if cfg.phone else {}
    rep = report.new_matrix_report(REPO, phone)
    previous = report.passed_rows(report.latest_matrix(cfg.reports_dir)) if resume else {}
    for c in combos:
        if only and c.index not in only:
            continue
        if c.key in previous:
            log(f"=== combo {c.index} {c.label}: passed in the previous run, carried over")
            rep.rows.append(previous[c.key])
            rep.write(cfg.reports_dir)
            continue
        log(f"=== combo {c.index}: {c.label}")
        live.emit("combo_start", index=c.index, label=c.label)
        t0 = time.time()
        row = report.MatrixRow(key=c.key, label=c.label, radios={}, status="blocked")
        cp = plan_combo(cfg, c, resolver, reflash=reflash)
        for name, have in cp.reused.items():
            log(f"  {name}: already {have}")
        try:
            for f in cp.flashes:
                log(f"  {f.radio}: flashing {f.target} ({f.reason})")
                flash_fn(cfg, cfg.radio(f.radio), f.target.protocol, f.target.version, log,
                         boot_wait=boot_wait)
                row.flashed.append(f.radio)
            cfg = reload_fn(cfg.path)
            row.radios = {n: f"{cfg.radio(n).protocol} {cfg.radio(n).firmware or '?'}" for n in c.radios}
            forget = [f.radio for f in cp.flashes if f.bond_lost]
            if forget:
                if unattended:
                    row.note = (f"needs the operator: Forget {', '.join(forget)} on the phone "
                                "(ESP32 flash dropped the Bluetooth bond)")
                    log(f"  blocked: {row.note}")
                    row.seconds = time.time() - t0
                    rep.rows.append(row)
                    rep.write(cfg.reports_dir)
                    continue
                for name in forget:
                    prompt(f"{name} was flashed and lost its Bluetooth bond. On the phone: "
                           f"Settings → Bluetooth → Forget This Device ({name}), then press Enter")
            r = run_fn(cfg, list(c.scenarios), dict(options), log, launch=True, verbose=verbose)
            row.status = "pass" if r.passed else "fail"
            row.report = str(r.written or "")
            row.scenarios = [{"name": s.name, "passed": s.passed, "skipped": s.skipped}
                             for s in r.scenarios]
            row.failed_checks = [f"{s.name}: {ch['name']}" + (f" ({ch['detail']})" if ch.get("detail") else "")
                                 for s in r.scenarios for ch in s.checks if not ch["ok"]]
        except KeyboardInterrupt:
            row.note = "interrupted"
            row.seconds = time.time() - t0
            rep.rows.append(row)
            rep.write(cfg.reports_dir)
            raise
        except Exception as e:  # noqa: BLE001 - a crash blocks the cell, the matrix goes on
            row.note = f"{type(e).__name__}: {e}"
            log(f"  blocked: {row.note}")
            if not row.radios:
                row.radios = {n: f"{cfg.radio(n).protocol} {cfg.radio(n).firmware or '?'}"
                              for n in c.radios}
        row.seconds = time.time() - t0
        rep.rows.append(row)
        rep.write(cfg.reports_dir)
        log(f"=== combo {c.index}: {row.status.upper()} ({row.seconds:.0f}s)")
        live.emit("combo_end", index=c.index, label=c.label, status=row.status, note=row.note)
    return rep


def _stdin_prompt(msg: str) -> None:
    input(f"\n>>> {msg} ")
