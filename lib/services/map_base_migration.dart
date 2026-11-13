// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/app_database.dart';
import 'base_location.dart';
import 'diag_log.dart';
import 'terrain/terrain_settings.dart';

/// One-time back-fill of each map's own base location (schema v8) from
/// what lived in SharedPreferences before, which the drift migration can't
/// read. Order: the base the user placed on the map, the base node's own
/// position (already copied by the migration), the location Radio Setup
/// remembered for that base (unless the user declined it for the map).
class MapBaseMigration {
  static const doneKey = 'map_base_location_v8_done';

  static Future<void> run(SharedPreferences prefs, AppDatabase db) async {
    if (prefs.getBool(doneKey) ?? false) return;
    final nodes = {for (final n in await db.getAllNodes()) n.id: n};
    var filled = 0;
    for (final m in await db.getAllCoverageMaps()) {
      final user = TerrainSettings.loadUserBase(prefs, m.id);
      if (user != null) {
        await db.setMapBaseLocation(m.id, user.latitude, user.longitude);
        filled++;
        continue;
      }
      if (m.baseLat != null && m.baseLon != null) continue;
      final base = nodes[m.baseNodeId];
      if (base == null) continue;
      if (base.lastLat != null && base.lastLon != null) {
        await db.setMapBaseLocation(m.id, base.lastLat, base.lastLon);
        filled++;
        continue;
      }
      if (TerrainSettings.loadBaseOptOut(prefs, m.id)) continue;
      final saved = BaseLocationStore(prefs).load(base.nodeId);
      if (saved != null) {
        await db.setMapBaseLocation(
            m.id, saved.point.latitude, saved.point.longitude);
        filled++;
      }
    }
    if (filled > 0) {
      DiagLog.instance
          .log('maps', 'base location back-filled on $filled map(s)');
    }
    await prefs.setBool(doneKey, true);
  }
}
