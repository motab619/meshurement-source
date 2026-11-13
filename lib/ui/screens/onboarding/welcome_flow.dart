// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/database/app_database.dart';
import '../../../providers.dart';
import '../../../services/base_node.dart';
import '../../../data/radio/ble/radio_scanner.dart' show RadioAdapterState;
import '../../../services/gps_service.dart';
import '../../../services/privacy_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ai_analysis_card.dart' show showAiConsentSheet;
import '../pro_paywall_screen.dart' show privacyPolicyUrl;
import '../radio_setup_screen.dart';
import '../../../utils/app_info.dart';
import '../../../utils/platform_text.dart';
import '../../widgets/coverage_diagram.dart';
import '../../widgets/wordmark.dart';
import '../../layout/window_class.dart';

/// Set once the welcome flow has been dismissed (Skip, Done, Open Radio
/// Setup or back), or when an existing install is recognised.
const onboardingSeenKey = 'onboarding_seen_v1';

Future<void> markOnboardingSeen(SharedPreferences prefs) =>
    prefs.setBool(onboardingSeenKey, true);

/// The short trademark line at the foot of page 01; the full notice
/// (`trademarkNotice`) stays on About.
const welcomeTrademarkLine = 'Meshtastic® is a trademark of Meshtastic LLC. '
    '${AppInfo.displayName} is not affiliated.';

/// Paragraph text on the welcome pages in the platform's proportional
/// face (SF on iOS) instead of the theme's B612, which is heavy for four
/// pages of prose (walkthrough 2026-11-08). One point up, since SF sets
/// narrower than B612. Kickers, step numbers and labels keep the theme.
TextStyle? _prose(ThemeData theme, TextStyle? base) {
  if (base == null) return null;
  final family = Typography.material2021(platform: theme.platform)
      .black
      .bodyMedium
      ?.fontFamily;
  return base.copyWith(
    fontFamily: family,
    fontSize: (base.fontSize ?? 14) + 1,
  );
}

/// Whether to greet this install with the welcome flow.
///
/// An install that already has maps or sessions, or a base recorded by
/// Radio Setup, was set up before the flow existed: it counts as seen (the
/// flag is set) so an update doesn't greet it.
Future<bool> shouldShowWelcome(SharedPreferences prefs, AppDatabase db) async {
  if (prefs.getBool(onboardingSeenKey) ?? false) return false;
  var existing = prefs.containsKey(baseNodePrefKey);
  if (!existing) {
    existing = (await db.getAllCoverageMaps()).isNotEmpty ||
        (await (db.select(db.sessions)..limit(1)).get()).isNotEmpty;
  }
  if (existing) {
    await markOnboardingSeen(prefs);
    // Set up before the checklist existed too: don't show it ticked off.
    await prefs.setBool(onboardingChecklistHiddenKey, true);
    return false;
  }
  return true;
}

/// Pushes the welcome flow as a full-screen route.
Future<void> showWelcomeFlow(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const WelcomeFlow(),
    ));

/// First-launch welcome: what the app does, the privacy switches (the same
/// state as Settings → Privacy), then how to set up the radios, ending on
/// the Open Radio Setup button. Shown once, skippable at every step;
/// About → Show welcome again re-opens it.
class WelcomeFlow extends ConsumerStatefulWidget {
  const WelcomeFlow({super.key});

  @override
  ConsumerState<WelcomeFlow> createState() => _WelcomeFlowState();
}

class _WelcomeFlowState extends ConsumerState<WelcomeFlow> {
  static const _pageCount = 4;
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _markSeen() =>
      markOnboardingSeen(ref.read(sharedPreferencesProvider));

  /// Skip / Done: close, landing on the Coverage tab where the Get
  /// started checklist takes over (unless it has been dismissed).
  Future<void> _finish() async {
    await _markSeen();
    if (!mounted) return;
    if (!ref.read(checklistHiddenProvider)) {
      ref.read(mainTabProvider.notifier).state = 1;
    }
    Navigator.of(context).pop();
  }

