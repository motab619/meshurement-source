// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/app_database.dart';
import 'coverage_interpolation.dart';
import 'rig_math.dart';

/// Cells are compared only where both sides have a measurement within this
/// many metres of the cell centre; beyond it the interpolation is guesswork.
const comparisonMatchRadiusM = 75.0;

/// The comparison's own interpolation fade, independent of the (much
/// wider) estimated-coverage display fade. Must start inside
/// [comparisonMatchRadiusM].
const _fadeStart = 50.0, _fadeEnd = 300.0;

/// Interpolation alpha for a cell whose nearest measurement is exactly
/// [comparisonMatchRadiusM] away (alpha is 1 out to [_fadeStart], then falls
/// linearly to 0 at [_fadeEnd]). Cells with at least this alpha are matched.
const _matchAlphaMin =
    (_fadeEnd - comparisonMatchRadiusM) / (_fadeEnd - _fadeStart) - 1e-6;

/// A delta of at least this many dB counts as clearly better.
const comparisonClearDeltaDb = 3.0;

/// Measured points of one side of a comparison.
class SidePoints {
  final List<double> lats, lons;

  /// Null where the packet had no RSSI / SNR.
  final List<double?> rssi, snr;

  const SidePoints(this.lats, this.lons, this.rssi, this.snr);
}

/// Stats for one metric (RSSI or SNR, in dB) over matched cells.
class MetricStats {
  final int cells;
  final double medianDelta;

  /// Share (0..100) of cells where B / A is better by at least 3 dB.
  final double pctBBetter;
  final double pctABetter;

  const MetricStats(
      this.cells, this.medianDelta, this.pctBBetter, this.pctABetter);

  static const empty = MetricStats(0, 0, 0, 0);
}

/// Delta grids (B minus A, NaN = not compared) on one shared grid, plus
/// each side's own interpolated values (NaN where that side has no reading
/// within [comparisonMatchRadiusM]), so A-only / B-only cells can be shown.
class RouteComparison {
  final CoverageGridSpec grid;
  final Float32List rssiDelta;
  final Float32List snrDelta;
  final MetricStats rssi;
  final MetricStats snr;
  final Float32List rssiA, rssiB, snrA, snrB;

  const RouteComparison(
    this.grid,
    this.rssiDelta,
    this.snrDelta,
    this.rssi,
    this.snr, {
    required this.rssiA,
    required this.rssiB,
    required this.snrA,
    required this.snrB,
  });

  bool get isEmpty => rssi.cells == 0 && snr.cells == 0;
}

/// Median of an unsorted list (0 for empty).
double median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Matches [a] and [b] on one ~50 m grid and returns B - A per cell, only
/// where both sides measured within [comparisonMatchRadiusM]. Null if either
/// side has no points.
RouteComparison? compareRoutes(SidePoints a, SidePoints b) {
  if (a.lats.isEmpty || b.lats.isEmpty) return null;
  final spec = coverageGridSpecFor(
      [...a.lats, ...b.lats], [...a.lons, ...b.lons],
      fadeEnd: _fadeEnd)!;
  final size = spec.cols * spec.rows;

  /// One side's values where it measured within the match radius.
  Float32List sideValues(CoverageGrid? g) {
    final out = Float32List(size)..fillRange(0, size, double.nan);
    if (g == null) return out;
    for (var i = 0; i < size; i++) {
      if (g.alpha[i] >= _matchAlphaMin) out[i] = g.values[i];
    }
    return out;
  }

  (Float32List, MetricStats, Float32List, Float32List) delta(
      List<double?> ma, List<double?> mb) {
    final va = sideValues(_grid(a, ma, spec));
    final vb = sideValues(_grid(b, mb, spec));
    final out = Float32List(size)..fillRange(0, size, double.nan);
    final deltas = <double>[];
    var bBetter = 0, aBetter = 0;
    for (var i = 0; i < size; i++) {
      if (va[i].isNaN || vb[i].isNaN) continue;
      final d = (vb[i] - va[i]).toDouble();
      out[i] = d;
      deltas.add(d);
      if (d >= comparisonClearDeltaDb) bBetter++;
      if (d <= -comparisonClearDeltaDb) aBetter++;
    }
    if (deltas.isEmpty) return (out, MetricStats.empty, va, vb);
    final n = deltas.length;
    return (
      out,
      MetricStats(n, median(deltas), 100 * bBetter / n, 100 * aBetter / n),
      va,
      vb,
    );
  }

  final (rssiGrid, rssiStats, rssiA, rssiB) = delta(a.rssi, b.rssi);
  final (snrGrid, snrStats, snrA, snrB) = delta(a.snr, b.snr);
  return RouteComparison(spec, rssiGrid, snrGrid, rssiStats, snrStats,
      rssiA: rssiA, rssiB: rssiB, snrA: snrA, snrB: snrB);
}

