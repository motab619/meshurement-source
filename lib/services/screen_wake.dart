// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../providers.dart';
import '../utils/constants.dart';

/// Keeps the screen awake while a session records, whatever "Keep screen
/// on" says; outside a session it follows that setting (new-user
/// walkthrough 2026-11-08: "Recommended for field sessions", yet off by
/// default). The only code that turns the wakelock on or off.
class ScreenWake {
  final SharedPreferences _prefs;
  final Future<void> Function(bool on) _apply;

  bool _recording = false;

  /// What was last applied; null until the first sync.
  bool? _held;

  ScreenWake(this._prefs, {Future<void> Function(bool on)? apply})
      : _apply = apply ?? _wakelock;

  static Future<void> _wakelock(bool on) => WakelockPlus.toggle(enable: on);

  /// The "Keep screen on" setting: on all the time, not only while
  /// recording.
  bool get alwaysOn => _prefs.getBool(AppConstants.prefKeepScreenOn) ?? false;

  bool get recording => _recording;

  /// Whether the screen is kept on now.
  bool get wanted => _recording || alwaysOn;

  Future<void> setRecording(bool recording) {
    _recording = recording;
    return _sync();
  }

  /// Stores the setting and applies it (a recording session keeps the
  /// screen on either way).
  Future<void> setAlwaysOn(bool on) async {
    await _prefs.setBool(AppConstants.prefKeepScreenOn, on);
    await _sync();
  }

  /// Re-apply after the setting changed elsewhere (e.g. erase all data).
  Future<void> refresh() => _sync();

  Future<void> _sync() async {
    final want = wanted;
    if (_held == want) return;
    _held = want;
    try {
      await _apply(want);
    } catch (e) {
      print('Screen wake: $e');
    }
  }
}

final screenWakeProvider = Provider<ScreenWake>(
    (ref) => ScreenWake(ref.watch(sharedPreferencesProvider)));

/// Read once at app start (`ref.read(screenWakeWiringProvider)`): follows
/// [activeSessionProvider] for the app's lifetime.
final screenWakeWiringProvider = Provider<void>((ref) {
  final wake = ref.watch(screenWakeProvider);
  ref.listen<AsyncValue<Object?>>(
    activeSessionProvider,
    (_, next) => wake.setRecording(next.valueOrNull != null),
    fireImmediately: true,
  );
});
