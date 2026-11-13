// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../demo/demo_mode.dart';
import '../../providers.dart';
import '../../services/diag_log.dart';
import '../../services/pro_entitlement.dart';
import '../../utils/map_tiles.dart';
import '../../utils/constants.dart';
import '../protocol_text.dart';
import 'onboarding/welcome_flow.dart';
import 'pro_paywall_screen.dart';
import '../../utils/user_errors.dart';
import '../../utils/app_info.dart';
import '../widgets/wordmark.dart';
import '../layout/window_class.dart';

const _aiDataNote = " With AI helpers on, an AI analysis sends a summary of "
    "the comparison's numbers and planning a test sends the sentence you "
    "type (never your route or positions) to our server and to Anthropic.";

/// Shown on About whenever AI analysis is built in.
const aiDisclaimer =
    'AI analysis is written by a language model from the numbers in your '
    'sessions. It can misread them or state something that is not so. '
    'Treat it as a second opinion: the measurements are the record, the '
    'text is a reading of them. It is not engineering, legal or safety '
    'advice, and nothing is sent unless you turn AI analysis on and ask '
    'for one.';

const supportUrl = 'https://${AppInfo.website}/support';

const sourceCodeUrl = 'https://github.com/motab619/meshurement-source';
const plateauNerdUrl = 'https://plateaunerd.com';
const osmCopyrightUrl = 'https://www.openstreetmap.org/copyright';

/// Meshtastic's required notice, word for word from their licensing and
/// trademark page (checked 2026-11-05), plus our no-endorsement line.
const trademarkNotice =
    'Meshtastic® is a registered trademark of Meshtastic LLC. Meshtastic '
    'software components are released under various licenses, see GitHub '
    'for details. No warranty is provided - use at your own risk. This app '
    'is not affiliated with or endorsed by Meshtastic LLC. MeshCore is a '
    'project of its authors; this app is not affiliated with it.';

/// Adds our NOTICE, the Meshtastic protobuf license and OSM attribution to
/// Flutter's license page (package licenses are added automatically).
/// Call once at startup.
void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['${AppInfo.displayName} — third-party notices'],
      await rootBundle.loadString('NOTICE'),
    );
    yield LicenseEntryWithLineBreaks(
      const ['Meshtastic protobufs'],
      'Message definitions from https://github.com/meshtastic/protobufs '
      '(v2.8.2), © Meshtastic LLC, licensed GPL-3.0.\n\n$trademarkNotice\n\n'
      '${await rootBundle.loadString('lib/proto/LICENSE')}',
    );
    yield const LicenseEntryWithLineBreaks(
      ['MeshCore protocol references'],
      'MeshCore support was written from reading these MIT-licensed '
      'projects; no code is copied from them.\n\n'
      'MeshCore firmware, https://github.com/meshcore-dev/MeshCore, '
      '© Scott Powell / rippleradios.com, MIT License.\n'
      'MeshMapper, https://github.com/DaveWoodCom/MeshMapper_Flutter_App, '
      '© MeshMapper, MIT License.\n'
      'meshcore-open, https://github.com/zjs81/meshcore-open, © zjs81, '
      'MIT License.\n\n'
      '$meshCoreCompatibilityNotice',
    );
    yield LicenseEntryWithLineBreaks(
      const ['B612 typeface'],
      await rootBundle.loadString('assets/fonts/OFL-B612.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const ['Courier Prime typeface'],
      await rootBundle.loadString('assets/fonts/OFL-CourierPrime.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      const ['Fredoka typeface'],
      await rootBundle.loadString('assets/fonts/OFL-Fredoka.txt'),
    );
    yield const LicenseEntryWithLineBreaks(
      ['OpenStreetMap'],
      'Map data © OpenStreetMap contributors, available under the Open '
      'Database License (ODbL) 1.0. $osmCopyrightUrl',
    );
  });
}

/// Who serves map tiles, for the "Your data" paragraph.
String mapTilesPrivacyText(MapTileConfig config) => config.anyRemoteHosted
    ? 'these hosts: our map tile server (CloudFront) inside '
        '${config.regionName ?? 'the covered region'} and '
        'tile.openstreetmap.org elsewhere, for map tiles'
    : 'two hosts: tile.openstreetmap.org for map tiles';

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

