// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/services/export/csv_v2.dart';

import 'fixture.dart';

void main() {
  late ExportFixture f;
  setUp(() async => f = await ExportFixture.create());
  tearDown(() => f.db.close());

  List<List<dynamic>> parse(String csv) =>
      const CsvToListConverter(eol: '\n').convert(csv.replaceAll('\r\n', '\n'));

  test('timestamps are UTC with Z, local has an offset, unix_ms matches',
      () async {
    final rows = parse(buildCsvV2([await f.session(f.session1)]));
    final h = rows.first.cast<String>();
    final r = rows[1];
    final local = DateTime(2026, 10, 17, 14, 3, 22);
    final utc = r[h.indexOf('timestamp_utc')] as String;
    expect(utc, local.toUtc().toIso8601String());
    expect(utc, endsWith('Z'));
    expect(r[h.indexOf('unix_ms')], local.millisecondsSinceEpoch);
    expect(r[h.indexOf('timestamp_local')] as String,
        matches(RegExp(r'T\d\d:\d\d:\d\d[+-]\d\d:\d\d$')));
  });

  test('offset formatting', () {
    // The offset is whatever zone the test runs in; just check the shape and
    // that it round-trips to the same instant.
    final t = DateTime(2026, 7, 1, 12);
    expect(DateTime.parse(isoWithOffset(t)).isAtSameMomentAs(t), isTrue);
  });

  test('node id keeps leading zeros; num is decimal; names included', () async {
    final rows = parse(buildCsvV2([await f.session(f.session1)]));
    final h = rows.first.cast<String>();
    expect(rows[1][h.indexOf('source_node_id')], '!0000a1b2');
    expect(rows[1][h.indexOf('source_node_num')], 0xa1b2);
    expect(rows[1][h.indexOf('source_short_name')], 'AB');
    expect(nodeIdHex(0xFFFFFFFF), '!ffffffff');
  });

  test('ping status and mesh packet id are exported', () async {
    final rows = parse(buildCsvV2([await f.session(f.session1)]));
    final h = rows.first.cast<String>();
    expect(rows[1][h.indexOf('mesh_packet_id')], 77);
    expect(rows[3][h.indexOf('ping_status')], 'timeout');
    expect(rows[4][h.indexOf('ping_status')], 'received');
    expect(rows[4][h.indexOf('round_trip_ms')], 1500);
  });

  test('formula-like text is neutralised, negative numbers are not', () async {
    final csv = buildCsvV2([await f.session(f.session1)]);
    expect(csv, contains("'=EVIL"));
    expect(csv, contains("'=cmd|x"));
    expect(csv, contains(',-116.24,'));
    expect(csvSafeText('+1'), "'+1");
    expect(csvSafeText('@x'), "'@x");
    expect(csvSafeText('plain'), 'plain');
  });

  test('session_distance_m is the track length, repeated on every row',
      () async {
    final rows = parse(buildCsvV2([await f.session(f.session1)]));
    final h = rows.first.cast<String>();
    final i = h.indexOf('session_distance_m');
    expect(h.sublist(h.length - 7), [
      'session_distance_m',
      'session_region',
      'session_frequency_slot',
      'session_frequency_mhz',
      'session_tx_power_dbm',
      'session_hop_limit',
      'uplink_snr', // schema v10
    ]);
    // Two ~144 m steps (0.001 deg lat and lon each).
    final d = rows[1][i] as int;
    expect(d, inInclusiveRange(280, 300));
    for (final r in rows.skip(1)) {
      expect(r[i], d);
    }
    final second = parse(buildCsvV2([await f.session(f.session2)]));
    expect(second[1][i], 0, reason: 'one fix is not a track');
  });

  test('session radio settings are exported, empty when unknown', () async {
    final rows = parse(buildCsvV2([await f.session(f.session1)]));
    final h = rows.first.cast<String>();
    final r = rows[1];
    expect(r[h.indexOf('session_region')], 'US');
    expect(r[h.indexOf('session_frequency_slot')], 20);
    expect(r[h.indexOf('session_frequency_mhz')], 906.875);
    expect(r[h.indexOf('session_tx_power_dbm')], 27);
    expect(r[h.indexOf('session_hop_limit')], 3);
    final second = parse(buildCsvV2([await f.session(f.session2)]));
    expect(second[1][h.indexOf('session_tx_power_dbm')], '');
    expect(second[1][h.indexOf('session_frequency_slot')], '');
  });

  test('header is defined once and has unique names', () {
    expect(csvV2Header.toSet().length, csvV2Header.length);
    expect(csvV2Header.first, 'event_id');
  });
}
