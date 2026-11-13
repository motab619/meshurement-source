# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Live view of a bench run: a page on the Mac (`bench run --ui`,
`bench matrix --ui`, `bench ui` to replay a report) that draws the bench
(Mac, cables, phone, radios) and animates what the run is doing while the
checklist ticks off.

The rest of the bench reports into this module with `emit(type, **data)`;
that is a no-op until `serve()` has started the page's server, so the hooks
cost nothing in a plain run or in tests. The page reads `/feed`, a
Server-Sent Events stream that first replays everything emitted so far
(marked `replay`) and then follows live.

Event types (all carry `seq` and `t`, epoch seconds):
  run_start   phone{name,platform,tier}, radios{name:{board,protocol,role,firmware}},
              scenarios[names], expected{scenario:[check names from the last report]}
  scenario_start / scenario_end   name (+ passed, skipped, seconds)
  check       scenario, name, ok, detail
  cmd         cmd, phase start|end, ok, args (an app bench command, BLE side)
  app         kind (the app's own event type: link, setup, ping, beacon...), data
  usb         radio, phase start|end, what (a serial session with a radio)
  flash       radio, phase start|end, version, ok
  combo_start / combo_end   index, label (+ status) for `bench matrix`
  log         text
  run_end     passed, report
"""

from __future__ import annotations

import json
import queue
import threading
import time
import webbrowser
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable, Iterator

DEFAULT_PORT = 8770
UI = Path(__file__).parent / "ui" / "index.html"

_lock = threading.Lock()
_history: list[dict[str, Any]] = []
_subs: list[queue.Queue] = []
_seq = 0
_server: ThreadingHTTPServer | None = None
_ports: dict[str, str] = {}          # serial device path -> radio name
_on_replay: Callable[[], None] | None = None
_first_client = threading.Event()


def active() -> bool:
    return _server is not None


def emit(type_: str, **data: Any) -> None:
    """Record an event and push it to every open page. No-op without `serve()`."""
    global _seq
    if _server is None:
        return
    with _lock:
        _seq += 1
        ev = {"seq": _seq, "t": round(time.time(), 3), "type": type_, **data}
        _history.append(ev)
        subs = list(_subs)
    for q in subs:
        q.put(ev)


def log(text: str) -> None:
    emit("log", text=text)


def reset() -> None:
    """Forget the history (a replay starting over). Open pages get `reset`
    (and reload); it is not kept, so a page opened later doesn't."""
    global _seq
    if _server is None:
        return
    with _lock:
        _history.clear()
        _seq += 1
        ev = {"seq": _seq, "t": round(time.time(), 3), "type": "reset"}
        subs = list(_subs)
    for q in subs:
        q.put(ev)


def map_ports(ports: dict[str, str]) -> None:
    """Teach the feed which serial device is which radio, so a serial
    session that only knows its port (`mt.connect(port)`) lights the right
    radio on the page."""
    _ports.update(ports)


def radio_for(port_or_name: str) -> str:
    return _ports.get(port_or_name, port_or_name)


@contextmanager
def usb(port_or_name: str, what: str = "serial") -> Iterator[None]:
    """Mark a USB conversation with a radio (the page runs data along its cable)."""
    name = radio_for(port_or_name)
    emit("usb", radio=name, phase="start", what=what)
    ok = False
    try:
        yield
        ok = True
    finally:
        emit("usb", radio=name, phase="end", what=what, ok=ok)


# -- server ------------------------------------------------------------------

class _Handler(BaseHTTPRequestHandler):
    def log_message(self, *a: Any) -> None:  # quiet: the run log is the terminal's
        pass

    def _send(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 - http.server API
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html"):
            self._send(200, UI.read_bytes(), "text/html; charset=utf-8")
        elif path == "/history":
            with _lock:
                body = json.dumps(_history).encode()
            self._send(200, body, "application/json")
        elif path == "/feed":
            self._feed()
        else:
            self._send(404, b"not found", "text/plain")

    def do_POST(self) -> None:  # noqa: N802
        if self.path == "/replay" and _on_replay is not None:
            threading.Thread(target=_on_replay, daemon=True).start()
            self._send(200, b"{}", "application/json")
        else:
            self._send(404, b"not found", "text/plain")

    def _feed(self) -> None:
        q: queue.Queue = queue.Queue()
        with _lock:
            backlog = list(_history)
            _subs.append(q)
        _first_client.set()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        try:
            for ev in backlog:
                self._event(ev | {"replay": True})
            while True:
                try:
                    ev = q.get(timeout=15)
                except queue.Empty:
                    self.wfile.write(b": keep-alive\n\n")
                    self.wfile.flush()
                    continue
                self._event(ev)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            with _lock:
                if q in _subs:
                    _subs.remove(q)

    def _event(self, ev: dict[str, Any]) -> None:
        self.wfile.write(b"data: " + json.dumps(ev, default=str).encode() + b"\n\n")
        self.wfile.flush()


class _Server(ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, request: Any, client_address: Any) -> None:
        import sys
        if isinstance(sys.exc_info()[1], (ConnectionResetError, BrokenPipeError)):
            return  # a page closed or reloaded: not worth a traceback in the run log
        super().handle_error(request, client_address)


def serve(port: int = DEFAULT_PORT, *, open_browser: bool = True,
          on_replay: Callable[[], None] | None = None) -> str:
    """Start the page's server (once) on 127.0.0.1 and return its URL."""
    global _server, _on_replay
    _on_replay = on_replay
    if _server is None:
        _server = _Server(("127.0.0.1", port), _Handler)
        threading.Thread(target=_server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{_server.server_address[1]}/"
    if open_browser:
        webbrowser.open(url)
    return url


def wait_for_page(timeout: float = 20) -> bool:
    """Block until a page has connected (so a short run isn't over before
    anyone sees it). False after `timeout`."""
    return _first_client.wait(timeout)


def stop() -> None:
    """Shut the server down and forget everything (tests)."""
    global _server, _seq, _on_replay
    if _server is not None:
        _server.shutdown()
        _server.server_close()
    _server = None
    _on_replay = None
    _first_client.clear()
    with _lock:
        _history.clear()
        _subs.clear()
        _seq = 0
    _ports.clear()


# -- what the page needs to know up front -------------------------------------

def last_checks(reports_dir: Path, names: list[str], limit: int = 40) -> dict[str, list[str]]:
    """For each scenario, the check names of the newest report that ran it,
    so the page can show the checklist before the checks arrive."""
    out: dict[str, list[str]] = {}
    files = sorted((p for p in reports_dir.glob("20*.json")), reverse=True)[:limit] \
        if reports_dir.is_dir() else []
    for p in files:
        try:
            d = json.loads(p.read_text())
        except (OSError, ValueError):
            continue
        for s in d.get("scenarios", []):
            n = s.get("name")
            if n in names and n not in out and s.get("checks") and not s.get("skipped"):
                out[n] = [c["name"] for c in s["checks"]]
        if len(out) == len(names):
            break
    return out


# -- replay ------------------------------------------------------------------

def replay_events(rep: dict[str, Any], *, total_s: float = 45) -> Iterator[tuple[float, str, dict[str, Any]]]:
    """A finished report as a timed event stream: (delay before, type, data).
    The whole run takes about `total_s` seconds whatever it took for real."""
    scen = rep.get("scenarios", [])
    n_checks = max(1, sum(len(s.get("checks", [])) for s in scen))
    step = min(2.2, max(0.35, total_s / n_checks))
    phone = dict(rep.get("phone", {}))
    phone.setdefault("tier", rep.get("tier", "T2"))
    radios = {n: {"role": "base" if "base" in n else "mobile", **r}
              for n, r in rep.get("radios", {}).items()}
    yield 0, "run_start", {
        "phone": phone, "radios": radios,
        "scenarios": [s["name"] for s in scen],
        "expected": {s["name"]: [c["name"] for c in s.get("checks", [])] for s in scen},
        "commit": rep.get("commit", ""), "replayOf": rep.get("started_at", ""),
    }
    for s in scen:
        yield 0.8, "scenario_start", {"name": s["name"]}
        for c in s.get("checks", []):
            yield step, "check", {"scenario": s["name"], "name": c["name"], "ok": c["ok"],
                                  "detail": c.get("detail", "")}
        yield 0.6, "scenario_end", {"name": s["name"], "passed": s.get("passed"),
                                    "skipped": s.get("skipped", ""), "seconds": s.get("seconds", 0)}
    yield 0.8, "run_end", {"passed": rep.get("passed"), "report": rep.get("started_at", "")}


def play(rep: dict[str, Any], *, total_s: float = 45,
         sleep: Callable[[float], None] = time.sleep) -> None:
    """Emit `replay_events(rep)` in real time (after a `reset`)."""
    reset()
    for delay, type_, data in replay_events(rep, total_s=total_s):
        sleep(delay)
        emit(type_, **data)
