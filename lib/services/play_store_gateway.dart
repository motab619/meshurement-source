// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

// Google Play side of Pro (Android). Only this file and pro_entitlement.dart
// touch the store plugins; the UI sees ProOffer/ProStatus/ProGrant only.

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'pro_entitlement.dart';

/// Thrown when the store can't be asked at all (Play Billing unavailable:
/// a sideloaded debug build, no Google account, no Play Store). A refresh
/// that throws keeps the cached entitlement.
class ProStoreUnavailable implements Exception {
  const ProStoreUnavailable([this.message = 'billing_unavailable']);
  final String message;
  @override
  String toString() => 'ProStoreUnavailable: $message';
}

/// Thrown by [ProStoreGateway.buy] when the store refused to open its
/// purchase sheet (Play's `launchBillingFlow` returned something other than
/// OK, e.g. ITEM_ALREADY_OWNED, ITEM_UNAVAILABLE, DEVELOPER_ERROR). No
/// purchase result follows on the purchase stream in that case, so without
/// this the paywall would spin forever.
class ProPurchaseNotStarted implements Exception {
  const ProPurchaseNotStarted();
  @override
  String toString() => 'ProPurchaseNotStarted';
}

/// Google Play Billing (Billing Library 8 via in_app_purchase_android).
///
/// Play gives the app no expiry date for a subscription (only the Play
/// Developer API does, server side). `restorePurchases()` is
/// `queryPurchasesAsync` for in-app products and subscriptions, which
/// returns only what the user owns *now*: active subscriptions (including
/// cancelled ones still inside their paid period, and grace period) and
/// owned one-time products; expired, on-hold, paused and refunded ones are
/// left out. So "present in a successful refresh" is the entitlement, and
/// [ProGrant.verified] records when that was last confirmed.
class PlayStoreGateway implements ProStoreGateway {
  PlayStoreGateway([this._override]);
  final InAppPurchase? _override;

  // Lazy so constructing a ProEntitlement never touches the platform plugin.
  InAppPurchase get _iap => _override ?? InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  @override
  Future<ProductDetailsResponse> queryProducts(Set<String> ids) async {
    if (!await _available()) {
      return ProductDetailsResponse(
        productDetails: const [],
        notFoundIDs: ids.toList(),
        error: IAPError(
          source: 'google_play',
          code: 'billing_unavailable',
          message: 'Google Play Billing is not available on this device.',
        ),
      );
    }
    final r = await _iap.queryProductDetails(ids);
    return ProductDetailsResponse(
      productDetails: pickPlayOffers(r.productDetails),
      notFoundIDs: r.notFoundIDs,
      error: r.error,
    );
  }

  // The plugin takes the offer token from the chosen GooglePlayProductDetails
  // (the free-week offer when the user is eligible, else the base plan).
  // buyNonConsumable is right for subscriptions and never consumes.
  @override
  Future<void> buy(ProductDetails product) async {
    final launched = await _iap.buyNonConsumable(
        purchaseParam: GooglePlayPurchaseParam(productDetails: product));
    if (!launched) throw const ProPurchaseNotStarted();
  }

  @override
  Future<void> refreshEntitlements() async {
    if (!await _available()) throw const ProStoreUnavailable();
    // Throws InAppPurchaseException when either query fails, so a failed
    // refresh never clears Pro.
    await _iap.restorePurchases();
  }

  /// Play has no separate "sync with the store" step: the refresh that
  /// follows already asks Play for the account's current purchases.
  @override
  Future<void> syncWithAppStore() async {}

  /// Acknowledges the purchase. Play refunds and revokes a purchase that
  /// isn't acknowledged within three days of becoming PURCHASED. A PENDING
  /// purchase can't be acknowledged yet: it is skipped here and comes back
  /// (still unacknowledged) on a later refresh once paid.
  @override
  Future<void> complete(PurchaseDetails purchase) async {
    if (purchase is GooglePlayPurchaseDetails &&
        purchase.billingClientPurchase.purchaseState !=
            PurchaseStateWrapper.purchased) {
      return;
    }
    // The plugin acknowledges (never consumes) and skips purchases that are
    // already acknowledged. A failed acknowledge isn't thrown (the plugin
    // returns the BillingResult, which in_app_purchase types as void): the
    // purchase stays unacknowledged and the next refresh (every launch and
    // resume) acknowledges it again, well inside Play's three days.
    await _iap.completePurchase(purchase);
  }

