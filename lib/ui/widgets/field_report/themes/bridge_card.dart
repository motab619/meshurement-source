// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../../services/field_report/field_report_data.dart';
import '../../../../services/field_report/private_route.dart';
import '../../../../services/units.dart';
import '../../../../utils/app_info.dart';
import '../../../../utils/signal_color_mapper.dart';
import '../../../theme/app_theme.dart';
import '../report_painters.dart';
import '../report_parts.dart' show reportHeading;
import '../report_style.dart';
import '../report_theme.dart';

/// The Bridge Field Report theme (docs/design/field-report/themes.md): a
/// generic starship instrument panel, drawn like a vector display: thin
/// tick rulers down the left, one per section, with the section code in
/// corner brackets; hairline header and footer strips; data in bracketed
/// readouts; the route on a dark scanner grid with square markers and
/// range rings around the base. Teal, steel blue and a pale phosphor
/// white; numbers that can hold a decimal point use B612, not the mono
/// face. Every number on it is real session data.
class BridgeReportCard extends StatelessWidget {
  const BridgeReportCard({super.key, required this.report});

  final ThemedReport report;

  @override
  Widget build(BuildContext context) {
    final size = report.format.size;
    return SizedBox.fromSize(
      size: size,
      child: ColoredBox(
        color: BridgeColors.bg,
        child: switch (report.format) {
          ReportFormat.feed => _feed(),
          ReportFormat.story => _story(),
          ReportFormat.wide => _wide(),
        },
      ),
    );
  }

  FieldReportData get _d => report.data;

  Widget _feed() {
    const s = 1.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 36, 36, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 58, child: _TopBar(report: report, s: s)),
          const SizedBox(height: 14),
          SizedBox(height: 82, child: _TitleRow(report: report, s: s)),
          const SizedBox(height: 16),
          SizedBox(
            height: 500,
            child: BridgeSection(
              code: 'SCAN',
              color: BridgeColors.teal,
              s: s,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _Scanner(report: report, dot: 9, s: s)),
                  const SizedBox(width: 18),
                  SizedBox(
                    width: 392,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Headline(
                            report: report, s: s, valueSize: 84, twoLine: true),
                        const SizedBox(height: 16),
                        Expanded(child: _SignalSplit(data: _d, s: s)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 112,
            child: BridgeSection(
              code: 'DATA',
              color: BridgeColors.steel,
              s: s,
              child: _Stats(report: report, s: s),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: BridgeSection(
              code: 'TRND',
              color: BridgeColors.pale,
              s: s,
              child: _Trend(data: _d, s: s),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 124,
            child: BridgeSection(
              code: 'CONF',
              color: BridgeColors.teal,
              s: s,
              child: _Setup(data: _d, s: s),
            ),
          ),
          if (report.note != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: _railW + _railGap),
              child: _Note(text: report.note!, s: s),
            ),
          ],
          const SizedBox(height: 14),
          const SizedBox(height: 34, child: _BottomBar(s: s)),
        ],
      ),
    );
  }

  Widget _story() {
    const s = 1.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 44, 40, 38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 62, child: _TopBar(report: report, s: s)),
          const SizedBox(height: 16),
          SizedBox(height: 88, child: _TitleRow(report: report, s: s)),
          const SizedBox(height: 18),
          SizedBox(
            height: 300,
            child: BridgeSection(
              code: 'RNGE',
              color: BridgeColors.pale,
              s: s,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _Headline(
                        report: report, s: s, valueSize: 136, fill: true),
                  ),
                  const SizedBox(width: 18),
                  Expanded(child: _SignalSplit(data: _d, s: s)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 700,
            child: BridgeSection(
              code: 'SCAN',
              color: BridgeColors.teal,
              s: s,
              child: _Scanner(report: report, dot: 11, s: s),
            ),
          ),
          if (report.note != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: _railW + _railGap),
              child: _Note(text: report.note!, s: s),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 124,
            child: BridgeSection(
              code: 'DATA',
              color: BridgeColors.steel,
              s: s,
              child: _Stats(report: report, s: s),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: BridgeSection(
              code: 'TRND',
              color: BridgeColors.pale,
              s: s,
              child: _Trend(data: _d, s: s),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 134,
            child: BridgeSection(
              code: 'CONF',
              color: BridgeColors.teal,
              s: s,
              child: _Setup(data: _d, s: s),
            ),
          ),
          const SizedBox(height: 18),
          const SizedBox(height: 36, child: _BottomBar(s: s)),
        ],
      ),
    );
  }

  Widget _wide() {
    const s = 0.8;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 46, child: _TopBar(report: report, s: s)),
          const SizedBox(height: 10),
          SizedBox(height: 62, child: _TitleRow(report: report, s: s)),
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
                    width: 470,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _Scanner(report: report, dot: 7, s: s)),
                        if (report.note != null) ...[
                          const SizedBox(height: 6),
                          _Note(text: report.note!, s: s, lines: 2),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Headline(report: report, s: s, valueSize: 80),
                        const SizedBox(height: 10),
                        Expanded(
                            child: _SignalSplit(data: _d, s: s, compact: true)),
                        const SizedBox(height: 10),
                        SizedBox(
                            height: 84, child: _Stats(report: report, s: s)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 28, child: _BottomBar(s: s)),
        ],
      ),
    );
  }
}