  Future<void> _openRadioSetup() async {
    await _markSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RadioSetupScreen()),
    );
  }

  void _next() {
    if (_page >= _pageCount - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = theme.readout.label.copyWith(
      fontFamily: ReadoutStyles.monoFamily,
      fontSize: 12,
      letterSpacing: 1.0,
    );
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _markSeen();
      },
      child: Scaffold(
        body: WideColumn(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                  child: Row(
                    children: [
                      Text(
                        '${(_page + 1).toString().padLeft(2, '0')}'
                        '/${_pageCount.toString().padLeft(2, '0')}',
                        style: mono.copyWith(color: scheme.primary),
                      ),
                      const Spacer(),
                      TextButton(onPressed: _finish, child: const Text('Skip')),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (i) => setState(() => _page = i),
                    children: [
                      const _WelcomePage(),
                      const _PrivacyPage(),
                      const _PermissionsPage(),
                      _RadiosPage(onOpenRadioSetup: _openRadioSetup),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      for (var i = 0; i < _pageCount; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 6),
                          width: i == _page ? 20 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? scheme.primary
                                : scheme.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _next,
                        child: Text(_page < _pageCount - 1 ? 'Next' : 'Done'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared page frame: an orange-ringed emblem, a mono kicker, a title and
/// the page's content, scrollable for small phones and large text (with a
/// scrollbar showing whenever there is more below).
class _Page extends StatefulWidget {
  const _Page({
    required this.icon,
    required this.kicker,
    required this.title,
    required this.children,
    this.header,
    this.bottomPadding = 16,
  });

  /// Shown in place of the icon box (the wordmark on the first page).
  final Widget? header;
  final IconData icon;
  final String kicker;
  final String title;
  final List<Widget> children;

  /// Space after the last item, so it never ends flush against the
  /// Next / Done bar.
  final double bottomPadding;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(20, 20, 20, widget.bottomPadding),
        children: [
          if (widget.header != null)
            Align(alignment: Alignment.centerLeft, child: widget.header)
          else
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.35),
                  border: Border.all(color: scheme.primary, width: 2),
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.25),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Icon(widget.icon, size: 28, color: scheme.primary),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            widget.kicker,
            style: theme.readout.label.copyWith(
              fontFamily: ReadoutStyles.monoFamily,
              fontSize: 12,
              letterSpacing: 1.0,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(widget.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 14),
          ...widget.children,
        ],
      ),
    );
  }
}

/// A numbered line ("01  text"), mono number in orange.
class _Step extends StatelessWidget {
  const _Step(this.number, this.text);
  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              number.toString().padLeft(2, '0'),
              style: theme.readout.label.copyWith(
                fontFamily: ReadoutStyles.monoFamily,
                fontSize: 14,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: Text(text, style: _prose(theme, theme.textTheme.bodyMedium)),
          ),
        ],
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Page(
      icon: Icons.radar,
      header: const Wordmark(height: 44),
      kicker: 'WELCOME',
      title: 'See how far your mesh really reaches',
      children: [
        Text(
          'Leave a base node in one place and carry a second node (the '
          'mobile) on a drive or a walk. ${AppInfo.displayName} logs what the '
          'mobile hears, with GPS, and draws a coverage map from real '
          'readings.',
          style: _prose(theme, theme.textTheme.bodyLarge),
        ),
        const SizedBox(height: 16),
        const _Step(1, 'Map real coverage, not a prediction.'),
        const _Step(
            2,
            'Compare antennas, range settings and nodes on the '
            'same route.'),
        const _Step(
            3,
            'You need two LoRa mesh nodes, like a Heltec V3 or a '
            'T1000-E running Meshtastic firmware or MeshCore companion '
            'firmware, connected over Bluetooth.'),
        const SizedBox(height: 20),
        Text(
          welcomeTrademarkLine,
          key: const ValueKey('welcome-trademark'),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _RadiosPage extends ConsumerWidget {
  const _RadiosPage({required this.onOpenRadioSetup});
  final VoidCallback onOpenRadioSetup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return _Page(
      icon: Icons.router,
      kicker: 'SET UP YOUR NODES',
      title: 'Two nodes, one private channel',
      children: [
        const CoverageDiagram(height: 120),
        const SizedBox(height: 16),
        const _Step(
            1,
            'Connect to one of your nodes over Bluetooth, from the Get '
            'started card or Connect a node on the Live tab.'),
        const _Step(
            2,
            'Run Node Setup. It puts both nodes on a private '
            'test channel (never the public one) and asks which is the base '
            'and which is the mobile.'),
        const _Step(
            3,
            'Leave the base where it is, take the mobile with you '
            'and start a session.'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: onOpenRadioSetup,
            icon: const Icon(Icons.router),
            label: const Text('Open Node Setup'),
          ),
        ),
        const SizedBox(height: 12),
        Text('Node Setup is always in Settings.',
            style: _prose(
                theme,
                theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
      ],
    );
  }
}

/// Height of the Next / Done bar under the pages (8 + 44 + 16): the
/// long pages leave at least this much space after their last item.
const _buttonBarHeight = 68.0;

/// What iOS will ask for, explained and asked here rather than when the
/// feature first needs it (Andy, first run 2026-11-07: "permissions should
/// be explained and asked for up front"). One compact row each (icon,
/// title and Allow on one line, the reason in a line under it; a tick once
/// granted, a Settings hint when refused), so all three Allow buttons fit
/// on an iPhone screen without scrolling (walkthrough 2026-11-08: the
/// Notifications one was below the fold and users tapped Next). Location
/// mattered most: Radio Setup and the first map come before any session,
/// which was the only place that asked, so the base location was never
/// saved and "My position now" was greyed out.
class _PermissionsPage extends ConsumerWidget {
  const _PermissionsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gps =
        ref.watch(gpsStatusProvider).valueOrNull?.status ?? GpsStatus.unknown;
    // Only after Allow: watching the adapter would itself show the prompt.
    final btAsked = ref.watch(_bluetoothAskedProvider);
    final bt = btAsked
        ? ref.watch(bleAdapterStateProvider).valueOrNull
        : ref.read(radioScannerProvider).adapterStateNow;
    final notify = ref.watch(notificationsAllowedProvider).valueOrNull;
    // Android: the adapter state needs no permission, so the row follows
    // Nearby devices instead (null on iOS and in demo mode).
    final nearby = ref.watch(_nearbyDevicesProvider).valueOrNull;
    final android = PlatformText.isAndroid;
    return _Page(
      icon: Icons.lock_open_outlined,
      kicker: 'PERMISSIONS',
      title: 'Three things the app asks ${android ? 'Android' : 'iOS'} for',
      bottomPadding: _buttonBarHeight + 8,
      children: [
        Text(
          'Each is asked once, here. Say no and only that feature stays '
          'off; change them later in '
          '${android ? 'Settings → Apps → ${AppInfo.displayName}' : 'iOS Settings'}.',
          style: _prose(theme, theme.textTheme.bodyMedium),
        ),
        const SizedBox(height: 16),
        _PermissionRow(
          icon: Icons.my_location,
          title: 'Location',
          reason: 'Marks where the base sits and tags each reading, also '
              'with the screen locked.',
          state: switch (gps) {
            GpsStatus.searching || GpsStatus.fix => _PermissionState.granted,
            GpsStatus.denied => _PermissionState.refused,
            GpsStatus.off => _PermissionState.off,
            _ => _PermissionState.unknown,
          },
          offText: 'Location Services are off for the whole phone.',
          allowKey: const ValueKey('welcome-allow-location'),
          okKey: const ValueKey('welcome-location-ok'),
          onAllow: () =>
              ref.read(gpsServiceProvider).ensureStarted(request: true),
        ),
        _PermissionRow(
          icon: Icons.bluetooth,
          title: 'Bluetooth',
          reason: 'Connects to your nodes to read what they hear and run '
              'Node Setup.',
          state: switch (nearby) {
            true => _PermissionState.granted,
            false when btAsked => _PermissionState.refused,
            false => _PermissionState.unknown,
            null => switch (bt) {
                RadioAdapterState.on ||
                RadioAdapterState.turningOn ||
                RadioAdapterState.off ||
                RadioAdapterState.turningOff =>
                  _PermissionState.granted,
                RadioAdapterState.unauthorized => _PermissionState.refused,
                _ => _PermissionState.unknown,
              },
          },
          grantedNote:
              bt == RadioAdapterState.off || bt == RadioAdapterState.turningOff
                  ? 'Bluetooth itself is switched off right now.'
                  : null,
          allowKey: const ValueKey('welcome-allow-bluetooth'),
          okKey: const ValueKey('welcome-bluetooth-ok'),
          onAllow: () async {
            ref.read(_bluetoothAskedProvider.notifier).state = true;
            await ref.read(radioScannerProvider).requestPermission();
            ref.invalidate(_nearbyDevicesProvider);
          },
        ),
        _PermissionRow(
          icon: Icons.notifications_active_outlined,
          title: 'Notifications',
          reason: 'Alerts you on the lock screen when the base goes quiet '
              'or the Bluetooth link to your node drops.',
          state: switch (notify) {
            true => _PermissionState.granted,
            false => _PermissionState.refused,
            null => _PermissionState.unknown,
          },
          allowKey: const ValueKey('welcome-allow-notifications'),
          okKey: const ValueKey('welcome-notifications-ok'),
          onAllow: () => ref
              .read(outOfRangeMonitorProvider)
              .requestNotificationPermission(),
        ),
      ],
    );
  }
}

/// Whether the Bluetooth row's Allow was tapped (then it follows the live
/// adapter state). Watching the adapter earlier would show the prompt
/// before the reason is read.
final _bluetoothAskedProvider = StateProvider<bool>((ref) => false);

/// Android's Nearby devices permission (null on iOS / in demo mode).
final _nearbyDevicesProvider = FutureProvider.autoDispose<bool?>(
    (ref) => ref.read(radioScannerProvider).nearbyDevicesGranted());

enum _PermissionState { unknown, granted, refused, off }

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.reason,
    required this.state,
    required this.allowKey,
    required this.okKey,
    required this.onAllow,
    this.grantedNote,
    this.offText,
  });

  final IconData icon;
  final String title;
  final String reason;
  final _PermissionState state;
  final Key allowKey;
  final Key okKey;
  final Future<void> Function() onAllow;

  /// A line under the reason when granted (Bluetooth switched off).
  final String? grantedNote;

  /// For [_PermissionState.off] (Location Services off).
  final String? offText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = _prose(theme,
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant));
    final Widget trailing = switch (state) {
      _PermissionState.granted => Row(
          key: okKey,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 18, color: theme.status.ok),
            const SizedBox(width: 4),
            Text('Allowed',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.status.ok)),
          ],
        ),
      _PermissionState.refused =>
        Text('Not allowed', style: theme.textTheme.labelLarge),
      _PermissionState.off => Text('Off', style: theme.textTheme.labelLarge),
      // Tonal orange: the first buttons a new user meets match the app's
      // orange primaries (walkthrough 2026-11-08; the default tonal is the
      // cyan secondary).
      _PermissionState.unknown => FilledButton.tonal(
          key: allowKey,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            minimumSize: const Size(72, 40),
          ),
          onPressed: onAllow,
          child: const Text('Allow'),
        ),
    };
    final String? note = switch (state) {
      _PermissionState.granted => grantedNote,
      _PermissionState.refused =>
        'Change it under ${AppInfo.displayName} in iOS Settings whenever '
            'you like.',
      _PermissionState.off =>
        '${offText ?? 'Switched off.'} Turn it on in iOS Settings.',
      _PermissionState.unknown => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Icon(icon, size: 22, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                trailing,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child:
                Text(reason, style: _prose(theme, theme.textTheme.bodyMedium)),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 4),
              child: Text(note, style: muted),
            ),
        ],
      ),
    );
  }
}

