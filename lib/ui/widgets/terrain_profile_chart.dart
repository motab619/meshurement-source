// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/terrain/los_verdict.dart';
import '../../services/terrain/terrain_profile.dart';
import '../theme/app_theme.dart';

/// Chart tokens, shared with the signal charts (see signal_charts_panel.dart;
/// dark values are the same, light values are the matching light set).
class ProfileChartColors {
  const ProfileChartColors({
    required this.surface,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkMuted,
    required this.grid,
    required this.series,
    required this.warning,
    required this.critical,
  });

  final Color surface, inkPrimary, inkSecondary, inkMuted, grid;

  /// Line of sight and Fresnel zone.
  final Color series;

  /// Partial Fresnel obstruction.
  final Color warning;

  /// Blocked.
  final Color critical;

  static const dark = ProfileChartColors(
    surface: Color(0xFF1A1A19),
    inkPrimary: Color(0xFFF0EFEC),
    inkSecondary: Color(0xFFC3C2B7),
    inkMuted: Color(0xFF898781),
    grid: Color(0xFF2C2C2A),
    series: Color(0xFF2BD9E6), // theme secondary, dark
    warning: Color(0xFFFAB219),
    critical: Color(0xFFD03B3B),
  );

  static const light = ProfileChartColors(
    surface: Color(0xFFF7F6F3),
    inkPrimary: Color(0xFF1A1A19),
    inkSecondary: Color(0xFF4A4943),
    inkMuted: Color(0xFF898781),
    grid: Color(0xFFE2E0D9),
    series: Color(0xFF007C87), // theme secondary, light
    warning: Color(0xFFC98A00),
    critical: Color(0xFFC12B2B),
  );

  static ProfileChartColors of(Brightness b) =>
      b == Brightness.dark ? dark : light;
}

/// Terrain cross-section: ground (with earth bulge) as a filled area, the
/// straight line of sight between the antenna tips, the first Fresnel zone
/// as a translucent band (its 60 % boundary dashed) and obstruction points.
///
/// The picture is in the "flattened earth" frame: the ground is raised by
/// the earth bulge (k = 4/3) so a straight line is the radio path.
/// Handles degenerate input (null profile, one sample, zero length) by
/// drawing an empty frame.
class TerrainProfilePainter extends CustomPainter {
  TerrainProfilePainter({
    required this.profile,
    required this.colors,
    this.baseHeightM = 2,
    this.mobileHeightM = 1.5,
  });

  final TerrainProfile? profile;
  final ProfileChartColors colors;
  final double baseHeightM;
  final double mobileHeightM;

