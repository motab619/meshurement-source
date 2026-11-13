// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import '../../../services/field_report/comparison_report_data.dart';
import '../../../services/field_report/field_report_data.dart';
import '../../../services/field_report/private_route.dart';
import 'report_style.dart';

/// SharedPreferences key of the last report style picked.
const reportThemePref = 'field_report_theme';

/// The look of a Field Report, single session or comparison
/// (docs/design/field-report/themes.md). Every theme shows the same
/// numbers under the same privacy rules; only the layout and palette
/// change. Night and Basic are free; the others are Pro
/// (`ProFeature.reportStyles`).
enum ReportTheme {
  night('Night'),
  basic('Basic'),
  pop('Pop'),
  bridge('Bridge'),
  mission('Mission');

  const ReportTheme(this.label);
  final String label;

  /// Sharing a card in this style needs Pro (previewing it never does).
  bool get isPro => this == pop || this == bridge || this == mission;

  static ReportTheme fromName(String? name) =>
      values.firstWhere((t) => t.name == name, orElse: () => ReportTheme.night);
}

/// What every themed card is built from. The [route] has already been
/// through [PrivateRoute] (rotated, base area dropped): a theme draws it
/// as given and never reads positions from [data].
class ThemedReport {
  const ThemedReport({
    required this.data,
    required this.title,
    required this.subtitle,
    required this.format,
    required this.miles,
    required this.route,
    this.note,
  });

  final FieldReportData data;
  final String title;

  /// Date and range setting, or the protocol when the title already says
  /// them.
  final String subtitle;
  final ReportFormat format;
  final bool miles;
  final PrivateRoute route;

  /// The card's note line ("Farthest reading had no second reading…"), or
  /// null.
  final String? note;
}

/// What every themed comparison card is built from. [routes] has one
/// entry per `data.sides`, all turned by the same angle and trimmed by
/// [PrivateRoute], to be drawn on one shared `RouteFrame`: a theme never
/// reads positions from the sides' data.
class ThemedComparison {
  const ThemedComparison({
    required this.data,
    required this.title,
    required this.format,
    required this.miles,
    required this.routes,
    required this.winLine,
    this.note,
  });

  /// 2 to 4 sides; `winner` is an index or null for a tie; `verdict` is
  /// the guided test's headline, when there was one.
  final ComparisonReportData data;
  final String title;
  final ReportFormat format;
  final bool miles;
  final List<PrivateRoute> routes;

  /// "5.8 dBi whip reached 0.6 mi farther, +4 dB median margin", or the
  /// no-clear-winner sentence. Always present.
  final String winLine;
  final String? note;
}
