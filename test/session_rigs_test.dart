// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/data/radio/switchable_radio.dart';
import 'package:mesh_analyzer/proto/meshtastic/channel.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/services/rig_math.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('startSession stores rig ids, snapshots and legacy hw fields',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    // A pretend connected radio on a private channel (no Bluetooth).
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
          settings: pb.ChannelSettings(name: 'MeshTest', psk: List.filled(32, 7)),
        ),
      ],
    );

    final baseId = await db.upsertNode(nodeId: 2);
    final mapId = await db.createCoverageMap(name: 'm', baseNodeId: baseId);
    final now = DateTime(2026);
    final mobile = await db.insertRigProfile(RigProfilesCompanion.insert(
      name: 'Stubby',
      radioModel: const Value('Seeed T1000-E'),
      antennaName: const Value('Stock'),
      antennaGainDbi: const Value(2),
      createdAt: now,
      updatedAt: now,
    ));
    final base = await db.insertRigProfile(RigProfilesCompanion.insert(
      name: 'Roof',
      antennaGainDbi: const Value(5.8),
      cableType: const Value('lmr400'),
      cableLengthM: const Value(10),
      createdAt: now,
      updatedAt: now,
    ));

    final session = await container.read(sessionManagerProvider).startSession(
          coverageMapId: mapId,
          baseMeshNodeId: 2,
          mobileRigId: mobile,
          baseRigId: base,
        );

    expect(session.mobileRigId, mobile);
    expect(session.baseRigId, base);
    expect(RigSpec.decode(session.mobileRigJson)!.name, 'Stubby');
    expect(RigSpec.decode(session.baseRigJson)!.netGainDb,
        closeTo(5.8 - 1.28, 1e-9));
    expect(session.hwNodeModel, 'Seeed T1000-E');
    expect(session.hwAntenna, 'Stock 2.0 dBi');
    expect(session.loraPreset, 'MEDIUM_FAST');
    expect(session.protocol, 'meshtastic');

    // Without rigs everything stays empty.
    final plain = await container
        .read(sessionManagerProvider)
        .startSession(coverageMapId: mapId, baseMeshNodeId: 2);
    expect(plain.mobileRigId, isNull);
    expect(plain.mobileRigJson, isNull);
    await container.read(sessionManagerProvider).endSession();
  });
}
