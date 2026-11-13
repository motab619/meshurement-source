// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Guided test: the ghost route and how closely a walk follows it.
///
/// The first walk's track, resampled every [ghostStepM], is the ghost
/// route later walks follow; the route match is the share of ghost points
/// that the current track has come within [matchRadiusM] of. Flat-earth
/// metres (equirectangular) are plenty at walking scale.

const ghostStepM = 10.0;
const matchRadiusM = 25.0;

/// Route match at or above this lights "Done walking".
const routeMatchDonePct = 80.0;

/// A track point is kept only when it moved at least this far.
const trackMinStepM = 3.0;

const _mPerDegLat = 111320.0;

/// Metres between two points, flat-earth.
double flatDistanceM(LatLng a, LatLng b) {
  final cosLat = math.cos((a.latitude + b.latitude) / 2 * math.pi / 180);
  final dx = (b.longitude - a.longitude) * _mPerDegLat * cosLat;
  final dy = (b.latitude - a.latitude) * _mPerDegLat;
  return math.sqrt(dx * dx + dy * dy);
}

/// Compass bearing from [a] to [b], degrees clockwise from north.
double bearingDeg(LatLng a, LatLng b) {
  final cosLat = math.cos((a.latitude + b.latitude) / 2 * math.pi / 180);
  final dx = (b.longitude - a.longitude) * cosLat;
  final dy = b.latitude - a.latitude;
  final deg = math.atan2(dx, dy) * 180 / math.pi;
  return (deg + 360) % 360;
}

/// [track] resampled to one point every [stepM] along it (the first point
/// always kept). Empty in → empty out; one point → that point.
List<LatLng> resampleRoute(List<LatLng> track, {double stepM = ghostStepM}) {
  if (track.isEmpty) return const [];
  final out = <LatLng>[track.first];
  var carry = 0.0; // distance walked since the last emitted point
  for (var i = 1; i < track.length; i++) {
    var from = track[i - 1];
    final to = track[i];
    var seg = flatDistanceM(from, to);
    // A hair of tolerance so 100 m of 10 m steps yields all eleven points.
    while (carry + seg >= stepM - 1e-6) {
      final need = stepM - carry;
      final t = seg == 0 ? 1.0 : need / seg;
      final p = LatLng(
        from.latitude + (to.latitude - from.latitude) * t,
        from.longitude + (to.longitude - from.longitude) * t,
      );
      out.add(p);
      from = p;
      seg -= need;
      carry = 0;
    }
    carry += seg;
  }
  return out;
}

/// Share (0..100) of [ghost] points within [radiusM] of any point of
/// [track]; null when there is no ghost to match.
double? routeMatchPct(List<LatLng> ghost, List<LatLng> track,
    {double radiusM = matchRadiusM}) {
  if (ghost.isEmpty) return null;
  final m = RouteMatcher(ghost, radiusM: radiusM);
  for (final p in track) {
    m.addPoint(p);
  }
  return m.pct;
}

/// Incremental route match: feed each new track point as it arrives.
class RouteMatcher {
  final List<LatLng> ghost;
  final double radiusM;
  final List<bool> _hit;
  int _hits = 0;

  RouteMatcher(this.ghost, {this.radiusM = matchRadiusM})
      : _hit = List.filled(ghost.length, false);

  /// Null without a ghost route.
  double? get pct => ghost.isEmpty ? null : 100 * _hits / ghost.length;

  int get hits => _hits;

  void addPoint(LatLng p) {
    for (var i = 0; i < ghost.length; i++) {
      if (_hit[i]) continue;
      if (flatDistanceM(ghost[i], p) <= radiusM) {
        _hit[i] = true;
        _hits++;
      }
    }
  }
}

/// Keeps a walked track thin: a point is added only when it moved at
/// least [minStepM] from the last one kept.
class TrackBuilder {
  final double minStepM;
  final List<LatLng> points = [];

  TrackBuilder({this.minStepM = trackMinStepM});

  /// True when the point was kept.
  bool add(LatLng p) {
    if (points.isNotEmpty && flatDistanceM(points.last, p) < minStepM) {
      return false;
    }
    points.add(p);
    return true;
  }
}

/// Compact JSON for a route ([lat, lon] pairs, 5 decimals ≈ 1 m). Stored in
/// a step's params, never sent anywhere.
List<List<double>> routeToJson(List<LatLng> route) => [
      for (final p in route)
        [_r5(p.latitude), _r5(p.longitude)],
    ];

List<LatLng> routeFromJson(Object? j) {
  if (j is! List) return const [];
  final out = <LatLng>[];
  for (final e in j) {
    if (e is List && e.length == 2 && e[0] is num && e[1] is num) {
      out.add(LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble()));
    }
  }
  return out;
}

double _r5(double v) => (v * 1e5).round() / 1e5;
