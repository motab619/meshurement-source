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
import '../../../theme/app_theme.dart';
import '../report_painters.dart';
import '../report_parts.dart';
import '../report_style.dart';
import '../report_theme.dart';

/// The Mission Field Report theme (docs/design/field-report/themes.md): a
/// page from a generic early-space-age engineering report. Cream paper,
/// near-black ink, one muted red spot colour, typewriter data, dotted
/// leaders, ruled figures. Signal margin is told apart by plot symbol
/// (filled circle, filled square, hollow circle, cross) and a restrained
/// print-ink version of the green to red ramp.
class MissionReportCard extends StatelessWidget {
  const MissionReportCard({super.key, required this.report});

  final ThemedReport report;

  @override
  Widget build(BuildContext context) {
    final size = report.format.size;
    return SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: missionPaper,
        child: switch (report.format) {
          ReportFormat.feed => _feed(),
          ReportFormat.story => _story(),
          ReportFormat.wide => _wide(),
        },
      ),
    );
  }

  FieldReportData get _d => report.data;

  Widget _header(double s, {int titleLines = 1, bool compact = false}) =>
      MissionHeader(
        kicker: 'SIGNAL COVERAGE SURVEY',
        date: _d.startedAt,
        title: report.title,
        subtitle: report.subtitle,
        scale: s,
        titleLines: titleLines,
        compact: compact,
      );

  Widget _fig1(double s, {bool caption = true}) => _Figure1(
        report: report,
        scale: s,
        caption: caption,
      );

  Widget _feed() {
    const s = 1.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 48, 56, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(s),
          const SizedBox(height: 22),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 11,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _fig1(s)),
                      const SizedBox(height: 22),
                      SizedBox(
                          height: 262, child: _Figure2(data: _d, scale: s)),
                    ],
                  ),
                ),
                const SizedBox(width: 34),
                Expanded(
                  flex: 8,
                  // Summary level with FIG. 1, TABLE 2 level with FIG. 2.
                  child: MissionSpread(children: [
                    _Summary(report: report, scale: s),
                    _MarginTable(data: _d, scale: s),
                    _DataTable(data: _d, miles: report.miles, scale: s),
                  ]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _EquipmentTable(data: _d, scale: s, columns: 2),
          const SizedBox(height: 16),
          const MissionFooter(scale: s),
        ],
      ),
    );
  }

  Widget _story() {
    const s = 1.12;
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 70, 64, 52),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(s, titleLines: 2),
          const SizedBox(height: 30),
          _Summary(report: report, scale: s, wideValue: true),
          const SizedBox(height: 32),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 11, child: _fig1(s)),
                const SizedBox(width: 36),
                Expanded(
                  flex: 7,
                  child: MissionSpread(children: [
                    _MarginTable(data: _d, scale: s, preset: false),
                    _DataTable(data: _d, miles: report.miles, scale: s),
                  ]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(height: 360, child: _Figure2(data: _d, scale: s)),
          const SizedBox(height: 30),
          _EquipmentTable(data: _d, scale: s, columns: 2),
          const SizedBox(height: 24),
          const MissionFooter(scale: s),
        ],
      ),
    );
  }

  Widget _wide() {
    const s = 0.78;
    // The right column reads at a larger size than the header.
    const r = 0.9;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 30, 40, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(s, compact: true),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 470, child: _fig1(s)),
                const SizedBox(width: 30),
                Expanded(
                  child: ScaleDownBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Summary(report: report, scale: r, wideValue: true),
                        const SizedBox(height: 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: _MarginTable(
                                    data: _d, scale: r, compact: true)),
                            const SizedBox(width: 26),
                            Expanded(
                                child: _DataTable(
                                    data: _d,
                                    miles: report.miles,
                                    scale: r,
                                    compact: true)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const MissionFooter(scale: s),
        ],
      ),
    );
  }
}

