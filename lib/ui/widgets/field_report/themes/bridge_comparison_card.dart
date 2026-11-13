// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../report_painters.dart';
import '../report_parts.dart' show SideSetupList;
import '../report_style.dart';
import '../report_theme.dart';
import 'bridge_card.dart';

/// The Bridge look of a comparison Field Report
/// (docs/design/field-report/themes.md): the result as a bracketed
/// readout, then one bracketed panel per setup (lettered A to D), each
/// with its route on a scanner that shares one scale with the others,
/// farthest heard, median margin, base heard and the settings that differ
/// between setups. Settings every setup shared go on one line under the
/// result. The winner's panel has pale brackets and a WINNER tag.
class BridgeComparisonCard extends StatelessWidget {
  const BridgeComparisonCard({super.key, required this.comparison});

  final ThemedComparison comparison;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: comparison.format.size,
      child: ColoredBox(
        color: BridgeColors.bg,
        child: switch (comparison.format) {
          ReportFormat.feed => _feed(),
          ReportFormat.story => _story(),
          ReportFormat.wide => _wide(),
        },
      ),
    );
  }

  int get _n => comparison.data.sides.length;

  String get _date => DateFormat('yyyy-MM-dd', 'en_US')
      .format(comparison.data.startedAt.toLocal());

  Widget _header(double s) =>
      BridgeHeader(info: 'SURVEY $_date', tag: '$_n SETUPS', s: s);

  Widget _feed() {
    const s = 1.0;
    final many = _n > 2;
    final ps = many ? 0.82 : 1.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 36, 36, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 58, child: _header(s)),
          const SizedBox(height: 14),
          SizedBox(
            height: 82,
            child: BridgeTitle(
                title: comparison.title, subtitle: 'Setup comparison', s: s),
          ),
          const SizedBox(height: 14),
          IntrinsicHeight(
              child: BridgeSection(
            code: 'RSLT',
            color: BridgeColors.pale,
            s: s,
            child: _Result(comparison: comparison, s: s),
          )),
          const SizedBox(height: 14),
          Expanded(
            child: BridgeSection(
              code: 'SCAN',
              color: BridgeColors.teal,
              s: s,
              child: _grid(
                columns: 2,
                gap: 14,
                panel: (i) => _SidePanel(
                  comparison: comparison,
                  index: i,
                  s: ps,
                  dot: many ? 6 : 8,
                  layout: _PanelLayout.column,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const SizedBox(height: 34, child: BridgeFooter(s: s)),
        ],
      ),
    );
  }

  Widget _story() {
    const s = 1.0;
    final many = _n > 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 44, 40, 38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 62, child: _header(s)),
          const SizedBox(height: 16),
          SizedBox(
            height: 88,
            child: BridgeTitle(
                title: comparison.title, subtitle: 'Setup comparison', s: s),
          ),
          const SizedBox(height: 18),
          IntrinsicHeight(
              child: BridgeSection(
            code: 'RSLT',
            color: BridgeColors.pale,
            s: s,
            child: _Result(comparison: comparison, s: s, lines: 3),
          )),
          const SizedBox(height: 18),
          Expanded(
            child: BridgeSection(
              code: 'SCAN',
              color: BridgeColors.teal,
              s: s,
              // Two setups side by side; more in rows, one per setup.
              child: _grid(
                columns: many ? 1 : 2,
                gap: 16,
                panel: (i) => _SidePanel(
                  comparison: comparison,
                  index: i,
                  s: many ? 0.86 : 1.0,
                  dot: many ? 7 : 9,
                  layout: many ? _PanelLayout.row : _PanelLayout.column,
                  statsH: 136,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const SizedBox(height: 36, child: BridgeFooter(s: s)),
        ],
      ),
    );
  }

  Widget _wide() {
    const s = 0.8;
    final many = _n > 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 46, child: _header(s)),
          const SizedBox(height: 12),
          Expanded(
            child: BridgeSection(
              code: 'SCAN',
              color: BridgeColors.teal,
              s: s,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 350,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(comparison.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: bridgeSans(30 * s, bold: true)
                                .copyWith(height: 1.1)),
                        const SizedBox(height: 4),
                        Text('SETUP COMPARISON',
                            maxLines: 1,
                            style: bridgeMono(bridgeSmall(19, s),
                                color: BridgeColors.teal, spacing: 2.5 * s)),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _Result(
                              comparison: comparison,
                              s: s,
                              lines: 4,
                              fill: true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _grid(
                      columns: 2,
                      gap: 10,
                      panel: (i) => _SidePanel(
                        comparison: comparison,
                        index: i,
                        s: many ? 0.66 : 0.8,
                        dot: many ? 5 : 6,
                        layout: many ? _PanelLayout.stack : _PanelLayout.column,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 28, child: BridgeFooter(s: s)),
        ],
      ),
    );
  }

  /// The side panels, [columns] across, as many rows as needed; a missing
  /// cell (three sides in two columns) stays empty.
  Widget _grid({
    required int columns,
    required double gap,
    required Widget Function(int) panel,
  }) {
    final n = _n;
    final cols = math.min(columns, n);
    final rows = (n + cols - 1) ~/ cols;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) SizedBox(height: gap),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < cols; c++) ...[
                  if (c > 0) SizedBox(width: gap),
                  Expanded(
                    child: r * cols + c < n
                        ? panel(r * cols + c)
                        : const SizedBox(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Settings rows (label, value per side) from [SideSetupList.rowsFor]:
/// the ones that differ between sides, and the ones every side shared.
({List<(String, List<String>)> differ, List<(String, String)> shared})
    _setupRows(ThemedComparison c) {
  final rows = SideSetupList.rowsFor([for (final s in c.data.sides) s.data]);
  return (
    differ: [
      for (final r in rows)
        if (r.$2.toSet().length > 1) r,
    ],
    shared: [
      for (final r in rows)
        if (r.$2.toSet().length == 1) (r.$1, r.$2.first),
    ],
  );
}

/// The result readout: verdict (guided tests), the win line, the note and
/// the settings every setup shared.
class _Result extends StatelessWidget {
  const _Result(
      {required this.comparison,
      required this.s,
      this.lines = 2,
      this.fill = false});

  final ThemedComparison comparison;
  final double s;
  final int lines;

  /// Spread over the height it is given (wide).
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final c = comparison;
    final tie = c.data.winner == null;
    final shared = _setupRows(c).shared;
    final sharedLine = shared.isEmpty
        ? null
        : Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: 'SAME ON ALL  ',
                  style: bridgeMono(bridgeSmall(15, s),
                      color: BridgeColors.dim, bold: true, spacing: 1 * s)),
              for (var i = 0; i < shared.length; i++) ...[
                if (i > 0)
                  TextSpan(
                      text: '  ·  ',
                      style: bridgeSans(bridgeSmall(17, s),
                          color: BridgeColors.line)),
                TextSpan(
                    text: '${shared[i].$1.toUpperCase()} ',
                    style: bridgeMono(bridgeSmall(15, s),
                        color: BridgeColors.dim)),
                TextSpan(
                    text: shared[i].$2,
                    style: bridgeSans(bridgeSmall(17, s),
                        color: BridgeColors.white, bold: true)),
              ],
            ]),
            maxLines: fill ? 3 : 1,
            overflow: TextOverflow.ellipsis,
          );
    final verdict = c.data.verdict;
    return BridgeReadout(
      s: s,
      accent: BridgeColors.pale,
      padding: EdgeInsets.fromLTRB(20 * s, 16 * s, 20 * s, 16 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          BridgeTag(tie ? 'RESULT · NO CLEAR WINNER' : 'RESULT', s: s),
          SizedBox(height: 12 * s),
          if (verdict != null) ...[
            Text(verdict,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: bridgeSans(30 * s, bold: true).copyWith(height: 1.15)),
            SizedBox(height: 6 * s),
          ],
          Text(c.winLine,
              maxLines: lines,
              overflow: TextOverflow.ellipsis,
              style: bridgeSans(verdict == null ? 32 * s : 25 * s,
                      color: BridgeColors.teal, bold: verdict == null)
                  .copyWith(height: 1.18)),
          if (c.note != null) ...[
            SizedBox(height: 8 * s),
            Text(c.note!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: bridgeSans(bridgeSmall(18, s), color: BridgeColors.dim)),
          ],
          if (fill) Expanded(child: _Bars(comparison: c, s: s)),
          if (sharedLine != null) ...[
            SizedBox(height: 12 * s),
            Container(height: 1.5, color: BridgeColors.line),
            SizedBox(height: 10 * s),
            sharedLine,
          ],
        ],
      ),
    );
  }
}

