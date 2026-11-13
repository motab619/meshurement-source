// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/constants.dart';

/// Antenna heights (metres above ground) used by the terrain features
/// (line-of-sight profile and terrain-aware estimate), persisted in
/// SharedPreferences.
class TerrainSettings {
  const TerrainSettings({
    this.baseHeightM = defaultBaseHeightM,
    this.mobileHeightM = defaultMobileHeightM,
  });

  static const double defaultBaseHeightM = 2.0;
  static const double defaultMobileHeightM = 1.5;
  static const double minHeightM = 0.5;
  static const double maxHeightM = 50.0;

  final double baseHeightM;
  final double mobileHeightM;

  /// Reads the saved heights (defaults when unset; clamped to the range).
  factory TerrainSettings.load(SharedPreferences prefs) => TerrainSettings(
        baseHeightM: (prefs.getDouble(AppConstants.prefTerrainBaseHeightM) ??
                defaultBaseHeightM)
            .clamp(minHeightM, maxHeightM),
        mobileHeightM:
            (prefs.getDouble(AppConstants.prefTerrainMobileHeightM) ??
                    defaultMobileHeightM)
                .clamp(minHeightM, maxHeightM),
      );

  static Future<void> saveBaseHeight(SharedPreferences prefs, double m) =>
      prefs.setDouble(
          AppConstants.prefTerrainBaseHeightM, m.clamp(minHeightM, maxHeightM));

  static Future<void> saveMobileHeight(SharedPreferences prefs, double m) =>
      prefs.setDouble(AppConstants.prefTerrainMobileHeightM,
          m.clamp(minHeightM, maxHeightM));

  /// The base location the user placed for [mapId], if any.
  static LatLng? loadUserBase(SharedPreferences prefs, int mapId) {
    final raw = prefs.getString(AppConstants.prefTerrainBaseLocation(mapId));
    if (raw == null) return null;
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0]), lon = double.tryParse(parts[1]);
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  /// Whether the user declined the Radio Setup base location for [mapId].
  static bool loadBaseOptOut(SharedPreferences prefs, int mapId) =>
      prefs.getBool(AppConstants.prefTerrainBaseOptOut(mapId)) ?? false;

  static Future<void> saveBaseOptOut(
          SharedPreferences prefs, int mapId, bool optOut) =>
      optOut
          ? prefs.setBool(AppConstants.prefTerrainBaseOptOut(mapId), true)
          : prefs.remove(AppConstants.prefTerrainBaseOptOut(mapId));

  /// Saves (or, with null, clears) the user-placed base for [mapId].
  static Future<void> saveUserBase(
          SharedPreferences prefs, int mapId, LatLng? p) =>
      p == null
          ? prefs.remove(AppConstants.prefTerrainBaseLocation(mapId))
          : prefs.setString(AppConstants.prefTerrainBaseLocation(mapId),
              '${p.latitude},${p.longitude}');
}