/// [children] spread over the available height, first at the top and last
/// at the bottom; scaled down as a whole if they don't fit.
class MissionSpread extends StatelessWidget {
  const MissionSpread({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minWidth: box.maxWidth,
                maxWidth: box.maxWidth,
                minHeight: box.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: children,
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Palette and type.

class MissionInk {
  MissionInk._();

  static const paper = Color(0xFFF1E9D6);
  static const paperLight = Color(0xFFF7F1E2);
  static const paperEdge = Color(0xFFE4D8BD);
  static const ink = Color(0xFF1D1B18);
  static const soft = Color(0xFF59534A);
  static const faint = Color(0xFF9A907C);
  static const red = Color(0xFFAE3B2F);

  // Print-ink signal ramp: same thresholds as SignalColorMapper.fromMargin
  // (0 dB red, 10 dB yellow, 20+ dB green), muted like a two-pass offset
  // print.
  static const sigGreen = Color(0xFF3D7650);
  static const sigYellow = Color(0xFFC79A2C);
  static const sigRed = Color(0xFFA9372B);

  static Color signal(double marginDb) {
    final t = (marginDb / 20).clamp(0.0, 1.0);
    return t > 0.5
        ? Color.lerp(sigYellow, sigGreen, (t - 0.5) * 2)!
        : Color.lerp(sigRed, sigYellow, t * 2)!;
  }
}

/// The page: cream paper, lighter where the light falls.
const missionPaper = BoxDecoration(
  color: MissionInk.paper,
  gradient: RadialGradient(
    center: Alignment(-0.2, -0.3),
    radius: 1.25,
    colors: [MissionInk.paperLight, MissionInk.paper, MissionInk.paperEdge],
    stops: [0, 0.65, 1],
  ),
);

/// The typewriter face (Courier Prime) for Mission's typed text.
const missionTypewriter = 'CourierPrime';

TextStyle missionMono(double size,
        {Color color = MissionInk.ink,
        bool bold = false,
        double spacing = 0}) =>
    TextStyle(
      fontFamily: missionTypewriter,
      fontSize: size,
      color: color,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      letterSpacing: spacing,
      height: 1.2,
      decoration: TextDecoration.none,
    );

TextStyle missionSans(double size,
        {Color color = MissionInk.ink,
        bool bold = false,
        bool italic = false,
        double spacing = 0}) =>
    TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: size,
      color: color,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: spacing,
      height: 1.2,
      decoration: TextDecoration.none,
    );

/// [text] in [style] (typed). Courier Prime centres the full stop in its
/// cell, so "5.8" needs no help (B612Mono, used before, left "5. 8").
TextSpan missionMonoSpan(String text, TextStyle style) =>
    TextSpan(text: text, style: style);

/// Short dB range for the margin table ("20+", "10–20", "<0").
String _range(MarginBand b) => switch (b) {
      MarginBand.strong => '20+',
      MarginBand.good => '10\u201320',
      MarginBand.weak => '0\u201310',
      MarginBand.below => '<0',
    };

String _upperDistance(double m, bool miles) =>
    reportDistance(m, miles).toUpperCase();

// ---------------------------------------------------------------------------
// Header, rules, footer.

/// Heavy red rule over a thin black one.
class MissionDoubleRule extends StatelessWidget {
  const MissionDoubleRule({super.key, required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 7 * scale, color: MissionInk.red),
          SizedBox(height: 4 * scale),
          Container(height: 2, color: MissionInk.ink),
        ],
      );
}

/// Page head: a kicker and the date, the double rule, the heading and the
/// subject line.
class MissionHeader extends StatelessWidget {
  const MissionHeader({
    super.key,
    required this.kicker,
    required this.date,
    required this.title,
    required this.scale,
    this.subtitle = '',
    this.titleLines = 1,
    this.compact = false,
  });

  /// "SIGNAL COVERAGE SURVEY", "COMPARATIVE TEST · 4 CONFIGURATIONS".
  final String kicker;
  final DateTime date;
  final String title, subtitle;
  final double scale;
  final int titleLines;

  /// One line for heading and subject (wide format).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final dateText =
        DateFormat('d MMM y', 'en_US').format(date.toLocal()).toUpperCase();
    final topStyle = missionMono(20 * s, bold: true, spacing: 2 * s);
    final topLine = Row(
      children: [
        Expanded(
          child: Text.rich(missionMonoSpan(kicker, topStyle),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        SizedBox(width: 20 * s),
        Text(dateText, style: topStyle),
      ],
    );
    final heading = Text(reportHeading.toUpperCase(),
        maxLines: 1,
        style:
            missionSans(compact ? 46 * s : 54 * s, bold: true, spacing: 5 * s)
                .copyWith(height: 1.05));
    final label = missionMono(20 * s, color: MissionInk.red, bold: true);
    final subject = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('SUBJECT:', style: label),
        SizedBox(width: 14 * s),
        Expanded(
          child: Text.rich(
              missionMonoSpan(title, missionMono(23 * s, bold: true)),
              maxLines: titleLines,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    final sub = subtitle.isEmpty
        ? null
        : Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Same indent as the subject.
              Opacity(opacity: 0, child: Text('SUBJECT:', style: label)),
              SizedBox(width: 14 * s),
              Expanded(
                child: Text.rich(
                    missionMonoSpan(
                        subtitle, missionMono(20 * s, color: MissionInk.soft)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        topLine,
        SizedBox(height: 8 * s),
        MissionDoubleRule(scale: s),
        SizedBox(height: 16 * s),
        if (compact)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FittedBox(fit: BoxFit.scaleDown, child: heading),
              SizedBox(width: 30 * s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [subject, if (sub != null) sub],
                ),
              ),
            ],
          )
        else ...[
          FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: heading),
          SizedBox(height: 12 * s),
          subject,
          if (sub != null) ...[SizedBox(height: 4 * s), sub],
        ],
      ],
    );
  }
}

/// A rule, then the website at the right (in B612: the mono full stop
/// leaves a gap).
class MissionFooter extends StatelessWidget {
  const MissionFooter({super.key, required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 2, color: MissionInk.ink),
        SizedBox(height: 8 * s),
        Align(
          alignment: Alignment.centerRight,
          child: Text(AppInfo.website,
              style: missionSans(18 * s,
                  color: MissionInk.soft, spacing: 0.5 * s)),
        ),
      ],
    );
  }
}

