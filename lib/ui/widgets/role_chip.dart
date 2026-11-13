// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../../services/radio_roles.dart';
import '../theme/app_theme.dart';

/// Small "Base" / "Mobile" tag.
class RoleChip extends StatelessWidget {
  final RadioRole role;

  const RoleChip(this.role, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = role == RadioRole.base;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: base ? scheme.tertiaryContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(base ? Icons.cell_tower : Icons.directions_walk,
              size: 13,
              color: base
                  ? scheme.onTertiaryContainer
                  : scheme.onSecondaryContainer),
          const SizedBox(width: 3),
          Text(role.label,
              style: theme.textTheme.labelMedium?.copyWith(
                  color: base
                      ? scheme.onTertiaryContainer
                      : scheme.onSecondaryContainer)),
        ],
      ),
    );
  }
}
