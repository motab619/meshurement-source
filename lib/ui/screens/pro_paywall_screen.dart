// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';
import '../../services/live_activity_service.dart';
import '../../services/pro_entitlement.dart';
import '../../utils/constants.dart';
import '../theme/app_theme.dart';
import '../../utils/app_info.dart';
import '../layout/window_class.dart';

const privacyPolicyUrl = 'https://${AppInfo.website}/privacy';
const termsOfUseUrl =
    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
const manageSubscriptionsUrl = 'https://apps.apple.com/account/subscriptions';

/// Google Play equivalents (Android). The manage link names the
/// subscription and app, so Play opens that subscription's own page.
const playTermsUrl = 'https://play.google.com/about/play-terms/';
const playManageSubscriptionsUrl =
    'https://play.google.com/store/account/subscriptions'
    '?sku=${ProProductIds.playYearly}'
    '&package=${ProProductIds.playPackageName}';

bool _onPlay(ProStatus s) => s.store == ProStoreKind.googlePlay;

/// Opens the Pro screen. [feature] is the gated action that triggered it
/// (null from About). Resolves to true if the user is Pro when it closes.
Future<bool> showProPaywall(BuildContext context, {ProFeature? feature}) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => ProPaywallScreen(feature: feature)),
  );
  if (!context.mounted) return false;
  return ProviderScope.containerOf(context).read(proEntitlementProvider).isPro;
}

/// Wraps a gated "create" action. [builder] gets whether the feature is
/// unlocked and an [onTap]-ready callback that runs [onUnlocked] when Pro,
/// or shows the paywall (then runs it if the purchase went through).
///
/// ```dart
/// ProGate(
///   feature: ProFeature.coverageReport,
///   onUnlocked: _createReport,
///   builder: (context, unlocked, activate) => FilledButton(
///     onPressed: activate,
///     child: Text(unlocked ? 'Create report' : 'Create report (Pro)'),
///   ),
/// )
/// ```
class ProGate extends ConsumerWidget {
  const ProGate({
    super.key,
    required this.feature,
    required this.onUnlocked,
    required this.builder,
  });

  final ProFeature feature;
  final VoidCallback onUnlocked;
  final Widget Function(
      BuildContext context, bool unlocked, VoidCallback activate) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(proEntitlementProvider);
    final unlocked = ref.watch(isProProvider).value ?? service.isPro;
    return builder(context, unlocked, () async {
      if (service.canCreate(feature) ||
          await showProPaywall(context, feature: feature)) {
        onUnlocked();
      }
    });
  }
}

class ProPaywallScreen extends ConsumerStatefulWidget {
  const ProPaywallScreen({super.key, this.feature});

  final ProFeature? feature;

  @override
  ConsumerState<ProPaywallScreen> createState() => _ProPaywallScreenState();
}

