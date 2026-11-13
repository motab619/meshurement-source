// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/app_database.dart';
import '../data/radio/mesh_radio.dart';
import '../data/radio/meshtastic/meshtastic_radio.dart';
import '../data/radio/switchable_radio.dart';
import 'packet_processor.dart';
import 'pro_entitlement.dart';
import 'radio_profile_service.dart';
import 'radio_roles.dart';
import 'diag_log.dart';
import 'rig_comparison.dart';
import 'session_manager.dart';
import 'signal_history.dart';

/// Settings → Data: lets the user remove what the app has recorded.
///
/// Only [clearNodes] touches a radio (the connected one's node list); the
/// rest is app data. Refuses while a session is recording, so the live
/// session never loses rows under it.
class DataEraseService {
  /// Kept by [eraseEverything]: the test channel key (so the radios still
  /// match the app), which radio is the base and which the mobile (how the
  /// radios are configured), and the cached Pro entitlement (a purchase,
  /// not data).
  static const keptPrefs = {
    RadioProfileService.prefKey,
    ...RadioRoles.prefKeys,
    ProEntitlement.cacheKey,
  };

  /// Per-map base location overrides for terrain profiles.
  static const _mapPrefPrefix = 'terrain_base_location_';
  static const _mapOptOutPrefix = 'terrain_base_optout_';

  final AppDatabase _db;
  final SharedPreferences _prefs;
  final PacketProcessor _packets;
  final SignalHistory _history;
  final SessionManager _sessions;
  final MeshRadio? _radio;
  final Future<Directory> Function() _documentsDir;
  final Future<Directory> Function() _supportDir;

  DataEraseService({
    required AppDatabase db,
    required SharedPreferences prefs,
    required PacketProcessor packets,
    required SignalHistory history,
    required SessionManager sessions,
    MeshRadio? radio,
    Future<Directory> Function()? documentsDir,
    Future<Directory> Function()? supportDir,
  })  : _db = db,
        _prefs = prefs,
        _packets = packets,
        _history = history,
        _sessions = sessions,
        _radio = radio,
        _documentsDir = documentsDir ?? getApplicationDocumentsDirectory,
        _supportDir = supportDir ?? getApplicationSupportDirectory;

  /// Erasing is only allowed with no session recording.
  bool get canErase => _sessions.activeSession == null;

  void _checkIdle() {
    if (!canErase) throw StateError('End the current session first');
  }

  /// Make the connected radio forget the nodes it has heard (keeping our
  /// base), and remove nodes no saved map or session uses from the app.
  /// Returns how many the radio forgot (null if no Meshtastic radio is
  /// connected), how many the app removed, and how many it kept because a
  /// map or session still uses them.
  Future<({int? radioForgot, bool baseKept, int removed, int kept})>
      clearNodes() async {
    _checkIdle();
    int? radioForgot;
    var baseKept = false;
    final radio = radioAs<MeshtasticRadio>(_radio);
    if (radio != null && radio.isReady && !radio.isDemo) {
      // Every base we know of: the one Radio Setup configured and every
      // map's base (one guess could be wrong, e.g. if radios swapped roles).
      final keep = <int>{
        if (RadioRoles(_prefs).nodeOf(RadioRole.base) case final b?) b,
        ...await _db.mapBaseNodeNums(),
      }..remove(radio.myNodeId);
      baseKept = keep.isNotEmpty;
      radioForgot = await radio.resetNodeDb(keep: keep);
    }
    final removed = await _db.deleteUnusedNodes();
    _packets.clearNodeCache();
    final kept = (await _db.getAllNodes()).length;
    return (
      radioForgot: radioForgot,
      baseKept: baseKept,
      removed: removed,
      kept: kept,
    );
  }

  /// Remove all coverage maps, sessions, packets and ping results, plus
  /// saved comparisons and per-map settings that pointed at them.
  Future<void> deleteSessionsAndMaps() async {
    _checkIdle();
    await _db.deleteAllMeasurements();
    await _prefs.remove(savedComparisonsKey);
    for (final key in _prefs.getKeys().toList()) {
      if (key.startsWith(_mapPrefPrefix) || key.startsWith(_mapOptOutPrefix)) {
        await _prefs.remove(key);
      }
    }
    _history.clear();
  }

  /// Folders under Documents that [eraseEverything] deletes: radio
  /// backups, and every CSV / GeoJSON / KML / zip export (full GPS tracks;
  /// `CsvExportService` writes them to `Documents/Exports/`).
  static const erasedDocumentDirs = ['radio_backups', 'Exports'];

  /// The diagnostics log (`DiagLog`), in Documents.
  static const diagLogName = 'diag.log';

  /// Remove everything the app has stored: measurements, nodes, rig
  /// profiles, radio backups, exports, the diagnostics log, cached terrain,
  /// the base locations Radio Setup recorded (usually the user's home) and
  /// settings. Keeps [keptPrefs]. The database is vacuumed afterwards so
  /// the deleted rows don't linger in free pages of the file.
  Future<void> eraseEverything() async {
    _checkIdle();
    await _db.deleteAllData();
    for (final key in _prefs.getKeys().toList()) {
      if (!keptPrefs.contains(key)) await _prefs.remove(key);
    }
    for (final name in erasedDocumentDirs) {
      await _deleteDir(_documentsDir, name);
    }
    await _deleteDir(_supportDir, 'elevation_cache');
    await DiagLog.instance.clear();
    // DiagLog finds Documents itself; also remove the file where this
    // service was told Documents is.
    final log = File(p.join((await _documentsDir()).path, diagLogName));
    if (await log.exists()) await log.delete();
    await _db.customStatement('VACUUM');
    _packets.clearNodeCache();
    _history.clear();
  }

  Future<void> _deleteDir(
    Future<Directory> Function() root,
    String name,
  ) async {
    final dir = Directory(p.join((await root()).path, name));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
