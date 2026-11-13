#!/usr/bin/env bash
# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
#
# Builds a debug APK and installs it on the USB-connected Android phone
# (the Galaxy A16), keeping the app's data (`adb install -r`). Optionally
# starts it in demo mode.
#
#   tool/android/install_debug.sh                 build, install, launch
#   tool/android/install_debug.sh --demo map      ... and open demo screen "map"
#   tool/android/install_debug.sh --no-build      reinstall the last APK
#   ANDROID_SERIAL=<serial> tool/android/...      pick a phone when several
#
# Extra flutter build arguments go in FLUTTER_ARGS, e.g.
#   FLUTTER_ARGS="--dart-define=PRO_OVERRIDE=true" tool/android/install_debug.sh
# Demo screens: map charts session coverage pings estimated profile compare
# radio base report report-story report-wide report-compare (CLAUDE.md).
set -euo pipefail

# Prefer the SDK's adb: the Homebrew android-platform-tools cask is
# Gatekeeper-quarantined on this Mac and gets killed (exit 137) silently.
SDK="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
[ -x "$SDK/platform-tools/adb" ] && PATH="$SDK/platform-tools:$PATH"

APP_ID="com.plateaunerd.meshurement"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APK="$ROOT/build/app/outputs/flutter-apk/app-debug.apk"
BUILD=1
DEMO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) BUILD=0 ;;
    --demo) DEMO="${2:?--demo needs a screen name}"; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

echo "== adb devices"
adb devices -l
# "unauthorized" = accept the RSA prompt on the phone; "offline" = replug.
if ! state_err="$(adb get-state 2>&1 >/dev/null)"; then
  case "$state_err" in
    *"more than one"*)
      echo "Several devices (an emulator too?). Pick one: ANDROID_SERIAL=<serial from the list above> $0 ..." >&2 ;;
    *)
      echo "No authorised device. Enable USB debugging and accept the prompt on the phone." >&2 ;;
  esac
  exit 1
fi

if [ "$BUILD" = 1 ]; then
  echo "== flutter build apk --debug"
  # shellcheck disable=SC2086
  (cd "$ROOT" && flutter build apk --debug ${FLUTTER_ARGS:-})
fi

echo "== adb install -r $APK"
adb install -r "$APK"

if [ -n "$DEMO" ]; then
  # MainActivity hands these extras to Dart as -MeshDemo / -demoScreen on the
  # mesh_analyzer/app channel. Stop first so the extras reach a fresh start.
  adb shell am force-stop "$APP_ID"
  adb shell am start -n "$APP_ID/.MainActivity" \
    --ez MeshDemo true --es demoScreen "$DEMO"
else
  adb shell am start -n "$APP_ID/.MainActivity"
fi
echo "Logs: adb logcat --pid=\$(adb shell pidof $APP_ID)   (or: flutter logs)"