/// The Settings → Privacy switches, bound to the same [privacyProvider].
/// One sentence each with a Details disclosure for the full wording, so
/// the page fits without scrolling (walkthrough 2026-11-08: the AI
/// helpers text was cut off behind Next).
class _PrivacyPage extends ConsumerWidget {
  const _PrivacyPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(privacyProvider);
    final notifier = ref.read(privacyProvider.notifier);
    final aiAvailable = ref.watch(aiAnalysisAvailableProvider);
    final theme = Theme.of(context);
    final small = _prose(
        theme,
        theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant));
    final blurb = _prose(theme, theme.textTheme.bodyMedium);
    return _Page(
      icon: Icons.shield_outlined,
      kicker: 'PRIVACY',
      title: 'Your data stays on this phone',
      bottomPadding: _buttonBarHeight + 8,
      children: [
        Text(
          'No accounts, no analytics, no cloud storage. Only these can '
          'leave the phone, and you choose each one:',
          style: blurb,
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Map tiles'),
          subtitle:
              Text('The map server sees which area you look at.', style: blurb),
          value: s.mapTiles,
          onChanged: notifier.setMapTiles,
        ),
        _Details(
          key: const ValueKey('welcome-details-tiles'),
          text: 'The tile server '
              '(${ref.watch(mapTileConfigProvider).tileServersPhrase}) '
              'sees which map area you look at, including the Terrain '
              'map\'s hillshade. Off: no basemap is requested.',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ground height lookups'),
          subtitle: Text('Point coordinates go to a public elevation service.',
              style: blurb),
          value: s.terrain,
          onChanged: notifier.setTerrain,
        ),
        const _Details(
          key: ValueKey('welcome-details-terrain'),
          text: 'Coordinates of your measurement points (and so your base) '
              'go to Open Topo Data, a public elevation service (not our '
              'map server), to look up ground height for the terrain-aware '
              'estimate and line-of-sight profile. Heights already looked up '
              'stay on the phone.',
        ),
        if (aiAvailable) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('AI helpers'),
            subtitle: Text('Numbers or your typed sentence, only when you tap.',
                style: blurb),
            value: s.aiConsent,
            onChanged: (on) async {
              // Same consent sheet as Settings → Privacy before turning on.
              if (on &&
                  !await showAiConsentSheet(context, confirmLabel: 'Allow')) {
                return;
              }
              await notifier.setAiConsent(on);
            },
          ),
          const _Details(
            key: ValueKey('welcome-details-ai'),
            text: 'Analyze (Pro) sends a numbers-only summary of a comparison '
                '(signal levels, counts, hardware names). Planning a test '
                'sends the sentence you type. Each goes to our server and '
                'on to Anthropic only when you tap Analyze or Next. No '
                'positions, node ids or keys. Off: test requests are read '
                'on the phone.',
          ),
        ],
        const SizedBox(height: 8),
        Text('Change these any time in Settings → Privacy.', style: small),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => launchUrl(Uri.parse(privacyPolicyUrl),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Privacy policy'),
          ),
        ),
      ],
    );
  }
}

/// A "Details" disclosure under a privacy switch: closed it is one small
/// button, open it shows the full wording.
class _Details extends StatefulWidget {
  const _Details({super.key, required this.text});
  final String text;

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => setState(() => _open = !_open),
            icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18),
            label: Text(_open ? 'Hide details' : 'Details'),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                widget.text,
                style: _prose(
                    theme,
                    theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            ),
        ],
      ),
    );
  }
}
