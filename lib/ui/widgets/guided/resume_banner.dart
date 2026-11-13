// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers.dart';
import '../../../services/guided/plan_models.dart';
import '../../screens/guided/guided_test_flow.dart';

/// Slim line above the Live and Coverage tabs while a guided test is
/// running or paused: "Guided test paused at step 3 · Continue". Nothing
/// when there is none (or the engine is not available).
class GuidedResumeBanner extends ConsumerWidget {
  const GuidedResumeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(activePlanProvider).valueOrNull;
    if (plan == null ||
        (plan.status != PlanStatus.running && plan.status != PlanStatus.paused)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final word = plan.status == PlanStatus.paused ? 'paused' : 'under way';
    return Material(
      color: scheme.primaryContainer,
      child: InkWell(
        onTap: () => GuidedTestFlow.resume(context, ref, plan),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            child: Row(
              children: [
                Icon(Icons.directions_walk, size: 16, color: scheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Guided test $word at step ${plan.currentStep + 1}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onPrimaryContainer),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'Continue',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700),
                ),
                Icon(Icons.chevron_right, size: 18, color: scheme.onPrimaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
