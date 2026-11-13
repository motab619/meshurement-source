// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/base_ride_along_detector.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/ui/screens/map_screen.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_location_backend.dart';
import 'fakes/fake_mesh_radio.dart';

/// The Live map's "base riding with you" banner: Stop & trim, Stop only,
/// Keep going.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late int sessionId;
  final startedAt = DateTime(2026, 10, 28, 14, 32);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
    }
  }

  int dots(WidgetTester tester) =>
      tester.widget<CircleLayer>(find.byType(CircleLayer).first).circles.length;

  /// A recording session with two points before [startedAt] and three
  /// after, and the banner up.
  Future<void> pumpBanner(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.path);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null));
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({'base_node_num': 2});
      final prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(
            FakeMeshRadio(currentPreset: MeshtasticPresets.longFast)),
        gpsServiceProvider
            .overrideWithValue(GpsService(backend: FakeLocationBackend())),
      ]);
      final base = await db.upsertNode(nodeId: 2);
      final map = await db.createCoverageMap(name: 'Polo', baseNodeId: base);
      await db.setMapBaseLocation(map, 33.68, -116.24);
      final s = await container
          .read(sessionManagerProvider)
          .startSession(coverageMapId: map, baseMeshNodeId: 2);
      sessionId = s.id;
      for (final m in [-10, -5, 0, 2, 4]) {
        await db.insertPacketEvent(PacketEventsCompanion.insert(
          sessionId: s.id,
          timestamp: startedAt.add(Duration(minutes: m)),
          direction: PacketDirection.rx,
          sourceNodeId: base,
          packetType: PacketType.telemetry,
          rxRssi: const Value(-55),
          rxLat: const Value(33.68),
          rxLon: Value(-116.24 + m / 1000),
        ));
      }
      // Let the detector's start() finish before raising the banner.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    addTearDown(() async {
      await container.read(sessionManagerProvider).endSession();
      container.dispose();
      await db.close();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MapScreen()),
    ));
    await settle(tester);
    expect(dots(tester), 5);
    container.read(baseRideAlongDetectorProvider).pending.value =
        RideAlongEvent(startedAt: startedAt, samplesSince: 3);
    await settle(tester);
    expect(find.textContaining('riding with you since 14:32'), findsOneWidget);
    expect(find.textContaining('drop the 3 points'), findsOneWidget);
  }

  bool recording() =>
      container.read(sessionManagerProvider).activeSession != null;

  testWidgets('Stop & trim ends the session and drops the tail',
      (tester) async {
    await pumpBanner(tester);
    await tester.tap(find.byKey(const ValueKey('ride-along-trim')));
    await settle(tester);
    expect(recording(), isFalse);
    expect(find.byKey(const ValueKey('ride-along-banner')), findsNothing);
    expect(find.text('Session stopped; 3 points dropped'), findsOneWidget);
    final left = await tester.runAsync(() => db.getEventsForSession(sessionId));
    expect(left, hasLength(2));
    expect(dots(tester), 2);
  });

  testWidgets('Stop only ends the session and keeps everything',
      (tester) async {
    await pumpBanner(tester);
    await tester.tap(find.byKey(const ValueKey('ride-along-stop')));
    await settle(tester);
    expect(recording(), isFalse);
    expect(find.byKey(const ValueKey('ride-along-banner')), findsNothing);
    expect(find.text('Session stopped'), findsOneWidget);
    final left = await tester.runAsync(() => db.getEventsForSession(sessionId));
    expect(left, hasLength(5));
  });

  testWidgets('Keep going hides the banner and keeps recording',
      (tester) async {
    await pumpBanner(tester);
    await tester.tap(find.byKey(const ValueKey('ride-along-keep')));
    await settle(tester);
    expect(recording(), isTrue);
    expect(find.byKey(const ValueKey('ride-along-banner')), findsNothing);
    expect(container.read(baseRideAlongDetectorProvider).pending.value, isNull);
  });
}
