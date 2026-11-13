#!/usr/bin/env bash
# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
#
# Android version of the devicectl recipe in CLAUDE.md: copies the app's
# diagnostics log, database and prefs off the USB-connected phone.
#
#   tool/android/pull_diag.sh [out-dir]       default ./android-diag-<time>
#
# How: `adb shell run-as <id>` runs as the app's own user, which can read
# its private directory /data/data/<id>/ (= /data/user/0/<id>/). run-as only
# works for DEBUGGABLE builds (debug APKs from tool/android/install_debug.sh
# or `flutter run`); Play/release builds refuse ("package not debuggable").
# For those, use About → "Share diagnostics log" on the phone instead.
#
# Where things live on Android:
#   path_provider getApplicationDocumentsDirectory() = app_flutter/
#     app_flutter/diag.log, app_flutter/mesh_analyzer.sqlite (+ -wal/-shm;
#     demo mode: mesh_analyzer_demo.sqlite)
#   shared_preferences = shared_prefs/FlutterSharedPreferences.xml
#   (shared_preferences_android 2.4 may also keep a DataStore file under
#    files/datastore/ when the app opts into SharedPreferencesAsync.)
set -euo pipefail

# Prefer the SDK's adb (the Homebrew cask's copy is Gatekeeper-quarantined).
SDK="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
[ -x "$SDK/platform-tools/adb" ] && PATH="$SDK/platform-tools:$PATH"

APP_ID="com.plateaunerd.meshurement"
OUT="${1:-./android-diag-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"

adb get-state >/dev/null || { echo "No authorised device (adb devices)." >&2; exit 1; }

pull() { # <path inside the app dir> <local name>
  if adb exec-out run-as "$APP_ID" cat "$1" > "$OUT/$2" 2>/dev/null && [ -s "$OUT/$2" ]; then
    echo "  $1 -> $OUT/$2"
  else
    rm -f "$OUT/$2"; echo "  $1: not found"
  fi
}

if ! adb shell run-as "$APP_ID" true 2>/dev/null; then
  echo "run-as failed: the installed build is not debuggable (or not installed)." >&2
  echo "Use About -> Share diagnostics log on the phone instead." >&2
  exit 1
fi

echo "== Files in app_flutter/"
adb shell run-as "$APP_ID" ls -la app_flutter || true
echo "== Pulling"
pull app_flutter/diag.log diag.log
# Copy the WAL too: without it recent rows may be missing from the .sqlite.
pull app_flutter/mesh_analyzer.sqlite mesh_analyzer.sqlite
pull app_flutter/mesh_analyzer.sqlite-wal mesh_analyzer.sqlite-wal
pull app_flutter/mesh_analyzer.sqlite-shm mesh_analyzer.sqlite-shm
pull shared_prefs/FlutterSharedPreferences.xml FlutterSharedPreferences.xml
