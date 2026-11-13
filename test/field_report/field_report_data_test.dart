// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/services/field_report/comparison_report_data.dart';
import 'package:mesh_analyzer/services/field_report/field_report_data.dart';
import 'package:mesh_analyzer/services/field_report/field_report_loader.dart';
import 'package:mesh_analyzer/services/field_report/private_route.dart';
import 'package:mesh_analyzer/services/guided/plan_models.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('session 32', () {
    late FieldReportData d;
    setUp(() async {
      final s = await seedSession32(db);
      d = (await FieldReportLoader(db).session(s.sessionId))!;
    });

    test('62 readings on Short Turbo, margin from its -7.5 dB limit', () {
      expect(d.samples, hasLength(62));
      expect(d.presetName, 'Short Turbo');
      expect(d.snrFloorDb, -7.5);
      expect(d.medianMarginDb, 6);
      expect(d.duration, const Duration(minutes: 108));
    });

    test('buckets 32 / 16 / 32 / 19 %', () {
      expect([for (final b in d.buckets) b.pct], [32, 16, 32, 19]);
      expect([for (final b in d.buckets) b.count], [20, 10, 20, 12]);
      expect([for (final b in d.buckets) b.band.label],
          ['Strong', 'Good', 'Weak', 'Below limit']);
    });

    test(
        'base heard: beacons + answered pings over expected, NAKs and '
        'throttled left out', () {
      expect(d.baseHeard, 62);
      expect(d.baseExpected, 127);
      expect(d.baseHeardPct, 49);
    });

    test('a single far reading is not the headline', () {
      expect(d.origin, ReportOrigin.base);
      // The lone 650 m fix has no second reading near it; the 400 m pair
      // (about 40 m apart) is the farthest that counts.
      expect(d.farthestM, closeTo(400, 2));
      final note = d.notes.whereType<SingleFarReadingNote>().single;
      expect(note.distanceM, closeTo(650, 2));
    });

    test('route length and 12 time bins', () {
      expect(d.routeM, greaterThan(1000));
      expect(d.marginOverTime, hasLength(12));
      expect(d.marginOverTime.whereType<double>(), isNotEmpty);
    });

    test('setup from the session and the base node', () {
      expect(d.setup.baseRadio, isNotEmpty);
      expect(d.setup.mobileRadio, isNotEmpty);
    });
  });

  test('a session filed on the wrong map shows no distance from the base',
      () async {
    final s = await seedSession32(db, mapBaseNorthM: 49700);
    final d = (await FieldReportLoader(db).session(s.sessionId))!;
    expect(d.origin, ReportOrigin.start);
    expect(d.farthestM, isNull);
    expect(d.notes.whereType<WrongMapNote>(), hasLength(1));
    // Everything else is still there.
    expect(d.samples, hasLength(62));
    expect(d.baseHeardPct, 49);
  });

  test('two readings within 50 m make a distance count', () {
    final s = testSession(1);
    List<PacketEvent> events(List<(double, double)> pos) => [
          for (var i = 0; i < pos.length; i++)
            testEvent(1, i, pos[i].$1, pos[i].$2, snr: 0),
        ];
    final lone = FieldReportData.build([
      SessionReportInput(
          session: s, events: events([(0, 100), (0, 110), (0, 900)]))
    ], base: (
      lat: baseLat,
      lon: baseLon
    ));
    expect(lone.farthestM, closeTo(110, 1));
    final pair = FieldReportData.build([
      SessionReportInput(
          session: s, events: events([(0, 100), (0, 880), (0, 900)]))
    ], base: (
      lat: baseLat,
      lon: baseLon
    ));
    expect(pair.farthestM, closeTo(900, 1));
    expect(pair.notes, isEmpty);
  });

  test('MeshCore margins use the ladder setting', () {
    final s = testSession(1, preset: 'MC_SF7_BW62.5_CR5', protocol: 'meshcore');
    final d = FieldReportData.build([
      SessionReportInput(session: s, events: [testEvent(1, 0, 0, 200, snr: 0)]),
    ], base: (
      lat: baseLat,
      lon: baseLon
    ));
    expect(d.snrFloorDb, -7.5);
    expect(d.samples.single.marginDb, 7.5);
  });

  group('comparison', () {
    FieldReportData side(int id, double far, double snr) =>
        FieldReportData.build([
          SessionReportInput(session: testSession(id), events: [
            testEvent(id, 0, 0, far - 20, snr: snr),
            testEvent(id, 1, 0, far, snr: snr),
          ]),
        ], base: (
          lat: baseLat,
          lon: baseLon
        ));

    List<ComparisonSideInput> inputs(List<(String, int, double, double)> s) => [
          for (final (name, id, far, snr) in s)
            ComparisonSideInput(name, [
              SessionReportInput(session: testSession(id), events: [
                testEvent(id, 0, 0, far - 20, snr: snr),
                testEvent(id, 1, 0, far, snr: snr),
              ]),
            ]),
        ];

    test('winner by distance, with how far and the margin', () {
      expect(side(1, 600, 0).farthestM, closeTo(600, 1));
      final c = ComparisonReportData.build(
          inputs([('Stock', 1, 600, 0), ('Whip', 2, 1500, 4)]),
          base: (lat: baseLat, lon: baseLon));
      expect(c.winner, 1);
      expect(c.winFartherM, closeTo(900, 2));
      expect(c.winMarginDb, closeTo(4, 0.01));
      expect(c.verdict, isNull);
    });

    test('a tie when within 50 m and 3 dB', () {
      final c = ComparisonReportData.build(
          inputs([('A', 1, 600, 0), ('B', 2, 620, 1), ('C', 3, 610, 2)]),
          base: (lat: baseLat, lon: baseLon));
      expect(c.winner, isNull);
      expect(c.sides, hasLength(3));
    });

    test('a guided test result supplies the winner and the verdict', () {
      const result = PlanAnalysisResult(
        headline: 'The stock antenna held the whole route.',
        fairness: '',
        variants: [],
        winner: 0,
        nextStep: '',
        thirdLabel: 'PINGS',
      );
      final c = ComparisonReportData.build(
          inputs([('Stock', 1, 600, 0), ('Whip', 2, 1500, 4)]),
          base: (lat: baseLat, lon: baseLon),
          result: result);
      expect(c.winner, 0);
      expect(c.verdict, result.headline);
    });
  });

  group('privacy transform', () {
    late FieldReportData d;
    setUp(() async {
      final s = await seedSession32(db);
      d = (await FieldReportLoader(db).session(s.sessionId))!;
    });

    for (final r in [120.0, 300.0]) {
      test('nothing drawn within $r m of the base', () {
        final route = PrivateRoute.of(d, hideRadiusM: r);
        expect(route.dots, isNotEmpty);
        for (final p in [...route.dots, for (final s in route.segments) ...s]) {
          expect(math.sqrt(p.x * p.x + p.y * p.y), greaterThanOrEqualTo(r));
        }
      });
    }

    test('Points only drops the line and keeps every dot', () {
      final both = PrivateRoute.of(d, hideRadiusM: 120);
      final points = PrivateRoute.of(d, hideRadiusM: 120, showPath: false);
      expect(both.segments, isNotEmpty);
      expect(points.segments, isEmpty);
      expect([for (final p in points.dots) (p.x, p.y)],
          [for (final p in both.dots) (p.x, p.y)]);
    });

    test('Off draws everything', () {
      final route = PrivateRoute.of(d, hideRadiusM: 0);
      expect(route.dots, hasLength(62));
    });

    test('rotation is fixed per session and keeps distances', () {
      expect(reportRotation(32), reportRotation(32));
      expect(reportRotation(32), isNot(reportRotation(33)));
      final a = PrivateRoute.of(d, hideRadiusM: 120);
      final b = PrivateRoute.of(d, hideRadiusM: 120);
      expect([for (final p in a.dots) (p.x, p.y)],
          [for (final p in b.dots) (p.x, p.y)]);
      // Turned, not just copied: positions differ from the unrotated ones.
      final kept = [
        for (final s in d.samples)
          if (s.distanceM >= 120) s
      ];
      expect(a.dots.first.x, isNot(closeTo(kept.first.x, 1)));
      for (var i = 0; i < kept.length; i++) {
        final p = a.dots[i];
        expect(
            math.sqrt(p.x * p.x + p.y * p.y), closeTo(kept[i].distanceM, 0.01));
      }
    });
  });
}
