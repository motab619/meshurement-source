# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""bench matrix: config, plan (flash vs reuse), dry-run text, run loop with
fakes (flash, scenarios, operator prompt), resume and unattended."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from bench import config, matrix, report
from bench.config import BenchConfig

from .conftest import write_bench_toml

FULL = {"meshtastic": {"latest": "2.8.1.8e6a88d", "pre": "2.8.2.1111111", "2.8.1": "2.8.1.8e6a88d",
                       "2.7.26": "2.7.26.abcdef0"},
        "meshcore": {"latest": "1.18.0", "1.18.0": "1.18.0"}}


def fake_resolver(cache: Path, table=FULL) -> matrix.Resolver:
    return matrix.Resolver(cache, lookup=lambda proto, ver: table.get(proto, {}).get(ver))


# -- config -------------------------------------------------------------------

def test_parse_target():
    assert matrix.parse_target("meshtastic 2.8.1") == matrix.Target("meshtastic", "2.8.1")
    assert str(matrix.parse_target("meshcore latest")) == "meshcore latest"
    for bad in ("meshtastic", "lora 2.8.1", "meshtastic 2.8.1 extra"):
        with pytest.raises(ValueError):
            matrix.parse_target(bad)


def test_combos_from_config(bench: BenchConfig):
    combos = matrix.combos_from(bench)
    assert [c.index for c in combos] == [1, 2, 3]
    assert combos[0].radios == {"base": matrix.Target("meshtastic", "2.8.1"),
                                "mobile": matrix.Target("meshtastic", "2.7.26")}
    assert combos[0].scenarios == ("radio-setup", "remote-base-change")
    assert combos[2].scenarios == ("radio-setup",), "per-combo override"
    assert combos[0].label == "base=meshtastic 2.8.1 mobile=meshtastic 2.7.26"
    assert combos[0].key == "base=meshtastic:2.8.1 mobile=meshtastic:2.7.26"
    assert combos[0].key != combos[1].key


def test_combos_validation(tmp_path):
    def load(matrix_toml: str) -> BenchConfig:
        return config.load(write_bench_toml(tmp_path, matrix=matrix_toml))

    with pytest.raises(ValueError, match="no \\[matrix\\]"):
        matrix.combos_from(load(""))
    with pytest.raises(ValueError, match="no \\[radios.observer\\]"):
        matrix.combos_from(load('[matrix]\nscenarios=["radio-setup"]\ncombos=[{ observer = "meshtastic 2.8.1" }]'))
    with pytest.raises(ValueError, match="unknown scenario"):
        matrix.combos_from(load('[matrix]\nscenarios=["nope"]\ncombos=[{ base = "meshtastic 2.8.1" }]'))
    with pytest.raises(ValueError, match="no scenarios"):
        matrix.combos_from(load('[matrix]\ncombos=[{ base = "meshtastic 2.8.1" }]'))
    with pytest.raises(ValueError, match="names no radio"):
        matrix.combos_from(load('[matrix]\nscenarios=["radio-setup"]\ncombos=[{ scenarios = ["radio-setup"] }]'))


def test_flashed_json_overlays_bench_toml(bench: BenchConfig, fresh_bench: BenchConfig):
    assert bench.radio("base").firmware == "2.8.1.8e6a88d"
    assert bench.radio("mobile").firmware == "2.7.26.abcdef0"
    assert fresh_bench.radio("base").firmware is None
    assert fresh_bench.radio("base").protocol == "meshtastic"


# -- plan ---------------------------------------------------------------------

def test_version_matches():
    assert matrix.version_matches("2.8.1.8e6a88d", "2.8.1")
    assert matrix.version_matches("2.8.1.8e6a88d", "2.8.1.8e6a88d")
    assert not matrix.version_matches("2.8.10.aaaaaaa", "2.8.1")
    assert not matrix.version_matches("2.8.1.8e6a88d", "2.8.1.0000000")
    assert not matrix.version_matches(None, "2.8.1")
    assert matrix.version_matches("1.18.0", "1.18.0")


def test_plan_flashes_only_what_differs(bench: BenchConfig):
    combos = matrix.combos_from(bench)
    res = fake_resolver(bench.firmware_cache)
    plans = matrix.plan(bench, combos, res)
    # combo 1: both already on it.
    assert plans[0].flashes == [] and plans[0].reused == {"base": "meshtastic 2.8.1.8e6a88d",
                                                          "mobile": "meshtastic 2.7.26.abcdef0"}
    # combo 2: the mobile moves to 2.8.1; nRF52, no bond lost.
    [f] = plans[1].flashes
    assert (f.radio, f.target.version, f.resolved, f.bond_lost) == ("mobile", "2.8.1", "2.8.1.8e6a88d", False)
    assert f.reason == "now meshtastic 2.7.26.abcdef0"
    assert plans[1].reused == {"base": "meshtastic 2.8.1.8e6a88d"}
    assert not plans[1].needs_operator
    # combo 3: `latest` resolves to what the base already runs; the mobile changes protocol.
    assert plans[2].reused == {"base": "meshtastic 2.8.1.8e6a88d"}
    [f] = plans[2].flashes
    assert (f.radio, f.target.protocol, f.resolved) == ("mobile", "meshcore", "1.18.0")


