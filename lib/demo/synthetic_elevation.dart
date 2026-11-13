// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../services/terrain/elevation_source.dart';

/// Demo-mode elevation source: plausible made-up terrain, no network.
///
/// Gently rolling ground (a few metres of relief) plus one smooth hill
/// ([hillCenter], [hillHeightM] tall, [hillRadiusM] wide) so a profile
/// through it shows an obstruction. Deterministic.
class SyntheticElevationSource implements ElevationSource {
  const SyntheticElevationSource({
    required this.hillCenter,
    this.baseLevelM = 20,
    this.hillHeightM = 14,
    this.hillRadiusM = 120,
  });

  final LatLng hillCenter;
  final double baseLevelM;
  final double hillHeightM;
  final double hillRadiusM;

  @override
  String get name => 'synthetic (demo)';

  double elevationAt(LatLng p) {
    // Local metres east/north of the hill centre.
    final n = (p.latitude - hillCenter.latitude) * 111132.0;
    final e = (p.longitude - hillCenter.longitude) *
        111320.0 *
        math.cos(hillCenter.latitude * math.pi / 180);
    final rolling = 2.5 * math.sin(e / 190) + 2.0 * math.cos(n / 140 + e / 420);
    final d2 = e * e + n * n;
    final hill = hillHeightM * math.exp(-d2 / (2 * hillRadiusM * hillRadiusM));
    return baseLevelM + rolling + hill;
  }

  @override
  Future<List<double?>> elevations(List<LatLng> points) async =>
      [for (final p in points) elevationAt(p)];
}
