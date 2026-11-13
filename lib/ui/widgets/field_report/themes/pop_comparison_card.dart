// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../services/field_report/field_report_data.dart';
import '../report_painters.dart';
import '../report_parts.dart';
import '../report_style.dart';
import '../report_theme.dart';
import 'pop_card.dart';

/// The Pop look of a comparison Field Report
/// (docs/design/field-report/themes.md): the result in a big violet
/// bubble, then one white card per setup with its own pastel name pill,
/// the winner ringed in violet and tagged with a pink WINNER star pill.
/// Every route sits on one shared frame, so the scales match.
class PopComparisonCard extends StatelessWidget {
  const PopComparisonCard({super.key, required this.comparison});

  final ThemedComparison comparison;

  static const _sideColors = [
    PopPalette.sky,
    PopPalette.pink,
    PopPalette.aqua,
    PopPalette.lilac,
  ];

  @override
  Widget build(BuildContext context) {
    final c = comparison;
    final n = c.data.sides.length;
    final frame = RouteFrame.of(c.routes);
    final rows = SideSetupList.rowsFor([for (final x in c.data.sides) x.data]);
    final shared = [
      for (final (label, values) in rows)
        if (values.toSet().length == 1) (label, values.first),
    ];
    final differing = [
      for (final r in rows)
        if (r.$2.toSet().length > 1) r,
    ];
    final body = switch (c.format) {
      ReportFormat.feed => _feed(n, frame, shared, differing),
      ReportFormat.story => _story(n, frame, shared, differing),
      ReportFormat.wide => _wide(n, frame, shared, differing),
    };
    return SizedBox.fromSize(
      size: c.format.size,
      child: ColoredBox(
        color: PopPalette.bg,
        child: Stack(
          children: [
            Positioned.fill(
                child: CustomPaint(painter: PopBackdropPainter(c.format))),
            Positioned.fill(child: body),
          ],
        ),
      ),
    );
  }

  String _subtitle(int n) => '$n setups compared';

  Widget _cell(int i, RouteFrame frame, List<(String, List<String>)> differing,
      {required bool horizontal, required double s, required double dot}) {
    final c = comparison;
    return _SideCard(
      name: c.data.sides[i].name,
      data: c.data.sides[i].data,
      color: _sideColors[i % _sideColors.length],
      winner: c.data.winner == i,
      route: PopRouteBlob(
        route: c.routes[i],
        frame: frame,
        miles: c.miles,
        dot: dot,
        scaleBar: i == 0,
        scale: s,
      ),
      miles: c.miles,
      differing: [for (final (label, values) in differing) (label, values[i])],
      horizontal: horizontal,
      scale: s,
    );
  }

  /// [n] cells in rows of [cols]; a short last row keeps the cell width.
  Widget _grid(int n, int cols, double gap, Widget Function(int) cell) {
    final rowCount = (n + cols - 1) ~/ cols;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row < rowCount; row++) ...[
          if (row > 0) SizedBox(height: gap),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var col = 0; col < cols; col++) ...[
                  if (col > 0) SizedBox(width: gap),
                  Expanded(
                    child: row * cols + col < n
                        ? cell(row * cols + col)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _feed(int n, RouteFrame frame, List<(String, String)> shared,
      List<(String, List<String>)> differing) {
    final c = comparison;
    final four = n > 3;
    final s = four ? 0.82 : (n == 3 ? 0.78 : 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(52, 46, 52, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PopHeader(title: c.title, subtitle: _subtitle(n)),
          const SizedBox(height: 26),
          _WinBubble(comparison: c, scale: 0.95),
          if (c.note != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: PopNoteLine(note: c.note!, maxLines: 2),
            ),
          ],
          if (shared.isNotEmpty) ...[
            const SizedBox(height: 18),
            _SharedPills(shared: shared),
          ],
          const SizedBox(height: 30),
          Expanded(
            child: _grid(
              n,
              four ? 2 : n,
              24,
              (i) => _cell(i, frame, differing,
                  horizontal: four, s: s, dot: four ? 5.5 : 6.5),
            ),
          ),
          const SizedBox(height: 16),
          const PopFooter(),
        ],
      ),
    );
  }

