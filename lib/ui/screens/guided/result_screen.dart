// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../providers.dart';
import '../../../services/guided/plan_models.dart';
import '../../widgets/field_report/field_report_sheet.dart';
import '../../widgets/guided/guided_styles.dart';
import '../../widgets/guided/lead_bars.dart';
import '../../widgets/guided/plan_ai_card.dart';
import '../../widgets/guided/result_table.dart';
import '../coverage_map_detail_screen.dart';
import 'plan_copy.dart';
import '../../../utils/user_errors.dart';
import '../../../utils/app_info.dart';
import '../../layout/window_class.dart';

/// Screen 4: "What you found out". Caption, verdict with a 3 px orange
/// rule, the table, lead bars, NEXT STEP, DATA NOTE(s), the AI card, and
/// Share / Open on map / Done.
class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key, required this.plan, this.result});

  final PlanRecord plan;

  /// Skips the lookup when the caller already has it (tests, demo).
  final PlanAnalysisResult? result;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  PlanAnalysisResult? _result;
  List<StepRecord> _steps = const [];
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _result = widget.result;
    _load();
  }

  Future<void> _load() async {
    final runner = ref.read(guidedRunnerProvider);
    try {
      _result ??= await runner.result(widget.plan.id);
      _steps = await runner.steps(widget.plan.id);
    } catch (e) {
      _error = userMessage(e, doing: 'reading the result');
    }
    if (mounted) setState(() => _loaded = true);
  }

  /// Walks recorded and the minutes they took (planned minutes when a
  /// walk has no times).
  (int, int) get _walksAndMinutes {
    var walks = 0, minutes = 0;
    for (final s in _steps) {
      if (s.step.kind != StepKind.walk || s.status != StepStatus.done) continue;
      walks++;
      final a = s.startedAt, b = s.endedAt;
      minutes += a != null && b != null
          ? (b.difference(a).inSeconds / 60).round()
          : PlanCopy.stepMinutes(s.step, widget.plan.intent);
    }
    return (walks, minutes);
  }

  String _shareText(PlanAnalysisResult r) {
    final b = StringBuffer()
      ..writeln('${widget.plan.title} · ${AppInfo.displayName} guided test')
      ..writeln()
      ..writeln(r.headline)
      ..writeln(r.fairness)
      ..writeln()
      ..writeln(resultTableText(r))
      ..writeln()
      ..writeln('Next step: ${r.nextStep}');
    for (final n in r.dataNotes) {
      b.writeln('Note: $n');
    }
    return b.toString().trimRight();
  }

  /// The Share key, so the share sheet has an anchor (an iPad shows it as
  /// a popover pointing at the key, and fails without one).
  final _shareKey = GlobalKey();

  Future<void> _share(PlanAnalysisResult r) {
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    return Share.share(_shareText(r),
        subject: widget.plan.title,
        sharePositionOrigin: box == null
            ? const Rect.fromLTWH(0, 0, 1, 1)
            : box.localToGlobal(Offset.zero) & box.size);
  }

  /// The comparison card: one side per variant, from its walks.
  Future<void> _fieldReport(PlanAnalysisResult r) => showComparisonFieldReport(
        context,
        coverageMapId: widget.plan.coverageMapId,
        sides: [for (final v in r.variants) (v.name, v.sessionIds)],
        result: r,
      );

  Future<void> _openMap() async {
    final map = await ref
        .read(databaseProvider)
        .getCoverageMap(widget.plan.coverageMapId);
    if (map == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CoverageMapDetailScreen(
        map: map,
        showOnlySessions: {
          for (final v in _result?.variants ?? const <VariantResult>[])
            ...v.sessionIds,
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = _result;
    final (walks, minutes) = _walksAndMinutes;
    return Scaffold(
      appBar: AppBar(title: const Text('What you found out')),
      body: WideColumn(
        child: Column(
          children: [
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : r == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _error ??
                                  'The result is still being worked out. Come '
                                      'back to this test from the map in a '
                                      'moment.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Text(
                              '${widget.plan.title.toUpperCase()} · $walks '
                              '${walks == 1 ? 'WALK' : 'WALKS'} · $minutes MIN',
                              style: context.guidedCaption,
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.only(left: 12),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                      color: scheme.primary, width: 3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.headline,
                                      style: context.guidedTitle
                                          .copyWith(fontSize: 21)),
                                  if (r.fairness.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(r.fairness, style: context.guidedFine),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            ResultTable(result: r),
                            const SizedBox(height: 18),
                            LeadBars(result: r),
                            const SizedBox(height: 10),
                            GuidedCard(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 12, 14, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('NEXT STEP',
                                      style: context.guidedCaption),
                                  const SizedBox(height: 4),
                                  Text(r.nextStep,
                                      style: theme.textTheme.bodyMedium),
                                ],
                              ),
                            ),
                            for (final note in r.dataNotes) ...[
                              const SizedBox(height: 14),
                              GuidedCard(
                                padding:
                                    const EdgeInsets.fromLTRB(14, 12, 14, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('DATA NOTE',
                                        style: context.guidedCaption),
                                    const SizedBox(height: 4),
                                    Text(note,
                                        style: context.guidedSoft
                                            .copyWith(fontSize: 14)),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            PlanAiCard(
                              planId: widget.plan.id,
                              digest: r.digest,
                              question: widget.plan.intent.question,
                            ),
                          ],
                        ),
            ),
            GuidedFooter(children: [
              GuidedGhostKey('Share field report',
                  key: const ValueKey('result-field-report'),
                  onPressed: r == null ? null : () => _fieldReport(r)),
              Row(children: [
                Expanded(
                  child: GuidedGhostKey('Share',
                      key: _shareKey,
                      onPressed: r == null ? null : () => _share(r)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GuidedGhostKey('Open on map', onPressed: _openMap),
                ),
              ]),
              GuidedKey('Done', onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }),
            ]),
          ],
        ),
      ),
    );
  }
}
