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
import '../report_painters.dart';
import '../report_parts.dart';
import '../report_style.dart';
import '../report_theme.dart';

/// The Pop Field Report theme (docs/design/field-report/themes.md):
/// bubbly and friendly on a warm cream, flat pastel blobs and pills, a
/// soft lilac route with small outlined dots. The pastels are blue, pink
/// and lilac only, so nothing reads as a green, yellow, orange or red
/// signal colour; every signal dot gets a dark ink ring so yellow still
/// shows on white.
class PopReportCard extends StatelessWidget {
  const PopReportCard({super.key, required this.report});

  final ThemedReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final frame = RouteFrame.of([r.route]);
    final body = switch (r.format) {
      ReportFormat.feed => _feed(frame),
      ReportFormat.story => _story(frame),
      ReportFormat.wide => _wide(frame),
    };
    return SizedBox.fromSize(
      size: r.format.size,
      child: ColoredBox(
        color: PopPalette.bg,
        child: Stack(
          children: [
            Positioned.fill(
                child: CustomPaint(painter: PopBackdropPainter(r.format))),
            Positioned.fill(child: body),
          ],
        ),
      ),
    );
  }

  Widget _routeWithNote(RouteFrame frame,
      {double dot = 8, double s = 1, double gap = 12}) {
    final route = PopRouteBlob(
        route: report.route, frame: frame, miles: report.miles, dot: dot);
    final note = report.note;
    if (note == null) return route;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: route),
        SizedBox(height: gap),
        PopNoteLine(note: note, scale: s),
      ],
    );
  }

  Widget _feed(RouteFrame frame) {
    final r = report;
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 46, 56, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PopHeader(title: r.title, subtitle: r.subtitle),
          const SizedBox(height: 26),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _routeWithNote(frame)),
                const SizedBox(width: 26),
                SizedBox(
                  width: 384,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Headline(data: r.data, miles: r.miles, size: 80),
                      const SizedBox(height: 20),
                      Expanded(
                        child: _MarginCard(data: r.data, chipsPerRow: 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _StatBubbles(data: r.data, miles: r.miles),
          const SizedBox(height: 24),
          SizedBox(height: 250, child: _ChartCard(data: r.data)),
          const SizedBox(height: 20),
          _SetupPills(data: r.data),
          const SizedBox(height: 18),
          const PopFooter(),
        ],
      ),
    );
  }

  Widget _story(RouteFrame frame) {
    final r = report;
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 72, 64, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PopHeader(title: r.title, subtitle: r.subtitle, scale: 1.1),
          const SizedBox(height: 30),
          _Headline(data: r.data, miles: r.miles, size: 100, wide: true),
          const SizedBox(height: 28),
          Expanded(child: _routeWithNote(frame, dot: 9)),
          const SizedBox(height: 28),
          _MarginCard(data: r.data, chipsPerRow: 4),
          const SizedBox(height: 26),
          _StatBubbles(data: r.data, miles: r.miles, scale: 1.05),
          const SizedBox(height: 26),
          SizedBox(height: 280, child: _ChartCard(data: r.data)),
          const SizedBox(height: 24),
          _SetupPills(data: r.data),
          const SizedBox(height: 22),
          const PopFooter(),
        ],
      ),
    );
  }

  Widget _wide(RouteFrame frame) {
    final r = report;
    const s = 0.74;
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 30, 40, 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
              width: 520,
              child: _routeWithNote(frame, dot: 7, s: 0.9, gap: 14)),
          const SizedBox(width: 30),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PopHeader(title: r.title, subtitle: r.subtitle, scale: s),
                const Spacer(),
                _Headline(
                    data: r.data, miles: r.miles, size: 64, wide: true, s: s),
                const Spacer(),
                _MarginCard(
                    data: r.data, chipsPerRow: 4, compact: true, scale: s),
                const Spacer(),
                _StatBubbles(
                    data: r.data, miles: r.miles, scale: 0.8, twoRows: true),
                const Spacer(),
                const PopFooter(scale: 0.85),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The theme's palette and type. Pastels stay in blue, pink and lilac so
/// they never read as a signal colour.
class PopPalette {
  PopPalette._();

