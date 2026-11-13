// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/field_report/field_report_data.dart';
import '../../../services/field_report/private_route.dart';
import '../../../services/units.dart';
import '../../../utils/signal_color_mapper.dart';
import 'report_style.dart';

/// Shared view box for one or more routes, so a comparison's routes sit on
/// the same scale.
class RouteFrame {
  final double minX, minY, maxX, maxY;
  const RouteFrame(this.minX, this.minY, this.maxX, this.maxY);

  factory RouteFrame.of(Iterable<PrivateRoute> routes) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final r in routes) {
      for (final p in r.extent) {
        minX = math.min(minX, p.x);
        maxX = math.max(maxX, p.x);
        minY = math.min(minY, p.y);
        maxY = math.max(maxY, p.y);
      }
    }
    if (!minX.isFinite) return const RouteFrame(-100, -100, 100, 100);
    // At least 100 m across, so a short walk isn't blown up.
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    final w = math.max(maxX - minX, 100.0), h = math.max(maxY - minY, 100.0);
    return RouteFrame(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2);
  }

  double get width => maxX - minX;
  double get height => maxY - minY;
}

/// Where [frame] lands in a box of [size]: fitted with a margin, north (+y)
/// up. The route painter and the map tiles under it share this, so a dot
/// sits on the street it was recorded on.
class RouteView {
  RouteView(this.frame, this.size)
      : scale = math.min((size.width - 2 * pad) / frame.width,
            (size.height - 2 * pad) / frame.height);

  static const pad = 40.0;
  final RouteFrame frame;
  final Size size;

  /// Box pixels per metre.
  final double scale;

  double get cx => (frame.minX + frame.maxX) / 2;
  double get cy => (frame.minY + frame.maxY) / 2;

  Offset at(double x, double y) => Offset(
      size.width / 2 + (x - cx) * scale, size.height / 2 - (y - cy) * scale);
}

/// The route on a plain grid (rotated, no tiles), or over map tiles
/// painted underneath ([grid] false); the base area hazed either way.
class RoutePainter extends CustomPainter {
  final PrivateRoute route;
  final RouteFrame frame;
  final bool miles;
  final double dotRadius;

  /// Draw the plain grid (off when map tiles are under the route).
  final bool grid;

  /// Draw the scale bar (a comparison draws one on the first map only).
  final bool scaleBar;

  RoutePainter({
    required this.route,
    required this.frame,
    required this.miles,
    this.dotRadius = 11,
    this.scaleBar = true,
    this.grid = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
        rect, const Radius.circular(ReportStyle.radius)));

    if (grid) {
      final gridPaint = Paint()
        ..color = ReportStyle.grid
        ..strokeWidth = 1.5;
      const cells = 12;
      final step = size.width / cells;
      for (var x = step; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (var y = step; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    final view = RouteView(frame, size);
    final scale = view.scale;
    final at = view.at;

    // Base (or start) area.
    final o = at(0, 0);
    if (route.origin != ReportOrigin.none) {
      final label = route.origin == ReportOrigin.base ? 'BASE' : 'START';
      final r = route.hideRadiusM * scale;
      if (r > 4) {
        canvas.drawCircle(
            o,
            r,
            Paint()
              ..shader = RadialGradient(colors: [
                ReportStyle.orange.withValues(alpha: 0.30),
                ReportStyle.orange.withValues(alpha: 0.12),
              ]).createShader(Rect.fromCircle(center: o, radius: r)));
        _dashedCircle(
            canvas,
            o,
            r,
            Paint()
              ..color = ReportStyle.orange.withValues(alpha: 0.8)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5);
      } else {
        canvas.drawCircle(o, 9, Paint()..color = ReportStyle.orange);
      }
      // Inside a roomy zone; above a small one so it doesn't cover dots.
      _drawText(
          canvas,
          label,
          o + Offset(0, r > 60 ? 0 : -(math.max(r, 9.0) + 18)),
          ReportStyle.mono(22, color: ReportStyle.orange, bold: true),
          center: true);
    }

    // Track line.
    final line = Paint()
      ..color = ReportStyle.track
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final seg in route.segments) {
      if (seg.length < 2) continue;
      final path = Path()
        ..moveTo(at(seg[0].x, seg[0].y).dx, at(seg[0].x, seg[0].y).dy);
      for (final p in seg.skip(1)) {
        final q = at(p.x, p.y);
        path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(path, line);
    }

    // Dots, weakest on top so trouble spots show.
    final dots = [...route.dots]
      ..sort((a, b) => b.marginDb.compareTo(a.marginDb));
    final ring = Paint()
      ..color = ReportStyle.panel
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final d in dots) {
      final p = at(d.x, d.y);
      canvas.drawCircle(p, dotRadius,
          Paint()..color = SignalColorMapper.fromMargin(d.marginDb));
      canvas.drawCircle(p, dotRadius, ring);
    }

    if (scaleBar) {
      final maxM = (size.width * 0.3) / scale;
      final (m, label) = niceScaleBar(maxM, miles: miles);
      final w = m * scale;
      final y = size.height - 30;
      final x1 = size.width - 30, x0 = x1 - w;
      if (!grid) {
        // Over map tiles: a dark backing so the bar and label read.
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTRB(x0 - 12, y - 40, x1 + 12, y + 12),
                const Radius.circular(6)),
            Paint()..color = ReportStyle.panel.withValues(alpha: 0.85));
      }
      canvas.drawLine(
          Offset(x0, y),
          Offset(x1, y),
          Paint()
            ..color = ReportStyle.soft
            ..strokeWidth = 3);
      _drawText(canvas, label, Offset((x0 + x1) / 2, y - 22),
          ReportStyle.figure(20, color: ReportStyle.soft),
          center: true);
    }
    canvas.restore();
  }

  static void _dashedCircle(Canvas canvas, Offset c, double r, Paint p) {
    final n = math.max(12, (2 * math.pi * r / 18).round());
    for (var i = 0; i < n; i += 1) {
      if (i.isOdd) continue;
      final a0 = 2 * math.pi * i / n, a1 = 2 * math.pi * (i + 1) / n;
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r), a0, a1 - a0, false, p);
    }
  }

  @override
  bool shouldRepaint(RoutePainter old) =>
      old.route != route ||
      old.miles != miles ||
      old.frame != frame ||
      old.scaleBar != scaleBar ||
      old.grid != grid;
}