/// Every setup as a segmented bar: farthest heard when every setup has
/// one, else median margin; nothing when neither is known for all. Shown
/// only when there is room for it (wide).
class _Bars extends StatelessWidget {
  const _Bars({required this.comparison, required this.s});

  final ThemedComparison comparison;
  final double s;

  static const _segments = 16;

  @override
  Widget build(BuildContext context) {
    final c = comparison;
    final data = [for (final x in c.data.sides) x.data];
    final List<double> values;
    final String title;
    final String Function(double) text;
    if (data.every((d) => d.farthestM != null)) {
      values = [for (final d in data) d.farthestM!];
      title = 'FARTHEST HEARD';
      text = (v) => reportDistance(v, c.miles);
    } else if (data.every((d) => d.medianMarginDb != null)) {
      values = [for (final d in data) d.medianMarginDb!];
      title = 'MEDIAN MARGIN';
      text = reportDb;
    } else {
      return const SizedBox();
    }
    final lo = math.min(0.0, values.reduce(math.min));
    final hi = values.reduce(math.max);
    final rowH = 34 * s;
    final need = 30 * s + values.length * rowH;
    return LayoutBuilder(builder: (context, box) {
      if (box.maxHeight < need) return const SizedBox();
      return Align(
        alignment: Alignment.center,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: bridgeMono(bridgeSmall(15, s),
                    color: BridgeColors.dim, bold: true, spacing: 1 * s)),
            SizedBox(height: 8 * s),
            for (var i = 0; i < values.length; i++)
              SizedBox(
                height: rowH,
                child: Row(
                  children: [
                    SizedBox(
                      width: 26 * s,
                      child: Text(String.fromCharCode(65 + i),
                          style: bridgeMono(bridgeSmall(18, s),
                              color: c.data.winner == i
                                  ? BridgeColors.pale
                                  : BridgeColors.steel,
                              bold: true)),
                    ),
                    Expanded(
                      child: SizedBox(
                        height: 16 * s,
                        child: Row(
                          children: [
                            for (var k = 0; k < _segments; k++)
                              Expanded(
                                child: Container(
                                  margin: EdgeInsets.only(right: 3 * s),
                                  color: k <
                                          math.max(
                                              1,
                                              ((values[i] - lo) /
                                                      math.max(1e-9, hi - lo) *
                                                      _segments)
                                                  .round())
                                      ? (c.data.winner == i
                                          ? BridgeColors.pale
                                          : BridgeColors.steel)
                                      : BridgeColors.unlit,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 92 * s,
                      child: Text(text(values[i]),
                          maxLines: 1,
                          textAlign: TextAlign.right,
                          style: bridgeSans(bridgeSmall(20, s), bold: true)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    });
  }
}

enum _PanelLayout {
  /// Scanner on top, readouts in a row under it.
  column,

  /// Scanner on the left, the distance and under it the other two side
  /// by side on its right.
  row,

  /// Scanner on the left, the three readouts in a column on its right.
  stack,
}

/// One setup: letter, name, WINNER tag, scanner and readouts.
class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.comparison,
    required this.index,
    required this.s,
    required this.dot,
    required this.layout,
    this.statsH = 112,
  });

  final ThemedComparison comparison;
  final int index;
  final double s, dot;
  final _PanelLayout layout;

  /// Height of the readout row under the scanner (column layout).
  final double statsH;

  @override
  Widget build(BuildContext context) {
    final c = comparison;
    final side = c.data.sides[index];
    final d = side.data;
    final win = c.data.winner == index;
    final accent = win ? BridgeColors.pale : BridgeColors.steel;
    final far = d.farthestM;
    final pct = d.baseHeardPct;
    final differ = _setupRows(c).differ;

    final name = SizedBox(
      height: 44 * s,
      child: Row(
        children: [
          _Letter(String.fromCharCode(65 + index), color: accent, s: s),
          SizedBox(width: 12 * s),
          Expanded(
            child: Text(side.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: bridgeSans(28 * s, bold: true)),
          ),
          if (win) ...[
            SizedBox(width: 10 * s),
            BridgeTag('WINNER', s: s),
          ],
        ],
      ),
    );

    final scanner = BridgeScanner(
      route: c.routes[index],
      frame: RouteFrame.of(c.routes),
      miles: c.miles,
      dot: dot,
      s: s,
      scaleBar: index == 0,
      accent: win ? BridgeColors.pale : BridgeColors.teal,
    );

    final labelLines = layout == _PanelLayout.stack ? 1 : 2;
    final distance = BridgeStat(
      labelLines: labelLines,
      label: far == null ? 'ROUTE LENGTH' : 'FARTHEST HEARD',
      value: reportDistance(far ?? d.routeM, c.miles),
      s: s,
      accent: accent,
      valueSize: layout == _PanelLayout.row ? 66 : 52,
      valueColor: win ? BridgeColors.teal : BridgeColors.white,
    );
    final margin = BridgeStat(
      label: 'MEDIAN MARGIN',
      labelLines: labelLines,
      value: d.medianMarginDb == null ? '-' : reportDb(d.medianMarginDb!),
      s: s,
      valueSize: layout == _PanelLayout.row ? 46 : 36,
    );
    final heard = BridgeStat(
      label: 'BASE HEARD',
      labelLines: labelLines,
      value: pct == null ? '-' : '$pct%',
      s: s,
      valueSize: layout == _PanelLayout.row ? 46 : 36,
    );
    final setup =
        differ.isEmpty ? null : _DiffRows(rows: differ, index: index, s: s);

    final body = switch (layout) {
      _PanelLayout.column => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: scanner),
            SizedBox(height: 10 * s),
            SizedBox(
              height: statsH * s,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 4, child: distance),
                  SizedBox(width: 8 * s),
                  Expanded(flex: 3, child: margin),
                  SizedBox(width: 8 * s),
                  Expanded(flex: 3, child: heard),
                ],
              ),
            ),
            if (setup != null) ...[SizedBox(height: 8 * s), setup],
          ],
        ),
      _PanelLayout.row => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 11, child: scanner),
            SizedBox(width: 12 * s),
            Expanded(
              flex: 9,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 5, child: distance),
                  SizedBox(height: 8 * s),
                  Expanded(
                    flex: 4,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: margin),
                        SizedBox(width: 8 * s),
                        Expanded(child: heard),
                      ],
                    ),
                  ),
                  if (setup != null) ...[SizedBox(height: 8 * s), setup],
                ],
              ),
            ),
          ],
        ),
      _PanelLayout.stack => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: scanner),
            SizedBox(width: 10 * s),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 7, child: distance),
                  SizedBox(height: 6 * s),
                  Expanded(flex: 6, child: margin),
                  SizedBox(height: 6 * s),
                  Expanded(flex: 6, child: heard),
                ],
              ),
            ),
          ],
        ),
    };

    return CustomPaint(
      foregroundPainter: _FramePainter(accent, s, win),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14 * s, 12 * s, 14 * s, 14 * s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            name,
            SizedBox(height: 8 * s),
            Expanded(child: body),
            if (layout == _PanelLayout.stack && setup != null) ...[
              SizedBox(height: 8 * s),
              setup,
            ],
          ],
        ),
      ),
    );
  }
}

