// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../demo/demo_mode.dart';
import '../../providers.dart';
import '../../services/active_probe_service.dart';
import '../../services/link_asymmetry.dart';
import '../../utils/constants.dart';
import '../protocol_text.dart';
import '../theme/app_theme.dart';
import 'radio_stats_readout.dart';
import 'signal_display.dart' show AirtimeReadout;

// Chart tokens (dark surface; see the dataviz reference palette).
const _surface = Color(0xFF1A1A19);
const _inkPrimary = Color(0xFFF0EFEC);
const _inkSecondary = Color(0xFFC3C2B7);
const _inkMuted = Color(0xFF898781);
const _grid = Color(0xFF2C2C2A);
const _series = Color(0xFF2BD9E6); // the theme's secondary (cyan), dark
// Status colours: always paired with an icon + label.
const _statusGood = Color(0xFF0CA30C);
const _statusWarning = Color(0xFFFAB219);
const _statusCritical = Color(0xFFD03B3B);

/// Live charts of the base → you signal (SNR, RSSI) and ping outcomes,
/// sharing one time axis. Drag across the charts to read values. A ping
/// is a round trip (it reaches the base and the reply comes back), so the
/// strip shows whether replies came back, not whether the base heard us.
class SignalChartsPanel extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const SignalChartsPanel({super.key, required this.onClose});

  @override
  ConsumerState<SignalChartsPanel> createState() => _SignalChartsPanelState();
}

class _SignalChartsPanelState extends ConsumerState<SignalChartsPanel> {
  static const _windows = [
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  // Demo screenshots show the whole recorded walk.
  Duration _window = DemoMode.enabled ? _windows[1] : _windows.first;
  DateTime? _cursor; // crosshair time while touching
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Slide the time axis even when no new samples arrive.
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _cursor == null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(signalHistoryProvider);
    final end = DateTime.now();
    final start = end.subtract(_window);
    final samples = [
      for (final s in history.samples)
        if (!s.time.isBefore(start)) s,
    ];
    final pings = [
      for (final p in history.pings)
        if (!p.sentAt.isBefore(start)) p,
    ];

    final chrome = context.mapChrome;
    return Material(
      color: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(chrome.radius),
        side: BorderSide(color: chrome.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const SizedBox(height: 4),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (d) => _setCursor(
                      d.localPosition.dx, constraints.maxWidth, start),
                  onHorizontalDragUpdate: (d) => _setCursor(
                      d.localPosition.dx, constraints.maxWidth, start),
                  onHorizontalDragEnd: (_) => setState(() => _cursor = null),
                  onTapDown: (d) => _setCursor(
                      d.localPosition.dx, constraints.maxWidth, start),
                  onTapUp: (_) => setState(() => _cursor = null),
                  child: Column(
                    children: [
                      Expanded(
                        flex: 5,
                        child: _LineChart(
                          title: 'SNR',
                          unit: 'dB',
                          points: [
                            for (final s in samples)
                              if (s.snr != null) (s.time, s.snr!),
                          ],
                          start: start,
                          end: end,
                          cursor: _cursor,
                          decimals: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        flex: 5,
                        child: _LineChart(
                          title: 'RSSI',
                          unit: 'dBm',
                          points: [
                            for (final s in samples)
                              if (s.rssi != null) (s.time, s.rssi!.toDouble()),
                          ],
                          start: start,
                          end: end,
                          cursor: _cursor,
                          decimals: 0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Its own height: the key under the strip wraps to
                      // more lines at large text sizes.
                      _PingStrip(
                        pings: pings,
                        noun: probeNoun(
                            ref.watch(meshRadioProvider).protocol,
                            plural: true,
                            capital: true),
                        start: start,
                        end: end,
                        cursor: _cursor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setCursor(double dx, double width, DateTime start) {
    final plotWidth = width - _LineChart.leftPad - _LineChart.rightPad;
    final f = ((dx - _LineChart.leftPad) / plotWidth).clamp(0.0, 1.0);
    setState(() {
      _cursor = start.add(_window * f);
    });
  }

  Widget _header() {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        // Title over the airtime readout: side by side they overflow
        // next to the window chips.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Signal from base',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(color: _inkPrimary)),
              const AirtimeReadout(color: _inkSecondary, fontSize: 11),
              const RadioStatsReadout(color: _inkSecondary, fontSize: 11),
            ],
          ),
        ),
        // Chips and close button shrink together at large text sizes
        // instead of pushing past the panel's edge.
        Flexible(
          flex: 2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final w in _windows)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: ChoiceChip(
                      label: Text(_windowLabel(w)),
                      selected: _window == w,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _window = w),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, color: _inkSecondary),
                  tooltip: 'Close charts',
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _windowLabel(Duration d) =>
      d.inHours >= 1 ? '${d.inHours}h' : '${d.inMinutes}m';
}

// ─── Line chart ────────────────────────────────────────────

class _LineChart extends StatelessWidget {
  static const leftPad = 40.0;
  static const rightPad = 52.0;

  final String title;
  final String unit;
  final List<(DateTime, double)> points;
  final DateTime start;
  final DateTime end;
  final DateTime? cursor;
  final int decimals;

  const _LineChart({
    required this.title,
    required this.unit,
    required this.points,
    required this.start,
    required this.end,
    required this.cursor,
    required this.decimals,
  });

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _LinePainter(
              points: points,
              start: start,
              end: end,
              cursor: cursor,
              decimals: decimals,
            ),
          ),
        ),
        Positioned(
          left: leftPad,
          top: 0,
          child: Text('$title ($unit)',
              style: small?.copyWith(color: _inkSecondary)),
        ),
        if (points.isEmpty)
          Center(
            child: Text('No samples yet',
                style: small?.copyWith(color: _inkMuted)),
          ),
        if (cursor != null && points.isNotEmpty) _tooltip(small),
      ],
    );
  }

  Widget _tooltip(TextStyle? small) {
    final nearest = _nearest(points, cursor!);
    if (nearest == null) return const SizedBox.shrink();
    final ago = DateTime.now().difference(nearest.$1);
    return Positioned(
      right: rightPad,
      top: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _grid),
        ),
        child: Text(
          '${nearest.$2.toStringAsFixed(decimals)} $unit · '
          '${AppConstants.formatSeconds(ago.inSeconds)} ago',
          style: small?.copyWith(color: _inkPrimary),
        ),
      ),
    );
  }
}

