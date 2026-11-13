# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""One report per bench run: JSON for the fastlane gate, Markdown for Andy.
`MatrixReport`: one per `bench matrix` run, a row per firmware combo.

`Report.write` files `<started>-<commit>.json/.md` and overwrites
`latest.json`; `latest()` reads that back and `evaluate()` is the release
gate's judgement (`bench latest --json`, fastlane `bench_check`).
"""

from __future__ import annotations

import json
import subprocess
import time
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any

TIME_FMT = "%Y-%m-%dT%H:%M:%S"


@dataclass
class ScenarioResult:
    name: str
    passed: bool
    seconds: float
    checks: list[dict[str, Any]] = field(default_factory=list)
    skipped: str = ""          # why, when not run (no attenuator, old firmware...)
    artifacts: list[str] = field(default_factory=list)


@dataclass
class Report:
    started_at: str
    commit: str
    dirty: bool
    phone: dict[str, Any]
    radios: dict[str, Any]           # name -> snapshot summary (firmware, node id)
    scenarios: list[ScenarioResult] = field(default_factory=list)
    finished_at: str = ""
    tier: str = "T2"                 # T1 simulator (no radios) | T2 bench | T3 matrix

    # Where `write` put the markdown (not a field: stays out of the JSON).
    written: Path | None = field(default=None, init=False, repr=False, compare=False)

    @property
    def passed(self) -> bool:
        return all(s.passed or s.skipped for s in self.scenarios)

    def to_dict(self) -> dict[str, Any]:
        d = {k: v for k, v in asdict(self).items() if k != "written"}
        return d | {"passed": self.passed}

    def write(self, reports_dir: Path) -> Path:
        reports_dir.mkdir(parents=True, exist_ok=True)
        self.finished_at = _now()
        stem = f"{self.started_at.replace(':', '')}-{self.commit[:8]}"
        text = json.dumps(self.to_dict(), indent=2)
        (reports_dir / f"{stem}.json").write_text(text)
        (reports_dir / f"{stem}.md").write_text(self.markdown())
        (reports_dir / "latest.json").write_text(text)
        self.written = reports_dir / f"{stem}.md"
        return self.written

    def markdown(self) -> str:
        lines = [f"# Bench run {self.started_at}",
                 "",
                 f"- commit `{self.commit[:12]}`{' (dirty)' if self.dirty else ''}",
                 f"- tier: {self.tier}",
                 f"- phone: {self.phone}",
                 f"- result: **{'PASS' if self.passed else 'FAIL'}**",
                 ""]
        for name, r in self.radios.items():
            lines.append(f"- {name}: {r}")
        lines.append("")
        lines.append("| scenario | result | s | failed checks |")
        lines.append("|---|---|---|---|")
        for s in self.scenarios:
            res = f"skipped: {s.skipped}" if s.skipped else ("pass" if s.passed else "FAIL")
            failed = "; ".join(f"{c['name']} ({c.get('detail', '')})"
                               for c in s.checks if not c["ok"])
            lines.append(f"| {s.name} | {res} | {s.seconds:.0f} | {failed} |")
        return "\n".join(lines) + "\n"


def _now() -> str:
    return time.strftime(TIME_FMT)


def git_state(repo: Path) -> tuple[str, bool]:
    def run(*a: str) -> str:
        return subprocess.run(["git", "-C", str(repo), *a], capture_output=True,
                              text=True, check=False).stdout.strip()
    return run("rev-parse", "HEAD") or "unknown", bool(run("status", "--porcelain"))


def new_report(repo: Path, phone: dict[str, Any], radios: dict[str, Any],
               tier: str = "T2") -> Report:
    commit, dirty = git_state(repo)
    return Report(started_at=_now(), commit=commit, dirty=dirty, phone=phone, radios=radios,
                  tier=tier)


def latest(reports_dir: Path) -> dict[str, Any] | None:
    p = reports_dir / "latest.json"
    return json.loads(p.read_text()) if p.exists() else None


# -- firmware matrix ---------------------------------------------------------

MATRIX_LATEST = "matrix-latest.json"


@dataclass
class MatrixRow:
    """One cell of the firmware matrix (README §6)."""
    key: str                      # stable id of the combo (what --resume matches on)
    label: str                    # "base=meshtastic 2.8.1 mobile=meshtastic 2.7.26"
    radios: dict[str, str]        # radio name -> what it really ran, "meshtastic 2.8.1.8e6a88d"
    status: str                   # pass | fail | blocked
    seconds: float = 0.0
    failed_checks: list[str] = field(default_factory=list)
    flashed: list[str] = field(default_factory=list)   # radios flashed for this cell
    note: str = ""                # why blocked, or other context
    report: str = ""              # the per-run report (.md) for this cell
    scenarios: list[dict[str, Any]] = field(default_factory=list)  # name, passed, skipped
    reused: bool = False          # carried over from the previous run by --resume

    @property
    def passed(self) -> bool:
        return self.status == "pass"


@dataclass
class MatrixReport:
    started_at: str
    commit: str
    dirty: bool
    phone: dict[str, Any]
    rows: list[MatrixRow] = field(default_factory=list)
    finished_at: str = ""

    @property
    def passed(self) -> bool:
        return bool(self.rows) and all(r.passed for r in self.rows)

    @property
    def stem(self) -> str:
        return f"matrix-{self.started_at.replace(':', '')}-{self.commit[:8]}"

    def row_for(self, key: str) -> MatrixRow | None:
        return next((r for r in self.rows if r.key == key), None)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self) | {"passed": self.passed}

    def write(self, reports_dir: Path) -> Path:
        """Write (or rewrite, after every combo) the json + markdown and
        `matrix-latest.json`; an interrupted run leaves its rows behind."""
        reports_dir.mkdir(parents=True, exist_ok=True)
        self.finished_at = _now()
        text = json.dumps(self.to_dict(), indent=2)
        (reports_dir / f"{self.stem}.json").write_text(text)
        (reports_dir / f"{self.stem}.md").write_text(self.markdown())
        (reports_dir / MATRIX_LATEST).write_text(text)
        return reports_dir / f"{self.stem}.md"

    def markdown(self) -> str:
        names: list[str] = []
        for r in self.rows:
            for n in r.radios:
                if n not in names:
                    names.append(n)
        lines = [f"# Bench matrix {self.started_at}",
                 "",
                 f"- commit `{self.commit[:12]}`{' (dirty)' if self.dirty else ''}",
                 f"- phone: {self.phone}",
                 f"- result: **{'PASS' if self.passed else 'FAIL'}** "
                 f"({sum(r.passed for r in self.rows)}/{len(self.rows)} combos)",
                 "",
                 "| # | " + " | ".join(f"{n} fw" for n in names) + " | result | s | failed checks | report |",
                 "|---|" + "---|" * len(names) + "---|---|---|---|"]
        for i, r in enumerate(self.rows, 1):
            res = r.status.upper() if r.status != "pass" else "pass"
            if r.reused:
                res += " (previous run)"
            if r.note:
                res += f": {r.note}"
            fws = " | ".join(r.radios.get(n, "") for n in names)
            rep = f"`{Path(r.report).name}`" if r.report else ""
            lines.append(f"| {i} | {fws} | {res} | {r.seconds:.0f} | "
                         f"{'; '.join(r.failed_checks)} | {rep} |")
        return "\n".join(lines) + "\n"


def new_matrix_report(repo: Path, phone: dict[str, Any]) -> MatrixReport:
    commit, dirty = git_state(repo)
    return MatrixReport(started_at=_now(), commit=commit, dirty=dirty, phone=phone)


def latest_matrix(reports_dir: Path) -> dict[str, Any] | None:
    p = reports_dir / MATRIX_LATEST
    return json.loads(p.read_text()) if p.exists() else None


def passed_rows(previous: dict[str, Any] | None) -> dict[str, MatrixRow]:
    """The combos a previous matrix run passed, by key: what `--resume`
    skips (and carries into the new report, marked `reused`)."""
    out: dict[str, MatrixRow] = {}
    for raw in (previous or {}).get("rows", []):
        if raw.get("status") == "pass":
            row = MatrixRow(**{k: v for k, v in raw.items() if k in MatrixRow.__dataclass_fields__})
            row.reused = True
            out[row.key] = row
    return out

# -- the gate ----------------------------------------------------------------

def _epoch(stamp: str) -> float | None:
    try:
        return time.mktime(time.strptime(stamp, TIME_FMT))
    except (TypeError, ValueError):
        return None


def _same_commit(a: str, b: str) -> bool:
    a, b = a.lower(), b.lower()
    return bool(a) and bool(b) and (a.startswith(b) or b.startswith(a))


def evaluate(rep: dict[str, Any] | None, *, max_age_h: float | None = None,
             commit: str | None = None, now: float | None = None,
             where: str = "") -> dict[str, Any]:
    """The release gate's view of the latest report (bench-rig §7).

    Returns {"ok", "problems": [...], "summary": str, ...report facts}. A
    problem is: no report, a failed scenario, older than `max_age_h`, a
    different commit than `commit`, or a T1 simulator run (no radios). The
    caller (fastlane `bench_check`) decides whether a problem warns or fails.
    """
    if rep is None:
        return {"ok": False, "found": False,
                "problems": [f"no bench report{' in ' + where if where else ''}: "
                             "run `bench run all` first"],
                "summary": "no bench report"}
    problems: list[str] = []
    tier = rep.get("tier", "T2")
    scen = rep.get("scenarios", [])
    failed = [s["name"] for s in scen if not (s.get("passed") or s.get("skipped"))]
    if not rep.get("passed", False) or failed:
        problems.append(f"latest run FAILED: {', '.join(failed) or 'no scenarios'}")
    stamp = rep.get("finished_at") or rep.get("started_at") or ""
    age_h: float | None = None
    t = _epoch(stamp)
    if t is not None:
        age_h = ((now if now is not None else time.time()) - t) / 3600
        if max_age_h is not None and age_h > max_age_h:
            problems.append(f"latest report is {age_h:.0f} h old (limit {max_age_h:g} h)")
    elif max_age_h is not None:
        problems.append(f"latest report has no readable timestamp ({stamp!r})")
    if commit and not _same_commit(rep.get("commit", ""), commit):
        problems.append(f"latest report is for commit {rep.get('commit', '?')[:8]}, "
                        f"not {commit[:8]}")
    if tier == "T1":
        problems.append("latest report is a T1 simulator run (no radios)")
    phone = rep.get("phone", {})
    lines = [f"bench {'PASS' if rep.get('passed') else 'FAIL'}  {stamp}"
             + (f"  ({age_h:.1f} h ago)" if age_h is not None else "")
             + f"  commit {rep.get('commit', '?')[:8]}{' dirty' if rep.get('dirty') else ''}"
             f"  tier {tier}  phone {phone.get('desc') or phone.get('platform', '?')}"]
    for s in scen:
        res = f"skipped: {s['skipped']}" if s.get("skipped") else "pass" if s.get("passed") else "FAIL"
        bad = [c["name"] for c in s.get("checks", []) if not c.get("ok")]
        lines.append(f"  {s['name']}: {res}" + (f"  [{'; '.join(bad)}]" if bad else ""))
    return {"ok": not problems, "found": True, "problems": problems,
            "summary": "\n".join(lines), "passed": bool(rep.get("passed")),
            "commit": rep.get("commit"), "dirty": rep.get("dirty"), "tier": tier,
            "started_at": rep.get("started_at"), "finished_at": rep.get("finished_at"),
            "age_h": age_h, "failed": failed}
