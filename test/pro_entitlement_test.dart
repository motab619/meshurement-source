// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/services/pro_entitlement.dart';

class FakeStore implements ProStoreGateway {
  final controller = StreamController<List<PurchaseDetails>>.broadcast();
  List<PurchaseDetails> current = [];
  bool failRefresh = false;
  final completed = <PurchaseDetails>[];
  final bought = <String>[];

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => controller.stream;

  @override
  Future<void> refreshEntitlements() async {
    if (failRefresh) throw Exception('network error');
    controller.add(current);
  }

  @override
  Future<void> syncWithAppStore() async {}

  @override
  Future<void> buy(ProductDetails product) async => bought.add(product.id);

  @override
  Future<void> complete(PurchaseDetails purchase) async =>
      completed.add(purchase);

  @override
  Future<bool> isIntroOfferEligible(ProductDetails product) async => true;

  @override
  Future<ProductDetailsResponse> queryProducts(Set<String> ids) async =>
      ProductDetailsResponse(productDetails: fakeProducts(), notFoundIDs: []);
}

List<ProductDetails> fakeProducts() => [
      ProductDetails(
          id: proYearlyId,
          title: 'Pro Yearly',
          description: '',
          price: r'$6.99',
          rawPrice: 6.99,
          currencyCode: 'USD'),
      ProductDetails(
          id: proLifetimeId,
          title: 'Pro Lifetime',
          description: '',
          price: r'$18.99',
          rawPrice: 18.99,
          currencyCode: 'USD'),
    ];

PurchaseDetails purchase(String id, PurchaseStatus status,
        [DateTime? expiry]) =>
    SK2PurchaseDetails(
      productID: id,
      purchaseID: '1',
      verificationData: PurchaseVerificationData(
          localVerificationData: '', serverVerificationData: '', source: 'x'),
      transactionDate: '0',
      status: status,
      expirationDate: expiry?.millisecondsSinceEpoch.toString(),
    );