(DateTime, double)? _nearest(List<(DateTime, double)> points, DateTime t) {
  (DateTime, double)? best;
  var bestDiff = 1 << 62;
  for (final p in points) {
    final diff = (p.$1.difference(t).inMilliseconds).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = p;
    }
  }
  return best;
}

class _LinePainter extends CustomPainter {
  /// Samples further apart than this aren't joined, so a silent stretch
  /// isn't drawn as if it had data.
  static const _maxGap = Duration(minutes: 2);

  final List<(DateTime, double)> points;
  final DateTime start;
  final DateTime end;
  final DateTime? cursor;
  final int decimals;

  _LinePainter({
    required this.points,
    required this.start,
    required this.end,
    required this.cursor,
    required this.decimals,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const top = 16.0; // room for the title
    const bottom = 4.0;
    final plot = Rect.fromLTRB(
      _LineChart.leftPad,
      top,
      size.width - _LineChart.rightPad,
      size.height - bottom,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    // Y range: data range padded, at least 6 units tall, on nice ticks.
    var lo = points.isEmpty ? -10.0 : points.map((p) => p.$2).reduce(math.min);
    var hi = points.isEmpty ? 10.0 : points.map((p) => p.$2).reduce(math.max);
    if (hi - lo < 6) {
      final mid = (hi + lo) / 2;
      lo = mid - 3;
      hi = mid + 3;
    }
    final step = _niceStep((hi - lo) / 3);
    lo = (lo / step).floor() * step;
    hi = (hi / step).ceil() * step;

    double x(DateTime t) =>
        plot.left +
        plot.width *
            (t.difference(start).inMilliseconds /
                end.difference(start).inMilliseconds);
    double y(double v) => plot.bottom - plot.height * (v - lo) / (hi - lo);

    // Gridlines + y labels (recessive hairlines).
    final gridPaint = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    for (var v = lo; v <= hi + 1e-9; v += step) {
      final yy = y(v);
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), gridPaint);
      _text(canvas, v.toStringAsFixed(step < 1 ? 1 : 0),
          Offset(plot.left - 6, yy), _inkMuted, 10,
          alignRight: true);
    }

    if (points.isNotEmpty) {
      final sorted = [...points]..sort((a, b) => a.$1.compareTo(b.$1));

      // Line, broken across long silences.
      final linePaint = Paint()
        ..color = _series
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      final path = Path();
      for (var i = 0; i < sorted.length; i++) {
        final o = Offset(x(sorted[i].$1), y(sorted[i].$2));
        final joined =
            i > 0 && sorted[i].$1.difference(sorted[i - 1].$1) <= _maxGap;
        joined ? path.lineTo(o.dx, o.dy) : path.moveTo(o.dx, o.dy);
      }
      canvas.save();
      canvas.clipRect(plot.inflate(6));
      canvas.drawPath(path, linePaint);

      // Sample dots while sparse; otherwise only the latest.
      final dots = sorted.length <= 40 ? sorted : [sorted.last];
      for (final p in dots) {
        _dot(canvas, Offset(x(p.$1), y(p.$2)), _series);
      }
      canvas.restore();

      // Direct label: latest value, in ink (not series colour).
      final last = sorted.last;
      _text(canvas, last.$2.toStringAsFixed(decimals),
          Offset(plot.right + 8, y(last.$2)), _inkPrimary, 12,
          bold: true);

      // Crosshair.
      if (cursor != null) {
        final cx = x(cursor!).clamp(plot.left, plot.right);
        canvas.drawLine(
          Offset(cx, plot.top),
          Offset(cx, plot.bottom),
          Paint()
            ..color = _inkMuted
            ..strokeWidth = 1,
        );
        final n = _nearest(sorted, cursor!);
        if (n != null) {
          _dot(canvas, Offset(x(n.$1), y(n.$2)), _inkPrimary, radius: 5);
        }
      }
    }
  }