  static const bg = Color(0xFFFFF3E4);
  static const ink = Color(0xFF2E2546);
  static const soft = Color(0xFF6F6488);
  static const white = Color(0xFFFFFFFF);
  static const violet = Color(0xFF6C4BF4);
  static const lilac = Color(0xFFE6DCFF);
  static const sky = Color(0xFFCDE7FF);
  static const pink = Color(0xFFFFD4E4);
  static const aqua = Color(0xFFCBEFF4);
  static const blush = Color(0xFFFBE3F5);
  static const track = Color(0xFFD3CAEE);
  static const hot = Color(0xFFFF5C9A);

  /// Fredoka is a variable font: the weight is set on the wght axis too.
  static const family = 'Fredoka';

  static TextStyle _fredoka(double size, double weight, Color color) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        color: color,
        fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
        fontVariations: [FontVariation('wght', weight)],
        decoration: TextDecoration.none,
      );

  /// Fredoka has no italic; [italic] is kept for callers and ignored.
  static TextStyle sans(double size,
          {Color color = ink, bool bold = false, bool italic = false}) =>
      _fredoka(size, bold ? 600 : 400, color).copyWith(height: 1.15);

  /// A number readout in bold Fredoka (proportional figures, no gap after
  /// a decimal point).
  static TextStyle number(double size, {Color color = ink}) =>
      _fredoka(size, 700, color).copyWith(height: 1.0);

  /// Short capital tags (BASE, MOBILE, RANGE); never numbers.
  static TextStyle mono(double size,
          {Color color = ink, bool bold = false, double spacing = 0}) =>
      _fredoka(size, bold ? 600 : 500, color)
          .copyWith(letterSpacing: spacing, height: 1.1);

  static Color signal(double marginDb) =>
      SignalColorMapper.fromMargin(marginDb);
}

/// A few flat decorative circles behind everything.
class PopBackdropPainter extends CustomPainter {
  PopBackdropPainter(this.format);
  final ReportFormat format;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    void blob(double x, double y, double r, Color c) =>
        canvas.drawCircle(Offset(x, y), r, Paint()..color = c);
    blob(w + 40, -30, 210, PopPalette.pink);
    blob(w - 150, 40, 46, PopPalette.sky);
    blob(-70, h + 40, 190, PopPalette.lilac);
    if (format != ReportFormat.wide) {
      blob(90, h - 40, 26, PopPalette.pink);
      blob(-40, h * 0.42, 70, PopPalette.sky);
      blob(w + 20, h * 0.66, 60, PopPalette.lilac);
    }
  }

  @override
  bool shouldRepaint(PopBackdropPainter old) => old.format != format;
}

/// Three dots, the heading, then the title in an ink pill.
class PopHeader extends StatelessWidget {
  const PopHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.scale = 1,
    this.stacked = false,
  });

  final String title, subtitle;
  final double scale;

  /// Subtitle on its own line (wide), so the title keeps its room.
  final bool stacked;

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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              popDot(26 * s, PopPalette.violet),
              SizedBox(width: 6 * s),
              popDot(18 * s, PopPalette.hot),
              SizedBox(width: 6 * s),
              popDot(12 * s, PopPalette.ink),
              SizedBox(width: 18 * s),
              Text(reportHeading,
                  style: PopPalette.sans(60 * s, bold: true)
                      .copyWith(height: 1.0, letterSpacing: -1 * s)),
            ],
          ),
        ),
        SizedBox(height: 14 * s),
        Row(
          children: [
            Flexible(
              flex: stacked ? 1 : 5,
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 20 * s, vertical: 8 * s),
                decoration: BoxDecoration(
                  color: PopPalette.ink,
                  borderRadius: BorderRadius.circular(40 * s),
                ),
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PopPalette.sans(26 * s,
                        color: PopPalette.white, bold: true)),
              ),
            ),
            if (subtitle.isNotEmpty && !stacked) ...[
              SizedBox(width: 14 * s),
              Flexible(
                flex: 2,
                child: Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PopPalette.sans(24 * s, color: PopPalette.soft)),
              ),
            ],
          ],
        ),
        if (subtitle.isNotEmpty && stacked) ...[
          SizedBox(height: 8 * s),
          Padding(
            padding: EdgeInsets.only(left: 20 * s),
            child: Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PopPalette.sans(24 * s, color: PopPalette.soft)),
          ),
        ],
      ],
    );
  }
}

/// A flat filled circle.
Widget popDot(double d, Color c) => Container(
    width: d,
    height: d,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle));

