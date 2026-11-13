// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import '../../data/database/app_database.dart';
import '../guided/plan_models.dart';
import 'comparison_report_data.dart';
import 'field_report_data.dart';

/// Reads what a Field Report needs from the database.
class FieldReportLoader {
  final AppDatabase db;
  const FieldReportLoader(this.db);

  Future<SessionReportInput?> _input(int sessionId) async {
    final s = await db.getSessionById(sessionId);
    if (s == null) return null;
    final events = await db.getEventsForSession(sessionId, includeMisses: true);
    final pings = await db.getPingsForSession(sessionId);
    var hw = '';
    final baseLocal = await db.baseNodeIdForSession(s);
    if (baseLocal != null) {
      final node = await (db.select(db.nodes)
            ..where((n) => n.id.equals(baseLocal)))
          .getSingleOrNull();
      hw = node?.hwModel ?? '';
    }
    return SessionReportInput(
        session: s, events: events, pings: pings, baseHwModel: hw);
  }

  Future<GeoPoint?> _base(int coverageMapId) async {
    final map = await db.getCoverageMap(coverageMapId);
    final lat = map?.baseLat, lon = map?.baseLon;
    return lat == null || lon == null ? null : (lat: lat, lon: lon);
  }

  /// One session's report, measured from its map's base location.
  Future<FieldReportData?> session(int sessionId) async {
    final input = await _input(sessionId);
    if (input == null) return null;
    return FieldReportData.build([input],
        base: await _base(input.session.coverageMapId));
  }

  /// A comparison of named groups of sessions on one map.
  Future<ComparisonReportData?> comparison(
    int coverageMapId,
    List<(String, List<int>)> sides, {
    PlanAnalysisResult? result,
  }) async {
    final inputs = <ComparisonSideInput>[];
    for (final (name, ids) in sides) {
      final sessions = [
        for (final id in ids) await _input(id),
      ].whereType<SessionReportInput>().toList();
      if (sessions.isEmpty) continue;
      inputs.add(ComparisonSideInput(name, sessions));
    }
    if (inputs.length < 2) return null;
    return ComparisonReportData.build(inputs,
        base: await _base(coverageMapId), result: result);
  }
}
