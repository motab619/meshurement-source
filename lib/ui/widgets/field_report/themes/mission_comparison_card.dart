// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../services/field_report/comparison_report_data.dart';
import '../../../../services/field_report/field_report_data.dart';
import '../report_painters.dart';
import '../report_parts.dart';
import '../report_style.dart';
import '../report_theme.dart';
import 'mission_card.dart';

/// The Mission look of a comparison Field Report
/// (docs/design/field-report/themes.md): a comparative test report on the
/// same cream paper as [MissionReportCard]. A FINDING box with the win
/// line, one figure per configuration (FIG. 1A, 1B…) all drawn on one
/// shared frame so their scales match, the best one stamped in the spot
/// red, and a results table with a column per configuration.
class MissionComparisonCard extends StatelessWidget {
  const MissionComparisonCard({super.key, required this.comparison});

  final ThemedComparison comparison;

  ComparisonReportData get _d => comparison.data;
  int get _n => _d.sides.length;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
        size: comparison.format.size,
        child: DecoratedBox(
          decoration: missionPaper,
          child: switch (comparison.format) {
            ReportFormat.feed => _feed(),
            ReportFormat.story => _story(),
            ReportFormat.wide => _wide(),
          },
        ),
      );

  Widget _header(double s, {int titleLines = 1, bool compact = false}) =>
      MissionHeader(
        kicker: 'COMPARATIVE TEST · $_n CONFIGURATIONS',
        date: _d.startedAt,
        title: comparison.title,
        scale: s,
        titleLines: titleLines,
        compact: compact,
      );

  Widget _feed() {
    final s = _n > 2 ? 0.92 : 1.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 48, 56, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(s),
          SizedBox(height: 20 * s),
          _Finding(comparison: comparison, scale: s),
          SizedBox(height: 22 * s),
          Expanded(child: _Figures(comparison: comparison, scale: s)),
          SizedBox(height: 22 * s),
          _ResultsTable(comparison: comparison, scale: s),
          const SizedBox(height: 14),
          const MissionFooter(scale: 1),
        ],
      ),
    );
  }

  Widget _story() {
    const s = 1.1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 70, 64, 52),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(s, titleLines: 2),
          const SizedBox(height: 30),
          _Finding(comparison: comparison, scale: s),
          const SizedBox(height: 30),
          Expanded(child: _Figures(comparison: comparison, scale: s)),
          const SizedBox(height: 30),
          _ResultsTable(comparison: comparison, scale: s),
          const SizedBox(height: 24),
          const MissionFooter(scale: s),
        ],
      ),
    );
  }

  Widget _wide() {
    const s = 0.78;
    const r = 0.84;
    final figuresW = switch (_n) { 2 => 560.0, 3 => 620.0, _ => 600.0 };
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 30, 40, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(s, compact: true),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                    width: figuresW,
                    child: _Figures(
                        comparison: comparison, scale: s, caption: false)),
                const SizedBox(width: 30),
                Expanded(
                  // Finding level with the figures' tops, the caption with
                  // their captions.
                  child: MissionSpread(children: [
                    _Finding(comparison: comparison, scale: r, compact: true),
                    _ResultsTable(
                        comparison: comparison, scale: r, compact: true),
                    _FiguresCaption(comparison: comparison, scale: s),
                  ]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const MissionFooter(scale: s),
        ],
      ),
    );
  }
}

/// Figure letter of side [i]: A, B, C, D.
String _letter(int i) => String.fromCharCode(0x41 + i);

// ---------------------------------------------------------------------------
// Finding.

class _Finding extends StatelessWidget {
  const _Finding(
      {required this.comparison, required this.scale, this.compact = false});

  final ThemedComparison comparison;
  final double scale;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final d = comparison.data;
    final verdict = d.verdict;
    final headline = verdict ?? comparison.winLine;
    final second = verdict == null ? null : comparison.winLine;
    final note = comparison.note;
    final w = d.winner;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: MissionInk.ink, width: 2.5),
      ),
      padding: EdgeInsets.all(5 * s),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: MissionInk.ink, width: 1),
        ),
        padding: EdgeInsets.fromLTRB(22 * s, 14 * s, 22 * s, 18 * s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(width: 14 * s, height: 14 * s, color: MissionInk.red),
                SizedBox(width: 10 * s),
                Text('FINDING',
                    style: missionMono(18 * s,
                        color: MissionInk.red, bold: true, spacing: 4 * s)),
                if (w != null) ...[
                  const Spacer(),
                  Text('BEST: FIG. 1${_letter(w)}',
                      style: missionSans(17 * s,
                          bold: true, color: MissionInk.red, spacing: 1.5 * s)),
                ],
              ],
            ),
            SizedBox(height: 10 * s),
            Text(headline,
                maxLines: compact ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: missionSans(compact ? 27 * s : 31 * s, bold: true)
                    .copyWith(height: 1.15)),
            if (second != null) ...[
              SizedBox(height: 6 * s),
              Text(second,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: missionSans(22 * s, italic: true)),
            ],
            if (note != null) ...[
              SizedBox(height: 12 * s),
              Container(height: 1, color: MissionInk.faint),
              SizedBox(height: 10 * s),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: 'NOTE: ',
                      style: missionMono(17 * s,
                          color: MissionInk.red, bold: true)),
                  TextSpan(
                      text: note,
                      style: missionSans(17 * s, color: MissionInk.soft)),
                ]),
                maxLines: compact ? 2 : 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Figures.