/// The big number in a violet bubble: farthest point the base was heard,
/// or the route length / readings when there is no distance to show
/// (same fallback as the Night card's BragTile).
class _Headline extends StatelessWidget {
  const _Headline({
    required this.data,
    required this.miles,
    required this.size,
    this.wide = false,
    this.s = 1,
  });

  final FieldReportData data;
  final bool miles;
  final double size;

  /// Value and caption side by side (story, wide).
  final bool wide;
  final double s;

  @override
  Widget build(BuildContext context) {
    final far = data.farthestM;
    final value = far != null
        ? reportDistance(far, miles)
        : data.routeM >= 50
            ? reportDistance(data.routeM, miles)
            : '${data.samples.length}';
    final caption = far != null
        ? 'farthest point the base was heard'
        : data.routeM >= 50
            ? 'route length'
            : data.samples.length == 1
                ? 'reading'
                : 'readings';
    final valueText = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(value.replaceAll(' ', '\u00A0'),
          maxLines: 1, style: PopPalette.number(size, color: PopPalette.white)),
    );
    final captionText = Text(caption,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: PopPalette.sans((wide ? 30 : 26) * s,
            color: PopPalette.white.withValues(alpha: 0.92), bold: true));
    return Container(
      padding: EdgeInsets.fromLTRB(34 * s, 26 * s, 30 * s, 26 * s),
      decoration: BoxDecoration(
        color: PopPalette.violet,
        borderRadius: BorderRadius.circular(56 * s),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -6 * s,
            top: -10 * s,
            child: Row(
              children: [
                _ring(22 * s),
                SizedBox(width: 8 * s),
                _ring(14 * s),
              ],
            ),
          ),
          wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(flex: 5, child: valueText),
                    SizedBox(width: 26 * s),
                    Expanded(flex: 4, child: captionText),
                    SizedBox(width: 30 * s),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(right: 40 * s),
                      child: valueText,
                    ),
                    SizedBox(height: 12 * s),
                    captionText,
                  ],
                ),
        ],
      ),
    );
  }

  static Widget _ring(double d) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: PopPalette.white.withValues(alpha: 0.25),
        ),
      );
}

/// White card with a soft lilac rim, the panel of this theme.
class PopPanel extends StatelessWidget {
  const PopPanel({
    super.key,
    required this.child,
    this.padding,
    this.radius = 44,
    this.rim = PopPalette.lilac,
    this.rimWidth = 4,
  });

  final Widget child;
  final EdgeInsets? padding;
  final double radius;
  final Color rim;
  final double rimWidth;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: PopPalette.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: rim, width: rimWidth),
        ),
        child: child,
      );
}

/// Signal margin: a fat pill split by band, then a chip per band.
class _MarginCard extends StatelessWidget {
  const _MarginCard({
    required this.data,
    required this.chipsPerRow,
    this.compact = false,
    this.scale = 1,
  });

  final FieldReportData data;
  final int chipsPerRow;

