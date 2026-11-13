# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""The live view's feed (bench/live.py): silent without a page server,
an SSE stream with a replayed backlog once serving, report replays."""

from __future__ import annotations

import json
import threading
import urllib.request

import pytest

from bench import live
from bench.scenarios import Context


@pytest.fixture
def served():
    url = live.serve(0, open_browser=False)
    yield url
    live.stop()


def _read_events(url: str, n: int, timeout: float = 5) -> list[dict]:
    """The first `n` events from /feed."""
    out: list[dict] = []
    with urllib.request.urlopen(url + "feed", timeout=timeout) as r:
        for raw in r:
            line = raw.decode().strip()
            if line.startswith("data: "):
                out.append(json.loads(line[6:]))
                if len(out) >= n:
                    break
    return out


def test_emit_is_a_noop_without_a_server():
    live.stop()
    live.emit("check", name="x", ok=True)
    assert not live.active()
    with live.usb("/dev/cu.x"):
        pass  # no error, nothing recorded


def test_page_and_history(served):
    html = urllib.request.urlopen(served, timeout=5).read().decode()
    assert "<title>Meshurement Bench</title>" in html
    live.emit("log", text="hello")
    hist = json.loads(urllib.request.urlopen(served + "history", timeout=5).read())
    assert [e["type"] for e in hist] == ["log"] and hist[0]["text"] == "hello"


def test_feed_replays_backlog_then_follows(served):
    live.emit("scenario_start", name="radio-setup")
    got: list[dict] = []
    t = threading.Thread(target=lambda: got.extend(_read_events(served, 2)))
    t.start()
    assert live.wait_for_page(5)
    live.emit("check", scenario="radio-setup", name="a", ok=True)
    t.join(5)
    assert [e["type"] for e in got] == ["scenario_start", "check"]
    assert got[0]["replay"] is True and "replay" not in got[1]


def test_usb_maps_ports_to_radio_names(served):
    live.map_ports({"/dev/cu.usbmodem1": "mobile"})
    with live.usb("/dev/cu.usbmodem1"):
        pass
    with pytest.raises(RuntimeError):
        with live.usb("base"):
            raise RuntimeError("serial gone")
    hist = json.loads(urllib.request.urlopen(served + "history", timeout=5).read())
    assert [(e["radio"], e["phase"], e.get("ok")) for e in hist] == [
        ("mobile", "start", None), ("mobile", "end", True),
        ("base", "start", None), ("base", "end", False)]


def test_context_check_reports_to_the_feed(served):
    ctx = Context(cfg=None, app=None, log=lambda s: None, scenario="exports")  # type: ignore[arg-type]
    ctx.check("csv has rows", False, "0 rows")
    hist = json.loads(urllib.request.urlopen(served + "history", timeout=5).read())
    assert hist[-1] | {"seq": 0, "t": 0} == {"seq": 0, "t": 0, "type": "check", "scenario": "exports",
                                             "name": "csv has rows", "ok": False, "detail": "0 rows"}


def test_reset_is_not_kept_for_later_pages(served):
    live.emit("log", text="old")
    live.reset()
    hist = json.loads(urllib.request.urlopen(served + "history", timeout=5).read())
    assert hist == []


REPORT = {
    "started_at": "2026-11-08T12:41:11", "commit": "fe669b09", "passed": True, "tier": "T2",
    "phone": {"name": "phone", "platform": "ios"},
    "radios": {"base": {"board": "heltec-v3", "protocol": "meshtastic"},
               "mobile": {"board": "t1000-e", "protocol": "meshtastic"}},
    "scenarios": [{"name": "radio-setup", "passed": True, "seconds": 196, "skipped": "",
                   "checks": [{"name": f"c{i}", "ok": True, "detail": ""} for i in range(10)]}],
}


def test_replay_events_shape_and_pace():
    evs = list(live.replay_events(REPORT, total_s=20))
    types = [t for _, t, _ in evs]
    assert types[0] == "run_start" and types[-1] == "run_end"
    assert types.count("check") == 10
    start = evs[0][2]
    assert start["radios"]["base"]["role"] == "base" and start["radios"]["mobile"]["role"] == "mobile"
    assert start["expected"] == {"radio-setup": [f"c{i}" for i in range(10)]}
    assert start["phone"]["tier"] == "T2"
    check_delays = [d for d, t, _ in evs if t == "check"]
    assert all(d == pytest.approx(2.0) for d in check_delays)


def test_play_emits_everything(served):
    live.play(REPORT, total_s=1, sleep=lambda s: None)
    hist = json.loads(urllib.request.urlopen(served + "history", timeout=5).read())
    assert hist[0]["type"] == "run_start" and hist[-1]["type"] == "run_end"


def test_last_checks_takes_the_newest_report_per_scenario(tmp_path):
    def write(stem: str, scen: list[dict]) -> None:
        (tmp_path / f"{stem}.json").write_text(json.dumps({"scenarios": scen}))
    write("2026-11-01T100000-aaaa", [{"name": "exports", "checks": [{"name": "old"}]}])
    write("2026-11-02T100000-bbbb", [{"name": "exports", "checks": [{"name": "new"}]},
                                     {"name": "backups", "skipped": "no", "checks": [{"name": "x"}]}])
    (tmp_path / "latest.json").write_text("{}")
    got = live.last_checks(tmp_path, ["exports", "backups", "smoke"])
    assert got == {"exports": ["new"]}