  static double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final f = raw / mag;
    final nice = f <= 1
        ? 1
        : f <= 2
            ? 2
            : f <= 5
                ? 5
                : 10;
    return nice * mag;
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}

/// Filled marker with a 2px surface ring so it reads over the line.
void _dot(Canvas canvas, Offset o, Color color, {double radius = 4}) {
  canvas.drawCircle(o, radius + 2, Paint()..color = _surface);
  canvas.drawCircle(o, radius, Paint()..color = color);
}

void _text(
  Canvas canvas,
  String s,
  Offset anchor,
  Color color,
  double size, {
  bool alignRight = false,
  bool bold = false,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final dx = alignRight ? anchor.dx - tp.width : anchor.dx;
  tp.paint(canvas, Offset(dx, anchor.dy - tp.height / 2));
}

// ─── Ping strip ────────────────────────────────────────────

class _PingStrip extends StatelessWidget {
  final List<PingSample> pings;
  final DateTime start;
  final DateTime end;
  final DateTime? cursor;

  /// "Pings" / "Link checks".
  final String noun;

  const _PingStrip({
    required this.pings,
    required this.noun,
    required this.start,
    required this.end,
    required this.cursor,
  });

  @override
  Widget build(BuildContext context) {
    final ok = pings.where((p) => p.status == AckStatus.received).length;
    final throttled =
        pings.where((p) => p.status == AckStatus.throttled).length;
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 16,
          child: CustomPaint(
            painter: _PingPainter(pings: pings, start: start, end: end),
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.only(left: _LineChart.leftPad, right: 8, top: 2),
          // The key wraps under the count on narrow phones: side by side
          // it needs ~350 pt, more than an SE or a 393-pt iPhone has.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 2,
            children: [
              Text(
                key: const ValueKey('ping-strip-count'),
                pings.isEmpty
                    ? '$noun: none yet'
                    : cursor != null
                        ? _readout(_nearestPing(pings, cursor!))
                        : '$noun $ok/${pings.length - throttled} came back'
                            '${throttled > 0 ? ' · $throttled throttled' : ''}',
                style: small?.copyWith(color: _inkSecondary),
              ),
              const Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Key(
                      color: _statusGood,
                      icon: Icons.check,
                      label: 'replied'),
                  _Key(
                      color: _statusWarning,
                      icon: Icons.swap_horiz,
                      label: 'relayed'),
                  _Key(
                      color: _statusWarning,
                      icon: Icons.hourglass_bottom,
                      label: 'throttled'),
                  _Key(
                      color: _statusCritical,
                      icon: Icons.close,
                      label: 'no reply'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static PingSample _nearestPing(List<PingSample> pings, DateTime t) =>
      pings.reduce((a, b) =>
          (a.sentAt.difference(t)).abs() <= (b.sentAt.difference(t)).abs()
              ? a
              : b);

  /// The ping under the crosshair: outcome, then Up/Down SNR when the
  /// protocol measures both legs (MeshCore), else the reply's SNR.
  static String _readout(PingSample p) {
    final ms = p.answeredAt.difference(p.sentAt).inMilliseconds;
    return roundTripReadout(
      status: p.status,
      downSnr: p.snr,
      downRssi: p.rssi,
      upSnr: p.uplinkSnr,
      roundTripMs: ms > 0 ? ms : null,
    );
  }
}

class _Key extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;

  const _Key({required this.color, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: _inkSecondary)),
        ],
      ),
    );
  }
}

class _PingPainter extends CustomPainter {
  final List<PingSample> pings;
  final DateTime start;
  final DateTime end;

  _PingPainter({required this.pings, required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    const left = _LineChart.leftPad;
    final right = size.width - _LineChart.rightPad;
    final cy = size.height / 2;
    canvas.drawLine(
      Offset(left, cy),
      Offset(right, cy),
      Paint()
        ..color = _grid
        ..strokeWidth = 1,
    );
    for (final p in pings) {
      final f = p.sentAt.difference(start).inMilliseconds /
          end.difference(start).inMilliseconds;
      final x = left + (right - left) * f;
      final (Color color, IconData icon) = switch (p.status) {
        AckStatus.received => (_statusGood, Icons.check),
        AckStatus.implicit => (_statusWarning, Icons.swap_horiz),
        AckStatus.throttled => (_statusWarning, Icons.hourglass_bottom),
        _ => (_statusCritical, Icons.close),
      };
      _dot(canvas, Offset(x, cy), color, radius: 7);
      // Icon inside the dot so outcome isn't colour-alone.
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: 10,
            color: _surface,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, cy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _PingPainter old) => true;
}
