// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../providers.dart';
import '../../../services/guided/plan_models.dart';
import '../../screens/guided/guided_test_flow.dart';
import '../field_report/field_report_sheet.dart';

/// Sessions recorded by [planId]'s walks, by variant (setup index).
Future<Map<int, List<int>>> planSessionsByVariant(
    AppDatabase db, int planId) async {
  final out = <int, List<int>>{};
  for (final s in await db.getTestSteps(planId)) {
    final id = s.sessionId;
    if (id == null) continue;
    (out[s.variant ?? 0] ??= []).add(id);
  }
  return out;
}

/// Field report for a test: the comparison card of its setups (the
/// stored result gives the verdict when there is one), or the single
/// session's card for a one-setup test. TestFlight 2026-11-10: "I should
/// be able to share and make reports of my tests."
Future<void> showTestFieldReport(
    BuildContext context, WidgetRef ref, PlanRecord plan) async {
  final db = ref.read(databaseProvider);
  final byVariant = await planSessionsByVariant(db, plan.id);
  final result = await ref.read(guidedRunnerProvider).result(plan.id);
  if (!context.mounted) return;
  final variants = plan.intent.variants;
  final sides = <(String, List<int>)>[
    for (final e
        in (byVariant.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
      (
        e.key < variants.length ? variants[e.key] : 'Setup ${e.key + 1}',
        e.value
      ),
  ];
  if (sides.length >= 2) {
    await showComparisonFieldReport(context,
        coverageMapId: plan.coverageMapId, sides: sides, result: result);
  } else if (sides.length == 1 && sides.first.$2.length == 1) {
    await showSessionFieldReport(context, sides.first.$2.first);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nothing recorded in this test yet, so there is no '
            'report to make.')));
  }
}

/// Short status line for a test row.
String planStatusLine(PlanRecord p) {
  final d = (p.finishedAt ?? p.createdAt).toLocal();
  final when = '${d.month}/${d.day} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final n = p.intent.variants.length;
  final setups = p.intent.template == PlanTemplate.reach
      ? 'reach'
      : '$n ${n == 1 ? 'setup' : 'setups'}';
  return switch (p.status) {
    PlanStatus.draft => 'Planned · $setups',
    PlanStatus.running => 'Under way · step ${p.currentStep + 1}',
    PlanStatus.paused => 'Paused at step ${p.currentStep + 1}',
    PlanStatus.done => '$when · $setups',
    PlanStatus.abandoned => 'Stopped · $when',
  };
}

/// "Tests" on map detail, next to Sessions: one row per plan (newest
/// first). A finished test opens its result; a paused one shows Continue.
/// Nothing is drawn when the map has no tests (or the engine is not
/// available).
class GuidedTestsSection extends ConsumerWidget {
  const GuidedTestsSection({super.key, required this.mapId, this.onShowOnly});

  final int mapId;

  /// Shows only these sessions on the map (the test's walks). Null hides
  /// the button.
  final void Function(Set<int> sessionIds)? onShowOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(mapPlansProvider(mapId)).valueOrNull ?? const [];
    if (plans.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text('Tests', style: theme.textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Plan a test'),
                onPressed: () => GuidedTestFlow.open(context, mapId: mapId),
              ),
            ],
          ),
        ),
        for (final p in plans)
          ListTile(
            key: ValueKey('plan-${p.id}'),
            leading: Icon(
              switch (p.status) {
                PlanStatus.done => Icons.flag,
                PlanStatus.running ||
                PlanStatus.paused =>
                  Icons.directions_walk,
                PlanStatus.draft => Icons.route,
                PlanStatus.abandoned => Icons.flag_outlined,
              },
              color: p.status == PlanStatus.done
                  ? theme.colorScheme.primary
                  : null,
            ),
            title: Text(p.title),
            subtitle: Text(planStatusLine(p)),
            trailing: p.status == PlanStatus.paused ||
                    p.status == PlanStatus.running
                ? FilledButton.tonal(
                    onPressed: () => GuidedTestFlow.resume(context, ref, p),
                    child: const Text('Continue'),
                  )
                : p.status == PlanStatus.draft
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (onShowOnly != null)
                            IconButton(
                              key: ValueKey('plan-show-${p.id}'),
                              tooltip: 'Show only this test on the map',
                              icon: const Icon(Icons.visibility_outlined),
                              onPressed: () async {
                                final byVariant = await planSessionsByVariant(
                                    ref.read(databaseProvider), p.id);
                                onShowOnly!({
                                  for (final ids in byVariant.values) ...ids,
                                });
                              },
                            ),
                          IconButton(
                            key: ValueKey('plan-report-${p.id}'),
                            tooltip: 'Field report',
                            icon: const Icon(Icons.summarize_outlined),
                            onPressed: () =>
                                showTestFieldReport(context, ref, p),
                          ),
                        ],
                      ),
            onTap: () => GuidedTestFlow.openPlanRecord(context, ref, p),
          ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
      ],
    );
  }
}
