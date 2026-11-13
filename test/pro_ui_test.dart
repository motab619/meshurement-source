// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/pro_entitlement.dart';
import 'package:mesh_analyzer/ui/screens/about_screen.dart';
import 'package:mesh_analyzer/ui/screens/pro_paywall_screen.dart';

import 'pro_entitlement_test.dart' show FakeStore, purchase;

AppStoreProduct2Details sk2Yearly() => AppStoreProduct2Details.fromSK2Product(
      SK2Product(
        id: proYearlyId,
        displayName: 'Pro Yearly',
        displayPrice: r'$6.99',
        description: '',
        price: 6.99,
        type: SK2ProductType.autoRenewable,
        priceLocale: SK2PriceLocale(currencyCode: 'USD', currencySymbol: r'$'),
        subscription: const SK2SubscriptionInfo(
          subscriptionGroupID: 'g',
          subscriptionPeriod: SK2SubscriptionPeriod(
              value: 1, unit: SK2SubscriptionPeriodUnit.year),
          promotionalOffers: [],
        ),
      ),
    );

class _Store extends FakeStore {
  @override
  Future<ProductDetailsResponse> queryProducts(Set<String> ids) async {
    final base = sk2Yearly().sk2Product;
    final withTrial = AppStoreProduct2Details.fromSK2Product(SK2Product(
      id: base.id,
      displayName: base.displayName,
      displayPrice: base.displayPrice,
      description: '',
      price: base.price,
      type: base.type,
      priceLocale: base.priceLocale,
      subscription: SK2SubscriptionInfo(
        subscriptionGroupID: 'g',
        subscriptionPeriod: base.subscription!.subscriptionPeriod,
        promotionalOffers: [
          SK2SubscriptionOffer(
            price: 0,
            type: SK2SubscriptionOfferType.introductory,
            period: const SK2SubscriptionPeriod(
                value: 1, unit: SK2SubscriptionPeriodUnit.week),
            periodCount: 1,
            paymentMode: SK2SubscriptionOfferPaymentMode.freeTrial,
          ),
        ],
      ),
    ));
    return ProductDetailsResponse(productDetails: [
      withTrial,
      ProductDetails(
          id: proLifetimeId,
          title: 'Pro Lifetime',
          description: '',
          price: r'$18.99',
          rawPrice: 18.99,
          currencyCode: 'USD'),
    ], notFoundIDs: []);
  }
}

Future<ProEntitlement> _service(FakeStore store, DateTime now) async {
  final prefs = await SharedPreferences.getInstance();
  return ProEntitlement(
      prefs: prefs, store: store, clock: () => now, proOverride: false);
}

Widget _app(ProEntitlement s, Widget home) => ProviderScope(
      overrides: [proEntitlementProvider.overrideWithValue(s)],
      child: MaterialApp(home: home),
    );

