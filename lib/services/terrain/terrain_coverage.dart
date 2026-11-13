// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import '../coverage_interpolation.dart';
import 'coverage_calibrator.dart';
import 'geo.dart';
import 'terrain_profile.dart';
import 'terrain_service.dart';

/// A terrain-aware estimate ready to rasterise (RSSI in dBm per cell).
class TerrainCoverage {
  const TerrainCoverage({
    required this.grid,
    required this.rmseDb,
    required this.calibrationSamples,
    required this.terrainUnavailable,
    required this.unavailableReason,
    required this.elevationPoints,
  });

  /// Same type as the interpolated overlay, so the same raster / colour
  /// scale code draws it.
  final CoverageGrid grid;

  /// Calibration fit error (dB); null if nothing was calibrated.
  final double? rmseDb;
  final int calibrationSamples;

  /// Elevations could not be fetched: values are the distance-only model.
  final bool terrainUnavailable;
  final String? unavailableReason;

  /// Upper bound on distinct elevation points requested (before caching).
  final int elevationPoints;
}

/// Budget for the terrain-aware estimate. Open Topo Data takes 100 points
/// per request and 1000 requests/day. The planner coarsens the grid until
/// the (un-deduped, un-cached) point count fits [maxElevationPoints]:
/// 12 000 points = at most 120 requests, i.e. well under the ~200 allowed
/// for one session area, ~2 minutes at 1 request/s. Dedupe of the shared
/// radial paths and the disk cache usually make it much cheaper.
class TerrainBudget {
  TerrainBudget._();

  static const double targetCellM = 100;
  static const int maxElevationPoints = 12000;

  /// Measured points used to calibrate (after binning to ~100 m cells).
  static const int maxCalibrationPoints = 50;
}

/// Coarse prediction cells chosen from an interpolation grid.
class TerrainGridPlan {
  const TerrainGridPlan({
    required this.cols,
    required this.rows,
    required this.cellMeters,
    required this.centers,
    required this.cellIndex,
    required this.alpha,
    required this.estimatedPoints,
  });

  final int cols, rows;
  final double cellMeters;

  /// Centres of the cells to predict (only cells the interpolation shows).
  final List<LatLng> centers;

  /// `row * cols + col` for each entry of [centers].
  final List<int> cellIndex;

  /// Interpolation fade alpha for each entry of [centers].
  final List<double> alpha;

  /// Elevation points the grid cells need (path length / 30 m summed).
  final int estimatedPoints;
}

/// Picks a coarse grid over the same footprint as [idw]: only cells where
/// the interpolation overlay has alpha > 0 (so, within [InterpolationParams.fadeEnd]
/// of a measurement). The cell size starts at [TerrainBudget.targetCellM] and
/// grows until the elevation points for these cells plus [reservedPoints]
/// (calibration paths) fit [maxPoints].
TerrainGridPlan planTerrainGrid(
  CoverageGrid idw,
  LatLng base, {
  double targetCellM = TerrainBudget.targetCellM,
  int maxPoints = TerrainBudget.maxElevationPoints,
  int reservedPoints = 0,
}) {
  final midLat = (idw.south + idw.north) / 2;
  final (mLat, mLon) = metersPerDegree(midLat);
  final widthM = (idw.east - idw.west) * mLon;
  final heightM = (idw.north - idw.south) * mLat;

  var cell = targetCellM;
  for (var attempt = 0;; attempt++) {
    final cols = math.max(1, (widthM / cell).ceil());
    final rows = math.max(1, (heightM / cell).ceil());
    final dLat = (idw.north - idw.south) / rows;
    final dLon = (idw.east - idw.west) / cols;
    final centers = <LatLng>[];
    final index = <int>[];
    final alpha = <double>[];
    var points = reservedPoints;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final lat = idw.south + (r + 0.5) * dLat;
        final lon = idw.west + (c + 0.5) * dLon;
        final i = idw.cellAt(lat, lon);
        if (i < 0 || idw.alpha[i] <= 0) continue;
        final p = LatLng(lat, lon);
        centers.add(p);
        index.add(r * cols + c);
        alpha.add(idw.alpha[i].toDouble());
        points += greatCircleDistanceM(base, p) ~/ TerrainProfile.targetSpacingM +
            1;
      }
    }
    if (points <= maxPoints || attempt >= 40) {
      return TerrainGridPlan(
        cols: cols,
        rows: rows,
        cellMeters: cell,
        centers: centers,
        cellIndex: index,
        alpha: alpha,
        estimatedPoints: points,
      );
    }
    cell *= 1.25;
  }
}

