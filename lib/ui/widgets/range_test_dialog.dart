// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../../services/range_test_detector.dart';
import '../theme/app_theme.dart';

/// Confirmation dialog when a Range Test beacon from a node other than our
/// base is detected during a session.
///
/// It can only be closed with Yes or No (tapping outside or swiping back
/// does nothing), so the question is never silently dropped. Beacons are
/// recorded while it is open.
class RangeTestDialog extends StatelessWidget {
  final RangeTestPrompt prompt;
  final void Function(bool confirmed) onResult;

  const RangeTestDialog({
    super.key,
    required this.prompt,
    required this.onResult,
  });

  /// Show the dialog (not dismissible by tapping outside).
  static Future<void> show(
    BuildContext context, {
    required RangeTestPrompt prompt,
    required void Function(bool confirmed) onResult,
  }) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RangeTestDialog(prompt: prompt, onResult: onResult),
      );

  @override
  Widget build(BuildContext context) {
    final nodeName =
        prompt.nodeName ?? '0x${prompt.meshNodeId.toRadixString(16)}';

    // canPop: false also blocks a barrier tap when the caller used
    // showDialog's default barrierDismissible.
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: Icon(Icons.radar, color: context.status.warning, size: 32),
        title: const Text('Test beacon detected'),
        content: Text(
          'Test beacons are coming from $nodeName, which is not your '
          'base.\n\n'
          'Record them in this session? They are being recorded until you '
          'answer.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              onResult(false);
              Navigator.pop(context);
            },
            child: const Text('No, ignore'),
          ),
          FilledButton(
            onPressed: () {
              onResult(true);
              Navigator.pop(context);
            },
            child: const Text('Yes, record'),
          ),
        ],
      ),
    );
  }
}
