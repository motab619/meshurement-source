// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../services/field_report/comparison_report_data.dart';
import '../report_painters.dart';
import '../report_parts.dart';
import '../report_style.dart';
import '../report_theme.dart';
import 'basic_card.dart';

/// The Basic look of a comparison Field Report
/// (docs/design/field-report/themes.md): light paper, the result in words
/// first, then one block per setup with its route (all on one shared
/// frame, so the scales match), how far it was heard, median margin and
/// base heard. Settings show only where the setups differ, and not in
/// wide.
///
/// The setups sit side by side, two by two (four in feed or story) or
/// stacked as rows (story), whichever draws the shared frame biggest.
class BasicComparisonCard extends StatelessWidget {
  const BasicComparisonCard({super.key, required this.comparison});

  final ThemedComparison comparison;

  ComparisonReportData get _d => comparison.data;
  int get _n => _d.sides.length;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
        size: comparison.format.size,
        child: ColoredBox(
          color: BasicStyle.paper,
          child: switch (comparison.format) {
            ReportFormat.feed => _feed(),
            ReportFormat.story => _story(),
            ReportFormat.wide => _wide(),
          },
        ),
      );

  String get _subtitle => '$_n setups compared';

  Widget _feed() => Padding(
        padding: const EdgeInsets.fromLTRB(72, 72, 72, 52),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BasicHeader(
                title: comparison.title,
                subtitle: _subtitle,
                scale: 0.9,
                titleLines: 1),
            const SizedBox(height: 36),
            _Result(comparison: comparison, scale: 1),
            const SizedBox(height: 40),
            Expanded(
                child: _Sides(comparison: comparison, layouts: [
              _Arrangement(_Place.columns,
                  s: switch (_n) { 2 => 1.0, 3 => 0.78, _ => 0.66 },
                  gap: _n == 2 ? 48 : 30),
              if (_n == 4)
                const _Arrangement(_Place.grid, s: 0.8, gap: 40, rowGap: 36),
              if (_n < 4)
                _Arrangement(_Place.stack,
                    s: _n == 2 ? 0.95 : 0.8, rowGap: 32, across: true),
            ])),
            ..._note(1),
            const SizedBox(height: 32),
            const BasicFooter(scale: 1),
          ],
        ),
      );

  Widget _story() => Padding(
        padding: const EdgeInsets.fromLTRB(84, 120, 84, 84),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BasicHeader(
                title: comparison.title, subtitle: _subtitle, scale: 1.1),
            const SizedBox(height: 56),
            _Result(comparison: comparison, scale: 1.15, lines: 3),
            const SizedBox(height: 60),
            Expanded(
                child: _Sides(comparison: comparison, layouts: [
              _Arrangement(_Place.columns,
                  s: switch (_n) { 2 => 1.1, 3 => 0.82, _ => 0.68 },
                  gap: _n == 2 ? 52 : 32),
              if (_n == 4) ...[
                const _Arrangement(_Place.grid, s: 0.92, gap: 44, rowGap: 52),
                const _Arrangement(_Place.grid,
                    s: 0.8, gap: 44, rowGap: 56, across: true),
              ],
              _Arrangement(_Place.stack,
                  s: switch (_n) { 2 => 1.1, 3 => 1.0, _ => 0.9 },
                  rowGap: 40,
                  across: true),
            ])),
            ..._note(1.1),
            const SizedBox(height: 52),
            const BasicFooter(scale: 1.1),
          ],
        ),
      );

  /// Wide: one row of every setup under a compact header; settings
  /// differences are dropped (no room), the numbers stay.
  Widget _wide() => Padding(
        padding: const EdgeInsets.fromLTRB(52, 40, 52, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: BasicHeader(
                      title: comparison.title,
                      subtitle: '',
                      scale: 0.66,
                      titleLines: 1),
                ),
                const SizedBox(width: 40),
                Expanded(
                  flex: 7,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _Result(comparison: comparison, scale: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Expanded(
                child:
                    _Sides(comparison: comparison, showSetup: false, layouts: [
              _Arrangement(_Place.columns,
                  s: switch (_n) { 2 => 0.72, 3 => 0.62, _ => 0.56 },
                  gap: _n == 2 ? 48 : 28,
                  compact: true),
              if (_n < 4)
                _Arrangement(_Place.columns,
                    s: _n == 2 ? 0.66 : 0.56,
                    gap: _n == 2 ? 48 : 32,
                    across: true),
            ])),
            ..._note(0.66, maxLines: 1),
            const SizedBox(height: 16),
            const BasicFooter(scale: 0.66),
          ],
        ),
      );

  List<Widget> _note(double s, {int maxLines = 2}) => [
        if (comparison.note != null) ...[
          SizedBox(height: 28 * s),
          Text(comparison.note!,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: BasicStyle.sans(21 * s, color: BasicStyle.soft)),
        ],
      ];
}