  /// No subtitle (wide).
  final bool compact;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final preset = data.presetName.isEmpty ? 'range setting' : data.presetName;
    final buckets = data.buckets;
    final total = buckets.fold<int>(0, (a, b) => a + b.count);
    final rows = <List<MarginBucket>>[
      for (var i = 0; i < buckets.length; i += chipsPerRow)
        buckets.sublist(i, math.min(i + chipsPerRow, buckets.length)),
    ];
    return PopPanel(
      padding: EdgeInsets.fromLTRB(26 * s, 20 * s, 26 * s, 22 * s),
      child: ScaleDownBox(
        alignment: Alignment.center,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Signal margin', style: PopPalette.sans(30 * s, bold: true)),
            if (!compact) ...[
              SizedBox(height: 4 * s),
              Text('How far above the $preset limit',
                  maxLines: chipsPerRow > 2 ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: PopPalette.sans(19 * s, color: PopPalette.soft)),
            ],
            SizedBox(height: 14 * s),
            _SplitPill(buckets: buckets, total: total, height: 34 * s),
            for (final row in rows) ...[
              SizedBox(height: 12 * s),
              Row(
                children: [
                  for (var i = 0; i < chipsPerRow; i++) ...[
                    if (i > 0) SizedBox(width: 10 * s),
                    Expanded(
                      child: i < row.length
                          ? _BandChip(bucket: row[i], scale: s)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SplitPill extends StatelessWidget {
  const _SplitPill(
      {required this.buckets, required this.total, required this.height});

  final List<MarginBucket> buckets;
  final int total;
  final double height;

  @override
  Widget build(BuildContext context) {
    final parts = [
      for (final b in buckets)
        if (b.count > 0) b
    ];
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: PopPalette.lilac,
        borderRadius: BorderRadius.circular(height),
        border: Border.all(color: PopPalette.ink, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: total == 0
            ? const SizedBox.expand()
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < parts.length; i++) ...[
                    if (i > 0) Container(width: 3, color: PopPalette.ink),
                    Expanded(
                      flex: math.max(1, parts[i].count),
                      child: ColoredBox(
                          color:
                              PopPalette.signal(parts[i].band.colourMarginDb)),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _BandChip extends StatelessWidget {
  const _BandChip({required this.bucket, this.scale = 1});

  final MarginBucket bucket;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      padding: EdgeInsets.fromLTRB(12 * s, 9 * s, 14 * s, 9 * s),
      decoration: BoxDecoration(
        color: PopPalette.bg,
        borderRadius: BorderRadius.circular(30 * s),
      ),
      child: Row(
        children: [
          Container(
            width: 22 * s,
            height: 22 * s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: PopPalette.signal(bucket.band.colourMarginDb),
              border: Border.all(color: PopPalette.ink, width: 2 * s),
            ),
          ),
          SizedBox(width: 10 * s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(bucket.band.label,
                      maxLines: 1,
                      style: PopPalette.sans(18 * s,
                          color: PopPalette.soft, bold: true)),
                ),
                SizedBox(height: 3 * s),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('${bucket.pct}%',
                      maxLines: 1, style: PopPalette.number(30 * s)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Route, time, readings, median margin, base heard as pastel bubbles:
/// one row of five, or (wide, [twoRows]) three over two, every value the
/// same size and every label on one line.
class _StatBubbles extends StatelessWidget {
  const _StatBubbles({
    required this.data,
    required this.miles,
    this.scale = 1,
    this.twoRows = false,
  });

  final FieldReportData data;
  final bool miles;
  final double scale;
  final bool twoRows;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final pct = data.baseHeardPct;
    final stats = <(String, String, Color)>[
      (reportDistance(data.routeM, miles), 'route', PopPalette.sky),
      (reportDuration(data.duration), 'time', PopPalette.pink),
      ('${data.samples.length}', 'readings', PopPalette.lilac),
      (
        data.medianMarginDb == null ? '-' : reportDb(data.medianMarginDb!),
        'median margin',
        PopPalette.aqua
      ),
      (pct == null ? '-' : '$pct%', 'base heard', PopPalette.blush),
    ];
    final height = (twoRows ? 92 : 124) * s;
    Widget bubble((String, String, Color) st) => Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: 14 * s),
          decoration: BoxDecoration(
            color: st.$3,
            borderRadius: BorderRadius.circular(height / 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(st.$1.replaceAll(' ', '\u00A0'),
                    maxLines: 1, style: PopPalette.number(40 * s)),
              ),
              SizedBox(height: 8 * s),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(st.$2,
                    maxLines: 1,
                    style: PopPalette.sans(20 * s,
                            color: PopPalette.soft, bold: true)
                        .copyWith(height: 1.0)),
              ),
            ],
          ),
        );
    Widget row(List<(String, String, Color)> items) => Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) SizedBox(width: 14 * s),
              Expanded(child: bubble(items[i])),
            ],
          ],
        );
    if (!twoRows) return row(stats);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row(stats.sublist(0, 3)),
        SizedBox(height: 12 * s),
        row(stats.sublist(3)),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.data});

  final FieldReportData data;

  @override
  Widget build(BuildContext context) {
    return PopPanel(
      padding: const EdgeInsets.fromLTRB(28, 20, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Margin over the session',
              style: PopPalette.sans(28, bold: true)),
          const SizedBox(height: 10),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _BubbleChartPainter(data.marginOverTime),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded columns per time bin, each capped with an outlined dot on the
/// margin ramp; an empty bin is a faint stub (a gap, not a zero).
class _BubbleChartPainter extends CustomPainter {
  _BubbleChartPainter(this.bins);
  final List<double?> bins;

  static const _top = 24.0, _bottom = -4.0;

  @override
  void paint(Canvas canvas, Size size) {
    const labelW = 96.0, bottomPad = 30.0, topPad = 20.0;
    final w = size.width - labelW;
    final h = size.height - bottomPad - topPad;
    final floorY = topPad + h;
    double yOf(double m) =>
        topPad +
        (1 - (m.clamp(_bottom, _top) - _bottom) / (_top - _bottom)) * h;

    final guide = Paint()
      ..color = PopPalette.track
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final (m, label) in [
      (20.0, 'Strong'),
      (10.0, 'Good'),
      (0.0, 'Limit'),
    ]) {
      final y = yOf(m);
      for (var x = 4.0; x < w - 4; x += 16) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), guide);
      }
      popText(canvas, label, Offset(w + 14, y),
          PopPalette.sans(18, color: PopPalette.soft, bold: true),
          middle: true);
    }

    final n = bins.length;
    if (n == 0) return;
    final slot = w / n;
    final colW = math.min(slot * 0.5, 34.0);
    final dotR = math.min(colW * 0.5, 14.0);
    for (var i = 0; i < n; i++) {
      final cx = slot * (i + 0.5);
      final v = bins[i];
      if (v == null) {
        canvas.drawCircle(
            Offset(cx, floorY - 6), 6, Paint()..color = PopPalette.track);
        continue;
      }
      final y = yOf(v);
      final c = PopPalette.signal(v);
      final col = RRect.fromLTRBR(
          cx - colW / 2, y, cx + colW / 2, floorY, Radius.circular(colW / 2));
      canvas.drawRRect(col, Paint()..color = c.withValues(alpha: 0.28));
      canvas.drawCircle(Offset(cx, y), dotR, Paint()..color = c);
      canvas.drawCircle(
          Offset(cx, y),
          dotR,
          Paint()
            ..color = PopPalette.ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5);
    }
    final small = PopPalette.sans(18, color: PopPalette.soft, bold: true);
    popText(canvas, 'Start', Offset(slot * 0.5 - 20, size.height - 22), small);
    final endW = popMeasure('End', small);
    popText(canvas, 'End',
        Offset(slot * (n - 0.5) + 20 - endW, size.height - 22), small);
  }

  @override
  bool shouldRepaint(_BubbleChartPainter old) => old.bins != bins;
}

/// A pastel pill holding an ink tag (BASE, RANGE...) and a value.
class PopTagPill extends StatelessWidget {
  const PopTagPill({
    super.key,
    required this.tag,
    required this.value,
    required this.color,
    this.scale = 1,
    this.valueColor = PopPalette.ink,
  });

  final String tag, value;
  final Color color;
  final double scale;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      height: 58 * s,
      padding: EdgeInsets.fromLTRB(8 * s, 8 * s, 18 * s, 8 * s),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(29 * s),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 7 * s),
            decoration: BoxDecoration(
              color: PopPalette.ink,
              borderRadius: BorderRadius.circular(22 * s),
            ),
            child: Text(tag,
                style: PopPalette.mono(15 * s,
                    color: PopPalette.white, bold: true, spacing: 1.5 * s)),
          ),
          SizedBox(width: 10 * s),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  maxLines: 1,
                  style:
                      PopPalette.sans(21 * s, bold: true, color: valueColor)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Base, mobile and range setting as pills.
class _SetupPills extends StatelessWidget {
  const _SetupPills({required this.data});

  final FieldReportData data;

  @override
  Widget build(BuildContext context) {
    final setup = data.setup;
    String join(String a, String b) {
      final v = [a, b].where((x) => x.trim().isNotEmpty).join(' · ');
      return v.isEmpty ? 'not recorded' : v;
    }

    final range = [
      data.presetName.isEmpty ? 'Mixed' : data.presetName,
      if (setup.txPowerDbm != null) '${setup.txPowerDbm} dBm',
    ].join(' · ');
    final pills = <(String, String, Color)>[
      ('BASE', join(setup.baseRadio, setup.baseAntenna), PopPalette.sky),
      ('MOBILE', join(setup.mobileRadio, setup.mobileAntenna), PopPalette.pink),
      ('RANGE', range, PopPalette.lilac),
    ];
    return Row(
      children: [
        for (var i = 0; i < pills.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: PopTagPill(
                tag: pills[i].$1, value: pills[i].$2, color: pills[i].$3),
          ),
        ],
      ],
    );
  }
}

/// The card's note, after a pink "i" dot.
class PopNoteLine extends StatelessWidget {
  const PopNoteLine(
      {super.key, required this.note, this.scale = 1, this.maxLines = 3});

  final String note;
  final double scale;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: EdgeInsets.only(top: 1 * s),
          width: 22 * s,
          height: 22 * s,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
              color: PopPalette.hot, shape: BoxShape.circle),
          child: Text('i',
              style:
                  PopPalette.sans(15 * s, color: PopPalette.white, bold: true)),
        ),
        SizedBox(width: 10 * s),
        Expanded(
          child: Text(note,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: PopPalette.sans(19 * s, color: PopPalette.soft)
                  .copyWith(height: 1.25)),
        ),
      ],
    );
  }
}

