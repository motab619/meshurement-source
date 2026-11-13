// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/app.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/pro_entitlement.dart';
import 'package:mesh_analyzer/ui/screens/onboarding/welcome_flow.dart';

/// Keeps the smoke test off the StoreKit plugin.
class _NoStore implements ProStoreGateway {
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();
  @override
  Future<void> refreshEntitlements() async {}
  @override
  Future<void> syncWithAppStore() async {}
  @override
  Future<void> buy(ProductDetails product) async {}
  @override
  Future<void> complete(PurchaseDetails purchase) async {}
  @override
  Future<bool> isIntroOfferEligible(ProductDetails product) async => false;
  @override
  Future<ProductDetailsResponse> queryProducts(Set<String> ids) async =>
      ProductDetailsResponse(productDetails: [], notFoundIDs: []);
}

void main() {
  testWidgets('App shows the bottom navigation and switches screens',
      (WidgetTester tester) async {
    // A phone: the bottom bar (a wide window gets the rail instead,
    // test/layout/app_nav_shell_test.dart).
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({onboardingSeenKey: true});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          notificationsProvider
              .overrideWithValue(FlutterLocalNotificationsPlugin()),
          databaseProvider.overrideWithValue(db),
          proEntitlementProvider.overrideWithValue(
              ProEntitlement(prefs: prefs, store: _NoStore())),
        ],
        child: const MeshAnalyzerApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['Live', 'Coverage', 'Settings']) {
      expect(
        find.descendant(
            of: find.byType(NavigationBar), matching: find.text(label)),
        findsOneWidget,
        reason: 'destination "$label"',
      );
    }

    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Settings')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Node Setup'), findsWidgets);

    // Unmount so providers dispose before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
      'Android back: Settings returns to Live; Live goes behind home, '
      'never finishes the activity', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <String>[];
    const channel = MethodChannel('mesh_analyzer/app');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      return call.method == 'launchArguments' ? <String>[] : null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    // A phone: the bottom bar (a wide window gets the rail instead,
    // test/layout/app_nav_shell_test.dart).
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({onboardingSeenKey: true});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          notificationsProvider
              .overrideWithValue(FlutterLocalNotificationsPlugin()),
          databaseProvider.overrideWithValue(db),
          proEntitlementProvider.overrideWithValue(
              ProEntitlement(prefs: prefs, store: _NoStore())),
        ],
        child: const MeshAnalyzerApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Settings')));
    await tester.pump(const Duration(milliseconds: 100));
    // The tab shell is an IndexedStack, so every screen stays in the tree:
    // the selected destination is the tell, not the visible text.
    int selectedTab() =>
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;
    expect(selectedTab(), 2);

    // Back from Settings: Live again, nothing asked of the platform.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(selectedTab(), 0);
    expect(calls, isNot(contains('moveToBack')));

    // Back from Live: the task goes behind the home screen; the engine
    // (and any recording session) stays alive.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, contains('moveToBack'));
    expect(find.byType(NavigationBar), findsOneWidget);

    // Before the test ends: the binding checks foundation overrides are unset.
    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