CoverageGrid? _grid(SidePoints p, List<double?> metric, CoverageGridSpec spec) {
  final lats = <double>[], lons = <double>[], vals = <double>[];
  for (var i = 0; i < p.lats.length; i++) {
    final v = metric[i];
    if (v == null) continue;
    lats.add(p.lats[i]);
    lons.add(p.lons[i]);
    vals.add(v);
  }
  return interpolateCoverage(lats, lons, vals,
      spec: spec, fadeStart: _fadeStart, fadeEnd: _fadeEnd);
}

/// [compareRoutes] on a background isolate.
Future<RouteComparison?> compareRoutesAsync(SidePoints a, SidePoints b) =>
    Isolate.run(() => compareRoutes(a, b));

// ---------------------------------------------------------------------------
// Compatibility

class ComparisonCheck {
  /// Set when the comparison must not be made (one line, shown to the user).
  final String? refusal;

  /// Set when it may go ahead but the result needs care.
  final String? warning;

  const ComparisonCheck({this.refusal, this.warning});

  bool get ok => refusal == null;
}

/// Can these two groups of sessions be compared at all?
ComparisonCheck checkComparable(List<Session> a, List<Session> b) {
  if (a.isEmpty || b.isEmpty) {
    return const ComparisonCheck(
        refusal: 'Pick at least one session for each side.');
  }
  final ids = {for (final s in a) s.id};
  if (b.any((s) => ids.contains(s.id))) {
    return const ComparisonCheck(refusal: 'A session cannot be on both sides.');
  }
  final all = [...a, ...b];
  if ({for (final s in all) s.protocol}.length > 1) {
    return const ComparisonCheck(
        refusal: 'These sessions use different mesh protocols, '
            'so their signal readings cannot be compared.');
  }
  if ({for (final s in all) s.coverageMapId}.length > 1) {
    return const ComparisonCheck(
        refusal: 'Sessions must come from the same coverage map.');
  }
  if ({for (final s in all) s.loraPreset}.length > 1) {
    return const ComparisonCheck(
        warning: 'The sessions use different modem presets, so part of the '
            'difference comes from the preset, not the hardware.');
  }
  return const ComparisonCheck();
}

// ---------------------------------------------------------------------------
// Expected gain from the rig snapshots

/// The rig of a group of sessions in one role (mobile or base).
class GroupRig {
  /// Null when no session has a rig, or only some do.
  final double? netGainDb;
  final String label;
  final bool hasProfile;

  const GroupRig(this.netGainDb, this.label, this.hasProfile);

  static const none = GroupRig(null, 'No hardware profile', false);
}

/// Mean net gain of the rigs snapshotted on [sessions] (the session JSON, so
/// later edits to a profile do not rewrite history).
GroupRig groupRig(List<Session> sessions, {required bool mobile}) {
  final specs = [
    for (final s in sessions)
      RigSpec.decode(mobile ? s.mobileRigJson : s.baseRigJson),
  ];
  final known = specs.whereType<RigSpec>().toList();
  if (known.isEmpty) return GroupRig.none;
  final names = <String>{for (final r in known) r.name}.toList();
  final label = names.length == 1 ? names.first : 'Mixed (${names.join(', ')})';
  if (known.length != specs.length) {
    return GroupRig(null, '$label + untagged', true);
  }
  final gain =
      known.map((r) => r.netGainDb).reduce((x, y) => x + y) / known.length;
  return GroupRig(gain, label, true);
}

class RigExpectation {
  /// Expected B - A in dB, or null if the profiles don't say.
  final double? deltaDb;
  final double mobileDeltaDb;
  final double baseDeltaDb;

  /// Neither side has any hardware profile.
  final bool noProfiles;

  const RigExpectation(
      this.deltaDb, this.mobileDeltaDb, this.baseDeltaDb, this.noProfiles);
}

/// Expected signal gain of B over A: change in mobile net gain plus change
/// in base net gain (both ends of the link count). A role that is untagged
/// on both sides contributes 0; tagged on one side only makes it unknown.
RigExpectation expectedRigDelta(List<Session> a, List<Session> b) {
  final groups = [
    groupRig(a, mobile: true),
    groupRig(a, mobile: false),
    groupRig(b, mobile: true),
    groupRig(b, mobile: false),
  ];
  if (!groups.any((g) => g.hasProfile)) {
    return const RigExpectation(null, 0, 0, true);
  }

  double? role(GroupRig ga, GroupRig gb) {
    if (!ga.hasProfile && !gb.hasProfile) return 0;
    if (ga.netGainDb == null || gb.netGainDb == null) return null;
    return gb.netGainDb! - ga.netGainDb!;
  }

  final m = role(groups[0], groups[2]);
  final bs = role(groups[1], groups[3]);
  if (m == null || bs == null) {
    return RigExpectation(null, m ?? 0, bs ?? 0, false);
  }
  return RigExpectation(m + bs, m, bs, false);
}

