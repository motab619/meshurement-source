// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

// The whole migration chain: a schema v1 database (the first release's
// tables, before lora_preset) upgraded through every step must end up with
// the same tables, columns, foreign keys and indexes as a fresh install.
// Per-step data tests live beside each feature (rig_test v3,
// beacon_kinds_test v6, session_base_test v7, radio_settings_test v8,
// meshcore_services_test v9).

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';

/// Schema v1 as drift created it (tables of the initial commit, 05adb24,
/// without v2's `sessions.lora_preset`), with the onCreate indexes.
const _v1 = [
  'CREATE TABLE "nodes" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"node_id" INTEGER NOT NULL UNIQUE, '
      '"long_name" TEXT NOT NULL DEFAULT \'\', '
      '"short_name" TEXT NOT NULL DEFAULT \'\', "user_label" TEXT NULL, '
      '"hw_model" TEXT NOT NULL DEFAULT \'\', '
      '"first_seen_at" INTEGER NOT NULL, "last_heard_at" INTEGER NOT NULL, '
      '"last_lat" REAL NULL, "last_lon" REAL NULL)',
  'CREATE TABLE "coverage_maps" ("id" INTEGER NOT NULL PRIMARY KEY '
      'AUTOINCREMENT, "name" TEXT NOT NULL, '
      '"base_node_id" INTEGER NOT NULL REFERENCES nodes (id), '
      '"created_at" INTEGER NOT NULL, '
      '"description" TEXT NOT NULL DEFAULT \'\', '
      '"color_metric" TEXT NOT NULL DEFAULT \'snr\', '
      '"signal_direction" TEXT NOT NULL DEFAULT \'rx\')',
  'CREATE TABLE "sessions" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
      '"coverage_map_id" INTEGER NOT NULL REFERENCES coverage_maps (id), '
      '"name" TEXT NOT NULL DEFAULT \'\', "started_at" INTEGER NOT NULL, '
      '"ended_at" INTEGER NULL, "is_active" INTEGER NOT NULL DEFAULT 0 '
      'CHECK ("is_active" IN (0, 1)), '
      '"remote_node_id" INTEGER NULL REFERENCES nodes (id), '
      '"hw_antenna" TEXT NOT NULL DEFAULT \'\', '
      '"hw_node_model" TEXT NOT NULL DEFAULT \'\', '
      '"hw_notes" TEXT NOT NULL DEFAULT \'\', '
      '"ping_interval_sec" INTEGER NOT NULL DEFAULT 0, '
      '"range_test_active" INTEGER NOT NULL DEFAULT 0 '
      'CHECK ("range_test_active" IN (0, 1)), '
      '"packet_count" INTEGER NOT NULL DEFAULT 0)',
  'CREATE TABLE "packet_events" ("id" INTEGER NOT NULL PRIMARY KEY '
      'AUTOINCREMENT, "session_id" INTEGER NOT NULL REFERENCES sessions (id), '
      '"timestamp" INTEGER NOT NULL, "direction" TEXT NOT NULL, '
      '"source_node_id" INTEGER NOT NULL REFERENCES nodes (id), '
      '"rx_snr" REAL NULL, "rx_rssi" INTEGER NULL, '
      '"hop_count" INTEGER NOT NULL DEFAULT 0, "rx_lat" REAL NULL, '
      '"rx_lon" REAL NULL, "rx_alt" REAL NULL, "gps_accuracy" REAL NULL, '
      '"packet_type" TEXT NOT NULL, "mesh_packet_id" INTEGER NULL, '
      '"channel_index" INTEGER NOT NULL DEFAULT 0, '
      '"via_mqtt" INTEGER NOT NULL DEFAULT 0 CHECK ("via_mqtt" IN (0, 1)))',
  'CREATE TABLE "ping_correlations" ("id" INTEGER NOT NULL PRIMARY KEY '
      'AUTOINCREMENT, '
      '"tx_event_id" INTEGER NOT NULL REFERENCES packet_events (id), '
      '"ack_event_id" INTEGER NULL REFERENCES packet_events (id), '
      '"round_trip_ms" INTEGER NULL, '
      '"ack_status" TEXT NOT NULL DEFAULT \'timeout\')',
  'CREATE INDEX idx_packet_events_session_time '
      'ON packet_events (session_id, timestamp)',
  'CREATE INDEX idx_packet_events_source_time '
      'ON packet_events (source_node_id, timestamp)',
  'CREATE INDEX idx_packet_events_location ON packet_events (rx_lat, rx_lon)',
];

