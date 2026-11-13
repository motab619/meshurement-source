// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/services/field_report/comparison_report_data.dart';
import 'package:mesh_analyzer/services/field_report/field_report_data.dart';
import 'package:mesh_analyzer/utils/constants.dart';

/// A session shaped like session 32 of the design doc ("short turbo EOD",
/// 2026-10-28, Short Turbo, 108 minutes): 62 readings in the 32/16/32/19 %
/// buckets with a +6 dB median margin, the base heard 49 % of the time, a
/// walk 150 to 400 m from the base and one reading 650 m out (0.4 mi)
/// while driving away at the end, with no second reading near it.

const baseLat = 33.70, baseLon = -116.23;
// Midday UTC, so the local date is Oct 28 in every time zone a test runs in.
final session32Start = DateTime.utc(2026, 10, 28, 12, 0);

/// lat/lon [m] metres north/east of the base.
({double lat, double lon}) offsetFrom(
        double lat0, double lon0, double north, double east) =>
    (
      lat: lat0 + north / 111320.0,
      lon: lon0 + east / (111320.0 * math.cos(lat0 * math.pi / 180)),
    );

class Session32 {
  final int mapId;
  final int sessionId;
  const Session32(this.mapId, this.sessionId);
}

/// Seed session 32 into [db]. [mapBaseNorthM] moves the map's base
/// location (49.7 km puts the session on the "wrong map").
Future<Session32> seedSession32(AppDatabase db,
    {double mapBaseNorthM = 0, String name = 'short turbo EOD'}) async {
  final mapBase = offsetFrom(baseLat, baseLon, mapBaseNorthM, 0);
  final mapId = await db.createCoverageMap(
      name: 'home v3', baseLat: mapBase.lat, baseLon: mapBase.lon);
  final baseNode = await db.upsertNode(
      nodeId: 0x4f68b8f4,
      longName: 'Base',
      shortName: 'BASE',
      hwModel: 'HELTEC_V3');
  final self = await db.upsertNode(
      nodeId: 0x8a2fe4ea,
      longName: 'Me',
      shortName: 'ME',
      hwModel: 'TRACKER_T1000_E');
  final sid = await db.createSession(
    coverageMapId: mapId,
    name: name,
    baseNodeId: baseNode,
    loraPreset: 'SHORT_TURBO',
    hwNodeModel: 'TRACKER_T1000_E',
    beaconKind: 'telemetry',
    beaconIntervalSec: 60,
  );
  await (db.update(db.sessions)..where((s) => s.id.equals(sid))).write(
    SessionsCompanion(
      startedAt: Value(session32Start),
      endedAt: Value(session32Start.add(const Duration(minutes: 108))),
      isActive: const Value(false),
    ),
  );

  // 62 margins on Short Turbo (floor -7.5 dB): 20 strong, 10 good, 20 weak
  // (all +6, so the median is +6), 12 below the limit. The last strong one
  // is the lone far reading.
  final margins = <double>[
    for (var i = 0; i < 19; i++) 22.0 + i % 4,
    for (var i = 0; i < 10; i++) 12.0 + i % 6,
    for (var i = 0; i < 20; i++) 6.0,
    for (var i = 0; i < 12; i++) -1.0 - i % 3,
  ]..shuffle(math.Random(32));
  margins.add(24); // the far one, last in time

  var t = session32Start.add(const Duration(minutes: 1));
  Future<int> event(String direction, String kind,
      {double? snr, double? north, double? east, DateTime? at}) {
    final p = north == null ? null : offsetFrom(baseLat, baseLon, north, east!);
    return db.insertPacketEvent(PacketEventsCompanion.insert(
      sessionId: sid,
      timestamp: at ?? t,
      direction: direction,
      sourceNodeId: direction == PacketDirection.tx ? self : baseNode,
      rxSnr: Value(snr),
      rxLat: Value(p?.lat),
      rxLon: Value(p?.lon),
      packetType: kind == SourceKind.telemetry ? 'telemetry' : 'routing',
      sourceKind: Value(kind),
    ));
  }

  // 61 walking readings on a loop 150 to 400 m from the base; the two
  // farthest of them (400 m) sit 20 m apart, so 400 m is the headline.
  var pingAcks = 0;
  for (var i = 0; i < 61; i++) {
    final a = 2 * math.pi * i / 61;
    final r = i == 30 || i == 31 ? 400.0 : 150 + 200 * math.sin(a / 2).abs();
    final north = r * math.cos(a), east = r * math.sin(a);
    final isPing = i % 5 == 0 && pingAcks < 12;
    if (isPing) {
      final tx = await event(PacketDirection.tx, SourceKind.ack,
          north: north, east: east);
      t = t.add(const Duration(seconds: 1));
      final ack = await event(PacketDirection.ack, SourceKind.ack,
          snr: margins[i] - 7.5, north: north, east: east);
      await db.insertPingCorrelation(PingCorrelationsCompanion.insert(
          txEventId: tx,
          ackEventId: Value(ack),
          ackStatus: const Value(AckStatus.received)));
      pingAcks++;
    } else {
      await event(PacketDirection.rx, SourceKind.telemetry,
          snr: margins[i] - 7.5, north: north, east: east);
    }
    t = t.add(const Duration(seconds: 100));
  }
  // The lone far reading, driving away (0.4 mi).
  await event(PacketDirection.rx, SourceKind.telemetry,
      snr: margins[61] - 7.5, north: 650, east: 0);

  // Beacon misses (no signal, interpolated positions) and pings that got
  // no reply, a NAK or were throttled: 50 beacons heard + 12 pings
  // answered = 62 of 50 + 55 missed + 12 + 10 timeouts = 127 (49 %).
  for (var i = 0; i < 55; i++) {
    await event(PacketDirection.rx, SourceKind.telemetryMiss,
        north: 9000, east: 9000, at: session32Start.add(Duration(seconds: i)));
  }
  for (final status in [
    ...List.filled(10, AckStatus.timeout),
    'error:NO_ROUTE',
    'error:PKI_UNKNOWN_PUBKEY',
    AckStatus.throttled,
  ]) {
    final tx = await event(PacketDirection.tx, SourceKind.ack,
        north: 200,
        east: 0,
        at: session32Start.add(const Duration(minutes: 90)));
    await db.insertPingCorrelation(PingCorrelationsCompanion.insert(
        txEventId: tx, ackStatus: Value(status)));
  }
  return Session32(mapId, sid);
}