void main() {
  final now = DateTime(2026, 10, 14, 12);
  late FakeStore store;
  late SharedPreferences prefs;

  Future<ProEntitlement> make({DateTime? at, bool override = false}) async {
    prefs = await SharedPreferences.getInstance();
    return ProEntitlement(
      prefs: prefs,
      store: store,
      clock: () => at ?? now,
      proOverride: override,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = FakeStore();
  });

  test('not Pro by default; canView always true, canCreate follows Pro',
      () async {
    final s = await make();
    await s.start();
    expect(s.isPro, isFalse);
    for (final f in ProFeature.values) {
      expect(s.canCreate(f), isFalse);
      expect(s.canView(f), isTrue);
    }
  });

  test('active yearly entitlement from StoreKit is Pro and is cached',
      () async {
    final expiry = now.add(const Duration(days: 200));
    store.current = [purchase(proYearlyId, PurchaseStatus.restored, expiry)];
    final s = await make();
    await s.start();
    expect(s.isPro, isTrue);
    expect(s.status.entitlement.plan, ProPlan.yearly);
    expect(s.status.entitlement.expiry, expiry);
    expect(prefs.getString(ProEntitlement.cacheKey), contains('yearly'));
    for (final f in ProFeature.values) {
      expect(s.canCreate(f), isTrue);
    }
  });

  test('lifetime is Pro and never expires', () async {
    store.current = [purchase(proLifetimeId, PurchaseStatus.restored)];
    final s = await make();
    await s.start();
    expect(s.isPro, isTrue);
    expect(s.status.entitlement.plan, ProPlan.lifetime);

    final later = await make(at: DateTime(2100));
    expect(later.isPro, isTrue); // from cache alone
  });

  test('lifetime beats yearly', () async {
    store.current = [
      purchase(proYearlyId, PurchaseStatus.restored,
          now.add(const Duration(days: 5))),
      purchase(proLifetimeId, PurchaseStatus.restored),
    ];
    final s = await make();
    await s.start();
    expect(s.status.entitlement.plan, ProPlan.lifetime);
  });

  test('cached subscription works offline until expiry + 3 days grace',
      () async {
    final expiry = now.add(const Duration(days: 10));
    store.current = [purchase(proYearlyId, PurchaseStatus.restored, expiry)];
    await (await make()).start();

    store.failRefresh = true; // offline
    final beforeExpiry =
        await make(at: expiry.subtract(const Duration(hours: 1)));
    await beforeExpiry.start();
    expect(beforeExpiry.isPro, isTrue);

    final inGrace = await make(at: expiry.add(const Duration(days: 2)));
    await inGrace.start();
    expect(inGrace.isPro, isTrue);

    final pastGrace =
        await make(at: expiry.add(const Duration(days: 3, minutes: 1)));
    await pastGrace.start();
    expect(pastGrace.isPro, isFalse);
  });

  test('successful refresh with no entitlements clears Pro (expired/refunded)',
      () async {
    store.current = [
      purchase(proYearlyId, PurchaseStatus.restored,
          now.add(const Duration(days: 1)))
    ];
    final s = await make();
    await s.start();
    expect(s.isPro, isTrue);

    store.current = [];
    await s.refresh();
    expect(s.isPro, isFalse);
    expect(prefs.getString(ProEntitlement.cacheKey), isNull);
  });

  test('failed refresh keeps the cached entitlement', () async {
    store.current = [purchase(proLifetimeId, PurchaseStatus.restored)];
    final s = await make();
    await s.start();
    store.failRefresh = true;
    await s.refresh();
    expect(s.isPro, isTrue);
  });

  test('expired yearly transaction grants nothing', () async {
    store.current = [
      purchase(proYearlyId, PurchaseStatus.restored,
          now.subtract(const Duration(days: 1)))
    ];
    final s = await make();
    await s.start();
    expect(s.isPro, isFalse);
  });

  test('a live purchase unlocks Pro and is completed', () async {
    final s = await make();
    await s.start();
    final p = purchase(proLifetimeId, PurchaseStatus.purchased);
    store.controller.add([p]);
    await Future<void>.delayed(Duration.zero);
    expect(s.isPro, isTrue);
    expect(store.completed, [p]);
  });

  test('status stream emits current value then updates', () async {
    final s = await make();
    await s.start();
    final seen = <bool>[];
    final sub = s.statusStream.listen((st) => seen.add(st.isPro));
    await Future<void>.delayed(Duration.zero);
    store.controller.add([purchase(proLifetimeId, PurchaseStatus.purchased)]);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen.first, isFalse);
    expect(seen.last, isTrue);
  });

  test('PRO_OVERRIDE forces Pro without any purchase', () async {
    final s = await make(override: true);
    await s.start();
    expect(s.isPro, isTrue);
    expect(s.canCreate(ProFeature.iCloudSync), isTrue);
  });

  test('purchase errors become friendly messages', () async {
    final s = await make();
    await s.start();
    final p = purchase(proYearlyId, PurchaseStatus.error);
    p.error = IAPError(
        source: 'app_store',
        code: 'network',
        message: 'The network is offline');
    store.controller.add([p]);
    await Future<void>.delayed(Duration.zero);
    expect(s.status.error, contains('App Store'));
    expect(s.status.error, isNot(contains('network is offline')));
  });

  test('loadProducts exposes only the yearly offer; buyYearly buys it',
      () async {
    final s = await make();
    await s.loadProducts();
    expect(s.status.productsLoaded, isTrue);
    expect(s.status.yearly?.id, proYearlyId);
    expect(s.status.yearly?.displayPrice, r'$6.99');
    expect(s.status.yearly?.periodLabel, 'year');
    expect(proProductIds, {proYearlyId});
    await s.buyYearly();
    expect(store.bought, [proYearlyId]);
  });
}
