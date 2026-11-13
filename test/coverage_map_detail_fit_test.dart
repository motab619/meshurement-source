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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/ui/screens/coverage_map_detail_screen.dart';
import 'package:mesh_analyzer/ui/widgets/base_map_layers.dart';
import 'package:mesh_analyzer/utils/constants.dart';

const _baseLat = 33.68, _baseLon = -116.24;
const _degPerM = 1 / 111320;

/// A map with two sessions, each a 1 km walk north-east of the base;
/// optionally one stray fix at 0,0 in the first session.
Future<(AppDatabase, CoverageMap)> _env(WidgetTester tester,
    {bool strayZero = false}) async {
  SharedPreferences.setMockInitialValues({});
  final out = await tester.runAsync(() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final node = await db.upsertNode(nodeId: 1, longName: 'Base');
    final mapId = await db.createCoverageMap(name: 'Map', baseNodeId: node);
    var t = DateTime(2026, 10, 1, 12);
    for (var s = 0; s < 2; s++) {
      final sid = await db.createSession(
          coverageMapId: mapId, loraPreset: 'MEDIUM_FAST', packetAirtimeMs: 300);
      for (var m = 100; m <= 1000; m += 100) {
        t = t.add(const Duration(seconds: 30));
        await db.insertPacketEvent(PacketEventsCompanion.insert(
          sessionId: sid,
          timestamp: t,
          direction: PacketDirection.rx,
          sourceNodeId: node,
          packetType: PacketType.rangeTest,
          rxSnr: const Value(4),
          rxRssi: const Value(-98),
          rxLat: Value(_baseLat + m * _degPerM * 0.5),
          rxLon: Value(_baseLon + m * _degPerM * 1.2),
        ));
      }
      if (s == 0 && strayZero) {
        await db.insertPacketEvent(PacketEventsCompanion.insert(
          sessionId: sid,
          timestamp: t.add(const Duration(seconds: 1)),
          direction: PacketDirection.rx,
          sourceNodeId: node,
          packetType: PacketType.rangeTest,
          rxSnr: const Value(4),
          rxLat: const Value(0),
          rxLon: const Value(0),
        ));
      }
      await db.endSession(sid);
    }
    final map = (await db.getAllCoverageMaps()).firstWhere((m) => m.id == mapId);
    return (db, map);
  });
  addTearDown(() => tester.runAsync(out!.$1.close));
  return out!;
}

Future<void> _settle(WidgetTester tester, [int rounds = 12]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _open(WidgetTester tester, (AppDatabase, CoverageMap) env) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path);
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null));
  // Phone-sized, like the field build runs.
  tester.view.physicalSize = const Size(430, 930);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(env.$1),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
    child: MaterialApp(home: CoverageMapDetailScreen(map: env.$2)),
  ));
  await _settle(tester, 20);
}

MapCamera _camera(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(BaseMapLayers)));

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('toggling a session with the sheet pulled up keeps the route zoom',
      (tester) async {
    final env = await _env(tester);
    await _open(tester, env);
    final before = _camera(tester).zoom;
    expect(before, greaterThan(12), reason: 'first fit frames the 1 km walk');
    // Nothing here was relayed, so the legend does not explain small dots.
    expect(find.text('Small dot: relayed'), findsNothing);

    // Pull the results sheet to its top snap (92% of the screen).
    await tester.drag(find.text('Signal (base → you)'), const Offset(0, -700));
    await _settle(tester);

    // Hide one session: the map refits to the other.
    await tester.tap(find.byType(CheckboxListTile).first);
    await _settle(tester);

    final after = _camera(tester).zoom;
    expect(after, greaterThan(12),
        reason: 'refit under a tall sheet must not zoom out to the world');
    await _dispose(tester);
  });

  testWidgets('a stray 0,0 fix does not pull the fit out to the ocean',
      (tester) async {
    final env = await _env(tester, strayZero: true);
    await _open(tester, env);
    final cam = _camera(tester);
    expect(cam.zoom, greaterThan(12));
    expect(cam.center.latitude, closeTo(_baseLat, 0.05));
    await _dispose(tester);
  });

  testWidgets('the legend sits above the map credit, not over it',
      (tester) async {
    final env = await _env(tester);
    await _open(tester, env);
    final legend = tester.getRect(find
        .ancestor(
            of: find.text('Strong (20+ dB margin)'),
            matching: find.byType(Container))
        .first);
    final credit = tester.getRect(find.byType(MapCreditChip));
    expect(legend.overlaps(credit), isFalse);
    expect(legend.bottom, lessThanOrEqualTo(credit.top));
    await _dispose(tester);
  });

  testWidgets('session tile: setup line, then base heard and farthest in bold',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final env = (await tester.runAsync(() async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final node = await db.upsertNode(nodeId: 1, longName: 'Base');
      final mapId = await db.createCoverageMap(
          name: 'Map', baseNodeId: node, baseLat: _baseLat, baseLon: _baseLon);
      final sid = await db.createSession(
          coverageMapId: mapId, loraPreset: 'MEDIUM_FAST', packetAirtimeMs: 300);
      var t = DateTime(2026, 10, 1, 12);
      // Ten beacons heard, every other sequence number missed: 10 of 19.
      // Readings 30 m apart, so the farthest one has a neighbour.
      for (var k = 1; k <= 10; k++) {
        t = t.add(const Duration(seconds: 30));
        final m = 30.0 * k;
        await db.insertPacketEvent(PacketEventsCompanion.insert(
          sessionId: sid,
          timestamp: t,
          direction: PacketDirection.rx,
          sourceNodeId: node,
          packetType: PacketType.rangeTest,
          sourceKind: const Value(SourceKind.rangeTest),
          seq: Value(2 * k - 1),
          rxSnr: const Value(4),
          rxLat: Value(_baseLat + m * _degPerM * 0.5),
          rxLon: Value(_baseLon + m * _degPerM * 1.2),
        ));
      }
      await db.endSession(sid);
      final map =
          (await db.getAllCoverageMaps()).firstWhere((m) => m.id == mapId);
      return (db, map, sid);
    }))!;
    addTearDown(() => tester.runAsync(env.$1.close));
    await _open(tester, (env.$1, env.$2));
    await tester.drag(find.text('Signal (base → you)'), const Offset(0, -700));
    await _settle(tester);

    expect(find.textContaining('Medium Fast'), findsWidgets);
    final stats =
        tester.widget<Text>(find.byKey(ValueKey('session-stats-${env.$3}')));
    final spans = <TextSpan>[];
    stats.textSpan!.visitChildren((s) {
      if (s is TextSpan) spans.add(s);
      return true;
    });
    final plain = stats.textSpan!.toPlainText();
    expect(plain, contains('Base heard 53 %'));
    expect(plain, contains('Farthest '));
    expect(plain, contains('10 readings'));
    final bold = [
      for (final s in spans)
        if (s.style?.fontWeight == FontWeight.w700) s.text,
    ];
    expect(bold, hasLength(2));
    expect(bold.first, '53 %');
    await _dispose(tester);
  });

  testWidgets('Compare is a labelled button; export and saved comparisons '
      'are text items in the menu', (tester) async {
    final env = await _env(tester);
    await _open(tester, env);
    expect(find.widgetWithText(TextButton, 'Compare'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-menu')));
    await _settle(tester, 4);
    expect(find.text('Export / share…'), findsOneWidget);
    expect(find.text('Estimated coverage'), findsOneWidget);
    expect(find.text('Set base location…'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await _settle(tester, 4);
    await _dispose(tester);
  });
}
