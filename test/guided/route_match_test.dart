// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mesh_analyzer/services/guided/route_match.dart';

const _origin = LatLng(33.68, -116.24);

/// [eastM] metres east and [northM] north of the origin.
LatLng at(double eastM, [double northM = 0]) => LatLng(
      _origin.latitude + northM / 111320,
      _origin.longitude +
          eastM / (111320 * math.cos(_origin.latitude * math.pi / 180)),
    );

void main() {
  test('flat distance and bearing', () {
    expect(flatDistanceM(_origin, at(100)), closeTo(100, 0.5));
    expect(flatDistanceM(_origin, at(0, 100)), closeTo(100, 0.5));
    expect(flatDistanceM(_origin, at(300, 400)), closeTo(500, 1));
    expect(bearingDeg(_origin, at(0, 100)), closeTo(0, 0.1)); // north
    expect(bearingDeg(_origin, at(100)), closeTo(90, 0.1)); // east
    expect(bearingDeg(_origin, at(0, -100)), closeTo(180, 0.1));
    expect(bearingDeg(_origin, at(-100)), closeTo(270, 0.1));
  });

  group('resampleRoute', () {
    test('empty and single', () {
      expect(resampleRoute(const []), isEmpty);
      expect(resampleRoute([_origin]), [_origin]);
    });

    test('one point every 10 m along a straight line', () {
      final route = resampleRoute([_origin, at(100)]);
      expect(route.length, 11);
      for (var i = 0; i < route.length; i++) {
        expect(flatDistanceM(_origin, route[i]), closeTo(10.0 * i, 0.2));
      }
    });

    test('carries distance across short segments', () {
      // 25 segments of 4 m = 100 m.
      final track = [for (var i = 0; i <= 25; i++) at(4.0 * i)];
      final route = resampleRoute(track);
      expect(route.length, 11);
      expect(flatDistanceM(route[0], route[1]), closeTo(10, 0.2));
      expect(flatDistanceM(route[9], route[10]), closeTo(10, 0.2));
    });

    test('a corner is followed, not cut', () {
      final route = resampleRoute([_origin, at(50), at(50, 50)]);
      // 100 m walked → 11 points; the sixth is at the corner.
      expect(route.length, 11);
      expect(flatDistanceM(route[5], at(50)), lessThan(0.3));
      expect(flatDistanceM(route.last, at(50, 50)), lessThan(0.3));
    });
  });

  group('routeMatchPct', () {
    final ghost = resampleRoute([_origin, at(200)]); // 21 points

    test('null without a ghost route', () {
      expect(routeMatchPct(const [], [_origin]), isNull);
      expect(RouteMatcher(const []).pct, isNull);
    });

    test('nothing walked yet is 0 %', () {
      expect(routeMatchPct(ghost, const []), 0);
    });

    test('the same route is 100 %', () {
      expect(routeMatchPct(ghost, [_origin, at(50), at(100), at(150), at(200)]),
          100);
    });

    test('half the route walked is about half', () {
      // Ghost points 0..100 m plus 110 and 120 m (within 25 m of 100 m).
      final pct = routeMatchPct(ghost, [_origin, at(50), at(100)])!;
      expect(pct, closeTo(100 * 13 / 21, 0.1));
    });

    test('a parallel path 30 m off matches nothing, 20 m off everything',
        () {
      expect(routeMatchPct(ghost, [at(0, 30), at(100, 30), at(200, 30)]), 0);
      expect(
          routeMatchPct(ghost, [
            for (var m = 0.0; m <= 200; m += 10) at(m, 20),
          ]),
          100);
    });

    test('incremental matcher agrees and never double counts', () {
      final m = RouteMatcher(ghost);
      m.addPoint(_origin);
      expect(m.hits, 3); // 0, 10, 20 m within 25 m
      m.addPoint(_origin);
      expect(m.hits, 3);
      m.addPoint(at(200));
      expect(m.hits, 6);
      expect(m.pct, closeTo(100 * 6 / 21, 0.1));
      expect(m.pct, routeMatchPct(ghost, [_origin, _origin, at(200)]));
    });

    test('80 % lights "Done walking"', () {
      expect(routeMatchDonePct, 80);
    });
  });

  group('TrackBuilder', () {
    test('keeps a point only when it moved 3 m', () {
      final t = TrackBuilder();
      expect(t.add(_origin), isTrue);
      expect(t.add(at(1)), isFalse);
      expect(t.add(at(2.9)), isFalse);
      expect(t.add(at(3.1)), isTrue);
      expect(t.points.length, 2);
    });
  });

  test('route JSON round trip at 1 m precision', () {
    final route = [_origin, at(123.4, 56.7)];
    final back = routeFromJson(routeToJson(route));
    expect(back.length, 2);
    expect(flatDistanceM(back[1], route[1]), lessThan(1.5));
    expect(routeFromJson('nonsense'), isEmpty);
    expect(routeFromJson([1, 2]), isEmpty);
  });
}
