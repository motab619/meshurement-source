// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where a base radio was when the phone set it up. Most base radios have
/// no GPS, but the phone is next to the base during Radio Setup ("put both
/// radios side by side"), so its fix is a good stand-in. Keyed by the
/// base's mesh node number; new coverage maps for that base start with it.
class BaseLocation {
  final LatLng point;
  final double accuracyM;
  final DateTime at;

  const BaseLocation(this.point, {required this.accuracyM, required this.at});
}

class BaseLocationStore {
  /// Fixes worse than this are not worth remembering as "the base".
  static const maxAccuracyM = 50.0;

  final SharedPreferences _prefs;
  const BaseLocationStore(this._prefs);

  static String _key(int nodeNum) => 'base_loc_$nodeNum';

  /// Remember [point] for [nodeNum]; ignored when [accuracyM] is too poor.
  Future<bool> record(int nodeNum, LatLng point,
      {required double accuracyM, DateTime? at}) async {
    if (accuracyM > maxAccuracyM) return false;
    final t = (at ?? DateTime.now()).millisecondsSinceEpoch;
    await _prefs.setString(
        _key(nodeNum), '${point.latitude},${point.longitude},$accuracyM,$t');
    return true;
  }

  BaseLocation? load(int nodeNum) {
    final raw = _prefs.getString(_key(nodeNum));
    if (raw == null) return null;
    final p = raw.split(',');
    if (p.length != 4) return null;
    final lat = double.tryParse(p[0]), lon = double.tryParse(p[1]);
    final acc = double.tryParse(p[2]), t = int.tryParse(p[3]);
    if (lat == null || lon == null || acc == null || t == null) return null;
    return BaseLocation(LatLng(lat, lon),
        accuracyM: acc, at: DateTime.fromMillisecondsSinceEpoch(t));
  }

  Future<void> clear(int nodeNum) => _prefs.remove(_key(nodeNum));

  /// Keys this store uses (kept by "Erase all app data", like the roles:
  /// they describe the radios, not recorded data).
  static bool isKey(String k) => k.startsWith('base_loc_');
}
