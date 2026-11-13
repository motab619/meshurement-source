// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers.dart';
import '../../theme/app_theme.dart';
import 'go_to_compass.dart' show formatGoToDistance;
import 'guided_styles.dart';

/// What the person chose on the risk sheet.
enum RiskChoice {
  /// "Change base from here": the sheet is marked as seen.
  changeHere,

  /// "I'll walk to it instead": the Bluetooth path.
  walkInstead,
}

/// Whether the full risk sheet has been read on this phone.
bool riskSheetSeen(WidgetRef ref) =>
    ref.read(sharedPreferencesProvider).getBool(guidedRiskSeenKey) ?? false;

/// "Changing the base from here" (design §5). The checkbox gates the
/// primary key. Resolves null when dismissed. [reminder] shows the same
/// sheet from the ⓘ later: the checkbox is pre-ticked.
Future<RiskChoice?> showRiskSheet(
  BuildContext context, {
  required String targetName,
  required double? baseDistanceM,
  bool reminder = false,
}) {
  return showModalBottomSheet<RiskChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => RiskSheet(
      targetName: targetName,
      baseDistanceM: baseDistanceM,
      reminder: reminder,
    ),
  );
}

class RiskSheet extends ConsumerStatefulWidget {
  const RiskSheet({
    super.key,
    required this.targetName,
    required this.baseDistanceM,
    this.reminder = false,
  });

  final String targetName;
  final double? baseDistanceM;
  final bool reminder;

  @override
  ConsumerState<RiskSheet> createState() => _RiskSheetState();
}

class _RiskSheetState extends ConsumerState<RiskSheet> {
  late bool _canReach = widget.reminder;

  Future<void> _confirm() async {
    await ref.read(sharedPreferencesProvider).setBool(guidedRiskSeenKey, true);
    if (mounted) Navigator.of(context).pop(RiskChoice.changeHere);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = theme.textTheme.bodyMedium!
        .copyWith(fontSize: 14, color: scheme.onSurfaceVariant);
    final bold =
        p.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface);
    final distance = formatGoToDistance(widget.baseDistanceM);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Changing the base from here',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(style: p, children: [
                const TextSpan(
                    text: 'The app will tell the base node to switch to '),
                TextSpan(text: widget.targetName, style: bold),
                const TextSpan(
                    text: ', then switch your node to match. The base '
                        'restarts to do it.'),
              ]),
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(style: p, children: [
                TextSpan(text: 'What can go wrong: ', style: bold),
                const TextSpan(
                    text: "if the base restarts on a setting your node can't "
                        "reach from here, you'll have to walk to the base and "
                        'fix it in Node Setup. The base is '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: _DistancePill(distance),
                ),
                const TextSpan(text: ' away right now.'),
              ]),
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(style: p, children: [
                TextSpan(
                    text: 'What the app does to keep you safe: ', style: bold),
                const TextSpan(
                    text: "saves the base's settings first · changes the base "
                        'first and your node second · listens for the base '
                        'for two minutes on the new setting · if the base '
                        'stays silent, puts your node back and stops with '
                        'directions to the base.'),
              ]),
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              key: const ValueKey('risk-check'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _canReach,
              onChanged: (v) {
                GuidedHaptics.tap();
                setState(() => _canReach = v ?? false);
              },
              title: const Text('I can get to the base if I need to'),
            ),
            GuidedKey(
              'Change base from here',
              tall: true,
              onPressed: _canReach ? _confirm : null,
            ),
            const SizedBox(height: 10),
            GuidedGhostKey(
              "I'll walk to it instead",
              onPressed: () =>
                  Navigator.of(context).pop(RiskChoice.walkInstead),
            ),
          ],
        ),
      ),
    );
  }
}

class _DistancePill extends StatelessWidget {
  const _DistancePill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(text, style: context.guidedMono),
    );
  }
}

/// After the sheet has been read once: "Changing the base from here has a
/// risk ⓘ", the ⓘ reopening it.
class RiskReminderLine extends StatelessWidget {
  const RiskReminderLine({super.key, required this.onInfo});

  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text('Changing the base from here has a risk',
              style: context.guidedFine),
        ),
        IconButton(
          tooltip: 'What can go wrong?',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.info_outline,
              size: 18, color: Theme.of(context).colorScheme.secondary),
          onPressed: onInfo,
        ),
      ],
    );
  }
}
