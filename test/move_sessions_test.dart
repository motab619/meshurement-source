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

/// A session recorded on the wrong map can be moved to another one
/// (feedback 2026-10-28).
void main() {
  Future<(AppDatabase, CoverageMap, int, int)> env(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final out = await tester.runAsync(() async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final node = await db.upsertNode(nodeId: 1, longName: 'Base');
      final a = await db.createCoverageMap(name: 'Wrong map', baseNodeId: node);
      final b = await db.createCoverageMap(name: 'Right map', baseNodeId: node);
      final sids = <int>[];
      for (var s = 0; s < 2; s++) {
        final sid = await db.createSession(
            coverageMapId: a, name: 'walk $s', loraPreset: 'MEDIUM_FAST');
        await db.insertPacketEvent(PacketEventsCompanion.insert(
          sessionId: sid,
          timestamp: DateTime(2026, 10, 1, 12, s),
          direction: PacketDirection.rx,
          sourceNodeId: node,
          packetType: PacketType.telemetry,
          rxSnr: const Value(4),
          rxLat: const Value(33.68),
          rxLon: Value(-116.24 + s * 0.001),
        ));
        await db.endSession(sid);
        sids.add(sid);
      }
      final map = (await db.getAllCoverageMaps()).firstWhere((m) => m.id == a);
      return (db, map, b, sids.first);
    });
    addTearDown(() => tester.runAsync(out!.$1.close));
    return out!;
  }

  Future<void> settle(WidgetTester tester, [int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  test('moveSessions refiles sessions under another map', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final node = await db.upsertNode(nodeId: 1);
    final a = await db.createCoverageMap(name: 'A', baseNodeId: node);
    final b = await db.createCoverageMap(name: 'B', baseNodeId: node);
    final s1 = await db.createSession(coverageMapId: a);
    final s2 = await db.createSession(coverageMapId: a);
    await db.moveSessions([s1], b);
    final all = await db.select(db.sessions).get();
    expect(all.firstWhere((s) => s.id == s1).coverageMapId, b);
    expect(all.firstWhere((s) => s.id == s2).coverageMapId, a);
  });

  group('guided tests stay with their map', () {
    late AppDatabase db;
    late int a, b, s1, s2, step1, step2;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      final node = await db.upsertNode(nodeId: 1);
      a = await db.createCoverageMap(name: 'A', baseNodeId: node);
      b = await db.createCoverageMap(name: 'B', baseNodeId: node);
      s1 = await db.createSession(coverageMapId: a);
      s2 = await db.createSession(coverageMapId: a);
      final plan = await db.insertTestPlan(TestPlansCompanion.insert(
        coverageMapId: a,
        title: 'Antennas',
        template: 'antennas',
        intentJson: '{}',
        createdAt: DateTime(2026, 11, 4),
      ));
      await db.insertTestSteps([
        for (var i = 0; i < 2; i++)
          TestStepsCompanion.insert(
              planId: plan,
              ordinal: i,
              kind: 'walk',
              title: 'Walk $i',
              instruction: ''),
      ]);
      final steps = await db.getTestSteps(plan);
      step1 = steps[0].id;
      step2 = steps[1].id;
      await db.linkSessionToStep(step1, s1);
      await db.linkSessionToStep(step2, s2);
    });

    tearDown(() => db.close());

    test('a session moved to another map leaves its plan', () async {
      await db.moveSessions([s1], b);
      final moved = (await db.getSessionById(s1))!;
      expect(moved.coverageMapId, b);
      expect(moved.testStepId, isNull);
      final steps = {
        for (final t in await db.select(db.testSteps).get()) t.id: t
      };
      expect(steps[step1]!.sessionId, isNull,
          reason: 'the step keeps its place');
      expect(steps[step2]!.sessionId, s2, reason: 'the other walk stays');
      expect((await db.getSessionById(s2))!.testStepId, step2);

      // Deleting the new map leaves nothing pointing at the gone session.
      await db.deleteCoverageMap(b);
      expect(await db.getSessionById(s1), isNull);
      expect((await db.select(db.testSteps).get()).map((t) => t.sessionId),
          everyElement(isNot(s1)));
    });

    test('a session moved within its plan\'s map keeps the link', () async {
      await db.moveSessions([s1], a);
      expect((await db.getSessionById(s1))!.testStepId, step1);
    });

    test('deleting a plan\'s map unlinks sessions filed elsewhere', () async {
      // An older move (before moveSessions unlinked) left s1 linked.
      await (db.update(db.sessions)..where((s) => s.id.equals(s1)))
          .write(SessionsCompanion(coverageMapId: Value(b)));
      await db.deleteCoverageMap(a);
      final kept = (await db.getSessionById(s1))!;
      expect(kept.testStepId, isNull);
      expect(await db.select(db.testSteps).get(), isEmpty);
    });
  });

  testWidgets('Select… → Move → pick a map refiles the session',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.path);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null));
    tester.view.physicalSize = const Size(430, 930);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (db, map, rightMapId, firstSession) = await env(tester);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(home: CoverageMapDetailScreen(map: map)),
    ));
    await settle(tester, 20);

    // Raise the sheet so the session list is on screen.
    await tester.drag(find.text('Signal (base → you)'), const Offset(0, -700));
    await settle(tester);
    expect(find.text('walk 0'), findsOneWidget);
    expect(find.text('walk 1'), findsOneWidget);

    await tester.tap(find.text('Select…'));
    await settle(tester, 4);
    expect(find.byKey(const ValueKey('move-sessions')), findsOneWidget);
    // Pick the first session (the tiles become checkboxes).
    await tester.tap(find.byType(CheckboxListTile).first);
    await settle(tester, 4);
    await tester.tap(find.byKey(const ValueKey('move-sessions')));
    await settle(tester, 6);
    expect(find.text('Move session to…'), findsOneWidget);
    expect(find.text('New map…'), findsOneWidget);
    await tester.tap(find.text('Right map'));
    await settle(tester, 12);

    final all = await tester.runAsync(() => db.select(db.sessions).get());
    final moved = all!.where((s) => s.coverageMapId == rightMapId).toList();
    expect(moved, hasLength(1));
    expect(find.textContaining('moved to Right map'), findsOneWidget);
    // One session left on this map (its show/hide checkbox remains).
    expect(find.textContaining('walk '), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);
    expect(all.where((s) => s.coverageMapId == map.id).map((s) => s.id),
        isNot(contains(moved.single.id)));
    expect(firstSession, isNotNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
