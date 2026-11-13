// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/data/radio/switchable_radio.dart';
import 'package:mesh_analyzer/proto/meshtastic/channel.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/data_erase_service.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // DiagLog.clear wants the services binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late SharedPreferences prefs;
  late ProviderContainer container;
  late Directory docs;
  late Directory support;
  late DataEraseService service;
  late int mapId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'test_channel_psk': 'a2V5',
      'pro_entitlement_v1': '{"plan":"lifetime"}',
      'saved_comparisons_v1': '[]',
      'terrain_base_location_1': '33.7,-116.2',
      AppConstants.prefColorMetric: 'rssi',
    });
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    final tmp = await Directory.systemTemp.createTemp('erase_test');
    docs = await Directory('${tmp.path}/docs').create();
    support = await Directory('${tmp.path}/support').create();
    await Directory('${docs.path}/radio_backups').create();
    await File('${docs.path}/radio_backups/b.json').writeAsString('{}');
    await Directory('${support.path}/elevation_cache').create();
    addTearDown(() async {
      container.dispose();
      await db.close();
      await tmp.delete(recursive: true);
    });

    service = DataEraseService(
      db: db,
      prefs: prefs,
      packets: container.read(packetProcessorProvider),
      history: container.read(signalHistoryProvider),
      sessions: container.read(sessionManagerProvider),
      documentsDir: () async => docs,
      supportDir: () async => support,
    );

    // A map with one finished session and a packet from node 4, plus a
    // node (3) that was only heard in passing and one rig profile.
    final base = await db.upsertNode(nodeId: 2);
    await db.upsertNode(nodeId: 3, longName: 'Passer-by');
    final source = await db.upsertNode(nodeId: 4);
    mapId = await db.createCoverageMap(name: 'm', baseNodeId: base);
    final session = await db.createSession(coverageMapId: mapId);
    final tx = await db.insertPacketEvent(PacketEventsCompanion.insert(
      sessionId: session,
      timestamp: DateTime(2026),
      direction: PacketDirection.rx,
      sourceNodeId: source,
      packetType: PacketType.rangeTest,
    ));
    await db.insertPingCorrelation(
        PingCorrelationsCompanion.insert(txEventId: tx));
    await db.endSession(session);
    await db.insertRigProfile(RigProfilesCompanion.insert(
      name: 'Rig',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ));
  });

  Future<List<int>> nodeNums() async =>
      [for (final n in await db.getAllNodes()) n.nodeId]..sort();

  test('clearNodes keeps nodes that maps or packets use', () async {
    expect(await service.clearNodes(), (radioForgot: null, baseKept: false, removed: 1, kept: 2));
    expect(await nodeNums(), [2, 4]);
    expect(await db.getAllCoverageMaps(), hasLength(1));
  });

  test('deleteSessionsAndMaps removes measurements and map settings',
      () async {
    await service.deleteSessionsAndMaps();
    expect(await db.getAllCoverageMaps(), isEmpty);
    expect(await db.select(db.sessions).get(), isEmpty);
    expect(await db.select(db.packetEvents).get(), isEmpty);
    expect(await db.select(db.pingCorrelations).get(), isEmpty);
    expect(prefs.containsKey('saved_comparisons_v1'), isFalse);
    expect(prefs.containsKey('terrain_base_location_1'), isFalse);
    // Nodes, rigs and settings stay; nodes are now all unused.
    expect(await nodeNums(), [2, 3, 4]);
    expect(await db.select(db.rigProfiles).get(), hasLength(1));
    expect(prefs.getString(AppConstants.prefColorMetric), 'rssi');
    expect(await service.clearNodes(), (radioForgot: null, baseKept: false, removed: 3, kept: 0));
  });

  test('eraseEverything keeps only the channel key and Pro', () async {
    await service.eraseEverything();
    expect(await nodeNums(), isEmpty);
    expect(await db.getAllCoverageMaps(), isEmpty);
    expect(await db.select(db.rigProfiles).get(), isEmpty);
    expect(prefs.getKeys(), {'test_channel_psk', 'pro_entitlement_v1'});
    expect(await Directory('${docs.path}/radio_backups').exists(), isFalse);
    expect(await Directory('${support.path}/elevation_cache').exists(), isFalse);
  });

  test('eraseEverything also removes base locations, exports and the log, '
      'keeps the node roles', () async {
    await prefs.setString('base_loc_1234', '33.7,-116.2,10,0');
    await prefs.setInt('base_node_num', 2);
    await Directory('${docs.path}/Exports').create();
    await File('${docs.path}/Exports/walk.csv').writeAsString('lat,lon');
    await File('${docs.path}/diag.log').writeAsString('line');
    await service.eraseEverything();
    expect(prefs.containsKey('base_loc_1234'), isFalse,
        reason: 'usually the user\'s home');
    expect(prefs.getInt('base_node_num'), 2, reason: 'roles are kept');
    expect(await Directory('${docs.path}/Exports').exists(), isFalse);
    expect(await File('${docs.path}/diag.log').exists(), isFalse);
    // The vacuumed database still works.
    expect(await db.getAllCoverageMaps(), isEmpty);
  });

  test('refuses while a session is recording', () async {
    radioAs<MeshtasticRadio>(container.read(meshRadioProvider))!.enterDemo(
      name: 'test',
      myNodeNum: 1,
      nodeInfos: [pb.NodeInfo(num: 1)],
      lora: pb.Config_LoRaConfig(
        usePreset: true,
        modemPreset: pb.Config_LoRaConfig_ModemPreset.MEDIUM_FAST,
      ),
      channelTable: [
        pb.Channel(
          index: 0,
          role: pb.Channel_Role.PRIMARY,
          settings:
              pb.ChannelSettings(name: 'MeshTest', psk: List.filled(32, 7)),
        ),
      ],
    );
    final sessions = container.read(sessionManagerProvider);
    await sessions.startSession(coverageMapId: mapId, baseMeshNodeId: 2);
    expect(service.canErase, isFalse);
    expect(service.eraseEverything, throwsStateError);
    expect(await db.getAllCoverageMaps(), hasLength(1));
    await sessions.endSession();
    expect(service.canErase, isTrue);
  });
}