/// "TABLE 1 — SIGNAL MARGIN" over a thin rule.
class MissionSectionLabel extends StatelessWidget {
  const MissionSectionLabel(this.number, this.title,
      {super.key, required this.scale});
  final String number, title;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: number,
                style: missionMono(17 * s, color: MissionInk.red, bold: true)),
            missionMonoSpan(
                ' — $title', missionMono(17 * s, bold: true, spacing: 1 * s)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 6 * s),
        Container(height: 1.5, color: MissionInk.ink),
      ],
    );
  }
}

/// LABEL ........ VALUE, the dots typed out like a typewriter's.
class MissionLeader extends StatelessWidget {
  const MissionLeader({
    super.key,
    required this.label,
    required this.value,
    required this.scale,
    this.lead,
  });

  final String label, value;
  final double scale;

  /// A symbol before the label (the legend rows), [leadSize] wide.
  final Widget? lead;
  static const leadSize = 20.0;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final style = missionMono(19 * s);
    final valueStyle = missionSans(20 * s, bold: true);
    return LayoutBuilder(builder: (context, box) {
      // The value keeps its width (up to 60%), the label gets the rest
      // less a few leader dots; either ellipsizes past that.
      final tp = TextPainter(
        text: TextSpan(text: value, style: valueStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final valueW = math.min(tp.width + 1, box.maxWidth * 0.6);
      tp.dispose();
      final leadW = lead == null ? 0.0 : (leadSize + 10) * s;
      final labelW =
          math.max(0.0, box.maxWidth - valueW - leadW - 12 * s - 24 * s);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (lead != null) ...[lead!, SizedBox(width: 10 * s)],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: labelW),
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
          SizedBox(width: 6 * s),
          Expanded(
            child: Text('.' * 120,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: missionMono(19 * s, color: MissionInk.faint)),
          ),
          SizedBox(width: 6 * s),
          SizedBox(
            width: valueW,
            child: Text(value,
                maxLines: 1,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: valueStyle),
          ),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Summary and tables.

class _Summary extends StatelessWidget {
  const _Summary(
      {required this.report, required this.scale, this.wideValue = false});

  final ThemedReport report;
  final double scale;

  /// Value and caption side by side (story, wide).
  final bool wideValue;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final data = report.data;
    final far = data.farthestM;
    // Same fallback as BragTile.
    final value = far != null
        ? _upperDistance(far, report.miles)
        : data.routeM >= 50
            ? _upperDistance(data.routeM, report.miles)
            : '${data.samples.length}';
    final caption = far != null
        ? 'Farthest point at which the base node was heard.'
        : data.routeM >= 50
            ? 'Route length.'
            : data.samples.length == 1
                ? 'Reading.'
                : 'Readings.';
    final valueText = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(value,
          style: missionSans(84 * s, bold: true, spacing: -1 * s)
              .copyWith(height: 1.0)),
    );
    final captionText = Text(caption,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: missionSans(25 * s, italic: true, color: MissionInk.ink));
    final note = report.note;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: MissionInk.ink, width: 2.5),
      ),
      padding: EdgeInsets.all(5 * s),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: MissionInk.ink, width: 1),
        ),
        padding: EdgeInsets.fromLTRB(22 * s, 14 * s, 22 * s, 18 * s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(width: 14 * s, height: 14 * s, color: MissionInk.red),
                SizedBox(width: 10 * s),
                Text('SUMMARY',
                    style: missionMono(18 * s,
                        color: MissionInk.red, bold: true, spacing: 4 * s)),
              ],
            ),
            SizedBox(height: 10 * s),
            if (wideValue)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(flex: 5, child: valueText),
                  SizedBox(width: 24 * s),
                  Expanded(flex: 6, child: captionText),
                ],
              )
            else ...[
              valueText,
              SizedBox(height: 6 * s),
              captionText,
            ],
            if (note != null) ...[
              SizedBox(height: 12 * s),
              Container(height: 1, color: MissionInk.faint),
              SizedBox(height: 10 * s),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: 'NOTE: ',
                      style: missionMono(17 * s,
                          color: MissionInk.red, bold: true)),
                  TextSpan(
                      text: note,
                      style: missionSans(17 * s, color: MissionInk.soft)),
                ]),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MarginTable extends StatelessWidget {
  const _MarginTable(
      {required this.data,
      required this.scale,
      this.compact = false,
      this.preset = true});

  final FieldReportData data;
  final double scale;

  /// Drop the dB ranges (wide format).
  final bool compact;

  /// Name the range setting in the note (off where it would wrap).
  final bool preset;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final name = data.presetName.isEmpty || compact || !preset
        ? ''
        : '${data.presetName} ';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MissionSectionLabel('TABLE 1', 'SIGNAL MARGIN', scale: s),
        SizedBox(height: 6 * s),
        Text(
            'dB above the ${name}limit '
            '(${data.snrFloorDb.toStringAsFixed(1)} dB SNR)',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: missionSans(16 * s, italic: true, color: MissionInk.soft)),
        for (final b in data.buckets)
          Padding(
            padding: EdgeInsets.only(top: 9 * s),
            child: MissionLeader(
              scale: s,
              lead: SizedBox(
                width: 20 * s,
                height: 20 * s,
                child: CustomPaint(
                    painter:
                        MissionSymbolPainter(b.band.colourMarginDb, 8.5 * s)),
              ),
              label: compact
                  ? b.band.label.toUpperCase()
                  : '${b.band.label.toUpperCase()} ${_range(b.band)}',
              value: '${b.pct}%',
            ),
          ),
      ],
    );
  }
}

