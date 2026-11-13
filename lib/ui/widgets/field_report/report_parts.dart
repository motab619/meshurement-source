// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../../../services/field_report/field_report_data.dart';
import '../../../services/field_report/private_route.dart';
import '../../../utils/app_info.dart';
import '../../../utils/signal_color_mapper.dart';
import 'report_basemap.dart';
import 'report_painters.dart';
import 'report_style.dart';

/// Building blocks shared by the single-session and comparison cards.

/// Lays [child] out at the full width it is given and shrinks it to fit
/// the height when it is too tall (long titles, a wide fallback font), so a
/// card never overflows.
class ScaleDownBox extends StatelessWidget {
  const ScaleDownBox(
      {super.key, required this.child, this.alignment = Alignment.topCenter});

  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: SizedBox(width: box.maxWidth, child: child),
      ),
    );
  }
}

/// The card's background and outer padding.
class ReportFrame extends StatelessWidget {
  const ReportFrame(
      {super.key,
      required this.size,
      required this.padding,
      required this.child});

  final Size size;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ReportStyle.bgTop, ReportStyle.bgBottom],
          ),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A rounded panel; [glow] marks the highlighted one (brag tile, winner).
class ReportPanel extends StatelessWidget {
  const ReportPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.glow = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: ReportStyle.panel,
        borderRadius: BorderRadius.circular(ReportStyle.radius),
        border: Border.all(
            color: glow ? ReportStyle.cyan : ReportStyle.border,
            width: glow ? 3 : 2),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: ReportStyle.cyan.withValues(alpha: 0.35),
                  blurRadius: 30,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

/// The card's heading.
const reportHeading = 'LoRa Field Report';

/// "/ LoRa Field Report" with a kicker line, and the title block on the right.
class ReportHeader extends StatelessWidget {
  const ReportHeader({
    super.key,
    required this.kicker,
    required this.title,
    required this.subtitle,
    this.scale = 1,
  });

  final String kicker, title, subtitle;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Transform(
          transform: Matrix4.skewX(-0.32),
          child: Container(
              width: 22 * s, height: 86 * s, color: ReportStyle.orange),
        ),
        SizedBox(width: 28 * s),
        // The heading shrinks before the title block loses its room.
        Flexible(
          flex: 3,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(reportHeading,
                    style: ReportStyle.sans(62 * s, bold: true, italic: true)
                        .copyWith(height: 1.0)),
                SizedBox(height: 10 * s),
                Text(kicker,
                    style: ReportStyle.mono(20 * s,
                        color: ReportStyle.soft, spacing: 7 * s)),
              ],
            ),
          ),
        ),
        SizedBox(width: 24 * s),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: ReportStyle.sans(26 * s, bold: true)),
              if (subtitle.isNotEmpty) ...[
                SizedBox(height: 6 * s),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: ReportStyle.sans(23 * s, color: ReportStyle.soft)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A thin rule and the website, small, on every card (no logo).
class ReportFooter extends StatelessWidget {
  const ReportFooter({super.key, this.scale = 1});
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 2, color: ReportStyle.border),
        SizedBox(height: 14 * s),
        Text(AppInfo.website,
            textAlign: TextAlign.right,
            style: ReportStyle.sans(20 * s, color: ReportStyle.soft)),
      ],
    );
  }
}

/// The big number: farthest point the base was heard, or the route length
/// when there is no distance from the base to show.
class BragTile extends StatelessWidget {
  const BragTile(
      {super.key, required this.data, required this.miles, this.scale = 1});

  final FieldReportData data;
  final bool miles;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
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
    return ReportPanel(
      glow: true,
      padding: EdgeInsets.fromLTRB(28 * s, 18 * s, 28 * s, 20 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: ReportStyle.figure(92 * s,
                        color: ReportStyle.cyan, bold: true)
                    .copyWith(shadows: [
                  Shadow(
                      color: ReportStyle.cyan.withValues(alpha: 0.6),
                      blurRadius: 24),
                ])),
          ),
          SizedBox(height: 6 * s),
          Text(caption,
              maxLines: 2,
              style: ReportStyle.sans(26 * s, color: ReportStyle.soft)),
        ],
      ),
    );
  }
}

/// Signal margin buckets.
class MarginsPanel extends StatelessWidget {
  const MarginsPanel(
      {super.key, required this.data, this.scale = 1, this.compact = false});

  final FieldReportData data;
  final double scale;