/// Median margin per time bin, dots on the margin ramp, guides at Strong,
/// Good and the limit.
class MarginChartPainter extends CustomPainter {
  final List<double?> bins;
  MarginChartPainter(this.bins);

  static const _top = 24.0, _bottom = -4.0;

  @override
  void paint(Canvas canvas, Size size) {
    const labelW = 100.0, bottomPad = 30.0, topPad = 12.0;
    final w = size.width - labelW;
    final h = size.height - bottomPad - topPad;
    double yOf(double m) =>
        topPad +
        (1 - (m.clamp(_bottom, _top) - _bottom) / (_top - _bottom)) * h;
    final guide = Paint()
      ..color = ReportStyle.soft.withValues(alpha: 0.35)
      ..strokeWidth = 1.5;
    for (final (m, label) in [
      (20.0, 'Strong'),
      (10.0, 'Good'),
      (0.0, 'Limit')
    ]) {
      final y = yOf(m);
      for (var x = 0.0; x < w; x += 14) {
        canvas.drawLine(Offset(x, y), Offset(x + 6, y), guide);
      }
      _drawText(canvas, label, Offset(w + 14, y),
          ReportStyle.mono(17, color: ReportStyle.soft),
          center: false, middle: true);
    }
    final n = bins.length;
    final pts = <(Offset, double)>[
      for (var i = 0; i < n; i++)
        if (bins[i] != null)
          (
            Offset(n == 1 ? w / 2 : 20 + i * (w - 40) / (n - 1), yOf(bins[i]!)),
            bins[i]!
          ),
    ];
    if (pts.length > 1) {
      final path = Path()..moveTo(pts.first.$1.dx, pts.first.$1.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.$1.dx, p.$1.dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = ReportStyle.cyan
            ..strokeWidth = 4
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round);
    }
    for (final (p, m) in pts) {
      canvas.drawCircle(
          p, 10, Paint()..color = SignalColorMapper.fromMargin(m));
      canvas.drawCircle(
          p,
          10,
          Paint()
            ..color = ReportStyle.panel
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
    final small = ReportStyle.mono(18, color: ReportStyle.soft);
    _drawText(canvas, 'Start', Offset(20, size.height - 22), small);
    _drawText(canvas, 'End', Offset(w - 20, size.height - 22), small,
        right: true);
  }

  @override
  bool shouldRepaint(MarginChartPainter old) => old.bins != bins;
}

/// Draw [text] at [at] (top-left, top-centre with [center], top-right
/// with [right]; [center] also centres vertically).
void _drawText(Canvas canvas, String text, Offset at, TextStyle style,
    {bool center = false, bool right = false, bool middle = false}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final dx = center
      ? at.dx - tp.width / 2
      : right
          ? at.dx - tp.width
          : at.dx;
  final dy = center || middle ? at.dy - tp.height / 2 : at.dy;
  tp.paint(canvas, Offset(dx, dy));
}
