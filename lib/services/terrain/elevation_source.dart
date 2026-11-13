// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:latlong2/latlong.dart';

/// Provider of ground elevation (metres above mean sea level).
///
/// Implementations: `OpenTopoDataSource` (network) and
/// `CachedElevationSource` (disk cache wrapper). A self-hosted tile source
/// can be added later behind the same interface.
abstract class ElevationSource {
  /// Elevation for each point, same order and length as [points].
  /// `null` means unknown (no data, e.g. over water in some datasets).
  /// Throws [ElevationUnavailable] if the source cannot be reached.
  Future<List<double?>> elevations(List<LatLng> points);

  /// Short human-readable name (for logs and attribution).
  String get name;
}

/// The elevation source cannot answer right now (offline, server error,
/// quota exhausted). Callers should degrade to a distance-only model.
class ElevationUnavailable implements Exception {
  const ElevationUnavailable(this.message);
  final String message;
  @override
  String toString() => 'ElevationUnavailable: $message';
}

/// Online terrain data is switched off (Settings → Privacy). Nothing was sent.
class ElevationDisabled extends ElevationUnavailable {
  const ElevationDisabled() : super(userMessage);

  /// Shown wherever a terrain feature is requested while the switch is off.
  static const String userMessage =
      'Turn on terrain elevation in Settings → Privacy';
}

/// The public API's daily request budget is used up.
class ElevationQuotaExceeded extends ElevationUnavailable {
  const ElevationQuotaExceeded(super.message);
  @override
  String toString() => 'ElevationQuotaExceeded: $message';
}
