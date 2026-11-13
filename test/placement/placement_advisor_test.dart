// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesh_analyzer/services/placement/placement_advisor.dart';
import 'package:mesh_analyzer/services/terrain/elevation_source.dart';
import 'package:mesh_analyzer/services/terrain/terrain_service.dart';

const origin = LatLng(33.0, -116.0);
const _mLat = 111132.0;
final _mLon = 111320.0 * math.cos(33.0 * math.pi / 180);

LatLng at(double eastM, double northM) =>
    LatLng(origin.latitude + northM / _mLat, origin.longitude + eastM / _mLon);

double _gauss(double x, double c, double s) =>
    math.exp(-math.pow(x - c, 2) / (2 * s * s));

/// Counts calls and points; elevation from a function of (east, north) m.
class FnSource implements ElevationSource {
  FnSource(this.fn);
  final double Function(double e, double n) fn;
  int calls = 0, points = 0;
  @override
  String get name => 'fn';
  @override
  Future<List<double?>> elevations(List<LatLng> pts) async {
    calls++;
    points += pts.length;
    return [
      for (final p in pts)
        fn((p.longitude - origin.longitude) * _mLon,
            (p.latitude - origin.latitude) * _mLat),
    ];
  }
}

class OfflineSource implements ElevationSource {
  @override
  String get name => 'offline';
  @override
  Future<List<double?>> elevations(List<LatLng> points) =>
      throw const ElevationUnavailable('offline');
}

/// Flat 100 m ground with a N-S ridge 1.5 km east of the base.
double ridgeTerrain(double e, double n) => 100 + 60 * _gauss(e, 1500, 150);

/// Two ridges: one 1.5 km east of the base, one 1.5 km west.
double twoRidges(double e, double n) =>
    100 + 60 * _gauss(e, 1500, 150) + 60 * _gauss(e, -1500, 150);

List<PlacementSample> grid(double e0, double e1, double n0, double n1,
    double rssi) {
  return [
    for (var e = e0; e <= e1; e += 100)
      for (var n = n0; n <= n1; n += 100)
        PlacementSample(at(e, n).latitude, at(e, n).longitude, rssi),
  ];
}

PlacementRequest valleyRequest(ElevationSource src,
        {bool isolate = false, bool predicted = false}) =>
    PlacementRequest(
      base: origin,
      source: src,
      baseHeightM: 10,
      samples: [
        ...grid(100, 800, -300, 300, -90),
        ...grid(2200, 3000, -300, 300, -125),
      ],
      includePredicted: predicted,
      useIsolate: isolate,
    );

