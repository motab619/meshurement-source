// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/services/other_radio_monitor.dart';
import 'package:mesh_analyzer/services/out_of_range_monitor.dart';
import 'package:mesh_analyzer/services/packet_processor.dart';
import 'package:mesh_analyzer/services/range_test_detector.dart';
import 'package:mesh_analyzer/utils/constants.dart';

import 'fakes/fake_mesh_radio.dart';

void main() {
  const me = 1;
  const base = 2;
  const stranger = 0x0a1b2c3d;

  group('OtherRadioMonitor.classify', () {
    late OtherRadioMonitor m;
    setUp(() => m = OtherRadioMonitor()..start(baseNodeId: base));
    tearDown(() => m.dispose());

    test('the base and our own radio are never strangers', () {
      expect(m.classify(from: base, type: PacketType.telemetry), isNull);
      expect(m.classify(from: me, type: PacketType.telemetry, myNodeId: me),
          isNull);
      expect(m.classify(from: 0, type: PacketType.ack), isNull);
    });

    test('another sender on the test channel is heard', () {
      expect(m.classify(from: stranger, type: PacketType.telemetry),
          OtherRadioReason.heard);
      expect(m.classify(from: stranger, type: PacketType.rangeTest),
          OtherRadioReason.heard);
    });

    test('a reply to our ping from another node is an answer, any channel',
        () {
      expect(m.classify(from: stranger, type: PacketType.ack, channelIndex: 8),
          OtherRadioReason.answered);
    });

    test('other channels and undecodable packets are not the test channel',
        () {
      expect(m.classify(from: stranger, type: PacketType.position, channelIndex: 1),
          isNull);
      expect(m.classify(from: stranger, type: PacketType.other, decoded: false),
          isNull);
    });

    test('nothing while no session records', () {
      m.stop();
      expect(m.classify(from: stranger, type: PacketType.telemetry), isNull);
      expect(
          m.notice(
              nodeId: stranger, name: 'x', reason: OtherRadioReason.heard),
          isNull);
      expect(m.current.value, isNull);
    });
  });

  group('OtherRadioMonitor.notice', () {
    late OtherRadioMonitor m;
    setUp(() => m = OtherRadioMonitor()..start(baseNodeId: base));
    tearDown(() => m.dispose());

    test('fires once per node per session, and again next session', () {
      final first = m.notice(
          nodeId: stranger, name: 'Spare Base', reason: OtherRadioReason.heard);
      expect(first, isNotNull);
      expect(m.current.value, same(first));
      expect(
          m.notice(
              nodeId: stranger,
              name: 'Spare Base',
              reason: OtherRadioReason.answered),
          isNull,
          reason: 'debounced');
      expect(m.alerts.value, hasLength(1));
      expect(m.classify(from: stranger, type: PacketType.ack), isNull,
          reason: 'no name lookup for a node already reported');

      m.dismiss();
      expect(m.current.value, isNull);
      expect(
          m.notice(
              nodeId: stranger, name: 'Spare Base', reason: OtherRadioReason.heard),
          isNull,
          reason: 'dismissing does not re-arm it');

      m.stop();
      m.start(baseNodeId: base);
      expect(
          m.notice(
              nodeId: stranger, name: 'Spare Base', reason: OtherRadioReason.heard),
          isNotNull);
    });

    test('a second stranger replaces the banner; both are listed', () {
      m.notice(nodeId: 3, name: 'A', reason: OtherRadioReason.heard);
      m.notice(nodeId: 4, name: 'B', reason: OtherRadioReason.answered);
      expect(m.current.value?.nodeId, 4);
      expect(m.alerts.value.map((a) => a.nodeId), [3, 4]);
    });

    test('ending the session hides the banner', () {
      m.notice(nodeId: 3, name: 'A', reason: OtherRadioReason.heard);
      m.stop();
      expect(m.current.value, isNull);
    });

    test('message copy', () {
      final heard = m.notice(
          nodeId: 0xa385,
          name: 'MeshTest Base',
          hwModel: 'Heltec V3',
          reason: OtherRadioReason.heard)!;
      expect(
          heard.message,
          'Another node is on the test channel: MeshTest Base (Heltec V3 · '
          '!a385). If it is a second base left on, turn it off; relayed '
          'answers do not count.');
      final answered = m.notice(
          nodeId: 4, name: '!0a1b2c3d', reason: OtherRadioReason.answered)!;
      expect(
          answered.message,
          'Another node is answering: !0a1b2c3d. If it is a second base '
          'left on, turn it off; relayed answers do not count.');
    });
  });

  group('PacketProcessor', () {
    late AppDatabase db;
    late FakeMeshRadio radio;
    late OutOfRangeMonitor monitor;
    late PacketProcessor processor;
    late int sessionId;

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      radio = FakeMeshRadio(myNodeId: me);
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
      processor.otherRadios.start(baseNodeId: base);
    });

    tearDown(() async {
      processor.dispose();
      monitor.dispose();
      await radio.dispose();
      await db.close();
    });

    test('the base and our own radio raise nothing', () async {
      radio.pushPacket(ReceivedPacket(from: base, type: PacketType.telemetry));
      radio.pushPacket(ReceivedPacket(from: me, type: PacketType.telemetry));
      await settle();
      expect(processor.otherRadios.current.value, isNull);
    });

    test("a stranger's telemetry raises one alert, named from the DB",
        () async {
      await db.upsertNode(nodeId: stranger, longName: 'Spare Base');
      radio.pushPacket(ReceivedPacket(
          from: stranger, type: PacketType.telemetry, snr: 3, rssi: -90));
      radio.pushPacket(ReceivedPacket(
          from: stranger, type: PacketType.telemetry, snr: 3, rssi: -90));
      await settle();
      final alert = processor.otherRadios.current.value;
      expect(alert, isNotNull);
      expect(alert!.nodeId, stranger);
      expect(alert.name, 'Spare Base');
      expect(alert.reason, OtherRadioReason.heard);
      expect(processor.otherRadios.alerts.value, hasLength(1));
    });

    test('a relayed ACK from another node is flagged as answering, '
        'even though relayed packets are otherwise ignored', () async {
      radio.nodes[stranger] = const RadioNode(num: stranger, shortName: 'SPR');
      radio.pushPacket(ReceivedPacket(
          from: stranger, type: PacketType.ack, hops: 1, snr: 1, rssi: -110));
      await settle();
      final alert = processor.otherRadios.current.value;
      expect(alert, isNotNull);
      expect(alert!.reason, OtherRadioReason.answered);
      expect(alert.hops, 1);
      expect(alert.name, 'SPR');
      expect(processor.relayedDropped, 1);
    });

    test('a user label beats the radio names; !hex when nothing is known',
        () async {
      final localId = await db.upsertNode(nodeId: 3, longName: 'Heltec');
      await db.updateNodeLabel(localId, 'Spare');
      radio.pushPacket(ReceivedPacket(from: 3, type: PacketType.position));
      await settle();
      expect(processor.otherRadios.current.value?.name, 'Spare');

      radio.pushPacket(
          ReceivedPacket(from: stranger, type: PacketType.position));
      await settle();
      expect(processor.otherRadios.current.value?.name, '!0a1b2c3d');
    });

    test('chatter on another channel, undecodable packets and stale '
        'replays are not strangers', () async {
      radio.pushPacket(ReceivedPacket(
          from: stranger, type: PacketType.position, channelIndex: 1));
      radio.pushPacket(ReceivedPacket(from: stranger, type: PacketType.other));
      radio.pushPacket(ReceivedPacket(
          from: stranger, type: PacketType.telemetry, queued: true));
      await settle();
      expect(processor.otherRadios.current.value, isNull);

      // A decoded text message on the test channel is.
      radio.pushPacket(ReceivedPacket(
          from: stranger,
          type: PacketType.other,
          payload: Uint8List.fromList([104, 105])));
      await settle();
      expect(processor.otherRadios.current.value?.nodeId, stranger);
    });

    test('nothing between sessions', () async {
      processor.otherRadios.stop();
      radio.pushPacket(
          ReceivedPacket(from: stranger, type: PacketType.telemetry));
      await settle();
      expect(processor.otherRadios.current.value, isNull);
    });
  });
}
