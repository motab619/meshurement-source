// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/services/coverage_interpolation.dart';
import 'package:mesh_analyzer/services/rig_comparison.dart';
import 'package:mesh_analyzer/services/rig_math.dart';
import 'package:mesh_analyzer/utils/coverage_raster.dart';

const _lat = 33.68007;
const _lon = -116.24006;
double _east(double m) => _lon + m / metersPerDegree(_lat).$2;

/// A route heading east from 0 to [lengthM], a point every 25 m.
SidePoints _route(double lengthM, double rssi, {double snr = 5}) {
  final lats = <double>[], lons = <double>[];
  final r = <double?>[], s = <double?>[];
  for (var m = 0.0; m <= lengthM; m += 25) {
    lats.add(_lat);
    lons.add(_east(m));
    r.add(rssi);
    s.add(snr);
  }
  return SidePoints(lats, lons, r, s);
}

const _stock = RigSpec(name: 'Stock', antennaGainDbi: 2.0);
const _whip = RigSpec(name: 'Whip', antennaGainDbi: 5.8, connectorCount: 1);
const _base = RigSpec(
    name: 'Base',
    antennaGainDbi: 5.8,
    cableType: 'lmr240',
    cableLengthM: 3,
    connectorCount: 2);

Future<Session> _session(
  AppDatabase db,
  int mapId, {
  RigSpec? mobile,
  RigSpec? base,
  String preset = 'MEDIUM_FAST',
  String protocol = 'meshtastic',
}) async {
  final id = await db.createSession(
    coverageMapId: mapId,
    loraPreset: preset,
    protocol: protocol,
    mobileRigJson: mobile?.encode(),
    baseRigJson: base?.encode(),
  );
  return (await db.getSessionById(id))!;
}