class PopFooter extends StatelessWidget {
  const PopFooter({super.key, this.scale = 1});
  final double scale;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Text(AppInfo.website,
            style: PopPalette.sans(21 * scale,
                color: PopPalette.soft, bold: true)),
      );
}

/// The route on a white blob.
class PopRouteBlob extends StatelessWidget {
  const PopRouteBlob({
    super.key,
    required this.route,
    required this.frame,
    required this.miles,
    required this.dot,
    this.scaleBar = true,
    this.scale = 1,
  });

  final PrivateRoute route;
  final RouteFrame frame;
  final bool miles;
  final double dot;

  /// Draw the scale bar (a comparison draws one on the first route only).
  final bool scaleBar;

  /// Size of the labels, track and rims (1 on a single-session card).
  final double scale;

  @override
  Widget build(BuildContext context) => PopPanel(
        radius: 52 * scale,
        rimWidth: 4 * math.min(1.0, scale + 0.2),
        child: CustomPaint(
          painter: PopRoutePainter(
              route: route,
              frame: frame,
              miles: miles,
              dotRadius: dot,
              scaleBar: scaleBar,
              s: scale),
        ),
      );
}

/// Soft lilac track, small outlined dots (weakest on top), the hidden
/// base area as a pink bubble ringed with little dots, and a pill scale
/// bar. Draws only the [PrivateRoute] it is given.
class PopRoutePainter extends CustomPainter {
  PopRoutePainter({
    required this.route,
    required this.frame,
    required this.miles,
    required this.dotRadius,
    this.scaleBar = true,
    this.s = 1,
  });

