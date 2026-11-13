// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers.dart';
import '../../services/privacy_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_analysis_card.dart' show showAiConsentSheet;
import '../widgets/export_dialog.dart' show exportPrivacyNote;
import 'pro_paywall_screen.dart' show privacyPolicyUrl;
import '../layout/window_class.dart';

/// Settings → Privacy: every choice about what leaves the phone, in one
/// place. The switches are the same prefs the features read.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(privacyProvider);
    final notifier = ref.read(privacyProvider.notifier);
    final aiAvailable = ref.watch(aiAnalysisAvailableProvider);
    final small = Theme.of(context).textTheme.bodySmall;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: WideColumn(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child:
                  Text('Your signal data, routes and node details stay on this '
                      'phone. '
                      'These are the only things that can leave it, and you '
                      'choose each one.'),
            ),
            const _Header('Sent to other servers'),
            SwitchListTile(
              title: const Text('Map tiles'),
              subtitle: Text('The tile server '
                  '(${ref.watch(mapTileConfigProvider).tileServersPhrase}) '
                  'sees which map area you look at, including the Terrain '
                  'map\'s hillshade. Off: no basemap is requested.'),
              value: s.mapTiles,
              onChanged: notifier.setMapTiles,
            ),
            SwitchListTile(
              title: const Text('Ground height lookups'),
              subtitle: const Text(
                  'Coordinates of your measurement points (and so your base) '
                  'go to Open Topo Data, a public elevation service (not our '
                  'map server), to look up ground height for the terrain-aware '
                  'estimate and line-of-sight profile. Heights already looked up '
                  'stay on the phone.'),
              value: s.terrain,
              onChanged: notifier.setTerrain,
            ),
            if (aiAvailable)
              SwitchListTile(
                title: const Text('AI helpers'),
                subtitle: const Text(
                    'Two uses. Analyze (Pro): a numbers-only summary of a '
                    'comparison or test result (signal levels, counts, rig '
                    'names). Planning a test: the sentence you type. Each goes '
                    'to our server and on to Anthropic only when you tap '
                    'Analyze, or type a request and tap Next. No positions, '
                    'node ids or keys. Off: test requests are read on the '
                    'phone.'),
                value: s.aiConsent,
                onChanged: (on) => _setAi(context, notifier, on),
              ),
            const _Header('Stays under your control'),
            const ListTile(
              leading: Icon(Icons.ios_share),
              title: Text('Exports'),
              subtitle: Text(
                  'Exports only go where you send them. $exportPrivacyNote'),
            ),
            const ListTile(
              leading: Icon(Icons.home_outlined),
              title: Text('Base location'),
              subtitle: Text(
                  'Chosen per map: open a coverage map, then the menu (top '
                  'right) → Set base location.'),
            ),
            const _Header('More'),
            ListTile(
              leading: const Icon(Icons.policy_outlined),
              title: const Text('Privacy policy'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => launchUrl(Uri.parse(privacyPolicyUrl),
                  mode: LaunchMode.externalApplication),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Text('No ads, analytics or tracking.', style: small),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setAi(
      BuildContext context, PrivacyNotifier notifier, bool on) async {
    if (on) {
      if (await showAiConsentSheet(context, confirmLabel: 'Allow')) {
        await notifier.setAiConsent(true);
      }
      return;
    }
    await notifier.setAiConsent(false);
    if (!context.mounted) return;
    final clear = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear saved analyses?'),
        content: const Text(
            'AI analysis is off. Delete the answers already saved on this '
            'phone too?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep them')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (clear == true) await notifier.clearAiResults();
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => SectionLabel(title);
}
