// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../../../data/radio/radio_types.dart' show RadioProtocol;
import '../../../services/field_report/field_report_data.dart';
import '../../../services/field_report/private_route.dart';
import '../../protocol_text.dart';
import 'report_basemap.dart';
import 'report_painters.dart';
import 'report_parts.dart';
import 'report_style.dart';
import 'report_theme.dart';
import 'themes/basic_card.dart';
import 'themes/bridge_card.dart';
import 'themes/mission_card.dart';
import 'themes/pop_card.dart';

/// The shareable Field Report for one session, laid out at the format's
/// pixel size (docs/design/field-report/README.md). Shows no coordinates:
/// the route is metres from the base, rotated and trimmed by
/// [PrivateRoute], on a plain grid.
class FieldReportCard extends StatelessWidget {
  const FieldReportCard({
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

  /// The look; every theme but Night draws the plain route (no map).
  final ReportTheme theme;

  final FieldReportData data;

  /// Plain grid, or a map under the route (needs [tiles]); a map draws the
  /// route north-up, unturned.
  final ReportBackground background;
  final ReportTileLoader? tiles;

  /// Card title from the report sheet (never the session name by default).
  final String title;
  final ReportFormat format;
  final bool miles;
  final double hideRadiusM;

  /// Draw the track line; false shows the readings' points only.
  final bool showPath;

  String get _subtitle {
    final dateAndPreset = defaultReportTitle(data.presetName, data.startedAt);
    return title.trim() == dateAndPreset
        ? probeProtocolLabel(data.protocol)
        : dateAndPreset;
  }

  @override
  Widget build(BuildContext context) {
    if (theme != ReportTheme.night) return _themed();
    final basemap = reportBasemapFor(data, background, tiles);
    final route = PrivateRoute.of(data,
        hideRadiusM: hideRadiusM,
        showPath: showPath,
        rotation: basemap == null ? null : 0);
    final frame = RouteFrame.of([route]);
    final note = reportNoteText(data.notes, miles);
    final map = RouteCaption(
      note: note,
      scale: format == ReportFormat.wide ? 0.8 : 1,
      map: RouteBox(route: route, frame: frame, miles: miles, basemap: basemap),
    );
    final header = ReportHeader(
      kicker: 'LORA COVERAGE SESSION',
      title: title,
      subtitle: _subtitle,
      scale: format == ReportFormat.wide ? 0.72 : 1,
    );
    return MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.noScaling),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: switch (format) {
          ReportFormat.feed => _feed(header, map),
          ReportFormat.story => _story(header, map),
          ReportFormat.wide => _wide(header, map),
        },
      ),
    );
  }

  Widget _themed() {
    final report = ThemedReport(
      data: data,
      title: title,
      subtitle: _subtitle,
      format: format,
      miles: miles,
      route:
          PrivateRoute.of(data, hideRadiusM: hideRadiusM, showPath: showPath),
      note: reportNoteText(data.notes, miles),
    );
    return MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.noScaling),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.fromSize(
          size: format.size,
          child: ClipRect(
            child: switch (theme) {
              ReportTheme.basic => BasicReportCard(report: report),
              ReportTheme.pop => PopReportCard(report: report),
              ReportTheme.bridge => BridgeReportCard(report: report),
              ReportTheme.mission => MissionReportCard(report: report),
              ReportTheme.night => throw StateError('night is not themed'),
            },
          ),
        ),
      ),
    );
  }

  Widget _feed(Widget header, Widget map) => ReportFrame(
        size: format.size,
        padding: const EdgeInsets.fromLTRB(50, 46, 50, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 26),
            SizedBox(
              height: 510,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: map),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 340,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                            child: ScaleDownBox(
                                child: BragTile(data: data, miles: miles))),
                        const SizedBox(height: 20),
                        Flexible(
                            child: ScaleDownBox(
                                alignment: Alignment.bottomCenter,
                                child: MarginsPanel(data: data))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            StatRow(data: data, miles: miles),
            const SizedBox(height: 20),
            Expanded(child: MarginChartPanel(data: data)),
            const SizedBox(height: 20),
            SetupRow(data: data),
            const SizedBox(height: 22),
            const ReportFooter(),
          ],
        ),
      );

  Widget _story(Widget header, Widget map) => ReportFrame(
        size: format.size,
        padding: const EdgeInsets.fromLTRB(50, 70, 50, 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 36),
            BragTile(data: data, miles: miles, scale: 1.15),
            const SizedBox(height: 26),
            Expanded(child: map),
            const SizedBox(height: 26),
            MarginsPanel(data: data, scale: 1.1),
            const SizedBox(height: 26),
            StatRow(data: data, miles: miles),
            const SizedBox(height: 26),
            SizedBox(height: 250, child: MarginChartPanel(data: data)),
            const SizedBox(height: 26),
            SetupRow(data: data),
            const SizedBox(height: 30),
            const ReportFooter(),
          ],
        ),
      );

  Widget _wide(Widget header, Widget map) => ReportFrame(
        size: format.size,
        padding: const EdgeInsets.fromLTRB(40, 30, 40, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 22),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: map),
                  const SizedBox(width: 22),
                  SizedBox(
                    width: 470,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                            child: ScaleDownBox(
                                child: BragTile(
                                    data: data, miles: miles, scale: 0.85))),
                        const SizedBox(height: 16),
                        Flexible(
                            child: ScaleDownBox(
                                alignment: Alignment.bottomCenter,
                                child: MarginsPanel(
                                    data: data, scale: 0.86, compact: true))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
                [
                  for (final (label, v) in SideSetupList.rowsFor([data]))
                    if (v.single.isNotEmpty) '$label ${v.single}',
                ].join('   '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ReportStyle.sans(17, color: ReportStyle.soft)),
            const SizedBox(height: 12),
            const ReportFooter(scale: 0.62),
          ],
        ),
      );
}

/// "Meshtastic" / "MeshCore" for a stored protocol (factual label).
String probeProtocolLabel(String protocol) =>
    protocolLabel(protocol == RadioProtocol.meshcore.name
        ? RadioProtocol.meshcore
        : RadioProtocol.meshtastic);