  Widget _story(int n, RouteFrame frame, List<(String, String)> shared,
      List<(String, List<String>)> differing) {
    final c = comparison;
    final four = n > 3;
    final s = four ? 0.9 : (n == 3 ? 0.86 : 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(60, 72, 60, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PopHeader(title: c.title, subtitle: _subtitle(n), scale: 1.05),
          const SizedBox(height: 34),
          _WinBubble(comparison: c, scale: 1.1),
          if (c.note != null) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: PopNoteLine(note: c.note!, scale: 1.1),
            ),
          ],
          if (shared.isNotEmpty) ...[
            const SizedBox(height: 22),
            _SharedPills(shared: shared, scale: 1.05),
          ],
          const SizedBox(height: 36),
          Expanded(
            child: _grid(
              n,
              four ? 2 : 1,
              28,
              (i) => _cell(i, frame, differing,
                  horizontal: !four, s: s, dot: four ? 6 : 7),
            ),
          ),
          const SizedBox(height: 20),
          const PopFooter(),
        ],
      ),
    );
  }

  Widget _wide(int n, RouteFrame frame, List<(String, String)> shared,
      List<(String, List<String>)> differing) {
    final c = comparison;
    final two = n == 2;
    final s = two ? 0.74 : (n == 3 ? 0.66 : 0.6);
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 28, 36, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 470,
                child: PopHeader(
                    title: c.title,
                    subtitle: _subtitle(n),
                    scale: 0.68,
                    stacked: true),
              ),
              const SizedBox(width: 24),
              Expanded(child: _WinBubble(comparison: c, scale: 0.62)),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _grid(
              n,
              n,
              16,
              (i) => _cell(i, frame, differing,
                  horizontal: two, s: s, dot: two ? 5.5 : 4.5),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: shared.isEmpty
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: _SharedPills(shared: shared, scale: 0.74),
                      ),
              ),
              const SizedBox(width: 16),
              const PopFooter(scale: 0.8),
            ],
          ),
        ],
      ),
    );
  }
}

/// The result: the guided test's verdict (when there was one) over the
/// win line, white on violet, after a star (winner) or two dots (a tie).
class _WinBubble extends StatelessWidget {
  const _WinBubble({required this.comparison, this.scale = 1});

