// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The one empty-state pattern: an icon in a hairlined tile, a short
/// title, one sentence of what to do, and an optional action. Centred,
/// never wider than a phone column. With [tile] false the icon stands
/// alone, muted, with no tile behind it (where a tile next to a FAB
/// reads as another button).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  /// Draw the icon in its hairlined tile (the default).
  final bool tile;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.tile = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          // Without the tile the state is a footnote under other content
          // (the Coverage tab's checklist), so it keeps less air.
          padding:
              EdgeInsets.symmetric(horizontal: 24, vertical: tile ? 32 : 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tile) ...[
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 36, color: scheme.primary),
                ),
                const SizedBox(height: 20),
              ] else ...[
                Icon(icon, size: 32, color: scheme.onSurfaceVariant),
                const SizedBox(height: 12),
              ],
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium!
                      .copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 20),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