class _DataTable extends StatelessWidget {
  const _DataTable(
      {required this.data,
      required this.miles,
      required this.scale,
      this.compact = false});

  final FieldReportData data;
  final bool miles;
  final double scale;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final pct = data.baseHeardPct;
    final rows = <(String, String)>[
      (compact ? 'ROUTE' : 'ROUTE LENGTH', _upperDistance(data.routeM, miles)),
      (
        compact ? 'TIME' : 'ELAPSED TIME',
        reportDuration(data.duration).toUpperCase()
      ),
      ('READINGS', '${data.samples.length}'),
      (
        compact ? 'MEDIAN' : 'MEDIAN MARGIN',
        data.medianMarginDb == null ? '—' : reportDb(data.medianMarginDb!)
      ),
      (compact ? 'BASE HEARD' : 'BASE NODE HEARD', pct == null ? '—' : '$pct%'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MissionSectionLabel('TABLE 2', 'SESSION DATA', scale: s),
        for (final (k, v) in rows)
          Padding(
            padding: EdgeInsets.only(top: 10 * s),
            child: MissionLeader(label: k, value: v, scale: s),
          ),
      ],
    );
  }
}

class _EquipmentTable extends StatelessWidget {
  const _EquipmentTable(
      {required this.data, required this.scale, this.columns = 1});