/// One figure per side on a shared frame, laid out in whichever grid
/// draws the routes largest, then (when [caption]) the shared caption and
/// the symbol key.
class _Figures extends StatelessWidget {
  const _Figures(
      {required this.comparison, required this.scale, this.caption = true});

  final ThemedComparison comparison;
  final double scale;
  final bool caption;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final routes = comparison.routes;
    final n = routes.length;
    final frame = RouteFrame.of(routes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final gapX = 24 * s, gapY = 20 * s;
            final dotR = n > 2 ? 7.5 : 9.0;
            final pad = (dotR + 10) * s;
            // Grids to try: one row, and two rows for four sides (or one
            // column for two or three).
            final options = {n, if (n == 4) 2 else 1};
            (int, double)? best;
            for (final cols in options) {
              final rows = (n + cols - 1) ~/ cols;
              final cellW = (box.maxWidth - (cols - 1) * gapX) / cols;
              final capH = _captionHeight(cellW, s);
              final cellH = (box.maxHeight - (rows - 1) * gapY) / rows - capH;
              final fit = math.min((cellW - 2 * pad) / frame.width,
                  (cellH - 2 * pad) / frame.height);
              if (best == null || fit > best.$2) best = (cols, fit);
            }
            final cols = best!.$1;
            final rows = (n + cols - 1) ~/ cols;
            final cellW = (box.maxWidth - (cols - 1) * gapX) / cols;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var row = 0; row < rows; row++) ...[
                  if (row > 0) SizedBox(height: gapY),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var c = 0; c < cols; c++) ...[
                          if (c > 0) SizedBox(width: gapX),
                          Expanded(
                            child: row * cols + c < n
                                ? _SideFigure(
                                    comparison: comparison,
                                    index: row * cols + c,
                                    frame: frame,
                                    scale: s,
                                    dotRadius: dotR,
                                    twoLine: _twoLine(cellW, s),
                                  )
                                : const SizedBox(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          }),
        ),
        if (caption) ...[
          SizedBox(height: 12 * s),
          _FiguresCaption(comparison: comparison, scale: s),
        ],
      ],
    );
  }

  static bool _twoLine(double cellW, double s) => cellW < 400 * s;

  static double _captionHeight(double cellW, double s) =>
      (_twoLine(cellW, s) ? 62 : 38) * s;
}

class _SideFigure extends StatelessWidget {
  const _SideFigure({
    required this.comparison,
    required this.index,
    required this.frame,
    required this.scale,
    required this.dotRadius,
    required this.twoLine,
  });

  final ThemedComparison comparison;
  final int index;
  final RouteFrame frame;
  final double scale, dotRadius;
  final bool twoLine;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final win = comparison.data.winner == index;
    final name = comparison.data.sides[index].name;
    final fig = missionMonoSpan('FIG. 1${_letter(index)}',
        missionMono(18 * s, color: MissionInk.red, bold: true));
    final nameStyle = missionMono(18 * s, bold: true);
    final stamp = win ? _BestStamp(scale: s) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomPaint(
            painter: MissionRoutePlot(
              route: comparison.routes[index],
              frame: frame,
              miles: comparison.miles,
              scale: s,
              scaleBar: index == 0,
              dotRadius: dotRadius,
            ),
          ),
        ),
        SizedBox(height: 10 * s),
        if (twoLine) ...[
          SizedBox(
            height: 24 * s,
            child: Row(
              children: [
                Text.rich(fig, maxLines: 1),
                const Spacer(),
                if (stamp != null) stamp,
              ],
            ),
          ),
          SizedBox(height: 4 * s),
          Text.rich(missionMonoSpan(name, nameStyle),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ] else
          SizedBox(
            height: 28 * s,
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      fig,
                      missionMonoSpan(' — $name', nameStyle),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (stamp != null) ...[SizedBox(width: 12 * s), stamp],
              ],
            ),
          ),
      ],
    );
  }
}