def test_plan_reflash_and_never_flashed(bench: BenchConfig, fresh_bench: BenchConfig):
    combos = matrix.combos_from(bench)
    plans = matrix.plan(bench, combos[:1], fake_resolver(bench.firmware_cache), reflash=True)
    assert [f.radio for f in plans[0].flashes] == ["base", "mobile"]
    assert {f.reason for f in plans[0].flashes} == {"--reflash"}
    assert plans[0].flashes[0].bond_lost is True, "the Heltec: operator pause"
    assert plans[0].needs_operator

    plans = matrix.plan(fresh_bench, matrix.combos_from(fresh_bench)[:1], fake_resolver(fresh_bench.firmware_cache))
    assert [f.radio for f in plans[0].flashes] == ["base", "mobile"]
    assert plans[0].flashes[0].reason.startswith("never flashed by the bench")


def test_plan_unresolved_version_is_shown_not_fatal(bench: BenchConfig):
    res = fake_resolver(bench.firmware_cache, table={})
    plans = matrix.plan(bench, matrix.combos_from(bench)[2:], res)
    # The base's `latest` could not be resolved, so it is flashed, not kept.
    assert [f.radio for f in plans[0].flashes] == ["base", "mobile"]
    assert all(f.resolved is None for f in plans[0].flashes)
    text = matrix.format_plan(plans, res)
    assert "base: flash meshtastic latest -> UNRESOLVED" in text
    assert "mobile: flash meshcore 1.18.0 -> UNRESOLVED" in text


def test_resolver_memoizes_and_falls_back_to_cache(bench: BenchConfig, monkeypatch):
    from bench import firmware
    calls = []

    def boom(proto, ver):
        calls.append((proto, ver))
        raise OSError("offline")

    monkeypatch.setattr(firmware, "resolve", boom)
    (bench.firmware_cache / "meshtastic" / "2.8.1.8e6a88d").mkdir(parents=True)
    res = matrix.Resolver(bench.firmware_cache)
    t = matrix.Target("meshtastic", "2.8.1")
    assert res.full_version(t) == "2.8.1.8e6a88d"
    assert res.full_version(t) == "2.8.1.8e6a88d"
    assert res.full_version(matrix.Target("meshtastic", "latest")) is None
    assert calls == [("meshtastic", "2.8.1"), ("meshtastic", "latest")], "one GitHub ask per target"
    assert "OSError" in res.errors[t]


def test_format_plan(bench: BenchConfig):
    res = fake_resolver(bench.firmware_cache)
    plans = matrix.plan(bench, matrix.combos_from(bench), res, passed_before={matrix.combos_from(bench)[0].key: object()})
    text = matrix.format_plan(plans, res)
    assert "combo 1: base=meshtastic 2.8.1 mobile=meshtastic 2.7.26" in text
    assert "skip: passed in the previous run (--resume)" in text
    assert "base: keep, already meshtastic 2.8.1.8e6a88d" in text
    assert "mobile: flash meshtastic 2.8.1 -> 2.8.1.8e6a88d  (now meshtastic 2.7.26.abcdef0)" in text
    assert "Forget This Device" not in text, "no ESP32 flashed"


# -- the run loop ---------------------------------------------------------------

class FakeBench:
    """Flash and scenario stand-ins: a flash rewrites flashed.json like the
    real one; scenarios pass unless `fail` names the combo's mobile version."""

    def __init__(self, cfg: BenchConfig, *, fail: set[str] = frozenset(), flash_error: str | None = None):
        self.cfg = cfg
        self.fail = fail
        self.flash_error = flash_error
        self.flashed: list[tuple[str, str, str]] = []
        self.runs: list[tuple[dict[str, str], list[str]]] = []
        self.prompts: list[str] = []

    def flash(self, cfg, radio, protocol, version, log, **kw):
        if self.flash_error and radio.name == self.flash_error:
            raise RuntimeError("esptool failed: no port")
        self.flashed.append((radio.name, protocol, version))
        p = cfg.firmware_cache / "flashed.json"
        state = json.loads(p.read_text()) if p.exists() else {}
        state[radio.serial] = {"protocol": protocol, "version": FULL[protocol][version], "at": "now"}
        p.write_text(json.dumps(state))

    def run(self, cfg, names, options, log, *, launch, verbose):
        fw = {n: f"{r.protocol} {r.firmware}" for n, r in cfg.radios.items()}
        self.runs.append((fw, list(names)))
        rep = report.Report(started_at="t", commit="c", dirty=False, phone={}, radios={})
        for n in names:
            bad = cfg.radio("mobile").firmware in self.fail
            rep.scenarios.append(report.ScenarioResult(
                n, not bad, 5.0, [{"name": "modem preset", "ok": not bad, "detail": "LONG_FAST"}]))
        rep.write(cfg.reports_dir)
        return rep

    def prompt(self, msg: str) -> None:
        self.prompts.append(msg)

    def go(self, **kw) -> report.MatrixReport:
        return matrix.run_matrix(self.cfg, matrix.combos_from(self.cfg), {}, lambda s: None,
                                 prompt=self.prompt, flash_fn=self.flash, run_fn=self.run,
                                 reload_fn=config.load, resolver=fake_resolver(self.cfg.firmware_cache), **kw)