class _ProPaywallScreenState extends ConsumerState<ProPaywallScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(proEntitlementProvider).loadProducts());
  }

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(proEntitlementProvider);
    final status = ref.watch(proStatusProvider).value ?? service.status;

    return Scaffold(
      appBar: AppBar(title: const Text(AppInfo.proName)),
      body: WideColumn(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (status.isPro)
              _ActiveCard(
                  status: status,
                  onManage: () => _open(_onPlay(status)
                      ? playManageSubscriptionsUrl
                      : manageSubscriptionsUrl))
            else ...[
              Text(AppInfo.proName,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '${AppInfo.displayName} stays free: mapping, pings, charts, coverage '
                'layers and export all work without Pro. Pro adds the '
                'features listed below.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (widget.feature != null) ...[
                const SizedBox(height: 8),
                Text('${widget.feature!.title} is a Pro feature.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ],
            const SizedBox(height: 16),
            const _FeatureList(),
            const SizedBox(height: 8),
            if (!status.isPro) ...[
              if (status.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(status.error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              if (!status.productsLoaded)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (status.yearly != null)
                  _PlanCard(
                    key: const Key('plan_yearly'),
                    title: 'Yearly · ${status.yearly!.displayPrice}/'
                        '${status.yearly!.periodLabel}',
                    headline: _yearlyHeadline(status),
                    caption: 'Auto-renews every year. Cancel anytime.',
                    busy: status.busy,
                    onTap: service.buyYearly,
                  ),
              ],
              Center(
                child: TextButton(
                  onPressed: status.busy ? null : service.restore,
                  child: const Text('Restore Purchases'),
                ),
              ),
              const SizedBox(height: 8),
              _Disclosure(yearly: status.yearly, play: _onPlay(status)),
            ] else
              const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _open(privacyPolicyUrl),
                  child: const Text('Privacy Policy'),
                ),
                TextButton(
                  onPressed: () =>
                      _open(_onPlay(status) ? playTermsUrl : termsOfUseUrl),
                  child: const Text('Terms of Use'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _yearlyHeadline(ProStatus s) {
    final y = s.yearly!;
    final price = '${y.displayPrice}/${y.periodLabel}';
    final trial = y.trialLabel;
    return trial == null ? price : '$trial, then $price';
  }
}

/// What Pro includes today, in display order. Only features that work in
/// this build are listed: the paywall describes what the price buys now,
/// never planned work (App Review 3.1.2). The other [ProFeature] values
/// (placement advisor, PDF report, offline maps, iCloud) stay off it until
/// they ship.
List<ProFeature> get proIncludedFeatures => [
      ProFeature.guidedTests,
      ProFeature.rigProfiles,
      ProFeature.rigComparison,
      // iPhone only (no Live Activity on iPad or Android).
      if (LiveActivityService.deviceSupported) ProFeature.liveActivity,
      ProFeature.fasterIntervals,
      ProFeature.remoteBaseChange,
      ProFeature.reportStyles,
      // Only once the backend URL is configured.
      if (AppConstants.aiAnalysisUrl != null) ProFeature.aiAnalysis,
    ];

class _FeatureList extends StatelessWidget {
  const _FeatureList();

  static const _blurbs = {
    ProFeature.guidedTests: 'Compare 3 or 4 antennas, nodes or settings in '
        'one guided test (2 are free).',
    ProFeature.rigProfiles:
        'Save your nodes and antennas as hardware profiles.',
    ProFeature.rigComparison: 'Compare nodes and antennas side by side.',
    ProFeature.liveActivity: 'Follow a recording on the lock screen and '
        'Dynamic Island: signal, link and range at a glance.',
    ProFeature.fasterIntervals: 'Ping and beacon faster than the airtime '
        'guideline, for short, dense tests on your private channel.',
    ProFeature.remoteBaseChange: 'Change the base\'s range setting or TX '
        'power from where you stand, with an automatic roll back if it goes '
        'quiet (Meshtastic).',
    ProFeature.reportStyles: 'Share Field Reports in the Pop, Bridge and '
        'Mission styles (Night and Basic are free).',
    ProFeature.aiAnalysis:
        'Plain-English read of a comparison: what held up, what didn\'t, '
            'what to try next.',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Included with Pro',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final f in proIncludedFeatures)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.check_circle_outline),
            title: Text(f.title),
            subtitle: Text(_blurbs[f]!),
          ),
        const ListTile(
          key: ValueKey('pro-support-indie'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.favorite_border),
          title: Text('Support an independent developer'),
          subtitle: Text('${AppInfo.displayName} is made by one person, with '
              'no ads and no tracking. Pro is what keeps it going.'),
        ),
        Text(
          'If Pro lapses, everything you made stays on your device and stays '
          'viewable and exportable. Only creating new Pro items needs Pro.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    super.key,
    required this.title,
    required this.headline,
    required this.caption,
    required this.busy,
    required this.onTap,
  });

  final String title;
  final String headline;
  final String caption;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('$headline\n$caption'),
        isThreeLine: true,
        trailing: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_right),
        onTap: busy ? null : onTap,
      ),
    );
  }
}

/// Auto-renewable subscription disclosure (Apple-required; the Google Play
/// version names the Play Store instead of the Apple ID).
class _Disclosure extends StatelessWidget {
  const _Disclosure({required this.yearly, this.play = false});
  final ProOffer? yearly;
  final bool play;

  @override
  Widget build(BuildContext context) {
    final price = yearly?.displayPrice ?? '\$6.99';
    if (play) {
      return Text(
        '${AppInfo.proName} (yearly): 1 year subscription, $price per year. '
        'Payment is charged to your Google Play account when you confirm '
        'the purchase or, with a free trial, when the trial ends unless you '
        'cancel before then. The subscription renews automatically every '
        'year until you cancel it. Manage or cancel in the Google Play Store '
        'app under Payments & subscriptions > Subscriptions.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Text(
      '${AppInfo.proName} (yearly): 1 year subscription, $price per year. '
      'Payment is charged to your Apple ID account at confirmation of '
      'purchase (after any free trial ends). The subscription renews '
      'automatically unless it is cancelled at least 24 hours before the end '
      'of the current period. Your account is charged for renewal within 24 '
      'hours before the end of the period. Manage or cancel in Settings > '
      'Apple ID > Subscriptions. Any unused part of a free trial is '
      'forfeited when you purchase a subscription.',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.status, required this.onManage});
  final ProStatus status;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final e = status.entitlement;
    final detail = switch (e.plan) {
      ProPlan.lifetime =>
        'Lifetime plan. Thank you for supporting ${AppInfo.displayName}!',
      // "Active until", not "renews": the store plugin gives us the expiry
      // but not whether auto-renew is still on, so "renews" would be wrong
      // after a cancel.
      // Google Play doesn't give the app an expiry date.
      ProPlan.yearly => e.untilLabel == null
          ? 'Yearly plan, active. '
              'Thank you for supporting ${AppInfo.displayName}!'
          : 'Yearly plan, active until ${e.untilLabel}. '
              'Thank you for supporting ${AppInfo.displayName}!',
      ProPlan.none => 'Pro is enabled for this build.',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.verified, color: context.status.ok),
              const SizedBox(width: 8),
              Text('You have Pro',
                  style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            Text(detail),
            if (e.plan == ProPlan.yearly)
              TextButton(
                onPressed: onManage,
                child: const Text('Manage subscription'),
              ),
          ],
        ),
      ),
    );
  }
}
