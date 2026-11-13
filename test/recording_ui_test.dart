// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/ui/screens/coverage_map_list_screen.dart';
import 'package:mesh_analyzer/ui/widgets/session_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_location_backend.dart';
import 'fakes/fake_mesh_radio.dart';

void main() {
  late AppDatabase db;
  late FakeMeshRadio radio;
  late FakeLocationBackend location;
  late ProviderContainer container;
  late int mapId;

  Future<void> setUpWorld(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      // Radio Setup made node 2 the base.
      SharedPreferences.setMockInitialValues({'base_node_num': 2});
      final prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      radio = FakeMeshRadio(currentPreset: MeshtasticPresets.longFast);
      location = FakeLocationBackend();
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(radio),
        gpsServiceProvider.overrideWithValue(GpsService(backend: location)),
      ]);
      final base = await db.upsertNode(nodeId: 2);
      mapId = await db.createCoverageMap(name: 'Polo', baseNodeId: base);
    });
  }

  Future<void> tearDownWorld(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await container.read(sessionManagerProvider).endSession();
      container.dispose();
      await db.close();
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  Widget app(Widget child) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: child)),
      );

  testWidgets('start form shows GPS status and refuses without location',
      (tester) async {
    await setUpWorld(tester);
    location.permission = LocationPermission.deniedForever;
    await tester.pumpWidget(app(const SessionPanel()));
    await settle(tester);

    expect(
        find.text('Out-of-range alerts need notifications.'), findsOneWidget);
    await tester.tap(find.text('Start session'));
    await settle(tester);

    expect(find.byKey(const ValueKey('start-error')), findsOneWidget);
    expect(find.textContaining('Location permission is off'), findsOneWidget);
    expect(find.text('GPS: permission denied — enable in Settings'),
        findsOneWidget);
    expect(container.read(sessionManagerProvider).activeSession, isNull);
    await tearDownWorld(tester);
  });

  testWidgets('End Session asks first; Continue session keeps it',
      (tester) async {
    await setUpWorld(tester);
    await tester.runAsync(() => container
        .read(sessionManagerProvider)
        .startSession(coverageMapId: mapId, baseMeshNodeId: 2));
    await tester.pumpWidget(app(const SessionPanel()));
    await settle(tester);

    expect(find.text('GPS: waiting for fix…'), findsOneWidget);
    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();
    expect(find.text('The session ends; its data is kept.'), findsOneWidget);

    await tester.tap(find.text('Continue session'));
    await settle(tester);
    expect(container.read(sessionManagerProvider).activeSession, isNotNull);

    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End'));
    await settle(tester);
    expect(container.read(sessionManagerProvider).activeSession, isNull);
    await tearDownWorld(tester);
  });

  testWidgets(
      'recording: a stat grid on top, setup folded, End session pinned in '
      'view on a phone; after it, a verdict', (tester) async {
    await setUpWorld(tester);
    // A phone, sheet at its half height.
    tester.view.physicalSize = const Size(390, 844);
    await tester.runAsync(() => container
        .read(sessionManagerProvider)
        .startSession(coverageMapId: mapId, baseMeshNodeId: 2));
    await tester.pumpWidget(app(const SessionPanel()));
    await settle(tester);

    for (final k in [
      'stat-readings',
      'stat-beacons',
      'stat-pings',
      'stat-gps',
      'stat-airtime',
      'stat-elapsed',
    ]) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('stat-readings')),
            matching: find.text('0')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('stat-gps')),
            matching: find.text('No fix')),
        findsOneWidget);
    // Setup facts are folded away.
    expect(find.text('Setup'), findsOneWidget);
    expect(find.textContaining('Map: Polo'), findsNothing);

    // End session sits inside the screen without scrolling.
    final end = find.byKey(const ValueKey('end-session'));
    expect(end.hitTestable(), findsOneWidget);
    expect(tester.getRect(end).bottom, lessThanOrEqualTo(844));

    await tester.tap(end);
    await tester.pumpAndSettle();
    await tester.tap(find.text('End'));
    await settle(tester);
    await settle(tester);
    expect(container.read(sessionManagerProvider).activeSession, isNull);
    // Nothing was due from the base in a session this short: said plainly.
    expect(find.byKey(const ValueKey('ended-session-verdict')), findsOneWidget);
    expect(find.textContaining('Base node not heard'), findsOneWidget);
    await tearDownWorld(tester);
  });

  testWidgets('the map being recorded cannot be deleted', (tester) async {
    await setUpWorld(tester);
    await tester.runAsync(() => container
        .read(sessionManagerProvider)
        .startSession(coverageMapId: mapId, baseMeshNodeId: 2));
    await tester.pumpWidget(app(const CoverageMapListScreen()));
    await settle(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.textContaining('Stop the session first'), findsOneWidget);
    expect(find.text('Delete map?'), findsNothing);

    // Once stopped: the dialog names the map and its sessions.
    await tester
        .runAsync(() => container.read(sessionManagerProvider).endSession());
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.textContaining('"Polo" with its 1 session'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);
    expect(await tester.runAsync(db.getAllCoverageMaps), isEmpty);
    await tearDownWorld(tester);
  });
}
