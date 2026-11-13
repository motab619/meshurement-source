# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Talk to the app's bench server (`lib/bench/bench_server.dart`) over USB.

The app listens on its own loopback (127.0.0.1:8765). The Mac reaches it
through a USB port forward: `iproxy` (libimobiledevice, `brew install
libimobiledevice`) for iOS, `adb forward` for Android. No Wi-Fi, no iOS
local-network prompt. On the iOS simulator (`ios-sim`) the app's loopback
is the Mac's, so [Forward] does nothing there.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Callable

from . import live

DEFAULT_PORT = 8765
PUMP_WAIT_S = 2   # long-poll length of the event pump that runs beside a command


class BenchCommandError(RuntimeError):
    pass


def _brief(args: dict[str, Any]) -> dict[str, Any]:
    """A command's arguments for the live page: short scalars only (no SQL
    walls, no keys)."""
    return {k: v for k, v in args.items()
            if isinstance(v, (str, int, float, bool)) and len(str(v)) <= 80
            and k not in ("sql", "psk", "key")}


@dataclass
class Event:
    seq: int
    t: str
    type: str
    data: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def parse(cls, raw: dict[str, Any]) -> "Event":
        d = dict(raw)
        return cls(seq=d.pop("seq"), t=d.pop("t"), type=d.pop("type"), data=d)

    def __str__(self) -> str:
        return f"{self.t[11:19]} {self.type:<8} {json.dumps(self.data, default=str)}"