  /// Drop the subtitle (wide format).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final preset = data.presetName.isEmpty ? 'range setting' : data.presetName;
    return ReportPanel(
      padding: EdgeInsets.fromLTRB(24 * s, 20 * s, 24 * s, 16 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Signal margin', style: ReportStyle.sans(28 * s, bold: true)),
          if (!compact) ...[
            SizedBox(height: 4 * s),
            Text('How far above the $preset limit',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ReportStyle.sans(18 * s, color: ReportStyle.soft)),
          ],
          SizedBox(height: 10 * s),
          Container(height: 1.5, color: ReportStyle.border),
          for (final b in data.buckets)
            Padding(
              padding: EdgeInsets.only(top: 10 * s),
              child: Row(
                children: [
                  Container(
                    width: 18 * s,
                    height: 18 * s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          SignalColorMapper.fromMargin(b.band.colourMarginDb),
                    ),
                  ),
                  SizedBox(width: 14 * s),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(b.band.label,
                          maxLines: 1, style: ReportStyle.sans(23 * s)),
                    ),
                  ),
                  SizedBox(width: 10 * s),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(b.band.range,
                          style: ReportStyle.sans(19 * s,
                              color: ReportStyle.soft)),
                    ),
                  ),
                  SizedBox(
                    width: 80 * s,
                    child: Text('${b.pct}%',
                        textAlign: TextAlign.right,
                        style: ReportStyle.mono(25 * s, bold: true)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Route length, time, readings, median margin, base heard.
class StatRow extends StatelessWidget {
  const StatRow(
      {super.key, required this.data, required this.miles, this.scale = 1});

  final FieldReportData data;
  final bool miles;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final pct = data.baseHeardPct;
    final stats = <(String, String)>[
      (reportDistance(data.routeM, miles), 'ROUTE'),
      (reportDuration(data.duration), 'TIME'),
      ('${data.samples.length}', 'READINGS'),
      (
        data.medianMarginDb == null ? '-' : reportDb(data.medianMarginDb!),
        'MEDIAN MARGIN'
      ),
      (pct == null ? '-' : '$pct%', 'BASE HEARD'),
    ];
    return ReportPanel(
      padding: EdgeInsets.symmetric(vertical: 16 * s, horizontal: 8 * s),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0)
              Container(width: 1.5, height: 60 * s, color: ReportStyle.border),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(stats[i].$1,
                        style: ReportStyle.figure(38 * s, bold: true)),
                  ),
                  SizedBox(height: 8 * s),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(stats[i].$2,
                        style: ReportStyle.mono(15 * s,
                            color: ReportStyle.soft, spacing: 3.5 * s)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Margin over the session" chart.
class MarginChartPanel extends StatelessWidget {
  const MarginChartPanel({super.key, required this.data, this.scale = 1});

  final FieldReportData data;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return ReportPanel(
      padding: EdgeInsets.fromLTRB(26 * s, 18 * s, 20 * s, 12 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Margin over the session',
              style: ReportStyle.sans(26 * s, bold: true)),
          SizedBox(height: 4 * s),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: MarginChartPainter(data.marginOverTime),
            ),
          ),
        ],
      ),
    );
  }
}

/// Base, mobile and range setting tiles.
class SetupRow extends StatelessWidget {
  const SetupRow({super.key, required this.data, this.scale = 1});