/// The console palette: teal, steel blue and a pale phosphor white on
/// near-black, like a vector display. Signal data keeps the app's
/// green → red margin ramp.
class BridgeColors {
  static const bg = Color(0xFF040709);
  static const panel = Color(0xFF081014);
  static const line = Color(0xFF1F3542);
  static const teal = Color(0xFF1EC8B6);

  /// The highlight: pale yellow-white (the base, the headline, the
  /// winner).
  static const pale = Color(0xFFF1EDC9);
  static const steel = Color(0xFF5B8DBF);
  static const white = Color(0xFFE6EFF2);
  static const dim = Color(0xFF8AA0AD);
  static const ink = Color(0xFF03080A);
  static const unlit = Color(0xFF14212A);
}

/// Width of the section ruler on the left, and the gap after it.
const bridgeRailW = 44.0;
const bridgeRailGap = 14.0;
const _railW = bridgeRailW;
const _railGap = bridgeRailGap;

/// A small label size at scale [s], never under 15 px.
double bridgeSmall(double px, double s) => math.max(15.0, px * s);

TextStyle bridgeMono(double size,
        {Color color = BridgeColors.white,
        bool bold = false,
        double spacing = 0}) =>
    TextStyle(
      fontFamily: ReadoutStyles.monoFamily,
      fontSize: size,
      color: color,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      letterSpacing: spacing,
      height: 1.1,
      decoration: TextDecoration.none,
    );

TextStyle bridgeSans(double size,
        {Color color = BridgeColors.white, bool bold = false}) =>
    TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: size,
      color: color,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      height: 1.2,
      decoration: TextDecoration.none,
    );

/// A flat block with one chamfered corner (tags only).
class _Block extends StatelessWidget {
  const _Block({
    required this.color,
    this.child,
    this.chamfer = 10,
    this.padding = EdgeInsets.zero,
  });

  final Color color;
  final Widget? child;
  final double chamfer;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: ShapeDecoration(
        color: color,
        shape: BeveledRectangleBorder(
            borderRadius:
                BorderRadius.only(bottomRight: Radius.circular(chamfer))),
      ),
      child: child,
    );
  }
}

/// A section: a thin tick ruler down the left, capped top and bottom like
/// a bracket, with the section code written up it, beside [child].
class BridgeSection extends StatelessWidget {
  const BridgeSection(
      {super.key,
      required this.code,
      required this.color,
      required this.child,
      required this.s});

  final String code;
  final Color color;
  final Widget child;
  final double s;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _railW * s,
          child: CustomPaint(painter: _RailPainter(code, color, s)),
        ),
        SizedBox(width: _railGap * s),
        Expanded(child: child),
      ],
    );
  }
}

class _RailPainter extends CustomPainter {
  _RailPainter(this.code, this.color, this.s);

  final String code;
  final Color color;
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final x = 3 * s;
    final spine = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 2;
    final cap = Paint()
      ..color = color
      ..strokeWidth = 3 * s
      ..strokeCap = StrokeCap.square;
    final minor = Paint()
      ..color = BridgeColors.line
      ..strokeWidth = 2;
    final major = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 2;

    // The code, written bottom to top near the top, in corner brackets.
    final tp = _layoutText(
        code,
        bridgeMono(bridgeSmall(17, s),
            color: color, bold: true, spacing: 3 * s));
    final codeTop = 16 * s;
    final codeLen = tp.width;
    final cx = size.width - 4 * s - tp.height / 2;
    canvas.save();
    canvas.translate(cx - tp.height / 2, codeTop + codeLen);
    canvas.rotate(-math.pi / 2);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
    final codeRect = Rect.fromLTWH(cx - tp.height / 2 - 5 * s, codeTop - 7 * s,
        tp.height + 10 * s, codeLen + 14 * s);
    bridgeBrackets(
        canvas,
        codeRect,
        6 * s,
        Paint()
          ..color = color.withValues(alpha: 0.7)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke);

    // Spine and ticks; the ticks stop short of the code.
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), spine);
    final step = 12 * s;
    var k = 0;
    for (var y = step; y < size.height - step / 2; y += step, k++) {
      final isMajor = k % 5 == 4;
      final len = isMajor ? 14 * s : 7 * s;
      if (y > codeRect.top - 4 &&
          y < codeRect.bottom + 4 &&
          x + len > codeRect.left) {
        canvas.drawLine(Offset(x, y), Offset(x + 7 * s, y), minor);
        continue;
      }
      canvas.drawLine(
          Offset(x, y), Offset(x + len, y), isMajor ? major : minor);
    }
    // Bracket caps.
    final w = 18 * s;
    canvas.drawLine(Offset(x, 1.5 * s), Offset(x + w, 1.5 * s), cap);
    canvas.drawLine(Offset(x, size.height - 1.5 * s),
        Offset(x + w, size.height - 1.5 * s), cap);
    // A lit square at the bottom of the ruler.
    canvas.drawRect(
        Rect.fromLTWH(size.width - 12 * s, size.height - 12 * s, 8 * s, 8 * s),
        Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.code != code || old.color != color || old.s != s;
}

/// A hairline strip with corner brackets, for the header and footer.
class BridgeStrip extends StatelessWidget {
  const BridgeStrip(
      {super.key, required this.child, required this.s, this.padding});

  final Widget child;
  final double s;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _BracketPainter(BridgeColors.teal, 14 * s, 3 * s),
      child: Container(
        padding: padding ?? EdgeInsets.symmetric(horizontal: 18 * s),
        decoration: BoxDecoration(
          border: Border.all(color: BridgeColors.line, width: 1.5),
        ),
        child: child,
      ),
    );
  }
}

