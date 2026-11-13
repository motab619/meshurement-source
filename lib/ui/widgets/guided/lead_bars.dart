// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../../../services/guided/plan_models.dart';
import '../../theme/app_theme.dart';
import 'guided_styles.dart';

/// "WHERE EACH ONE LED · SHARED CELLS": one bar per setup with its share
/// of the shared cells where it was stronger. The winner is orange, the
/// others cyan; with no winner every bar is full and reads "tie".
class LeadBars extends StatelessWidget {
  const LeadBars({super.key, required this.result});

  final PlanAnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tie = result.winner == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('WHERE EACH ONE LED · SHARED CELLS', style: context.guidedCaption),
        const SizedBox(height: 10),
        for (final v in result.variants)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(v.name,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 10,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ColoredBox(color: theme.status.neutral),
                          ),
                          FractionallySizedBox(
                            widthFactor: tie
                                ? 1
                                : (v.leadPct / 100).clamp(0.0, 1.0),
                            heightFactor: 1,
                            child: ColoredBox(
                              color: result.winner == v.variant
                                  ? scheme.primary
                                  : scheme.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: Text(
                    tie ? 'tie' : '${v.leadPct.round()} %',
                    textAlign: TextAlign.right,
                    style: context.readout.value.copyWith(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