/// "FIGS. 1A–1D — ROUTES TO ONE SCALE." with the privacy line, then the
/// symbol key.
class _FiguresCaption extends StatelessWidget {
  const _FiguresCaption({required this.comparison, required this.scale});

  final ThemedComparison comparison;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final route0 = comparison.routes.first;
    final n = comparison.routes.length;
    final hide = route0.hideRadiusM;
    final where = route0.origin == ReportOrigin.base ? 'base' : 'start';
    final detail = [
      'Scale bar in Fig. 1A.',
      'Tracks rotated; no coordinates.',
      if (route0.origin != ReportOrigin.none && hide > 0)
        'Readings within ${reportDistance(hide, comparison.miles)} '
            'of the $where withheld.',
    ].join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(children: [
            missionMonoSpan('FIGS. 1A\u20131${_letter(n - 1)}',
                missionMono(17 * s, color: MissionInk.red, bold: true)),
            missionMonoSpan(' \u2014 ROUTES TO ONE SCALE. ',
                missionMono(17 * s, bold: true)),
            TextSpan(
                text: detail,
                style:
                    missionSans(17 * s, italic: true, color: MissionInk.soft)),
          ]),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 10 * s),
        _Key(scale: s),
      ],
    );
  }
}

/// A small double-ruled "BEST" box in the spot red, set a little askew
/// like a rubber stamp.
class _BestStamp extends StatelessWidget {
  const _BestStamp({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Transform.rotate(
      angle: -0.05,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: MissionInk.red, width: 2.2 * s),
        ),
        padding: EdgeInsets.all(2 * s),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: MissionInk.red, width: 0.8 * s),
          ),
          padding: EdgeInsets.symmetric(horizontal: 8 * s),
          child: Text('BEST',
              style: missionMono(14 * s,
                      color: MissionInk.red, bold: true, spacing: 3 * s)
                  .copyWith(height: 1.15)),
        ),
      ),
    );
  }
}

