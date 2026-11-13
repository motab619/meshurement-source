// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/pro_entitlement.dart';
import 'package:mesh_analyzer/services/rig_comparison.dart';
import 'package:mesh_analyzer/services/rig_math.dart';
import 'package:mesh_analyzer/ui/screens/rig_comparison_screen.dart';
import 'package:mesh_analyzer/ui/widgets/comparison_actions.dart';

import 'pro_entitlement_test.dart' show FakeStore;

class _Env {
  final AppDatabase db;
  final CoverageMap map;
  final List<int> sessionIds;
  final SharedPreferences prefs;

  _Env(this.db, this.map, this.sessionIds, this.prefs);

  Widget app(Widget home, {bool pro = false}) {
    final service = ProEntitlement(
        prefs: prefs,
        store: FakeStore(),
        clock: () => DateTime(2026, 10, 14),
        proOverride: pro);
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        proEntitlementProvider.overrideWithValue(service),
      ],
      child: MaterialApp(home: home),
    );
  }

  Widget actions() =>
      Scaffold(appBar: AppBar(actions: [ComparisonActions(map: map)]));
}

/// Real async work (database) must run outside the widget test's fake clock.
Future<_Env> _env(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  PackageInfo.setMockInitialValues(
    appName: 'Meshurement',
    packageName: 'x',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  final env = await tester.runAsync(() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final node = await db.upsertNode(nodeId: 1, longName: 'Base');
    final mapId = await db.createCoverageMap(name: 'Map', baseNodeId: node);
    final map =
        (await db.getAllCoverageMaps()).firstWhere((m) => m.id == mapId);
    final ids = [
      await db.createSession(
          coverageMapId: mapId,
          loraPreset: 'MEDIUM_FAST',
          mobileRigJson:
              const RigSpec(name: 'Stock', antennaGainDbi: 2).encode()),
      await db.createSession(
          coverageMapId: mapId,
          loraPreset: 'MEDIUM_FAST',
          mobileRigJson:
              const RigSpec(name: 'Whip', antennaGainDbi: 5.8).encode()),
    ];
    return _Env(db, map, ids, await SharedPreferences.getInstance());
  });
  addTearDown(() => tester.runAsync(env!.db.close));
  return env!;
}

/// Drop the screen so drift's stream clean-up timers fire inside the test.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('non-Pro tapping Compare sees the paywall', (tester) async {
    final env = await _env(tester);
    await tester.pumpWidget(env.app(env.actions()));
    await tester.tap(find.byIcon(Icons.compare));
    await tester.pumpAndSettle();
    expect(find.text('Meshurement Pro'), findsWidgets);
    expect(find.byType(RigComparisonPickerScreen), findsNothing);
    await _dispose(tester);
  });

  testWidgets('Pro tapping Compare opens the session picker', (tester) async {
    final env = await _env(tester);
    await tester.pumpWidget(env.app(env.actions(), pro: true));
    await tester.tap(find.byIcon(Icons.compare));
    await tester.pumpAndSettle();
    expect(find.byType(RigComparisonPickerScreen), findsOneWidget);
    expect(find.text('Meshurement Pro'), findsNothing);
    await _dispose(tester);
  });

  testWidgets('non-Pro can open a saved comparison', (tester) async {
    final env = await _env(tester);
    await SavedComparisonStore(env.prefs).add(SavedComparison(
        mapId: env.map.id,
        sessionIdsA: [env.sessionIds[0]],
        sessionIdsB: [env.sessionIds[1]],
        createdAt: DateTime(2026, 1, 1)));
    await tester.pumpWidget(env.app(env.actions()));
    await tester.tap(find.byIcon(Icons.bookmarks_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RigComparisonScreen), findsOneWidget);
    // The sessions have no readings, so the comparison ends empty.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('no overlapping route'), findsOneWidget);
    expect(find.text('Meshurement Pro'), findsNothing);
    await _dispose(tester);
  });
}
