// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesh_analyzer/services/terrain/coverage_calibrator.dart';
import 'package:mesh_analyzer/services/terrain/elevation_source.dart';
import 'package:mesh_analyzer/services/terrain/geo.dart';
import 'package:mesh_analyzer/services/terrain/path_loss_model.dart';
import 'package:mesh_analyzer/services/terrain/terrain_profile.dart';
import 'package:mesh_analyzer/services/terrain/terrain_service.dart';

/// Flat-earth-ish synthetic source: elevation from a function of the
/// distance (m) east of [origin] along a due-east path.
class FnSource implements ElevationSource {
  FnSource(this.origin, this.fn);
  final LatLng origin;
  final double Function(double eastM) fn;
  int calls = 0;
  @override
  String get name => 'fn';
  @override
  Future<List<double?>> elevations(List<LatLng> points) async {
    calls++;
    return [for (final p in points) fn(greatCircleDistanceM(origin, p))];
  }
}

class OfflineSource implements ElevationSource {
  @override
  String get name => 'offline';
  @override
  Future<List<double?>> elevations(List<LatLng> points) =>
      throw const ElevationUnavailable('offline');
}

LatLng east(LatLng o, double m) =>
    LatLng(o.latitude, o.longitude + m / (111194.9 * math.cos(o.latitude * math.pi / 180)));