  final FieldReportData data;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final setup = data.setup;
    String or(String v) => v.isEmpty ? 'not recorded' : v;
    final range = <(String, String)>[
      ('Preset', data.presetName.isEmpty ? 'Mixed' : data.presetName),
      ('Limit', '${data.snrFloorDb.toStringAsFixed(1)} dB SNR'),
      if (setup.txPowerDbm != null) ('Power', '${setup.txPowerDbm} dBm'),
      if (setup.frequencyMhz != null)
        ('Freq', '${setup.frequencyMhz!.toStringAsFixed(3)} MHz'),
    ];
    Widget tile(String title, List<(String, String)> rows) => Expanded(
          child: ReportPanel(
            padding: EdgeInsets.fromLTRB(22 * s, 18 * s, 22 * s, 16 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: ReportStyle.mono(19 * s,
                        color: ReportStyle.orange, bold: true, spacing: 5 * s)),
                for (final (k, v) in rows)
                  Padding(
                    padding: EdgeInsets.only(top: 8 * s),
                    child: Row(
                      children: [
                        Text(k,
                            style: ReportStyle.sans(20 * s,
                                color: ReportStyle.soft)),
                        SizedBox(width: 10 * s),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(v,
                                style: ReportStyle.sans(20 * s, bold: true)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile('BASE', [
            ('Hardware', or(setup.baseRadio)),
            ('Antenna', or(setup.baseAntenna)),
          ]),
          SizedBox(width: 22 * s),
          tile('MOBILE', [
            ('Hardware', or(setup.mobileRadio)),
            ('Antenna', or(setup.mobileAntenna)),
          ]),
          SizedBox(width: 22 * s),
          tile('RANGE SETTING', range),
        ],
      ),
    );
  }
}

/// The route box: grid, track, dots, base area and scale bar. Notes go
/// under it ([RouteCaption]), never over the drawing.
class RouteBox extends StatelessWidget {
  const RouteBox({
    super.key,
    required this.route,
    required this.frame,
    required this.miles,
    this.dotRadius = 11,
    this.scaleBar = true,
    this.scale = 1,
    this.basemap,
  });

  final PrivateRoute route;
  final RouteFrame frame;
  final bool miles;
  final double dotRadius;
  final bool scaleBar;
  final double scale;

  /// Map tiles under the route; null draws the plain grid.
  final ReportBasemap? basemap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ReportStyle.panel,
        borderRadius: BorderRadius.circular(ReportStyle.radius),
        border: Border.all(color: ReportStyle.border, width: 2),
      ),
      child: Stack(
        children: [
          if (basemap != null)
            Positioned.fill(
              child: ReportBasemapLayer(
                  basemap: basemap!, frame: frame, scale: scale),
            ),
          Positioned.fill(
            child: CustomPaint(
              painter: RoutePainter(
                route: route,
                frame: frame,
                miles: miles,
                dotRadius: dotRadius,
                scaleBar: scaleBar,
                grid: basemap == null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [map] with the card's note line ([reportNoteText]) as a caption under
/// it, so the note never covers the BASE label or the route (walkthrough
/// 2026-11-08). Without a note it is just [map].
class RouteCaption extends StatelessWidget {
  const RouteCaption(
      {super.key, required this.map, required this.note, this.scale = 1});

  final Widget map;
  final String? note;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    if (note == null) return map;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: map),
        SizedBox(height: 10 * scale),
        Text(note,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: ReportStyle.sans(18 * scale, color: ReportStyle.soft)),
      ],
    );
  }
}

/// The card's note line for [notes], or null.
String? reportNoteText(List<ReportNote> notes, bool miles) {
  final parts = <String>[];
  for (final n in notes) {
    switch (n) {
      case WrongMapNote():
        parts.add("This route is far from its map's base location, so "
            'distances from the base are left out.');
      case NoBaseNote():
        parts.add('No base location on this map, so distances from the base '
            'are left out.');
      case SingleFarReadingNote(:final distanceM):
        parts.add('One reading at ${reportDistance(distanceM, miles)} had no '
            'second reading near it, so it is not the headline.');
    }
  }
  return parts.isEmpty ? null : parts.join(' ');
}

/// One comparison side's radio settings and hardware, as label/value
/// lines. A value that differs between the sides is orange, so the card
/// shows what was actually changed; a line nobody recorded is left out.
class SideSetupList extends StatelessWidget {
  const SideSetupList(
      {super.key, required this.all, required this.index, this.scale = 1});

  /// Every side's report, in card order.
  final List<FieldReportData> all;
  final int index;
  final double scale;

  static String _join(String a, String b) =>
      [a, b].where((v) => v.trim().isNotEmpty).join(' · ');

  /// (label, value per side); empty values mean not recorded.
  static List<(String, List<String>)> rowsFor(List<FieldReportData> all) {
    final rows = <(String, List<String>)>[
      ('Range', [for (final d in all) d.presetName]),
      (
        'Power',
        [
          for (final d in all)
            d.setup.txPowerDbm == null ? '' : '${d.setup.txPowerDbm} dBm'
        ]
      ),
      (
        'Freq',
        [
          for (final d in all)
            d.setup.frequencyMhz == null
                ? ''
                : '${d.setup.frequencyMhz!.toStringAsFixed(3)} MHz'
        ]
      ),
      (
        'Mobile',
        [for (final d in all) _join(d.setup.mobileRadio, d.setup.mobileAntenna)]
      ),
      (
        'Base',
        [for (final d in all) _join(d.setup.baseRadio, d.setup.baseAntenna)]
      ),
    ];
    return [
      for (final r in rows)
        if (r.$2.any((v) => v.isNotEmpty)) r,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final rows = rowsFor(all);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 1, color: ReportStyle.border),
        SizedBox(height: 6 * s),
        for (final (label, values) in rows)
          Padding(
            padding: EdgeInsets.only(top: 4 * s),
            child: Row(
              children: [
                SizedBox(
                  width: 80 * s,
                  child: Text(label,
                      style: ReportStyle.sans(19 * s, color: ReportStyle.soft)),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(values[index].isEmpty ? '-' : values[index],
                        style: ReportStyle.sans(19 * s,
                            bold: true,
                            color: values.toSet().length > 1
                                ? ReportStyle.orange
                                : ReportStyle.text)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
