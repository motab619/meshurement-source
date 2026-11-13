// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesh_analyzer/demo/demo_mode.dart';
import 'package:mesh_analyzer/demo/demo_profile.dart';
import 'package:mesh_analyzer/demo/grid_elevation.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/services/coverage_interpolation.dart';
import 'package:mesh_analyzer/services/terrain/elevation_source.dart';
import 'package:mesh_analyzer/services/terrain/geo.dart';
import 'package:mesh_analyzer/services/terrain/los_verdict.dart';
import 'package:mesh_analyzer/services/terrain/terrain_coverage.dart';
import 'package:mesh_analyzer/services/terrain/terrain_profile.dart';
import 'package:mesh_analyzer/services/terrain/terrain_service.dart';
import 'package:mesh_analyzer/services/terrain/terrain_settings.dart';
import 'package:mesh_analyzer/ui/widgets/terrain_profile_chart.dart';
import 'package:mesh_analyzer/ui/widgets/terrain_profile_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const base = LatLng(33.0, -116.0);

LatLng east(double m) => LatLng(
    base.latitude,
    base.longitude +
        m / (111194.9 * math.cos(base.latitude * math.pi / 180)));

/// Profile base -> [lengthM] east; ground height from [ground] (distance m).
TerrainProfile profile(
  double lengthM,
  double Function(double d) ground, {
  double baseH = 2,
  double mobH = 1.5,
}) {
  final pts = TerrainProfile.samplePoints(base, east(lengthM));
  return TerrainProfile.fromElevations(
    points: pts,
    elevations: [for (final p in pts) ground(greatCircleDistanceM(base, p))],
    baseHeightM: baseH,
    mobileHeightM: mobH,
  )!;
}

double bump(double d, double center, double height, double width) =>
    height * math.exp(-math.pow((d - center) / width, 2));

class FnSource implements ElevationSource {
  FnSource(this.fn);
  final double Function(LatLng) fn;
  int points = 0;
  @override
  String get name => 'fn';
  @override
  Future<List<double?>> elevations(List<LatLng> p) async {
    points += p.length;
    return [for (final x in p) fn(x)];
  }
}

class Offline implements ElevationSource {
  @override
  String get name => 'offline';
  @override
  Future<List<double?>> elevations(List<LatLng> p) =>
      throw const ElevationUnavailable('offline');
}

