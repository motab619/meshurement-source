# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""report.Report write/latest round trip, markdown, and the gate (evaluate)."""

from __future__ import annotations

import json
import time

from bench import report
from bench.report import Report, ScenarioResult, evaluate

try:  # tests/ may or may not be a package in the merged tree
    from .gate_fixtures import no_network  # noqa: F401
except ImportError:
    from gate_fixtures import no_network  # noqa: F401

COMMIT = "4423f72abcdef0123456789abcdef0123456789a"


def _report(passed=True, tier="T2", started="2026-11-08T12:41:11"):
    checks = [{"name": "a", "ok": True, "detail": ""},
              {"name": "b", "ok": passed, "detail": "7 vs 8"}]
    return Report(started_at=started, commit=COMMIT, dirty=False,
                  phone={"platform": "ios", "id": "X", "desc": "iPhone SE iOS 17.5.1"},
                  radios={"base": {"board": "heltec-v3"}},
                  scenarios=[ScenarioResult("radio-setup", passed, 196.4, checks),
                             ScenarioResult("session", False, 0.0, [], skipped="no attenuator")],
                  tier=tier)


def test_passed_counts_skipped_as_fine():
    assert _report(True).passed
    assert not _report(False).passed


def test_write_and_latest_round_trip(tmp_path):
    rep = _report(False)
    md = rep.write(tmp_path / "reports")
    assert md.name == f"2026-11-08T124111-{COMMIT[:8]}.md"
    assert md.exists() and md.with_suffix(".json").exists()
    assert rep.finished_at                      # stamped by write
    got = report.latest(tmp_path / "reports")
    assert got == json.loads(md.with_suffix(".json").read_text())
    assert got["commit"] == COMMIT and got["passed"] is False and got["tier"] == "T2"
    assert [s["name"] for s in got["scenarios"]] == ["radio-setup", "session"]
    assert got["scenarios"][1]["skipped"] == "no attenuator"
    assert report.latest(tmp_path / "nothing") is None


def test_markdown(tmp_path):
    text = _report(False).markdown()
    assert text.startswith("# Bench run 2026-11-08T12:41:11")
    assert f"commit `{COMMIT[:12]}`" in text
    assert "- tier: T2" in text
    assert "**FAIL**" in text
    assert "| radio-setup | FAIL | 196 | b (7 vs 8) |" in text
    assert "| session | skipped: no attenuator | 0 |  |" in text
    assert "- base: {'board': 'heltec-v3'}" in text


def test_new_report_without_git(tmp_path):
    rep = report.new_report(tmp_path, {"platform": "ios-sim"}, {}, tier="T1")
    assert rep.commit == "unknown" and rep.dirty is False and rep.tier == "T1"
    assert time.strptime(rep.started_at, report.TIME_FMT)


# -- the gate ----------------------------------------------------------------

def _now_for(rep_dict, hours_later):
    t = time.mktime(time.strptime(rep_dict["started_at"], report.TIME_FMT))
    return t + hours_later * 3600


def test_evaluate_no_report():
    res = evaluate(None, where="/x/reports")
    assert res["ok"] is False and res["found"] is False
    assert "no bench report in /x/reports" in res["problems"][0]


def test_evaluate_fresh_passing_same_commit():
    d = _report(True).to_dict()
    res = evaluate(d, max_age_h=48, commit=COMMIT[:8].upper(), now=_now_for(d, 1))
    assert res["ok"] is True and res["problems"] == []
    assert res["passed"] and res["tier"] == "T2" and 0.9 < res["age_h"] < 1.1
    assert res["summary"].startswith("bench PASS  2026-11-08T12:41:11")
    assert "radio-setup: pass" in res["summary"]
    assert "session: skipped: no attenuator" in res["summary"]


def test_evaluate_failed():
    d = _report(False).to_dict()
    res = evaluate(d, max_age_h=48, commit=COMMIT, now=_now_for(d, 1))
    assert res["problems"] == ["latest run FAILED: radio-setup"]
    assert res["failed"] == ["radio-setup"]
    assert "radio-setup: FAIL  [b]" in res["summary"]


def test_evaluate_stale():
    d = _report(True).to_dict()
    res = evaluate(d, max_age_h=48, commit=COMMIT, now=_now_for(d, 72))
    assert res["problems"] == ["latest report is 72 h old (limit 48 h)"]
    # No limit: age is reported but not a problem.
    assert evaluate(d, commit=COMMIT, now=_now_for(d, 72))["ok"]


def test_evaluate_other_commit():
    d = _report(True).to_dict()
    res = evaluate(d, max_age_h=48, commit="deadbeef" * 5, now=_now_for(d, 1))
    assert res["problems"] == [f"latest report is for commit {COMMIT[:8]}, not deadbeef"]


def test_evaluate_simulator_run_is_flagged():
    d = _report(True, tier="T1").to_dict()
    res = evaluate(d, max_age_h=48, commit=COMMIT, now=_now_for(d, 1))
    assert res["problems"] == ["latest report is a T1 simulator run (no radios)"]


def test_evaluate_old_report_without_tier_or_finished_at():
    d = _report(True).to_dict()
    del d["tier"]
    d["finished_at"] = ""
    res = evaluate(d, max_age_h=48, commit=COMMIT, now=_now_for(d, 2))
    assert res["ok"] and res["tier"] == "T2" and 1.9 < res["age_h"] < 2.1


def test_evaluate_everything_wrong_lists_each_problem():
    d = _report(False, tier="T1").to_dict()
    res = evaluate(d, max_age_h=1, commit="0000000", now=_now_for(d, 5))
    assert len(res["problems"]) == 4
