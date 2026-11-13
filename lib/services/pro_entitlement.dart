// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'play_store_gateway.dart';

/// App Store product ids (see App Store Connect).
const proYearlyId = 'com.andybrunker.meshAnalyzer.pro.yearly';
const proLifetimeId = 'com.andybrunker.meshAnalyzer.pro.lifetime';

/// Only the yearly plan is queried for sale. The lifetime product is never
/// offered in the app; it exists so beta testers can redeem App Store offer
/// codes for it (redeemed in the App Store, not in the app).
const proProductIds = {proYearlyId};

/// Which store sells Pro on this device.
enum ProStoreKind { appStore, googlePlay, none }

/// Product ids per store, in one place.
///
/// Google Play ids may only use lowercase letters, digits, `_` and `.` and
/// must start with a lowercase letter or digit, so the App Store ids (with
/// the capital A of `meshAnalyzer`) can't be reused there. Play setup:
/// subscription [play] `.yearly` with base plan [playBasePlan] (1 year,
/// auto-renewing, $6.99) and offer [playTrialOffer] (free trial phase of
/// 1 week, eligibility "new customer acquisition"); one-time product [play]
/// `.lifetime`, never offered in the app, granted by Play promo codes.
@immutable
class ProProductIds {
  const ProProductIds._(this.store, this.yearly, this.lifetime);

  static const appStore =
      ProProductIds._(ProStoreKind.appStore, proYearlyId, proLifetimeId);
  static const play =
      ProProductIds._(ProStoreKind.googlePlay, playYearly, playLifetime);

  /// Google Play product ids.
  static const playYearly = 'pro_yearly';
  static const playLifetime = 'pro_lifetime';
  static const none =
      ProProductIds._(ProStoreKind.none, proYearlyId, proLifetimeId);

  /// Play base plan id of [play] `.yearly` (ids allow lowercase and `-`).
  static const playBasePlan = 'yearly';

  /// Play offer id of the 1-week free trial on [playBasePlan].
  static const playTrialOffer = 'free-week';

  /// Android application id, for Play's "manage this subscription" link.
  static const playPackageName = 'com.plateaunerd.meshurement';

  final ProStoreKind store;
  final String yearly;
  final String lifetime;

  /// Queried for sale: the yearly plan only (lifetime is never offered).
  Set<String> get forSale => {yearly};

  /// The ids that go with [store].
  static ProProductIds of(ProStoreGateway store) => switch (store) {
        PlayStoreGateway() => play,
        NoStoreGateway() => none,
        _ => appStore,
      };

  /// "the App Store" / "Google Play", for messages.
  String get storeName => switch (store) {
        ProStoreKind.googlePlay => 'Google Play',
        _ => 'the App Store',
      };
}

/// Pro features. Creating new items of these kinds is gated; viewing and
/// exporting existing ones never is.
enum ProFeature {
  // Creating a rig profile is gated; viewing, editing, archiving and
  // selecting existing rigs, and the rig columns in CSV export, stay free
  // for lapsed users (roadmap: never hold data hostage).
  rigProfiles('Hardware profiles'),
  rigComparison('Rig comparison'),
  placementAdvisor('Node placement advisor'),
  coverageReport('PDF coverage report'),

  /// Unused: MeshCore radios are free since 2026-11-05. Kept so the enum's
  /// order and any stored names don't shift.
  meshCore('MeshCore nodes'),
  offlineMaps('Offline map packs'),
  iCloudSync('iCloud backup & sync'),
  aiAnalysis('AI session analysis'),

  /// Guided test with three or four setups (two are free).
  guidedTests('Guided tests, 3–4 setups'),

  /// The recording on the lock screen and Dynamic Island (iOS). Checked
  /// when a session starts; out-of-range alerts stay free.
  liveActivity('Live Activity'),

  /// Pings and base beacon below the airtime recommendation (Settings →
  /// Active Probing). Without Pro the recommendation applies, whatever the
  /// stored preference says.
  fasterIntervals('Faster than recommended'),

  /// Change the base's range setting or TX power from the phone, outside a
  /// guided test (Radio Setup → "Change the base from here"; Meshtastic).
  remoteBaseChange('Change the base from a distance'),

  /// Sharing a Field Report in the Pop, Bridge or Mission style (Night and
  /// Basic are free; every style can be previewed).
  reportStyles('Field Report styles');

  const ProFeature(this.title);
  final String title;
}

