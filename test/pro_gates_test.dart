// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/demo/demo_mode.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/pro_entitlement.dart';
import 'package:mesh_analyzer/ui/screens/pro_paywall_screen.dart';
import 'package:mesh_analyzer/ui/screens/rig_profiles_screen.dart';

import 'pro_entitlement_test.dart' show FakeStore;

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Meshurement',
      packageName: 'x',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async {
    DemoMode.enabled = false;
    await db.close();
  });

  Future<Widget> app({required bool pro}) async {
    final prefs = await SharedPreferences.getInstance();
    final service =
        ProEntitlement(prefs: prefs, store: FakeStore(), proOverride: pro);
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        proEntitlementProvider.overrideWithValue(service),
      ],
      child: const MaterialApp(home: RigProfilesScreen()),
    );
  }

  // Unmount so drift's stream-cleanup timer fires inside the test.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<int> rigCount() async => (await db.watchRigProfiles().first).length;

  Future<void> seedRig(WidgetTester tester) => tester.runAsync(() async {
        await db.insertRigProfile(RigProfilesCompanion.insert(
          name: 'Stubby',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ));
      });

  testWidgets('non-Pro: New rig opens the paywall and creates nothing',
      (tester) async {
    await tester.pumpWidget(await app(pro: false));
    await tester.pump();
    expect(find.text('New hardware profile (Pro)'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);

    await tester.tap(find.text('New hardware profile (Pro)'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ProPaywallScreen), findsOneWidget);
    expect(find.byType(RigEditScreen), findsNothing);
    expect(await tester.runAsync(rigCount), 0);
    await unmount(tester);
  });

  testWidgets('Pro: New rig opens the editor and saves a rig', (tester) async {
    await tester.pumpWidget(await app(pro: true));
    await tester.pump();
    expect(find.text('New hardware profile'), findsOneWidget);

    await tester.tap(find.text('New hardware profile'));
    await tester.pumpAndSettle();
    expect(find.byType(ProPaywallScreen), findsNothing);
    expect(find.byType(RigEditScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Roof yagi');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(rigCount), 1);
    await unmount(tester);
  });

  testWidgets('non-Pro can still open, edit and archive existing rigs',
      (tester) async {
    await seedRig(tester);
    await tester.pumpWidget(await app(pro: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Stubby'), findsOneWidget);

    await tester.tap(find.text('Stubby'));
    await tester.pumpAndSettle();
    expect(find.byType(RigEditScreen), findsOneWidget);
    expect(find.byType(ProPaywallScreen), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Stubby 2');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Stubby 2'), findsOneWidget);

    await tester.drag(find.text('Stubby 2'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Stubby 2'), findsNothing);
    expect(await tester.runAsync(rigCount), 0);
    await unmount(tester);
  });

  test('demo mode is treated as Pro, normal mode is not', () async {
    // Normal mode on iOS: Android is free for now (TestBuild.androidProFree).
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer make() => ProviderContainer(overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ]);

    var c = make();
    addTearDown(c.dispose);
    expect(c.read(proEntitlementProvider).canCreate(ProFeature.rigProfiles),
        isFalse);

    DemoMode.enabled = true;
    c = make();
    addTearDown(c.dispose);
    final s = c.read(proEntitlementProvider);
    expect(s.canCreate(ProFeature.rigProfiles), isTrue);
    expect(s.isPro, isTrue);
  });

  test('Android: Pro without a purchase and without Play Billing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    final s = c.read(proEntitlementProvider);
    expect(s.isPro, isTrue);
    expect(s.canCreate(ProFeature.guidedTests), isTrue);
    // No store is asked: refresh returns at once (never opens Play Billing).
    expect(await s.refresh(), isTrue);
  });
}