/// Subtitle for the Pro row: "Pro · lifetime", "Pro · until Oct 14, 2027"
/// or "Get Pro". "Until", not "renews": auto-renew status isn't available
/// from the store plugin, so "renews" would be wrong after a cancel.
String proRowLabel(ProStatus s) {
  if (!s.isPro) return 'Get Pro';
  final e = s.entitlement;
  return switch (e.plan) {
    ProPlan.lifetime => 'Pro · lifetime',
    ProPlan.yearly =>
      e.untilLabel == null ? 'Pro · yearly' : 'Pro · until ${e.untilLabel}',
    ProPlan.none => 'Pro',
  };
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _info = i);
    });
  }

  Future<void> _shareDiagnostics() async {
    final path = await DiagLog.instance.path();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (path == null) {
      messenger
          .showSnackBar(const SnackBar(content: Text('Nothing logged yet.')));
      return;
    }
    // iPad (and some iOS versions) need to know where the share sheet
    // pops from; anchor it to this screen.
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      await Share.shareXFiles([XFile(path)],
          subject: '${AppInfo.displayName} diagnostics',
          sharePositionOrigin: origin);
    } catch (e) {
      // A share that silently does nothing is the worst outcome in the
      // field: say what went wrong.
      messenger.showSnackBar(SnackBar(
          content: Text('Couldn\'t open the share sheet. ${userMessage(e)}')));
    }
  }

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  /// Hidden switch for App Review (docs/app-review-notes.md): a long-press
  /// on the app name opens the sample-data demo from the next launch, or
  /// turns it off again. iOS apps can't relaunch themselves, so the user
  /// closes and reopens the app.
  Future<void> _toggleDemoOnLaunch() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final on = prefs.getBool(DemoMode.nextLaunchPref) ?? false;
    final turnOn = !on;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(turnOn ? 'Open the demo?' : 'Leave the demo?'),
        content: Text(turnOn
            ? 'From the next launch the app shows sample data: a pretend '
                'node and a recorded walk, with every Pro feature on. '
                'Nothing is sent over Bluetooth and your own maps are not '
                'touched. Long-press here again to turn it off.'
            : 'From the next launch the app goes back to your own nodes '
                'and maps.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(turnOn ? 'Open demo' : 'Leave demo'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await prefs.setBool(DemoMode.nextLaunchPref, turnOn);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Close the app (swipe it away) and open it again.')));
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final version =
        info == null ? '' : 'Version ${info.version} (${info.buildNumber})';
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: WideColumn(
        child: ListView(
          children: [
            ListTile(
              title: const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wordmark(key: ValueKey('wordmark'), height: 36),
                ),
              ),
              subtitle: Text(
                '$version\nMaps how far your LoRa mesh nodes reach.',
              ),
              isThreeLine: true,
              onLongPress: _toggleDemoOnLaunch,
            ),
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text(AppInfo.proName),
              subtitle: Text(proRowLabel(ref.watch(proStatusProvider).value ??
                  ref.watch(proEntitlementProvider).status)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showProPaywall(context),
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Source code'),
              subtitle: const Text('github.com/motab619/meshurement-source (GPL-3.0)'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _open(sourceCodeUrl),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Licenses'),
              subtitle: const Text('Open-source components and notices'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: AppInfo.displayName,
                applicationVersion: version,
                applicationLegalese: '© 2026 Andy Brunker (Plateau Nerd). '
                    'Free software under the GNU GPL v3 or later. '
                    'Source: $sourceCodeUrl',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.waving_hand_outlined),
              title: const Text('Show welcome again'),
              subtitle: const Text('What the app does, privacy, node setup'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showWelcomeFlow(context),
            ),
            ListTile(
              leading: const Icon(Icons.checklist_outlined),
              title: const Text('Show checklist again'),
              subtitle: const Text('The four Get started steps, Coverage tab'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                ref.read(checklistHiddenProvider.notifier).state = false;
                await ref
                    .read(sharedPreferencesProvider)
                    .remove(onboardingChecklistHiddenKey);
                ref.read(mainTabProvider.notifier).state = 1;
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy policy'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _open(privacyPolicyUrl),
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Support'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _open(supportUrl),
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Share diagnostics log'),
              subtitle: const Text('Alerts, GPS, Bluetooth and app state '
                  'events — no positions or keys. Attach it to a bug report.'),
              trailing: const Icon(Icons.ios_share, size: 18),
              onTap: _shareDiagnostics,
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('© OpenStreetMap contributors'),
              subtitle: const Text('Map data, ODbL'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _open(osmCopyrightUrl),
            ),
            ListTile(
              leading: const Icon(Icons.terrain),
              title: const Text('Built by Plateau Nerd'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _open(plateauNerdUrl),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your data',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Your sessions, positions and signal readings stay on this '
                    'phone. The app contacts only '
                    '${mapTilesPrivacyText(ref.watch(mapTileConfigProvider))} '
                    '(this reveals the '
                    'area you are viewing), and, only if you turn on Online '
                    'terrain data in Settings, api.opentopodata.org for '
                    'elevations (this sends coordinates of the map area). '
                    'Nothing else is sent anywhere. There is no analytics or '
                    'tracking. Data leaves the phone only when you export or '
                    'share it yourself.'
                    '${AppConstants.aiAnalysisUrl != null ? _aiDataNote : ''}',
                    style: muted,
                  ),
                ],
              ),
            ),
            if (AppConstants.aiAnalysisUrl != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('About the AI analysis',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(aiDisclaimer, style: muted),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trademarkNotice, style: muted),
                  const SizedBox(height: 8),
                  Text(meshCoreCompatibilityNotice, style: muted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
