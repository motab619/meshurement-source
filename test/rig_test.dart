// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/services/rig_math.dart';

void main() {
  group('rig math', () {
    test('cable table is sane and ordered', () {
      expect(cableTypeFor('lmr400').lossDbPerM, closeTo(0.128, 1e-9));
      expect(cableTypeFor('rg58').lossDbPerM, 0.5);
      expect(cableTypeFor('rg174').lossDbPerM, 0.95);
      expect(cableTypeFor('none').lossDbPerM, 0);
      expect(cableTypeFor('unknown').key, 'none');
      expect(cableTypeFor('lmr600').lossDbPerM,
          lessThan(cableTypeFor('lmr400').lossDbPerM));
      expect(cableTypeFor('lmr240').lossDbPerM,
          lessThan(cableTypeFor('rg58').lossDbPerM));
    });

    test('net gain', () {
      const rig = RigSpec(
        name: 'x',
        antennaGainDbi: 5.8,
        cableType: 'lmr240',
        cableLengthM: 3,
        connectorCount: 2,
      );
      // 5.8 - 3*0.25 - 2*0.1 = 4.85
      expect(rig.netGainDb, closeTo(4.85, 1e-9));
      expect(const RigSpec(name: 'stub', antennaGainDbi: 2).netGainDb, 2);
    });

    test('expected delta', () {
      const a = RigSpec(name: 'a', antennaGainDbi: 5.8);
      const b = RigSpec(name: 'b', antennaGainDbi: 2);
      expect(expectedDeltaDb(a, b), closeTo(3.8, 1e-9));
      expect(expectedDeltaDb(b, a), closeTo(-3.8, 1e-9));
    });

    test('formatGainDb', () {
      expect(formatGainDb(4.44), '+4.4 dB');
      expect(formatGainDb(-1), '-1.0 dB');
      expect(formatGainDb(-0.01), '+0.0 dB');
    });

    test('snapshot JSON round-trips', () {
      const rig = RigSpec(
        id: 3,
        name: 'Base',
        radioModel: 'Heltec V3',
        antennaName: 'Collinear',
        antennaGainDbi: 5.8,
        cableType: 'lmr400',
        cableLengthM: 10,
        connectorCount: 2,
        connectorLossDb: 0.15,
        notes: 'roof',
      );
      final back = RigSpec.decode(rig.encode())!;
      expect(back.toJson(), rig.toJson());
      expect(back.netGainDb, rig.netGainDb);
      expect(RigSpec.decode(null), isNull);
      expect(RigSpec.decode('not json'), isNull);
    });
  });

  group('rig profile queries', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    RigProfilesCompanion rig(String name) => RigProfilesCompanion.insert(
          name: name,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('insert, get, update, archive', () async {
      final id = await db.insertRigProfile(rig('A'));
      final b = await db.insertRigProfile(rig('B'));
      var got = (await db.getRigProfile(id))!;
      expect(got.connectorLossDb, 0.1);
      expect(got.role, 'either');
      expect(got.archived, isFalse);

      await db.updateRigProfile(
          id, const RigProfilesCompanion(antennaGainDbi: Value(5.8)));
      got = (await db.getRigProfile(id))!;
      expect(got.antennaGainDbi, 5.8);
      expect(got.updatedAt.isAfter(DateTime(2026, 2)), isTrue);

      expect((await db.watchRigProfiles().first).length, 2);
      await db.archiveRigProfile(b);
      final visible = await db.watchRigProfiles().first;
      expect(visible.map((r) => r.name), ['A']);
      expect((await db.getRigProfile(b))!.archived, isTrue);
    });

    test('session stores rig ids and snapshots', () async {
      final base = await db.upsertNode(nodeId: 1);
      final map = await db.createCoverageMap(name: 'm', baseNodeId: base);
      final rigId = await db.insertRigProfile(rig('Stubby'));
      final spec = RigSpec.fromProfile((await db.getRigProfile(rigId))!);
      final sid = await db.createSession(
        coverageMapId: map,
        mobileRigId: rigId,
        mobileRigJson: spec.encode(),
      );
      // Editing the profile later does not change the snapshot.
      await db.updateRigProfile(
          rigId, const RigProfilesCompanion(name: Value('Renamed')));
      final s = (await db.getSessionById(sid))!;
      expect(s.mobileRigId, rigId);
      expect(s.baseRigId, isNull);
      expect(RigSpec.decode(s.mobileRigJson)!.name, 'Stubby');
      expect(s.baseRigJson, isNull);
    });
  });

  test('migrates a v3 database to v4', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
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
          ping_interval_sec INTEGER NOT NULL DEFAULT 0,
          packet_airtime_ms REAL NOT NULL DEFAULT 0,
          range_test_active INTEGER NOT NULL DEFAULT 0,
          packet_count INTEGER NOT NULL DEFAULT 0
        )''');
      raw.execute('''
        CREATE TABLE packet_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          timestamp INTEGER NOT NULL,
          direction TEXT NOT NULL,
          source_node_id INTEGER NOT NULL,
          hop_count INTEGER NOT NULL DEFAULT 0,
          packet_type TEXT NOT NULL,
          channel_index INTEGER NOT NULL DEFAULT 0,
          via_mqtt INTEGER NOT NULL DEFAULT 0
        )''');
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
            base_node_id INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            color_metric TEXT NOT NULL DEFAULT 'snr',
            signal_direction TEXT NOT NULL DEFAULT 'rx'
          )''');
      raw.execute("INSERT INTO sessions (coverage_map_id, name, started_at, "
          "hw_antenna) VALUES (1, 'old', 1700000000, 'whip')");
      raw.execute('PRAGMA user_version = 3');
    }));
    addTearDown(db.close);

    final s = (await db.getSessionById(1))!;
    expect(s.name, 'old');
    expect(s.hwAntenna, 'whip');
    expect(s.mobileRigId, isNull);
    expect(s.baseRigJson, isNull);

    final id = await db.insertRigProfile(RigProfilesCompanion.insert(
      name: 'New',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ));
    expect((await db.getRigProfile(id))!.name, 'New');
  });
}
