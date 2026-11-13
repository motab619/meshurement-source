// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/bench/bench_server.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/proto/meshtastic/admin.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/export/csv_v2.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/services/radio_backup_service.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:mesh_analyzer/services/session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../export/fixture.dart';
import '../fakes/fake_location_backend.dart';
import '../fakes/fake_mesh_radio.dart';
import '../meshtastic/fake_meshtastic_transport.dart';

/// The bench server's commands and state, driven directly (no HTTP): the
/// same services the Mac-side scenarios (`tool/bench/bench/scenarios`)
/// rely on, with the radio faked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const base = 0xa385;

  late AppDatabase db;
  late SharedPreferences prefs;
  late Directory backupsDir;

  Future<ProviderContainer> container(MeshRadio radio,
      {AppDatabase? database}) async {
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(database ?? db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      meshRadioProvider.overrideWithValue(radio),
      gpsServiceProvider
          .overrideWithValue(GpsService(backend: FakeLocationBackend())),
      radioBackupServiceProvider
          .overrideWithValue(RadioBackupService(directory: backupsDir)),
    ]);
    addTearDown(() async {
      await c.read(sessionManagerProvider).endSession();
      c.dispose();
    });
    return c;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backupsDir = Directory.systemTemp.createTempSync('bench_backups');
    addTearDown(() async {
      await db.close();
      backupsDir.deleteSync(recursive: true);
    });
  });

  group('state and session', () {
    late FakeMeshRadio radio;
    late BenchServer server;
    late ProviderContainer c;
    late int mapId;

    setUp(() async {
      radio = FakeMeshRadio(
          myNodeId: 0x1234, currentPreset: MeshtasticPresets.mediumFast);
      radio.nodes[base] = const RadioNode(
          num: base, longName: 'MeshTest Base', hwModel: 'HELTEC_V3');
      await radio.connect(const RadioDescriptor(id: 'M', name: 'MOBL_1234'));
      addTearDown(radio.dispose);
      c = await container(radio);
      await RadioRoles(prefs).assign(RadioRole.base, nodeNum: base);
      await RadioRoles(prefs).assign(RadioRole.mobile, nodeNum: 0x1234);
      server = BenchServer(c.read);
      mapId = await server.runCommand('map.create',
          {'name': 'Bench', 'baseLat': 33.65, 'baseLon': -116.3}) as int;
    });

    test('/state carries radio, roles, range and beacon', () {
      final s = server.state();
      final r = s['radio'] as Map;
      expect(r['ready'], isTrue);
      expect(r['onPublicChannel'], isFalse);
      expect(r['preset'], 'MEDIUM_FAST');
      expect((s['roles'] as Map)['base'], base);
      expect((s['roles'] as Map)['mobile'], 0x1234);
      expect(s['session'], isNull);
      expect(s['range'], 'unknown');
      expect((s['beacon'] as Map)['active'], isFalse);
      expect((s['app'] as Map)['bench'], isTrue);
    });

    test('session.start refuses on the public channel, then works',
        () async {
      radio.onPublicChannel = true;
      expect(server.state()['radio'], containsPair('onPublicChannel', true));
      await expectLater(
          server.runCommand('session.start', {'mapId': mapId}),
          throwsA(isA<SessionStartError>()
              .having((e) => e.message, 'message', contains('public channel'))));
      expect(server.state()['session'], isNull);

      radio.onPublicChannel = false;
      final id = await server.runCommand(
          'session.start', {'mapId': mapId, 'pingIntervalSec': 10}) as int;
      final s = server.state()['session'] as Map;
      expect(s['id'], id);
      expect(s['mapId'], mapId);
      expect(s['protocol'], 'meshtastic');
      expect(s['loraPreset'], 'MEDIUM_FAST');
      // Floored by the airtime budget, never below what was asked.
      expect(s['pingIntervalSec'], greaterThanOrEqualTo(10));
      final rows = await server.runCommand('db.query',
          {'sql': 'select ping_interval_sec from sessions where id = $id;'});
      expect((rows as List).single, {'ping_interval_sec': s['pingIntervalSec']});
      expect(await server.runCommand('session.end', {}), isTrue);
      expect(server.state()['session'], isNull);
    });

    test('db.query takes one SELECT only', () async {
      expect(() => server.runCommand('db.query', {'sql': 'delete from sessions'}),
          throwsArgumentError);
      expect(
          () => server.runCommand(
              'db.query', {'sql': 'select 1; delete from sessions'}),
          throwsArgumentError);
      expect(await server.runCommand('db.query', {'sql': ' SELECT 1 AS one '}),
          [{'one': 1}]);
    });

    test('beacon state and event follow the tracker', () async {
      server.hook();
      expect((server.state()['beacon'] as Map)['active'], isFalse);
      final id = await server.runCommand(
          'session.start', {'mapId': mapId, 'pingIntervalSec': 10}) as int;
      expect(id, isPositive);
      final st = await server.runCommand('beacon.state', {}) as Map;
      expect(st['active'], isTrue);
      // A trace-style beacon: three timeouts in a row = absent. (The
      // tracker is the one the server reads, through PacketProcessor.)
      final tracker = c.read(packetProcessorProvider).beacons;
      tracker.start(baseNodeId: base, kind: BeaconKind.trace, intervalSec: 10);
      for (var i = 0; i < 3; i++) {
        tracker.onTraceTimeout(DateTime.now());
      }
      await Future<void>.delayed(Duration.zero);
      expect((server.state()['beacon'] as Map)['absent'], isTrue);
      expect(
          server.events
              .where((e) => e['type'] == 'beacon' && e['absent'] == true),
          hasLength(1));
      expect(server.events.any((e) => e['type'] == 'link'), isTrue);
      await server.stop();
    });

    test('radio.reconnect drops and re-opens the same radio', () async {
      final r = await server.runCommand('radio.reconnect', {}) as Map;
      expect(r['ready'], isTrue);
      expect(radio.descriptor!.id, 'M');
      // No radio and no mobile device remembered: a clear error.
      radio.descriptor = null;
      await expectLater(server.runCommand('radio.reconnect', {}),
          throwsA(isA<StateError>()));
    });

    test('prefs.set / prefs.get round trip', () async {
      await server.runCommand(
          'prefs.set', {'key': 'out_of_range_timeout_sec', 'value': 30});
      expect(
          await server.runCommand('prefs.get', {'key': 'out_of_range_timeout_sec'}),
          30);
      await server.runCommand(
          'prefs.set', {'key': 'out_of_range_timeout_sec', 'value': null});
      expect(
          await server.runCommand('prefs.get', {'key': 'out_of_range_timeout_sec'}),
          isNull);
    });
  });

  group('exports', () {
    late ExportFixture f;
    late BenchServer server;

    setUp(() async {
      f = await ExportFixture.create();
      addTearDown(f.db.close);
      final radio = FakeMeshRadio();
      addTearDown(radio.dispose);
      server = BenchServer((await container(radio, database: f.db)).read);
    });

    List<List<dynamic>> parse(String csv) => const CsvToListConverter(eol: '\n')
        .convert(csv.replaceAll('\r\n', '\n'));

    test('export.session returns CSV v2 with every column and row', () async {
      final text = await server
          .runCommand('export.session', {'sessionId': f.session1}) as String;
      final rows = parse(text);
      expect(rows.first, csvV2Header);
      expect(rows.first.last, 'uplink_snr');
      final count = await server.runCommand('db.query', {
        'sql': 'select count(*) n from packet_events where session_id = ${f.session1}'
      }) as List;
      expect(rows.length - 1, (count.single as Map)['n']);
      final h = rows.first.cast<String>();
      expect(rows[1][h.indexOf('session_region')], 'US');
      expect(rows[1][h.indexOf('session_tx_power_dbm')], 27);
    });

    test('other formats and a missing session', () async {
      final rt = await server.runCommand('export.session',
          {'sessionId': f.session1, 'format': 'meshtasticCsv'}) as String;
      expect(rt, isNotEmpty);
      final geo = jsonDecode(await server.runCommand('export.session',
          {'sessionId': f.session1, 'format': 'geoJson'}) as String) as Map;
      expect(geo['type'], 'FeatureCollection');
      await expectLater(server.runCommand('export.session', {'sessionId': 999}),
          throwsA(isA<StateError>()));
    });

    test('export.mapsJson lists the map and its sessions', () async {
      final j = jsonDecode(await server
          .runCommand('export.mapsJson', {'mapId': f.mapId}) as String) as Map;
      final maps = j['maps'] as List;
      expect(maps, hasLength(1));
      final m = maps.single as Map;
      expect(m['id'], f.mapId);
      final sessions = (m['sessions'] as List).cast<Map>();
      expect(sessions.map((s) => s['id']), [f.session1, f.session2]);
      expect(sessions.first['event_count'], 4);
      expect(sessions.first['region'], 'US');
      // All maps when no id is given.
      final all = jsonDecode(
          await server.runCommand('export.mapsJson', {}) as String) as Map;
      expect((all['maps'] as List), hasLength(1));
    });
  });

  group('backups', () {
    const node = 0x73eed5b5;
    late MeshtasticRadio radio;
    late FakeMeshtasticTransport t;
    late BenchServer server;
    late RadioBackupService service;

    setUp(() async {
      t = FakeMeshtasticTransport(myNodeNum: node, nodes: [
        pb.NodeInfo(
            num: node, user: pb.User(longName: 'Pocket', shortName: 'PKT')),
      ]);
      radio = MeshtasticRadio(transport: t);
      await radio.connect(const RadioDescriptor(id: 'M', name: 'PKT_d5b5'));
      addTearDown(radio.dispose);
      final c = await container(radio);
      service = c.read(radioBackupServiceProvider);
      await RadioRoles(prefs).assign(RadioRole.mobile, nodeNum: node);
      server = BenchServer(c.read);
    });

    test('backups.list shows the original first saved for a node', () async {
      expect(await server.runCommand('backups.list', {}), isEmpty);
      await service.save(radio, reason: 'Before Radio Setup');
      final list = await server.runCommand('backups.list', {}) as List;
      final b = list.single as Map;
      expect(b['nodeNum'], node);
      expect(b['nodeId'], '!73eed5b5');
      expect(b['original'], isTrue);
      expect(b['protocol'], 'meshtastic');
      expect(b['preset'], 'LONG_FAST');
      expect(b['channels'], contains('MeshTest'));
    });

    test('backups.restoreOriginal writes it back and clears the role',
        () async {
      await service.save(radio, reason: 'Before Radio Setup');
      final r = await server.runCommand('backups.restoreOriginal', {}) as Map;
      expect(r['rolesCleared'], isTrue);
      expect(r['reboots'], isTrue);
      expect((r['steps'] as List), isNotEmpty);
      expect((r['backup'] as Map)['original'], isTrue);
      final kinds = t.localAdmin.map((m) => m.whichPayloadVariant()).toList();
      expect(kinds, contains(pb.AdminMessage_PayloadVariant.beginEditSettings));
      expect(kinds, contains(pb.AdminMessage_PayloadVariant.setChannel));
      expect(kinds.last, pb.AdminMessage_PayloadVariant.commitEditSettings);
      expect(RadioRoles(prefs).nodeOf(RadioRole.mobile), isNull);
      expect(
          server.events.where((e) => e['type'] == 'restore'), isNotEmpty);
    });

    test('backups.restoreOriginal without an original is an error', () async {
      await expectLater(
          server.runCommand('backups.restoreOriginal', {'nodeNum': 1}),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('No original'))));
    });
  });
}