/// One or two plain sentences about the result.
String comparisonVerdict({
  required double measuredMedianDb,
  required RigExpectation expected,
  required int cells,
}) {
  if (cells == 0) {
    return 'The two routes do not overlap closely enough to compare.';
  }
  String dbText(double v) => '${v.abs().round()} dB';
  final m = measuredMedianDb;
  final head = m.abs() < 1
      ? 'Both sides performed about the same '
          '(median ${formatGainDb(m)}).'
      : "${m > 0 ? 'B' : 'A'} was ~${dbText(m)} stronger on this route.";
  final e = expected.deltaDb;
  if (expected.noProfiles) {
    return '$head No hardware profile on these sessions, so there is no '
        'spec to compare against.';
  }
  if (e == null) {
    return '$head Only one side has a hardware profile, so the expected '
        'difference is unknown.';
  }
  if (e.abs() < 0.5) {
    return m.abs() < 1
        ? '$head The hardware specs predict no difference.'
        : '$head The hardware specs predict no difference, so look for '
            'another cause (placement, weather, preset).';
  }
  final predicts = 'the ${dbText(e)} its specs predict';
  final sameDirection = m.abs() < 1 || (m > 0) == (e > 0);
  if (!sameDirection) {
    return '$head The specs predict the opposite: '
        '${e > 0 ? 'B' : 'A'} stronger by ${dbText(e)}.';
  }
  final diff = m.abs() - e.abs();
  if (diff.abs() <= 2) return '$head That is close to $predicts.';
  return diff > 0
      ? '$head That is ${dbText(diff)} more than $predicts.'
      : '$head That is ${dbText(diff)} less than $predicts.';
}

// ---------------------------------------------------------------------------
// Saved comparisons

const savedComparisonsKey = 'saved_comparisons_v1';

class SavedComparison {
  final int mapId;
  final List<int> sessionIdsA, sessionIdsB;
  final DateTime createdAt;

  const SavedComparison({
    required this.mapId,
    required this.sessionIdsA,
    required this.sessionIdsB,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'mapId': mapId,
        'sessionIdsA': sessionIdsA,
        'sessionIdsB': sessionIdsB,
        'createdAt': createdAt.toIso8601String(),
      };

  static SavedComparison? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return SavedComparison(
        mapId: (j['mapId'] as num).toInt(),
        sessionIdsA: [
          for (final v in j['sessionIdsA'] as List) (v as num).toInt()
        ],
        sessionIdsB: [
          for (final v in j['sessionIdsB'] as List) (v as num).toInt()
        ],
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  bool sameAs(SavedComparison o) =>
      mapId == o.mapId &&
      _sameSet(sessionIdsA, o.sessionIdsA) &&
      _sameSet(sessionIdsB, o.sessionIdsB);

  static bool _sameSet(List<int> x, List<int> y) =>
      x.toSet().length == y.toSet().length && x.toSet().containsAll(y);
}

/// Pairs of session groups worth coming back to, in SharedPreferences.
class SavedComparisonStore {
  final SharedPreferences prefs;

  SavedComparisonStore(this.prefs);

  List<SavedComparison> all() {
    final raw = prefs.getString(savedComparisonsKey);
    if (raw == null) return [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          if (SavedComparison.fromJson(j) case final c?) c,
      ];
    } catch (_) {
      return [];
    }
  }

  List<SavedComparison> forMap(int mapId) => [
        for (final c in all())
          if (c.mapId == mapId) c
      ];

  bool contains(SavedComparison c) => all().any((x) => x.sameAs(c));

  Future<void> add(SavedComparison c) =>
      _write([c, ...all().where((x) => !x.sameAs(c))]);

  Future<void> remove(SavedComparison c) =>
      _write(all().where((x) => !x.sameAs(c)).toList());

  /// Drop saved comparisons that use any of [sessionIds] (they were
  /// deleted, so the comparison can't be rebuilt).
  Future<void> removeSessions(Set<int> sessionIds) => _write([
        for (final c in all())
          if (!c.sessionIdsA.any(sessionIds.contains) &&
              !c.sessionIdsB.any(sessionIds.contains))
            c
      ]);

  Future<void> _write(List<SavedComparison> l) => prefs.setString(
      savedComparisonsKey, jsonEncode([for (final c in l) c.toJson()]));
}