void main() {
  late AppDatabase db;
  late int mapId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Meshurement',
      packageName: 'x',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final nodeId = await db.upsertNode(nodeId: 1, longName: 'Base');
    mapId = await db.createCoverageMap(name: 'Map', baseNodeId: nodeId);
  });

  tearDown(() => db.close());

  group('compareRoutes', () {
    test('compares only cells both sides measured', () {
      final r = compareRoutes(_route(1000, -90), _route(500, -85))!;
      final g = r.grid;
      double? at(double m) {
        final i = CoverageGrid(
          south: g.south,
          west: g.west,
          north: g.north,
          east: g.east,
          cols: g.cols,
          rows: g.rows,
          cellMeters: g.cellMeters,
          values: r.rssiDelta,
          alpha: r.rssiDelta,
        ).cellAt(_lat, _east(m));
        return i < 0 ? null : r.rssiDelta[i].toDouble();
      }

      expect(at(250), closeTo(5, 1e-4));
      expect(at(500), closeTo(5, 1e-4));
      // B has nothing past ~575 m (500 + 75 m match radius).
      expect(at(700), isNaN);
      expect(at(950), isNaN);
      // And nothing off the route sideways is compared.
      expect(r.rssi.cells, inInclusiveRange(20, 60));
    });

    test('exposes each side\'s own cells, including one-sided ones', () {
      final r = compareRoutes(_route(1000, -90), _route(500, -85))!;
      var aOnly = 0, bOnly = 0, both = 0;
      for (var i = 0; i < r.rssiDelta.length; i++) {
        final a = r.rssiA[i], b = r.rssiB[i];
        if (!a.isNaN && !b.isNaN) {
          both++;
          expect(a, closeTo(-90, 1e-4));
          expect(b, closeTo(-85, 1e-4));
          expect(r.rssiDelta[i], closeTo(b - a, 1e-4));
        } else {
          expect(r.rssiDelta[i], isNaN);
          if (!a.isNaN) aOnly++;
          if (!b.isNaN) bOnly++;
        }
      }
      expect(both, r.rssi.cells);
      // A walked ~425 m further east than B: those cells are A-only.
      expect(aOnly, greaterThan(10));
      expect(bOnly, 0);
      expect(r.snrA.length, r.snrDelta.length);
      expect(r.snrB.where((v) => !v.isNaN).length, greaterThan(0));
    });

    test('delta is B minus A: positive when B is stronger', () {
      final up = compareRoutes(_route(500, -100), _route(500, -90))!;
      expect(up.rssi.medianDelta, closeTo(10, 1e-4));
      final down = compareRoutes(_route(500, -90), _route(500, -100))!;
      expect(down.rssi.medianDelta, closeTo(-10, 1e-4));
    });

    test('percentages use the 3 dB threshold', () {
      final r = compareRoutes(_route(500, -90), _route(500, -87))!;
      expect(r.rssi.pctBBetter, 100); // exactly +3 counts
      expect(r.rssi.pctABetter, 0);
      final small = compareRoutes(_route(500, -90), _route(500, -88))!;
      expect(small.rssi.pctBBetter, 0);
    });

    test('no overlap yields no compared cells', () {
      final a = _route(200, -90);
      // B starts 2 km east.
      final b = SidePoints(
        [for (final _ in a.lats) _lat],
        [for (final lon in a.lons) lon + 2000 / metersPerDegree(_lat).$2],
        a.rssi,
        a.snr,
      );
      expect(compareRoutes(a, b)!.isEmpty, isTrue);
    });

    test('empty side returns null', () {
      expect(compareRoutes(const SidePoints([], [], [], []), _route(100, -90)),
          isNull);
    });

    test('readings without SNR are skipped for the SNR delta', () {
      final a = _route(300, -90);
      final noSnr =
          SidePoints(a.lats, a.lons, a.rssi, [for (final _ in a.snr) null]);
      final r = compareRoutes(a, noSnr)!;
      expect(r.rssi.cells, greaterThan(0));
      expect(r.snr.cells, 0);
    });
  });

  test('median of even and odd lists', () {
    expect(median([3, 1, 2]), 2);
    expect(median([4, 1, 3, 2]), 2.5);
    expect(median([]), 0);
  });

  group('compatibility', () {
    test('different protocols are refused', () async {
      final a = await _session(db, mapId);
      final b = await _session(db, mapId, protocol: 'meshcore');
      final c = checkComparable([a], [b]);
      expect(c.ok, isFalse);
      expect(c.refusal, contains('protocols'));
    });

    test('different presets warn but are allowed', () async {
      final a = await _session(db, mapId);
      final b = await _session(db, mapId, preset: 'LONG_FAST');
      final c = checkComparable([a], [b]);
      expect(c.ok, isTrue);
      expect(c.warning, contains('presets'));
    });

    test('same preset is clean; empty or shared sides are refused', () async {
      final a = await _session(db, mapId);
      final b = await _session(db, mapId);
      final c = checkComparable([a], [b]);
      expect(c.ok, isTrue);
      expect(c.warning, isNull);
      expect(checkComparable([a], []).ok, isFalse);
      expect(checkComparable([a], [a]).ok, isFalse);
    });
  });

  group('expected delta from rig snapshots', () {
    test('mobile and base contributions both count', () async {
      final a = await _session(db, mapId, mobile: _stock, base: _base);
      final b = await _session(db, mapId, mobile: _whip, base: _stock);
      final e = expectedRigDelta([a], [b]);
      expect(
          e.mobileDeltaDb, closeTo(_whip.netGainDb - _stock.netGainDb, 1e-9));
      expect(e.baseDeltaDb, closeTo(_stock.netGainDb - _base.netGainDb, 1e-9));
      expect(
          e.deltaDb,
          closeTo(
              expectedDeltaDb(_whip, _stock) + expectedDeltaDb(_stock, _base),
              1e-9));
    });

    test('uses the snapshot, not later profile edits', () async {
      final a = await _session(db, mapId, mobile: _stock, base: _base);
      final b = await _session(db, mapId, mobile: _whip, base: _base);
      final id = await db.insertRigProfile(RigProfilesCompanion.insert(
        name: 'Whip',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      // Editing a profile row changes nothing in the sessions' JSON.
      expect(id, greaterThan(0));
      expect(expectedRigDelta([a], [b]).deltaDb, closeTo(3.7, 1e-9));
    });

    test('no profile on either side', () async {
      final a = await _session(db, mapId);
      final b = await _session(db, mapId);
      final e = expectedRigDelta([a], [b]);
      expect(e.noProfiles, isTrue);
      expect(e.deltaDb, isNull);
    });

    test('profile on one side only makes the expectation unknown', () async {
      final a = await _session(db, mapId, mobile: _stock);
      final b = await _session(db, mapId);
      final e = expectedRigDelta([a], [b]);
      expect(e.noProfiles, isFalse);
      expect(e.deltaDb, isNull);
    });

    test('a role untagged on both sides counts as no change', () async {
      final a = await _session(db, mapId, mobile: _stock);
      final b = await _session(db, mapId, mobile: _whip);
      expect(expectedRigDelta([a], [b]).deltaDb, closeTo(3.7, 1e-9));
    });

    test('groups average their sessions', () async {
      final s1 = await _session(db, mapId, mobile: _stock);
      final s2 = await _session(db, mapId, mobile: _whip);
      final g = groupRig([s1, s2], mobile: true);
      expect(g.netGainDb, closeTo((2.0 + 5.7) / 2, 1e-9));
      expect(g.label, contains('Mixed'));
    });
  });

  group('verdict', () {
    test('close to the spec', () {
      final v = comparisonVerdict(
        measuredMedianDb: 4.1,
        expected: const RigExpectation(5, 5, 0, false),
        cells: 50,
      );
      expect(v, contains('B was ~4 dB stronger'));
      expect(v, contains('close to the 5 dB its specs predict'));
    });

    test('A stronger, less than predicted, no profile, no overlap', () {
      expect(
        comparisonVerdict(
            measuredMedianDb: -6,
            expected: const RigExpectation(-1, -1, 0, false),
            cells: 9),
        allOf(contains('A was ~6 dB'), contains('more than')),
      );
      expect(
        comparisonVerdict(
            measuredMedianDb: 1.5,
            expected: const RigExpectation(8, 8, 0, false),
            cells: 9),
        contains('less than'),
      );
      expect(
        comparisonVerdict(
            measuredMedianDb: 3,
            expected: const RigExpectation(null, 0, 0, true),
            cells: 9),
        contains('No hardware profile'),
      );
      expect(
        comparisonVerdict(
            measuredMedianDb: 3,
            expected: const RigExpectation(null, 0, 0, true),
            cells: 0),
        contains('do not overlap'),
      );
    });
  });

  test('delta colours: grey at 0, blue for B, orange for A, clamped', () {
    expect(comparisonDeltaColor(0, 10), comparisonNeutralColor);
    expect(comparisonDeltaColor(10, 10), comparisonBetterBColor);
    expect(comparisonDeltaColor(99, 10), comparisonBetterBColor);
    expect(comparisonDeltaColor(-10, 10), comparisonBetterAColor);
    expect(comparisonDeltaColor(5, 10), isNot(comparisonDeltaColor(-5, 10)));
  });

  test('winner colours use the 3 dB threshold', () {
    const t = comparisonClearDeltaDb;
    expect(comparisonWinnerColor(3, t), comparisonBetterBColor);
    expect(comparisonWinnerColor(2.9, t), comparisonNeutralColor);
    expect(comparisonWinnerColor(0, t), comparisonNeutralColor);
    expect(comparisonWinnerColor(-2.9, t), comparisonNeutralColor);
    expect(comparisonWinnerColor(-3, t), comparisonBetterAColor);
  });

  test('saved comparisons round-trip, dedupe and survive bad data', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = SavedComparisonStore(prefs);
    final c = SavedComparison(
        mapId: 1,
        sessionIdsA: [1, 2],
        sessionIdsB: [3],
        createdAt: DateTime(2026, 1, 1));
    await store.add(c);
    await store.add(SavedComparison(
        mapId: 1,
        sessionIdsA: [2, 1],
        sessionIdsB: [3],
        createdAt: DateTime(2026, 2, 1)));
    expect(store.all(), hasLength(1));
    expect(store.forMap(1).single.sessionIdsA, [2, 1]);
    expect(store.forMap(2), isEmpty);
    expect(store.contains(c), isTrue);
    await store.remove(c);
    expect(store.all(), isEmpty);
    await prefs.setString(savedComparisonsKey, 'not json');
    expect(store.all(), isEmpty);
  });
}
