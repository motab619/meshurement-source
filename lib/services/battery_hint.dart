// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_info.dart';
import '../utils/platform_text.dart';

/// Android only, once ever: battery savers (Samsung's "sleeping apps"
/// above all) can stop a recording with the screen off even though GPS
/// runs in a foreground service. Shown after the first session starts;
/// there is no permission to ask for (REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
/// is restricted on Google Play), only a setting to point at.
class AndroidBatteryHint {
  AndroidBatteryHint._();

  /// Set once the hint has been handed out.
  static const prefKey = 'android_battery_hint_seen_v1';

  static const text = 'Tip: to keep recording with the screen off, set '
      'Settings → Apps → ${AppInfo.displayName} → Battery to Unrestricted. '
      'Some phones (Samsung especially) otherwise put the app to sleep.';

  /// [text] the first time on Android ([android] overrides the platform
  /// for tests), null after that and on iOS.
  static String? takeOnce(SharedPreferences prefs, {bool? android}) {
    if (!(android ?? PlatformText.isAndroid)) return null;
    if (prefs.getBool(prefKey) ?? false) return null;
    prefs.setBool(prefKey, true);
    return text;
  }
}