class Forward:
    """USB port forward Mac:port -> phone:port, as a context manager."""

    def __init__(self, platform: str, device_id: str, port: int = DEFAULT_PORT) -> None:
        self.platform, self.device_id, self.port = platform, device_id, port
        self._proc: subprocess.Popen | None = None

    def __enter__(self) -> "Forward":
        if self.platform == "ios":
            if not shutil.which("iproxy"):
                raise RuntimeError("iproxy not found: `brew install libimobiledevice`")
            self._proc = subprocess.Popen(
                ["iproxy", "-u", self.device_id, f"{self.port}:{self.port}"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(0.5)
        elif self.platform == "android":
            from .phones.android import adb_path
            self._adb = adb_path()
            # (prints the port on stdout; keep the run log clean)
            subprocess.run([self._adb, "-s", self.device_id, "forward",
                            f"tcp:{self.port}", f"tcp:{self.port}"], check=True,
                           capture_output=True)
        elif self.platform == "ios-sim":
            pass  # the simulator shares the Mac's loopback
        else:
            raise ValueError(self.platform)
        return self

    def __exit__(self, *exc: object) -> None:
        if self._proc:
            self._proc.terminate()
        elif self.platform == "android":
            subprocess.run([self._adb, "-s", self.device_id, "forward", "--remove",
                            f"tcp:{self.port}"], check=False, capture_output=True)


class AppLink:
    """HTTP client for the app's bench server (through a [Forward])."""

    def __init__(self, port: int = DEFAULT_PORT, log: Callable[[str], None] | None = None) -> None:
        self.base = f"http://127.0.0.1:{port}"
        self.log = log or (lambda s: None)
        self._seq = 0
        self.events: list[Event] = []
        self._lock = threading.Lock()

    # -- transport ---------------------------------------------------------

    def _req(self, path: str, body: dict | None = None, timeout: float = 30) -> Any:
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data,
                                     headers={"Content-Type": "application/json"} if data else {})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode())

    def wait_up(self, timeout: float = 60) -> dict[str, Any]:
        """Poll /state until the app answers (it starts after the splash)."""
        end = time.time() + timeout
        last: Exception | None = None
        while time.time() < end:
            try:
                return self.state()
            except (urllib.error.URLError, ConnectionError, TimeoutError, OSError) as e:
                last = e
                time.sleep(1)
        hint = ""
        if "timed out" in str(last):
            # Accepted but silent: something else owns the Mac's port (a stale
            # iproxy / adb forward to a phone that is not there), or the app's
            # own bind failed because of it. `lsof -nP -iTCP:<port>` tells.
            hint = (f" (the connection was accepted but nothing answered: is another "
                    f"process listening on {self.base}? `lsof -nP -iTCP:{self.base.rsplit(':', 1)[1]}`)")
        raise TimeoutError(f"bench server not answering after {timeout}s: {last}{hint}")

    # -- api ---------------------------------------------------------------

    def state(self) -> dict[str, Any]:
        return self._req("/state", timeout=10)

    def cmd(self, _cmd: str, timeout: float = 60, **args: Any) -> Any:
        """Run a command; keyword arguments are its args (`name` included).
        Events keep streaming on a side thread while it runs."""
        self.log(f"> {_cmd} {json.dumps(args, default=str) if args else ''}")
        stop = threading.Event()
        t = threading.Thread(target=self._pump, args=(stop,), daemon=True)
        t.start()
        live.emit("cmd", cmd=_cmd, phase="start", args=_brief(args))
        r: dict[str, Any] = {}
        try:
            r = self._req("/cmd", {"cmd": _cmd, "args": args}, timeout=timeout)
        finally:
            stop.set()
            t.join(timeout=PUMP_WAIT_S + 3)
            live.emit("cmd", cmd=_cmd, phase="end", ok=bool(r.get("ok")),
                      error=str(r.get("error") or "")[:200])
        if not r.get("ok"):
            raise BenchCommandError(f"{_cmd}: {r.get('error')}")
        return r.get("value")

    def _pump(self, stop: threading.Event) -> None:
        # Short polls so the thread notices `stop` soon after the command
        # returns (a quiet app, e.g. the simulator, would otherwise hold each
        # command for the server's full 20 s long-poll).
        while not stop.is_set():
            try:
                self.poll_events(wait=PUMP_WAIT_S)
            except Exception:  # noqa: BLE001 - transport hiccup; try again
                stop.wait(1)

    def poll_events(self, wait: float | None = None) -> list[Event]:
        """Fetch new events. The server long-polls up to `wait` seconds when
        idle (its default, 20, when None)."""
        q = f"/events?since={self._seq}" + (f"&wait={int(wait)}" if wait is not None else "")
        raw = self._req(q, timeout=30)
        new = [Event.parse(e) for e in raw]
        with self._lock:
            new = [e for e in new if e.seq > self._seq]
            for e in new:
                self._seq = max(self._seq, e.seq)
                self.events.append(e)
                self.log(f"  {e}")
                live.emit("app", kind=e.type, data=e.data)
        return new

    def drain(self) -> None:
        """Pull everything queued so far without waiting."""
        raw = self._req(f"/events?since={self._seq}", timeout=30) if self._pending() else []
        for e in (Event.parse(x) for x in raw):
            if e.seq <= self._seq:
                continue
            self._seq = max(self._seq, e.seq)
            self.events.append(e)
            self.log(f"  {e}")
            live.emit("app", kind=e.type, data=e.data)

    def _pending(self) -> bool:
        return self.state().get("seq", 0) > self._seq

    def wait_event(self, type_: str, pred: Callable[[Event], bool] | None = None,
                   timeout: float = 120) -> Event:
        """Block until an event of `type_` (matching `pred`) arrives."""
        end = time.time() + timeout
        while time.time() < end:
            for e in self.poll_events():
                if e.type == type_ and (pred is None or pred(e)):
                    return e
        raise TimeoutError(f"no '{type_}' event within {timeout}s")

    def wait_link(self, state: str = "ready", timeout: float = 120) -> Event:
        return self.wait_event("link", lambda e: e.data.get("state") == state, timeout)

    def query(self, sql: str) -> list[dict[str, Any]]:
        return self.cmd("db.query", sql=sql)

    def count(self, sql: str) -> int:
        rows = self.query(sql)
        return int(next(iter(rows[0].values()))) if rows else 0