void main() {
  test('valley behind a ridge: top site is on the ridge with LOS both ways',
      () async {
    final r = await PlacementAdvisor.suggest(
        valleyRequest(FnSource(ridgeTerrain)));
    expect(r.emptyReason, isNull);
    expect(r.suggestions, isNotEmpty);
    final top = r.suggestions.first;
    expect(top.rank, 1);
    final eastM = (top.lon - origin.longitude) * _mLon;
    expect(eastM, inInclusiveRange(1300, 1700), reason: 'on the ridge');
    expect(top.elevationM, greaterThan(140));
    expect(top.losToBase, isTrue);
    expect(top.linkMarginToBaseDb, greaterThan(3));
    expect(top.coveredPercent, greaterThan(80));
    expect(r.cumulativeCoveredPercent, greaterThan(80));
    expect(r.meta.degraded, isFalse);
    expect(r.meta.measuredShare, 1.0);
    expect(r.meta.calibrated, isTrue);
    expect(r.weakCells.every((w) => w.kind != WeakKind.predicted), isTrue);
    expect(top.notes, isNotEmpty);
  });

  test('predicted cells are labelled and counted separately', () async {
    final r = await PlacementAdvisor.suggest(
        valleyRequest(FnSource(ridgeTerrain), predicted: true));
    expect(r.weakCells.any((w) => w.kind == WeakKind.predicted) ||
        r.meta.predictedShare == 0, isTrue);
    expect(r.meta.measuredShare + r.meta.predictedShare, closeTo(1, 1e-9));
  });

  test('greedy picks add marginal coverage and do not duplicate', () async {
    final req = PlacementRequest(
      base: origin,
      source: FnSource(twoRidges),
      baseHeightM: 10,
      samples: [
        ...grid(100, 600, -300, 300, -90),
        ...grid(2200, 3000, -300, 300, -125),
        ...grid(-3000, -2200, -300, 300, -125),
      ],
      includePredicted: false,
      useIsolate: false,
    );
    final r = await PlacementAdvisor.suggest(req);
    expect(r.suggestions.length, greaterThanOrEqualTo(2));
    final sides = {for (final s in r.suggestions) s.lon > origin.longitude};
    expect(sides, {true, false}, reason: 'one pick per valley');
    var sum = 0;
    var prev = double.infinity;
    for (final s in r.suggestions) {
      expect(s.coveredCells, greaterThan(0));
      expect(s.coveredCells, lessThanOrEqualTo(s.standaloneCoveredCells));
      expect(s.coveredCells, lessThanOrEqualTo(prev));
      prev = s.coveredCells.toDouble();
      sum += s.coveredCells;
    }
    expect(sum, lessThanOrEqualTo(r.meta.scoredCellCount));
    expect(r.cumulativeCoveredPercent,
        closeTo(100 * sum / r.meta.scoredCellCount, 1e-6));
    // Distinct sites.
    final spots = {for (final s in r.suggestions) '${s.lat},${s.lon}'};
    expect(spots.length, r.suggestions.length);
    expect(r.cumulativeCoveredPercent, greaterThan(80));
  });

  test('no weak cells: empty suggestions with a clear reason', () async {
    final r = await PlacementAdvisor.suggest(PlacementRequest(
      base: origin,
      source: FnSource(ridgeTerrain),
      samples: grid(100, 800, -300, 300, -80),
      includePredicted: false,
      useIsolate: false,
    ));
    expect(r.suggestions, isEmpty);
    expect(r.weakCells, isEmpty);
    expect(r.emptyReason, contains('No weak'));
  });

  test('weak SNR and dead points mark cells even with good RSSI', () async {
    final p = at(500, 0);
    final d = at(900, 0);
    final r = await PlacementAdvisor.suggest(PlacementRequest(
      base: origin,
      source: FnSource(ridgeTerrain),
      samples: [PlacementSample(p.latitude, p.longitude, -90, snrDb: -15)],
      deadPoints: [d],
      includePredicted: false,
      useIsolate: false,
    ));
    final kinds = r.weakCells.map((w) => w.kind).toSet();
    expect(kinds, containsAll([WeakKind.measured, WeakKind.dead]));
    expect(r.weakCells.firstWhere((w) => w.kind == WeakKind.dead).rssiDbm,
        isNull);
  });

  test('elevation request budget is respected and cells coarsen', () async {
    final src = FnSource(ridgeTerrain);
    final r = await PlacementAdvisor.suggest(PlacementRequest(
      base: origin,
      source: src,
      samples: [
        PlacementSample(at(-30000, -30000).latitude,
            at(-30000, -30000).longitude, -125),
        PlacementSample(
            at(30000, 30000).latitude, at(30000, 30000).longitude, -125),
      ],
      cellM: 50,
      includePredicted: false,
      useIsolate: false,
    ));
    expect(src.calls, lessThanOrEqualTo(120));
    expect(src.points, lessThanOrEqualTo(12000));
    expect(r.meta.elevationRequests, src.calls);
    expect(r.meta.cellM, greaterThan(50));
    expect(r.meta.requestBudget, 120);
  });

  test('offline source degrades without crashing', () async {
    final r = await PlacementAdvisor.suggest(PlacementRequest(
      base: origin,
      source: OfflineSource(),
      samples: [
        ...grid(100, 500, -200, 200, -90),
        ...grid(2200, 3000, -300, 300, -125),
      ],
      includePredicted: false,
      useIsolate: false,
    ));
    expect(r.meta.degraded, isTrue);
    expect(r.meta.degradedReason, 'offline');
    expect(r.meta.elevationPoints, 0);
    for (final s in r.suggestions) {
      expect(s.elevationM, isNull);
      expect(s.losToBase, isFalse);
      expect(s.notes.join(' '), contains('No terrain data'));
    }
  });

  test('deterministic, and isolate run equals synchronous run', () async {
    Future<PlacementResult> run(bool iso) => PlacementAdvisor.suggest(
        valleyRequest(FnSource(ridgeTerrain), isolate: iso));
    final a = await run(false);
    final b = await run(false);
    final c = await run(true);
    String sig(PlacementResult r) => [
          for (final s in r.suggestions)
            '${s.lat},${s.lon},${s.coveredCells},${s.linkMarginToBaseDb}',
          r.weakCells.length,
        ].join('|');
    expect(sig(a), sig(b));
    expect(sig(a), sig(c));
  });

  test('cancel token aborts', () async {
    final cancel = TerrainCancelToken()..cancel();
    expect(
      PlacementAdvisor.suggest(PlacementRequest(
        base: origin,
        source: FnSource(ridgeTerrain),
        cancel: cancel,
        useIsolate: false,
      )),
      throwsA(isA<TerrainCancelled>()),
    );
  });
}