  final FieldReportData data;
  final double scale;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final setup = data.setup;
    String or(String v) => v.trim().isEmpty ? 'not recorded' : v;
    final hardware = <(String, String)>[
      ('BASE NODE RADIO', or(setup.baseRadio)),
      ('BASE ANTENNA', or(setup.baseAntenna)),
      ('MOBILE RADIO', or(setup.mobileRadio)),
      ('MOBILE ANTENNA', or(setup.mobileAntenna)),
    ];
    final radio = <(String, String)>[
      ('RANGE SETTING', data.presetName.isEmpty ? 'Mixed' : data.presetName),
      ('DECODE LIMIT', '${data.snrFloorDb.toStringAsFixed(1)} dB SNR'),
      if (setup.txPowerDbm != null) ('TX POWER', '${setup.txPowerDbm} dBm'),
      if (setup.frequencyMhz != null)
        ('FREQUENCY', '${setup.frequencyMhz!.toStringAsFixed(3)} MHz'),
    ];
    Widget list(List<(String, String)> rows) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (k, v) in rows)
              Padding(
                padding: EdgeInsets.only(top: 8 * s),
                child: MissionLeader(label: k, value: v, scale: s),
              ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MissionSectionLabel('TABLE 3', 'EQUIPMENT', scale: s),
        if (columns == 2)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: list(hardware)),
              SizedBox(width: 40 * s),
              Expanded(child: list(radio)),
            ],
          )
        else
          list([...hardware, ...radio]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Figures.

/// Plot symbol for a margin: filled circle (Strong), filled square (Good),
/// hollow circle (Weak), cross (Below limit), inked on the print ramp.
void missionDrawSymbol(Canvas canvas, Offset p, double marginDb, double r) {
  final colour = MissionInk.signal(marginDb);
  final outline = Paint()
    ..color = MissionInk.ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.2, r * 0.16);
  switch (MarginBand.of(marginDb)) {
    case MarginBand.strong:
      canvas.drawCircle(p, r, Paint()..color = colour);
      canvas.drawCircle(p, r, outline);
    case MarginBand.good:
      final rect =
          Rect.fromCenter(center: p, width: r * 1.75, height: r * 1.75);
      canvas.drawRect(rect, Paint()..color = colour);
      canvas.drawRect(rect, outline);
    case MarginBand.weak:
      canvas.drawCircle(p, r * 0.92, Paint()..color = MissionInk.paper);
      canvas.drawCircle(
          p,
          r * 0.82,
          Paint()
            ..color = colour
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.38);
    case MarginBand.below:
      final k = r * 0.95;
      final halo = Paint()
        ..color = MissionInk.paper
        ..strokeWidth = r * 0.75
        ..strokeCap = StrokeCap.round;
      final stroke = Paint()
        ..color = colour
        ..strokeWidth = r * 0.42
        ..strokeCap = StrokeCap.square;
      for (final paint in [halo, stroke]) {
        canvas.drawLine(p + Offset(-k, -k), p + Offset(k, k), paint);
        canvas.drawLine(p + Offset(-k, k), p + Offset(k, -k), paint);
      }
  }
}

class MissionSymbolPainter extends CustomPainter {
  MissionSymbolPainter(this.marginDb, this.r);
  final double marginDb, r;

  @override
  void paint(Canvas canvas, Size size) =>
      missionDrawSymbol(canvas, size.center(Offset.zero), marginDb, r);

  @override
  bool shouldRepaint(MissionSymbolPainter old) =>
      old.marginDb != marginDb || old.r != r;
}

void missionText(Canvas canvas, String text, Offset at, TextStyle style,
    {double ax = 0, double ay = 0, Color? backing, double pad = 0}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final o = at - Offset(tp.width * ax, tp.height * ay);
  if (backing != null) {
    canvas.drawRect(
        Rect.fromLTWH(
            o.dx - pad, o.dy - pad * 0.5, tp.width + 2 * pad, tp.height + pad),
        Paint()..color = backing);
  }
  tp.paint(canvas, o);
}

/// FIG. 1: the route in a ruled box with tick marks, and its caption.
class _Figure1 extends StatelessWidget {
  const _Figure1(
      {required this.report, required this.scale, this.caption = true});

