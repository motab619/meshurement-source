// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/link_asymmetry.dart';
import '../../services/range_stats.dart';
import '../../utils/link_margin.dart';
import '../../utils/signal_color_mapper.dart';

/// Ring spacings tried in order, metres.
const _ringSteps = [100.0, 200.0, 250.0, 500.0, 1000.0, 2000.0, 2500.0, 5000.0];

/// At most this many rings, whatever the radius (a misplaced base 50 km
/// away once drew two hundred 250 m rings with their labels on top of each
/// other).
const polarMaxRings = 6;

/// Distance between rings for a plot reaching [distanceM]: the smallest
/// step from [_ringSteps] that needs at most [polarMaxRings] rings, then
/// doublings of the largest.
double polarRingStepFor(double distanceM) {
  for (final s in _ringSteps) {
    if (distanceM / s <= polarMaxRings) return s;
  }
  var s = _ringSteps.last;
  while (distanceM / s > polarMaxRings) {
    s *= 2;
  }
  return s;
}

/// Outer ring for a plot that must hold [maxDistanceM]: a whole number of
/// rings, at least one. Pass the same value to both plots to share a scale.
double polarOuterRingM(double maxDistanceM) {
  final step = polarRingStepFor(maxDistanceM);
  return math.max(1, (maxDistanceM / step).ceil()) * step;
}

/// Ring label: "250 m", "1 km", "2.5 km".
String polarRingLabel(double m) {
  if (m < 1000) return '${m.round()} m';
  final km = m / 1000;
  return km == km.roundToDouble()
      ? '${km.round()} km'
      : '${km.toStringAsFixed(1)} km';
}

/// What the dots are coloured by.
enum PolarColorMode {
  result('Ping result'),
  snr('Base signal (SNR)');

  final String label;
  const PolarColorMode(this.label);
}

const polarAckedColor = SignalColorMapper.inRange;
const polarMissedColor = SignalColorMapper.outOfRange;
const polarImplicitColor = Color(0xFFE0A100);

/// [scale] is the side's preset (link-margin colours, as on the maps).
Color polarPingColor(PingPoint p, PolarColorMode mode,
    {MarginScale scale = MarginScale.fallback}) {
  if (mode == PolarColorMode.snr) {
    final m = p.snr == null ? null : scale.marginDb(snr: p.snr, rssi: p.rssi);
    return m == null ? SignalColorMapper.noData : SignalColorMapper.fromMargin(m);
  }
  if (p.acked) return polarAckedColor;
  return p.implicit ? polarImplicitColor : polarMissedColor;
}

/// Polar view of one side: the base in the centre, rings every
/// [polarRingStepFor] metres, north up, the walked route as a thin line and every
/// ping as a dot. Tap a dot for its distance, result and SNR.
class RangePolarPlot extends StatefulWidget {
  final SideRangeStats stats;
  final Color accent;

  /// Outer ring in metres; shared by both plots (see [polarOuterRingM]).
  final double outerRingM;
  final PolarColorMode mode;

  const RangePolarPlot({
    super.key,
    required this.stats,
    required this.accent,
    required this.outerRingM,
    required this.mode,
  });

  @override
  State<RangePolarPlot> createState() => _RangePolarPlotState();
}

class _RangePolarPlotState extends State<RangePolarPlot> {
  PingPoint? _selected;

  static const _pad = 22.0;

  Offset _toPx(Size size, double east, double north) {
    final r = math.min(size.width, size.height) / 2 - _pad;
    final k = r / widget.outerRingM;
    return Offset(size.width / 2 + east * k, size.height / 2 - north * k);
  }

