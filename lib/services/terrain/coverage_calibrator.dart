// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'elevation_source.dart';
import 'geo.dart';
import 'path_loss_model.dart';
import 'terrain_profile.dart';

/// A measured RSSI at a location.
class MeasuredPoint {
  const MeasuredPoint(this.lat, this.lon, this.rssi);
  final double lat;
  final double lon;
  final double rssi;
  LatLng get point => LatLng(lat, lon);
}

/// One regression input: distance, the model's diffraction loss on that
/// path, and the measured RSSI.
class CalibrationSample {
  const CalibrationSample(this.distanceM, this.diffractionDb, this.rssiDbm);
  final double distanceM;
  final double diffractionDb;
  final double rssiDbm;
}

/// Fitted model plus fit quality.
class CalibrationResult {
  const CalibrationResult({
    required this.model,
    required this.rmseDb,
    required this.sampleCount,
    required this.maxFitDistanceM,
    required this.exponentFitted,
  });

  final PathLossModel model;

  /// Root-mean-square error of the fit over the calibration samples (dB).
  final double rmseDb;
  final int sampleCount;
  final double maxFitDistanceM;
  final bool exponentFitted;

  double get offsetDb => model.offsetDb;
  double get exponent => model.exponent;

  /// Heuristic confidence 0..1 for a prediction at [distanceM]:
  /// product of (a) fit quality 1 - rmse/12 dB, (b) sample support
  /// min(1, n/10), and (c) an extrapolation penalty maxFitDistance/distance
  /// beyond the farthest calibration point. With no samples: 0.1.
  /// It is a ranking aid for the UI, not a statistical interval.
  double confidenceAt(double distanceM) {
    if (sampleCount == 0) return 0.1;
    final fit = (1 - rmseDb / 12).clamp(0.05, 1.0);
    final support = math.min(1.0, sampleCount / 10);
    final extrap = distanceM <= maxFitDistanceM
        ? 1.0
        : (maxFitDistanceM / distanceM).clamp(0.2, 1.0);
    return (fit * support * extrap).clamp(0.05, 1.0);
  }
}

/// RSSI estimate for one location.
class RssiEstimate {
  const RssiEstimate(this.rssiDbm, this.confidence, this.prediction);
  final double rssiDbm;
  final double confidence;
  final PathLossPrediction prediction;
}

/// Calibrates [PathLossModel] against measured signal strength.
///
/// Model: RSSI = offset - (FSPL(1 m) + 10 n log10 d + diffraction). With
/// y = RSSI + FSPL(1 m) + diffraction and x = log10 d this is the straight
/// line y = offset - 10 n x, so ordinary least squares gives offset and n in
/// closed form. n is bounded to [minExponent, maxExponent] (2.0-4.0); if the
/// unconstrained slope falls outside, n is pinned to the bound and the
/// offset is re-fitted (the exact constrained optimum for this convex
/// problem). Needs >= 3 samples with distance spread to fit n; otherwise only
/// the offset is fitted at the base model's exponent.
class CoverageCalibrator {
  CoverageCalibrator({
    required this.base,
    this.source,
    this.baseModel = const PathLossModel(),
    this.baseHeightM = 2.0,
    this.mobileHeightM = 1.5,
    this.fitExponent = true,
  });

  static const double minExponent = 2.0;
  static const double maxExponent = 4.0;

  final LatLng base;

  /// Elevation source; null means distance-only calibration.
  final ElevationSource? source;
  final PathLossModel baseModel;
  final double baseHeightM;
  final double mobileHeightM;
  final bool fitExponent;

  CalibrationResult? _result;
  CalibrationResult? get result => _result;