  final PrivateRoute route;
  final RouteFrame frame;
  final bool miles;
  final double dotRadius;
  final bool scaleBar;
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(48 * s)));

    // Polka dots, very faint, so the blob isn't a blank sheet.
    final polka = Paint()..color = PopPalette.bg;
    final step = 44.0 * s;
    var row = 0;
    for (var y = step / 2; y < size.height; y += step, row++) {
      for (var x = (row.isOdd ? step : step / 2); x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 3.5 * s, polka);
      }
    }

    final view = RouteView(frame, size);
    final scale = view.scale;
    final at = view.at;

    final o = at(0, 0);
    final r = route.hideRadiusM * scale;
    if (route.origin != ReportOrigin.none) {
      if (r > 4) {
        canvas.drawCircle(o, r, Paint()..color = PopPalette.pink);
        final n = math.max(10, (2 * math.pi * r / (22 * s)).round());
        final ringDot = Paint()..color = PopPalette.hot;
        for (var i = 0; i < n; i++) {
          final a = 2 * math.pi * i / n;
          canvas.drawCircle(
              o + Offset(math.cos(a) * r, math.sin(a) * r), 3 * s, ringDot);
        }
      } else {
        canvas.drawCircle(o, 10 * s, Paint()..color = PopPalette.hot);
        canvas.drawCircle(
            o,
            10 * s,
            Paint()
              ..color = PopPalette.ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5 * s);
      }
    }

    final line = Paint()
      ..color = PopPalette.track
      ..strokeWidth = math.max(6.0, dotRadius * 1.1)
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final seg in route.segments) {
      if (seg.length < 2) continue;
      final p0 = at(seg[0].x, seg[0].y);
      final path = Path()..moveTo(p0.dx, p0.dy);
      for (final p in seg.skip(1)) {
        final q = at(p.x, p.y);
        path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(path, line);
    }

    final dots = [...route.dots]
      ..sort((a, b) => b.marginDb.compareTo(a.marginDb));
    final ring = Paint()
      ..color = PopPalette.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, dotRadius * 0.22);
    for (final d in dots) {
      final p = at(d.x, d.y);
      canvas.drawCircle(
          p, dotRadius, Paint()..color = PopPalette.signal(d.marginDb));
      canvas.drawCircle(p, dotRadius, ring);
    }

    if (route.origin != ReportOrigin.none) {
      _originLabel(canvas, size, view, o, r,
          route.origin == ReportOrigin.base ? 'BASE' : 'START');
    }

    if (scaleBar) _scaleBar(canvas, size, view);
    canvas.restore();
  }

  /// A fat ink pill, label above, in the corner the route leaves emptiest.
  void _scaleBar(Canvas canvas, Size size, RouteView view) {
    final scale = view.scale;
    final at = view.at;
    final maxM = (size.width * 0.3) / scale;
    final (m, label) = niceScaleBar(maxM, miles: miles);
    final w = m * scale;
    final drawn = [
      for (final d in route.dots) at(d.x, d.y),
      for (final seg in route.segments)
        for (final p in seg) at(p.x, p.y),
    ];
    final inset = 30 * s;
    final corners = [
      for (final bottom in [true, false])
        for (final right in [true, false])
          (
            right ? size.width - inset - w : inset,
            bottom ? size.height - 28 * s : 54.0 * s,
          ),
    ];
    int crowd((double, double) c) {
      final box = Rect.fromLTRB(c.$1 - dotRadius - 8, c.$2 - 40 * s,
          c.$1 + w + dotRadius + 8, c.$2 + 14 * s);
      return drawn.where(box.contains).length;
    }

    var best = corners.first;
    for (final c in corners.skip(1)) {
      if (crowd(c) < crowd(best)) best = c;
    }
    final x0 = best.$1, y = best.$2, x1 = x0 + w;
    canvas.drawLine(
        Offset(x0, y),
        Offset(x1, y),
        Paint()
          ..color = PopPalette.ink
          ..strokeWidth = 8 * s
          ..strokeCap = StrokeCap.round);
    popText(canvas, label.replaceAll(' ', '\u00A0'),
        Offset((x0 + x1) / 2, y - 22 * s), PopPalette.number(20 * s),
        center: true);
  }

  /// BASE / START as an ink pill: inside a big hidden-area bubble, else
  /// above, below, left or right of it, whichever covers the fewest dots.
  void _originLabel(Canvas canvas, Size size, RouteView view, Offset o,
      double r, String text) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: PopPalette.mono(18 * s,
              color: PopPalette.white, bold: true, spacing: 2 * s)),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + 24 * s, h = tp.height + 10 * s;
    var c = o;
    if (r <= 60 * s) {
      final rr = math.max(r, 10 * s) + 8 * s;
      final drawn = [
        for (final d in route.dots) view.at(d.x, d.y),
        for (final seg in route.segments)
          for (final p in seg) view.at(p.x, p.y),
      ];
      final inside = (Offset.zero & size).deflate(6 * s);
      int cost(Offset at) {
        final box =
            Rect.fromCenter(center: at, width: w, height: h).inflate(dotRadius);
        final out =
            inside.contains(box.topLeft) && inside.contains(box.bottomRight)
                ? 0
                : 1000;
        return out + drawn.where(box.contains).length;
      }

      final options = [
        o + Offset(0, -(rr + h / 2)),
        o + Offset(0, rr + h / 2),
        o + Offset(-(rr + w / 2), 0),
        o + Offset(rr + w / 2, 0),
      ];
      c = options.first;
      for (final opt in options.skip(1)) {
        if (cost(opt) < cost(c)) c = opt;
      }
    }
    final box = Rect.fromCenter(center: c, width: w, height: h);
    canvas.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(h / 2)),
        Paint()..color = PopPalette.ink);
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(PopRoutePainter old) =>
      old.route != route ||
      old.frame != frame ||
      old.miles != miles ||
      old.dotRadius != dotRadius ||
      old.scaleBar != scaleBar ||
      old.s != s;
}

double popMeasure(String text, TextStyle style) => (TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout())
        .width;

void popText(Canvas canvas, String text, Offset at, TextStyle style,
    {bool center = false, bool middle = false}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final dx = center ? at.dx - tp.width / 2 : at.dx;
  final dy = center || middle ? at.dy - tp.height / 2 : at.dy;
  tp.paint(canvas, Offset(dx, dy));
}
