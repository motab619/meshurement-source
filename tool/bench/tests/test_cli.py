# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""`bench matrix --dry-run` end to end through argparse, no hardware, no network."""

from __future__ import annotations

from bench import cli, config, matrix


def test_matrix_dry_run_prints_the_plan(bench, monkeypatch, capsys):
    monkeypatch.setattr(config, "load", lambda path=None: bench)
    table = {"meshtastic": {"latest": "2.8.1.8e6a88d", "2.8.1": "2.8.1.8e6a88d", "2.7.26": "2.7.26.abcdef0"},
             "meshcore": {"1.18.0": "1.18.0"}}
    real = matrix.Resolver
    monkeypatch.setattr(matrix, "Resolver", lambda cache: real(cache, lookup=lambda p, v: table[p].get(v)))
    assert cli.main(["matrix", "--dry-run"]) == 0
    out = capsys.readouterr().out
    assert "combo 1: base=meshtastic 2.8.1 mobile=meshtastic 2.7.26" in out
    assert "mobile: keep, already meshtastic 2.7.26.abcdef0" in out
    assert "combo 2:" in out and "mobile: flash meshtastic 2.8.1 -> 2.8.1.8e6a88d" in out
    assert "combo 3:" in out and "mobile: flash meshcore 1.18.0 -> 1.18.0" in out
    assert "3 combo(s), 2 flash(es), 0 with an operator pause" in out


def test_matrix_dry_run_reflash_counts_operator_pauses(bench, monkeypatch, capsys):
    monkeypatch.setattr(config, "load", lambda path=None: bench)
    real = matrix.Resolver
    monkeypatch.setattr(matrix, "Resolver", lambda cache: real(cache, lookup=lambda p, v: None))
    assert cli.main(["matrix", "--dry-run", "--reflash", "--combo", "1", "--unattended"]) == 0
    out = capsys.readouterr().out
    assert "base: flash meshtastic 2.8.1 -> UNRESOLVED" in out
    assert "[then Forget This Device on the phone]" in out
    assert "1 combo(s), 2 flash(es), 1 with an operator pause (blocked with --unattended)" in out


def test_matrix_without_config_section_exits_clearly(fresh_bench, monkeypatch, capsys):
    fresh_bench.matrix = None
    monkeypatch.setattr(config, "load", lambda path=None: fresh_bench)
    try:
        cli.main(["matrix", "--dry-run"])
    except SystemExit as e:
        assert "no [matrix] combos" in str(e)
    else:
        raise AssertionError("expected SystemExit")
