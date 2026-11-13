// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../services/field_report/field_report_data.dart';
import '../../../../services/field_report/private_route.dart';
import '../../../../services/units.dart';
import '../../../../utils/app_info.dart';
import '../../../../utils/signal_color_mapper.dart';
import '../../../theme/app_theme.dart';
import '../report_painters.dart';
import '../report_parts.dart';
import '../report_style.dart';
import '../report_theme.dart';

/// The Basic Field Report theme (docs/design/field-report/themes.md):
/// light paper, dark ink, one big number, a small route drawing and a few
/// stats. Shows less than Night on purpose, and prints well.
class BasicReportCard extends StatelessWidget {
  const BasicReportCard({super.key, required this.report});

  final ThemedReport report;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
        size: report.format.size,
        child: ColoredBox(
          color: BasicStyle.paper,
          child: switch (report.format) {
            ReportFormat.feed => _feed(),
            ReportFormat.story => _story(),
            ReportFormat.wide => _wide(),
          },
        ),
      );

  FieldReportData get _d => report.data;

  /// Taller than wide (base area included).
  bool get _tallRoute {
    final f = RouteFrame.of([report.route]);
    return f.height > f.width * 1.1;
  }

  Widget _feed() => Padding(
        padding: const EdgeInsets.fromLTRB(84, 76, 84, 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BasicHeader(
                title: report.title, subtitle: report.subtitle, scale: 1),
            const SizedBox(height: 48),
            _Headline(report: report, size: 150),
            const SizedBox(height: 44),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                      flex: 11,
                      child: _RouteDrawing(report: report, dotRadius: 8.5)),
                  const SizedBox(width: 48),
                  Expanded(
                    flex: 8,
                    child: _StatList(report: report, scale: 1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            _MarginSplit(data: _d, scale: 1),
            ..._quietLines(1),
            const SizedBox(height: 36),
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
                title: report.title, subtitle: report.subtitle, scale: 1.1),
            const SizedBox(height: 72),
            _Headline(report: report, size: 176),
            const SizedBox(height: 48),
            // A tall route gets the stats beside it (as in feed) so it can
            // use the height; a wide one spans the card over a 2 x 2 grid.
            if (_tallRoute) ...[
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                        flex: 3,
                        child: _RouteDrawing(report: report, dotRadius: 10)),
                    const SizedBox(width: 48),
                    Expanded(
                      flex: 2,
                      child: _StatList(report: report, scale: 1.1),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Expanded(child: _RouteDrawing(report: report, dotRadius: 10)),
              const SizedBox(height: 48),
              _StatGrid(report: report, scale: 1.1),
            ],
            const SizedBox(height: 56),
            _MarginSplit(data: _d, scale: 1.1),
            ..._quietLines(1.1),
            const SizedBox(height: 56),
            const BasicFooter(scale: 1.1),
          ],
        ),
      );

  Widget _wide() => Padding(
        padding: const EdgeInsets.fromLTRB(56, 48, 64, 40),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
                width: 470,
                child: _RouteDrawing(report: report, dotRadius: 7.5)),
            const SizedBox(width: 56),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BasicHeader(
                      title: report.title,
                      subtitle: report.subtitle,
                      scale: 0.72,
                      titleLines: 1),
                  const Spacer(),
                  _Headline(report: report, size: 96, scale: 0.78),
                  const Spacer(),
                  _StatGrid(report: report, scale: 0.72, columns: 4),
                  const SizedBox(height: 30),
                  _MarginSplit(data: _d, scale: 0.72),
                  if (report.note != null) ...[
                    const SizedBox(height: 14),
                    _quiet(report.note!, 0.72, maxLines: 2),
                  ],
                  const Spacer(),
                  const BasicFooter(scale: 0.72),
                ],
              ),
            ),
          ],
        ),
      );

  /// The note and the one-line setup, both quiet.
  List<Widget> _quietLines(double s) {
    final setup = _setupLine(_d);
    return [
      if (report.note != null) ...[
        SizedBox(height: 28 * s),
        _quiet(report.note!, s, maxLines: 2),
      ],
      if (setup.isNotEmpty) ...[
        SizedBox(height: (report.note == null ? 28 : 10) * s),
        _quiet(setup, s, maxLines: 1),
      ],
    ];
  }

  static Widget _quiet(String text, double s, {required int maxLines}) =>
      Text(text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: BasicStyle.sans(21 * s, color: BasicStyle.soft));

  static String _setupLine(FieldReportData d) => [
        for (final (label, v) in SideSetupList.rowsFor([d]))
          if (v.single.isNotEmpty && label != 'Freq') '$label ${v.single}',
      ].join('   ·   ');
}

