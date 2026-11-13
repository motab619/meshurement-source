// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import '../guided/plan_models.dart';
import '../rig_comparison.dart' show comparisonClearDeltaDb;
import 'field_report_data.dart';

/// One setup on a comparison card.
class ComparisonSide {
  /// "5.8 dBi whip", "Medium Fast", "A".
  final String name;
  final FieldReportData data;

  const ComparisonSide(this.name, this.data);
}

/// Sessions of one side, before building.
class ComparisonSideInput {
  final String name;
  final List<SessionReportInput> sessions;

  const ComparisonSideInput(this.name, this.sessions);
}

/// The numbers on a comparison card (guided test result, rig comparison):
/// per side the farthest heard distance and median margin, the winner and
/// how far ahead it was, and the guided test's verdict line.
class ComparisonReportData {
  final List<ComparisonSide> sides;

  /// Index into [sides]; null for a tie (no clear winner).
  final int? winner;

  /// How much farther the winner reached than the best other side (null
  /// when a distance is missing or it didn't reach farther).
  final double? winFartherM;

  /// Winner's median margin minus the best other side's.
  final double? winMarginDb;

  /// `PlanAnalysisResult.headline`, when the comparison came from a guided
  /// test.
  final String? verdict;

  const ComparisonReportData({
    required this.sides,
    this.winner,
    this.winFartherM,
    this.winMarginDb,
    this.verdict,
  });

  DateTime get startedAt => sides
      .map((s) => s.data.startedAt)
      .reduce((a, b) => a.isBefore(b) ? a : b);

  /// The range setting every side used, or empty when they differ.
  String get presetName {
    final names = {for (final s in sides) s.data.presetName};
    return names.length == 1 ? names.first : '';
  }

  /// Seed for the shared rotation.
  int get rotationSeed =>
      sides.map((s) => s.data.rotationSeed).reduce(math.min);

  ReportOrigin get origin => sides.first.data.origin;

  /// Build every side on one grid: from the base when the sessions as a
  /// whole sit near it, else from the earliest session's first fix.
  /// [result] supplies the winner and verdict of a guided test.
  factory ComparisonReportData.build(
    List<ComparisonSideInput> inputs, {
    GeoPoint? base,
    PlanAnalysisResult? result,
  }) {
    // Decide the origin over every side together, so they share a grid.
    final all = [for (final s in inputs) ...s.sessions];
    final probe = FieldReportData.build(all, base: base);
    final useBase = probe.origin == ReportOrigin.base;
    GeoPoint? start;
    if (!useBase) {
      final fixes = [
        for (final i in all)
          for (final e in i.events)
            if (e.rxLat != null && e.rxLon != null) e,
      ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (fixes.isNotEmpty) {
        start = (lat: fixes.first.rxLat!, lon: fixes.first.rxLon!);
      }
    }
    final sides = [
      for (final s in inputs)
        ComparisonSide(
          s.name,
          FieldReportData.build(s.sessions,
              base: base, fallbackOrigin: start, forceStartOrigin: !useBase),
        ),
    ];

    int? winner = result?.winner;
    if (winner != null && (winner < 0 || winner >= sides.length)) {
      winner = null;
    }
    if (result == null) winner = _pickWinner(sides);

    double? farther, margin;
    if (winner != null && sides.length > 1) {
      final w = sides[winner].data;
      final others = [
        for (var i = 0; i < sides.length; i++)
          if (i != winner) sides[i].data,
      ];
      final otherFar = others.map((d) => d.farthestM).whereType<double>();
      if (w.farthestM != null && otherFar.isNotEmpty) {
        final d = w.farthestM! - otherFar.reduce(math.max);
        if (d > 0) farther = d;
      }
      final otherMargin =
          others.map((d) => d.medianMarginDb).whereType<double>();
      if (w.medianMarginDb != null && otherMargin.isNotEmpty) {
        margin = w.medianMarginDb! - otherMargin.reduce(math.max);
      }
    }

    return ComparisonReportData(
      sides: sides,
      winner: winner,
      winFartherM: farther,
      winMarginDb: margin,
      verdict: (result?.headline.isNotEmpty ?? false) ? result!.headline : null,
    );
  }

  /// The side that reached clearly farther (by [farthestPairM]), else the
  /// one with a clearly better median margin (3 dB), else none.
  static int? _pickWinner(List<ComparisonSide> sides) {
    int? best(double? Function(FieldReportData) f, double clear) {
      final vals = [for (final s in sides) f(s.data)];
      if (vals.any((v) => v == null)) return null;
      final order = List.generate(vals.length, (i) => i)
        ..sort((a, b) => vals[b]!.compareTo(vals[a]!));
      if (order.length < 2) return order.first;
      return vals[order[0]]! - vals[order[1]]! >= clear ? order[0] : null;
    }

    return best((d) => d.farthestM, farthestPairM) ??
        best((d) => d.medianMarginDb, comparisonClearDeltaDb);
  }
}