  void _tap(Size size, Offset at) {
    PingPoint? best;
    var bestD = 26.0;
    for (final p in widget.stats.pings) {
      final d = (_toPx(size, p.eastM, p.northM) - at).distance;
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    setState(() => _selected = best);
  }

  @override
  void didUpdateWidget(RangePolarPlot old) {
    super.didUpdateWidget(old);
    if (old.stats != widget.stats) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final s = widget.stats;
    final sel = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: widget.accent, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(
                child: Text(s.name,
                    style: text.titleSmall, overflow: TextOverflow.ellipsis)),
          ],
        ),
        const SizedBox(height: 4),
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, c) {
              final size = Size(c.maxWidth, c.maxHeight);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _tap(size, d.localPosition),
                child: CustomPaint(
                  size: size,
                  painter: _PolarPainter(
                    stats: s,
                    accent: widget.accent,
                    outerRingM: widget.outerRingM,
                    mode: widget.mode,
                    selected: sel,
                    ink: scheme.onSurface,
                    textStyle: (text.labelSmall ?? const TextStyle())
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: 34,
          child: Text(
            sel == null ? 'Tap a dot for its readout.' : _readout(sel),
            style: text.bodySmall,
          ),
        ),
      ],
    );
  }

  String _readout(PingPoint p) {
    final result = p.acked
        ? 'ACKed'
        : p.implicit
            ? 'ACK from a relay only'
            : 'missed';
    // A reply needs both legs; its own SNR is base → you. A MeshCore trace
    // also says how well the base heard us (uplink).
    final signal = p.snr == null
        ? ''
        : p.uplinkSnr != null
            ? ' · ${upDownText(p.uplinkSnr!, p.snr!)}'
            : ' · reply SNR ${p.snr!.toStringAsFixed(1)} dB';
    return '${p.distanceM.round()} m from base · $result$signal'
        '${p.rssi == null ? '' : ' · ${p.rssi} dBm'}';
  }
}

class _PolarPainter extends CustomPainter {
  final SideRangeStats stats;
  final Color accent, ink;
  final double outerRingM;
  final PolarColorMode mode;
  final PingPoint? selected;
  final TextStyle textStyle;

  _PolarPainter({
    required this.stats,
    required this.accent,
    required this.outerRingM,
    required this.mode,
    required this.selected,
    required this.ink,
    required this.textStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - _RangePolarPlotState._pad;
    final k = r / outerRingM;
    Offset px(double e, double n) =>
        Offset(centre.dx + e * k, centre.dy - n * k);

    void label(String t, Offset at, {Alignment align = Alignment.center}) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          at -
              Offset(
                  tp.width * (align.x + 1) / 2, tp.height * (align.y + 1) / 2));
    }

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ink.withValues(alpha: 0.18);
    final step = polarRingStepFor(outerRingM);
    final rings = (outerRingM / step).round();
    for (var i = 1; i <= rings; i++) {
      final m = i * step;
      canvas.drawCircle(centre, m * k, ring);
      // Label every other ring once there are more than three.
      if (rings <= 3 || i.isEven) {
        label(polarRingLabel(m),
            centre + Offset(m * k * 0.7071 + 2, -m * k * 0.7071),
            align: Alignment.centerLeft);
      }
    }
    // Axes and north.
    final axis = Paint()
      ..strokeWidth = 1
      ..color = ink.withValues(alpha: 0.12);
    canvas.drawLine(Offset(centre.dx, centre.dy - r),
        Offset(centre.dx, centre.dy + r), axis);
    canvas.drawLine(Offset(centre.dx - r, centre.dy),
        Offset(centre.dx + r, centre.dy), axis);
    label('N', Offset(centre.dx, centre.dy - r - 9));

    // Walked route.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeJoin = StrokeJoin.round
      ..color = accent.withValues(alpha: 0.55);
    for (final route in stats.routes) {
      if (route.length < 2) continue;
      final path = Path()
        ..moveTo(px(route.first.eastM, route.first.northM).dx,
            px(route.first.eastM, route.first.northM).dy);
      for (final p in route.skip(1)) {
        final o = px(p.eastM, p.northM);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, line);
    }

    // Pings: misses first so ACKs stay visible on top.
    final ordered = [
      ...stats.pings.where((p) => p.missed),
      ...stats.pings.where((p) => !p.missed),
    ];
    final fill = Paint();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.9);
    final scale = MarginScale.forPresetId(stats.presetId);
    for (final p in ordered) {
      final o = px(p.eastM, p.northM);
      fill.color = polarPingColor(p, mode, scale: scale);
      canvas.drawCircle(o, 3.6, fill);
      canvas.drawCircle(o, 3.6, edge);
    }
    final sel = selected;
    if (sel != null) {
      canvas.drawCircle(
          px(sel.eastM, sel.northM),
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = ink);
    }

    // Base diamond.
    final d = Path()
      ..moveTo(centre.dx, centre.dy - 6)
      ..lineTo(centre.dx + 6, centre.dy)
      ..lineTo(centre.dx, centre.dy + 6)
      ..lineTo(centre.dx - 6, centre.dy)
      ..close();
    canvas.drawPath(d, Paint()..color = ink);
    label('base', centre + const Offset(9, 9), align: Alignment.topLeft);
  }

  @override
  bool shouldRepaint(_PolarPainter old) =>
      old.stats != stats ||
      old.mode != mode ||
      old.selected != selected ||
      old.outerRingM != outerRingM ||
      old.ink != ink;
}