/// The result in words: the guided test's verdict (bold) when there was
/// one, then the win line.
class _Result extends StatelessWidget {
  const _Result(
      {required this.comparison, required this.scale, this.lines = 2});

  final ThemedComparison comparison;
  final double scale;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final verdict = comparison.data.verdict;
    return Container(
      padding: EdgeInsets.only(left: 22 * s),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: BasicStyle.ink, width: 6 * s)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (verdict != null) ...[
            Text(verdict,
                maxLines: lines,
                overflow: TextOverflow.ellipsis,
                style: BasicStyle.sans(34 * s, bold: true)),
            SizedBox(height: 8 * s),
          ],
          Text(comparison.winLine,
              maxLines: lines,
              overflow: TextOverflow.ellipsis,
              style: verdict == null
                  ? BasicStyle.sans(32 * s, bold: true)
                  : BasicStyle.sans(28 * s, color: BasicStyle.soft)),
        ],
      ),
    );
  }
}

enum _Place { columns, grid, stack }

/// One way to place the setups: side by side, two by two or stacked;
/// each setup a column (name, route, numbers) or, [across], a row (route
/// left, numbers right).
class _Arrangement {
  const _Arrangement(this.place,
      {required this.s,
      this.gap = 0,
      this.rowGap = 0,
      this.across = false,
      this.compact = false});

  final _Place place;
  final double s, gap, rowGap;
  final bool across, compact;

  (int, int) cells(int n) => switch (place) {
        _Place.columns => (n, 1),
        _Place.grid => (2, 2),
        _Place.stack => (1, n),
      };
}

/// Height of a [BasicStat] at scale 1 (its natural 93.2 plus slack).
const _statH = 98.0;

/// Route padding inside each box: the dots reach closer to the edge than
/// on the single card, where the route has the space to itself.
const _routePad = 20.0;

/// Places the setups by the [layouts] candidate that draws the shared
/// frame at the largest scale (an earlier one wins a near tie), then
/// trims the route boxes to the height the drawing needs and centres the
/// block, so a tall narrow frame doesn't leave a void inside every box.
class _Sides extends StatelessWidget {
  const _Sides(
      {required this.comparison, required this.layouts, this.showSetup = true});

  final ThemedComparison comparison;
  final List<_Arrangement> layouts;
  final bool showSetup;

  int get _n => comparison.data.sides.length;

  _SideMetrics _metrics(_Arrangement a, double cellW, bool setup) =>
      _SideMetrics(a.s, compact: a.compact, setup: setup, stacked: cellW < 240);

  /// Size of one cell under [a] in [area].
  Size _cell(_Arrangement a, Size area) {
    final (c, r) = a.cells(_n);
    return Size((area.width - a.gap * (c - 1)) / c,
        (area.height - a.rowGap * (r - 1)) / r);
  }

  /// Height of a cell's fixed parts (everything but the route).
  double _overhead(_Arrangement a, double cellW, bool setup) =>
      a.across ? _SideRow.overhead(a.s) : _metrics(a, cellW, setup).overhead;

  Size _routeBox(_Arrangement a, Size cell, bool setup) => Size(
      a.across ? _SideRow.routeWidth(cell.width, a.s) : cell.width,
      cell.height - _overhead(a, cell.width, setup));

