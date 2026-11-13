# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Android phone over `adb` (the bench Galaxy A16, SM-A166U, Android 16).

Launch arguments: `MainActivity.kt` builds the iOS-style list Dart expects
(`-MeshBench -benchPort 8765`) from Intent extras named like the flags
without the dash. [extras_for] does the reverse: a bare flag is a boolean
extra (`--ez MeshBench true`), a flag with a number is an int extra
(`--ei benchPort 8765`), anything else a string extra (`--es demoScreen map`).
So `bench launch` runs

    adb shell am start -S -W -n com.plateaunerd.meshurement/.MainActivity \\
        --ez MeshBench true --ei benchPort 8765

Unlike iOS, a Flutter *debug* APK can be launched this way too, but the
bench installs the release build (`flutter build apk --release
--dart-define=BENCH=true`, debug-signed when android/key.properties is
missing); only `pull` (run-as) needs a debuggable build.

Permissions: `adb install -g` grants every runtime permission the manifest
declares (Nearby devices = BLUETOOTH_SCAN/CONNECT, location, notifications),
and [grant_permissions] repeats it with `pm grant` for an already installed
app, so bench mode never meets a permission sheet. Bluetooth *pairing* is
the one system dialog left: Meshtastic radios on `bluetooth.mode = NO_PIN`
may still make Android ask once per radio ("Pair with BASE_3e9c?"), so
[accept_pairing] reads the screen with `uiautomator dump` and taps Pair; the
Radio Setup scenario polls it while the app connects.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

#: Runtime permissions the bench needs granted (AndroidManifest.xml).
PERMISSIONS = (
    "android.permission.BLUETOOTH_SCAN",
    "android.permission.BLUETOOTH_CONNECT",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.POST_NOTIFICATIONS",
)

#: Button labels that accept a Bluetooth pairing request (Android's
#: BluetoothPairingDialog: "Pair"; Samsung One UI shows the same text).
PAIR_LABELS = ("pair", "pair & connect", "ok")
#: Packages whose dialog a pairing tap is allowed in; anything else (the
#: app itself, the launcher) is never tapped by label.
PAIR_PACKAGES = ("com.android.settings", "com.android.bluetooth",
                 "com.samsung.android.bluetooth", "com.google.android.bluetooth")


def adb_path() -> str:
    """The SDK's adb when present: the Homebrew cask copy is Gatekeeper-
    quarantined on this Mac and dies silently (tool/android/install_debug.sh)."""
    sdk = os.environ.get("ANDROID_HOME") or "/opt/homebrew/share/android-commandlinetools"
    cand = Path(sdk) / "platform-tools" / "adb"
    if cand.is_file() and os.access(cand, os.X_OK):
        return str(cand)
    return shutil.which("adb") or "adb"


def extras_for(args: tuple[str, ...] | list[str]) -> list[str]:
    """Intent extras for an iOS-style argument list (see the module doc)."""
    extras: list[str] = []
    items = list(args)
    i = 0
    while i < len(items):
        a = items[i]
        if not a.startswith("-"):
            raise ValueError(f"launch argument {a!r} is not a -flag (value without a flag)")
        key = a.lstrip("-")
        nxt = items[i + 1] if i + 1 < len(items) else None
        if nxt is None or nxt.startswith("-"):
            extras += ["--ez", key, "true"]
            i += 1
        elif re.fullmatch(r"\d+", nxt):
            extras += ["--ei", key, nxt]
            i += 2
        else:
            extras += ["--es", key, nxt]
            i += 2
    return extras


def _bounds(node: ET.Element) -> tuple[int, int] | None:
    m = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
    if not m:
        return None
    x1, y1, x2, y2 = map(int, m.groups())
    return (x1 + x2) // 2, (y1 + y2) // 2


def find_pairing_button(dump_xml: str) -> tuple[int, int] | None:
    """Centre of the Pair button in a `uiautomator dump`, or None when no
    pairing dialog is up. Only a clickable node labelled like Pair, inside a
    Bluetooth/Settings package, counts."""
    try:
        root = ET.fromstring(dump_xml)
    except ET.ParseError:
        return None
    for node in root.iter("node"):
        pkg = node.get("package", "")
        if not pkg.startswith(PAIR_PACKAGES):
            continue
        label = (node.get("text") or node.get("content-desc") or "").strip().lower()
        if label in PAIR_LABELS and node.get("clickable") == "true":
            return _bounds(node)
    return None


