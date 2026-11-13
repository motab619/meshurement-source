// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../../../services/field_report/comparison_report_data.dart';
import '../../../services/field_report/field_report_data.dart';
import '../../../services/field_report/private_route.dart';
import 'report_basemap.dart';
import 'report_painters.dart';
import 'report_parts.dart';
import 'report_style.dart';
import 'report_theme.dart';
import 'themes/basic_comparison_card.dart';
import 'themes/bridge_comparison_card.dart';
import 'themes/mission_comparison_card.dart';
import 'themes/pop_comparison_card.dart';

/// The comparison card: two to four setups side by side on one shared
/// grid, the winner highlighted with how far ahead it was, and the guided
/// test's verdict line.
class ComparisonReportCard extends StatelessWidget {
  const ComparisonReportCard({
    super.key,
    required this.data,
    required this.title,
    required this.format,
    required this.miles,
    this.hideRadiusM = defaultHideRadiusM,
    this.showPath = showPathByDefault,
    this.background = ReportBackground.plain,
    this.tiles,
    this.theme = ReportTheme.night,
  });

  /// The look; every theme but Night draws the plain routes (no map).
  final ReportTheme theme;

  final ComparisonReportData data;

  /// Plain grid, or a map under every side's route (needs [tiles]).
  final ReportBackground background;
  final ReportTileLoader? tiles;
  final String title;
  final ReportFormat format;
  final bool miles;
  final double hideRadiusM;

  /// Draw the track line; false shows the readings' points only.
  final bool showPath;

  /// "Whip antenna reached 0.6 mi farther, +4 dB median margin".
  String get winLine {
    final w = data.winner;
    if (w == null) {
      return 'No clear winner: the setups were within '
          '${reportDistance(farthestPairM, miles)} and 3 dB of each other.';
    }
    final name = data.sides[w].name;
    final far = data.winFartherM;
    final m = data.winMarginDb;
    final marginText = m == null ? null : '${reportDb(m)} median margin';
    if (far != null && far >= 1) {
      return '$name reached ${reportDistance(far, miles)} farther'
          '${marginText == null ? '' : ', $marginText'}';
    }
    return marginText == null
        ? '$name came out ahead'
        : '$name led by $marginText';
  }