/// Every table's columns (name, type, not null, default, primary key, in
/// name order), foreign keys and named indexes, as SQLite reports them.
Future<Map<String, Object>> schemaOf(AppDatabase db) async {
  Future<List<Map<String, Object?>>> q(String sql) async =>
      [for (final r in await db.customSelect(sql).get()) r.data];
  final out = <String, Object>{};
  final tables = await q("SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name");
  for (final t in tables) {
    final name = t['name']! as String;
    final cols = await q('PRAGMA table_info("$name")');
    out['$name.columns'] = [
      for (final c
          in cols..sort((a, b) => '${a['name']}'.compareTo('${b['name']}')))
        '${c['name']} ${c['type']} notnull=${c['notnull']} '
            'default=${c['dflt_value']} pk=${c['pk']}'
    ];
    final fks = await q('PRAGMA foreign_key_list("$name")');
    out['$name.fks'] = [
      for (final f in fks) '${f['from']} -> ${f['table']}.${f['to']}'
    ]..sort();
  }
  final indexes = await q("SELECT name, tbl_name, sql FROM sqlite_master "
      "WHERE type = 'index' AND sql IS NOT NULL ORDER BY name");
  out['indexes'] = [
    for (final i in indexes)
      '${i['name']} on ${i['tbl_name']}: '
          '${(i['sql'] as String).replaceAll('IF NOT EXISTS ', '')}'
  ];
  return out;
}

void main() {
  test('v1 upgraded through every step matches a fresh install', () async {
    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(fresh.close);
    final upgraded = AppDatabase.forTesting(NativeDatabase.memory(
      setup: (raw) {
        for (final sql in _v1) {
          raw.execute(sql);
        }
        raw.execute('PRAGMA user_version = 1');
      },
    ));
    addTearDown(upgraded.close);

    final want = await schemaOf(fresh);
    final got = await schemaOf(upgraded);
    expect(got.keys.toSet(), want.keys.toSet());
    for (final k in want.keys) {
      expect(got[k], want[k], reason: k);
    }
    expect(
        (await upgraded.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        upgraded.schemaVersion);
  });

  test('data written at v1 survives the whole chain', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(
      setup: (raw) {
        for (final sql in _v1) {
          raw.execute(sql);
        }
        raw.execute("INSERT INTO nodes (node_id, first_seen_at, last_heard_at, "
            'last_lat, last_lon) VALUES (2, 1700000000, 1700000000, 33.68, '
            '-116.24)');
        raw.execute(
            "INSERT INTO coverage_maps (name, base_node_id, created_at) "
            "VALUES ('Polo', 1, 1700000000)");
        raw.execute("INSERT INTO sessions (coverage_map_id, name, started_at) "
            "VALUES (1, 'first', 1700000000)");
        raw.execute('INSERT INTO packet_events (session_id, timestamp, '
            'direction, source_node_id, packet_type, rx_snr) '
            "VALUES (1, 1700000010, 'rx', 1, 'position', 4.5)");
        raw.execute('PRAGMA user_version = 1');
      },
    ));
    addTearDown(db.close);

    final s = (await db.getSessionById(1))!;
    expect(s.name, 'first');
    expect(s.loraPreset, '');
    expect(s.protocol, 'meshtastic');
    expect(s.baseNodeId, 1, reason: 'v8 gives old sessions their map base');
    final map = (await db.getAllCoverageMaps()).single;
    expect(map.baseLat, 33.68, reason: 'v8 places the map at its base');
    expect(map.baseLon, -116.24);
    final e = (await db.getEventsForSession(1)).single;
    expect(e.rxSnr, 4.5);
    expect(e.sourceKind, 'passive');
    // New tables work.
    final id = await db.into(db.testPlans).insert(TestPlansCompanion.insert(
        coverageMapId: 1,
        title: 't',
        template: 'antennas',
        intentJson: '{}',
        createdAt: DateTime(2026)));
    expect(id, 1);
  });
}
