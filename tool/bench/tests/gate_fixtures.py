# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Fixtures for the test_gate_* files (imported by them, not a conftest.py,
so other agents' conftest fixtures stay untouched)."""

from __future__ import annotations

import urllib.request

import pytest


@pytest.fixture(autouse=True)
def no_network(monkeypatch):
    """Any urllib call that is not to the local stub server fails loudly."""
    real = urllib.request.urlopen

    def guarded(req, *a, **kw):
        url = req.full_url if hasattr(req, "full_url") else str(req)
        if url.startswith("http://127.0.0.1:"):
            return real(req, *a, **kw)
        raise AssertionError(f"network call in a test: {url}")

    monkeypatch.setattr(urllib.request, "urlopen", guarded)
