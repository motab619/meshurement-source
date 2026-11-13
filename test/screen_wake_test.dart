// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/screen_wake.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _session = Session(
  id: 1,
  coverageMapId: 1,
  name: '',
  startedAt: DateTime(2026, 11, 8),
  isActive: true,
  hwAntenna: '',
  hwNodeModel: '',
  hwNotes: '',
  loraPreset: 'LONG_FAST',
  protocol: 'meshtastic',
  pingIntervalSec: 30,
  packetAirtimeMs: 0,
  rangeTestActive: false,
  packetCount: 0,
  beaconKind: '',
  beaconIntervalSec: 0,
);

void main() {
  late StreamController<Session?> sessions;
  late List<bool> applied;
  late ProviderContainer container;

  Future<void> start({bool alwaysOn = false}) async {
    SharedPreferences.setMockInitialValues(
        {if (alwaysOn) AppConstants.prefKeepScreenOn: true});
    final prefs = await SharedPreferences.getInstance();
    sessions = StreamController<Session?>();
    applied = [];
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      activeSessionProvider.overrideWith((ref) => sessions.stream),
      screenWakeProvider.overrideWith((ref) => ScreenWake(prefs,
          apply: (on) async => applied.add(on))),
    ]);
    addTearDown(container.dispose);
    addTearDown(sessions.close);
    container.read(screenWakeWiringProvider);
    await pumpEventQueue();
  }

  Future<void> emit(Session? s) async {
    sessions.add(s);
    await pumpEventQueue();
  }

  test('on while a session records, back off when it ends', () async {
    await start();
    expect(applied, [false]); // setting off, nothing recording
    await emit(null);
    expect(applied, [false]); // no change, no call
    await emit(_session);
    expect(applied, [false, true]);
    expect(container.read(screenWakeProvider).wanted, isTrue);
    await emit(null);
    expect(applied, [false, true, false]);
  });

  test('with the setting on, the screen stays on after the session',
      () async {
    await start(alwaysOn: true);
    await emit(_session);
    await emit(null);
    expect(applied, [true]);
  });

  test('turning the setting off during a session keeps it on until the end',
      () async {
    await start(alwaysOn: true);
    await emit(_session);
    final wake = container.read(screenWakeProvider);
    await wake.setAlwaysOn(false);
    expect(wake.alwaysOn, isFalse);
    expect(applied, [true]);
    await emit(null);
    expect(applied, [true, false]);
    await wake.setAlwaysOn(true);
    expect(applied, [true, false, true]);
  });
}
