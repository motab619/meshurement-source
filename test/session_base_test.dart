// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/base_location.dart';
import 'package:mesh_analyzer/services/base_node.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/services/map_base_migration.dart';
import 'package:mesh_analyzer/services/session_manager.dart';
import 'package:mesh_analyzer/services/terrain/terrain_settings.dart';
import 'package:mesh_analyzer/ui/widgets/session_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_location_backend.dart';
import 'fakes/fake_mesh_radio.dart';

/// The session, not the map, owns the base radio (schema v8). Field
/// failure 2026-10-27: a map's fixed base outlived Radio Setup, so three
/// sessions pinged a switched-off radio.
void main() {
  group('schema v8 migration', () {
    test('maps get a nullable base and a location; sessions their base',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
        raw.execute('''
          CREATE TABLE nodes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            node_id INTEGER NOT NULL UNIQUE,
            long_name TEXT NOT NULL DEFAULT '',
            short_name TEXT NOT NULL DEFAULT '',
            user_label TEXT NULL,
            hw_model TEXT NOT NULL DEFAULT '',
            first_seen_at INTEGER NOT NULL,
            last_heard_at INTEGER NOT NULL,
            last_lat REAL NULL,
            last_lon REAL NULL
          )''');
        raw.execute('''
          CREATE TABLE coverage_maps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            base_node_id INTEGER NOT NULL REFERENCES nodes (id),
            created_at INTEGER NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            color_metric TEXT NOT NULL DEFAULT 'snr',
            signal_direction TEXT NOT NULL DEFAULT 'rx'
          )''');
        raw.execute('''
          CREATE TABLE sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            coverage_map_id INTEGER NOT NULL,
            name TEXT NOT NULL DEFAULT '',
            started_at INTEGER NOT NULL,
            ended_at INTEGER NULL,
            is_active INTEGER NOT NULL DEFAULT 0,
            remote_node_id INTEGER NULL,
            hw_antenna TEXT NOT NULL DEFAULT '',
            hw_node_model TEXT NOT NULL DEFAULT '',
            hw_notes TEXT NOT NULL DEFAULT '',
            lora_preset TEXT NOT NULL DEFAULT '',
            protocol TEXT NOT NULL DEFAULT 'meshtastic',
            ping_interval_sec INTEGER NOT NULL DEFAULT 0,
            packet_airtime_ms REAL NOT NULL DEFAULT 0,
            mobile_rig_id INTEGER NULL,
            base_rig_id INTEGER NULL,
            mobile_rig_json TEXT NULL,
            base_rig_json TEXT NULL,
            radio_air_util_tx REAL NULL,
            radio_channel_util REAL NULL,
            beacon_kind TEXT NOT NULL DEFAULT '',
            beacon_interval_sec INTEGER NOT NULL DEFAULT 0,
            range_test_active INTEGER NOT NULL DEFAULT 0,
            packet_count INTEGER NOT NULL DEFAULT 0
          )''');
        // As of v7 (schema v10 adds uplink_snr to it).
        raw.execute('''
          CREATE TABLE packet_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            timestamp INTEGER NOT NULL,
            direction TEXT NOT NULL,
            source_node_id INTEGER NOT NULL,
            rx_snr REAL NULL,
            rx_rssi INTEGER NULL,
            hop_count INTEGER NOT NULL DEFAULT 0,
            rx_lat REAL NULL,
            rx_lon REAL NULL,
            rx_alt REAL NULL,
            gps_accuracy REAL NULL,
            packet_type TEXT NOT NULL,
            mesh_packet_id INTEGER NULL,
            channel_index INTEGER NOT NULL DEFAULT 0,
            via_mqtt INTEGER NOT NULL DEFAULT 0,
            seq INTEGER NULL,
            source_kind TEXT NOT NULL DEFAULT 'passive',
            base_channel_util REAL NULL
          )''');
        raw.execute("INSERT INTO nodes (node_id, long_name, first_seen_at, "
            "last_heard_at, last_lat, last_lon) "
            "VALUES (48879, 'Old Base', 1, 1, 33.5, -116.2)");
        raw.execute("INSERT INTO nodes (node_id, long_name, first_seen_at, "
            "last_heard_at) VALUES (51966, 'No GPS', 1, 1)");
        raw.execute("INSERT INTO coverage_maps (name, base_node_id, "
            "created_at, description) VALUES ('Park', 1, 1700000000, 'd')");
        raw.execute("INSERT INTO coverage_maps (name, base_node_id, "
            "created_at) VALUES ('Hill', 2, 1700000001)");
        raw.execute("INSERT INTO sessions (coverage_map_id, name, started_at) "
            "VALUES (1, 'old', 1700000000)");
        raw.execute('PRAGMA user_version = 7');
      }));
      addTearDown(db.close);

      expect(db.schemaVersion, 11);
      final maps = await db.getAllCoverageMaps();
      final park = maps.firstWhere((m) => m.name == 'Park');
      expect(park.baseNodeId, 1);
      expect(park.description, 'd');
      expect((park.baseLat, park.baseLon), (33.5, -116.2));
      final hill = maps.firstWhere((m) => m.name == 'Hill');
      expect(hill.baseLat, isNull);

      final s = (await db.getSessionById(1))!;
      expect(s.baseNodeId, 1);
      expect(await db.baseMeshNodeIdForSession(s), 48879);

      // New maps have no base radio.
      final id = await db.createCoverageMap(name: 'New');
      expect((await db.getCoverageMap(id))!.baseNodeId, isNull);
    });
  });

  group('MapBaseMigration', () {
    test('placed base wins, Radio Setup location fills, opt-out respected',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final withPos = await db.upsertNode(nodeId: 10);
      await db.updateNodePosition(10, 1, 2);
      final noPos = await db.upsertNode(nodeId: 11);
      final placed = await db.createCoverageMap(
          name: 'placed', baseNodeId: withPos, baseLat: 1, baseLon: 2);
      final setup =
          await db.createCoverageMap(name: 'setup', baseNodeId: noPos);
      final declined =
          await db.createCoverageMap(name: 'declined', baseNodeId: noPos);
      await TerrainSettings.saveUserBase(prefs, placed, const LatLng(5, 6));
      await BaseLocationStore(prefs)
          .record(11, const LatLng(7, 8), accuracyM: 5);
      await TerrainSettings.saveBaseOptOut(prefs, declined, true);

      await MapBaseMigration.run(prefs, db);
      Future<(double?, double?)> loc(int id) async {
        final m = (await db.getCoverageMap(id))!;
        return (m.baseLat, m.baseLon);
      }

      expect(await loc(placed), (5.0, 6.0));
      expect(await loc(setup), (7.0, 8.0));
      expect(await loc(declined), (null, null));

      // Once only.
      await TerrainSettings.saveUserBase(prefs, setup, const LatLng(9, 9));
      await MapBaseMigration.run(prefs, db);
      expect(await loc(setup), (7.0, 8.0));
    });
  });

  group('startSession', () {
    late AppDatabase db;
    late FakeMeshRadio radio;
    late ProviderContainer container;
    late int mapId;
    late int oldBase;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      radio = FakeMeshRadio(myNodeId: 1);
      radio.nodes[0xa385] = const RadioNode(
          num: 0xa385, longName: 'MeshTest Base', hwModel: 'HELTEC_V3');
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(radio),
        gpsServiceProvider
            .overrideWithValue(GpsService(backend: FakeLocationBackend())),
      ]);
      // An old map whose base was another radio (now switched off).
      oldBase = await db.upsertNode(nodeId: 0x5555, longName: 'MeshTest Base');
      mapId = await db.createCoverageMap(name: 'Polo', baseNodeId: oldBase);
      addTearDown(() async {
        await container.read(sessionManagerProvider).endSession();
        container.dispose();
        await radio.dispose();
        await db.close();
      });
    });

    test('stores the chosen base and monitors it, not the map\'s', () async {
      final sessions = container.read(sessionManagerProvider);
      final s = await sessions.startSession(
          coverageMapId: mapId, baseMeshNodeId: 0xa385, pingIntervalSec: 30);

      // The Nodes row is created from what the radio knows.
      final node = (await db.getNodeByMeshId(0xa385))!;
      expect(node.longName, 'MeshTest Base');
      expect(node.hwModel, 'HELTEC_V3');
      expect(s.baseNodeId, node.id);
      expect((await db.getSessionById(s.id))!.baseNodeId, node.id);

      final processor = container.read(packetProcessorProvider);
      expect(processor.otherRadios.baseNodeId, 0xa385);
      expect(processor.beacons.baseNodeId, 0xa385);
      expect(container.read(outOfRangeMonitorProvider).baseNodeId, 0xa385);
      expect(
          container.read(activeProbeServiceProvider).targetMeshNodeId, 0xa385);
    });

    test('a session from before v8 follows its map\'s base', () async {
      final id = await db.createSession(coverageMapId: mapId);
      final s = (await db.getSessionById(id))!;
      expect(s.baseNodeId, isNull);
      expect(await db.baseMeshNodeIdForSession(s), 0x5555);
    });

    test('refuses without a base, or with our own radio as base', () async {
      final sessions = container.read(sessionManagerProvider);
      await expectLater(
          sessions.startSession(coverageMapId: mapId, baseMeshNodeId: null),
          throwsA(isA<SessionStartError>()
              .having((e) => e.message, 'message', contains('Node Setup'))));
      await expectLater(
          sessions.startSession(coverageMapId: mapId, baseMeshNodeId: 1),
          throwsA(isA<SessionStartError>()
              .having((e) => e.message, 'message', contains('ping itself'))));
      expect(sessions.activeSession, isNull);
    });

    test('knownBaseNodeNum falls back to the newest session\'s base', () async {
      await container
          .read(sessionManagerProvider)
          .startSession(coverageMapId: mapId, baseMeshNodeId: 0xa385);
      final prefs = container.read(sharedPreferencesProvider);
      expect(await knownBaseNodeNum(prefs, db), 0xa385);
      expect(await db.mapBaseNodeNums(), {0x5555, 0xa385});
    });
  });

  group('start form', () {
    Future<(AppDatabase, int)> pump(WidgetTester tester,
        {required Map<String, Object> prefsInit}) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(prefsInit);
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final radio = FakeMeshRadio(
          myNodeId: 0x1234abcd, currentPreset: MeshtasticPresets.longFast);
      radio.nodes[0xa385] = const RadioNode(
          num: 0xa385, longName: 'MeshTest Base', hwModel: 'HELTEC_V3');
      await radio.connect(const RadioDescriptor(id: 'A', name: 'Pocket'));
      late int mapId;
      await tester.runAsync(() async {
        final old = await db.upsertNode(
            nodeId: 0x5555, longName: 'MeshTest Base', hwModel: 'RAK4631');
        mapId = await db.createCoverageMap(name: 'Polo');
        await db.into(db.sessions).insert(SessionsCompanion.insert(
            coverageMapId: mapId,
            startedAt: DateTime(2026, 10, 26),
            baseNodeId: Value(old)));
      });

      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          meshRadioProvider.overrideWithValue(radio),
          activeSessionProvider.overrideWith((ref) => Stream.value(null)),
          meshLinkStateProvider
              .overrideWith((ref) => Stream.value(RadioConnectionState.ready)),
        ],
        child: const MaterialApp(home: Scaffold(body: SessionPanel())),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      return (db, mapId);
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    }

    testWidgets('shows the Radio Setup base and notes a different earlier one',
        (tester) async {
      await pump(tester, prefsInit: {baseNodePrefKey: 0xa385});
      expect(find.textContaining('MeshTest Base · Heltec V3 · !a385'),
          findsWidgets);
      expect(find.byKey(const ValueKey('no-setup-base')), findsNothing);
      final note = find.byKey(const ValueKey('base-mismatch'));
      expect(note, findsOneWidget);
      expect(
          tester.widget<Text>(note).data,
          'Earlier sessions on this map used MeshTest Base · RAK4631 · !5555. '
          'Comparisons across sessions assume the same base position.');
      // Hardware profiles are optional, folded away until opened.
      expect(find.text('Mobile hardware profile'), findsNothing);
      await tester.tap(find.text('Hardware profiles (optional)'));
      await tester.pumpAndSettle();
      expect(find.text('Mobile hardware profile'), findsOneWidget);
      expect(find.text('Base hardware profile'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('no Radio Setup base: warns and offers a picker',
        (tester) async {
      await pump(tester, prefsInit: {});
      expect(find.byKey(const ValueKey('no-setup-base')), findsOneWidget);
      expect(find.text('Or pick the base node (the one that stays put)'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('base-mismatch')), findsNothing);

      // Picking a base clears the warning; the closed field shows the name
      // only (the menu entry's second line spilled below the border).
      final field = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('base-pick-'));
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('MeshTest Base').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('no-setup-base')), findsNothing);
      expect(
          find.descendant(of: field, matching: find.text('MeshTest Base')),
          findsOneWidget);
      expect(
          find.descendant(of: field, matching: find.textContaining('!a385')),
          findsNothing);
      await unmount(tester);
    });
  });
}