/// `--dart-define=PRO_OVERRIDE=true` forces Pro in debug builds only.
const _proOverrideDefine = bool.fromEnvironment('PRO_OVERRIDE');

enum ProPlan { none, yearly, lifetime }

/// What the user is entitled to.
///
/// A [ProPlan.yearly] grant has either an [expiry] (App Store: StoreKit 2
/// gives the expiration date) or only [verifiedAt] (Google Play: the device
/// never learns the expiry; the subscription was present in the store's
/// list of current purchases at that time).
@immutable
class ProGrant {
  const ProGrant(this.plan, [this.expiry, this.verifiedAt]);

  /// A subscription the store confirmed as current at [at], expiry unknown.
  const ProGrant.verified(DateTime at)
      : plan = ProPlan.yearly,
        expiry = null,
        verifiedAt = at;

  static const none = ProGrant(ProPlan.none);
  static const lifetime = ProGrant(ProPlan.lifetime);

  final ProPlan plan;
  final DateTime? expiry;
  final DateTime? verifiedAt;

  /// Offline grace: a cached subscription is trusted until expiry + this.
  static const grace = Duration(days: 3);

  /// A subscription without a known expiry is trusted this long after the
  /// last refresh that confirmed it (every launch and resume refreshes;
  /// a refresh that fails, e.g. offline, leaves the cache alone).
  static const recheckWindow = Duration(days: 3);

  /// Until when a yearly grant is trusted; null for none/lifetime.
  DateTime? get trustedUntil => plan != ProPlan.yearly
      ? null
      : expiry?.add(grace) ?? verifiedAt?.add(recheckWindow);

  bool activeAt(DateTime now) => switch (plan) {
        ProPlan.none => false,
        ProPlan.lifetime => true,
        ProPlan.yearly => trustedUntil != null && now.isBefore(trustedUntil!),
      };

  /// "Oct 14, 2027" for a yearly grant with a known expiry, else null
  /// (Google Play doesn't tell the app; never show "until null").
  String? get untilLabel {
    final e = expiry;
    return plan == ProPlan.yearly && e != null
        ? DateFormat.yMMMd().format(e)
        : null;
  }

  Map<String, Object?> toJson() => {
        'plan': plan.name,
        if (expiry != null) 'expiryMs': expiry!.millisecondsSinceEpoch,
        if (verifiedAt != null)
          'verifiedMs': verifiedAt!.millisecondsSinceEpoch,
      };

  static ProGrant fromJson(Map<String, Object?> json) {
    final plan = ProPlan.values.asNameMap()[json['plan']] ?? ProPlan.none;
    final ms = json['expiryMs'];
    final vms = json['verifiedMs'];
    if (plan == ProPlan.yearly && (ms is int || vms is int)) {
      return ProGrant(
        plan,
        ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
        vms is int ? DateTime.fromMillisecondsSinceEpoch(vms) : null,
      );
    }
    return plan == ProPlan.lifetime ? lifetime : none;
  }

  @override
  bool operator ==(Object other) =>
      other is ProGrant &&
      other.plan == plan &&
      other.expiry == expiry &&
      other.verifiedAt == verifiedAt;

  @override
  int get hashCode => Object.hash(plan, expiry, verifiedAt);
}

/// A plan for sale, free of any StoreKit types so the UI never imports them.
@immutable
class ProOffer {
  const ProOffer({
    required this.id,
    required this.displayPrice,
    required this.periodLabel,
    this.trialLabel,
  });

  final String id;

  /// Localized price, e.g. "$6.99".
  final String displayPrice;

  /// e.g. "year".
  final String periodLabel;

  /// Free trial the user is eligible for, e.g. "1 week free"; null if none.
  final String? trialLabel;
}

/// Snapshot published on [ProEntitlement.statusStream].
@immutable
class ProStatus {
  const ProStatus({
    this.entitlement = ProGrant.none,
    this.isPro = false,
    this.busy = false,
    this.error,
    this.yearly,
    this.productsLoaded = false,
    this.store = ProStoreKind.appStore,
  });

  final ProGrant entitlement;
  final bool isPro;

  /// A purchase or restore is in flight.
  final bool busy;

  /// User-friendly message for the last failure, if any.
  final String? error;

  /// The yearly plan, once products have loaded.
  final ProOffer? yearly;
  final bool productsLoaded;

  /// Which store sells Pro here, so the paywall can name it.
  final ProStoreKind store;
}

/// The slice of StoreKit that [ProEntitlement] needs, so tests can fake it.
abstract class ProStoreGateway {
  Stream<List<PurchaseDetails>> get purchaseStream;
  Future<ProductDetailsResponse> queryProducts(Set<String> ids);