/// The settings that differ between setups, this side's value in pale.
/// Scales down when the panel is short.
class _DiffRows extends StatelessWidget {
  const _DiffRows({required this.rows, required this.index, required this.s});

  final List<(String, List<String>)> rows;
  final int index;
  final double s;

  @override
  Widget build(BuildContext context) {
    final size = bridgeSmall(19, s);
    final rowH = size * 1.25 + 4 * s;
    final shown = math.min(rows.length, 3);
    return SizedBox(
      height: shown * rowH,
      child: BridgeFitColumn(
        children: [
          for (final (label, values) in rows)
            SizedBox(
              height: rowH,
              child: Row(
                children: [
                  SizedBox(
                    width: math.max(92 * s, 72),
                    child: Text(label.toUpperCase(),
                        maxLines: 1,
                        style: bridgeMono(bridgeSmall(15, s),
                            color: BridgeColors.dim, spacing: 1 * s)),
                  ),
                  Expanded(
                    child: Text(values[index].isEmpty ? '-' : values[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: bridgeSans(size,
                            color: BridgeColors.pale, bold: true)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A setup's letter in a small outlined square.
class _Letter extends StatelessWidget {
  const _Letter(this.letter, {required this.color, required this.s});

  final String letter;
  final Color color;
  final double s;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34 * s,
      height: 34 * s,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
      ),
      child: Text(letter,
          style: bridgeMono(bridgeSmall(20, s), color: color, bold: true)),
    );
  }
}

/// A panel's frame: a hairline box and corner brackets; the winner's are
/// longer and pale, with a tick run along its top edge.
class _FramePainter extends CustomPainter {
  _FramePainter(this.color, this.s, this.win);

  final Color color;
  final double s;
  final bool win;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect.deflate(0.75),
        Paint()
          ..color = BridgeColors.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    bridgeBrackets(
        canvas,
        rect,
        (win ? 40 : 22) * s,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = (win ? 4 : 3) * s
          ..strokeCap = StrokeCap.square);
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.color != color || old.s != s || old.win != win;
}
