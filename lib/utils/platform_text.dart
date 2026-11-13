// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/foundation.dart';

import 'app_info.dart';

/// Where to send the user in the phone's Settings, per platform. iOS
/// wording is unchanged; Android names the app-info pages instead.
class PlatformText {
  PlatformText._();

  static bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// The app's own permission page: "iOS Settings → Meshurement → Location"
  /// on iOS, "Settings → Apps → Meshurement → Permissions → Location" on
  /// Android. [androidLeaf] when Android calls the permission differently.
  static String appPermission(String iosLeaf, {String? androidLeaf}) =>
      isAndroid
          ? 'Settings → Apps → ${AppInfo.displayName} → Permissions → '
              '${androidLeaf ?? iosLeaf}'
          : 'iOS Settings → ${AppInfo.displayName} → $iosLeaf';

  /// The app's notification switch.
  static String get appNotifications => isAndroid
      ? 'Settings → Apps → ${AppInfo.displayName} → Notifications'
      : 'iOS Settings → ${AppInfo.displayName} → Notifications';

  /// The phone's Bluetooth device list, to forget a stale pairing. Android
  /// makers file it differently (Samsung: Connections → Bluetooth; Pixel:
  /// Connected devices), so no path there.
  static String get bluetoothDevices => isAndroid
      ? 'the phone\'s Bluetooth settings'
      : 'iOS Settings → Bluetooth';

  /// Switching location on for the whole phone.
  static String get locationServicesOff => isAndroid
      ? 'Location is off. Turn it on in the quick settings or '
          'Settings → Location, then try again.'
      : 'Location Services are off. Turn them on in iOS Settings → '
          'Privacy & Security → Location Services, then try again.';

  /// What the platform calls exact (vs approximate) location.
  static String get preciseLocation =>
      isAndroid ? 'Use precise location' : 'Precise Location';
}
