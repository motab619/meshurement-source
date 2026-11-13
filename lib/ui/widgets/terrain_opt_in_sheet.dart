// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../demo/demo_mode.dart';
import '../../services/privacy_settings.dart';

/// True when terrain elevation may be fetched. When it is off, explains what
/// would be sent and asks; "Turn on" sets the same switch as
/// Settings → Privacy. Demo mode uses synthetic terrain, so never asks.
Future<bool> ensureTerrainOptIn(BuildContext context, WidgetRef ref) async {
  if (DemoMode.enabled || ref.read(privacyProvider).terrain) return true;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const TerrainOptInSheet(),
  );
  if (ok != true) return false;
  await ref.read(privacyProvider.notifier).setTerrain(true);
  return true;
}

class TerrainOptInSheet extends StatelessWidget {
  const TerrainOptInSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Look up terrain elevation?', style: text.titleMedium),
              const SizedBox(height: 12),
              const Text(
                  'To see the ground between two points, the app sends the '
                  'coordinates of those points (this can include your base '
                  'location) to Open Topo Data, api.opentopodata.org. Nothing '
                  'else is sent. Elevations you have already looked up are '
                  'kept on the phone and work offline.'),
              const SizedBox(height: 8),
              Text('You can switch this off any time in Settings → Privacy.',
                  style: text.bodySmall),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Not now'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Turn on'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