class AndroidPhone:
    def __init__(self, serial: str, package: str) -> None:
        self.serial = serial
        self.package = package
        self.adb = adb_path()

    def _adb(self, *args: str, timeout: int = 300, check: bool = True) -> str:
        r = subprocess.run([self.adb, "-s", self.serial, *args], capture_output=True,
                           text=True, timeout=timeout)
        if check and r.returncode != 0:
            raise RuntimeError(f"adb {' '.join(args)} failed:\n{r.stderr.strip() or r.stdout.strip()}")
        return r.stdout

    # -- state -------------------------------------------------------------

    def ready(self) -> tuple[bool, str]:
        out = subprocess.run([self.adb, "devices"], capture_output=True, text=True).stdout
        for line in out.splitlines()[1:]:
            fields = line.split()
            if len(fields) >= 2 and fields[0] == self.serial:
                state = fields[1]   # `adb devices -l` adds model:... after it
                if state == "device":
                    model = self._adb("shell", "getprop", "ro.product.model").strip()
                    rel = self._adb("shell", "getprop", "ro.build.version.release").strip()
                    return True, f"{model} Android {rel}"
                return False, f"adb state {state} (accept the USB debugging prompt)"
        return False, "not in `adb devices`"

    # -- app ---------------------------------------------------------------

    def install(self, apk: Path) -> None:
        """`adb install -r -g`: keep app data, grant runtime permissions."""
        self._adb("install", "-r", "-g", str(apk))
        self.grant_permissions()

    def grant_permissions(self) -> list[str]:
        """`pm grant` each bench permission; returns the ones that were refused
        (not declared by the build, or not a runtime permission on this OS)."""
        refused = []
        for perm in PERMISSIONS:
            r = subprocess.run([self.adb, "-s", self.serial, "shell", "pm", "grant",
                                self.package, perm], capture_output=True, text=True, timeout=60)
            if r.returncode != 0:
                refused.append(perm)
        return refused

    def uninstall(self) -> None:
        self._adb("uninstall", self.package, check=False)

    def launch(self, *args: str, env: dict[str, str] | None = None) -> None:
        """Start MainActivity fresh (`-S` stops a running instance first) with
        the launch arguments as extras. `env` is ignored: Android apps get no
        environment from `am start`; everything travels as extras."""
        self._adb("shell", "am", "start", "-S", "-W", "-n",
                  f"{self.package}/.MainActivity", *extras_for(args), timeout=60)

    def terminate(self) -> None:
        self._adb("shell", "am", "force-stop", self.package)

    def lock(self) -> None:
        self._adb("shell", "input", "keyevent", "26")   # power: screen off

    def wake(self) -> None:
        self._adb("shell", "input", "keyevent", "224")  # wake up
        self._adb("shell", "wm", "dismiss-keyguard", check=False)

    # -- system dialogs ----------------------------------------------------

    def ui_dump(self) -> str:
        """The current window hierarchy as XML (`uiautomator dump`)."""
        out = self._adb("shell", "uiautomator", "dump", "/dev/tty", timeout=30, check=False)
        # The XML is followed by "UI hierchary dumped to: /dev/tty".
        start, end = out.find("<?xml"), out.rfind("</hierarchy>")
        if start < 0 or end < 0:
            return ""
        return out[start:end + len("</hierarchy>")]

    def accept_pairing(self) -> bool:
        """Tap Pair on a Bluetooth pairing dialog if one is showing.
        Returns True when it tapped."""
        pos = find_pairing_button(self.ui_dump())
        if pos is None:
            return False
        self._adb("shell", "input", "tap", str(pos[0]), str(pos[1]), timeout=30)
        return True

    # -- app data ----------------------------------------------------------

    def pull(self, source: str, dest: Path) -> Path:
        """Debug builds only: read a file from the app's private storage via run-as."""
        dest.parent.mkdir(parents=True, exist_ok=True)
        data = subprocess.run([self.adb, "-s", self.serial, "exec-out", "run-as", self.package,
                               "cat", source], capture_output=True, timeout=120)
        if data.returncode != 0:
            raise RuntimeError(data.stderr.decode(errors="replace"))
        dest.write_bytes(data.stdout)
        return dest

    def logcat(self, since: str | None = None) -> str:
        args = ["logcat", "-d", "-v", "time"]
        if since:
            args += ["-T", since]
        return self._adb(*args, timeout=60)

    def notifications(self) -> str:
        return self._adb("shell", "dumpsys", "notification", "--noredact", timeout=60)