  @override
  Widget build(BuildContext context) {
    final frame = RouteFrame.of(comparison.routes);
    final diffs = showSetup ? _setupDiffs(comparison.data) : null;
    final setup = diffs != null;
    return LayoutBuilder(builder: (context, box) {
      final area = box.biggest;
      // Cell height a layout really uses once its route box is trimmed
      // to the drawing (plus a little air).
      double usedCellH(_Arrangement l, Size cell, double k) => math.min(
          cell.height,
          frame.height * k +
              2 * _routePad +
              BasicRoutePainter.scaleStrip +
              8 +
              _overhead(l, cell.width, setup));
      double blockH(_Arrangement l, double cellH) {
        final rows = l.cells(_n).$2;
        return cellH * rows + l.rowGap * (rows - 1);
      }

      // Score: drawing scale, nudged towards layouts that fill the space
      // rather than leave a band of empty paper.
      var a = layouts.first;
      var best = -1.0;
      for (final l in layouts) {
        final cell = _cell(l, area);
        final rb = _routeBox(l, cell, setup);
        if (rb.width <= 2 * _routePad || rb.height <= 80) continue;
        final k = BasicRoutePainter.scaleFor(frame, rb, pad: _routePad);
        final fill = blockH(l, usedCellH(l, cell, k)) / area.height;
        final score = k * math.sqrt(fill);
        if (score > best * 1.05) {
          a = l;
          best = score;
        }
      }
      final cell = _cell(a, area);
      final k = BasicRoutePainter.scaleFor(frame, _routeBox(a, cell, setup),
          pad: _routePad);
      final (cols, rows) = a.cells(_n);
      final block = blockH(a, usedCellH(a, cell, k));

      Widget side(int i) => a.across
          ? _SideRow(
              comparison: comparison,
              index: i,
              frame: frame,
              scale: a.s,
              setup: diffs?[i])
          : _Side(
              comparison: comparison,
              index: i,
              frame: frame,
              metrics: _metrics(a, cell.width, setup),
              setup: diffs?[i]);

      return Align(
        alignment: Alignment.center,
        child: SizedBox(
          height: block,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) SizedBox(height: a.rowGap),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < cols; c++) ...[
                        if (c > 0) SizedBox(width: a.gap),
                        Expanded(
                            child: r * cols + c < _n
                                ? side(r * cols + c)
                                : const SizedBox.shrink()),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }

  /// Per side, the settings that differ between the setups ("Range Long
  /// Fast  ·  Power 22 dBm"), or null when they all match (or nothing was
  /// recorded).
  static List<String>? _setupDiffs(ComparisonReportData d) {
    final rows = [
      for (final r in SideSetupList.rowsFor([for (final s in d.sides) s.data]))
        if (r.$2.toSet().length > 1) r,
    ];
    if (rows.isEmpty) return null;
    return [
      for (var i = 0; i < d.sides.length; i++)
        [
          for (final (label, values) in rows)
            '$label ${values[i].isEmpty ? '-' : values[i]}'
        ].join('  ·  '),
    ];
  }
}

/// Name and the WINNER tag over a rule (heavy ink for the winner).
class _SideName extends StatelessWidget {
  const _SideName({required this.name, required this.win, required this.scale});

  final String name;
  final bool win;
  final double scale;

  static double height(double s) => 5 + 16 * s + 40 * s;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 5,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
                height: win ? 5 : 1.5,
                color: win ? BasicStyle.ink : BasicStyle.rule),
          ),
        ),
        SizedBox(height: 16 * s),
        SizedBox(
          height: 40 * s,
          child: Row(
            children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: BasicStyle.sans(32 * s, bold: true)),
              ),
              if (win) ...[
                SizedBox(width: 12 * s),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
                  color: BasicStyle.ink,
                  child: Text('WINNER',
                      style: BasicStyle.label(math.max(15 * s, 11),
                              color: BasicStyle.paper)
                          .copyWith(height: 1.0)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Farthest heard (route length when no distance from the base), with
/// its caption.
(String, String) _headline(ThemedComparison c, int i) {
  final d = c.data.sides[i].data;
  final far = d.farthestM;
  return far == null
      ? (reportDistance(d.routeM, c.miles), 'Route length')
      : (reportDistance(far, c.miles), 'Farthest heard');
}

/// Sizes of the fixed parts of a [_Side]; the route takes the rest.
class _SideMetrics {
  const _SideMetrics(this.s,
      {required this.compact, required this.setup, required this.stacked});

  final double s;
  final bool compact, setup;

  /// Narrow column: margin and base heard one above the other.
  final bool stacked;

  /// Scale of the two small stats (kept legible in narrow columns).
  double get statScale => math.max(s * 0.82, 0.62);

  /// Height of one [BasicStat] at [statScale].
  double get statHeight => _statH * statScale;
  double get statsHeight => stacked ? 2 * statHeight + 14 * s : statHeight;

  double get belowName => 18 * s;
  double get afterRoute => (compact ? 8 : 24) * s;
  double get number => 76 * s;
  double get captionSize => math.max(16 * s, 12);
  double get caption => captionSize * 1.2;
  double get beforeRule => (compact ? 14 : 22) * s;
  double get afterRule => (compact ? 12 : 18) * s;
  double get setupLine => 21 * s * 1.2 * 2;

  double get overhead =>
      _SideName.height(s) +
      belowName +
      afterRoute +
      number +
      10 * s +
      caption +
      beforeRule +
      1.5 +
      afterRule +
      statsHeight +
      (setup ? 8 * s + setupLine : 0);
}

Widget _stat(String value, String label, double scale) => SizedBox(
      height: _statH * scale,
      child: BasicStat(value: value, label: label, scale: scale),
    );

Widget _setupText(String text, double s) => SizedBox(
      height: 21 * s * 1.2 * 2,
      child: Text(text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: BasicStyle.sans(21 * s, color: BasicStyle.soft)),
    );

Widget _route(ThemedComparison c, int index, RouteFrame frame,
        {required double dotRadius, double textScale = 1}) =>
    CustomPaint(
      size: Size.infinite,
      painter: BasicRoutePainter(
        route: c.routes[index],
        frame: frame,
        miles: c.miles,
        dotRadius: dotRadius,
        scaleBar: index == 0,
        textScale: textScale,
        pad: _routePad,
        dotPeers: c.routes,
      ),
    );

/// One setup as a column: name, route, big number, two small stats.
/// Every part but the route has a fixed height ([_SideMetrics]), so the
/// routes of a row get the same box and the shared frame the same scale.
class _Side extends StatelessWidget {
  const _Side({
    required this.comparison,
    required this.index,
    required this.frame,
    required this.metrics,
    required this.setup,
  });

  final ThemedComparison comparison;
  final int index;
  final RouteFrame frame;
  final _SideMetrics metrics;
  final String? setup;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final s = m.s;
    final c = comparison;
    final d = c.data.sides[index].data;
    final (value, caption) = _headline(c, index);
    final pct = d.baseHeardPct;
    final margin = _stat(
        d.medianMarginDb == null ? '-' : reportDb(d.medianMarginDb!),
        'Margin',
        m.statScale);
    final heard = _stat(pct == null ? '-' : '$pct%', 'Base heard', m.statScale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SideName(
            name: c.data.sides[index].name,
            win: c.data.winner == index,
            scale: s),
        SizedBox(height: m.belowName),
        Expanded(
          child: _route(c, index, frame,
              dotRadius: 5 + 3 * s, textScale: s.clamp(0.8, 1.0)),
        ),
        SizedBox(height: m.afterRoute),
        BasicBigNumber(value: value, size: m.number),
        SizedBox(height: 10 * s),
        SizedBox(
          height: m.caption,
          child: Text(caption.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BasicStyle.label(m.captionSize)),
        ),
        SizedBox(height: m.beforeRule),
        Container(height: 1.5, color: BasicStyle.rule),
        SizedBox(height: m.afterRule),
        SizedBox(
          height: m.statsHeight,
          child: m.stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [margin, SizedBox(height: 14 * s), heard],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: margin),
                    SizedBox(width: math.max(16 * s, 20)),
                    Expanded(child: heard),
                  ],
                ),
        ),
        if (m.setup) ...[
          SizedBox(height: 8 * s),
          _setupText(setup ?? '', s),
        ],
      ],
    );
  }
}