  /// Pure least-squares fit; no IO.
  static CalibrationResult fit(
    PathLossModel model,
    List<CalibrationSample> samples, {
    bool fitExponent = true,
  }) {
    if (samples.isEmpty) {
      return CalibrationResult(
        model: model,
        rmseDb: 0,
        sampleCount: 0,
        maxFitDistanceM: 0,
        exponentFitted: false,
      );
    }
    final fspl1m = PathLossModel.freeSpaceLossDb(
        PathLossModel.referenceDistanceM, model.frequencyMHz);
    final n = samples.length;
    final xs = [
      for (final s in samples)
        math.log(math.max(s.distanceM, 1.0)) / math.ln10,
    ];
    final ys = [
      for (final s in samples) s.rssiDbm + fspl1m + s.diffractionDb,
    ];
    final mx = xs.reduce((a, b) => a + b) / n;
    final my = ys.reduce((a, b) => a + b) / n;
    var sxx = 0.0, sxy = 0.0;
    for (var i = 0; i < n; i++) {
      sxx += (xs[i] - mx) * (xs[i] - mx);
      sxy += (xs[i] - mx) * (ys[i] - my);
    }
    var exponent = model.exponent;
    var fitted = false;
    if (fitExponent && n >= 3 && sxx > 1e-6) {
      exponent = (-(sxy / sxx) / 10).clamp(minExponent, maxExponent);
      fitted = true;
    }
    final offset = my + 10 * exponent * mx;
    final fittedModel = model.copyWith(exponent: exponent, offsetDb: offset);
    var sse = 0.0;
    var maxD = 0.0;
    for (var i = 0; i < n; i++) {
      final e = ys[i] - (offset - 10 * exponent * xs[i]);
      sse += e * e;
      maxD = math.max(maxD, samples[i].distanceM);
    }
    return CalibrationResult(
      model: fittedModel,
      rmseDb: math.sqrt(sse / n),
      sampleCount: n,
      maxFitDistanceM: maxD,
      exponentFitted: fitted,
    );
  }

  /// Fits the model to [measured], using terrain diffraction when [source]
  /// can provide elevations (falls back to distance-only on
  /// [ElevationUnavailable]).
  Future<CalibrationResult> calibrate(List<MeasuredPoint> measured) async {
    final samples = <CalibrationSample>[];
    var terrainOk = source != null;
    for (final m in measured) {
      TerrainProfile? profile;
      if (terrainOk) {
        try {
          profile = await TerrainProfile.build(source!, base, m.point,
              frequencyMHz: baseModel.frequencyMHz,
              baseHeightM: baseHeightM,
              mobileHeightM: mobileHeightM);
        } on ElevationUnavailable {
          terrainOk = false;
        }
      }
      samples.add(CalibrationSample(
        greatCircleDistanceM(base, m.point),
        profile == null ? 0 : baseModel.diffractionLossDb(profile),
        m.rssi,
      ));
    }
    // If terrain failed part-way, earlier samples include diffraction and
    // later ones do not; refit consistently without terrain.
    if (source != null && !terrainOk) {
      for (var i = 0; i < samples.length; i++) {
        samples[i] = CalibrationSample(
            samples[i].distanceM, 0, samples[i].rssiDbm);
      }
    }
    return _result = fit(baseModel, samples, fitExponent: fitExponent);
  }

  /// RSSI estimate at ([lat], [lon]) with the calibrated model (the base
  /// model if [calibrate] has not run).
  Future<RssiEstimate> predict(double lat, double lon) async {
    final model = _result?.model ?? baseModel;
    final target = LatLng(lat, lon);
    TerrainProfile? profile;
    if (source != null) {
      try {
        profile = await TerrainProfile.build(source!, base, target,
            frequencyMHz: model.frequencyMHz,
            baseHeightM: baseHeightM,
            mobileHeightM: mobileHeightM);
      } on ElevationUnavailable {
        profile = null;
      }
    }
    final d = greatCircleDistanceM(base, target);
    final p = model.predict(distanceM: d, profile: profile);
    final conf = _result?.confidenceAt(d) ?? 0.1;
    return RssiEstimate(p.rssiDbm, conf, p);
  }
}