/// A small reticle (square, cross, centre dot) for the rail's corner.
class BridgeReticle extends StatelessWidget {
  const BridgeReticle({super.key, required this.s});
  final double s;

  @override
  Widget build(BuildContext context) => SizedBox(
      width: _railW * s, child: CustomPaint(painter: _ReticlePainter(s)));
}

class _ReticlePainter extends CustomPainter {
  _ReticlePainter(this.s);
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(3 * s + 15 * s, size.height / 2);
    final r = 13 * s;
    final p = Paint()
      ..color = BridgeColors.teal
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    bridgeBrackets(canvas, Rect.fromCircle(center: c, radius: r), 6 * s, p);
    canvas.drawLine(c - Offset(r + 4 * s, 0), c - Offset(4 * s, 0), p);
    canvas.drawLine(c + Offset(4 * s, 0), c + Offset(r + 4 * s, 0), p);
    canvas.drawLine(c - Offset(0, r + 4 * s), c - Offset(0, 4 * s), p);
    canvas.drawLine(c + Offset(0, 4 * s), c + Offset(0, r + 4 * s), p);
    canvas.drawRect(Rect.fromCircle(center: c, radius: 2.5 * s),
        Paint()..color = BridgeColors.pale);
  }

  @override
  bool shouldRepaint(_ReticlePainter old) => old.s != s;
}

/// Header: reticle, "LORA FIELD REPORT" in a hairline strip, [info] (dim
/// caps) and a small filled [tag] at its right.
class BridgeHeader extends StatelessWidget {
  const BridgeHeader(
      {super.key, required this.info, required this.tag, required this.s});

  final String info, tag;
  final double s;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BridgeReticle(s: s),
        SizedBox(width: _railGap * s),
        Expanded(
          child: BridgeStrip(
            s: s,
            padding: EdgeInsets.fromLTRB(18 * s, 0, 10 * s, 0),
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(reportHeading.toUpperCase(),
                        style: bridgeMono(28 * s,
                            color: BridgeColors.pale,
                            bold: true,
                            spacing: 5 * s)),
                  ),
                ),
                SizedBox(width: 16 * s),
                Text(info,
                    style: bridgeMono(bridgeSmall(20, s),
                        color: BridgeColors.dim, spacing: 1.5 * s)),
                SizedBox(width: 14 * s),
                Center(child: BridgeTag(tag, s: s, color: BridgeColors.teal)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Header of the single-session card: the survey date and reading count.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.report, required this.s});

  final ThemedReport report;
  final double s;

  @override
  Widget build(BuildContext context) {
    final d = report.data;
    final date =
        DateFormat('yyyy-MM-dd', 'en_US').format(d.startedAt.toLocal());
    return BridgeHeader(
        info: 'SURVEY $date', tag: '${d.samples.length} RDG', s: s);
  }
}

/// Title (white) and subtitle (teal caps), in line with the content.
class BridgeTitle extends StatelessWidget {
  const BridgeTitle(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.s});

  final String title, subtitle;
  final double s;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: (_railW + _railGap) * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: bridgeSans(40 * s, bold: true).copyWith(height: 1.05)),
          if (subtitle.isNotEmpty) ...[
            SizedBox(height: 6 * s),
            Text(subtitle.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: bridgeMono(bridgeSmall(21, s),
                    color: BridgeColors.teal, spacing: 3 * s)),
          ],
        ],
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.report, required this.s});

  final ThemedReport report;
  final double s;

  @override
  Widget build(BuildContext context) =>
      BridgeTitle(title: report.title, subtitle: report.subtitle, s: s);
}

/// Footer: a tick ruler, the website and a lit square.
class BridgeFooter extends StatelessWidget {
  const BridgeFooter({super.key, required this.s});
  final double s;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: (_railW + _railGap) * s),
        Expanded(child: CustomPaint(painter: _RulerPainter(s))),
        SizedBox(width: 16 * s),
        Center(
          child: Text(AppInfo.website.toUpperCase(),
              style: bridgeMono(bridgeSmall(20, s),
                  color: BridgeColors.dim, spacing: 2 * s)),
        ),
        SizedBox(width: 14 * s),
        Center(
          child: Container(
              width: 12 * s, height: 12 * s, color: BridgeColors.pale),
        ),
      ],
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter(this.s);
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2 + 6 * s;
    final base = Paint()
      ..color = BridgeColors.steel.withValues(alpha: 0.6)
      ..strokeWidth = 2;
    final minor = Paint()
      ..color = BridgeColors.line
      ..strokeWidth = 2;
    final major = Paint()
      ..color = BridgeColors.teal.withValues(alpha: 0.8)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), base);
    final step = 14 * s;
    var k = 0;
    for (var x = 0.0; x <= size.width; x += step, k++) {
      final isMajor = k % 5 == 0;
      canvas.drawLine(Offset(x, y), Offset(x, y - (isMajor ? 14 : 7) * s),
          isMajor ? major : minor);
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) => old.s != s;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.s});
  final double s;

  @override
  Widget build(BuildContext context) => BridgeFooter(s: s);
}

/// A dark readout box with bracket corners.
class BridgeReadout extends StatelessWidget {
  const BridgeReadout({
    super.key,
    required this.child,
    required this.s,
    this.accent = BridgeColors.teal,
    this.padding,
  });