def test_run_matrix_flashes_between_combos_and_reports(bench: BenchConfig):
    fb = FakeBench(bench, fail={"2.8.1.8e6a88d"})
    rep = fb.go()
    # Combo 1 reused both; combo 2 flashed the mobile; combo 3 moved it to MeshCore.
    assert fb.flashed == [("mobile", "meshtastic", "2.8.1"), ("mobile", "meshcore", "1.18.0")]
    assert [r.status for r in rep.rows] == ["pass", "fail", "pass"]
    assert rep.rows[1].flashed == ["mobile"]
    assert rep.rows[1].radios == {"base": "meshtastic 2.8.1.8e6a88d", "mobile": "meshtastic 2.8.1.8e6a88d"}
    assert rep.rows[1].failed_checks == ["radio-setup: modem preset (LONG_FAST)",
                                         "remote-base-change: modem preset (LONG_FAST)"]
    assert rep.rows[2].radios["mobile"] == "meshcore 1.18.0"
    assert fb.runs[2][1] == ["radio-setup"], "per-combo scenario list"
    assert fb.prompts == [], "nRF52 flashes need no operator"
    assert all(r.report.endswith(".md") for r in rep.rows)
    latest = report.latest_matrix(bench.reports_dir)
    assert latest and [r["status"] for r in latest["rows"]] == ["pass", "fail", "pass"]
    assert (bench.reports_dir / (rep.stem + ".md")).exists()


def test_run_matrix_esp32_flash_pauses_or_blocks(bench: BenchConfig):
    fb = FakeBench(bench)
    rep = fb.go(reflash=True, only=[1])
    assert [f[0] for f in fb.flashed] == ["base", "mobile"]
    assert len(fb.prompts) == 1 and "Forget This Device" in fb.prompts[0] and "base" in fb.prompts[0]
    assert rep.rows[0].status == "pass" and rep.rows[0].flashed == ["base", "mobile"]

    fb = FakeBench(bench)
    rep = fb.go(reflash=True, only=[1], unattended=True)
    assert fb.prompts == [] and fb.runs == []
    assert rep.rows[0].status == "blocked"
    assert "Forget base" in rep.rows[0].note
    assert rep.passed is False


def test_run_matrix_flash_failure_blocks_the_cell_and_goes_on(bench: BenchConfig):
    fb = FakeBench(bench, flash_error="mobile")
    rep = fb.go()
    assert [r.status for r in rep.rows] == ["pass", "blocked", "blocked"]
    assert "RuntimeError: esptool failed" in rep.rows[1].note
    assert rep.rows[1].radios["mobile"] == "meshtastic 2.7.26.abcdef0", "what it still runs"
    assert len(fb.runs) == 1


def test_run_matrix_resume_skips_passed_combos(bench: BenchConfig):
    fb = FakeBench(bench, fail={"2.8.1.8e6a88d"})
    first = fb.go()
    assert [r.status for r in first.rows] == ["pass", "fail", "pass"]
    # Second run with --resume: combos 1 and 3 are carried over, 2 runs again (the
    # mobile is on MeshCore now, so it is flashed back to 2.8.1 first).
    fb2 = FakeBench(config.load(bench.path))
    second = fb2.go(resume=True)
    assert fb2.flashed == [("mobile", "meshtastic", "2.8.1")]
    assert [(r.status, r.reused) for r in second.rows] == [("pass", True), ("pass", False), ("pass", True)]
    assert len(fb2.runs) == 1
    md = (bench.reports_dir / (second.stem + ".md")).read_text()
    assert md.count("(previous run)") == 2
    assert second.passed


def test_run_matrix_without_resume_runs_everything(bench: BenchConfig):
    fb = FakeBench(bench)
    fb.go()
    fb2 = FakeBench(config.load(bench.path))
    fb2.go()
    assert len(fb2.runs) == 3