/// Palette and type for the Basic card.
class BasicStyle {
  BasicStyle._();

  static const paper = Color(0xFFFAFAF7);
  static const ink = Color(0xFF15171A);
  static const soft = Color(0xFF6E727A);
  static const faint = Color(0xFFA3A7AE);
  static const rule = Color(0xFFE2E2DC);
  static const track = Color(0xFFC6C8CC);
  static const zone = Color(0xFFEDECE6);

  static TextStyle sans(double size,
          {Color color = ink, bool bold = false, double spacing = 0}) =>
      TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: size,
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        letterSpacing: spacing,
        height: 1.2,
        decoration: TextDecoration.none,
      );

  /// Small tracked caps labels.
  static TextStyle label(double size, {Color color = soft}) => TextStyle(
        fontFamily: ReadoutStyles.monoFamily,
        fontSize: size,
        color: color,
        letterSpacing: size * 0.18,
        height: 1.2,
        decoration: TextDecoration.none,
      );

  /// Signal colour on paper: the app's ramp, a touch deeper so the
  /// yellow end still reads on white and in print.
  static Color signal(double marginDb) {
    final c = SignalColorMapper.fromMargin(marginDb);
    return Color.lerp(c, ink, 0.08)!;
  }
}

/// Kicker, bold title and a soft subtitle.
class BasicHeader extends StatelessWidget {
  const BasicHeader(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.scale,
      this.titleLines = 2});

  final String title, subtitle;
  final double scale;
  final int titleLines;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(reportHeading.toUpperCase(),
            maxLines: 1, style: BasicStyle.label(20 * s)),
        SizedBox(height: 18 * s),
        Text(title,
            maxLines: titleLines,
            overflow: TextOverflow.ellipsis,
            style: BasicStyle.sans(50 * s, bold: true, spacing: -0.5)),
        if (subtitle.isNotEmpty) ...[
          SizedBox(height: 8 * s),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BasicStyle.sans(28 * s, color: BasicStyle.soft)),
        ],
      ],
    );
  }
}

/// "0.2 mi": the number big and bold (never mono: B612Mono spaces the
/// decimal point wide), the unit smaller and soft beside it. Scales down
/// to fit, inside a box of fixed height ([size]) so neighbours line up.
class BasicBigNumber extends StatelessWidget {
  const BasicBigNumber(
      {super.key,
      required this.value,
      required this.size,
      this.color = BasicStyle.ink});

  final String value;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final m = RegExp(r'^([-+]?[\d.,]+)\s*(.*)$').firstMatch(value);
    final number = m?.group(1) ?? value;
    final unit = m?.group(2) ?? '';
    return SizedBox(
      height: size,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.bottomLeft,
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: number,
                style: BasicStyle.sans(size,
                        bold: true, color: color, spacing: -size * 0.03)
                    .copyWith(height: 1.0)),
            if (unit.isNotEmpty)
              TextSpan(
                  text: ' $unit',
                  style: BasicStyle.sans(size * 0.36, color: BasicStyle.soft)
                      .copyWith(height: 1.0)),
          ]),
          maxLines: 1,
        ),
      ),
    );
  }
}

/// The big number: farthest point the base was heard, or the route length
/// (or readings) when there is no distance from the base to show; same
/// rules as [BragTile].
class _Headline extends StatelessWidget {
  const _Headline({required this.report, required this.size, this.scale = 1});

  final ThemedReport report;
  final double size;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final data = report.data;
    final miles = report.miles;
    final far = data.farthestM;
    final String value;
    final String caption;
    if (far != null) {
      value = reportDistance(far, miles);
      caption = 'Farthest point the base was heard';
    } else if (data.routeM >= 50) {
      value = reportDistance(data.routeM, miles);
      caption = 'Route length';
    } else {
      value = '${data.samples.length}';
      caption = data.samples.length == 1 ? 'Reading' : 'Readings';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        BasicBigNumber(value: value, size: size),
        SizedBox(height: 14 * scale),
        Row(
          children: [
            Container(width: 36 * scale, height: 4, color: BasicStyle.ink),
            SizedBox(width: 16 * scale),
            Expanded(
              child: Text(caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BasicStyle.sans(30 * scale)),
            ),
          ],
        ),
      ],
    );
  }
}