/// Bins measurements into ~[binM] cells (mean RSSI each) and, if more than
/// [maxCount] remain, keeps an even spread of them.
List<MeasuredPoint> calibrationPoints(
  List<double> lats,
  List<double> lons,
  List<double> rssi, {
  double binM = 100,
  int maxCount = TerrainBudget.maxCalibrationPoints,
}) {
  if (lats.isEmpty) return const [];
  final (mLat, mLon) = metersPerDegree(lats.first);
  final sumLat = <(int, int), double>{};
  final sumLon = <(int, int), double>{};
  final sumV = <(int, int), double>{};
  final count = <(int, int), int>{};
  for (var i = 0; i < lats.length; i++) {
    final k = ((lats[i] * mLat / binM).floor(), (lons[i] * mLon / binM).floor());
    sumLat[k] = (sumLat[k] ?? 0) + lats[i];
    sumLon[k] = (sumLon[k] ?? 0) + lons[i];
    sumV[k] = (sumV[k] ?? 0) + rssi[i];
    count[k] = (count[k] ?? 0) + 1;
  }
  var out = [
    for (final k in count.keys)
      MeasuredPoint(sumLat[k]! / count[k]!, sumLon[k]! / count[k]!,
          sumV[k]! / count[k]!),
  ];
  if (out.length > maxCount) {
    final step = out.length / maxCount;
    out = [for (var i = 0; i < maxCount; i++) out[(i * step).floor()]];
  }
  return out;
}

/// Terrain-aware coverage estimate (the "Terrain-aware" option of the
/// Estimated layer).
///
/// 1. IDW-interpolate [rssi] to find where the Estimated overlay would draw
///    (cells within ~300 m of a measurement).
/// 2. Cover those cells with a coarser grid (~100 m, widened to fit the
///    request budget) and predict each cell with
///    [TerrainService.predictGrid], calibrated on a binned subset of the
///    measurements.
/// 3. The result reuses the interpolation fade alpha, so the footprint and
///    edge fade match the plain estimate and the same RSSI colour scale
///    applies.
///
/// Returns null if there are no measurements. Throws [TerrainCancelled] if
/// [cancel] fires. If elevations are unavailable the result is the
/// calibrated distance-only model, flagged `terrainUnavailable`.
Future<TerrainCoverage?> terrainCoverage({
  required TerrainService service,
  required LatLng base,
  required List<double> lats,
  required List<double> lons,
  required List<double> rssi,
  required double frequencyMHz,
  required double baseHeightM,
  required double mobileHeightM,
  void Function(double progress)? onProgress,
  TerrainCancelToken? cancel,
}) async {
  if (lats.isEmpty) return null;
  final idw = await interpolateCoverageAsync(lats, lons, rssi);
  if (idw == null) return null;
  final measured = calibrationPoints(lats, lons, rssi);
  var reserved = 0;
  for (final m in measured) {
    reserved += greatCircleDistanceM(base, m.point) ~/
            TerrainProfile.targetSpacingM +
        1;
  }
  final plan = planTerrainGrid(idw, base, reservedPoints: reserved);
  final result = await service.predictGrid(
    base: base,
    points: plan.centers,
    frequencyMHz: frequencyMHz,
    baseHeightM: baseHeightM,
    mobileHeightM: mobileHeightM,
    measured: measured,
    onProgress: onProgress,
    cancel: cancel,
  );
  final values = Float32List(plan.cols * plan.rows);
  final alpha = Float32List(plan.cols * plan.rows);
  for (var i = 0; i < plan.centers.length; i++) {
    values[plan.cellIndex[i]] = result.points[i].rssiDbm;
    alpha[plan.cellIndex[i]] = plan.alpha[i];
  }
  return TerrainCoverage(
    grid: CoverageGrid(
      south: idw.south,
      west: idw.west,
      north: idw.north,
      east: idw.east,
      cols: plan.cols,
      rows: plan.rows,
      cellMeters: plan.cellMeters,
      values: values,
      alpha: alpha,
    ),
    rmseDb: result.calibration?.rmseDb,
    calibrationSamples: result.calibration?.sampleCount ?? 0,
    terrainUnavailable: result.terrainUnavailable,
    unavailableReason: result.unavailableReason,
    elevationPoints: plan.estimatedPoints,
  );
}
