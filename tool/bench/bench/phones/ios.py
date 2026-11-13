# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""iPhone over `xcrun devicectl` (Xcode 15+), no Xcode GUI needed.

Checked on the bench iPhone SE (iOS 17.5.1) on 2026-11-08: pairing, Developer
Mode, `process launch` passes arguments after the bundle id and they reach
Dart through `AppDelegate`'s `mesh_analyzer/app` channel (`-MeshDemo
-demoScreen map` created the demo database).

**Only profile/release builds can be launched this way.** A Flutter debug
build on iOS 14+ needs the Flutter tool's debugger attached and stalls when
launched from devicectl or the home screen. So: `flutter build ios --release
--dart-define=BENCH=true` for black-box bench runs; `flutter test
integration_test -d <udid>` (the tool launches) for in-process tests.
Registering a new phone with the team profile once: build with xcodebuild
`-destination id=<udid> -allowProvisioningUpdates
-allowProvisioningDeviceRegistration` plus the ASC API key args fastlane uses.
Never `flutter install` (it wipes app data on Andy's daily phone; the bench
phone is a different device, but the rule stays).
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path


class IosPhone:
    def __init__(self, udid: str, bundle_id: str) -> None:
        self.udid = udid
        self.bundle_id = bundle_id

    # -- plumbing ----------------------------------------------------------

    def _devicectl(self, *args: str, positional: tuple[str, ...] = (),
                   json_out: bool = False, timeout: int = 300) -> dict | str:
        # Options first, positionals last: anything after `process launch`'s
        # bundle id is handed to the app as its arguments. Human text goes to
        # stdout; the JSON report to a file (`-` only works for some subcommands).
        cmd = ["xcrun", "devicectl", *args, "--device", self.udid]
        out = None
        if json_out:  # devicectl won't overwrite an existing file
            out = Path(tempfile.mkdtemp(prefix="bench-devicectl-")) / "out.json"
            cmd += ["--json-output", str(out)]
        cmd += list(positional)
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            if r.returncode != 0:
                raise RuntimeError(f"devicectl {' '.join(args)} failed:\n{r.stderr.strip() or r.stdout.strip()}")
            if out:
                return json.loads(out.read_text())
            return r.stdout
        finally:
            if out:
                shutil.rmtree(out.parent, ignore_errors=True)

    # -- state -------------------------------------------------------------

    def info(self) -> dict:
        d = self._devicectl("device", "info", "details", json_out=True)["result"]
        dp, cp = d.get("deviceProperties", {}), d.get("connectionProperties", {})
        return {
            "name": dp.get("name"),
            "os": dp.get("osVersionNumber"),
            "developer_mode": dp.get("developerModeStatus"),
            "ddi": dp.get("ddiServicesAvailable"),
            "transport": cp.get("transportType"),
            "tunnel": cp.get("tunnelState"),
        }

    def ready(self) -> tuple[bool, str]:
        i = self.info()
        if i["developer_mode"] != "enabled":
            return False, f"Developer Mode is {i['developer_mode']}"
        if i["tunnel"] != "connected":
            return False, f"tunnel {i['tunnel']} (unlock the phone / replug)"
        return True, f"{i['name']} iOS {i['os']}"

    # -- app ---------------------------------------------------------------

    def install(self, app: Path) -> None:
        """Install a built .app (build/ios/iphoneos/Runner.app). Keeps app data."""
        self._devicectl("device", "install", "app", positional=(str(app),))

    def uninstall(self) -> None:
        """Wipe the app (and its data): the bench's fresh-install start."""
        self._devicectl("device", "uninstall", "app", positional=(self.bundle_id,))

    def launch(self, *args: str, env: dict[str, str] | None = None) -> int:
        """Launch with arguments (e.g. '-MeshBench', '-benchServer', url); returns pid."""
        cmd = ["device", "process", "launch", "--terminate-existing"]
        if env:
            cmd += ["--environment-variables", json.dumps(env)]
        try:
            out = self._devicectl(*cmd, positional=(self.bundle_id, *args), json_out=True)
        except RuntimeError as e:
            if "could not be, unlocked" in str(e):
                raise RuntimeError("the iPhone is locked: unlock it (bench phones: Settings → "
                                   "Display & Brightness → Auto-Lock → Never)") from None
            raise
        return int(out["result"]["process"]["processIdentifier"])

    def terminate(self) -> None:
        try:
            pid = self._pid()
        except RuntimeError:
            return
        if pid:
            self._devicectl("device", "process", "terminate", "--pid", str(pid))

    def _pid(self) -> int | None:
        out = self._devicectl("device", "info", "processes", json_out=True)
        for p in out["result"]["runningProcesses"]:
            if p.get("executable", "").endswith("/Runner"):
                return int(p["processIdentifier"])
        return None

    # -- system dialogs ----------------------------------------------------

    def accept_pairing(self) -> bool:
        """iOS offers no way to tap its pairing alert from the Mac (devicectl
        has no UI automation); the one-time confirm is manual (§4 Pairing)."""
        return False

    # -- app data ----------------------------------------------------------

    def pull(self, source: str, dest: Path) -> Path:
        """Copy a file out of the app's data container, e.g. 'Documents/diag.log',
        'Documents/mesh_analyzer.sqlite',
        'Library/Preferences/com.andybrunker.meshAnalyzer.plist'."""
        dest.parent.mkdir(parents=True, exist_ok=True)
        self._devicectl("device", "copy", "from",
                        "--domain-type", "appDataContainer",
                        "--domain-identifier", self.bundle_id,
                        "--source", source, "--destination", str(dest))
        return dest

    def push(self, src: Path, dest: str) -> None:
        """Copy a file into the app's data container (e.g. a .mabackup to import)."""
        self._devicectl("device", "copy", "to",
                        "--domain-type", "appDataContainer",
                        "--domain-identifier", self.bundle_id,
                        "--source", str(src), "--destination", dest)
