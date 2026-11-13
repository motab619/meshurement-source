// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/guided/plan_models.dart';
import '../../theme/app_theme.dart';
import 'guided_styles.dart';

/// Distance for the compass readout: whole metres under 1 km, else km
/// with one decimal.
String formatGoToDistance(double? m) {
  if (m == null) return '—';
  if (m < 1000) return '${m.round()} m';
  return '${(m / 1000).toStringAsFixed(1)} km';
}

/// A ring with an orange arrow rotated to the target's bearing, next to
/// the big mono distance and a caption ("TO THE BASE" / "TO THE START
/// PIN"). Without a fix the arrow is dimmed and the distance a dash.
class GoToCompass extends StatelessWidget {
  const GoToCompass({super.key, required this.state, required this.caption});

  final GoToState state;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dist = formatGoToDistance(state.distanceM);
    final unitAt = dist.indexOf(' ');
    final value = unitAt < 0 ? dist : dist.substring(0, unitAt);
    final unit = unitAt < 0 ? '' : dist.substring(unitAt);
    final hasFix = state.bearingDeg != null;
    return GuidedCard(
      child: SizedBox(
        height: 150,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: CustomPaint(
                painter: _CompassPainter(
                  bearingDeg: state.bearingDeg ?? 0,
                  ring: scheme.outlineVariant,
                  arrow: hasFix
                      ? (state.arrived ? theme.status.ok : scheme.primary)
                      : theme.status.neutral,
                ),
              ),
            ),
            const SizedBox(width: 20),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: value,
                    style: context.readout.valueLarge.copyWith(fontSize: 40),
                    children: [
                      TextSpan(
                        text: unit,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ],
                  ),
                  key: const ValueKey('goto-distance'),
                ),
                Text(caption, style: context.guidedMonoLabel),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  const _CompassPainter({
    required this.bearingDeg,
    required this.ring,
    required this.arrow,
  });

  final double bearingDeg;
  final Color ring;
  final Color arrow;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(
      c,
      r - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring,
    );
    // Arrow from the mock: tip at the top, notched tail.
    final s = r / 50; // the mock is a 100 × 100 box
    final path = Path()
      ..moveTo(0, -40 * s)
      ..lineTo(14 * s, 8 * s)
      ..lineTo(0, -2 * s)
      ..lineTo(-14 * s, 8 * s)
      ..close();
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(bearingDeg * math.pi / 180);
    canvas.drawPath(path, Paint()..color = arrow);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompassPainter old) =>
      old.bearingDeg != bearingDeg || old.ring != ring || old.arrow != arrow;
}