  /// Play only lists offers the user is eligible for, so the trial is
  /// eligible exactly when the chosen details carry a free phase.
  @override
  Future<bool> isIntroOfferEligible(ProductDetails product) async =>
      playTrialLabel(product) != null;

  Future<bool> _available() async {
    try {
      return await _iap.isAvailable();
    } catch (_) {
      return false;
    }
  }
}

/// The entitlement a Google Play purchase grants, or null.
///
/// Only PURCHASED purchases count (a PENDING one is reported as `restored`
/// by the plugin's restore too, so the wrapper state is checked, not just
/// [PurchaseDetails.status]). A subscription has no expiry on device:
/// it is [ProGrant.verified] at [now].
ProGrant? playGrantOf(PurchaseDetails p, ProProductIds ids, DateTime now) {
  if (p.status != PurchaseStatus.purchased &&
      p.status != PurchaseStatus.restored) {
    return null;
  }
  if (p is GooglePlayPurchaseDetails &&
      p.billingClientPurchase.purchaseState != PurchaseStateWrapper.purchased) {
    return null;
  }
  if (p.productID == ids.lifetime) return ProGrant.lifetime;
  if (p.productID == ids.yearly) return ProGrant.verified(now);
  return null;
}

/// Play returns one [GooglePlayProductDetails] per subscription offer (the
/// base plan, plus each offer the user is eligible for). Keeps one per
/// product id: on [ProProductIds.playBasePlan], the free-trial offer when
/// present, else the plain base plan; other offers and base plans are
/// dropped. Non-subscription details pass through.
List<ProductDetails> pickPlayOffers(List<ProductDetails> all) {
  final chosen = <String, ProductDetails>{};
  int rank(ProductDetails p) {
    final offer = _offerOf(p);
    if (offer == null) return 1; // one-time product
    if (offer.basePlanId != ProProductIds.playBasePlan) return 0;
    if (_hasFreePhase(offer)) return 3;
    return offer.offerId == null ? 2 : 0;
  }

  for (final p in all) {
    final r = rank(p);
    if (r == 0) continue;
    final prev = chosen[p.id];
    if (prev == null || r > rank(prev)) chosen[p.id] = p;
  }
  // Fall back to whatever Play sent if no base plan matched (console
  // renamed): better a sale than nothing.
  for (final p in all) {
    chosen.putIfAbsent(p.id, () => p);
  }
  return chosen.values.toList();
}

/// Free trial of the chosen Play offer, e.g. "1 week free", or null.
String? playTrialLabel(ProductDetails product) {
  final offer = _offerOf(product);
  if (offer == null || !_hasFreePhase(offer)) return null;
  final free = offer.pricingPhases.first;
  final period = parseIsoPeriod(free.billingPeriod);
  if (period == null) return null;
  final n =
      period.$1 * (free.billingCycleCount < 1 ? 1 : free.billingCycleCount);
  return '$n ${period.$2}${n == 1 ? '' : 's'} free';
}

/// The recurring price of a Play subscription offer ("$6.99", not the
/// trial's "Free"): the infinitely recurring phase, which Play lists last;
/// [ProductDetails.price] for anything else.
String playDisplayPrice(ProductDetails product) {
  final offer = _offerOf(product);
  if (offer == null || offer.pricingPhases.isEmpty) return product.price;
  final phases = offer.pricingPhases;
  for (final ph in phases.reversed) {
    if (ph.recurrenceMode == RecurrenceMode.infiniteRecurring) {
      return ph.formattedPrice;
    }
  }
  return phases.last.formattedPrice;
}

/// "P1W" → (1, 'week'); "P7D" → (7, 'day'); null if not a single unit.
(int, String)? parseIsoPeriod(String iso) {
  final m = RegExp(r'^P(\d+)([DWMY])$').firstMatch(iso);
  if (m == null) return null;
  final unit = switch (m.group(2)) {
    'D' => 'day',
    'W' => 'week',
    'M' => 'month',
    _ => 'year',
  };
  return (int.parse(m.group(1)!), unit);
}

SubscriptionOfferDetailsWrapper? _offerOf(ProductDetails p) {
  if (p is! GooglePlayProductDetails) return null;
  final i = p.subscriptionIndex;
  final offers = p.productDetails.subscriptionOfferDetails;
  if (i == null || offers == null || i >= offers.length) return null;
  return offers[i];
}

bool _hasFreePhase(SubscriptionOfferDetailsWrapper o) =>
    o.pricingPhases.length > 1 && o.pricingPhases.first.priceAmountMicros == 0;