  /// Opens the store's purchase sheet; the result arrives on
  /// [purchaseStream]. Throws [ProPurchaseNotStarted] when the store refused
  /// to open it (then no result follows).
  Future<void> buy(ProductDetails product);

  /// Re-emits every *current* entitlement on [purchaseStream] (StoreKit 2:
  /// `Transaction.currentEntitlements`, which excludes expired and revoked
  /// ones) and completes once they have all been sent. No sign-in prompt.
  Future<void> refreshEntitlements();

  /// User-initiated restore: asks the App Store to sync (may prompt for
  /// the Apple ID); call [refreshEntitlements] afterwards.
  Future<void> syncWithAppStore();
  Future<void> complete(PurchaseDetails purchase);
  Future<bool> isIntroOfferEligible(ProductDetails product);

  /// The store for this platform: App Store on iOS (and macOS), Google Play
  /// on Android, none elsewhere.
  static ProStoreGateway forPlatform([TargetPlatform? platform]) {
    if (kIsWeb) return NoStoreGateway();
    return switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => AppStoreGateway(),
      TargetPlatform.android => PlayStoreGateway(),
      _ => NoStoreGateway(),
    };
  }
}

/// No store on this platform: nothing for sale, refresh keeps the cache.
class NoStoreGateway implements ProStoreGateway {
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();

  @override
  Future<ProductDetailsResponse> queryProducts(Set<String> ids) async =>
      ProductDetailsResponse(productDetails: const [], notFoundIDs: [...ids]);

  @override
  Future<void> buy(ProductDetails product) async =>
      throw const ProStoreUnavailable('no store on this platform');

  @override
  Future<void> refreshEntitlements() async =>
      throw const ProStoreUnavailable('no store on this platform');

  @override
  Future<void> syncWithAppStore() async {}

  @override
  Future<void> complete(PurchaseDetails purchase) async {}

  @override
  Future<bool> isIntroOfferEligible(ProductDetails product) async => false;
}

class AppStoreGateway implements ProStoreGateway {
  AppStoreGateway([this._override]);
  final InAppPurchase? _override;

  // Lazy so constructing a ProEntitlement never touches the platform plugin.
  InAppPurchase get _iap => _override ?? InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  @override
  Future<ProductDetailsResponse> queryProducts(Set<String> ids) =>
      _iap.queryProductDetails(ids);

  // in_app_purchase has no separate subscription call; buyNonConsumable is
  // right for auto-renewable subscriptions too.
  @override
  Future<void> buy(ProductDetails product) => _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product));

  @override
  Future<void> refreshEntitlements() => _iap.restorePurchases();

  @override
  Future<void> syncWithAppStore() =>
      _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>().sync();

  @override
  Future<void> complete(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);

  @override
  Future<bool> isIntroOfferEligible(ProductDetails product) async {
    if (product is! AppStoreProduct2Details) return false;
    return SK2Product.isIntroductoryOfferEligible(product.id);
  }
}

/// The free trial the store advertises for [product], e.g. "1 week free",
/// or null when it has none (StoreKit 2 or Google Play details only).
String? introTrialLabel(ProductDetails product) {
  if (product is! AppStoreProduct2Details) return playTrialLabel(product);
  final offers = product.sk2Product.subscription?.promotionalOffers ?? const [];
  for (final o in offers) {
    if (o.type == SK2SubscriptionOfferType.introductory &&
        o.paymentMode == SK2SubscriptionOfferPaymentMode.freeTrial) {
      final n = o.period.value * o.periodCount;
      final unit = switch (o.period.unit) {
        SK2SubscriptionPeriodUnit.day => 'day',
        SK2SubscriptionPeriodUnit.week => 'week',
        SK2SubscriptionPeriodUnit.month => 'month',
        SK2SubscriptionPeriodUnit.year => 'year',
      };
      return '$n $unit${n == 1 ? '' : 's'} free';
    }
  }
  return null;
}