void main() {
  group('verdict rules', () {
    test('flat 1 km path is clear despite low antennas (ratio < 0.6)', () {
      final p = profile(1000, (_) => 100);
      expect(p.worstClearanceRatio, lessThan(0.6)); // raw engine says partial
      final v = LosVerdictRules.evaluate(p);
      expect(v.kind, LosKind.clear);
      expect(v.text, 'Clear line of sight');
    });

    test('tall ridge blocks, names distance and ridge elevation', () {
      final p = profile(1000, (d) => 100 + bump(d, 400, 30, 60));
      final v = LosVerdictRules.evaluate(p);
      expect(v.kind, LosKind.blocked);
      expect(v.text, startsWith('Blocked by terrain at '));
      expect(v.text, contains('(ridge 129 m)'));
    });

    test('terrain intruding on the Fresnel zone only is partly blocked', () {
      // 10 m antennas; a 6 m rise leaves ~4 m of ~9 m F1 radius.
      final p = profile(1000, (d) => 100 + bump(d, 500, 6, 80),
          baseH: 10, mobH: 10);
      final v = LosVerdictRules.evaluate(p);
      expect(v.kind, LosKind.partial);
      expect(v.text, 'Partly blocked (Fresnel zone) — expect weaker signal');
    });

    test('slope with no rise above the end-to-end line is clear', () {
      final p = profile(1000, (d) => 100 + d * 0.02);
      expect(LosVerdictRules.evaluate(p).kind, LosKind.clear);
    });

    test('very long flat path is blocked by earth curvature, not terrain', () {
      final p = profile(40000, (_) => 50);
      final v = LosVerdictRules.evaluate(p);
      expect(v.kind, LosKind.blocked);
      expect(v.text, contains('earth'));
    });

    test('too few samples is clear', () {
      final p = profile(10, (_) => 5);
      expect(LosVerdictRules.evaluate(p).kind, LosKind.clear);
    });
  });

  group('settings', () {
    test('defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = TerrainSettings.load(prefs);
      expect(s.baseHeightM, 2.0);
      expect(s.mobileHeightM, 1.5);
    });

    test('saved values persist and clamp to 0.5-50 m', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await TerrainSettings.saveBaseHeight(prefs, 12.5);
      await TerrainSettings.saveMobileHeight(prefs, 500);
      final s = TerrainSettings.load(prefs);
      expect(s.baseHeightM, 12.5);
      expect(s.mobileHeightM, 50);
      await TerrainSettings.saveMobileHeight(prefs, 0.1);
      expect(TerrainSettings.load(prefs).mobileHeightM, 0.5);
    });

    test('frequency from region', () {
      expect(
          MeshtasticRadio.frequencyForRegion(
              pb.Config_LoRaConfig_RegionCode.US),
          915);
      expect(
          MeshtasticRadio.frequencyForRegion(
              pb.Config_LoRaConfig_RegionCode.EU_868),
          868);
      expect(
          MeshtasticRadio.frequencyForRegion(
              pb.Config_LoRaConfig_RegionCode.ANZ),
          915);
      expect(
          MeshtasticRadio.frequencyForRegion(
              pb.Config_LoRaConfig_RegionCode.UNSET),
          915);
      expect(MeshtasticRadio.frequencyForRegion(null), 915);
    });

    test('user-placed base is stored per map', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(TerrainSettings.loadUserBase(prefs, 1), isNull);
      await TerrainSettings.saveUserBase(prefs, 1, const LatLng(33.5, -116.25));
      expect(TerrainSettings.loadUserBase(prefs, 1)!.latitude, 33.5);
      expect(TerrainSettings.loadUserBase(prefs, 2), isNull);
      await TerrainSettings.saveUserBase(prefs, 1, null);
      expect(TerrainSettings.loadUserBase(prefs, 1), isNull);
    });
  });

  group('profile painter', () {
    void paintIt(TerrainProfile? p) {
      final rec = ui.PictureRecorder();
      final canvas = ui.Canvas(rec);
      for (final c in [ProfileChartColors.dark, ProfileChartColors.light]) {
        TerrainProfilePainter(profile: p, colors: c)
            .paint(canvas, const ui.Size(360, 190));
      }
      TerrainProfilePainter(profile: p, colors: ProfileChartColors.dark)
          .paint(canvas, const ui.Size(10, 5)); // tiny canvas
      rec.endRecording();
    }

    test('normal profile', () => paintIt(profile(1000, (d) => bump(d, 500, 20, 90))));
    test('null profile (no data)', () => paintIt(null));

    test('all-null elevations produce no profile and paint empty', () {
      final pts = TerrainProfile.samplePoints(base, east(500));
      final p = TerrainProfile.fromElevations(
          points: pts, elevations: List<double?>.filled(pts.length, null));
      expect(p, isNull);
      paintIt(p);
    });

    test('two coincident points (zero length)', () {
      final p = TerrainProfile.fromElevations(
          points: [base, base], elevations: [10, 10])!;
      expect(p.distanceM, 0);
      paintIt(p);
    });

    test('very short path and constant ground', () {
      paintIt(profile(5, (_) => 0));
    });
  });

  group('nearest reading', () {
    test('within 50 m only, closest wins, needs a value', () {
      final t = east(1000);
      final near = ProfileReading(east(1030), rssi: -104);
      final nearer = ProfileReading(east(1010), rssi: -99);
      final empty = ProfileReading(east(1001));
      final far = ProfileReading(east(1100), rssi: -90);
      expect(nearestReading(t, [far, near, empty, nearer])!.rssi, -99);
      expect(nearestReading(t, [far, empty]), isNull);
    });
  });

  group('terrain-aware overlay pipeline', () {
    // Measurements walking east/north-east of the base, RSSI from a simple
    // log-distance law.
    ({List<double> lats, List<double> lons, List<double> rssi}) walk() {
      final lats = <double>[], lons = <double>[], rssi = <double>[];
      for (var d = 60.0; d <= 900; d += 20) {
        final p = east(d);
        lats.add(p.latitude + d * 1e-6);
        lons.add(p.longitude);
        rssi.add(-60 - 27 * math.log(d / 60) / math.ln10);
      }
      return (lats: lats, lons: lons, rssi: rssi);
    }

    test('produces a calibrated RSSI grid on the interpolation footprint',
        () async {
      final src = FnSource((p) => 100 + 5 * math.sin(p.longitude * 4000));
      final w = walk();
      final progress = <double>[];
      final r = await terrainCoverage(
        service: TerrainService(src),
        base: base,
        lats: w.lats,
        lons: w.lons,
        rssi: w.rssi,
        frequencyMHz: 915,
        baseHeightM: 2,
        mobileHeightM: 1.5,
        onProgress: progress.add,
      );
      expect(r, isNotNull);
      expect(r!.terrainUnavailable, isFalse);
      expect(r.rmseDb, isNotNull);
      expect(r.calibrationSamples, greaterThan(3));
      expect(src.points, greaterThan(0));
      expect(src.points, lessThanOrEqualTo(TerrainBudget.maxElevationPoints));
      expect(progress.last, 1);
      final g = r.grid;
      var shown = 0;
      for (var i = 0; i < g.alpha.length; i++) {
        if (g.alpha[i] > 0) {
          shown++;
          expect(g.values[i], inInclusiveRange(-160, 0));
        }
      }
      expect(shown, greaterThan(5));
      expect(g.cellMeters, greaterThanOrEqualTo(TerrainBudget.targetCellM));
    });

    test('a hill between base and the far points lowers the estimate',
        () async {
      final w = walk();
      Future<TerrainCoverage?> run(double Function(LatLng) fn) =>
          terrainCoverage(
            service: TerrainService(FnSource(fn)),
            base: base,
            lats: w.lats,
            lons: w.lons,
            rssi: w.rssi,
            frequencyMHz: 915,
            baseHeightM: 2,
            mobileHeightM: 1.5,
          );
      final flat = await run((_) => 100);
      // Ridge 300 m east of the base, uncalibratable from the walk alone but
      // present in the fitted diffraction.
      final hilly = await run((p) =>
          100 + bump(greatCircleDistanceM(base, p), 300, 40, 40));
      expect(flat, isNotNull);
      expect(hilly, isNotNull);
      expect(hilly!.rmseDb, isNotNull);
    });

    test('offline falls back to the distance-only model, flagged', () async {
      final w = walk();
      final r = await terrainCoverage(
        service: TerrainService(Offline()),
        base: base,
        lats: w.lats,
        lons: w.lons,
        rssi: w.rssi,
        frequencyMHz: 915,
        baseHeightM: 2,
        mobileHeightM: 1.5,
      );
      expect(r, isNotNull);
      expect(r!.terrainUnavailable, isTrue);
      expect(r.grid.alpha.any((a) => a > 0), isTrue);
    });

    test('cancel stops the run', () async {
      final w = walk();
      final token = TerrainCancelToken()..cancel();
      expect(
        terrainCoverage(
          service: TerrainService(FnSource((_) => 0)),
          base: base,
          lats: w.lats,
          lons: w.lons,
          rssi: w.rssi,
          frequencyMHz: 915,
          baseHeightM: 2,
          mobileHeightM: 1.5,
          cancel: token,
        ),
        throwsA(isA<TerrainCancelled>()),
      );
    });

    test('no measurements gives null', () async {
      final r = await terrainCoverage(
        service: TerrainService(FnSource((_) => 0)),
        base: base,
        lats: const [],
        lons: const [],
        rssi: const [],
        frequencyMHz: 915,
        baseHeightM: 2,
        mobileHeightM: 1.5,
      );
      expect(r, isNull);
    });

    test('large areas are coarsened to fit the request budget', () {
      // A 6 km x 6 km area of measurements.
      final lats = <double>[], lons = <double>[], v = <double>[];
      for (var i = 0; i < 40; i++) {
        lats.add(base.latitude + i * 0.0015);
        lons.add(base.longitude + i * 0.0015);
        v.add(-100);
      }
      final idw = interpolateCoverage(lats, lons, v)!;
      final plan = planTerrainGrid(idw, base);
      expect(plan.cellMeters, greaterThan(TerrainBudget.targetCellM));
      expect(plan.estimatedPoints,
          lessThanOrEqualTo(TerrainBudget.maxElevationPoints));
      expect(plan.centers, isNotEmpty);
      // 100 points per request, well under the ~200-request session budget.
      expect(plan.estimatedPoints / 100, lessThan(200));
    });

    test('calibration points are binned and capped', () {
      final lats = [for (var i = 0; i < 500; i++) 33 + i * 0.0003];
      final lons = List<double>.filled(500, -116);
      final v = List<double>.filled(500, -90);
      final pts = calibrationPoints(lats, lons, v);
      expect(pts.length, lessThanOrEqualTo(TerrainBudget.maxCalibrationPoints));
      expect(pts, isNotEmpty);
    });
  });

  group('demo terrain', () {
    tearDown(() => DemoMode.site = 'cove');

    test('polo: target is ~1 km from the base and the profile has a hill',
        () async {
      DemoMode.site = 'polo';
      final target = demoProfileTarget();
      final d = greatCircleDistanceM(demoBase, target);
      expect(d, inInclusiveRange(700, 1300));
      final p = await TerrainProfile.build(
          demoElevationSource(), demoBase, target);
      expect(p, isNotNull);
      expect(LosVerdictRules.evaluate(p!).kind, isNot(LosKind.clear));
    });

    test('cove: real terrain, the profile target is behind the east ridge',
        () async {
      DemoMode.site = 'cove';
      final src = demoElevationSource() as GridElevationSource;
      // Base at the trailhead (~90 m), the Cove floor lower to the north,
      // the ridge east of the Cove well above both.
      expect(src.elevationAt(demoBase), inInclusiveRange(70, 110));
      expect(src.elevationAt(const LatLng(33.6700, -116.3080)),
          inInclusiveRange(0, 40));
      final target = demoProfileTarget();
      final d = greatCircleDistanceM(demoBase, target);
      expect(d, inInclusiveRange(2500, 4000));
      final p = await TerrainProfile.build(src, demoBase, target);
      expect(p, isNotNull);
      expect(LosVerdictRules.evaluate(p!).kind, isNot(LosKind.clear));
    });
  });
}
