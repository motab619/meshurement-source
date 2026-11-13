// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/services/csv_export_service.dart';

import 'fixture.dart';

void main() {
  late ExportFixture f;
  late Directory tmp;
  late CsvExportService service;

  setUp(() async {
    f = await ExportFixture.create();
    tmp = await Directory.systemTemp.createTemp('export_test');
    service = CsvExportService(
      db: f.db,
      appVersion: () async => '9.9.9+1',
      documentsDir: () async => tmp,
    );
  });
  tearDown(() async {
    await f.db.close();
    await tmp.delete(recursive: true);
  });

  test('session export goes to Documents/Exports with _s<id> in the name',
      () async {
    final path = await service.exportSession(f.session1);
    expect(path, contains('/Exports/'));
    expect(path, endsWith('_s${f.session1}.csv'));
    expect(File(path).readAsStringSync(), startsWith('event_id,session_id'));
  });

  test('every format writes a file with the right extension', () async {
    for (final fmt in ExportFormat.values) {
      final one = await service.exportSession(f.session1, format: fmt);
      final map = await service.exportMap(f.mapId, format: fmt);
      expect(one, endsWith('.${fmt.extension}'));
      expect(map, endsWith('.${fmt.extension}'));
      expect(File(map).lengthSync(), greaterThan(0));
    }
    // The two CSV layouts do not overwrite each other.
    final a = await service.exportMap(f.mapId);
    final b =
        await service.exportMap(f.mapId, format: ExportFormat.meshtasticCsv);
    expect(a == b, isFalse);
  });

  test('map export covers all sessions', () async {
    final path = await service.exportMap(f.mapId);
    final lines = File(path).readAsStringSync().trim().split('\r\n');
    expect(lines.length - 1, 5); // 4 events + 1 event in session 2
    expect(path, endsWith('Park_map${f.mapId}.csv'));
  });

  test('export all: zip with manifest, maps.json, per-session CSV, GeoJSON',
      () async {
    final path = await service.exportAll();
    expect(path, endsWith('.zip'));
    final zip = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
    final names = zip.files.map((x) => x.name).toList();
    expect(names, containsAll(['manifest.json', 'maps.json']));
    expect(names.where((n) => n.startsWith('sessions/') && n.endsWith('.csv')),
        hasLength(2));
    expect(names.where((n) => n.startsWith('maps/') && n.endsWith('.geojson')),
        hasLength(1));
    String read(String n) =>
        utf8.decode(zip.files.firstWhere((x) => x.name == n).content);
    final manifest = jsonDecode(read('manifest.json')) as Map;
    expect(manifest['app_version'], '9.9.9+1');
    expect(manifest['format_version'], exportFormatVersion);
    expect(DateTime.parse(manifest['created_utc'] as String).isUtc, isTrue);
    expect(manifest['files'], containsAll(names));
    final maps = jsonDecode(read('maps.json')) as Map;
    final m = (maps['maps'] as List).single as Map;
    expect(m['name'], 'Park');
    expect(m['base_node']['node_id'], '!00000002');
    expect(m['sessions'], hasLength(2));
    expect((m['sessions'] as List).first['distance_m'],
        inInclusiveRange(280, 300));
    final first = (m['sessions'] as List).first as Map;
    expect(first['region'], 'US');
    expect(first['frequency_slot'], 20);
    expect(first['frequency_mhz'], 906.875);
    expect(first['tx_power_dbm'], 27);
    expect(first['hop_limit'], 3);
    final second = (m['sessions'] as List)[1] as Map;
    expect(second['tx_power_dbm'], isNull);
  });
}
