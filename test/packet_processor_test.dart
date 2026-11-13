// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/services/out_of_range_monitor.dart';
import 'package:mesh_analyzer/services/packet_processor.dart';
import 'package:mesh_analyzer/services/range_test_detector.dart';
import 'package:mesh_analyzer/utils/constants.dart';

import 'fakes/fake_mesh_radio.dart';

void main() {
  const base = 2;
  late AppDatabase db;
  late FakeMeshRadio radio;
  late OutOfRangeMonitor monitor;
  late PacketProcessor processor;
  late int sessionId;

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    radio = FakeMeshRadio();
    monitor = OutOfRangeMonitor(
      notifications: FlutterLocalNotificationsPlugin(),
      radio: radio,
    );
    processor = PacketProcessor(
      db: db,
      radio: radio,
      gps: GpsService(),
      rangeTestDetector: RangeTestDetector(),
      outOfRangeMonitor: monitor,
    )..start();
    final baseId = await db.upsertNode(nodeId: base);
    final mapId = await db.createCoverageMap(name: 'm', baseNodeId: baseId);
    sessionId = await db.createSession(coverageMapId: mapId);
    processor.activeSessionId = sessionId;
    monitor.configure(baseNodeId: base, timeoutSec: 600);
  });

  tearDown(() async {
    processor.dispose();
    monitor.dispose();
    await radio.dispose();
    await db.close();
  });

  test('an rx packet is logged with its signal and shown to the UI', () async {
    final seen = <double?>[];
    processor.signalStream.listen((e) => seen.add(e.rxSnr));

    radio.pushPacket(ReceivedPacket(
      from: base,
      type: PacketType.position,
      packetId: 42,
      snr: 6.25,
      rssi: -101,
      hops: 0, // direct: relayed copies are ignored by default
      channelIndex: 0,
    ));
    await settle();

    final events = await db.getEventsForSession(sessionId);
    expect(events, hasLength(1));
    expect(events.single.direction, PacketDirection.rx);
    expect(events.single.packetType, PacketType.position);
    expect(events.single.rxSnr, 6.25);
    expect(events.single.rxRssi, -101);
    expect(events.single.hopCount, 0);
    expect(events.single.meshPacketId, 42);
    expect(seen, [6.25]);
    expect(monitor.state, RangeState.inRange);
  });

  test('an ack-type packet only feeds the out-of-range monitor', () async {
    expect(monitor.state, isNot(RangeState.inRange));
    radio.pushPacket(ReceivedPacket(
      from: base,
      type: PacketType.ack,
      packetId: 7,
      snr: 4,
      rssi: -95,
    ));
    await settle();

    expect(await db.getEventsForSession(sessionId), isEmpty);
    expect(monitor.state, RangeState.inRange);
  });

  test('packets from our own radio are ignored', () async {
    radio.pushPacket(ReceivedPacket(from: 1, type: PacketType.position));
    await settle();
    expect(await db.getEventsForSession(sessionId), isEmpty);
  });

  test('replayed or old packets are dropped, and do not reset the monitor',
      () async {
    final before = monitor.state;
    // Replayed from the radio's buffer during the handshake.
    radio.pushPacket(ReceivedPacket(
        from: base, type: PacketType.position, snr: 5, queued: true));
    // Old by the radio's clock.
    radio.pushPacket(ReceivedPacket(
        from: base,
        type: PacketType.position,
        snr: 5,
        rxTime: DateTime.now().subtract(const Duration(minutes: 10))));
    await settle();
    expect(await db.getEventsForSession(sessionId), isEmpty);
    expect(processor.staleDropped, 2);
    expect(monitor.state, before);

    // A fresh one (recent rx_time) is recorded as usual.
    radio.pushPacket(ReceivedPacket(
        from: base,
        type: PacketType.position,
        snr: 5,
        rxTime: DateTime.now().subtract(const Duration(seconds: 5))));
    await settle();
    expect(await db.getEventsForSession(sessionId), hasLength(1));
  });

  test('relayed packets are ignored by default and never reset the monitor',
      () async {
    final before = monitor.state;
    radio.pushPacket(ReceivedPacket(
        from: base, type: PacketType.position, snr: 5, rssi: -90, hops: 2));
    await settle();
    expect(await db.getEventsForSession(sessionId), isEmpty);
    expect(processor.relayedDropped, 1);
    expect(monitor.state, before);
  });

  test('relayed packets count when the setting is on', () async {
    processor.dispose();
    processor = PacketProcessor(
      db: db,
      radio: radio,
      gps: GpsService(),
      rangeTestDetector: RangeTestDetector(),
      outOfRangeMonitor: monitor,
      countRelayed: () => true,
    )..start();
    processor.activeSessionId = sessionId;
    radio.pushPacket(ReceivedPacket(
        from: base, type: PacketType.position, snr: 5, rssi: -90, hops: 2));
    await settle();
    final events = await db.getEventsForSession(sessionId);
    expect(events, hasLength(1));
    expect(events.single.hopCount, 2);
  });

  test('last heard is written at most once per node per 30 s', () async {
    var now = DateTime(2026, 11, 4, 12);
    final throttled = PacketProcessor(
      db: db,
      radio: radio,
      gps: GpsService(),
      rangeTestDetector: RangeTestDetector(),
      outOfRangeMonitor: monitor,
      clock: () => now,
    )..start();
    throttled.activeSessionId = sessionId;
    processor.stop(); // only the throttled one listens
    final t0 = now;
    var updates = 0;
    final sub = db.watchAllNodes().listen((_) => updates++);
    await settle();
    final before = updates;

    Future<void> heard(int id) async {
      radio.pushPacket(ReceivedPacket(
        from: base,
        type: PacketType.position,
        packetId: id,
        snr: 5,
        rssi: -90,
        hops: 0,
        channelIndex: 0,
      ));
      await settle();
    }

    Future<DateTime> lastHeard() async =>
        (await db.getNodeByMeshId(base))!.lastHeardAt;

    await heard(1);
    expect(await lastHeard(), t0);
    now = t0.add(const Duration(seconds: 10));
    await heard(2);
    now = t0.add(const Duration(seconds: 20));
    await heard(3);
    expect(await lastHeard(), t0, reason: 'held back');
    expect(updates - before, 1, reason: 'one node-list refresh, not three');

    // Session end writes what was held back.
    await throttled.flushLastHeard();
    expect(await lastHeard(), t0.add(const Duration(seconds: 20)));

    // A packet after the interval is written at once.
    now = t0.add(const Duration(seconds: 55));
    await heard(4);
    expect(await lastHeard(), now);
    expect(await db.getEventsForSession(sessionId), hasLength(4),
        reason: 'every packet is still recorded');

    await sub.cancel();
    throttled.dispose();
  });

  test('node updates refresh names and position in the DB', () async {
    radio.pushNode(const RadioNode(
      num: base,
      longName: 'Polo Base',
      shortName: 'BASE',
      hwModel: 'TRACKER_T1000_E',
      latitude: 33.68,
      longitude: -116.24,
    ));
    await settle();

    final node = await db.getNodeByMeshId(base);
    expect(node!.longName, 'Polo Base');
    expect(node.shortName, 'BASE');
    expect(node.lastLat, closeTo(33.68, 1e-9));
  });
}