  final ThemedReport report;
  final double scale;
  final bool caption;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final route = report.route;
    final hide = route.hideRadiusM;
    final where = route.origin == ReportOrigin.base ? 'base' : 'start';
    final detail = [
      'Track rotated; no coordinates.',
      if (route.origin != ReportOrigin.none && hide > 0)
        'Readings within ${reportDistance(hide, report.miles)} '
            'of the $where withheld.',
    ].join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomPaint(
            painter: MissionRoutePlot(
              route: route,
              frame: RouteFrame.of([route]),
              miles: report.miles,
              scale: s,
            ),
          ),
        ),
        if (caption) ...[
          SizedBox(height: 10 * s),
          Text.rich(
            TextSpan(children: [
              missionMonoSpan('FIG. 1',
                  missionMono(17 * s, color: MissionInk.red, bold: true)),
              TextSpan(
                  text: ' — ROUTE AND SIGNAL MARGIN. ',
                  style: missionMono(17 * s, bold: true)),
              TextSpan(
                  text: detail,
                  style: missionSans(17 * s,
                      italic: true, color: MissionInk.soft)),
            ]),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// A route on graph paper in a ticked frame: track, plot symbols, the
/// withheld base area and (when [scaleBar]) a scale bar. Comparison
/// figures share one [frame].
class MissionRoutePlot extends CustomPainter {
  MissionRoutePlot({
    required this.route,
    required this.frame,
    required this.miles,
    required this.scale,
    this.scaleBar = true,
    this.dotRadius = 9.5,
  });

  final PrivateRoute route;
  final RouteFrame frame;
  final bool miles;
  final double scale;
  final bool scaleBar;

  /// Plot symbol radius before [scale].
  final double dotRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final s = scale;
    final rect = Offset.zero & size;

    // Graph-paper ruling, a heavier line every fifth.
    final cell = 24.0 * s;
    final fine = Paint()
      ..color = MissionInk.ink.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = MissionInk.ink.withValues(alpha: 0.15)
      ..strokeWidth = 1.2;
    final cx = size.width / 2, cy = size.height / 2;
    var i = 0;
    for (var x = cx; x < size.width; x += cell, i++) {
      for (final xx in {x, 2 * cx - x}) {
        canvas.drawLine(
            Offset(xx, 0), Offset(xx, size.height), i % 5 == 0 ? major : fine);
      }
    }
    i = 0;
    for (var y = cy; y < size.height; y += cell, i++) {
      for (final yy in {y, 2 * cy - y}) {
        canvas.drawLine(
            Offset(0, yy), Offset(size.width, yy), i % 5 == 0 ? major : fine);
      }
    }

    // Frame and inward tick marks.
    final frameInk = Paint()
      ..color = MissionInk.ink
      ..strokeWidth = 1.5;
    i = 0;
    for (var x = cx; x < size.width; x += cell, i++) {
      final len = (i % 5 == 0 ? 16 : 8) * s;
      for (final xx in {x, 2 * cx - x}) {
        canvas.drawLine(Offset(xx, 0), Offset(xx, len), frameInk);
        canvas.drawLine(
            Offset(xx, size.height), Offset(xx, size.height - len), frameInk);
      }
    }
    i = 0;
    for (var y = cy; y < size.height; y += cell, i++) {
      final len = (i % 5 == 0 ? 16 : 8) * s;
      for (final yy in {y, 2 * cy - y}) {
        canvas.drawLine(Offset(0, yy), Offset(len, yy), frameInk);
        canvas.drawLine(
            Offset(size.width, yy), Offset(size.width - len, yy), frameInk);
      }
    }

    canvas.save();
    canvas.clipRect(rect);
    // RouteView keeps a fixed 40 px margin; a small comparison figure
    // gets a narrower one (enough for a plot symbol), by fitting into a
    // larger box and shifting back.
    final pad = math.min(RouteView.pad,
        math.max((dotRadius + 10) * s, 0.08 * size.shortestSide));
    final shift = RouteView.pad - pad;
    final view =
        RouteView(frame, Size(size.width + 2 * shift, size.height + 2 * shift));
    Offset at(double x, double y) => view.at(x, y) - Offset(shift, shift);
    final mpp = view.scale;

    // Hidden base (or start) area: hatched, dashed red outline.
    final o = at(0, 0);
    var labelAt = o;
    // Radius of the drawn base area, for placing the label beside it; 0
    // when the label sits inside it.
    var labelRing = 0.0;
    String? label;
    if (route.origin != ReportOrigin.none) {
      label = route.origin == ReportOrigin.base ? 'BASE' : 'START';
      final r = route.hideRadiusM * mpp;
      if (r > 6) {
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCircle(center: o, radius: r)));
        canvas.drawCircle(o, r, Paint()..color = MissionInk.paper);
        final hatch = Paint()
          ..color = MissionInk.red.withValues(alpha: 0.35)
          ..strokeWidth = 1.6 * s;
        for (var d = -2 * r; d < 2 * r; d += 10 * s) {
          canvas.drawLine(Offset(o.dx + d - r, o.dy + r),
              Offset(o.dx + d + r, o.dy - r), hatch);
        }
        canvas.restore();
        _dashedCircle(
            canvas,
            o,
            r,
            Paint()
              ..color = MissionInk.red
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5 * s);
        labelRing = r > 50 * s ? 0 : r + 8 * s;
      } else {
        labelRing = 16 * s;
      }
      // Key marker: red cross-hair at the origin.
      final red = Paint()
        ..color = MissionInk.red
        ..strokeWidth = 2.5 * s
        ..style = PaintingStyle.stroke;
      if (r <= 50 * s) {
        canvas.drawCircle(o, 7 * s, red);
        canvas.drawLine(o - Offset(13 * s, 0), o + Offset(13 * s, 0), red);
        canvas.drawLine(o - Offset(0, 13 * s), o + Offset(0, 13 * s), red);
      }
    }

    // Track.
    final line = Paint()
      ..color = MissionInk.ink.withValues(alpha: 0.75)
      ..strokeWidth = 2.5 * s
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

    // Symbols, weakest on top.
    final dots = [...route.dots]
      ..sort((a, b) => b.marginDb.compareTo(a.marginDb));
    for (final d in dots) {
      missionDrawSymbol(canvas, at(d.x, d.y), d.marginDb, dotRadius * s);
    }

    if (label != null) {
      final style = missionMono(20 * s,
          color: MissionInk.red, bold: true, spacing: 2 * s);
      final tp = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final hw = tp.width / 2 + 10 * s, hh = tp.height / 2 + 6 * s;
      tp.dispose();
      if (labelRing > 0) {
        // Above the base area, else left, right or below: the first that
        // stays inside the frame and covers the fewest readings.
        final d = labelRing;
        final candidates = [
          o - Offset(0, d + hh),
          o - Offset(d + hw, 0),
          o + Offset(d + hw, 0),
          o + Offset(0, d + hh),
        ];
        final pts = [for (final p in route.dots) at(p.x, p.y)];
        var bestHits = 1 << 30;
        for (final c in candidates) {
          final fits = c.dx >= hw &&
              c.dx <= size.width - hw &&
              c.dy >= hh &&
              c.dy <= size.height - hh;
          if (!fits) continue;
          final box = Rect.fromCenter(center: c, width: 2 * hw, height: 2 * hh)
              .inflate(dotRadius * s);
          final hits = pts.where(box.contains).length;
          if (hits < bestHits) {
            bestHits = hits;
            labelAt = c;
          }
        }
        if (bestHits == 1 << 30) labelAt = candidates.first;
      }
      labelAt = Offset(
        labelAt.dx.clamp(hw, math.max(hw, size.width - hw)),
        labelAt.dy.clamp(hh, math.max(hh, size.height - hh)),
      );
      missionText(canvas, label, labelAt, style,
          ax: 0.5, ay: 0.5, backing: MissionInk.paper, pad: 6 * s);
    }

    if (scaleBar) {
      // Scale bar: four alternating cells, "0" and the length under it.
      // Wide enough for its label in a narrow comparison figure.
      final maxM =
          math.max(size.width * 0.3, math.min(size.width * 0.6, 130 * s)) / mpp;
      final (m, text) = niceScaleBar(maxM, miles: miles);
      final w = m * mpp;
      final h = 9 * s;
      // In whichever corner covers the fewest readings and track points.
      final pts = [
        for (final d in route.dots) at(d.x, d.y),
        for (final seg in route.segments)
          for (final p in seg) at(p.x, p.y),
      ];
      final m30 = 30 * s;
      final corners = [
        (size.width - m30, size.height - 48 * s), // bottom right
        (m30 + w, size.height - 48 * s), // bottom left
        (size.width - m30, 30 * s), // top right
        (m30 + w, 30 * s), // top left
      ];
      var best = corners.first;
      var bestHits = 1 << 30;
      for (final c in corners) {
        final box = Rect.fromLTRB(
            c.$1 - w - 14 * s, c.$2 - 14 * s, c.$1 + 14 * s, c.$2 + h + 36 * s);
        final hits = pts.where(box.contains).length;
        if (hits < bestHits) {
          best = c;
          bestHits = hits;
        }
      }
      final x1 = best.$1, x0 = x1 - w;
      final y = best.$2;
      final labelStyle = missionSans(17 * s, bold: true);
      for (var k = 0; k < 4; k++) {
        final cellRect = Rect.fromLTWH(x0 + k * w / 4, y, w / 4, h);
        canvas.drawRect(cellRect,
            Paint()..color = k.isEven ? MissionInk.ink : MissionInk.paper);
      }
      canvas.drawRect(
          Rect.fromLTWH(x0, y, w, h),
          Paint()
            ..color = MissionInk.ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      final lengthW = (TextPainter(
        text: TextSpan(text: text.toUpperCase(), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout())
          .width;
      // "0" only when it clears the length label.
      if (w > lengthW + 24 * s) {
        missionText(canvas, '0', Offset(x0, y + h + 5 * s), labelStyle,
            backing: MissionInk.paper, pad: 3 * s);
      }
      missionText(
          canvas, text.toUpperCase(), Offset(x1, y + h + 5 * s), labelStyle,
          ax: 1, backing: MissionInk.paper, pad: 3 * s);
    }
    canvas.restore();

    canvas.drawRect(
        rect.deflate(1.25),
        Paint()
          ..color = MissionInk.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
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
  bool shouldRepaint(MissionRoutePlot old) =>
      old.route != route ||
      old.frame != frame ||
      old.miles != miles ||
      old.scale != scale ||
      old.scaleBar != scaleBar ||
      old.dotRadius != dotRadius;
}

/// FIG. 2: median margin per time bin on ruled axes.
class _Figure2 extends StatelessWidget {
  const _Figure2({required this.data, required this.scale});

  final FieldReportData data;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final bins = data.marginOverTime.length;
    final binLen = bins == 0 ? Duration.zero : data.duration ~/ bins;
    final detail = binLen.inMinutes >= 1
        ? 'Median per interval of ${reportDuration(binLen)}; gaps had no readings.'
        : 'Median per interval; gaps had no readings.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child:
              CustomPaint(painter: _MarginPlot(data.marginOverTime, scale: s)),
        ),
        SizedBox(height: 8 * s),
        Text.rich(
          TextSpan(children: [
            missionMonoSpan('FIG. 2',
                missionMono(17 * s, color: MissionInk.red, bold: true)),
            TextSpan(
                text: ' — MARGIN OVER THE SESSION. ',
                style: missionMono(17 * s, bold: true)),
            TextSpan(
                text: detail,
                style:
                    missionSans(17 * s, italic: true, color: MissionInk.soft)),
          ]),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _MarginPlot extends CustomPainter {
  _MarginPlot(this.bins, {required this.scale});
  final List<double?> bins;
  final double scale;

  static const _top = 25.0, _bottom = -5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final s = scale;
    final left = 58 * s, right = 92 * s, top = 12 * s, bottom = 34 * s;
    final w = size.width - left - right;
    final h = size.height - top - bottom;
    double yOf(double m) =>
        top + (1 - (m.clamp(_bottom, _top) - _bottom) / (_top - _bottom)) * h;
    final ink = Paint()
      ..color = MissionInk.ink
      ..strokeWidth = 2;
    final small = missionMono(15 * s, color: MissionInk.soft);

    // Guides at Strong and Good, the limit in red.
    for (final (m, label) in [(20.0, 'STRONG'), (10.0, 'GOOD')]) {
      final y = yOf(m);
      final guide = Paint()
        ..color = MissionInk.ink.withValues(alpha: 0.35)
        ..strokeWidth = 1.2;
      for (var x = left; x < left + w; x += 8 * s) {
        canvas.drawLine(Offset(x, y), Offset(x + 2 * s, y), guide);
      }
      missionText(canvas, label, Offset(left + w + 10 * s, y), small, ay: 0.5);
    }
    final limitY = yOf(0);
    final redDash = Paint()
      ..color = MissionInk.red
      ..strokeWidth = 2 * s;
    for (var x = left; x < left + w; x += 14 * s) {
      canvas.drawLine(Offset(x, limitY), Offset(x + 8 * s, limitY), redDash);
    }
    missionText(canvas, 'LIMIT', Offset(left + w + 10 * s, limitY),
        missionMono(15 * s, color: MissionInk.red, bold: true),
        ay: 0.5);

    // Axes with ticks every 5 dB, labels every 10.
    canvas.drawLine(Offset(left, top), Offset(left, top + h), ink);
    canvas.drawLine(Offset(left, top + h), Offset(left + w, top + h), ink);
    for (var m = _bottom; m <= _top; m += 5) {
      final y = yOf(m);
      final major = m % 10 == 0;
      canvas.drawLine(
          Offset(left - (major ? 10 : 5) * s, y), Offset(left, y), ink);
      if (major) {
        missionText(canvas, m == 0 ? '0' : '+${m.round()}',
            Offset(left - 14 * s, y), small,
            ax: 1, ay: 0.5);
      }
    }
    missionText(canvas, 'dB', Offset(left - 14 * s, top - 2 * s), small,
        ax: 1, ay: 0.2);

    final n = bins.length;
    if (n == 0) return;
    double xOf(int i) =>
        n == 1 ? left + w / 2 : left + 16 * s + i * (w - 32 * s) / (n - 1);
    for (var i = 0; i < n; i++) {
      canvas.drawLine(
          Offset(xOf(i), top + h), Offset(xOf(i), top + h + 7 * s), ink);
    }
    missionText(canvas, 'START', Offset(xOf(0), top + h + 10 * s), small,
        ax: 0.5);
    missionText(canvas, 'END', Offset(xOf(n - 1), top + h + 10 * s), small,
        ax: 0.5);

    // Line, broken where a bin had no readings.
    final line = Paint()
      ..color = MissionInk.ink
      ..strokeWidth = 2.5 * s
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    Path? path;
    for (var i = 0; i < n; i++) {
      final v = bins[i];
      if (v == null) {
        if (path != null) canvas.drawPath(path, line);
        path = null;
        continue;
      }
      final p = Offset(xOf(i), yOf(v));
      if (path == null) {
        path = Path()..moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    if (path != null) canvas.drawPath(path, line);
    for (var i = 0; i < n; i++) {
      final v = bins[i];
      if (v != null) {
        missionDrawSymbol(canvas, Offset(xOf(i), yOf(v)), v, 9 * s);
      }
    }
  }

  @override
  bool shouldRepaint(_MarginPlot old) => old.bins != bins || old.scale != scale;
}
