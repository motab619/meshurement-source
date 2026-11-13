# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Report and MatrixReport: files written, markdown, resume bookkeeping."""

from __future__ import annotations

import json

from bench import report


def _row(key: str, status: str, **kw) -> report.MatrixRow:
    return report.MatrixRow(key=key, label=key, radios={"base": "meshtastic 2.8.1.8e6a88d",
                                                        "mobile": "meshtastic 2.7.26.abcdef0"},
                            status=status, **kw)


def test_scenario_report_write_and_written_path(tmp_path):
    rep = report.Report(started_at="2026-11-08T10:00:00", commit="abcdef1234567890", dirty=False,
                        phone={"platform": "ios"}, radios={})
    rep.scenarios.append(report.ScenarioResult("radio-setup", True, 12.0, [{"name": "a", "ok": True}]))
    path = rep.write(tmp_path)
    assert path == rep.written == tmp_path / "2026-11-08T100000-abcdef12.md"
    latest = json.loads((tmp_path / "latest.json").read_text())
    assert latest["passed"] is True
    assert "written" not in latest, "the local path is not part of the gate's JSON"
    assert "| radio-setup | pass | 12 |" in path.read_text()


def test_matrix_report_markdown_json_and_latest(tmp_path):
    rep = report.MatrixReport(started_at="2026-11-08T10:00:00", commit="abcdef1234567890", dirty=True,
                              phone={"platform": "ios", "id": "P"})
    rep.rows.append(_row("k1", "pass", seconds=300.4, flashed=["mobile"], report="/r/one.md",
                         scenarios=[{"name": "radio-setup", "passed": True, "skipped": ""}]))
    rep.rows.append(_row("k2", "fail", seconds=200, failed_checks=["radio-setup: base: modem preset MEDIUM_FAST (LONG_FAST)"]))
    rep.rows.append(_row("k3", "blocked", note="needs the operator: Forget base on the phone"))
    assert rep.passed is False
    path = rep.write(tmp_path)
    assert path == tmp_path / "matrix-2026-11-08T100000-abcdef12.md"
    md = path.read_text()
    assert "| # | base fw | mobile fw | result | s | failed checks | report |" in md
    assert "| 1 | meshtastic 2.8.1.8e6a88d | meshtastic 2.7.26.abcdef0 | pass | 300 |  | `one.md` |" in md
    assert "| 2 | " in md and "FAIL | 200 | radio-setup: base: modem preset MEDIUM_FAST (LONG_FAST) |" in md
    assert "BLOCKED: needs the operator: Forget base on the phone" in md
    assert "(dirty)" in md and "1/3 combos" in md
    latest = json.loads((tmp_path / report.MATRIX_LATEST).read_text())
    assert latest["passed"] is False
    assert [r["status"] for r in latest["rows"]] == ["pass", "fail", "blocked"]
    assert latest == json.loads((tmp_path / "matrix-2026-11-08T100000-abcdef12.json").read_text())
    assert report.latest_matrix(tmp_path) == latest
    assert report.latest_matrix(tmp_path / "none") is None


def test_passed_rows_for_resume(tmp_path):
    rep = report.MatrixReport(started_at="t", commit="c", dirty=False, phone={})
    rep.rows += [_row("k1", "pass"), _row("k2", "fail"), _row("k3", "blocked")]
    rep.write(tmp_path)
    prev = report.passed_rows(report.latest_matrix(tmp_path))
    assert list(prev) == ["k1"]
    assert prev["k1"].reused is True and prev["k1"].passed
    assert report.passed_rows(None) == {}
    # A row carried over says so in the table.
    rep2 = report.MatrixReport(started_at="t2", commit="c", dirty=False, phone={}, rows=[prev["k1"]])
    assert "pass (previous run)" in rep2.markdown()
    assert rep2.passed is True


def test_empty_matrix_is_not_a_pass():
    assert report.MatrixReport(started_at="t", commit="c", dirty=False, phone={}).passed is False
