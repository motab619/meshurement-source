// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:latlong2/latlong.dart';

import '../data/database/app_database.dart';
import '../utils/constants.dart';

/// Distance travelled during a session, from the GPS fixes on its packet
/// events (a mileage log for test drives).
///
/// The track is sampled wherever a packet was sent or heard, so it joins
/// those fixes with straight lines and slightly undercounts curves. Steps
/// under [jitterM] are GPS noise while stopped and are skipped. Synthesised
/// beacon-miss rows carry interpolated positions, not fixes, and are left
/// out.
const double trackJitterM = 3;

const _dist = Distance();

/// Track length in metres of [events] (any order), or 0 with fewer than two
/// fixes.
double trackDistanceM(Iterable<PacketEvent> events,
    {double jitterM = trackJitterM}) {
  final fixes = [
    for (final e in events)
      if (e.rxLat != null &&
          e.rxLon != null &&
          e.sourceKind != SourceKind.telemetryMiss)
        (e.timestamp, LatLng(e.rxLat!, e.rxLon!)),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return trackLengthM([for (final f in fixes) f.$2], jitterM: jitterM);
}

/// Length of a time-ordered track in metres, skipping steps under [jitterM].
double trackLengthM(List<LatLng> track, {double jitterM = trackJitterM}) {
  var total = 0.0;
  for (var i = 1; i < track.length; i++) {
    final d = _dist.as(LengthUnit.Meter, track[i - 1], track[i]);
    if (d >= jitterM) total += d;
  }
  return total;
}

/// Countries that drive in miles (US, UK, Liberia, Myanmar).
bool milesForCountry(String? countryCode) =>
    const {'US', 'GB', 'LR', 'MM'}.contains(countryCode?.toUpperCase());

/// "5.1 mi" or "8.2 km"; null when under 50 m (not a drive).
String? formatTrackDistance(double metres, {required bool miles}) {
  if (metres < 50) return null;
  final v = miles ? metres / 1609.344 : metres / 1000;
  return '${v.toStringAsFixed(1)} ${miles ? 'mi' : 'km'}';
}
