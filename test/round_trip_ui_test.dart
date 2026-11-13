// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/ui/screens/coverage_map_detail_screen.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pings are round trips (RF review item 2): the map detail's layer and
/// session tile say so, and a MeshCore session shows how the two legs
/// compare while a Meshtastic one shows nothing for it.
void main() {
  Future<void> pumpMap(WidgetTester tester, {required String protocol}) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.path);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null));
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final meshCore = protocol == 'meshcore';
    final (db, map) = (await tester.runAsync(() async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final node = await db.upsertNode(nodeId: 1, longName: 'Base');
      final mapId = await db.createCoverageMap(name: 'Park', baseNodeId: node);
      final sid = await db.createSession(
        coverageMapId: mapId,
        name: 'walk',
        loraPreset: '',
        protocol: protocol,
        pingIntervalSec: 30,
        beaconKind: meshCore ? 'trace' : '',
      );
      final t0 = DateTime(2026, 10, 1, 12);
      for (var i = 0; i < 6; i++) {
        final at = t0.add(Duration(seconds: 30 * i));
        final tx = await db.insertPacketEvent(PacketEventsCompanion.insert(
          sessionId: sid,
          timestamp: at,
          direction: PacketDirection.tx,
          sourceNodeId: node,
          packetType: 'ping',
          rxLat: Value(33.68 + i * 0.001),
          rxLon: const Value(-116.24),
        ));
        final ack = await db.insertPacketEvent(PacketEventsCompanion.insert(
          sessionId: sid,
          timestamp: at.add(const Duration(seconds: 1)),
          direction: PacketDirection.ack,
          sourceNodeId: node,
          packetType: PacketType.ack,
          sourceKind: const Value(SourceKind.ack),
          rxSnr: const Value(-5),
          rxRssi: const Value(-110),
          // The base heard us 2.5 dB worse than we heard it.
          uplinkSnr: Value(meshCore ? -7.5 : null),
          rxLat: Value(33.68 + i * 0.001),
          rxLon: const Value(-116.24),
        ));
        await db.insertPingCorrelation(PingCorrelationsCompanion.insert(
          txEventId: tx,
          ackEventId: Value(ack),
          roundTripMs: const Value(1000),
          ackStatus: const Value(AckStatus.received),
        ));
      }
      await db.endSession(sid);
      final map =
          (await db.getAllCoverageMaps()).firstWhere((m) => m.id == mapId);
      return (db, map);
    }))!;
    addTearDown(() => tester.runAsync(db.close));
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(home: CoverageMapDetailScreen(map: map)),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> unpump(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('MeshCore: round-trip layer, tile and uplink vs downlink',
      (tester) async {
    await pumpMap(tester, protocol: 'meshcore');
    expect(find.text('Link checks (you ⇄ base)'), findsOneWidget);
    expect(find.textContaining('link checks 6/6 came back'), findsOneWidget);
    expect(
        find.textContaining(
            'Uplink 2.5 dB weaker than downlink (median of 6 link checks)'),
        findsOneWidget);

    await tester.tap(find.text('Link checks (you ⇄ base)'));
    await tester.pump();
    expect(find.text('A reply needs both directions'), findsOneWidget);
    await unpump(tester);
  });

  testWidgets('Meshtastic: no uplink line', (tester) async {
    await pumpMap(tester, protocol: 'meshtastic');
    expect(find.text('Pings (you ⇄ base)'), findsOneWidget);
    expect(find.textContaining('pings 6/6 came back'), findsOneWidget);
    expect(find.textContaining('Uplink'), findsNothing);
    await unpump(tester);
  });
}