  static const double _left = 44, _right = 10, _top = 10, _bottom = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
        _left,
        _top,
        math.max(_left + 1, size.width - _right),
        math.max(_top + 1, size.height - _bottom));
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.surface);
    final p = profile;
    if (p == null || p.samples.length < 2 || !(p.distanceM > 0)) {
      _text(canvas, 'No profile', plot.center, colors.inkMuted,
          align: _Align.center);
      return;
    }
    final s = p.samples;

    // Vertical range from everything drawn.
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final e in s) {
      lo = math.min(lo, e.groundM);
      hi = math.max(hi, math.max(e.effectiveGroundM, e.losM + e.f1RadiusM));
    }
    if (!lo.isFinite || !hi.isFinite) return;
    final pad = math.max(2.0, (hi - lo) * 0.08);
    lo -= pad;
    hi += pad;
    if (hi - lo < 10) hi = lo + 10;

    double x(double d) => plot.left + d / p.distanceM * plot.width;
    double y(double m) => plot.bottom - (m - lo) / (hi - lo) * plot.height;

    // Grid and axes.
    final gridPaint = Paint()
      ..color = colors.grid
      ..strokeWidth = 1;
    final yStep = _niceStep((hi - lo) / 4);
    for (var v = (lo / yStep).ceil() * yStep; v <= hi; v += yStep) {
      canvas.drawLine(
          Offset(plot.left, y(v)), Offset(plot.right, y(v)), gridPaint);
      _text(
          canvas, '${v.round()}', Offset(plot.left - 4, y(v)), colors.inkMuted,
          align: _Align.right);
    }
    final xStep = _niceStep(p.distanceM / 4);
    for (var d = 0.0; d <= p.distanceM + 1e-6; d += xStep) {
      canvas.drawLine(
          Offset(x(d), plot.top), Offset(x(d), plot.bottom), gridPaint);
      _text(canvas, _distLabel(d, xStep), Offset(x(d), plot.bottom + 4),
          colors.inkMuted,
          align: _Align.top);
    }
    _text(canvas, 'm', Offset(2, plot.top), colors.inkMuted,
        align: _Align.left);

    canvas.save();
    canvas.clipRect(plot.inflate(0.5));

    // Fresnel zone band (first zone), then dashed 60 % boundary.
    final upper = Path(), lower = Path();
    for (var i = 0; i < s.length; i++) {
      final px = x(s[i].distanceM);
      final u = y(s[i].losM + s[i].f1RadiusM);
      final l = y(s[i].losM - s[i].f1RadiusM);
      if (i == 0) {
        upper.moveTo(px, u);
        lower.moveTo(px, l);
      } else {
        upper.lineTo(px, u);
        lower.lineTo(px, l);
      }
    }
    final band = Path.from(upper);
    for (var i = s.length - 1; i >= 0; i--) {
      band.lineTo(x(s[i].distanceM), y(s[i].losM - s[i].f1RadiusM));
    }
    band.close();
    canvas.drawPath(
        band, Paint()..color = colors.series.withValues(alpha: 0.16));
    final dashed = Paint()
      ..color = colors.series.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final sign in const [1.0, -1.0]) {
      final path = Path();
      for (var i = 0; i < s.length; i++) {
        final py = y(s[i].losM + sign * 0.6 * s[i].f1RadiusM);
        i == 0
            ? path.moveTo(x(s[i].distanceM), py)
            : path.lineTo(x(s[i].distanceM), py);
      }
      _dashPath(canvas, path, dashed);
    }

    // Terrain: filled area under the bulged ground.
    final ground = Path()..moveTo(x(0), plot.bottom);
    for (final e in s) {
      ground.lineTo(x(e.distanceM), y(e.effectiveGroundM));
    }
    ground
      ..lineTo(x(p.distanceM), plot.bottom)
      ..close();
    canvas.drawPath(
        ground, Paint()..color = colors.inkMuted.withValues(alpha: 0.45));
    final edge = Path();
    for (var i = 0; i < s.length; i++) {
      i == 0
          ? edge.moveTo(x(s[i].distanceM), y(s[i].effectiveGroundM))
          : edge.lineTo(x(s[i].distanceM), y(s[i].effectiveGroundM));
    }
    canvas.drawPath(
        edge,
        Paint()
          ..color = colors.inkSecondary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Line of sight.
    canvas.drawLine(
        Offset(x(0), y(s.first.losM)),
        Offset(x(p.distanceM), y(s.last.losM)),
        Paint()
          ..color = colors.series
          ..strokeWidth = 2);

    // Antenna masts and end markers.
    final mast = Paint()
      ..color = colors.inkPrimary
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x(0), y(s.first.effectiveGroundM)),
        Offset(x(0), y(s.first.losM)), mast);
    canvas.drawLine(Offset(x(p.distanceM), y(s.last.effectiveGroundM)),
        Offset(x(p.distanceM), y(s.last.losM)), mast);
    canvas.drawCircle(
        Offset(x(0), y(s.first.losM)), 4, Paint()..color = colors.series);
    canvas.drawCircle(Offset(x(p.distanceM), y(s.last.losM)), 4,
        Paint()..color = colors.series);

    // Obstruction points.
    for (var i = 1; i < s.length - 1; i++) {
      if (!LosVerdictRules.isObstruction(p, i)) continue;
      final blocked = s[i].clearanceM < 0;
      canvas.drawCircle(
          Offset(x(s[i].distanceM), y(s[i].effectiveGroundM)),
          blocked ? 3.5 : 2.5,
          Paint()..color = blocked ? colors.critical : colors.warning);
    }
    canvas.restore();

    _text(canvas, 'Base', Offset(x(0) + 6, plot.top + 2), colors.inkSecondary,
        align: _Align.left);
    _text(canvas, 'You', Offset(x(p.distanceM) - 6, plot.top + 2),
        colors.inkSecondary,
        align: _Align.right);
  }

  static double _niceStep(double raw) {
    if (!(raw > 0) || !raw.isFinite) return 1;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final f = raw / mag;
    final n = f < 1.5 ? 1 : (f < 3.5 ? 2 : (f < 7.5 ? 5 : 10));
    return n * mag;
  }

  static String _distLabel(double d, double step) {
    if (d >= 1000 || step >= 1000) {
      final km = d / 1000;
      return km == km.roundToDouble()
          ? '${km.round()} km'
          : '${km.toStringAsFixed(step >= 100 ? 1 : 2)} km';
    }
    return '${d.round()} m';
  }

  static void _dashPath(Canvas canvas, Path path, Paint paint,
      {double dash = 5, double gap = 4}) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  void _text(Canvas canvas, String text, Offset at, Color color,
      {required _Align align}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    final o = switch (align) {
      _Align.right => Offset(at.dx - tp.width, at.dy - tp.height / 2),
      _Align.left => Offset(at.dx, at.dy),
      _Align.center => Offset(at.dx - tp.width / 2, at.dy - tp.height / 2),
      _Align.top => Offset(at.dx - tp.width / 2, at.dy),
    };
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(TerrainProfilePainter old) =>
      old.profile != profile ||
      old.colors != colors ||
      old.baseHeightM != baseHeightM ||
      old.mobileHeightM != mobileHeightM;
}

enum _Align { left, right, center, top }

/// Profile chart with its legend, sized for a bottom sheet.
class TerrainProfileChart extends StatelessWidget {
  const TerrainProfileChart({
    super.key,
    required this.profile,
    this.baseHeightM = 2,
    this.mobileHeightM = 1.5,
    this.height = 190,
  });

  final TerrainProfile? profile;
  final double baseHeightM;
  final double mobileHeightM;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = ProfileChartColors.of(theme.brightness);
    Widget key(Color c, String label, {bool dashed = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: dashed ? 0 : 3,
              decoration: BoxDecoration(
                color: dashed ? null : c,
                border: dashed ? Border(top: BorderSide(color: c)) : null,
              ),
            ),
            const SizedBox(width: 4),
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.inkSecondary)),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              painter: TerrainProfilePainter(
                profile: profile,
                colors: colors,
                baseHeightM: baseHeightM,
                mobileHeightM: mobileHeightM,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 2,
          children: [
            key(colors.series, 'Line of sight'),
            key(colors.series.withValues(alpha: 0.5), 'Fresnel zone'),
            key(colors.series, '60 % of zone', dashed: true),
            key(colors.inkMuted, 'Terrain'),
          ],
        ),
      ],
    );
  }
}
