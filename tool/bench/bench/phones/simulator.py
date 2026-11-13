# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""The iOS simulator over `xcrun simctl`: tier T1 (bench-rig §8).

No radios and no Bluetooth, so the app runs bench mode *and* demo mode
(`-MeshBench -MeshDemo`): the demo's pretend radio on the MeshTest channel,
the throwaway demo database, GPS from `gps.set`. The bench server binds the
simulator's loopback, which is the Mac's own, so 127.0.0.1:8765 is reachable
without any port forward (`app.Forward` is a no-op for this platform).

Build: `flutter build ios --simulator --debug --dart-define=BENCH=true`
(a debug build is fine here: simctl launches it like the Flutter tool would;
the device rule "release only" is about the iOS 14+ JIT, not the simulator).
Output: build/ios/iphonesimulator/Runner.app.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path


class SimulatorPhone:
    def __init__(self, device: str, bundle_id: str) -> None:
        self.device = device          # name ("iPhone 18 Pro Max") or UDID
        self.bundle_id = bundle_id
        self._udid: str | None = None
        self._desc = ""

    # -- plumbing ----------------------------------------------------------

    @staticmethod
    def _simctl(*args: str, timeout: int = 300, check: bool = True,
                env: dict[str, str] | None = None) -> str:
        r = subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True,
                           timeout=timeout, env=env)
        if check and r.returncode != 0:
            raise RuntimeError(f"simctl {' '.join(args)} failed:\n"
                               f"{r.stderr.strip() or r.stdout.strip()}")
        return r.stdout

    @classmethod
    def devices(cls) -> list[dict]:
        """Available simulators: name, udid, state, runtime ("iOS 26.0")."""
        raw = json.loads(cls._simctl("list", "devices", "available", "--json"))
        out = []
        for runtime, devs in raw.get("devices", {}).items():
            rt = runtime.rsplit(".", 1)[-1].replace("-", " ", 1).replace("-", ".")
            for d in devs:
                out.append({"name": d["name"], "udid": d["udid"], "state": d["state"],
                            "runtime": rt})
        return out

    def resolve(self) -> str:
        """UDID for `device`; a booted one wins when several share the name."""
        if self._udid:
            return self._udid
        devs = self.devices()
        hits = [d for d in devs if d["udid"] == self.device or d["name"] == self.device]
        if not hits:
            raise RuntimeError(f"no simulator {self.device!r}; have "
                               f"{sorted({d['name'] for d in devs})}")
        hits.sort(key=lambda d: d["state"] != "Booted")
        d = hits[0]
        self._udid, self._desc = d["udid"], f"{d['name']} ({d['runtime']}) simulator"
        return self._udid

    # -- state -------------------------------------------------------------

    def ready(self) -> tuple[bool, str]:
        """Boot the simulator if needed and wait for it."""
        udid = self.resolve()
        state = next((d["state"] for d in self.devices() if d["udid"] == udid), "?")
        if state != "Booted":
            self._simctl("boot", udid)
        self._simctl("bootstatus", udid, "-b", timeout=180)
        return True, self._desc

    # -- app ---------------------------------------------------------------

    def install(self, app: Path) -> None:
        """Install build/ios/iphonesimulator/Runner.app. Keeps app data."""
        self._simctl("install", self.resolve(), str(app))

    def uninstall(self) -> None:
        self._simctl("uninstall", self.resolve(), self.bundle_id, check=False)

    def launch(self, *args: str, env: dict[str, str] | None = None) -> int:
        """Launch with arguments (they reach Dart through the same
        `mesh_analyzer/app` channel as on a phone); returns the pid."""
        import os
        udid = self.resolve()
        child_env = None
        if env:
            # simctl hands SIMCTL_CHILD_* through to the app's environment.
            child_env = {**os.environ, **{f"SIMCTL_CHILD_{k}": v for k, v in env.items()}}
        out = self._simctl("launch", "--terminate-running-process", udid, self.bundle_id,
                           *args, env=child_env)
        # "com.andybrunker.meshAnalyzer: 12345"
        try:
            return int(out.strip().rsplit(":", 1)[1])
        except (IndexError, ValueError):
            return 0

    def terminate(self) -> None:
        self._simctl("terminate", self.resolve(), self.bundle_id, check=False)

    # -- app data ----------------------------------------------------------

    def container(self) -> Path:
        """The app's data container on disk (Documents/, Library/ inside)."""
        return Path(self._simctl("get_app_container", self.resolve(), self.bundle_id,
                                 "data").strip())

    def pull(self, source: str, dest: Path) -> Path:
        """Copy e.g. 'Documents/diag.log' or 'Documents/mesh_analyzer_demo.sqlite'
        out of the app's data container."""
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(self.container() / source, dest)
        return dest

    def push(self, src: Path, dest: str) -> None:
        target = self.container() / dest
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, target)