void main() {
  final now = DateTime(2026, 10, 14, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Meshurement',
      packageName: 'x',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('paywall shows plans, trial text, disclosure and links',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = await _service(_Store(), now);
    await tester.pumpWidget(_app(s, const ProPaywallScreen()));
    await tester.pumpAndSettle();

    // Only what Pro includes today; nothing planned or "Coming soon".
    for (final f in proIncludedFeatures) {
      expect(find.text(f.title), findsOneWidget);
    }
    expect(proIncludedFeatures, contains(ProFeature.guidedTests));
    // MeshCore radios are free (2026-11-05): never on the paywall.
    expect(proIncludedFeatures, isNot(contains(ProFeature.meshCore)));
    expect(find.text(ProFeature.meshCore.title), findsNothing);
    for (final f in [
      ProFeature.placementAdvisor,
      ProFeature.coverageReport,
      ProFeature.offlineMaps,
      ProFeature.iCloudSync,
    ]) {
      expect(find.text(f.title), findsNothing);
    }
    expect(find.textContaining('Coming soon'), findsNothing);
    expect(find.textContaining('as they ship'), findsNothing);
    expect(
        find.textContaining(r'1 week free, then $6.99/year'), findsOneWidget);
    // Lifetime is never offered for sale, even if the store returns it.
    expect(find.byKey(const Key('plan_lifetime')), findsNothing);
    expect(find.textContaining(r'$18.99'), findsNothing);
    expect(find.textContaining('Lifetime'), findsNothing);
    expect(find.text('Restore Purchases'), findsOneWidget);
    expect(find.textContaining('renews automatically unless'), findsOneWidget);
    expect(find.textContaining('Settings > Apple ID > Subscriptions'),
        findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Terms of Use'), findsOneWidget);
    expect(find.text('Manage subscription'), findsNothing);
    // No missing-blurb "null".
    expect(find.textContaining('null'), findsNothing);
  });

  testWidgets('paywall shows the active yearly plan with its end date',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _Store()
      ..current = [
        purchase(
            proYearlyId, PurchaseStatus.restored, DateTime(2027, 10, 14, 12))
      ];
    final s = await _service(store, now);
    await s.start();
    await tester.pumpWidget(_app(s, const ProPaywallScreen()));
    await tester.pumpAndSettle();

    expect(find.text('You have Pro'), findsOneWidget);
    // "Active until", never "renews": auto-renew may have been cancelled.
    expect(find.textContaining('active until Oct 14, 2027'), findsOneWidget);
    expect(find.textContaining('renews Oct'), findsNothing);
    expect(find.text('Manage subscription'), findsOneWidget);
    expect(find.text('Restore Purchases'), findsNothing);
  });

  testWidgets('owned lifetime shows Lifetime on the active card',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _Store()
      ..current = [purchase(proLifetimeId, PurchaseStatus.restored)];
    final s = await _service(store, now);
    await s.start();
    await tester.pumpWidget(_app(s, const ProPaywallScreen()));
    await tester.pumpAndSettle();

    expect(find.text('You have Pro'), findsOneWidget);
    expect(find.textContaining('Lifetime'), findsOneWidget);
    expect(find.text('Manage subscription'), findsNothing);
    expect(find.text('Restore Purchases'), findsNothing);
  });

  group('About Pro row', () {
    Future<void> pumpAbout(WidgetTester tester, FakeStore store) async {
      final s = await _service(store, now);
      await s.start();
      await tester.pumpWidget(_app(s, const AboutScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('Get Pro when free', (tester) async {
      await pumpAbout(tester, FakeStore());
      expect(find.text('Meshurement Pro'), findsOneWidget);
      expect(find.text('Get Pro'), findsOneWidget);
    });

    testWidgets('lifetime', (tester) async {
      await pumpAbout(
          tester,
          FakeStore()
            ..current = [purchase(proLifetimeId, PurchaseStatus.restored)]);
      expect(find.text('Pro · lifetime'), findsOneWidget);
    });

    testWidgets('yearly shows the end date', (tester) async {
      await pumpAbout(
          tester,
          FakeStore()
            ..current = [
              purchase(proYearlyId, PurchaseStatus.restored,
                  DateTime(2027, 10, 14, 12))
            ]);
      expect(find.text('Pro · until Oct 14, 2027'), findsOneWidget);
    });

    testWidgets('tapping opens the paywall', (tester) async {
      await pumpAbout(tester, FakeStore());
      await tester.tap(find.text('Meshurement Pro'));
      await tester.pumpAndSettle();
      expect(find.byType(ProPaywallScreen), findsOneWidget);
    });
  });

  testWidgets('ProGate runs the action when Pro, shows the paywall when not',
      (tester) async {
    var created = 0;
    Future<void> pumpGate(FakeStore store) async {
      final s = await _service(store, now);
      await s.start();
      await tester.pumpWidget(const SizedBox()); // drop the old navigator
      await tester.pumpWidget(_app(
        s,
        Scaffold(
          body: ProGate(
            feature: ProFeature.coverageReport,
            onUnlocked: () => created++,
            builder: (context, unlocked, activate) =>
                TextButton(onPressed: activate, child: const Text('Create')),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
    }

    await pumpGate(FakeStore());
    expect(created, 0);
    expect(find.byType(ProPaywallScreen), findsOneWidget);
    expect(find.text('PDF coverage report is a Pro feature.'), findsOneWidget);

    await pumpGate(FakeStore()
      ..current = [purchase(proLifetimeId, PurchaseStatus.restored)]);
    expect(created, 1);
  });
}
