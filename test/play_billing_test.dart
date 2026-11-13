// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/play_store_gateway.dart';
import 'package:mesh_analyzer/services/pro_entitlement.dart';
import 'package:mesh_analyzer/ui/screens/pro_paywall_screen.dart';

import 'pro_entitlement_test.dart' show FakeStore;

const _ids = ProProductIds.play;

GooglePlayPurchaseDetails playPurchase(
  String id, {
  PurchaseStateWrapper state = PurchaseStateWrapper.purchased,
  bool acknowledged = false,
  bool autoRenewing = true,
  PurchaseStatus? status,
}) {
  final p = GooglePlayPurchaseDetails.fromPurchase(PurchaseWrapper(
    orderId: 'GPA.1',
    packageName: 'com.plateaunerd.meshurement',
    purchaseTime: 0,
    purchaseToken: 'token',
    signature: '',
    products: [id],
    isAutoRenewing: autoRenewing,
    originalJson: '{}',
    isAcknowledged: acknowledged,
    purchaseState: state,
  )).single;
  if (status != null) p.status = status;
  return p;
}

PricingPhaseWrapper _phase(String price, int micros, String period,
        {int cycles = 0}) =>
    PricingPhaseWrapper(
      billingCycleCount: cycles,
      billingPeriod: period,
      formattedPrice: price,
      priceAmountMicros: micros,
      priceCurrencyCode: 'USD',
      recurrenceMode: cycles == 0
          ? RecurrenceMode.infiniteRecurring
          : RecurrenceMode.finiteRecurring,
    );

/// What Play returns for pro_yearly to a trial-eligible user: the base plan
/// and the free-week offer, one details object each.
List<GooglePlayProductDetails> playYearly({bool trial = true}) =>
    GooglePlayProductDetails.fromProductDetails(ProductDetailsWrapper(
      description: '',
      name: 'Pro',
      productId: _ids.yearly,
      productType: ProductType.subs,
      title: 'Pro (Meshurement)',
      subscriptionOfferDetails: [
        SubscriptionOfferDetailsWrapper(
          basePlanId: ProProductIds.playBasePlan,
          offerTags: const [],
          offerIdToken: 'base-token',
          pricingPhases: [_phase(r'$6.99', 6990000, 'P1Y')],
        ),
        if (trial)
          SubscriptionOfferDetailsWrapper(
            basePlanId: ProProductIds.playBasePlan,
            offerId: ProProductIds.playTrialOffer,
            offerTags: const [],
            offerIdToken: 'trial-token',
            pricingPhases: [
              _phase('Free', 0, 'P1W', cycles: 1),
              _phase(r'$6.99', 6990000, 'P1Y'),
            ],
          ),
      ],
    ));

class PlayFake extends FakeStore {
  bool unavailable = false;

  /// Play refuses to open its sheet (launchBillingFlow not OK).
  bool refuseBuy = false;

  /// Each refresh waits for this before answering (overlap tests).
  Completer<void>? gate;
  int refreshes = 0;

  @override
  Future<void> refreshEntitlements() async {
    refreshes++;
    if (unavailable) throw const ProStoreUnavailable();
    final g = gate;
    if (g != null) await g.future;
    return super.refreshEntitlements();
  }

  @override
  Future<void> buy(ProductDetails product) async {
    if (refuseBuy) throw const ProPurchaseNotStarted();
    return super.buy(product);
  }

  @override
  Future<ProductDetailsResponse> queryProducts(Set<String> ids) async {
    if (unavailable) {
      return ProductDetailsResponse(
        productDetails: const [],
        notFoundIDs: ids.toList(),
        error: IAPError(
            source: 'google_play', code: 'billing_unavailable', message: ''),
      );
    }
    return ProductDetailsResponse(
        productDetails: pickPlayOffers(playYearly()), notFoundIDs: []);
  }

  @override
  Future<bool> isIntroOfferEligible(ProductDetails product) async =>
      playTrialLabel(product) != null;
}