  @override
  Widget build(BuildContext context) {
    // Every side shares the first side's origin (one grid).
    final themed = theme != ReportTheme.night;
    final basemap = themed
        ? null
        : reportBasemapFor(data.sides.first.data, background, tiles);
    final rotation = basemap == null ? reportRotation(data.rotationSeed) : 0.0;
    final routes = [
      for (final s in data.sides)
        PrivateRoute.of(s.data,
            hideRadiusM: hideRadiusM, showPath: showPath, rotation: rotation),
    ];
    final frame = RouteFrame.of(routes);
    final wide = format == ReportFormat.wide;
    final story = format == ReportFormat.story;
    final n = data.sides.length;
    final s = wide ? 0.72 : (n > 2 ? 0.8 : 1.0);
    final note = reportNoteText(
        {for (final side in data.sides) ...side.data.notes}
            .where((n) => n is! SingleFarReadingNote)
            .toList(),
        miles);
    if (themed) {
      final comparison = ThemedComparison(
        data: data,
        title: title,
        format: format,
        miles: miles,
        routes: routes,
        winLine: winLine,
        note: note,
      );
      return MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.noScaling),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.fromSize(
            size: format.size,
            child: ClipRect(
              child: switch (theme) {
                ReportTheme.basic =>
                  BasicComparisonCard(comparison: comparison),
                ReportTheme.pop => PopComparisonCard(comparison: comparison),
                ReportTheme.bridge =>
                  BridgeComparisonCard(comparison: comparison),
                ReportTheme.mission =>
                  MissionComparisonCard(comparison: comparison),
                ReportTheme.night => throw StateError('night is not themed'),
              },
            ),
          ),
        ),
      );
    }

    Widget column(int i) {
      final side = data.sides[i];
      final win = data.winner == i;
      final far = side.data.farthestM;
      return ReportPanel(
        glow: win,
        padding: EdgeInsets.all(18 * s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 34 * s,
              child: Row(children: [
                Expanded(
                  child: Text(side.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ReportStyle.sans(26 * s, bold: true)),
                ),
                if (win)
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 10 * s, vertical: 3 * s),
                    decoration: BoxDecoration(
                      color: ReportStyle.orange,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('WINNER',
                        style: ReportStyle.mono(15 * s,
                            bold: true, color: ReportStyle.bgBottom)),
                  ),
              ]),
            ),
            SizedBox(height: 12 * s),
            Expanded(
              child: RouteBox(
                route: routes[i],
                frame: frame,
                miles: miles,
                dotRadius: n > 2 ? 7 : 9,
                scaleBar: i == 0,
                scale: s,
                basemap: basemap,
              ),
            ),
            SizedBox(height: 14 * s),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                  far == null
                      ? reportDistance(side.data.routeM, miles)
                      : reportDistance(far, miles),
                  style: ReportStyle.figure(58 * s,
                      bold: true,
                      color: win ? ReportStyle.cyan : ReportStyle.text)),
            ),
            Text(far == null ? 'route length' : 'farthest heard',
                style: ReportStyle.sans(19 * s, color: ReportStyle.soft)),
            SizedBox(height: 10 * s),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                        side.data.medianMarginDb == null
                            ? '-'
                            : reportDb(side.data.medianMarginDb!),
                        style: ReportStyle.figure(34 * s, bold: true)),
                  ),
                ),
                Text('${side.data.samples.length} rdg',
                    style: ReportStyle.mono(17 * s, color: ReportStyle.soft)),
              ],
            ),
            Text('median margin',
                style: ReportStyle.sans(19 * s, color: ReportStyle.soft)),
            SizedBox(height: 10 * s),
            SideSetupList(
                all: [for (final x in data.sides) x.data], index: i, scale: s),
          ],
        ),
      );
    }

    final columns = (story && n > 2)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var row = 0; row < (n + 1) ~/ 2; row++) ...[
                if (row > 0) const SizedBox(height: 20),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < 2; c++) ...[
                        if (c > 0) const SizedBox(width: 20),
                        Expanded(
                            child: row * 2 + c < n
                                ? column(row * 2 + c)
                                : const SizedBox()),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < n; i++) ...[
                if (i > 0) SizedBox(width: wide ? 16 : 20),
                Expanded(child: column(i)),
              ],
            ],
          );

    final verdict = Container(
      padding: EdgeInsets.only(left: 18 * (wide ? 0.72 : 1)),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: ReportStyle.orange, width: 5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (data.verdict != null) ...[
            Text(data.verdict!,
                maxLines: wide ? 1 : 3,
                overflow: TextOverflow.ellipsis,
                style: ReportStyle.sans(wide ? 22 : 30, bold: true)),
            SizedBox(height: wide ? 4 : 8),
          ],
          Text(winLine,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ReportStyle.sans(wide ? 19 : 25, color: ReportStyle.cyan)),
          if (note != null) ...[
            SizedBox(height: wide ? 4 : 8),
            Text(note,
                maxLines: 2,
                style:
                    ReportStyle.sans(wide ? 14 : 18, color: ReportStyle.soft)),
          ],
        ],
      ),
    );

    final header = ReportHeader(
      kicker: 'SETUP COMPARISON',
      title: title,
      subtitle: '$n setups',
      scale: wide ? 0.72 : 1,
    );

    return MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.noScaling),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ReportFrame(
          size: format.size,
          padding: switch (format) {
            ReportFormat.feed => const EdgeInsets.fromLTRB(50, 46, 50, 36),
            ReportFormat.story => const EdgeInsets.fromLTRB(50, 70, 50, 60),
            ReportFormat.wide => const EdgeInsets.fromLTRB(40, 30, 40, 24),
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              SizedBox(height: wide ? 18 : 34),
              verdict,
              SizedBox(height: wide ? 16 : 30),
              Expanded(child: columns),
              SizedBox(height: wide ? 16 : 30),
              ReportFooter(scale: wide ? 0.62 : 1),
            ],
          ),
        ),
      ),
    );
  }
}