List<(String, String)> _stats(FieldReportData d, bool miles) {
  final pct = d.baseHeardPct;
  return [
    (reportDistance(d.routeM, miles), 'Route'),
    ('${d.samples.length}', 'Readings'),
    (
      d.medianMarginDb == null ? '-' : reportDb(d.medianMarginDb!),
      'Median margin'
    ),
    (pct == null ? '-' : '$pct%', 'Base heard'),
  ];
}

class BasicStat extends StatelessWidget {
  const BasicStat(
      {super.key,
      required this.value,
      required this.label,
      required this.scale});

  final String value, label;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(label.toUpperCase(),
              maxLines: 1, style: BasicStyle.label(17 * s)),
        ),
        SizedBox(height: 8 * s),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              maxLines: 1, style: BasicStyle.sans(54 * s, bold: true)),
        ),
      ],
    );
  }
}

/// Four stats stacked with hairlines between (feed, beside the route).
class _StatList extends StatelessWidget {
  const _StatList({required this.report, required this.scale});

  final ThemedReport report;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final stats = _stats(report.data, report.miles);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) Container(height: 1.5, color: BasicStyle.rule),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ScaleDownBox(
                alignment: Alignment.centerLeft,
                child: BasicStat(
                    value: stats[i].$1, label: stats[i].$2, scale: scale),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Stats in a grid: 2 x 2 (story) or one row of four (wide).
class _StatGrid extends StatelessWidget {
  const _StatGrid(
      {required this.report, required this.scale, this.columns = 2});

  final ThemedReport report;
  final double scale;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final stats = _stats(report.data, report.miles);
    final rows = <List<(String, String)>>[
      for (var i = 0; i < stats.length; i += columns)
        stats.sublist(i, math.min(i + columns, stats.length)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          Container(height: 1.5, color: BasicStyle.rule),
          SizedBox(height: 22 * scale),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) SizedBox(width: 36 * scale),
                Expanded(
                  child: c < rows[r].length
                      ? BasicStat(
                          value: rows[r][c].$1,
                          label: rows[r][c].$2,
                          scale: scale)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
          SizedBox(height: (r == rows.length - 1 ? 0 : 26) * scale),
        ],
      ],
    );
  }
}

/// One stacked bar of the margin bands with a legend line under it.
class _MarginSplit extends StatelessWidget {
  const _MarginSplit({required this.data, required this.scale});

  final FieldReportData data;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final buckets = [
      for (final b in data.buckets)
        if (b.count > 0) b
    ];
    final preset = data.presetName.isEmpty ? 'the' : 'the ${data.presetName}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('SIGNAL MARGIN', style: BasicStyle.label(17 * s)),
            SizedBox(width: 18 * s),
            Expanded(
              child: Text('above $preset decode limit',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BasicStyle.sans(19 * s, color: BasicStyle.faint)),
            ),
          ],
        ),
        SizedBox(height: 14 * s),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 22 * s,
            child: buckets.isEmpty
                ? const ColoredBox(color: BasicStyle.rule)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < buckets.length; i++) ...[
                        if (i > 0) SizedBox(width: 3 * s),
                        Expanded(
                          flex: buckets[i].count,
                          child: ColoredBox(
                              color: BasicStyle.signal(
                                  buckets[i].band.colourMarginDb)),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        SizedBox(height: 14 * s),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < data.buckets.length; i++) ...[
                if (i > 0) SizedBox(width: 30 * s),
                Container(
                  width: 14 * s,
                  height: 14 * s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        BasicStyle.signal(data.buckets[i].band.colourMarginDb),
                  ),
                ),
                SizedBox(width: 9 * s),
                Text(data.buckets[i].band.label,
                    style: BasicStyle.sans(21 * s, color: BasicStyle.soft)),
                SizedBox(width: 8 * s),
                Text('${data.buckets[i].pct}%',
                    style: BasicStyle.sans(21 * s, bold: true)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class BasicFooter extends StatelessWidget {
  const BasicFooter({super.key, required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 1.5, color: BasicStyle.rule),
        SizedBox(height: 16 * s),
        Text(AppInfo.website,
            textAlign: TextAlign.right,
            style: BasicStyle.sans(20 * s, color: BasicStyle.faint)),
      ],
    );
  }
}

