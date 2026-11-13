// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/services/coverage_interpolation.dart';

const _start = InterpolationParams.fadeStart;
const _end = InterpolationParams.fadeEnd;

// Offset a few metres so points don't sit exactly on a cell boundary.
const _lat = 33.68007;
const _lon = -116.24006;

/// Longitude [m] metres east of [_lon].
double _east(double m) => _lon + m / metersPerDegree(_lat).$2;

void main() {
  test('empty input yields no grid', () {
    expect(interpolateCoverage([], [], []), isNull);
  });

  test('single point: exact value in its cell, fades out by fadeEnd', () {
    final g = interpolateCoverage([_lat], [_lon], [7.5])!;
    final idx = g.cellAt(_lat, _lon);
    expect(g.values[idx], closeTo(7.5, 1e-5));
    expect(g.alpha[idx], 1);
    // Every estimated cell carries the only value.
    for (var i = 0; i < g.values.length; i++) {
      if (g.alpha[i] > 0) expect(g.values[i], closeTo(7.5, 1e-5));
    }
  });

  test('measured point cell shows its exact value even among neighbours', () {
    final lats = [_lat, _lat];
    final lons = [_lon, _east(400)];
    final g = interpolateCoverage(lats, lons, [-10, 8])!;
    expect(g.values[g.cellAt(_lat, lons[0])], closeTo(-10, 1e-5));
    expect(g.values[g.cellAt(_lat, lons[1])], closeTo(8, 1e-5));
  });

  test('midpoint between two points is about the mean', () {
    final g = interpolateCoverage([_lat, _lat], [_lon, _east(400)], [0, 10])!;
    final mid = g.cellAt(_lat, _east(200));
    expect(g.alpha[mid], greaterThan(0));
    expect(g.values[mid], closeTo(5, 1.5));
    // Symmetric: cells mirrored around the midpoint sum to ~10.
    final a = g.values[g.cellAt(_lat, _east(100))];
    final b = g.values[g.cellAt(_lat, _east(300))];
    expect(a + b, closeTo(10, 1.5));
    expect(a, lessThan(b == a ? 99 : b));
  });

  test('fades with distance and is omitted beyond fadeEnd', () {
    final g = interpolateCoverage([_lat], [_lon], [0])!;
    double alphaAt(double m) {
      final i = g.cellAt(_lat, _east(m));
      return i < 0 ? 0 : g.alpha[i]; // outside the grid = no estimate
    }

    const mid = (_start + _end) / 2;
    expect(alphaAt(0), 1);
    expect(alphaAt(_start * 0.8), greaterThan(0.9));
    expect(alphaAt(mid), inExclusiveRange(0.2, 0.8));
    expect(alphaAt(mid), greaterThan(alphaAt(_end - 100)));
    expect(alphaAt(_end - 100), greaterThan(0));
    expect(alphaAt(_end + 30), 0);
    expect(alphaAt(-_end - 30), 0);
  });

  test('grid covers the points plus a margin', () {
    final g = interpolateCoverage([_lat], [_lon], [0])!;
    expect(g.south, lessThan(_lat));
    expect(g.north, greaterThan(_lat));
    expect(g.west, lessThan(_lon));
    expect(g.east, greaterThan(_lon));
    final (mLat, _) = metersPerDegree(_lat);
    expect((g.north - g.south) * mLat, greaterThan(2 * _end - 1));
  });

  test('1000 points finish quickly', () {
    final rnd = math.Random(1);
    final lats = <double>[], lons = <double>[], vals = <double>[];
    var x = 0.0, y = 0.0;
    for (var i = 0; i < 1000; i++) {
      x += rnd.nextDouble() * 6 - 2; // random walk, ~2 km span
      y += rnd.nextDouble() * 6 - 2;
      lats.add(_lat + y / 111000);
      lons.add(_east(x));
      vals.add(rnd.nextDouble() * 30 - 20);
    }
    final sw = Stopwatch()..start();
    final g = interpolateCoverage(lats, lons, vals)!;
    sw.stop();
    // ignore: avoid_print
    print(
        '1000 points: ${g.cols}x${g.rows} cells in ${sw.elapsedMilliseconds} ms');
    expect(sw.elapsedMilliseconds, lessThan(3000));
    expect(g.alpha.any((a) => a > 0), isTrue);
  });

  test('1000 points scattered over 5 km finish quickly', () {
    final rnd = math.Random(2);
    final lats = [
      for (var i = 0; i < 1000; i++) _lat + rnd.nextDouble() * 0.045
    ];
    final lons = [
      for (var i = 0; i < 1000; i++) _east(rnd.nextDouble() * 5000)
    ];
    final vals = [for (var i = 0; i < 1000; i++) rnd.nextDouble() * 30 - 20];
    final sw = Stopwatch()..start();
    final g = interpolateCoverage(lats, lons, vals)!;
    sw.stop();
    // ignore: avoid_print
    print('scattered: ${g.cols}x${g.rows} in ${sw.elapsedMilliseconds} ms');
    expect(sw.elapsedMilliseconds, lessThan(3000));
  });

  test('async variant matches sync', () async {
    final g = await interpolateCoverageAsync([_lat], [_lon], [3]);
    expect(g, isNotNull);
    expect(g!.values[g.cellAt(_lat, _lon)], closeTo(3, 1e-5));
  });
}
