// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'terrain_profile.dart';

/// How a path looks against the first Fresnel zone.
enum PathClass {
  /// At least 60% of the first Fresnel zone is clear everywhere.
  clear,

  /// Line of sight exists but terrain intrudes more than 40% into F1.
  partialFresnel,

  /// Terrain blocks the line of sight.
  obstructed,
}

/// Result of [PathLossModel.predict].
class PathLossPrediction {
  const PathLossPrediction({
    required this.distanceM,
    required this.freeSpaceDb,
    required this.logDistanceDb,
    required this.diffractionDb,
    required this.rssiDbm,
    required this.classification,
    required this.worstClearanceRatio,
  });

  final double distanceM;

  /// Free-space path loss at [distanceM] (reference only).
  final double freeSpaceDb;

  /// Log-distance loss with the model's exponent (no terrain).
  final double logDistanceDb;

  /// Knife-edge diffraction penalty (0 when no profile was used).
  final double diffractionDb;
  final double rssiDbm;
  final PathClass classification;

  /// Null when no terrain profile was available.
  final double? worstClearanceRatio;

  double get totalLossDb => logDistanceDb + diffractionDb;
}

/// Radio path-loss model: log-distance plus knife-edge diffraction.
///
///   RSSI = offsetDb - [ FSPL(d0) + 10 n log10(d / d0) + diffraction ]
///
/// - FSPL(d) = 32.44 + 20 log10(d_km) + 20 log10(f_MHz) dB (Friis,
///   ITU-R P.525).
/// - Log-distance with reference d0 = 1 m and exponent n (Rappaport,
///   "Wireless Communications", ch. 4). n = 2 is free space; 2.7-3.5 is
///   typical of suburban/obstructed outdoor paths. Default 2.7.
/// - Diffraction: single knife edge with Fresnel-Kirchhoff parameter
///   v = h * sqrt(2 (d1 + d2) / (lambda d1 d2)), where h is the obstacle top
///   above the line of sight; J(v) = 6.9 + 20 log10(sqrt((v-0.1)^2 + 1) +
///   v - 0.1) for v > -0.78, else 0 (ITU-R P.526 eq. 31). For several edges
///   the Deygout construction is used: the principal edge (largest v) first,
///   then the most significant edge on each side of it measured against the
///   principal edge top (so up to 3 edges). Deygout tends to over-estimate
///   for many edges, hence the 3-edge limit and [maxDiffractionDb] cap.
/// - [offsetDb] folds in transmit power, antenna gains, cable losses and
///   receiver offset (so it is an "RSSI at 1 m path loss of 0" constant); the
///   calibrator fits it.
class PathLossModel {
  const PathLossModel({
    this.frequencyMHz = 915,
    this.exponent = 2.7,
    this.offsetDb = 20,
    this.maxEdges = 3,
    this.maxDiffractionDb = 50,
  });

  final double frequencyMHz;
  final double exponent;
  final double offsetDb;

  /// 1 = principal edge only, 3 = Deygout with up to three edges.
  final int maxEdges;
  final double maxDiffractionDb;

  /// Reference distance of the log-distance model.
  static const double referenceDistanceM = 1.0;

  /// Clearance ratio at or above which a path counts as [PathClass.clear].
  static const double clearThreshold = 0.6;

  PathLossModel copyWith({double? exponent, double? offsetDb}) =>
      PathLossModel(
        frequencyMHz: frequencyMHz,
        exponent: exponent ?? this.exponent,
        offsetDb: offsetDb ?? this.offsetDb,
        maxEdges: maxEdges,
        maxDiffractionDb: maxDiffractionDb,
      );

  /// Free-space path loss in dB.
  static double freeSpaceLossDb(double distanceM, double frequencyMHz) =>
      32.44 +
      20 * _log10(math.max(distanceM, 1.0) / 1000.0) +
      20 * _log10(frequencyMHz);

  /// Knife-edge diffraction loss J(v) in dB (ITU-R P.526).
  static double knifeEdgeLossDb(double v) {
    if (v <= -0.78) return 0;
    final a = v - 0.1;
    return 6.9 + 20 * _log10(math.sqrt(a * a + 1) + a);
  }

  /// Log-distance loss at [distanceM] using this model's exponent.
  double logDistanceLossDb(double distanceM) {
    final d = math.max(distanceM, referenceDistanceM);
    return freeSpaceLossDb(referenceDistanceM, frequencyMHz) +
        10 * exponent * _log10(d / referenceDistanceM);
  }

  /// Diffraction loss along [profile] (Deygout, see class docs).
  double diffractionLossDb(TerrainProfile profile) {
    final s = profile.samples;
    final n = s.length - 1;
    if (n < 2) return 0;
    final lambda = wavelengthM(frequencyMHz);

    double height(int i) =>
        (i == 0 || i == n) ? s[i].losM : s[i].effectiveGroundM;

    // Returns the loss of the principal edge between a and b plus (while
    // depth allows) the sub-path edges.
    double deygout(int a, int b, int depth) {
      var bestV = double.negativeInfinity;
      var bestI = -1;
      for (var i = a + 1; i < b; i++) {
        final d1 = s[i].distanceM - s[a].distanceM;
        final d2 = s[b].distanceM - s[i].distanceM;
        if (d1 <= 0 || d2 <= 0) continue;
        final los = height(a) + (height(b) - height(a)) * d1 / (d1 + d2);
        final h = s[i].effectiveGroundM - los;
        final v = h * math.sqrt(2 * (d1 + d2) / (lambda * d1 * d2));
        if (v > bestV) {
          bestV = v;
          bestI = i;
        }
      }
      if (bestI < 0 || bestV <= -0.78) return 0;
      var loss = knifeEdgeLossDb(bestV);
      if (depth < (maxEdges >= 3 ? 1 : 0)) {
        loss += deygout(a, bestI, depth + 1) + deygout(bestI, b, depth + 1);
      }
      return loss;
    }

    // Sub-path edges measured against the principal edge top use the
    // obstacle's bulged ground height as the new end point, as in `height`.
    return math.min(deygout(0, n, 0), maxDiffractionDb);
  }

  /// Classification from the worst first-Fresnel clearance ratio.
  static PathClass classify(double worstClearanceRatio) {
    if (worstClearanceRatio >= clearThreshold) return PathClass.clear;
    if (worstClearanceRatio >= 0) return PathClass.partialFresnel;
    return PathClass.obstructed;
  }

  /// Predicts loss and RSSI over [distanceM]; terrain is used if [profile] is
  /// given (its distance wins if [distanceM] is omitted).
  PathLossPrediction predict({double? distanceM, TerrainProfile? profile}) {
    final d = distanceM ?? profile?.distanceM ?? 1.0;
    final diff = profile == null ? 0.0 : diffractionLossDb(profile);
    final ld = logDistanceLossDb(d);
    return PathLossPrediction(
      distanceM: d,
      freeSpaceDb: freeSpaceLossDb(d, frequencyMHz),
      logDistanceDb: ld,
      diffractionDb: diff,
      rssiDbm: offsetDb - (ld + diff),
      classification: profile == null
          ? PathClass.clear
          : classify(profile.worstClearanceRatio),
      worstClearanceRatio: profile?.worstClearanceRatio,
    );
  }
}

double _log10(double x) => math.log(x) / math.ln10;
