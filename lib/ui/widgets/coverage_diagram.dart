// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../theme/status_colors.dart';

/// The one picture that explains the app (welcome page 04): the base node
/// at the left, a dashed radio link to the mobile node carried next to a
/// phone, along a route whose readings go green → orange → red as the
/// signal fades. Painted, theme-aware, no image assets.
class CoverageDiagram extends StatelessWidget {
  const CoverageDiagram({super.key, this.height = 120});

  final double height;

  static const semanticsLabel =
      'Diagram: the base node stays in one place. You carry the mobile node '
      'and your phone along a route; each reading is a dot, green near the '
      'base where the signal is strong, turning orange and red as it fades.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.status;
    final label = theme.readout.label.copyWith(
      fontFamily: ReadoutStyles.monoFamily,
      fontSize: 10,
      letterSpacing: 1.0,
      color: scheme.onSurfaceVariant,
    );
    return Semantics(
      label: semanticsLabel,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: CoverageDiagramPainter(
            node: scheme.primary,
            onNode: scheme.onPrimary,
            link: status.info,
            route: scheme.outlineVariant,
            phone: scheme.onSurface,
            dots: [status.ok, status.warning, status.lost, status.danger],
            labelStyle: label,
            textDirection: Directionality.of(context),
          ),
        ),
      ),
    );
  }
}

class CoverageDiagramPainter extends CustomPainter {
  CoverageDiagramPainter({
    required this.node,
    required this.onNode,
    required this.link,
    required this.route,
    required this.phone,
    required this.dots,
    required this.labelStyle,
    required this.textDirection,
  });

  final Color node, onNode, link, route, phone;

  /// Strong → no signal, spread evenly along the route.
  final List<Color> dots;
  final TextStyle labelStyle;
  final TextDirection textDirection;

  static const _dotCount = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const r = 9.0;
    final base = Offset(r + 6, h * 0.42);
    final mobile = Offset(w - 46, h * 0.42);

    // Route: leaves from near the base, dips below the link, ends at the
    // mobile.
    final routePath = Path()
      ..moveTo(base.dx + 8, h * 0.62)
      ..cubicTo(w * 0.30, h * 1.02, w * 0.62, h * 0.98, mobile.dx, mobile.dy);
    canvas.drawPath(
      routePath,
      Paint()
        ..color = route
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    final metric = routePath.computeMetrics().first;
    for (var i = 0; i < _dotCount; i++) {
      final t = i / (_dotCount - 1);
      // Stop short of the mobile so its circle stays clear.
      final at = metric.getTangentForOffset(metric.length * t * 0.86);
      if (at == null) continue;
      canvas.drawCircle(at.position, 4.5, Paint()..color = _colorAt(t));
    }

    // Dashed radio link base ↔ mobile.
    _dashed(
      canvas,
      Offset(base.dx + r + 4, base.dy),
      Offset(mobile.dx - r - 4, mobile.dy),
      Paint()
        ..color = link
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    _node(canvas, base, r);
    _node(canvas, mobile, r);

    // The phone beside the mobile node.
    final phoneRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: mobile + const Offset(r + 13, 2), width: 12, height: 20),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(
      phoneRect,
      Paint()
        ..color = phone
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawLine(
      Offset(phoneRect.center.dx - 2, phoneRect.bottom - 3),
      Offset(phoneRect.center.dx + 2, phoneRect.bottom - 3),
      Paint()
        ..color = phone
        ..strokeWidth = 1.2,
    );

    _label(canvas, 'BASE', Offset(base.dx - r, base.dy - r - 6), size,
        alignEnd: false);
    _label(canvas, 'MOBILE + PHONE',
        Offset(mobile.dx + r + 20, mobile.dy - r - 6), size,
        alignEnd: true);
  }

  void _node(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(c, r + 5, Paint()..color = node.withValues(alpha: 0.22));
    canvas.drawCircle(c, r, Paint()..color = node);
    canvas.drawCircle(c, r * 0.35, Paint()..color = onNode);
  }

  /// [anchor] is the label's bottom-left (or bottom-right with [alignEnd]).
  void _label(Canvas canvas, String text, Offset anchor, Size size,
      {required bool alignEnd}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: textDirection,
      maxLines: 1,
    )..layout(maxWidth: size.width / 2);
    var x = alignEnd ? anchor.dx - tp.width : anchor.dx;
    x = x.clamp(0.0, (size.width - tp.width).clamp(0.0, size.width));
    final y = (anchor.dy - tp.height).clamp(0.0, size.height);
    tp.paint(canvas, Offset(x, y));
  }

  Color _colorAt(double t) {
    if (dots.length == 1) return dots.first;
    final pos = t * (dots.length - 1);
    final i = pos.floor().clamp(0, dots.length - 2);
    return Color.lerp(dots[i], dots[i + 1], pos - i)!;
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 6.0, gap = 5.0;
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy);
    for (final PathMetric m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, (d + dash).clamp(0, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(CoverageDiagramPainter old) =>
      old.node != node ||
      old.onNode != onNode ||
      old.link != link ||
      old.route != route ||
      old.phone != phone ||
      old.labelStyle != labelStyle ||
      old.textDirection != textDirection ||
      !_sameColors(old.dots, dots);

  static bool _sameColors(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
