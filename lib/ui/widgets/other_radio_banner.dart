// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../theme/app_theme.dart';

/// Amber strip on the live map while a session records and a radio other
/// than the base (and ours) is heard on the test channel or answers a
/// ping: usually a second base left on, which relayed answers would hide
/// until the Compare screen. Dismissable; each radio is reported once a
/// session (see `OtherRadioMonitor`).
class OtherRadioBanner extends ConsumerWidget {
  const OtherRadioBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alert = ref.watch(otherRadioAlertProvider).valueOrNull;
    if (alert == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final status = theme.status;
    return Container(
      key: const ValueKey('other-radio-banner'),
      padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
      decoration: BoxDecoration(
        color: status.warningContainer.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.cell_tower,
                size: 18, color: status.onWarningContainer),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                alert.message,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: status.onWarningContainer),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('other-radio-dismiss'),
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            iconSize: 18,
            color: status.onWarningContainer,
            icon: const Icon(Icons.close),
            onPressed: () =>
                ref.read(packetProcessorProvider).otherRadios.dismiss(),
          ),
        ],
      ),
    );
  }
}
