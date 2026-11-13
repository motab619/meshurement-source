// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../../../services/guided/plan_models.dart';
import '../../theme/app_theme.dart';
import 'guided_styles.dart';

/// SETUP / REACH / MARGIN / third column with mono numbers and small captions;
/// the winner's row is orange and bold.
class ResultTable extends StatelessWidget {
  const ResultTable({super.key, required this.result});

  final PlanAnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final line = BorderSide(color: scheme.outlineVariant);
    final head = context.guidedMonoLabel;
    Widget th(String s) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(s, style: head),
        );
    Widget num(Measure m) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.value, style: context.readout.value),
              Text(m.caption,
                  style: context.guidedMonoLabel
                      .copyWith(letterSpacing: 0, height: 1.3)),
            ],
          ),
        );
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(31),
        1: FlexColumnWidth(23),
        2: FlexColumnWidth(23),
        3: FlexColumnWidth(23),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          decoration: BoxDecoration(border: Border(bottom: line)),
          children: [
            th('SETUP'),
            th('REACH'),
            th('MARGIN'),
            th(result.thirdLabel.toUpperCase()),
          ],
        ),
        for (final v in result.variants)
          TableRow(
            decoration: BoxDecoration(border: Border(bottom: line)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 9, 6, 9),
                child: Text(
                  v.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    color: result.winner == v.variant ? scheme.primary : null,
                    fontWeight: result.winner == v.variant
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
              num(v.reach),
              num(v.margin),
              num(v.third),
            ],
          ),
      ],
    );
  }
}

/// The table as plain text for sharing: one line per setup.
String resultTableText(PlanAnalysisResult r) {
  final b = StringBuffer();
  b.writeln('SETUP · REACH · MARGIN · ${r.thirdLabel.toUpperCase()}');
  for (final v in r.variants) {
    final win = r.winner == v.variant ? ' ★' : '';
    b.writeln('${v.name}$win · ${v.reach.value} (${v.reach.caption}) · '
        '${v.margin.value} (${v.margin.caption}) · '
        '${v.third.value} (${v.third.caption})');
  }
  return b.toString().trimRight();
}
