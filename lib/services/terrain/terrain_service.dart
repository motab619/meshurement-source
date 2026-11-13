// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:latlong2/latlong.dart';

import 'coverage_calibrator.dart';
import 'elevation_source.dart';
import 'geo.dart';
import 'path_loss_model.dart';
import 'terrain_profile.dart';

/// Cooperative cancellation for [TerrainService.predictGrid].
class TerrainCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Thrown by [TerrainService.predictGrid] when its token is cancelled.
class TerrainCancelled implements Exception {
  const TerrainCancelled();
  @override
  String toString() => 'TerrainCancelled';
}

/// Estimate for one grid point.
class PointPrediction {
  const PointPrediction({
    required this.lat,
    required this.lon,
    required this.rssiDbm,
    required this.confidence,
    required this.distanceM,
    required this.classification,
    required this.diffractionDb,
    this.worstClearanceRatio,
  });

  final double lat;
  final double lon;
  final double rssiDbm;
  final double confidence;
  final double distanceM;

  /// [PathClass.clear] when no terrain was available.
  final PathClass classification;
  final double diffractionDb;
  final double? worstClearanceRatio;
}

/// Result of [TerrainService.predictGrid].
class TerrainPrediction {
  const TerrainPrediction({
    required this.points,
    required this.terrainUnavailable,
    required this.calibration,
    this.unavailableReason,
  });

  /// Same order as the requested points.
  final List<PointPrediction> points;

  /// True when elevation data could not be obtained and the predictions use
  /// the distance-only (log-distance) model.
  final bool terrainUnavailable;
  final String? unavailableReason;

  /// Null when no measured points were supplied.
  final CalibrationResult? calibration;
}

/// Ties elevation source, profiles, path-loss model and calibration
/// together.
class TerrainService {
  TerrainService(this.source, {this.chunkSize = 1000});

  final ElevationSource source;

  /// Elevation points requested per source call (progress / cancellation
  /// granularity, and the unit persisted by a caching source).
  final int chunkSize;

  /// Predicts RSSI at each of [points] from [base].
  ///
  /// All profile sample locations for all points are gathered and deduped,
  /// then fetched in chunks (a caching source therefore keeps partial
  /// progress). [onProgress] receives 0..1. If the elevation source fails
  /// (offline, quota), the result is flagged `terrainUnavailable` and uses
  /// the distance-only model. Throws [TerrainCancelled] when [cancel] fires.
  Future<TerrainPrediction> predictGrid({
    required LatLng base,
    required List<LatLng> points,
    double frequencyMHz = 915,
    double baseHeightM = 2.0,
    double mobileHeightM = 1.5,
    List<MeasuredPoint> measured = const [],
    PathLossModel? model,
    void Function(double progress)? onProgress,
    TerrainCancelToken? cancel,
  }) async {
    final baseModel = model ?? const PathLossModel();
    final m0 = PathLossModel(
      frequencyMHz: frequencyMHz,
      exponent: baseModel.exponent,
      offsetDb: baseModel.offsetDb,
      maxEdges: baseModel.maxEdges,
      maxDiffractionDb: baseModel.maxDiffractionDb,
    );
    void check() {
      if (cancel?.isCancelled ?? false) throw const TerrainCancelled();
    }

    // Targets: grid points first, then measured points.
    final targets = <LatLng>[...points, for (final m in measured) m.point];
    final paths = [
      for (final t in targets) TerrainProfile.samplePoints(base, t),
    ];

    // Dedupe sample locations.
    final index = <(double, double), int>{};
    final unique = <LatLng>[];
    for (final path in paths) {
      for (final p in path) {
        index.putIfAbsent((p.latitude, p.longitude), () {
          unique.add(p);
          return unique.length - 1;
        });
      }
    }

    final elev = <double?>[];
    String? reason;
    try {
      for (var i = 0; i < unique.length; i += chunkSize) {
        check();
        final end = (i + chunkSize).clamp(0, unique.length);
        elev.addAll(await source.elevations(unique.sublist(i, end)));
        onProgress?.call(0.9 * end / unique.length);
      }
    } on ElevationUnavailable catch (e) {
      reason = e.message;
    }
    check();
    final terrain = reason == null;

    TerrainProfile? profileFor(int t) {
      if (!terrain) return null;
      final path = paths[t];
      return TerrainProfile.fromElevations(
        points: path,
        elevations: [
          for (final p in path) elev[index[(p.latitude, p.longitude)]!],
        ],
        frequencyMHz: frequencyMHz,
        baseHeightM: baseHeightM,
        mobileHeightM: mobileHeightM,
      );
    }

    // Calibrate on measured points.
    CalibrationResult? calibration;
    if (measured.isNotEmpty) {
      final samples = <CalibrationSample>[];
      for (var j = 0; j < measured.length; j++) {
        final prof = profileFor(points.length + j);
        samples.add(CalibrationSample(
          greatCircleDistanceM(base, measured[j].point),
          prof == null ? 0 : m0.diffractionLossDb(prof),
          measured[j].rssi,
        ));
      }
      calibration = CoverageCalibrator.fit(m0, samples);
    }
    final fitted = calibration?.model ?? m0;

    final out = <PointPrediction>[];
    for (var i = 0; i < points.length; i++) {
      if (i % 50 == 0) check();
      final prof = profileFor(i);
      final d = greatCircleDistanceM(base, points[i]);
      final p = fitted.predict(distanceM: d, profile: prof);
      out.add(PointPrediction(
        lat: points[i].latitude,
        lon: points[i].longitude,
        rssiDbm: p.rssiDbm,
        confidence: (calibration?.confidenceAt(d) ?? 0.1) * (terrain ? 1 : 0.5),
        distanceM: d,
        classification: p.classification,
        diffractionDb: p.diffractionDb,
        worstClearanceRatio: p.worstClearanceRatio,
      ));
    }
    onProgress?.call(1);
    return TerrainPrediction(
      points: out,
      terrainUnavailable: !terrain,
      unavailableReason: reason,
      calibration: calibration,
    );
  }
}