void main() {
  final now = DateTime(2026, 11, 6, 12);

  group('product ids', () {
    test('Play ids follow the Play Console rules', () {
      final rule = RegExp(r'^[a-z0-9][a-z0-9_.]*$');
      expect(rule.hasMatch(_ids.yearly), isTrue);
      expect(rule.hasMatch(_ids.lifetime), isTrue);
      expect(_ids.yearly.length, lessThanOrEqualTo(40));
      // The App Store ids would be rejected (capital A).
      expect(rule.hasMatch(proYearlyId), isFalse);
      final planRule = RegExp(r'^[a-z0-9][a-z0-9-]*$');
      expect(planRule.hasMatch(ProProductIds.playBasePlan), isTrue);
      expect(planRule.hasMatch(ProProductIds.playTrialOffer), isTrue);
    });

    test('ids and gateway per platform; only yearly is for sale', () {
      expect(ProStoreGateway.forPlatform(TargetPlatform.iOS),
          isA<AppStoreGateway>());
      expect(ProStoreGateway.forPlatform(TargetPlatform.android),
          isA<PlayStoreGateway>());
      expect(ProStoreGateway.forPlatform(TargetPlatform.linux),
          isA<NoStoreGateway>());
      expect(ProProductIds.of(PlayStoreGateway()), ProProductIds.play);
      expect(ProProductIds.of(AppStoreGateway()), ProProductIds.appStore);
      expect(ProProductIds.of(NoStoreGateway()).store, ProStoreKind.none);
      expect(ProProductIds.of(FakeStore()), ProProductIds.appStore);
      expect(_ids.forSale, {'pro_yearly'});
      expect(ProProductIds.appStore.forSale, proProductIds);
    });
  });

  group('Play purchase to grant', () {
    test('active subscription: verified now, no expiry', () {
      final g = playGrantOf(
          playPurchase(_ids.yearly, status: PurchaseStatus.restored),
          _ids,
          now);
      expect(g, ProGrant.verified(now));
      expect(g!.expiry, isNull);
      expect(g.activeAt(now), isTrue);
    });

    test('cancelled but still paid-up subscription still counts', () {
      // queryPurchasesAsync lists it until the period ends; autoRenewing
      // is false after a cancel.
      final g = playGrantOf(
          playPurchase(_ids.yearly,
              autoRenewing: false, status: PurchaseStatus.restored),
          _ids,
          now);
      expect(g?.plan, ProPlan.yearly);
    });

    test('lifetime (incl. promo code redemption)', () {
      expect(playGrantOf(playPurchase(_ids.lifetime), _ids, now),
          ProGrant.lifetime);
    });

    test('pending grants nothing, even when restore labels it restored', () {
      expect(
          playGrantOf(
              playPurchase(_ids.yearly, state: PurchaseStateWrapper.pending),
              _ids,
              now),
          isNull);
      expect(
          playGrantOf(
              playPurchase(_ids.lifetime,
                  state: PurchaseStateWrapper.pending,
                  status: PurchaseStatus.restored),
              _ids,
              now),
          isNull);
    });

    test('canceled flow, error and unknown products grant nothing', () {
      expect(
          playGrantOf(
              playPurchase(_ids.yearly, status: PurchaseStatus.canceled),
              _ids,
              now),
          isNull);
      expect(
          playGrantOf(playPurchase(_ids.yearly, status: PurchaseStatus.error),
              _ids, now),
          isNull);
      expect(playGrantOf(playPurchase('other'), _ids, now), isNull);
      // App Store ids don't unlock anything on Play.
      expect(playGrantOf(playPurchase(proYearlyId), _ids, now), isNull);
    });

    test('entitlementOf dispatches Play purchases', () {
      expect(
          ProEntitlement.entitlementOf(playPurchase(_ids.lifetime), now, _ids),
          ProGrant.lifetime);
    });
  });

  group('grant without expiry', () {
    test('trusted for the recheck window after the last refresh', () {
      final g = ProGrant.verified(now);
      expect(g.activeAt(now.add(const Duration(days: 2, hours: 23))), isTrue);
      expect(g.activeAt(now.add(ProGrant.recheckWindow)), isFalse);
      expect(g.untilLabel, isNull);
    });

    test('an iOS cache written before Play support still reads as Pro', () {
      // pro_entitlement_v1 as the App Store-only build wrote it.
      final expiry = now.add(const Duration(days: 200));
      final g = ProGrant.fromJson({
        'plan': 'yearly',
        'expiryMs': expiry.millisecondsSinceEpoch,
      });
      expect(g, ProGrant(ProPlan.yearly, expiry));
      expect(g.activeAt(now), isTrue);
      expect(ProGrant.fromJson({'plan': 'lifetime'}), ProGrant.lifetime);
      // Garbage or a yearly without any date grants nothing.
      expect(ProGrant.fromJson({'plan': 'yearly'}), ProGrant.none);
      expect(ProGrant.fromJson({'plan': 'bogus'}), ProGrant.none);
    });

    test('a verified-only grant round-trips without expiryMs', () {
      final g = ProGrant(ProPlan.yearly, null, now);
      expect(g.toJson().containsKey('expiryMs'), isFalse);
      expect(ProGrant.fromJson(g.toJson()), ProGrant.verified(now));
    });

    test('round-trips through the cache', () {
      final g = ProGrant.verified(now);
      expect(ProGrant.fromJson(g.toJson()), g);
      final e = ProGrant(ProPlan.yearly, now);
      expect(ProGrant.fromJson(e.toJson()), e);
      expect(e.untilLabel, 'Nov 6, 2026');
    });
  });

  group('ProEntitlement on Play', () {
    late PlayFake store;
    late SharedPreferences prefs;

    Future<ProEntitlement> make({DateTime? at}) async {
      prefs = await SharedPreferences.getInstance();
      return ProEntitlement(
        prefs: prefs,
        store: store,
        productIds: _ids,
        clock: () => at ?? now,
        proOverride: false,
      );
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      store = PlayFake();
    });

    test('active subscription is Pro, acknowledged on restore, cached',
        () async {
      final p = playPurchase(_ids.yearly, status: PurchaseStatus.restored);
      store.current = [p];
      final s = await make();
      await s.start();
      expect(s.isPro, isTrue);
      expect(s.status.store, ProStoreKind.googlePlay);
      expect(s.status.entitlement, ProGrant.verified(now));
      expect(store.completed, [p]);

      // Offline later: trusted for 3 days after that refresh, then not.
      store.failRefresh = true;
      final day2 = await make(at: now.add(const Duration(days: 2)));
      await day2.start();
      expect(day2.isPro, isTrue);
      final day4 = await make(at: now.add(const Duration(days: 4)));
      await day4.start();
      expect(day4.isPro, isFalse);
    });

    test('already acknowledged purchases are not completed again', () async {
      store.current = [
        playPurchase(_ids.lifetime,
            acknowledged: true, status: PurchaseStatus.restored)
      ];
      final s = await make();
      await s.start();
      expect(s.status.entitlement, ProGrant.lifetime);
      expect(store.completed, isEmpty);
    });

    test('subscription missing from a refresh (expired) clears Pro', () async {
      store.current = [
        playPurchase(_ids.yearly, status: PurchaseStatus.restored)
      ];
      final s = await make();
      await s.start();
      expect(s.isPro, isTrue);
      store.current = [];
      await s.refresh();
      expect(s.isPro, isFalse);
    });

    test('pending purchase: not Pro, Play wording', () async {
      final s = await make();
      await s.start();
      store.controller.add(
          [playPurchase(_ids.yearly, state: PurchaseStateWrapper.pending)]);
      await pumpEventQueue();
      expect(s.isPro, isFalse);
      expect(s.status.error, contains('Google Play'));
    });

    test('billing unavailable: no crash, cache kept, clear message', () async {
      store.unavailable = true;
      final s = await make();
      await s.start();
      expect(s.isPro, isFalse);
      await s.loadProducts();
      expect(s.status.productsLoaded, isTrue);
      expect(s.status.yearly, isNull);
      expect(s.status.error, contains('not available'));
      await s.restore();
      expect(s.status.busy, isFalse);
      expect(s.status.error, contains('Google Play'));
    });

    test('lifetime from a promo code shows up in a restore and is acknowledged',
        () async {
      // Redeemed in the Play Store app while Meshurement was closed: the
      // next refresh lists it as restored, still unacknowledged.
      final p = playPurchase(_ids.lifetime, status: PurchaseStatus.restored);
      expect(p.pendingCompletePurchase, isTrue);
      store.current = [p];
      final s = await make();
      await s.start();
      expect(s.status.entitlement, ProGrant.lifetime);
      expect(store.completed, [p]);
      expect(s.isPro, isTrue);
    });

    test('a pending purchase is never acknowledged and frees the button',
        () async {
      final s = await make();
      await s.start();
      await s.loadProducts();
      await s.buyYearly();
      expect(s.status.busy, isTrue);
      final p = playPurchase(_ids.yearly, state: PurchaseStateWrapper.pending);
      store.controller.add([p]);
      await pumpEventQueue();
      expect(s.status.busy, isFalse);
      expect(s.isPro, isFalse);
      // Restore lists it as "restored", still PENDING: no grant either.
      store.current = [
        playPurchase(_ids.yearly,
            state: PurchaseStateWrapper.pending,
            status: PurchaseStatus.restored)
      ];
      await s.refresh();
      expect(s.isPro, isFalse);
    });

    test('purchase sheet refused but already owned: restore, no error',
        () async {
      final s = await make();
      await s.start();
      await s.loadProducts();
      store
        ..refuseBuy = true
        ..current = [
          playPurchase(_ids.yearly, status: PurchaseStatus.restored)
        ];
      await s.buyYearly();
      expect(s.isPro, isTrue);
      expect(s.status.busy, isFalse);
      expect(s.status.error, isNull);
    });

    test('purchase sheet refused, nothing owned: message, not stuck', () async {
      final s = await make();
      await s.start();
      await s.loadProducts();
      store.refuseBuy = true;
      await s.buyYearly();
      expect(s.isPro, isFalse);
      expect(s.status.busy, isFalse);
      expect(s.status.error, contains('Google Play'));
    });

    test('itemAlreadyOwned on the purchase stream triggers a restore',
        () async {
      final s = await make();
      await s.start();
      await s.loadProducts();
      await s.buyYearly();
      final before = store.refreshes;
      store.current = [
        playPurchase(_ids.yearly, status: PurchaseStatus.restored)
      ];
      // What the plugin sends for ITEM_ALREADY_OWNED with no purchase.
      store.controller.add([
        PurchaseDetails(
          productID: '',
          status: PurchaseStatus.error,
          transactionDate: null,
          verificationData: PurchaseVerificationData(
              localVerificationData: '',
              serverVerificationData: '',
              source: 'google_play'),
        )..error = IAPError(
            source: 'google_play',
            code: 'purchase_error',
            message: 'BillingResponse.itemAlreadyOwned'),
      ]);
      await pumpEventQueue();
      expect(store.refreshes, before + 1);
      expect(s.isPro, isTrue);
      expect(s.status.error, isNull);
      expect(s.status.busy, isFalse);
    });

    test('user cancel is silent', () async {
      final s = await make();
      await s.start();
      await s.loadProducts();
      await s.buyYearly();
      store.controller.add([
        playPurchase(_ids.yearly, status: PurchaseStatus.canceled),
      ]);
      await pumpEventQueue();
      expect(s.status.busy, isFalse);
      expect(s.status.error, isNull);
    });

    test('overlapping refreshes (launch + resume) share one run', () async {
      store.current = [
        playPurchase(_ids.yearly, status: PurchaseStatus.restored)
      ];
      final s = await make();
      await s.start();
      expect(s.isPro, isTrue);
      final gate = store.gate = Completer<void>();
      final a = s.refresh();
      final b = s.refresh();
      gate.complete();
      expect(await a, isTrue);
      expect(await b, isTrue);
      expect(store.refreshes, 2); // start + one shared run
      expect(s.isPro, isTrue);
    });

    test('network error on restore: friendly message, cache kept', () async {
      store.current = [
        playPurchase(_ids.yearly, status: PurchaseStatus.restored)
      ];
      final s = await make();
      await s.start();
      store.failRefresh = true;
      await s.restore();
      expect(s.isPro, isTrue);
      expect(s.status.error, isNull);
      expect(
          ProEntitlement.friendlyError(
              InAppPurchaseException(
                  source: 'google_play',
                  code: 'restore_transactions_failed',
                  message: 'BillingResponse.serviceUnavailable'),
              'Google Play'),
          contains('Could not reach Google Play'));
    });

    test('offer shows the recurring price and the free week', () async {
      final s = await make();
      await s.start();
      await s.loadProducts();
      final y = s.status.yearly!;
      expect(y.displayPrice, r'$6.99');
      expect(y.trialLabel, '1 week free');
      await s.buyYearly();
      expect(store.bought, [_ids.yearly]);
    });
  });

  group('Play offers', () {
    test('picks the trial offer when present, else the base plan', () {
      final withTrial = pickPlayOffers(playYearly()).single;
      expect((withTrial as GooglePlayProductDetails).offerToken, 'trial-token');
      final noTrial = pickPlayOffers(playYearly(trial: false)).single;
      expect((noTrial as GooglePlayProductDetails).offerToken, 'base-token');
      expect(playTrialLabel(noTrial), isNull);
      expect(playDisplayPrice(withTrial), r'$6.99');
    });

    test('order-independent; other offers on the base plan are ignored', () {
      final details =
          GooglePlayProductDetails.fromProductDetails(ProductDetailsWrapper(
        description: '',
        name: 'Pro',
        productId: _ids.yearly,
        productType: ProductType.subs,
        title: 'Pro',
        subscriptionOfferDetails: [
          SubscriptionOfferDetailsWrapper(
            basePlanId: ProProductIds.playBasePlan,
            offerId: 'winback',
            offerTags: const [],
            offerIdToken: 'winback-token',
            pricingPhases: [
              _phase(r'$2.99', 2990000, 'P1Y', cycles: 1),
              _phase(r'$6.99', 6990000, 'P1Y'),
            ],
          ),
          SubscriptionOfferDetailsWrapper(
            basePlanId: ProProductIds.playBasePlan,
            offerId: ProProductIds.playTrialOffer,
            offerTags: const [],
            offerIdToken: 'trial-token',
            pricingPhases: [
              _phase('Free', 0, 'P1W', cycles: 1),
              _phase(r'$6.99', 6990000, 'P1Y'),
            ],
          ),
          SubscriptionOfferDetailsWrapper(
            basePlanId: 'monthly',
            offerTags: const [],
            offerIdToken: 'monthly-token',
            pricingPhases: [_phase(r'$0.99', 990000, 'P1M')],
          ),
          SubscriptionOfferDetailsWrapper(
            basePlanId: ProProductIds.playBasePlan,
            offerTags: const [],
            offerIdToken: 'base-token',
            pricingPhases: [_phase(r'$6.99', 6990000, 'P1Y')],
          ),
        ],
      ));
      final picked = pickPlayOffers(details.reversed.toList()).single
          as GooglePlayProductDetails;
      expect(picked.offerToken, 'trial-token');
      expect(pickPlayOffers(details).single, same(picked));
      expect(playDisplayPrice(picked), r'$6.99');
      expect(playTrialLabel(picked), '1 week free');
      // Without the trial (not eligible): the plain base plan, never the
      // discounted winback offer.
      final noTrial =
          details.where((d) => d.offerToken != 'trial-token').toList();
      expect(
          (pickPlayOffers(noTrial).single as GooglePlayProductDetails)
              .offerToken,
          'base-token');
      // The price is never the trial's "Free" (the plugin's own price is).
      expect(picked.price, 'Free');
    });

    test('ISO periods', () {
      expect(parseIsoPeriod('P1W'), (1, 'week'));
      expect(parseIsoPeriod('P3D'), (3, 'day'));
      expect(parseIsoPeriod('P1Y'), (1, 'year'));
      expect(parseIsoPeriod('P1Y2M'), isNull);
    });
  });

  group('PlayStoreGateway against a fake plugin', () {
    test('refused sheet throws; unavailable billing throws on refresh',
        () async {
      final iap = _FakeIap()..launches = false;
      final g = PlayStoreGateway(iap);
      final product = pickPlayOffers(playYearly()).single;
      await expectLater(g.buy(product), throwsA(isA<ProPurchaseNotStarted>()));
      expect(iap.boughtTokens, ['trial-token']);
      iap.available = false;
      await expectLater(
          g.refreshEntitlements(), throwsA(isA<ProStoreUnavailable>()));
      final r = await g.queryProducts({_ids.yearly});
      expect(r.error?.code, 'billing_unavailable');
      expect(r.productDetails, isEmpty);
    });

    test('acknowledges purchased, skips pending', () async {
      final iap = _FakeIap();
      final g = PlayStoreGateway(iap);
      final paid = playPurchase(_ids.lifetime, status: PurchaseStatus.restored);
      final pending =
          playPurchase(_ids.yearly, state: PurchaseStateWrapper.pending);
      await g.complete(pending);
      await g.complete(paid);
      expect(iap.completed, [paid]);
    });
  });

  testWidgets('paywall on Play: no "until", Google Play wording',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = PlayFake()
      ..current = [playPurchase(_ids.yearly, status: PurchaseStatus.restored)];
    final s = ProEntitlement(
        prefs: prefs,
        store: store,
        productIds: _ids,
        clock: () => now,
        proOverride: false);
    await s.start();
    await tester.pumpWidget(ProviderScope(
      overrides: [proEntitlementProvider.overrideWithValue(s)],
      child: const MaterialApp(home: ProPaywallScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Yearly plan, active.'), findsOneWidget);
    expect(find.textContaining('until'), findsNothing);
    expect(find.textContaining('null'), findsNothing);
    expect(find.text('Manage subscription'), findsOneWidget);
    expect(
        playManageSubscriptionsUrl,
        'https://play.google.com/store/account/subscriptions'
        '?sku=pro_yearly&package=com.plateaunerd.meshurement');

    // Not Pro: the disclosure names Google Play, not the Apple ID.
    store.current = [];
    await s.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('Google Play account'), findsOneWidget);
    expect(find.textContaining('Apple ID'), findsNothing);
    expect(
        find.textContaining('1 week free, then \$6.99/year'), findsOneWidget);
  });
}

/// Just enough of [InAppPurchase] for [PlayStoreGateway].
class _FakeIap implements InAppPurchase {
  bool available = true;
  bool launches = true;
  final boughtTokens = <String?>[];
  final completed = <PurchaseDetails>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    boughtTokens.add(
        (purchaseParam.productDetails as GooglePlayProductDetails).offerToken);
    return launches;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async =>
      completed.add(purchase);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