  final Widget child;
  final double s;
  final Color accent;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _BracketPainter(accent, 18 * s, 3 * s),
      child: Container(
        padding: padding ?? EdgeInsets.all(16 * s),
        decoration: BoxDecoration(
          color: BridgeColors.panel,
          border: Border.all(color: BridgeColors.line, width: 1.5),
        ),
        child: child,
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  _BracketPainter(this.color, this.len, this.width);

  final Color color;
  final double len, width;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    bridgeBrackets(canvas, Offset.zero & size, len, p);
  }

  @override
  bool shouldRepaint(_BracketPainter old) =>
      old.color != color || old.len != len || old.width != width;
}

/// Four L-shaped corner marks just inside [r].
void bridgeBrackets(Canvas canvas, Rect r, double len, Paint p) {
  final i = p.strokeWidth / 2;
  final a = r.deflate(i);
  for (final (c, dx, dy) in [
    (a.topLeft, 1.0, 1.0),
    (a.topRight, -1.0, 1.0),
    (a.bottomLeft, 1.0, -1.0),
    (a.bottomRight, -1.0, -1.0),
  ]) {
    canvas.drawPath(
        Path()
          ..moveTo(c.dx + dx * len, c.dy)
          ..lineTo(c.dx, c.dy)
          ..lineTo(c.dx, c.dy + dy * len),
        p);
  }
}

/// A small filled tag with dark caps text.
class BridgeTag extends StatelessWidget {
  const BridgeTag(this.text,
      {super.key, required this.s, this.color = BridgeColors.pale});

  final String text;
  final double s;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _Block(
      color: color,
      chamfer: 8 * s,
      padding: EdgeInsets.fromLTRB(10 * s, 4 * s, 14 * s, 4 * s),
      child: Text(text,
          maxLines: 1,
          style: bridgeMono(bridgeSmall(17, s),
              color: BridgeColors.ink, bold: true, spacing: 1.5 * s)),
    );
  }
}

/// The headline: farthest point the base was heard, or the same fallback
/// as the default card (route length, then the reading count).
class _Headline extends StatelessWidget {
  const _Headline(
      {required this.report,
      required this.s,
      required this.valueSize,
      this.fill = false,
      this.twoLine = false});

  /// Break the caption in two balanced lines (narrow column).
  final bool twoLine;

  final ThemedReport report;
  final double s, valueSize;

  /// Spread over the height it is given (story).
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final data = report.data, miles = report.miles;
    final far = data.farthestM;
    final n = data.samples.length;
    final value = far != null
        ? reportDistance(far, miles)
        : data.routeM >= 50
            ? reportDistance(data.routeM, miles)
            : '$n';
    final tag = far != null
        ? 'MAX RANGE · BASE HEARD'
        : data.routeM >= 50
            ? 'ROUTE LENGTH'
            : n == 1
                ? 'READING'
                : 'READINGS';
    final caption = far != null
        ? 'Farthest point the${twoLine ? '\n' : ' '}base node was heard'
        : data.routeM >= 50
            ? 'Route length'
            : n == 1
                ? 'Signal reading'
                : 'Signal readings';
    final children = [
      BridgeTag(tag, s: s),
      SizedBox(height: 8 * s),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(value,
            style:
                bridgeSans(valueSize * s, color: BridgeColors.teal, bold: true)
                    .copyWith(height: 1.05)),
      ),
      SizedBox(height: 4 * s),
      Text(caption,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: bridgeSans(21 * s, color: BridgeColors.dim)),
    ];
    return BridgeReadout(
      s: s,
      accent: BridgeColors.pale,
      padding: EdgeInsets.fromLTRB(18 * s, 16 * s, 18 * s, 14 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment:
            fill ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
        children: fill
            ? [
                children[0],
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: children[2],
                  ),
                ),
                children[4],
              ]
            : children,
      ),
    );
  }
}

/// Strong / Good / Weak / Below limit as 20-segment level bars.
class _SignalSplit extends StatelessWidget {
  const _SignalSplit(
      {required this.data, required this.s, this.compact = false});

  final FieldReportData data;
  final double s;

  /// No dB ranges under the band names (wide).
  final bool compact;

  static const _segments = 20;

  @override
  Widget build(BuildContext context) {
    final limit = '${data.snrFloorDb.toStringAsFixed(1)} dB';
    return BridgeReadout(
      s: s,
      padding: EdgeInsets.fromLTRB(16 * s, 14 * s, 16 * s, 12 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('SIGNAL MARGIN',
                  style: bridgeMono(19 * s,
                      color: BridgeColors.teal, bold: true, spacing: 2 * s)),
              SizedBox(width: 10 * s),
              Expanded(
                child: Text(compact ? 'LIMIT $limit SNR' : 'LIMIT $limit',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: bridgeSans(bridgeSmall(16, s),
                        color: BridgeColors.dim)),
              ),
            ],
          ),
          SizedBox(height: 6 * s),
          Container(height: 2, color: BridgeColors.line),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final b in data.buckets) _row(b),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(MarginBucket b) {
    final colour = SignalColorMapper.fromMargin(b.band.colourMarginDb);
    final lit = b.pct == 0 ? 0 : math.max(1, (b.pct * _segments / 100).round());
    return Row(
      children: [
        SizedBox(
          width: (compact ? 136 : 116) * s,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(b.band.label.toUpperCase(),
                    maxLines: 1,
                    style: bridgeMono(bridgeSmall(17, s), bold: true)),
              ),
              if (!compact)
                Text(b.band.range,
                    maxLines: 1,
                    style: bridgeMono(15 * s, color: BridgeColors.dim)),
            ],
          ),
        ),
        SizedBox(width: 8 * s),
        Expanded(
          child: SizedBox(
            height: 20 * s,
            child: Row(
              children: [
                for (var i = 0; i < _segments; i++)
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: 3 * s),
                      color: i < lit ? colour : BridgeColors.unlit,
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 66 * s,
          child: Text('${b.pct}%',
              textAlign: TextAlign.right,
              style: bridgeMono(23 * s, bold: true)),
        ),
      ],
    );
  }
}