/// Pro entitlement and purchases.
///
/// Entitlement approach: StoreKit 2 verifies every transaction on device
/// (unverified ones are dropped natively), so there is no server. Truth is
/// `Transaction.currentEntitlements`, which in_app_purchase_storekit exposes
/// only via `restorePurchases()`: it emits each current (unexpired,
/// unrevoked) transaction, with its expiration date, on `purchaseStream` as
/// `restored`. [refresh] runs that at start and on every app resume and
/// REPLACES the entitlement with the result, so expiry and refunds are
/// noticed. Live `Transaction.updates` (purchases, renewals) arrive on the
/// same stream and are merged in. The result is cached in SharedPreferences;
/// offline, a cached subscription is trusted until expiry + 3 days and a
/// lifetime purchase never expires. If a refresh itself fails (offline)
/// the cache is kept untouched.
///
/// Google Play ([PlayStoreGateway]) works the same way, except that a
/// subscription carries no expiry on device: a refresh that lists it
/// grants [ProGrant.verified] (trusted for [ProGrant.recheckWindow] after
/// that refresh), a refresh that doesn't clears it. Every PURCHASED Play
/// purchase is acknowledged via `complete` (restored ones too), since
/// Play refunds unacknowledged purchases after three days.
class ProEntitlement {
  ProEntitlement({
    required SharedPreferences prefs,
    ProStoreGateway? store,
    ProProductIds? productIds,
    DateTime Function()? clock,
    bool? proOverride,
  })  : _prefs = prefs,
        _store = store ?? ProStoreGateway.forPlatform(),
        _now = clock ?? DateTime.now,
        _override = proOverride ?? (kDebugMode && _proOverrideDefine) {
    _ids = productIds ?? ProProductIds.of(_store);
    _entitlement = _readCache();
    _status = _buildStatus();
  }

  static const cacheKey = 'pro_entitlement_v1';

  final SharedPreferences _prefs;
  final ProStoreGateway _store;
  final DateTime Function() _now;
  final bool _override;
  late final ProProductIds _ids;

  final _controller = StreamController<ProStatus>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;
  late ProGrant _entitlement;
  late ProStatus _status;

  // Entitlements collected during a refresh (null when none is running).
  List<ProGrant>? _collecting;
  String? _error;
  bool _busy = false;
  ProductDetails? _yearly;
  bool _trialEligible = false;
  bool _productsLoaded = false;

  ProStatus get status => _status;
  bool get isPro => _status.isPro;

  /// Current status, then every change.
  Stream<ProStatus> get statusStream async* {
    yield _status;
    yield* _controller.stream;
  }

  bool canCreate(ProFeature feature) => isPro;

  /// Lapsed users keep seeing what they made.
  bool canView(ProFeature feature) => true;