class _RouteDrawing extends StatelessWidget {
  const _RouteDrawing({required this.report, required this.dotRadius});

  final ThemedReport report;
  final double dotRadius;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.infinite,
        painter: BasicRoutePainter(
          route: report.route,
          frame: RouteFrame.of([report.route]),
          miles: report.miles,
          dotRadius: dotRadius,
        ),
      );
}

/// Thin grey track, signal-coloured dots, the hidden base area as a plain
/// marked disc and a small scale bar. No grid, no frame. Every route of a
/// comparison shares one [frame] and box size, so their scales match.
class BasicRoutePainter extends CustomPainter {
  BasicRoutePainter({
    required this.route,
    required this.frame,
    required this.miles,
    required this.dotRadius,
    this.scaleBar = true,
    this.textScale = 1,
    this.pad = RouteView.pad,
    this.dotPeers,
  });

  final PrivateRoute route;
  final RouteFrame frame;
  final bool miles;

  /// The largest dot; dense routes draw them smaller (down to about half)
  /// so a tight loop still reads as a line, not a string of beads.
  final double dotRadius;

  /// Draw the scale bar. The strip it sits in is kept either way, so
  /// boxes with and without one map metres to pixels the same.
  final bool scaleBar;
  final double textScale;

  /// Margin around the route inside the box (RouteView's own is 40 px,
  /// a lot in a narrow comparison column).
  final double pad;

  /// Every route of a comparison: the dot size is fitted over all of them
  /// so the sides draw the same dots. Null: fitted to [route] alone.
  final List<PrivateRoute>? dotPeers;

  /// Pixels per metre for [frame] in a box of [size] with [pad].
  static double scaleFor(RouteFrame frame, Size size,
      {double pad = RouteView.pad}) {
    final k = RouteView.pad - pad;
    return RouteView(
            frame, Size(size.width + 2 * k, size.height - scaleStrip + 2 * k))
        .scale;
  }

  /// Height of the strip under the route kept for the scale bar.
  static const scaleStrip = 36.0;

