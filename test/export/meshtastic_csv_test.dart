// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/services/export/meshtastic_csv.dart';

import 'fixture.dart';

void main() {
  late ExportFixture f;
  setUp(() async => f = await ExportFixture.create());
  tearDown(() => f.db.close());

  test('header matches the firmware rangetest.csv byte for byte', () async {
    final csv = buildMeshtasticCsv([await f.session(f.session1)]);
    expect(csv.split('\r\n').first,
        'time,from,sender name,sender lat,sender long,rx lat,rx long,'
        'rx elevation,rx snr,distance,hop limit,payload,rx rssi');
  });

  test('only rx rows, time as HH:MM:SS UTC, decimal from, 13 columns', () async {
    final csv = buildMeshtasticCsv([await f.session(f.session1)]);
    final lines = csv.split('\r\n');
    expect(lines, hasLength(3)); // header + 2 rx rows, pings are tx
    expect(lines[1], matches(RegExp(r'^\d\d:\d\d:\d\d,41394,')));
    expect(lines[1], contains(',33.68,-116.24,'));
    expect(lines[1].split(',').length, 13);
  });

  test('rows from the base carry the map location and the distance', () async {
    await f.db.setMapBaseLocation(f.mapId, 33.68, -116.25);
    final base = (await f.db.getNodeByMeshId(2))!;
    await f.db.insertPacketEvent(PacketEventsCompanion.insert(
      sessionId: f.session2,
      timestamp: DateTime(2026, 10, 18, 9),
      direction: 'rx',
      sourceNodeId: base.id,
      packetType: 'telemetry',
      rxLat: const Value(33.68),
      rxLon: const Value(-116.24),
      rxSnr: const Value(4.0),
    ));
    final lines = buildMeshtasticCsv([await f.session(f.session2)])
        .split('\r\n');
    final fromBase = lines.firstWhere((l) => l.contains(',2,Base,'));
    final cells = fromBase.split(',');
    expect(cells[3], '33.68');
    expect(cells[4], '-116.25');
    // 0.01 degrees of longitude at 33.68 N is about 926 m.
    expect(int.parse(cells[9]), inInclusiveRange(920, 932));
    expect(cells[10], '');
    // Another sender's row leaves the sender columns empty.
    final other = lines.firstWhere((l) => l.contains(',41394,'));
    expect(other.split(',').sublist(3, 5), ['', '']);
  });
}