/// A bare session row for pure builder tests.
Session testSession(int id,
        {String preset = 'SHORT_TURBO', String protocol = 'meshtastic'}) =>
    Session(
      id: id,
      coverageMapId: 1,
      name: 'Up the street to Pat\'s',
      startedAt: DateTime.utc(2026, 10, 28, 12),
      endedAt: DateTime.utc(2026, 10, 28, 13),
      isActive: false,
      hwAntenna: '',
      hwNodeModel: '',
      hwNotes: '',
      loraPreset: preset,
      protocol: protocol,
      pingIntervalSec: 0,
      packetAirtimeMs: 0,
      beaconKind: '',
      beaconIntervalSec: 0,
      rangeTestActive: false,
      packetCount: 0,
    );

PacketEvent testEvent(int sessionId, int i, double north, double east,
    {double? snr}) {
  final p = offsetFrom(baseLat, baseLon, north, east);
  return PacketEvent(
    id: sessionId * 1000 + i,
    sessionId: sessionId,
    timestamp: DateTime.utc(2026, 10, 28, 12, i),
    direction: 'rx',
    sourceNodeId: 1,
    rxSnr: snr,
    hopCount: 0,
    rxLat: p.lat,
    rxLon: p.lon,
    packetType: 'telemetry',
    channelIndex: 0,
    viaMqtt: false,
    sourceKind: 'telemetry',
  );
}

/// A comparison side input: two readings [far] - 20 m and [far] m east of
/// the base at [snr].
ComparisonSideInput testSide(String name, int id, double far, double snr) =>
    ComparisonSideInput(name, [
      SessionReportInput(session: testSession(id), events: [
        testEvent(id, 0, 0, far - 20, snr: snr),
        testEvent(id, 1, 0, far, snr: snr),
      ]),
    ]);
