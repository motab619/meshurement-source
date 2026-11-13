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

import 'window_sizes.dart';

/// Coverage map detail: results in a sheet over the map on a phone, in a
/// column beside it on an iPad, and the map keeps its framing when the
/// window changes between the two (rotation, Split View, fold/unfold).
const _baseLat = 33.68, _baseLon = -116.24;
const _degPerM = 1 / 111320;

Future<(AppDatabase, CoverageMap)> _env(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final out = await tester.runAsync(() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final node = await db.upsertNode(nodeId: 1, longName: 'Base');
    final mapId = await db.createCoverageMap(name: 'Map', baseNodeId: node);
    var t = DateTime(2026, 10, 1, 12);
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
    await db.endSession(sid);
    final map =
        (await db.getAllCoverageMaps()).firstWhere((m) => m.id == mapId);
    return (db, map);
  });
  addTearDown(() => tester.runAsync(out!.$1.close));
  return out!;
}

Future<void> _settle(WidgetTester tester, [int rounds = 12]) async {
  for (var i = 0; i < rounds; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _open(
    WidgetTester tester, (AppDatabase, CoverageMap) env, Size size) async {
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathProvider, (call) async => Directory.systemTemp.path);
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, null));
  await setWindow(tester, size);
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

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 100));
}

MapCamera _camera(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(BaseMapLayers)));

final _docked = find.byKey(const ValueKey('coverage-results-docked'));
final _sheet = find.byType(DraggableScrollableSheet);

void main() {
  for (final (name, size) in [
    ('phone', phone),
    ('Duo folded', duoOuter),
    ('Duo unfolded upright', duoInner),
    ('iPad mini', iPadMini),
    ('iPad Pro 10.5', iPadPro105),
    ('iPad 11', iPad11),
  ]) {
    testWidgets('$name: results sheet over the map', (tester) async {
      final env = await _env(tester);
      await _open(tester, env, size);
      expect(_sheet, findsOneWidget);
      expect(_docked, findsNothing);
      expect(tester.getSize(find.byType(FlutterMap)).width, size.width);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  }

  for (final (name, size) in [
    ('iPad 13 portrait', const Size(1032, 1376)),
    ('iPad 13 landscape', iPad13Landscape),
    ('Duo unfolded sideways', duoInnerLandscape),
  ]) {
    testWidgets('$name: results beside the map', (tester) async {
      final env = await _env(tester);
      await _open(tester, env, size);
      expect(_docked, findsOneWidget);
      expect(_sheet, findsNothing);
      expect(find.text('Signal (base → you)'), findsOneWidget);
      expect(tester.getSize(find.byType(FlutterMap)).width,
          lessThan(size.width - 300));
      expect(_camera(tester).zoom, greaterThan(12),
          reason: 'the walk is framed with the whole map height');
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  }

  testWidgets('rotating an iPad keeps the map where it was', (tester) async {
    final env = await _env(tester);
    await _open(tester, env, iPad13Landscape);
    final before = _camera(tester).center;

    // Into a narrow Split View pane: back to the sheet, same map.
    await setWindow(tester, const Size(500, 1032));
    await _settle(tester);
    expect(_sheet, findsOneWidget);
    expect(_camera(tester).center.latitude, closeTo(before.latitude, 1e-9));
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });
}
