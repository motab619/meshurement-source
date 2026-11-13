// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app.dart';
import 'bench/bench_location.dart';
import 'bench/bench_mode.dart';
import 'demo/demo_mode.dart';
import 'providers.dart';
import 'services/diag_log.dart';
import 'services/gps_service.dart';
import 'services/live_activity_service.dart';
import 'ui/screens/about_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DemoMode.detect();
  await BenchMode.detect();
  registerAppLicenses();

  final prefs = await SharedPreferences.getInstance();

  final notifications = FlutterLocalNotificationsPlugin();
  // No permission prompt at launch: it's asked when the first session
  // starts (OutOfRangeMonitor.requestNotificationPermission), never in demo.
  // A failure here (Android: the drawable missing, e.g. stripped by
  // resource shrinking -> "invalid_icon") must not stop the app: only the
  // alerts are lost, and diag.log says so.
  try {
    await notifications.initialize(
      const InitializationSettings(
        // Android: the monochrome status-bar icon
        // (res/drawable-*/ic_stat_notify.png, also the recording notice's).
        android: AndroidInitializationSettings('ic_stat_notify'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
  } catch (e) {
    DiagLog.instance.log('notify', 'initialize failed: $e');
  }

  final keepScreenOn = prefs.getBool('keep_screen_on') ?? false;
  // Bench rig: the screen stays on so the OS never puts the app in the
  // background (Android freezes cached apps, and with them the bench
  // server; iOS would need Auto-Lock → Never on the bench phone).
  if (keepScreenOn || BenchMode.enabled) {
    await WakelockPlus.enable();
  }

  // iPhone or not: decides whether Live Activity is mentioned anywhere.
  await LiveActivityService.checkDeviceSupport();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notificationsProvider.overrideWithValue(notifications),
        // Bench rig: GPS comes from the Mac, never from the phone.
        if (BenchMode.enabled)
          gpsServiceProvider.overrideWith(
              (ref) => GpsService(backend: const BenchLocationBackend())),
      ],
      child: MeshAnalyzerApp(showSplash: !DemoMode.enabled),
    ),
  );
}