/// Route, time, readings, median margin, base heard as readout blocks.
class _Stats extends StatelessWidget {
  const _Stats({required this.report, required this.s});

  final ThemedReport report;
  final double s;

  @override
  Widget build(BuildContext context) {
    final data = report.data;
    final pct = data.baseHeardPct;
    final stats = <(String, String)>[
      (reportDistance(data.routeM, report.miles), 'ROUTE'),
      (reportDuration(data.duration), 'TIME'),
      ('${data.samples.length}', 'READINGS'),
      (
        data.medianMarginDb == null ? '-' : reportDb(data.medianMarginDb!),
        'MEDIAN MARGIN'
      ),
      (pct == null ? '-' : '$pct%', 'BASE HEARD'),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) SizedBox(width: 8 * s),
          Expanded(
            child: BridgeStat(
              label: stats[i].$2,
              value: stats[i].$1,
              s: s,
              accent: i == 4 ? BridgeColors.pale : BridgeColors.steel,
            ),
          ),
        ],
      ],
    );
  }
}

/// One readout: a hairline box with a short accent tick on its top edge,
/// a small caps [label] (wraps to two lines when narrow) and a bold
/// [value] scaled to fit below it.
class BridgeStat extends StatelessWidget {
  const BridgeStat({
    super.key,
    required this.label,
    required this.value,
    required this.s,
    this.accent = BridgeColors.steel,
    this.valueSize = 38,
    this.valueColor = BridgeColors.white,
    this.labelLines = 2,
  });

  final String label, value;
  final double s, valueSize;
  final Color accent, valueColor;