  final ThemedComparison comparison;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final c = comparison;
    final verdict = c.data.verdict;
    final tie = c.data.winner == null;
    final wide = c.format == ReportFormat.wide;
    final note = c.note;
    final badge = Container(
      width: 78 * s,
      height: 78 * s,
      decoration:
          const BoxDecoration(color: PopPalette.white, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: tie
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                popDot(26 * s, PopPalette.sky),
                SizedBox(width: 4 * s),
                popDot(26 * s, PopPalette.pink),
              ],
            )
          : CustomPaint(
              size: Size.square(46 * s),
              painter: const _StarPainter(PopPalette.hot)),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(26 * s, 24 * s, 36 * s, 24 * s),
      decoration: BoxDecoration(
        color: PopPalette.violet,
        borderRadius: BorderRadius.circular(52 * s),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          badge,
          SizedBox(width: 24 * s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (verdict != null) ...[
                  Text(verdict,
                      maxLines: wide ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: PopPalette.sans(34 * s,
                          color: PopPalette.white, bold: true)),
                  SizedBox(height: 8 * s),
                ],
                Text(c.winLine,
                    maxLines: verdict == null ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: verdict == null
                        ? PopPalette.sans(36 * s,
                                color: PopPalette.white, bold: true)
                            .copyWith(height: 1.2)
                        : PopPalette.sans(26 * s,
                            color: PopPalette.white.withValues(alpha: 0.9))),
                if (note != null && wide) ...[
                  SizedBox(height: 10 * s),
                  Text(note,
                      maxLines: wide ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: PopPalette.sans((wide ? 24 : 21) * s,
                          color: PopPalette.white.withValues(alpha: 0.8))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings every side had in common, after an "All setups" label.
class _SharedPills extends StatelessWidget {
  const _SharedPills({required this.shared, this.scale = 1});

  final List<(String, String)> shared;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('All setups',
              style:
                  PopPalette.sans(22 * s, color: PopPalette.soft, bold: true)),
          for (final (label, value) in shared) ...[
            SizedBox(width: 12 * s),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 420 * s),
              child: PopTagPill(
                tag: label.toUpperCase(),
                value: value,
                color: PopPalette.white,
                scale: s * 0.9,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One setup: name pill, route, farthest heard, two stat bubbles and the
/// settings that differ from the other sides.
class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.name,
    required this.data,
    required this.color,
    required this.winner,
    required this.route,
    required this.miles,
    required this.differing,
    required this.horizontal,
    required this.scale,
  });

  final String name;
  final FieldReportData data;
  final Color color;
  final bool winner;
  final Widget route;
  final bool miles;

  /// (label, this side's value) for each setting that differs.
  final List<(String, String)> differing;

  /// Route left and stats right (a wide cell), else route over stats.
  final bool horizontal;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final namePill = Container(
      height: 54 * s,
      padding: EdgeInsets.symmetric(horizontal: 20 * s),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: winner ? PopPalette.violet : color,
        borderRadius: BorderRadius.circular(27 * s),
      ),
      child: Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PopPalette.sans(27 * s,
              bold: true, color: winner ? PopPalette.white : PopPalette.ink)),
    );
    final stats = _stats(s);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        namePill,
        SizedBox(height: 14 * s),
        Expanded(
          child: horizontal
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: route),
                    SizedBox(width: 18 * s),
                    SizedBox(
                      width: 300 * s,
                      child: ScaleDownBox(
                          alignment: Alignment.center, child: stats),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: route),
                    SizedBox(height: 16 * s),
                    stats,
                  ],
                ),
        ),
      ],
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: PopPanel(
            radius: 44 * s,
            rim: winner ? PopPalette.violet : PopPalette.lilac,
            rimWidth: winner ? 6 : 4,
            // The winner's thicker rim eats into the padding, so every
            // card's content lines up.
            padding: EdgeInsets.all(14 * s - (winner ? 2 : 0)),
            child: content,
          ),
        ),
        if (winner)
          Positioned(
            top: -24 * s,
            right: 10 * s,
            child: _WinnerBadge(scale: s),
          ),
      ],
    );
  }

  Widget _stats(double s) {
    final far = data.farthestM;
    final pct = data.baseHeardPct;
    final value = reportDistance(far ?? data.routeM, miles);
    // Small print never drops below a size that reads on a phone.
    double small(double size, double floor) => math.max(size * s, floor);
    final labelStyle =
        PopPalette.sans(small(17, 13.5), color: PopPalette.soft, bold: true)
            .copyWith(height: 1.0);
    Widget fit(Widget child, {Alignment align = Alignment.center}) =>
        FittedBox(fit: BoxFit.scaleDown, alignment: align, child: child);

    /// Value over label (a column cell), or value then label in one
    /// long pill (a wide cell, where the stats stack).
    Widget bubble(String v, String label, Color bg) {
      final valueText = Text(v.replaceAll(' ', '\u00A0'),
          maxLines: 1, style: PopPalette.number(32 * s));
      final labelText = Text(label, maxLines: 1, style: labelStyle);
      if (horizontal) {
        return Container(
          height: 62 * s,
          padding: EdgeInsets.symmetric(horizontal: 20 * s),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(31 * s),
          ),
          child: Row(
            children: [
              fit(valueText),
              SizedBox(width: 12 * s),
              Expanded(child: fit(labelText, align: Alignment.centerRight)),
            ],
          ),
        );
      }
      return Container(
        height: 84 * s,
        padding: EdgeInsets.symmetric(horizontal: 10 * s),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(42 * s),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            fit(valueText),
            SizedBox(height: 6 * s),
            fit(labelText),
          ],
        ),
      );
    }

    final margin = bubble(
        data.medianMarginDb == null ? '-' : reportDb(data.medianMarginDb!),
        'median margin',
        PopPalette.aqua);
    final heard =
        bubble(pct == null ? '-' : '$pct%', 'base heard', PopPalette.blush);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 6 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          fit(
            Text(value.replaceAll(' ', '\u00A0'),
                maxLines: 1,
                style: PopPalette.number(66 * s,
                    color: winner ? PopPalette.violet : PopPalette.ink)),
            align: Alignment.centerLeft,
          ),
          SizedBox(height: 6 * s),
          Row(
            children: [
              Expanded(
                child: Text(far == null ? 'route length' : 'farthest heard',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PopPalette.sans(small(19, 14.5),
                        color: PopPalette.soft, bold: true)),
              ),
              Text('${data.samples.length} readings',
                  maxLines: 1,
                  style:
                      PopPalette.sans(small(17, 13.5), color: PopPalette.soft)),
            ],
          ),
          SizedBox(height: 12 * s),
          if (horizontal) ...[
            margin,
            SizedBox(height: 8 * s),
            heard,
          ] else
            Row(
              children: [
                Expanded(child: margin),
                SizedBox(width: 8 * s),
                Expanded(child: heard),
              ],
            ),
          for (final (label, value) in differing) ...[
            SizedBox(height: 8 * s),
            PopTagPill(
              tag: label.toUpperCase(),
              value: value.isEmpty ? '-' : value,
              color: PopPalette.bg,
              scale: math.max(s * 0.8, 0.62),
            ),
          ],
        ],
      ),
    );
  }
}

/// A pink pill with a white star and WINNER, tilted a little.
class _WinnerBadge extends StatelessWidget {
  const _WinnerBadge({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Transform.rotate(
      angle: 0.06,
      child: Container(
        padding: EdgeInsets.fromLTRB(10 * s, 6 * s, 16 * s, 6 * s),
        decoration: BoxDecoration(
          color: PopPalette.hot,
          borderRadius: BorderRadius.circular(30 * s),
          border: Border.all(color: PopPalette.white, width: 4 * s),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
                size: Size.square(26 * s),
                painter: const _StarPainter(PopPalette.white)),
            SizedBox(width: 6 * s),
            Text('WINNER',
                style:
                    PopPalette.sans(21 * s, color: PopPalette.white, bold: true)
                        .copyWith(letterSpacing: 1.5 * s, height: 1.0)),
          ],
        ),
      ),
    );
  }
}

/// A chunky five-point star filling its box.
class _StarPainter extends CustomPainter {
  const _StarPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final inner = outer * 0.5;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r + outer * 0.06);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = outer * 0.18
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = outer * 0.18
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.color != color;
}