/// One setup as a row (story, when the shared frame is wide): the route
/// on the left, the numbers on the right.
class _SideRow extends StatelessWidget {
  const _SideRow({
    required this.comparison,
    required this.index,
    required this.frame,
    required this.scale,
    required this.setup,
  });

  final ThemedComparison comparison;
  final int index;
  final RouteFrame frame;
  final double scale;
  final String? setup;

  static const gapBelowName = 18.0;

  /// Height of the fixed parts (name block).
  static double overhead(double s) => _SideName.height(s) + gapBelowName * s;

  /// Width of the route box in a row [w] wide.
  static double routeWidth(double w, double s) => (w - 44 * s) * 0.56;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final c = comparison;
    final d = c.data.sides[index].data;
    final (value, caption) = _headline(c, index);
    final pct = d.baseHeardPct;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SideName(
            name: c.data.sides[index].name,
            win: c.data.winner == index,
            scale: s),
        SizedBox(height: gapBelowName * s),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: routeWidth(box.maxWidth, s),
                  child: _route(c, index, frame,
                      dotRadius: 5 + 3 * s, textScale: s.clamp(0.8, 1.0)),
                ),
                SizedBox(width: 44 * s),
                Expanded(
                  child: ScaleDownBox(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BasicBigNumber(value: value, size: 84 * s),
                        SizedBox(height: 10 * s),
                        Text(caption.toUpperCase(),
                            maxLines: 1, style: BasicStyle.label(16 * s)),
                        SizedBox(height: 22 * s),
                        Container(height: 1.5, color: BasicStyle.rule),
                        SizedBox(height: 18 * s),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _stat(
                                  d.medianMarginDb == null
                                      ? '-'
                                      : reportDb(d.medianMarginDb!),
                                  'Margin',
                                  s * 0.82),
                            ),
                            SizedBox(width: math.max(16 * s, 20)),
                            Expanded(
                              child: _stat(pct == null ? '-' : '$pct%',
                                  'Base heard', s * 0.82),
                            ),
                          ],
                        ),
                        if (setup != null) ...[
                          SizedBox(height: 8 * s),
                          _setupText(setup!, s),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