  /// Dot radius for [dots] at [scale] px/m: about half the typical gap
  /// between consecutive readings, within [maxR] / 2 .. [maxR].
  static double fitDotRadius(List<RouteDot> dots, double scale, double maxR) {
    if (dots.length < 8) return maxR;
    final gaps = <double>[
      for (var i = 1; i < dots.length; i++)
        math.sqrt(math.pow(dots[i].x - dots[i - 1].x, 2) +
                math.pow(dots[i].y - dots[i - 1].y, 2)) *
            scale,
    ]..sort();
    final typical = gaps[gaps.length ~/ 2];
    return (typical * 0.48).clamp(math.max(3.0, maxR * 0.5), maxR);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = textScale;
    if (route.isEmpty) {
      _text(
          canvas,
          'No route recorded',
          Offset(size.width / 2, size.height / 2),
          BasicStyle.sans(22 * t, color: BasicStyle.faint),
          center: true);
      return;
    }
    // Keep a strip at the bottom for the scale bar.
    // RouteView keeps a fixed 40 px margin: grow its box past ours by the
    // difference to get [pad].
    final k = RouteView.pad - pad;
    final box = Size(size.width + 2 * k, size.height - scaleStrip + 2 * k);
    canvas.save();
    canvas.translate(-k, -k);
    final view = RouteView(frame, box);
    final at = view.at;
    final scale = view.scale;

    // Base (or start) area.
    final o = at(0, 0);
    (String, Offset, TextStyle)? baseLabel;
    if (route.origin != ReportOrigin.none) {
      final label = route.origin == ReportOrigin.base ? 'BASE' : 'START';
      final r = route.hideRadiusM * scale;
      final style = BasicStyle.label(15 * t, color: BasicStyle.ink);
      if (r > 4) {
        canvas.drawCircle(o, r, Paint()..color = BasicStyle.zone);
        _dashedCircle(
            canvas,
            o,
            r,
            Paint()
              ..color = BasicStyle.faint
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      }
      canvas.drawCircle(o, 5, Paint()..color = BasicStyle.ink);
      // Under the centre mark inside a roomy zone, else just outside the
      // zone, above or below, whichever side has fewer dots in the way.
      // Drawn after the dots, on a paper patch, so it always reads.
      if (r > 50) {
        baseLabel = (label, o + Offset(0, 20.0 * t), style);
      } else {
        final off = math.max(r, 5.0) + 16 * t;
        int crowd(Offset c) => route.dots.where((d) {
              final p = at(d.x, d.y);
              return (p.dx - c.dx).abs() < 40 * t + dotRadius &&
                  (p.dy - c.dy).abs() < 12 * t + dotRadius;
            }).length;
        final above = o + Offset(0, -off), below = o + Offset(0, off);
        baseLabel = (label, crowd(below) < crowd(above) ? below : above, style);
      }
    }

    final peers = dotPeers ?? [route];
    final dotR = peers
            .map((r) => fitDotRadius(r.dots, scale, dotRadius))
            .reduce((a, b) => a + b) /
        peers.length;

    // Track.
    final line = Paint()
      ..color = BasicStyle.track
      ..strokeWidth = math.min(3, math.max(2, dotR * 0.4))
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final seg in route.segments) {
      if (seg.length < 2) continue;
      final first = at(seg[0].x, seg[0].y);
      final path = Path()..moveTo(first.dx, first.dy);
      for (final p in seg.skip(1)) {
        final q = at(p.x, p.y);
        path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(path, line);
    }

    // Dots, weakest on top so trouble spots show; a thin paper ring keeps
    // touching dots apart.
    final dots = [...route.dots]
      ..sort((a, b) => b.marginDb.compareTo(a.marginDb));
    final ring = Paint()
      ..color = BasicStyle.paper
      ..style = PaintingStyle.stroke
      ..strokeWidth = (dotR * 0.2).clamp(1.0, 1.75);
    for (final d in dots) {
      final p = at(d.x, d.y);
      canvas.drawCircle(
          p, dotR, Paint()..color = BasicStyle.signal(d.marginDb));
      canvas.drawCircle(p, dotR, ring);
    }

    if (baseLabel != null) {
      final (text, at, style) = baseLabel;
      _text(canvas, text, at, style, center: true, patch: true);
    }

    canvas.restore();
    if (!scaleBar) return;
    // Scale bar, bottom left: a hairline with end ticks.
    final (m, label) = niceScaleBar((size.width * 0.3) / scale, miles: miles);
    final w = m * scale;
    final y = size.height - 6;
    final x0 = math.min(RouteView.pad / 2, size.width * 0.06);
    final x1 = x0 + w;
    final bar = Paint()
      ..color = BasicStyle.soft
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x0, y), Offset(x1, y), bar);
    canvas.drawLine(Offset(x0, y - 8), Offset(x0, y), bar);
    canvas.drawLine(Offset(x1, y - 8), Offset(x1, y), bar);
    _text(canvas, label, Offset(x1 + 12 * t, y - 4),
        BasicStyle.sans(18 * t, color: BasicStyle.soft),
        middle: true);
  }

  static void _dashedCircle(Canvas canvas, Offset c, double r, Paint p) {
    final n = math.max(12, (2 * math.pi * r / 14).round());
    for (var i = 0; i < n; i += 2) {
      final a0 = 2 * math.pi * i / n, a1 = 2 * math.pi * (i + 1) / n;
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r), a0, a1 - a0, false, p);
    }
  }

  static void _text(Canvas canvas, String text, Offset at, TextStyle style,
      {bool center = false, bool middle = false, bool patch = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = center ? at.dx - tp.width / 2 : at.dx;
    final dy = center || middle ? at.dy - tp.height / 2 : at.dy;
    if (patch) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(dx - 5, dy - 2, tp.width + 10, tp.height + 4),
              const Radius.circular(3)),
          Paint()..color = BasicStyle.paper.withValues(alpha: 0.9));
    }
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(BasicRoutePainter old) =>
      old.route != route ||
      old.frame != frame ||
      old.miles != miles ||
      old.dotRadius != dotRadius ||
      old.scaleBar != scaleBar ||
      old.textScale != textScale ||
      old.pad != pad ||
      old.dotPeers != dotPeers;
}
