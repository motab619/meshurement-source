// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../data/database/app_database.dart';
import 'export/csv_v2.dart';
import 'export/export_data.dart';
import 'export/geojson.dart';
import 'export/kml.dart';
import 'export/meshtastic_csv.dart';
import 'rig_math.dart';
import '../utils/app_info.dart';

/// Output formats.
enum ExportFormat {
  csvV2('CSV (full data)', 'csv'),
  meshtasticCsv('CSV (Meshtastic range test layout)', 'csv'),
  geoJson('GeoJSON (QGIS, web maps)', 'geojson'),
  kml('KML (Google Earth)', 'kml');

  final String label;
  final String extension;
  const ExportFormat(this.label, this.extension);

  /// Keeps the two CSV layouts from overwriting each other's file.
  String get nameSuffix =>
      this == ExportFormat.meshtasticCsv ? '_rangetest' : '';

  String render(Iterable<SessionExport> sessions, {String name = ''}) {
    switch (this) {
      case ExportFormat.csvV2:
        return buildCsvV2(sessions);
      case ExportFormat.meshtasticCsv:
        return buildMeshtasticCsv(sessions);
      case ExportFormat.geoJson:
        return buildGeoJson(sessions);
      case ExportFormat.kml:
        return buildKml(sessions, name: name.isEmpty ? AppInfo.displayName : name);
    }
  }
}

/// Bumped when the zip layout or CSV columns change incompatibly.
const exportFormatVersion = 2;

/// Writes exports under `Documents/Exports/` (visible in the Files app).
class CsvExportService {
  final AppDatabase _db;
  final Future<String> Function() _appVersion;
  final Future<Directory> Function() _documentsDir;

  CsvExportService({
    required AppDatabase db,
    Future<String> Function()? appVersion,
    Future<Directory> Function()? documentsDir,
  })  : _db = db,
        _appVersion = appVersion ?? _packageVersion,
        _documentsDir = documentsDir ?? getApplicationDocumentsDirectory;

  static Future<String> _packageVersion() async {
    final i = await PackageInfo.fromPlatform();
    return '${i.version}+${i.buildNumber}';
  }

  /// Export one session. Returns the file path.
  Future<String> exportSession(
    int sessionId, {
    String? fileName,
    ExportFormat format = ExportFormat.csvV2,
  }) async {
    final data = await ExportLoader(_db).session(sessionId);
    final session = data?.session;
    final name = fileName ??
        (session == null
            ? 'session-$sessionId'
            : csvFileName(
                mapName: data!.mapName,
                sessionName: session.name,
                startedAt: session.startedAt.toLocal(),
                preset: session.loraPreset,
                sessionId: sessionId,
              ));
    final text =
        format.render([if (data != null) data], name: session?.name ?? '');
    return _write('$name${format.nameSuffix}.${format.extension}', text);
  }

  /// One session rendered in [format], as text (nothing written). Throws
  /// when the session does not exist. The bench reads exports this way.
  Future<String> renderSession(
    int sessionId, {
    ExportFormat format = ExportFormat.csvV2,
  }) async {
    final data = await ExportLoader(_db).session(sessionId);
    if (data == null) throw StateError('No such session: $sessionId');
    return format.render([data], name: data.session.name);
  }

  /// The `maps.json` text of [exportAll], for every map or just [mapId].
  Future<String> mapsJson({int? mapId}) async {
    final loader = ExportLoader(_db);
    final maps = mapId == null
        ? await loader.allMaps()
        : [
            await loader.map(mapId) ??
                (throw StateError('No such map: $mapId'))
          ];
    return _mapsJsonText(maps);
  }

  static const _enc = JsonEncoder.withIndent('  ');

  String _mapsJsonText(List<MapExport> maps) =>
      _enc.convert({'maps': [for (final m in maps) _mapJson(m)]});

  /// Export every session of a coverage map into one file.
  Future<String> exportMap(
    int mapId, {
    ExportFormat format = ExportFormat.csvV2,
  }) async {
    final data = await ExportLoader(_db).map(mapId);
    if (data == null) throw StateError('No such map: $mapId');
    final text = format.render(data.sessions, name: data.map.name);
    return _write(
        '${mapFileName(data.map.name, mapId)}${format.nameSuffix}.${format.extension}',
        text);
  }

