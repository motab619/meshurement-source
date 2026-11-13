// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The `mesh_analyzer/app` method channel (AppDelegate.swift and
/// MainActivity.kt): launch arguments, opened files, and on Android the
/// task-level actions a Flutter app can't do itself.
abstract final class AppChannel {
  static const name = 'mesh_analyzer/app';
  static const _channel = MethodChannel(name);

  /// Android: put the app behind the home screen without finishing the
  /// activity (`Activity.moveTaskToBack`), so the Flutter engine, and with
  /// it a recording session, its BLE link and the foreground service, stay
  /// alive. Finishing the activity destroys the engine. No-op elsewhere.
  static Future<void> moveToBack() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('moveToBack');
    } on PlatformException {
      // Older MainActivity without the method: nothing to do.
    } on MissingPluginException {
      // Tests without a handler.
    }
  }
}
