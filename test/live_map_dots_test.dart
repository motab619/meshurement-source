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
import 'package:mesh_analyzer/services/active_probe_service.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/ui/screens/map_screen.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_location_backend.dart';
import 'fakes/fake_mesh_radio.dart';

/// The Live map shows the active session's dots. A new session starts
/// with a clean map (feedback 2026-10-28).
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late int mapId;
  late int baseDbId;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump();
    }
  }

  int dots(WidgetTester tester) =>
      tester.widget<CircleLayer>(find.byType(CircleLayer).first).circles.length;

  testWidgets('starting another session clears the previous dots',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.path);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null));
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final location = FakeLocationBackend();
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({'base_node_num': 2});
      final prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(
            FakeMeshRadio(currentPreset: MeshtasticPresets.longFast)),
        gpsServiceProvider.overrideWithValue(GpsService(backend: location)),
      ]);
      baseDbId = await db.upsertNode(nodeId: 2);
      mapId = await db.createCoverageMap(name: 'Polo', baseNodeId: baseDbId);
    });
    addTearDown(() async {
      await container.read(sessionManagerProvider).endSession();
      container.dispose();
      await db.close();
    });
    final sessions = container.read(sessionManagerProvider);

    // Session 1 with two received packets on the ground.
    await tester.runAsync(() async {
      final s =
          await sessions.startSession(coverageMapId: mapId, baseMeshNodeId: 2);
      for (final lon in [-116.24, -116.241]) {
        await db.insertPacketEvent(PacketEventsCompanion.insert(
          sessionId: s.id,
          timestamp: DateTime.now(),
          direction: PacketDirection.rx,
          sourceNodeId: baseDbId,
          packetType: PacketType.telemetry,
          rxSnr: const Value(8.0),
          rxLat: const Value(33.68),
          rxLon: Value(lon),
        ));
      }
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MapScreen()),
    ));
    await settle(tester);
    expect(dots(tester), 2);

    // Session 2 on the same map: the map starts clean.
    await tester.runAsync(() async {
      await sessions.endSession();
      await sessions.startSession(coverageMapId: mapId, baseMeshNodeId: 2);
    });
    await settle(tester);
    expect(dots(tester), 0);

    // A ping reply (base → you) is a signal sample: it lands as a dot
    // without passing through PacketProcessor.
    container.read(activeProbeServiceProvider).injectSample(PingSample(
          sentAt: DateTime.now(),
          answeredAt: DateTime.now(),
          status: AckStatus.received,
          snr: 6.5,
          rssi: -95,
          fromBase: true,
          latitude: 33.68,
          longitude: -116.242,
        ));
    await settle(tester);
    expect(dots(tester), 1);

    // A timeout has nothing to plot.
    container.read(activeProbeServiceProvider).injectSample(PingSample(
          sentAt: DateTime.now(),
          answeredAt: DateTime.now(),
          status: AckStatus.timeout,
          latitude: 33.68,
          longitude: -116.243,
        ));
    await settle(tester);
    expect(dots(tester), 1);
  });
}
