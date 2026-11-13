// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/services/export/export_data.dart';
import 'package:mesh_analyzer/utils/constants.dart';

/// Two sessions on one map. Session 1 has a formula-like name, a node with
/// leading zeros in its id, a positioned rx, an unpositioned rx, a failed
/// ping and an answered ping.
class ExportFixture {
  final AppDatabase db;
  late int mapId, session1, session2;
  late int nodeIdRow;

  ExportFixture(this.db);

  static Future<ExportFixture> create() async {
    final f = ExportFixture(AppDatabase.forTesting(NativeDatabase.memory()));
    final base = await f.db.upsertNode(nodeId: 0x2, longName: 'Base');
    f.nodeIdRow = await f.db
        .upsertNode(nodeId: 0xa1b2, longName: '=cmd|x', shortName: 'AB');
    f.mapId = await f.db.createCoverageMap(name: 'Park', baseNodeId: base);
    f.session1 = await f.db.createSession(
        coverageMapId: f.mapId,
        name: '=EVIL',
        loraPreset: 'LONG_FAST',
        radioSettings: const RadioSettings(
            region: 'US',
            frequencySlot: 20,
            txPowerDbm: 27,
            hopLimit: 3,
            frequencyMHz: 906.875));
    f.session2 = await f.db.createSession(
        coverageMapId: f.mapId, name: 'Second', loraPreset: 'LONG_FAST');

    Future<int> ev(int session, DateTime t, String dir, String type,
        {double? lat, double? lon, double? snr, int? rssi, int? pktId}) {
      return f.db.insertPacketEvent(PacketEventsCompanion.insert(
        sessionId: session,
        timestamp: t,
        direction: dir,
        sourceNodeId: f.nodeIdRow,
        packetType: type,
        rxLat: Value(lat),
        rxLon: Value(lon),
        rxSnr: Value(snr),
        rxRssi: Value(rssi),
        meshPacketId: Value(pktId),
      ));
    }

    final t0 = DateTime(2026, 10, 17, 14, 3, 22);
    await ev(f.session1, t0, 'rx', PacketType.rangeTest,
        lat: 33.68, lon: -116.24, snr: 5.5, rssi: -90, pktId: 77);
    await ev(f.session1, t0.add(const Duration(seconds: 10)), 'rx',
        PacketType.rangeTest,
        snr: -3);
    final failed = await ev(f.session1, t0.add(const Duration(seconds: 20)),
        'tx', PacketType.ping,
        lat: 33.681, lon: -116.241);
    await f.db.insertPingCorrelation(PingCorrelationsCompanion.insert(
        txEventId: failed, ackStatus: const Value('timeout')));
    final ok = await ev(f.session1, t0.add(const Duration(seconds: 30)), 'tx',
        PacketType.ping,
        lat: 33.682, lon: -116.242);
    await f.db.insertPingCorrelation(PingCorrelationsCompanion.insert(
        txEventId: ok,
        ackStatus: const Value('received'),
        roundTripMs: const Value(1500)));
    await ev(f.session2, t0.add(const Duration(days: 1)), 'rx',
        PacketType.rangeTest,
        lat: 33.7, lon: -116.3, snr: -12, rssi: -110);
    return f;
  }

  Future<SessionExport> session(int id) async =>
      (await ExportLoader(db).session(id))!;
}