/// KEY: the four plot symbols.
class _Key extends StatelessWidget {
  const _Key({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final style = missionMono(15 * s, color: MissionInk.soft);
    return Wrap(
      spacing: 22 * s,
      runSpacing: 6 * s,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('KEY',
            style: missionMono(15 * s, color: MissionInk.red, bold: true)),
        for (final (band, text) in [
          (MarginBand.strong, 'STRONG 20+'),
          (MarginBand.good, 'GOOD 10–20'),
          (MarginBand.weak, 'WEAK 0–10'),
          (MarginBand.below, 'BELOW LIMIT'),
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18 * s,
                height: 18 * s,
                child: CustomPaint(
                    painter:
                        MissionSymbolPainter(band.colourMarginDb, 7.5 * s)),
              ),
              SizedBox(width: 7 * s),
              Text(text, style: style),
            ],
          ),
        Text('dB above the decode limit',
            style: missionSans(15 * s, italic: true, color: MissionInk.soft)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Results table.

class _ResultsTable extends StatelessWidget {
  const _ResultsTable(
      {required this.comparison, required this.scale, this.compact = false});

  final ThemedComparison comparison;
  final double scale;
  final bool compact;

  static const _settingLabels = {
    'Range': 'RANGE SETTING',
    'Power': 'TX POWER',
    'Freq': 'FREQUENCY',
    'Mobile': 'MOBILE NODE',
    'Base': 'BASE NODE',
  };

  static const _commonLabels = {
    'Range': 'range setting',
    'Power': 'TX power',
    'Freq': 'frequency',
    'Mobile': 'mobile node',
    'Base': 'base node',
  };

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final d = comparison.data;
    final miles = comparison.miles;
    final sides = [for (final x in d.sides) x.data];
    final n = sides.length;

    String dist(double m) => reportDistance(m, miles).toUpperCase();
    final anyFallback = sides.any((x) => x.farthestM == null);
    final rows = <_Row>[
      _Row(
        compact ? 'FARTHEST HEARD' : 'FARTHEST POINT HEARD',
        [
          for (final x in sides)
            x.farthestM != null ? dist(x.farthestM!) : '${dist(x.routeM)}*'
        ],
        _best([for (final x in sides) x.farthestM], (v) => dist(v)),
      ),
      _Row(
        'MEDIAN MARGIN',
        [
          for (final x in sides)
            x.medianMarginDb == null ? '—' : reportDb(x.medianMarginDb!)
        ],
        _best([for (final x in sides) x.medianMarginDb], reportDb),
      ),
      _Row(
        compact ? 'BASE HEARD' : 'BASE NODE HEARD',
        [
          for (final x in sides)
            x.baseHeardPct == null ? '—' : '${x.baseHeardPct}%'
        ],
        _best([for (final x in sides) x.baseHeardPct?.toDouble()],
            (v) => '${v.round()}%'),
      ),
      _Row(
          'READINGS', [for (final x in sides) '${x.samples.length}'], const {}),
    ];
    final setup = SideSetupList.rowsFor(sides);
    final differ = [
      for (final (label, values) in setup)
        if (values.toSet().length > 1)
          _Row(_settingLabels[label] ?? label.toUpperCase(),
              [for (final v in values) v.isEmpty ? '—' : v], const {},
              setting: true),
    ];
    final common = [
      for (final (label, values) in setup)
        if (values.toSet().length == 1)
          '${_commonLabels[label] ?? label} ${values.first}',
    ];
    final notes = [
      if (anyFallback) '* Route length; no farthest point could be given.',
      if (common.isNotEmpty) 'Same for all: ${common.join('; ')}.',
    ];

    return LayoutBuilder(builder: (context, box) {
      // Wide enough for the longest label and a few leader dots.
      var longest = 0.0;
      for (final r in [...rows, ...differ]) {
        final tp = TextPainter(
          text: TextSpan(text: r.label, style: missionMono(18 * s)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        longest = math.max(longest, tp.width);
        tp.dispose();
      }
      final labelW = math.min(box.maxWidth * 0.42,
          math.max(box.maxWidth * (n <= 2 ? 0.34 : 0.26), longest + 40 * s));
      final colW = (box.maxWidth - labelW) / n;
      final names = colW >= 230 * s;
      final valueStyle = missionSans(20 * s);
      final bestStyle = missionSans(20 * s, bold: true);

      Widget cell(int i, Widget child) => Container(
            width: colW,
            color: d.winner == i
                ? MissionInk.red.withValues(alpha: 0.07)
                : Colors.transparent,
            padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 6 * s),
            alignment: Alignment.center,
            child: child,
          );

      Widget labelCell(String text, {bool dots = true}) => SizedBox(
            width: labelW,
            child: Row(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: labelW - 16 * s),
                  child: Text(text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: missionMono(18 * s)),
                ),
                if (dots) ...[
                  SizedBox(width: 6 * s),
                  Expanded(
                    child: Text('.' * 80,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: missionMono(18 * s, color: MissionInk.faint)),
                  ),
                ],
              ],
            ),
          );

      Widget value(_Row row, int i) {
        final best = row.best.contains(i);
        final text = Text(row.values[i],
            maxLines: row.setting ? 2 : 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: row.setting
                ? missionSans(16 * s)
                : (best ? bestStyle : valueStyle));
        if (!best) return text;
        // Best in the row: bold, a short red rule under it.
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            text,
            SizedBox(height: 2 * s),
            Container(width: 46 * s, height: 2.5 * s, color: MissionInk.red),
          ],
        );
      }

      Widget tableRow(_Row row) => IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                labelCell(row.label),
                for (var i = 0; i < n; i++) cell(i, value(row, i)),
              ],
            ),
          );

      final head = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: labelW,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('CONFIGURATION',
                    style: missionMono(15 * s,
                        color: MissionInk.soft, spacing: 1 * s)),
              ),
            ),
            for (var i = 0; i < n; i++)
              cell(
                i,
                Text.rich(
                  TextSpan(children: [
                    missionMonoSpan(_letter(i),
                        missionMono(19 * s, color: MissionInk.red, bold: true)),
                    if (names)
                      missionMonoSpan('  ${d.sides[i].name}',
                          missionMono(17 * s, bold: true)),
                  ]),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          MissionSectionLabel('TABLE 1', 'RESULTS BY CONFIGURATION', scale: s),
          head,
          Container(height: 1.5, color: MissionInk.ink),
          for (final r in rows) tableRow(r),
          if (differ.isNotEmpty) ...[
            Container(height: 1, color: MissionInk.faint),
            for (final r in differ) tableRow(r),
          ],
          Container(height: 1.5, color: MissionInk.ink),
          for (final t in notes)
            Padding(
              padding: EdgeInsets.only(top: 6 * s),
              child: Text(t,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: missionSans(15 * s,
                      italic: true, color: MissionInk.soft)),
            ),
        ],
      );
    });
  }

  /// Indices holding the row's best (largest) value, by what the card
  /// shows; none when fewer than two sides have one or all show the same.
  static Set<int> _best(List<double?> values, String Function(double) show) {
    final known = values.whereType<double>().toList();
    if (known.length < 2) return const {};
    final top = show(known.reduce(math.max));
    final idx = {
      for (var i = 0; i < values.length; i++)
        if (values[i] != null && show(values[i]!) == top) i,
    };
    return idx.length == values.length ? const {} : idx;
  }
}

class _Row {
  const _Row(this.label, this.values, this.best, {this.setting = false});
  final String label;
  final List<String> values;
  final Set<int> best;

  /// A radio setting that differs between sides (smaller, no best).
  final bool setting;
}
