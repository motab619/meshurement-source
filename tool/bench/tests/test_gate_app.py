# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""app.AppLink against a tiny threaded stand-in for the app's bench server."""

from __future__ import annotations

import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import pytest

from bench.app import AppLink, BenchCommandError, Event, Forward

try:  # tests/ may or may not be a package in the merged tree
    from .gate_fixtures import no_network  # noqa: F401
except ImportError:
    from gate_fixtures import no_network  # noqa: F401


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # quiet
        pass

    def _json(self, obj, status=200):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        srv = self.server
        if u.path == "/state":
            self._json({"app": {"bench": True, "demo": False}, "seq": len(srv.events)})
        elif u.path == "/events":
            qs = parse_qs(u.query)
            since = int(qs.get("since", ["0"])[0])
            srv.waits.append(qs.get("wait", [None])[0])
            new = [e for e in srv.events if e["seq"] > since]
            if not new:
                time.sleep(0.02)      # a short "long poll"
            self._json(new)
        else:
            self._json({"error": "no"}, 404)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        srv = self.server
        srv.cmds.append(body)
        cmd, args = body["cmd"], body.get("args", {})
        if cmd == "ping":
            self._json({"ok": True, "value": "pong"})
        elif cmd == "echo":
            self._json({"ok": True, "value": args})
        elif cmd == "emit":
            srv.add(args["type"], **args.get("data", {}))
            self._json({"ok": True, "value": True})
        elif cmd == "db.query":
            self._json({"ok": True, "value": [{"count(*)": 4}] if "count" in args["sql"] else []})
        elif cmd == "slow":
            time.sleep(args.get("s", 0.3))
            self._json({"ok": True, "value": "done"})
        else:
            self._json({"ok": False, "error": f"Invalid argument(s): unknown command {cmd}"})


class _Server(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self):
        super().__init__(("127.0.0.1", 0), _Handler)
        self.events: list[dict] = []
        self.cmds: list[dict] = []
        self.waits: list[str | None] = []    # the `wait` query of every /events poll

    def add(self, type_, **data):
        self.events.append({"seq": len(self.events) + 1, "t": "2026-11-08T12:00:00.000",
                            "type": type_, **data})


@pytest.fixture
def server():
    srv = _Server()
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    yield srv
    srv.shutdown()
    srv.server_close()


@pytest.fixture
def link(server):
    return AppLink(port=server.server_address[1])


def test_state_and_wait_up(link):
    assert link.state()["app"]["bench"] is True
    assert link.wait_up(timeout=5)["app"]["bench"] is True


def test_wait_up_times_out_on_a_dead_port():
    dead = AppLink(port=1)        # nothing listens on tcp/1
    t0 = time.time()
    with pytest.raises(TimeoutError, match="bench server not answering"):
        dead.wait_up(timeout=0.2)
    assert time.time() - t0 < 5


def test_cmd_ok_and_args(link, server):
    assert link.cmd("ping") == "pong"
    assert link.cmd("echo", key="test_channel_psk", n=3) == {"key": "test_channel_psk", "n": 3}
    assert server.cmds[-1] == {"cmd": "echo", "args": {"key": "test_channel_psk", "n": 3}}
    assert server.cmds[0] == {"cmd": "ping", "args": {}}


def test_cmd_error(link):
    with pytest.raises(BenchCommandError, match="nope: Invalid argument.*unknown command nope"):
        link.cmd("nope")


def test_cmd_pumps_events_meanwhile(link, server):
    server.add("link", state="ready")
    t0 = time.time()
    assert link.cmd("slow", s=0.3) == "done"
    assert time.time() - t0 < 3                      # the pump does not hold the command
    assert [e.type for e in link.events] == ["link"]
    assert server.waits and set(server.waits) == {"2"}   # short polls beside a command
    link.poll_events()
    assert server.waits[-1] is None                  # a plain poll takes the server's default


def test_poll_events_order_and_dedup(link, server):
    server.add("link", state="connecting")
    server.add("link", state="ready", nodeId=5)
    server.add("ping", status="received", snr=7.5)
    new = link.poll_events()
    assert [e.seq for e in new] == [1, 2, 3]
    assert new[1].data == {"state": "ready", "nodeId": 5}
    assert new[1].t == "2026-11-08T12:00:00.000"
    assert link.poll_events() == []                 # nothing new
    server.add("range", state="outOfRange")
    assert [e.seq for e in link.poll_events()] == [4]
    assert len(link.events) == 4                    # no duplicates kept
    assert str(new[2]) == '12:00:00 ping     {"status": "received", "snr": 7.5}'


def test_wait_event_timeout(link):
    t0 = time.time()
    with pytest.raises(TimeoutError, match="no 'never' event within"):
        link.wait_event("never", timeout=0.4)
    assert 0.3 < time.time() - t0 < 3


def test_wait_event_with_predicate(link, server):
    server.add("link", state="connecting")
    server.add("link", state="ready")
    e = link.wait_link("ready", timeout=2)
    assert e.seq == 2 and e.data["state"] == "ready"
    assert len(link.events) == 2                    # the earlier one was kept too


def test_drain_and_query(link, server):
    link.drain()
    assert link.events == []
    server.add("log", line="x")
    link.drain()
    assert [e.type for e in link.events] == ["log"]
    assert link.query("SELECT 1") == []
    assert link.count("SELECT count(*) FROM sessions") == 4
    assert link.count("SELECT 1") == 0


def test_event_parse():
    e = Event.parse({"seq": 9, "t": "2026-11-08T12:00:00", "type": "setup", "role": "base", "step": "lora"})
    assert (e.seq, e.type, e.data) == (9, "setup", {"role": "base", "step": "lora"})


def test_forward_is_a_no_op_on_the_simulator():
    with Forward("ios-sim", "iPhone 18 Pro Max") as f:
        assert f.port == 8765
    with pytest.raises(ValueError):
        Forward("windows", "x").__enter__()
