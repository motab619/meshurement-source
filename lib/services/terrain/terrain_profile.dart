// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'elevation_source.dart';
import 'geo.dart';

const double _speedOfLight = 299792458.0;

/// Wavelength in metres for [frequencyMHz].
double wavelengthM(double frequencyMHz) => _speedOfLight / (frequencyMHz * 1e6);

/// Radius of the first Fresnel zone (metres) at a point [d1M] from one
/// end and [d2M] from the other: `F1 = sqrt(lambda * d1 * d2 / (d1 + d2))`.
/// (Standard result; e.g. ITU-R P.526 section 2.)
double fresnelRadiusM(double d1M, double d2M, double frequencyMHz) {
  final d = d1M + d2M;
  if (d <= 0 || d1M <= 0 || d2M <= 0) return 0;
  return math.sqrt(wavelengthM(frequencyMHz) * d1M * d2M / d);
}

/// Earth bulge (metres) at a point [d1M]/[d2M] from the ends of a path, for
/// effective earth radius `k * R`: `h = d1 * d2 / (2 * k * R)`. Radio
/// refraction in a standard atmosphere is modelled by k = 4/3 (ITU-R P.834).
double earthBulgeM(double d1M, double d2M, {double k = 4 / 3}) =>
    d1M * d2M / (2 * k * 6371000.0);

/// One sample along the path.
class ProfileSample {
  const ProfileSample({
    required this.point,
    required this.distanceM,
    required this.groundM,
    required this.bulgeM,
    required this.losM,
    required this.f1RadiusM,
  });

  final LatLng point;

  /// Distance from the base along the path.
  final double distanceM;

  /// Ground elevation above sea level (metres).
  final double groundM;

  /// Earth bulge at this sample (metres).
  final double bulgeM;

  /// Height of the line of sight between antenna tips (metres, same datum
  /// as [groundM]).
  final double losM;

  /// First Fresnel zone radius here (metres).
  final double f1RadiusM;

  /// Ground height raised by earth bulge: the obstacle height in the
  /// "flattened earth" picture.
  double get effectiveGroundM => groundM + bulgeM;

  /// Metres between the LOS and the bulged ground (negative = blocked).
  double get clearanceM => losM - effectiveGroundM;

  /// Clearance in units of F1 radius (>= 1 fully clear, >= 0.6 is the usual
  /// design target, < 0 blocked). Zero at the end points where F1 is zero.
  double get clearanceRatio =>
      f1RadiusM > 0 ? clearanceM / f1RadiusM : double.infinity;
}

/// Terrain cross-section between a base and a target, with line-of-sight and
/// Fresnel clearance computed on a flattened earth with effective radius
/// factor k.
class TerrainProfile {
  TerrainProfile._({
    required this.samples,
    required this.distanceM,
    required this.frequencyMHz,
    required this.k,
    required this.worstIndex,
  });

  /// Samples from base (index 0) to target (last).
  final List<ProfileSample> samples;
  final double distanceM;
  final double frequencyMHz;
  final double k;

  /// Index of the interior sample with the lowest clearance ratio, or -1 if
  /// there is no interior sample.
  final int worstIndex;

  /// Cap used when there is nothing to measure (very short paths).
  static const double clearRatioCap = 10.0;

  /// Lowest clearance / F1 radius over interior samples (capped at
  /// [clearRatioCap]).
  double get worstClearanceRatio => worstIndex < 0
      ? clearRatioCap
      : math.min(samples[worstIndex].clearanceRatio, clearRatioCap);

  /// The sample that limits the path (null for paths with no interior).
  ProfileSample? get dominantObstruction =>
      worstIndex < 0 ? null : samples[worstIndex];

  /// Maximum spacing target and sample cap used by [samplePoints].
  static const double targetSpacingM = 30.0;
  static const int maxSamples = 200;

  /// Sample locations along the great circle base -> target, including both
  /// end points. Spacing ~30 m, widened so there are at most [maxSamples].
  static List<LatLng> samplePoints(LatLng base, LatLng target) {
    final d = greatCircleDistanceM(base, target);
    final n = (d / targetSpacingM).ceil().clamp(1, maxSamples - 1);
    return [
      for (var i = 0; i <= n; i++) greatCircleInterpolate(base, target, i / n),
    ];
  }

  /// Builds a profile from elevations at [points] (as from [samplePoints]).
  /// Unknown elevations (null) are filled by linear interpolation between
  /// known neighbours (nearest known at the ends). Returns null if no
  /// elevation is known at all.
  static TerrainProfile? fromElevations({
    required List<LatLng> points,
    required List<double?> elevations,
    double frequencyMHz = 915,
    double baseHeightM = 2.0,
    double mobileHeightM = 1.5,
    double k = 4 / 3,
  }) {
    assert(points.length == elevations.length && points.length >= 2);
    final ground = _fillGaps(elevations);
    if (ground == null) return null;
    final n = points.length - 1;
    final cum = <double>[0];
    for (var i = 1; i <= n; i++) {
      cum.add(cum.last + greatCircleDistanceM(points[i - 1], points[i]));
    }
    final total = cum.last;
    final baseTip = ground.first + baseHeightM;
    final mobTip = ground.last + mobileHeightM;
    final samples = <ProfileSample>[];
    var worst = -1;
    var worstRatio = double.infinity;
    for (var i = 0; i <= n; i++) {
      final d1 = cum[i], d2 = total - cum[i];
      final s = ProfileSample(
        point: points[i],
        distanceM: d1,
        groundM: ground[i],
        bulgeM: earthBulgeM(d1, d2, k: k),
        losM: total > 0 ? baseTip + (mobTip - baseTip) * d1 / total : baseTip,
        f1RadiusM: fresnelRadiusM(d1, d2, frequencyMHz),
      );
      samples.add(s);
      if (i > 0 && i < n && s.clearanceRatio < worstRatio) {
        worstRatio = s.clearanceRatio;
        worst = i;
      }
    }
    return TerrainProfile._(
      samples: samples,
      distanceM: total,
      frequencyMHz: frequencyMHz,
      k: k,
      worstIndex: worst,
    );
  }

  static List<double>? _fillGaps(List<double?> e) {
    final known = [
      for (var i = 0; i < e.length; i++)
        if (e[i] != null) i,
    ];
    if (known.isEmpty) return null;
    final out = List<double>.filled(e.length, 0);
    for (var i = 0; i < e.length; i++) {
      final v = e[i];
      if (v != null) {
        out[i] = v;
        continue;
      }
      int? lo, hi;
      for (final j in known) {
        if (j < i) lo = j;
        if (j > i) {
          hi = j;
          break;
        }
      }
      if (lo == null) {
        out[i] = e[hi!]!;
      } else if (hi == null) {
        out[i] = e[lo]!;
      } else {
        final t = (i - lo) / (hi - lo);
        out[i] = e[lo]! + (e[hi]! - e[lo]!) * t;
      }
    }
    return out;
  }

  /// Fetches elevations from [source] and builds the profile. Returns null if
  /// no elevation is known. Throws [ElevationUnavailable] from the source.
  static Future<TerrainProfile?> build(
    ElevationSource source,
    LatLng base,
    LatLng target, {
    double frequencyMHz = 915,
    double baseHeightM = 2.0,
    double mobileHeightM = 1.5,
    double k = 4 / 3,
  }) async {
    final pts = samplePoints(base, target);
    final elev = await source.elevations(pts);
    return fromElevations(
      points: pts,
      elevations: elev,
      frequencyMHz: frequencyMHz,
      baseHeightM: baseHeightM,
      mobileHeightM: mobileHeightM,
      k: k,
    );
  }
}