  /// Everything: a zip with `manifest.json`, `maps.json`, one CSV v2 per
  /// session (`sessions/`) and one GeoJSON per map (`maps/`).
  Future<String> exportAll() async {
    final maps = await ExportLoader(_db).allMaps();
    final createdUtc = DateTime.now().toUtc();
    final version = await _appVersion();
    final zip = Archive();
    final files = <String>[];
    void add(String name, String content) {
      files.add(name);
      zip.addFile(ArchiveFile.bytes(name, utf8.encode(content)));
    }

    const enc = _enc;
    add('maps.json', _mapsJsonText(maps));
    for (final m in maps) {
      add('maps/${mapFileName(m.map.name, m.map.id)}.geojson',
          buildGeoJson(m.sessions));
      for (final s in m.sessions) {
        final name = csvFileName(
          mapName: m.map.name,
          sessionName: s.session.name,
          startedAt: s.session.startedAt.toLocal(),
          preset: s.session.loraPreset,
          sessionId: s.session.id,
        );
        add('sessions/$name.csv', buildCsvV2([s]));
      }
    }
    final manifest = enc.convert({
      'app': AppInfo.displayName,
      'app_version': version,
      'created_utc': createdUtc.toIso8601String(),
      'format_version': exportFormatVersion,
      'csv_columns': csvV2Header,
      'files': [...files, 'manifest.json'],
    });
    zip.addFile(ArchiveFile.bytes('manifest.json', utf8.encode(manifest)));

    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${createdUtc.year}${two(createdUtc.month)}${two(createdUtc.day)}'
        '-${two(createdUtc.hour)}${two(createdUtc.minute)}${two(createdUtc.second)}';
    final bytes = ZipEncoder().encode(zip);
    return _writeBytes('meshurement-export_$stamp.zip', bytes);
  }

  Map<String, Object?> _mapJson(MapExport m) => {
        'id': m.map.id,
        'name': m.map.name,
        'description': m.map.description,
        'created_utc': m.map.createdAt.toUtc().toIso8601String(),
        'color_metric': m.map.colorMetric,
        'signal_direction': m.map.signalDirection,
        'base_lat': m.map.baseLat,
        'base_lon': m.map.baseLon,
        // The newest session's base radio; each session lists its own.
        'base_node': _nodeJson(m.baseNode),
        'sessions': [
          for (final s in m.sessions)
            {
              'id': s.session.id,
              'name': s.session.name,
              'started_utc': s.session.startedAt.toUtc().toIso8601String(),
              'ended_utc': s.session.endedAt?.toUtc().toIso8601String(),
              'lora_preset': s.session.loraPreset,
              'protocol': s.session.protocol,
              'ping_interval_sec': s.session.pingIntervalSec,
              'packet_airtime_ms': s.session.packetAirtimeMs,
              'range_test_active': s.session.rangeTestActive,
              'event_count': s.heardEvents.length,
              'mobile_rig': RigSpec.decode(s.session.mobileRigJson)?.name,
              'base_rig': RigSpec.decode(s.session.baseRigJson)?.name,
              'hw_antenna': s.session.hwAntenna,
              'hw_node_model': s.session.hwNodeModel,
              'hw_notes': s.session.hwNotes,
              'radio_air_util_tx_pct': s.session.radioAirUtilTx,
              'radio_channel_util_pct': s.session.radioChannelUtil,
              'beacon_kind': s.session.beaconKind,
              'beacon_interval_sec': s.session.beaconIntervalSec,
              'distance_m': sessionDistanceM(s),
              // Radio settings beyond the preset (schema v9); null = unknown.
              'region': s.session.region,
              'frequency_slot': s.session.frequencySlot,
              'frequency_mhz': s.session.frequencyMhz,
              'tx_power_dbm': s.session.txPowerDbm,
              'hop_limit': s.session.hopLimit,
              'base_node': _nodeJson(s.baseNode),
            },
        ],
      };

  Map<String, Object?>? _nodeJson(Node? n) => n == null
      ? null
      : {
          'node_id': nodeIdHex(n.nodeId),
          'node_num': n.nodeId,
          'long_name': n.longName,
          'short_name': n.shortName,
          'hw_model': n.hwModel,
        };

  Future<String> _write(String fileName, String content) async =>
      _writeBytes(fileName, utf8.encode(content));

  Future<String> _writeBytes(String fileName, List<int> bytes) async {
    final docs = await _documentsDir();
    final dir = Directory(p.join(docs.path, 'Exports'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes);
    return file.path;
  }
}

/// File name stem for a whole-map export, e.g. `Park_map3`.
String mapFileName(String mapName, int mapId) {
  final c = mapName
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final short = c.length <= 30 ? c : c.substring(0, 30);
  return [if (short.isNotEmpty) short, 'map$mapId'].join('_');
}

/// Readable, sortable export name, e.g.
/// `Park_Walk-to-the-store_2026-10-15_2224_MediumFast` (no extension).
/// Re-exporting a session gives the same name, so it replaces the old file.
String csvFileName({
  required String mapName,
  required String sessionName,
  required DateTime startedAt,
  required String preset,
  int? sessionId,
}) {
  // Letters and digits only, at most 30 characters (so the date survives).
  String clean(String s) {
    final c = s
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return c.length <= 30
        ? c
        : c.substring(0, 30).replaceAll(RegExp(r'-+$'), '');
  }

  String two(int n) => n.toString().padLeft(2, '0');
  final when = '${startedAt.year}-${two(startedAt.month)}-'
      '${two(startedAt.day)}_${two(startedAt.hour)}${two(startedAt.minute)}';
  // MEDIUM_FAST → MediumFast
  final presetShort = preset
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0] + w.substring(1).toLowerCase())
      .join();
  final parts = [
    clean(mapName),
    clean(sessionName),
    when,
    presetShort,
    if (sessionId != null) 's$sessionId',
  ].where((p) => p.isNotEmpty);
  return parts.join('_');
}
