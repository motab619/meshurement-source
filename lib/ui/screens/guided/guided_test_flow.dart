// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../providers.dart';
import '../../../services/guided/plan_models.dart';
import 'ask_screen.dart';
import 'plan_screen.dart';
import 'result_screen.dart';
import 'run_screen.dart';

/// Navigation between the four guided-test screens (Ask → Plan → Run →
/// Result) and from the entry points (Coverage tab key, checklist, Live
/// idle sheet, Compare, map detail, resume banner).
abstract final class GuidedTestFlow {
  /// Open the Ask screen. [mapId] pins the map (map detail, Live tab);
  /// [prefill] pre-selects a template with its variants (Compare screen).
  static Future<void> open(BuildContext context,
      {int? mapId, PlanIntent? prefill}) {
    return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AskScreen(mapId: mapId, prefill: prefill),
    ));
  }

  static Future<void> openPlan(BuildContext context, PlanRecord plan,
      {bool replace = false}) {
    final route = MaterialPageRoute<void>(builder: (_) => PlanScreen(plan: plan));
    final nav = Navigator.of(context);
    return replace ? nav.pushReplacement(route) : nav.push(route);
  }

  static Future<void> openRun(BuildContext context, int planId,
      {bool replace = false}) {
    final route =
        MaterialPageRoute<void>(builder: (_) => RunScreen(planId: planId));
    final nav = Navigator.of(context);
    return replace ? nav.pushReplacement(route) : nav.push(route);
  }

  static Future<void> openResult(BuildContext context, PlanRecord plan,
      {bool replace = false}) {
    final route =
        MaterialPageRoute<void>(builder: (_) => ResultScreen(plan: plan));
    final nav = Navigator.of(context);
    return replace ? nav.pushReplacement(route) : nav.push(route);
  }

  /// A running or paused plan: resume it at its current step.
  static Future<void> resume(
      BuildContext context, WidgetRef ref, PlanRecord plan) async {
    if (plan.status == PlanStatus.paused) {
      await ref.read(guidedRunnerProvider).start(plan.id);
    }
    if (!context.mounted) return;
    await openRun(context, plan.id);
  }

  /// Where a test row leads: the result for a finished plan, the Run
  /// screen for one under way, the Plan screen for a draft.
  static Future<void> openPlanRecord(
      BuildContext context, WidgetRef ref, PlanRecord plan) {
    return switch (plan.status) {
      PlanStatus.done => openResult(context, plan),
      PlanStatus.running || PlanStatus.paused => resume(context, ref, plan),
      PlanStatus.draft => openPlan(context, plan),
      PlanStatus.abandoned => openResult(context, plan),
    };
  }
}

/// Which map a new plan belongs to: the given one, the only one, the one
/// the person picks from a sheet, or a new "Guided tests" map when there
/// are none (the person is told it was made). Null when the picker was dismissed.
Future<int?> pickMapForPlan(BuildContext context, WidgetRef ref,
    {int? mapId}) async {
  if (mapId != null) return mapId;
  final db = ref.read(databaseProvider);
  final maps = ref.read(coverageMapsProvider).valueOrNull ??
      await db.getAllCoverageMaps();
  if (maps.isEmpty) {
    // No map yet: make one, and say so (it shows up on the Coverage tab).
    final messenger =
        context.mounted ? ScaffoldMessenger.maybeOf(context) : null;
    final id = await db.createCoverageMap(name: 'Guided tests');
    messenger?.showSnackBar(const SnackBar(
      content: Text('Made a coverage map called "Guided tests" for this '
          'test. The first step asks where the base is.'),
      duration: Duration(seconds: 6),
    ));
    return id;
  }
  if (maps.length == 1) return maps.first.id;
  if (!context.mounted) return null;
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (_) => _MapPickerSheet(maps: maps),
  );
}

class _MapPickerSheet extends StatelessWidget {
  const _MapPickerSheet({required this.maps});

  final List<CoverageMap> maps;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Which map is this test for?',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final m in maps)
            ListTile(
              leading: const Icon(Icons.map),
              title: Text(m.name),
              onTap: () => Navigator.of(context).pop(m.id),
            ),
        ],
      ),
    );
  }
}
