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

import 'fakes/fake_location_backend.dart';
import 'fakes/fake_mesh_radio.dart';

void main() {
  group('RangeTestDetector', () {
    test('an unknown node is recorded while its question is open', () {
      final d = RangeTestDetector();
      final prompts = <int>[];
      d.promptStream.listen((p) => prompts.add(p.meshNodeId));

      expect(d.shouldLogRangeTest(7), isTrue);
      expect(d.shouldLogRangeTest(7), isTrue);
      expect(d.confirmationFor(7), isNull);

      d.setConfirmation(7, false);
      expect(d.shouldLogRangeTest(7), isFalse);
      return Future<void>.delayed(Duration.zero, () => expect(prompts, [7]));
    });

    test('the known base is recorded without asking', () async {
      final d = RangeTestDetector()..trust([2, null]);
      final prompts = <int>[];
      d.promptStream.listen((p) => prompts.add(p.meshNodeId));

      expect(d.shouldLogRangeTest(2), isTrue);
      d.setConfirmation(2, false); // ignored for a trusted base
      expect(d.shouldLogRangeTest(2), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(prompts, isEmpty);
    });

    test('a yes survives the next session, a no does not', () async {
      final d = RangeTestDetector();
      final prompts = <int>[];
      d.promptStream.listen((p) => prompts.add(p.meshNodeId));
      d.shouldLogRangeTest(7);
      d.shouldLogRangeTest(8);
      d.setConfirmation(7, true);
      d.setConfirmation(8, false);

      d.endSession();
      expect(d.shouldLogRangeTest(7), isTrue);
      expect(d.shouldLogRangeTest(8), isTrue); // asked again
      await Future<void>.delayed(Duration.zero);
      expect(prompts, [7, 8, 8]);
    });
  });

  group('PacketProcessor with Range Test packets', () {
    const base = 2;
    const stranger = 9;
    late AppDatabase db;
    late FakeMeshRadio radio;
    late OutOfRangeMonitor monitor;
    late RangeTestDetector detector;
    late PacketProcessor processor;
    late int sessionId;
    late List<int> prompts;

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    ReceivedPacket beacon(int from) =>
        ReceivedPacket(from: from, type: PacketType.rangeTest, snr: 3);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      radio = FakeMeshRadio();
      monitor = OutOfRangeMonitor(
        notifications: FlutterLocalNotificationsPlugin(),
        radio: radio,
      );
      detector = RangeTestDetector();
      prompts = [];
      detector.promptStream.listen((p) => prompts.add(p.meshNodeId));
      processor = PacketProcessor(
        db: db,
        radio: radio,
        gps: GpsService(backend: FakeLocationBackend()),
        rangeTestDetector: detector,
        outOfRangeMonitor: monitor,
      )..start();
      final baseId = await db.upsertNode(nodeId: base);
      final mapId = await db.createCoverageMap(name: 'm', baseNodeId: baseId);
      sessionId = await db.createSession(coverageMapId: mapId);
    });

    tearDown(() async {
      processor.dispose();
      monitor.dispose();
      detector.dispose();
      await radio.dispose();
      await db.close();
    });

    test('no prompt and nothing recorded while idle', () async {
      radio.pushPacket(beacon(stranger));
      await settle();
      expect(prompts, isEmpty);
    });

    test('pending beacons are recorded; the base is never asked about',
        () async {
      processor.activeSessionId = sessionId;
      detector.trust([base]);
      radio.pushPacket(beacon(stranger));
      radio.pushPacket(beacon(stranger));
      radio.pushPacket(beacon(base));
      await settle();

      expect(prompts, [stranger]);
      expect(await db.getEventsForSession(sessionId), hasLength(3));
      expect((await db.getSessionById(sessionId))!.rangeTestActive, isTrue);
    });

    test('a declined base still counts as heard by the monitor', () async {
      processor.activeSessionId = sessionId;
      monitor.configure(baseNodeId: base, timeoutSec: 600);
      detector.shouldLogRangeTest(base);
      detector.setConfirmation(base, false);

      radio.pushPacket(beacon(base));
      await settle();

      expect(await db.getEventsForSession(sessionId), isEmpty);
      expect(monitor.state, RangeState.inRange);
    });
  });
}