  /// Start listening to purchases for the app's lifetime (must happen at
  /// launch so interrupted transactions and renewals are finished).
  Future<void> start() async {
    _sub ??= _store.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => _setError(friendlyError(e)),
    );
    await refresh();
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }

  /// Re-reads current entitlements from the store (see class docs).
  /// Returns false when the store couldn't be asked (cache kept).
  ///
  /// Overlapping calls (launch + resume, a resume during Restore) share one
  /// run: two runs would share [_collecting], and the first to finish could
  /// replace the entitlement with the second's still-empty list.
  Future<bool> refresh() {
    if (_override) return Future.value(true);
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<bool>? _refreshing;

  Future<bool> _refresh() async {
    _lastRefreshError = null;
    _collecting = [];
    try {
      await _store.refreshEntitlements();
      // Let queued stream events from the native side drain (microtasks
      // only, so this also works under FakeAsync in widget tests).
      for (var i = 0; i < 5; i++) {
        await Future<void>.value();
      }
      _setEntitlement(_best(_collecting!), clearError: true);
      return true;
    } catch (e) {
      // Offline, store hiccup or no billing on this device: keep the
      // cached entitlement.
      debugPrint('Pro refresh failed: $e');
      _lastRefreshError = e;
      return false;
    } finally {
      _collecting = null;
    }
  }

  Object? _lastRefreshError;

  Future<void> loadProducts() async {
    try {
      final r = await _store.queryProducts(_ids.forSale);
      _yearly = _find(r.productDetails, _ids.yearly);
      _trialEligible =
          _yearly != null && await _store.isIntroOfferEligible(_yearly!);
      _productsLoaded = true;
      _error = r.error?.code == 'billing_unavailable'
          ? _unavailableMessage
          : r.error != null || (_yearly == null)
              ? 'Purchases are not available right now. Please try again '
                  'later.'
              : null;
    } catch (e) {
      _productsLoaded = true;
      _error = friendlyError(e, _ids.storeName);
    }
    _publish();
  }

  /// Buy the yearly plan (the only plan offered).
  Future<void> buyYearly() async {
    final y = _status.yearly;
    if (y == null) return;
    await buy(y);
  }

  Future<void> buy(ProOffer offer) async {
    final product = _yearly;
    if (product == null || product.id != offer.id) return;
    _busy = true;
    _error = null;
    _publish();
    try {
      // The result arrives on purchaseStream; _onPurchases clears busy.
      await _store.buy(product);
    } on ProPurchaseNotStarted {
      // Play refused to open its purchase sheet (most often: the account
      // already owns Pro but no refresh has seen it yet). Ask Play what the
      // account owns; only complain if that doesn't unlock Pro.
      await _refreshAfterRefusal();
      _busy = false;
      _error ??= _status.isPro
          ? null
          : 'Could not start the purchase with ${_ids.storeName}. Please '
              'try again.';
      _publish();
    } catch (e) {
      _busy = false;
      _error = friendlyError(e, _ids.storeName);
      _publish();
    }
  }

  /// Restore Purchases button.
  Future<void> restore() async {
    _busy = true;
    _error = null;
    _publish();
    try {
      await _store.syncWithAppStore();
      final ok = await refresh();
      final failure = _lastRefreshError;
      if (!ok && failure != null && !_status.isPro) {
        _error = failure is ProStoreUnavailable
            ? _unavailableMessage
            : friendlyError(failure, _ids.storeName);
      } else if (!_status.isPro) {
        _error = _ids.store == ProStoreKind.googlePlay
            ? 'No previous purchases were found for this Google account.'
            : 'No previous purchases were found for this Apple ID.';
      }
    } on ProStoreUnavailable {
      _error = _unavailableMessage;
    } catch (e) {
      _error = friendlyError(e, _ids.storeName);
    }
    _busy = false;
    _publish();
  }

  String get _unavailableMessage => _ids.store == ProStoreKind.googlePlay
      ? 'Google Play purchases are not available on this device. Install '
          'the app from Google Play and sign in to your Google account.'
      : 'Purchases are not available right now. Please try again later.';

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    final granted = <ProGrant>[];
    var alreadyOwned = false;
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final e = entitlementOf(p, _now(), _ids);
          if (e != null) {
            granted.add(e);
          } else if (_isPending(p)) {
            _error = _pendingMessage;
          }
          _busy = false;
        case PurchaseStatus.pending:
          // The store's sheet has closed; the payment finishes later
          // (Play "slow" payment methods, Ask to Buy).
          _error = _pendingMessage;
          _busy = false;
        case PurchaseStatus.canceled:
          _busy = false;
        case PurchaseStatus.error:
          _busy = false;
          if (isAlreadyOwned(p.error)) {
            // Play: "you already own this" — the account has Pro that no
            // refresh has seen yet (bought on another phone, promo code).
            alreadyOwned = true;
          } else {
            _error = friendlyError(p.error, _ids.storeName);
          }
      }
    }
    // Record before completing: completing is a platform round trip (Play
    // acknowledge), and a refresh waiting on [_collecting] must not miss
    // these grants meanwhile.
    if (_collecting != null) {
      _collecting!.addAll(granted);
      _publish();
    } else if (granted.isNotEmpty) {
      _setEntitlement(_best([_entitlement, ...granted]), clearError: true);
    } else {
      _publish();
    }
    for (final p in purchases) {
      // Required: unfinished StoreKit transactions are redelivered forever,
      // and Play refunds a purchase not acknowledged within three days.
      // Restored purchases are completed too (a Play purchase made while
      // the app was closed, or redeemed with a promo code, first shows up
      // in a restore).
      if (p.pendingCompletePurchase) {
        try {
          await _store.complete(p);
        } catch (e) {
          debugPrint('completePurchase failed: $e');
        }
      }
    }
    if (alreadyOwned) {
      await _refreshAfterRefusal();
      if (!_status.isPro) {
        _error = '${_ids.storeName} says this account already has Pro. Tap '
            'Restore Purchases.';
        _publish();
      }
    }
  }

  /// Refresh after the store refused a purchase; publishes the result.
  Future<void> _refreshAfterRefusal() async {
    await refresh();
    _publish();
  }

  /// The store says the account already owns the product (Play
  /// `ITEM_ALREADY_OWNED`, reported as "BillingResponse.itemAlreadyOwned").
  @visibleForTesting
  static bool isAlreadyOwned(Object? e) {
    final text = e is IAPError ? '${e.code} ${e.message} ${e.details}' : '$e';
    return text.toLowerCase().contains('itemalreadyowned');
  }

  String get _pendingMessage => _ids.store == ProStoreKind.googlePlay
      ? 'Payment is pending. Pro unlocks once Google Play confirms it.'
      : 'Waiting for approval (Ask to Buy). Pro unlocks once it is approved.';

  static bool _isPending(PurchaseDetails p) =>
      p is GooglePlayPurchaseDetails &&
      p.billingClientPurchase.purchaseState == PurchaseStateWrapper.pending;

  /// The entitlement a verified purchase grants, or null.
  @visibleForTesting
  static ProGrant? entitlementOf(PurchaseDetails p, DateTime now,
      [ProProductIds ids = ProProductIds.appStore]) {
    if (p is GooglePlayPurchaseDetails) return playGrantOf(p, ids, now);
    if (p.productID == ids.lifetime) return ProGrant.lifetime;
    if (p.productID == ids.yearly) {
      final ms =
          int.tryParse(p is SK2PurchaseDetails ? (p.expirationDate ?? '') : '');
      if (ms == null) return null;
      final expiry = DateTime.fromMillisecondsSinceEpoch(ms);
      return expiry.isAfter(now) ? ProGrant(ProPlan.yearly, expiry) : null;
    }
    return null;
  }

  static ProGrant _best(Iterable<ProGrant> all) {
    var best = ProGrant.none;
    for (final e in all) {
      if (e.plan == ProPlan.lifetime) return e;
      final until = e.trustedUntil;
      if (until == null) continue;
      if (best.plan == ProPlan.none || until.isAfter(best.trustedUntil!)) {
        best = e;
      }
    }
    return best;
  }

  ProGrant _readCache() {
    try {
      final raw = _prefs.getString(cacheKey);
      if (raw == null) return ProGrant.none;
      return ProGrant.fromJson(
          (jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      return ProGrant.none;
    }
  }

  void _setEntitlement(ProGrant e, {bool clearError = false}) {
    _entitlement = e;
    if (clearError) _error = null;
    if (e.plan == ProPlan.none) {
      _prefs.remove(cacheKey);
    } else {
      _prefs.setString(cacheKey, jsonEncode(e.toJson()));
    }
    _publish();
  }

  ProStatus _buildStatus() => ProStatus(
        entitlement: _entitlement,
        isPro: _override || _entitlement.activeAt(_now()),
        busy: _busy,
        error: _error,
        yearly: _offerOf(_yearly, _trialEligible),
        productsLoaded: _productsLoaded,
        store: _ids.store,
      );

  static ProOffer? _offerOf(ProductDetails? p, bool trialEligible) {
    if (p == null) return null;
    return ProOffer(
      id: p.id,
      displayPrice: playDisplayPrice(p),
      periodLabel: 'year',
      trialLabel: trialEligible ? introTrialLabel(p) : null,
    );
  }

  void _publish() {
    _status = _buildStatus();
    if (!_controller.isClosed) _controller.add(_status);
  }

  void _setError(String message) {
    _error = message;
    _busy = false;
    _publish();
  }

  static ProductDetails? _find(List<ProductDetails> l, String id) {
    for (final p in l) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Plain-language message for a purchase failure. [store] names the
  /// store ("the App Store" or "Google Play").
  static String friendlyError(Object? e, [String store = 'the App Store']) {
    final text = e is PlatformException
        ? '${e.code} ${e.message}'
        : e is IAPError
            ? '${e.code} ${e.message}'
            : '$e';
    final t = text.toLowerCase();
    if (t.contains('network') ||
        t.contains('offline') ||
        t.contains('connect') ||
        // Play: BillingResponse.serviceUnavailable / serviceTimeout.
        t.contains('serviceunavailable') ||
        t.contains('servicetimeout')) {
      return 'Could not reach $store. Check your connection and try again.';
    }
    if (t.contains('billing_unavailable') ||
        t.contains('billingunavailable') ||
        t.contains('itemunavailable')) {
      return 'Purchases through $store are not available on this device '
          'right now.';
    }
    if (t.contains('itemalreadyowned')) {
      return 'You already have Pro. Tap Restore Purchases.';
    }
    if (t.contains('not_allowed') ||
        t.contains('not allowed') ||
        t.contains('restricted')) {
      return 'Purchases are turned off on this device (Screen Time or '
          'parental controls).';
    }
    if (t.contains('unverified') || t.contains('verif')) {
      return '${store[0].toUpperCase()}${store.substring(1)} could not verify '
          'this purchase. Please try again.';
    }
    return 'Something went wrong with $store. Please try again.';
  }
}