  /// 1 keeps the label on one line, shrunk a little if it must.
  final int labelLines;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _TickPainter(accent, s),
      child: Container(
        padding: EdgeInsets.fromLTRB(12 * s, 11 * s, 10 * s, 6 * s),
        decoration: BoxDecoration(
          color: BridgeColors.panel,
          border: Border.all(color: BridgeColors.line, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (labelLines == 1)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(label,
                    maxLines: 1,
                    style: bridgeMono(bridgeSmall(15, s),
                        color: BridgeColors.teal, bold: true, spacing: 1 * s)),
              )
            else
              Text(label,
                  maxLines: labelLines,
                  overflow: TextOverflow.ellipsis,
                  style: bridgeMono(bridgeSmall(15, s),
                      color: BridgeColors.teal, bold: true, spacing: 1 * s)),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Text(value,
                    maxLines: 1,
                    style:
                        bridgeSans(valueSize * s, color: valueColor, bold: true)
                            .copyWith(height: 1.05)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short thick accent line on the top-left of a box, and a small one on
/// the bottom-right.
class _TickPainter extends CustomPainter {
  _TickPainter(this.color, this.s);
  final Color color;
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    canvas.drawRect(Rect.fromLTWH(0, 0, 30 * s, 4 * s), p);
    canvas.drawRect(Rect.fromLTWH(0, 0, 4 * s, 12 * s), p);
    canvas.drawRect(
        Rect.fromLTWH(size.width - 10 * s, size.height - 3 * s, 10 * s, 3 * s),
        Paint()..color = color.withValues(alpha: 0.6));
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color || old.s != s;
}

/// Margin over the session as segmented level columns.
class _Trend extends StatelessWidget {
  const _Trend({required this.data, required this.s});

  final FieldReportData data;
  final double s;

  @override
  Widget build(BuildContext context) {
    return BridgeReadout(
      s: s,
      padding: EdgeInsets.fromLTRB(16 * s, 12 * s, 16 * s, 10 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('MARGIN OVER THE SESSION',
                  style: bridgeMono(19 * s,
                      color: BridgeColors.teal, bold: true, spacing: 2 * s)),
              const Spacer(),
              Text('MEDIAN PER INTERVAL',
                  style: bridgeMono(bridgeSmall(15, s),
                      color: BridgeColors.dim, spacing: 1 * s)),
            ],
          ),
          SizedBox(height: 8 * s),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _TrendPainter(
                  data.marginOverTime, reportDuration(data.duration), s),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.bins, this.durationLabel, this.s);

  final List<double?> bins;
  final String durationLabel;
  final double s;

  static const _lo = -5.0, _hi = 25.0, _step = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final labelW = 92 * s, bottom = 24 * s;
    final w = size.width - labelW;
    final h = size.height - bottom;
    if (h <= 10 || bins.isEmpty) return;
    double yOf(double m) => (1 - (m - _lo) / (_hi - _lo)) * h;

    final levels = ((_hi - _lo) / _step).round();
    final segH = h / levels;
    final n = bins.length;
    final colW = w / n;
    final gapX = math.max(4.0, colW * 0.18);
    final gapY = math.max(1.5, math.min(4.0, segH * 0.28));

    for (var i = 0; i < n; i++) {
      final x0 = i * colW + gapX / 2, x1 = (i + 1) * colW - gapX / 2;
      final v = bins[i];
      for (var k = 0; k < levels; k++) {
        final lo = _lo + k * _step;
        final top = h - (k + 1) * segH + gapY / 2;
        final rect = Rect.fromLTRB(x0, top, x1, top + segH - gapY);
        final on = v != null && v.clamp(_lo, _hi) > lo;
        canvas.drawRect(
            rect,
            Paint()
              ..color = on
                  ? SignalColorMapper.fromMargin(lo + _step / 2)
                  : BridgeColors.unlit);
      }
      if (v == null) {
        // No readings in this interval: an empty frame, not a zero.
        canvas.drawRect(
            Rect.fromLTRB(x0, 0, x1, h),
            Paint()
              ..color = BridgeColors.line
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
        canvas.drawRect(Rect.fromLTRB(x0 + 2, 2, x1 - 2, h - 2),
            Paint()..color = BridgeColors.panel);
      }
    }

    for (final (m, label, colour) in [
      (20.0, 'STRONG', BridgeColors.dim),
      (10.0, 'GOOD', BridgeColors.dim),
      (0.0, 'LIMIT', BridgeColors.pale),
    ]) {
      final y = yOf(m);
      canvas.drawLine(
          Offset(0, y),
          Offset(w + 6 * s, y),
          Paint()
            ..color = colour.withValues(alpha: m == 0 ? 0.9 : 0.5)
            ..strokeWidth = m == 0 ? 2.5 : 1.5);
      _text(canvas, label, Offset(w + 12 * s, y),
          bridgeMono(bridgeSmall(15, s), color: colour),
          vCenter: true);
    }

    final small =
        bridgeMono(bridgeSmall(15, s), color: BridgeColors.dim, spacing: 1 * s);
    _text(canvas, 'START', Offset(gapX / 2, h + 6 * s), small);
    _text(canvas, 'END  $durationLabel', Offset(w - gapX / 2, h + 6 * s), small,
        right: true);
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.bins != bins || old.durationLabel != durationLabel || old.s != s;
}

/// Base, mobile and range setting readouts.
class _Setup extends StatelessWidget {
  const _Setup({required this.data, required this.s});

  final FieldReportData data;
  final double s;

  @override
  Widget build(BuildContext context) {
    final setup = data.setup;
    String or(String v) => v.isEmpty ? 'not recorded' : v;
    final range = <(String, String)>[
      ('PRESET', data.presetName.isEmpty ? 'Mixed' : data.presetName),
      ('LIMIT', '${data.snrFloorDb.toStringAsFixed(1)} dB SNR'),
      if (setup.txPowerDbm != null) ('POWER', '${setup.txPowerDbm} dBm'),
      if (setup.frequencyMhz != null)
        ('FREQ', '${setup.frequencyMhz!.toStringAsFixed(3)} MHz'),
    ];
    Widget box(String title, Color accent, List<(String, String)> rows) =>
        Expanded(
          child: CustomPaint(
            foregroundPainter: _TickPainter(accent, s),
            child: Container(
              padding: EdgeInsets.fromLTRB(14 * s, 12 * s, 14 * s, 8 * s),
              decoration: BoxDecoration(
                color: BridgeColors.panel,
                border: Border.all(color: BridgeColors.line, width: 1.5),
              ),
              child: BridgeFitColumn(
                children: [
                  Text(title,
                      style: bridgeMono(bridgeSmall(17, s),
                          color: accent, bold: true, spacing: 2.5 * s)),
                  for (final (k, v) in rows)
                    Padding(
                      padding: EdgeInsets.only(top: 5 * s),
                      child: Row(
                        children: [
                          Text(k,
                              style: bridgeMono(bridgeSmall(15, s),
                                  color: BridgeColors.dim)),
                          SizedBox(width: 8 * s),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(v,
                                  maxLines: 1,
                                  style: bridgeSans(18 * s, bold: true)),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        box('BASE NODE', BridgeColors.pale, [
          ('RADIO', or(setup.baseRadio)),
          ('ANTENNA', or(setup.baseAntenna)),
        ]),
        SizedBox(width: 8 * s),
        box('MOBILE', BridgeColors.steel, [
          ('RADIO', or(setup.mobileRadio)),
          ('ANTENNA', or(setup.mobileAntenna)),
        ]),
        SizedBox(width: 8 * s),
        box('RANGE SETTING', BridgeColors.teal, range),
      ],
    );
  }
}

/// A column that shrinks to fit the height it is given.
class BridgeFitColumn extends StatelessWidget {
  const BridgeFitColumn({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: box.maxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// The note line, behind a NOTE tag.
class _Note extends StatelessWidget {
  const _Note({required this.text, required this.s, this.lines = 2});

  final String text;
  final double s;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BridgeTag('NOTE', s: s, color: BridgeColors.steel),
        SizedBox(width: 10 * s),
        Expanded(
          child: Text(text,
              maxLines: lines,
              overflow: TextOverflow.ellipsis,
              style: bridgeSans(bridgeSmall(18, s), color: BridgeColors.dim)),
        ),
      ],
    );
  }
}

/// The scanner of the single-session card.
class _Scanner extends StatelessWidget {
  const _Scanner({required this.report, required this.dot, required this.s});

  final ThemedReport report;
  final double dot, s;

  @override
  Widget build(BuildContext context) => BridgeScanner(
        route: report.route,
        frame: RouteFrame.of([report.route]),
        miles: report.miles,
        dot: dot,
        s: s,
      );
}

/// The scanner: a private route on a dark grid with square markers, range
/// rings around the base and bracket corners in [accent]. Comparison
/// cards pass one shared [frame] so every side has the same scale.
class BridgeScanner extends StatelessWidget {
  const BridgeScanner({
    super.key,
    required this.route,
    required this.frame,
    required this.miles,
    required this.dot,
    required this.s,
    this.scaleBar = true,
    this.accent = BridgeColors.teal,
  });

  final PrivateRoute route;
  final RouteFrame frame;
  final bool miles, scaleBar;
  final double dot, s;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BridgeColors.panel,
        border: Border.all(color: BridgeColors.line, width: 1.5),
      ),
      child: CustomPaint(
        size: Size.infinite,
        painter: _ScannerPainter(
          route: route,
          frame: frame,
          miles: miles,
          dot: dot,
          s: s,
          scaleBar: scaleBar,
          accent: accent,
        ),
      ),
    );
  }
}

class _ScannerPainter extends CustomPainter {
  _ScannerPainter({
    required this.route,
    required this.frame,
    required this.miles,
    required this.dot,
    required this.s,
    required this.scaleBar,
    required this.accent,
  });

  final PrivateRoute route;
  final RouteFrame frame;
  final bool miles, scaleBar;
  final double dot, s;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);

    final view = RouteView(frame, size);
    final scale = view.scale;
    final o = view.at(0, 0);

    // Grid through the origin, with ticks on the frame.
    final step = 56 * s;
    final grid = Paint()
      ..color = BridgeColors.teal.withValues(alpha: 0.09)
      ..strokeWidth = 1.5;
    final tick = Paint()
      ..color = BridgeColors.teal.withValues(alpha: 0.5)
      ..strokeWidth = 2;
    double first(double c) => c - (c / step).floor() * step;
    for (var x = first(o.dx); x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(x, 0), Offset(x, 10 * s), tick);
      canvas.drawLine(
          Offset(x, size.height), Offset(x, size.height - 10 * s), tick);
    }
    for (var y = first(o.dy); y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      canvas.drawLine(Offset(0, y), Offset(10 * s, y), tick);
      canvas.drawLine(
          Offset(size.width, y), Offset(size.width - 10 * s, y), tick);
    }

    // Every drawn point on screen, to keep labels off the data.
    final pts = <Offset>[
      for (final seg in route.segments)
        for (final p in seg) view.at(p.x, p.y),
      for (final d in route.dots) view.at(d.x, d.y),
    ];
    final ringLabels = <(Offset, String)>[];

    // Scale bar: in the corner with the fewest drawn points.
    final (barM, barLabel) =
        niceScaleBar(size.width * 0.28 / scale, miles: miles);
    final barW = barM * scale;
    final lp = _layoutText(barLabel,
        bridgeSans(bridgeSmall(17, s), color: BridgeColors.white, bold: true));
    final boxW = math.max(barW, lp.width) + 20 * s;
    final boxH = lp.height + 30 * s;
    final inset = 22 * s;
    Rect? barBox;
    var fewest = 1 << 30;
    for (final (left, top) in !scaleBar
        ? const <(bool, bool)>[]
        : [
            (false, false),
            (true, false),
            (false, true),
            (true, true),
          ]) {
      final x = left ? inset : size.width - inset - boxW;
      final y = top ? inset : size.height - inset - boxH;
      final box = Rect.fromLTWH(x, y, boxW, boxH);
      final hit = box.inflate(dot + 4 * s);
      final n = pts.where(hit.contains).length + (hit.contains(o) ? 1000 : 0);
      if (n < fewest) {
        fewest = n;
        barBox = box;
      }
    }

    // Where the BASE / START tag goes (rings keep their labels off it).
    final tagStyle =
        bridgeMono(bridgeSmall(17, s), color: BridgeColors.ink, bold: true);
    final tagText = route.origin == ReportOrigin.base ? 'BASE' : 'START';
    final tagTp = _layoutText(tagText, tagStyle);
    final hideR0 = route.hideRadiusM * scale;
    final tagTy = hideR0 > 60 * s
        ? o.dy - hideR0 * 0.45
        : o.dy - math.max(hideR0, 9 * s) - 14 * s - tagTp.height;
    final tagBox = Rect.fromLTWH(o.dx - tagTp.width / 2 - 8 * s, tagTy - 3 * s,
        tagTp.width + 16 * s, tagTp.height + 6 * s);
    final taken = <Rect>[
      if (route.origin != ReportOrigin.none) tagBox.inflate(8 * s),
    ];

    // Range rings around the base, labelled with their true distance.
    if (route.origin == ReportOrigin.base) {
      final far = math.max(
          math.max((o - rect.topLeft).distance, (o - rect.topRight).distance),
          math.max(
              (o - rect.bottomLeft).distance, (o - rect.bottomRight).distance));
      final (ringM, _) = niceScaleBar(
          math.sqrt(size.width * size.height) / 3.2 / scale,
          miles: miles);
      final ring = Paint()
        ..color = BridgeColors.teal.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * s;
      final hideR = route.hideRadiusM * scale;
      for (var k = 1; k * ringM * scale < far && k < 12; k++) {
        final r = k * ringM * scale;
        if (r < hideR + 8 * s) continue;
        canvas.drawCircle(o, r, ring);
        // Label where the ring is farthest from any drawn point.
        Offset? best;
        var bestGap = 0.0;
        for (var i = 0; i < 16; i++) {
          final a = -math.pi / 4 + i * math.pi / 8;
          final at = o + Offset(r * math.cos(a), r * math.sin(a));
          final labelBox =
              Rect.fromCenter(center: at, width: 84 * s, height: 30 * s);
          if (!rect.deflate(36 * s).contains(at) ||
              (barBox?.inflate(40 * s).contains(at) ?? false) ||
              taken.any(labelBox.overlaps)) {
            continue;
          }
          var gap = double.infinity;
          for (final q in pts) {
            gap = math.min(gap, (q - at).distance);
          }
          if (gap > bestGap + 0.5) {
            bestGap = gap;
            best = at;
          }
        }
        if (best != null && bestGap > 34 * s) {
          taken.add(Rect.fromCenter(center: best, width: 84 * s, height: 30 * s)
              .inflate(12 * s));
          ringLabels.add((best, formatDistance(k * ringM, miles: miles)));
        }
      }
    }

    // Hidden base (or start) area.
    if (route.origin != ReportOrigin.none) {
      final r = hideR0;
      final pale = Paint()
        ..color = BridgeColors.pale
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * s;
      if (r > 6) {
        canvas.drawCircle(
            o, r, Paint()..color = BridgeColors.pale.withValues(alpha: 0.10));
        _dashedCircle(canvas, o, r, pale);
      }
      final c = 9 * s;
      canvas.drawLine(o - Offset(c, 0), o + Offset(c, 0), pale);
      canvas.drawLine(o - Offset(0, c), o + Offset(0, c), pale);
      canvas.drawRect(tagBox, Paint()..color = BridgeColors.pale);
      tagTp.paint(canvas, Offset(tagBox.left + 8 * s, tagBox.top + 3 * s));
    }

    // Track.
    final line = Paint()
      ..color = BridgeColors.steel
      ..strokeWidth = 4 * s
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.miter;
    for (final seg in route.segments) {
      if (seg.length < 2) continue;
      final p0 = view.at(seg[0].x, seg[0].y);
      final path = Path()..moveTo(p0.dx, p0.dy);
      for (final p in seg.skip(1)) {
        final q = view.at(p.x, p.y);
        path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(path, line);
    }

    // Square markers, weakest on top.
    final dots = [...route.dots]
      ..sort((a, b) => b.marginDb.compareTo(a.marginDb));
    final edge = Paint()
      ..color = BridgeColors.bg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * s;
    for (final d in dots) {
      final r = Rect.fromCircle(center: view.at(d.x, d.y), radius: dot);
      canvas.drawRect(
          r, Paint()..color = SignalColorMapper.fromMargin(d.marginDb));
      canvas.drawRect(r, edge);
    }

    for (final (at, label) in ringLabels) {
      _text(canvas, label, at,
          bridgeSans(bridgeSmall(17, s), color: BridgeColors.teal, bold: true),
          center: true, vCenter: true, backing: BridgeColors.panel);
    }

    // Scale bar, bracket-ended, on a dark backing.
    final box = barBox;
    if (box != null) {
      canvas.drawRect(
          box, Paint()..color = BridgeColors.panel.withValues(alpha: 0.9));
      final bar = Paint()
        ..color = BridgeColors.white
        ..strokeWidth = 2.5 * s;
      final x0 = box.center.dx - barW / 2, x1 = box.center.dx + barW / 2;
      final y = box.bottom - 10 * s;
      canvas.drawLine(Offset(x0, y), Offset(x1, y), bar);
      canvas.drawLine(Offset(x0, y - 9 * s), Offset(x0, y + 2), bar);
      canvas.drawLine(Offset(x1, y - 9 * s), Offset(x1, y + 2), bar);
      lp.paint(canvas, Offset(box.center.dx - lp.width / 2, box.top + 6 * s));
    }

    // Frame brackets.
    bridgeBrackets(
        canvas,
        rect.deflate(6 * s),
        26 * s,
        Paint()
          ..color = accent
          ..strokeWidth = 3 * s
          ..style = PaintingStyle.stroke);

    canvas.restore();
  }

  static void _dashedCircle(Canvas canvas, Offset c, double r, Paint p) {
    final n = math.max(12, (2 * math.pi * r / 16).round());
    for (var i = 0; i < n; i += 2) {
      final a0 = 2 * math.pi * i / n, a1 = 2 * math.pi * (i + 1) / n;
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r), a0, a1 - a0, false, p);
    }
  }

  @override
  bool shouldRepaint(_ScannerPainter old) =>
      old.route != route ||
      old.frame != frame ||
      old.miles != miles ||
      old.dot != dot ||
      old.s != s ||
      old.scaleBar != scaleBar ||
      old.accent != accent;
}

TextPainter _layoutText(String text, TextStyle style) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

void _text(Canvas canvas, String text, Offset at, TextStyle style,
    {bool center = false,
    bool right = false,
    bool vCenter = false,
    Color? backing}) {
  final tp = _layoutText(text, style);
  final dx = center
      ? at.dx - tp.width / 2
      : right
          ? at.dx - tp.width
          : at.dx;
  final dy = vCenter ? at.dy - tp.height / 2 : at.dy;
  if (backing != null) {
    canvas.drawRect(Rect.fromLTWH(dx - 4, dy - 2, tp.width + 8, tp.height + 4),
        Paint()..color = backing);
  }
  tp.paint(canvas, Offset(dx, dy));
}