void main() {
  const origin = LatLng(33.0, -116.0);

  test('Fresnel radius at midpoint of 1 km 915 MHz path', () {
    expect(fresnelRadiusM(500, 500, 915), closeTo(9.05, 0.05));
  });

  test('FSPL at 915 MHz / 1 km', () {
    expect(PathLossModel.freeSpaceLossDb(1000, 915), closeTo(91.67, 0.05));
  });

  test('knife-edge J(v) known values', () {
    expect(PathLossModel.knifeEdgeLossDb(0), closeTo(6.03, 0.1));
    expect(PathLossModel.knifeEdgeLossDb(1), closeTo(13.9, 0.1));
    expect(PathLossModel.knifeEdgeLossDb(-1), 0);
  });

  test('earth bulge at midpoint of 10 km, k=4/3', () {
    expect(earthBulgeM(5000, 5000), closeTo(1.47, 0.02));
  });

  test('great-circle interpolation endpoints and midpoint', () {
    final b = east(origin, 2000);
    final mid = greatCircleInterpolate(origin, b, 0.5);
    expect(greatCircleDistanceM(origin, mid), closeTo(1000, 1));
  });

  test('flat profile is clear', () async {
    final src = FnSource(origin, (_) => 100);
    final p = (await TerrainProfile.build(src, origin, east(origin, 2000),
        baseHeightM: 20, mobileHeightM: 20))!;
    expect(p.samples.length, greaterThan(60));
    expect(p.worstClearanceRatio, greaterThan(0.6));
    final pred = const PathLossModel().predict(profile: p);
    expect(pred.classification, PathClass.clear);
    expect(pred.diffractionDb, 0);
  });

  test('ridge produces obstruction and diffraction loss', () async {
    final src = FnSource(
        origin, (d) => 100 + 60 * math.exp(-math.pow((d - 1000) / 80, 2)));
    final p = (await TerrainProfile.build(src, origin, east(origin, 2000)))!;
    expect(p.worstClearanceRatio, lessThan(0));
    expect((p.dominantObstruction!.distanceM - 1000).abs(), lessThan(60));
    final pred = const PathLossModel().predict(profile: p);
    expect(pred.classification, PathClass.obstructed);
    expect(pred.diffractionDb, greaterThan(15));
    // More edges never reduce loss below the single principal edge.
    final one = const PathLossModel(maxEdges: 1).diffractionLossDb(p);
    expect(pred.diffractionDb, greaterThanOrEqualTo(one));
  });

  test('small bump gives partial Fresnel obstruction', () async {
    final src = FnSource(
        origin, (d) => 100 + 4 * math.exp(-math.pow((d - 1000) / 300, 2)));
    final p = (await TerrainProfile.build(src, origin, east(origin, 2000),
        baseHeightM: 5, mobileHeightM: 5))!;
    final c = PathLossModel.classify(p.worstClearanceRatio);
    expect(c, PathClass.partialFresnel);
  });

  test('sample count is capped', () {
    final pts = TerrainProfile.samplePoints(origin, east(origin, 50000));
    expect(pts.length, lessThanOrEqualTo(200));
  });

  test('calibrator recovers known offset and exponent', () {
    const truth = PathLossModel(exponent: 3.2, offsetDb: 14);
    final samples = [
      for (final d in <double>[50.0, 120, 300, 600, 1100, 2500, 4000])
        CalibrationSample(d, 0, truth.predict(distanceM: d).rssiDbm),
    ];
    final r = CoverageCalibrator.fit(const PathLossModel(), samples);
    expect(r.exponent, closeTo(3.2, 1e-6));
    expect(r.offsetDb, closeTo(14, 1e-6));
    expect(r.rmseDb, closeTo(0, 1e-6));
    expect(r.confidenceAt(1000), greaterThan(0.6));
  });

  test('calibrator bounds exponent and refits offset', () {
    // True exponent 5 is outside [2,4]: pinned to 4.
    const truth = PathLossModel(exponent: 5, offsetDb: 10);
    final samples = [
      for (final d in <double>[50.0, 200, 800, 3000])
        CalibrationSample(d, 0, truth.predict(distanceM: d).rssiDbm),
    ];
    final r = CoverageCalibrator.fit(const PathLossModel(), samples);
    expect(r.exponent, 4.0);
    expect(r.rmseDb, greaterThan(0));
  });

  test('calibrator offset-only when exponent fixed', () {
    const truth = PathLossModel(exponent: 2.7, offsetDb: 9);
    final samples = [
      for (final d in <double>[100.0, 500, 1500])
        CalibrationSample(d, 3, truth.predict(distanceM: d).rssiDbm - 3),
    ];
    final r = CoverageCalibrator.fit(const PathLossModel(), samples,
        fitExponent: false);
    expect(r.exponent, 2.7);
    expect(r.offsetDb, closeTo(9, 1e-6));
  });

  test('calibrate + predict through a source', () async {
    final src = FnSource(origin, (_) => 100);
    const truth = PathLossModel(exponent: 3.0, offsetDb: 12);
    final cal = CoverageCalibrator(
        base: origin, source: src, baseHeightM: 30, mobileHeightM: 30);
    final measured = [
      for (final d in <double>[100.0, 400, 900, 1600])
        MeasuredPoint(east(origin, d).latitude, east(origin, d).longitude,
            truth.predict(distanceM: d).rssiDbm),
    ];
    final r = await cal.calibrate(measured);
    expect(r.exponent, closeTo(3.0, 0.05));
    final t = east(origin, 700);
    final est = await cal.predict(t.latitude, t.longitude);
    expect(est.rssiDbm,
        closeTo(truth.predict(distanceM: greatCircleDistanceM(origin, t)).rssiDbm, 0.5));
  });

  group('TerrainService', () {
    test('offline degrades to distance-only', () async {
      final svc = TerrainService(OfflineSource());
      final res = await svc.predictGrid(
          base: origin, points: [east(origin, 500), east(origin, 1500)]);
      expect(res.terrainUnavailable, isTrue);
      expect(res.points.length, 2);
      expect(res.points[0].rssiDbm, greaterThan(res.points[1].rssiDbm));
      expect(res.points[0].diffractionDb, 0);
    });

    test('online prediction with ridge, progress and measured', () async {
      final src = FnSource(
          origin, (d) => 100 + 60 * math.exp(-math.pow((d - 1000) / 80, 2)));
      final progress = <double>[];
      final res = await TerrainService(src).predictGrid(
        base: origin,
        points: [east(origin, 500), east(origin, 2000)],
        measured: [
          MeasuredPoint(east(origin, 300).latitude, east(origin, 300).longitude, -80),
          MeasuredPoint(east(origin, 600).latitude, east(origin, 600).longitude, -90),
          MeasuredPoint(east(origin, 450).latitude, east(origin, 450).longitude, -86),
        ],
        baseHeightM: 20,
        mobileHeightM: 20,
        onProgress: progress.add,
      );
      expect(res.terrainUnavailable, isFalse);
      expect(res.calibration, isNotNull);
      expect(res.points[1].classification, PathClass.obstructed);
      expect(res.points[0].classification, PathClass.clear);
      expect(progress.last, 1);
    });

    test('cancellation', () async {
      final token = TerrainCancelToken()..cancel();
      expect(
        TerrainService(FnSource(origin, (_) => 0)).predictGrid(
            base: origin, points: [east(origin, 500)], cancel: token),
        throwsA(isA<TerrainCancelled>()),
      );
    });
  });
}
