// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Demo mode for App Store-style screenshots (fastlane snapshot).
///
/// Only on when launched with `-MeshDemo` in the arguments (the UI tests
/// pass it; MESH_DEMO=SCREEN in the environment also works). It uses a
/// separate database, a pretend connected radio and a recorded walk,
/// sends nothing over Bluetooth and asks for no permissions.
/// `-demoScreen NAME` opens straight to a screen:
/// map, charts, session, coverage, pings, estimated, terrain (signal map on
/// the Terrain base map), profile, compare, guided,
/// radio, settings, base (connected to the base radio, beacon card showing),
/// report, report-story, report-wide, report-compare (Field Report sheet).
/// `-demoSite cove|polo` (or MESH_DEMO_SITE) picks the place
/// (`DemoSite`): the La Quinta Cove drive by default, or the original
/// Empire Polo walk.
///
/// App Review can't pass launch arguments, so a long-press on the app name
/// and version on About offers to open the demo on the next launch
/// ([nextLaunchPref]; documented in docs/app-review-notes.md). It stays on
/// until turned off the same way. Your own data is untouched: the demo uses
/// its own database.
class DemoMode {
  DemoMode._();

  static bool enabled = false;
  static String screen = 'map';
  static String site = 'cove';

  /// Set from About: start in demo mode on every launch until cleared.
  static const nextLaunchPref = 'demo_mode_on_launch_v1';

  static Future<bool> _askedFromAbout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(nextLaunchPref) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> detect() async {
    final siteEnv = Platform.environment['MESH_DEMO_SITE'];
    if (siteEnv != null && siteEnv.isNotEmpty) site = siteEnv;
    final env = Platform.environment['MESH_DEMO'];
    if (env != null && env.isNotEmpty) {
      enabled = true;
      screen = env;
      return;
    }
    // Launch arguments come over a native channel registered in
    // AppDelegate. On a cold start the channel can lag behind main(), so
    // retry briefly instead of falling back to the real (permission
    // prompting) app. Android's MainActivity registers it in
    // configureFlutterEngine, before main() runs, so one try is enough
    // there (no handler = not a demo launch, no 3 s wait).
    final attempts = Platform.isIOS ? 30 : 1;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final args = await const MethodChannel('mesh_analyzer/app')
                .invokeListMethod<String>('launchArguments') ??
            const [];
        enabled = args.contains('-MeshDemo');
        final i = args.indexOf('-demoScreen');
        if (i >= 0 && i + 1 < args.length) screen = args[i + 1];
        final s = args.indexOf('-demoSite');
        if (s >= 0 && s + 1 < args.length) site = args[s + 1];
        break;
      } on MissingPluginException {
        if (attempt + 1 < attempts) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      } catch (_) {
        enabled = false;
        break;
      }
    }
    if (!enabled) enabled = await _askedFromAbout();
  }
}
