// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'track_distance.dart';

/// Distance units (Settings → Display → Units, pref `distance_units`).
/// Automatic follows the phone's region ([milesForCountry]).
enum DistanceUnits {
  automatic('Automatic'),
  miles('Miles'),
  kilometres('Kilometres');

  const DistanceUnits(this.label);
  final String label;

  static DistanceUnits fromName(String? name) => DistanceUnits.values
      .firstWhere((u) => u.name == name, orElse: () => automatic);

  /// Whether distances show in miles (and short ones in feet) for a phone
  /// in [countryCode].
  bool useMiles(String? countryCode) => switch (this) {
        automatic => milesForCountry(countryCode),
        miles => true,
        kilometres => false,
      };
}

const metresPerMile = 1609.344;
const metresPerFoot = 0.3048;

/// A distance for a headline or a stat: "0.4 mi" / "530 ft" in miles,
/// "1.2 km" / "650 m" otherwise. Short distances (under 0.1 mi or 1 km)
/// use feet or metres, rounded to 10.
String formatDistance(double metres, {required bool miles}) {
  if (miles) {
    final mi = metres / metresPerMile;
    if (mi < 0.1) return '${_round10(metres / metresPerFoot)} ft';
    return '${mi < 10 ? mi.toStringAsFixed(1) : mi.round()} mi';
  }
  if (metres < 1000) return '${_round10(metres)} m';
  final km = metres / 1000;
  return '${km < 10 ? km.toStringAsFixed(1) : km.round()} km';
}

int _round10(double v) => (v / 10).round() * 10;

/// The Hide base area choices in metres, as offered in a region: 120 m and
/// 300 m, or 400 ft and 1,000 ft (a little more, never less) in miles.
List<double> hideRadiusChoicesM({required bool miles}) => miles
    ? const [0, 400 * metresPerFoot, 1000 * metresPerFoot]
    : const [0, 120, 300];

/// "Off", "120 m", "1,000 ft".
String hideRadiusLabel(double metres, {required bool miles}) {
  if (metres <= 0) return 'Off';
  if (!miles) return '${metres.round()} m';
  final ft = (metres / metresPerFoot).round();
  return ft >= 1000
      ? '${ft ~/ 1000},${(ft % 1000).toString().padLeft(3, '0')} ft'
      : '$ft ft';
}

/// A scale bar length that reads well ("100 m", "500 ft", "1 mi") and is
/// at most [maxMetres] long. Returns (length in metres, label).
(double, String) niceScaleBar(double maxMetres, {required bool miles}) {
  if (miles) {
    // Feet up to 1,000, then fractions and whole miles.
    const feet = [10, 20, 50, 100, 200, 500, 1000];
    const mi = [0.25, 0.5, 1, 2, 5, 10, 20, 50, 100];
    (double, String)? best;
    for (final f in feet) {
      final m = f * metresPerFoot;
      if (m <= maxMetres) best = (m, '${f == 1000 ? '1,000' : f} ft');
    }
    for (final v in mi) {
      final m = v * metresPerMile;
      if (m <= maxMetres) {
        best = (m, '${v == v.roundToDouble() ? v.round() : v} mi');
      }
    }
    return best ?? (10 * metresPerFoot, '10 ft');
  }
  const metres = [10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000];
  (double, String)? best;
  for (final v in metres) {
    if (v <= maxMetres) best = (v.toDouble(), v >= 1000 ? '${v ~/ 1000} km' : '$v m');
  }
  return best ?? (10, '10 m');
}
