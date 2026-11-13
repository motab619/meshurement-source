// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Mean earth radius in metres (IUGG).
const double earthRadiusM = 6371008.8;

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

/// Great-circle (haversine) distance in metres.
double greatCircleDistanceM(LatLng a, LatLng b) {
  final dLat = _rad(b.latitude - a.latitude);
  final dLon = _rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) *
          math.cos(_rad(b.latitude)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Point at fraction [f] (0..1) along the great circle from [a] to [b]
/// (spherical linear interpolation).
LatLng greatCircleInterpolate(LatLng a, LatLng b, double f) {
  if (f <= 0) return a;
  if (f >= 1) return b;
  final delta = greatCircleDistanceM(a, b) / earthRadiusM;
  if (delta < 1e-12) return a;
  final la = _rad(a.latitude), lo1 = _rad(a.longitude);
  final lb = _rad(b.latitude), lo2 = _rad(b.longitude);
  final sd = math.sin(delta);
  final wa = math.sin((1 - f) * delta) / sd;
  final wb = math.sin(f * delta) / sd;
  final x =
      wa * math.cos(la) * math.cos(lo1) + wb * math.cos(lb) * math.cos(lo2);
  final y =
      wa * math.cos(la) * math.sin(lo1) + wb * math.cos(lb) * math.sin(lo2);
  final z = wa * math.sin(la) + wb * math.sin(lb);
  return LatLng(
    _deg(math.atan2(z, math.sqrt(x * x + y * y))),
    _deg(math.atan2(y, x)),
  );
}
