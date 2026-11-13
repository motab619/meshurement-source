// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/services/active_probe_service.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/utils/constants.dart';

import 'fakes/fake_mesh_radio.dart';

void main() {
  const base = 2;
  late AppDatabase db;
  late FakeMeshRadio radio;
  late ActiveProbeService probe;
  late int sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    radio = FakeMeshRadio();
    probe = ActiveProbeService(db: db, radio: radio, gps: GpsService());
    final baseId = await db.upsertNode(nodeId: base);
    final mapId = await db.createCoverageMap(name: 'm', baseNodeId: baseId);
    sessionId = await db.createSession(coverageMapId: mapId);
    probe.start(sessionId: sessionId, baseMeshNodeId: base);
  });

  tearDown(() async {
    probe.dispose();
    await radio.dispose();
    await db.close();
  });

  Future<PingCorrelation> onlyCorrelation() async {
    final pings = await db.getPingsForSession(sessionId);
    expect(pings, hasLength(1));
    return pings.values.single;
  }

  Future<List<PacketEvent>> events(String direction) async =>
      (await db.getEventsForSession(sessionId))
          .where((e) => e.direction == direction)
          .toList();

  test('start swaps NodeInfo with the base first', () {
    expect(radio.preparedTargets, [base]);
  });

  test('received: ACK from the base is logged with its signal', () async {
    radio.script.add((id) => PingOutcome(
          pingId: id,
          status: PingStatus.received,
          responder: base,
          replyPacketId: 77,
          snr: 5.5,
          rssi: -90,
          roundTrip: const Duration(milliseconds: 1200),
        ));
    final samples = <PingSample>[];
    probe.outcomes.listen(samples.add);

    await probe.pingNow();

    final corr = await onlyCorrelation();
    expect(corr.ackStatus, AckStatus.received);
    expect(corr.roundTripMs, 1200);
    expect(corr.ackEventId, isNotNull);
    final ack = (await events(PacketDirection.ack)).single;
    expect(ack.rxSnr, 5.5);
    expect(ack.rxRssi, -90);
    expect(ack.hopCount, 0);
    expect(ack.meshPacketId, 77);
    expect(probe.pingsAnswered, 1);
    expect(probe.pingsOk, 1);
    expect(probe.lastAckSnr, 5.5);
    expect(probe.lastAckRssi, -90);
    expect(probe.lastAckAt, isNotNull);
    await Future<void>.delayed(Duration.zero);
    expect(samples.single.status, AckStatus.received);
    expect(samples.single.fromBase, isTrue);
    // No fix in this test: the Live map gets no dot, but hops ride along.
    expect(samples.single.hasGps, isFalse);
    expect(samples.single.hops, 0);
  });

  test('a relayed ACK is delivery but not a direct signal sample', () async {
    radio.script.add((id) => PingOutcome(
          pingId: id,
          status: PingStatus.received,
          responder: base,
          replyPacketId: 78,
          snr: 5.5,
          rssi: -90,
          hops: 1,
          roundTrip: const Duration(milliseconds: 1200),
        ));
    final samples = <PingSample>[];
    probe.outcomes.listen(samples.add);

    await probe.pingNow();

    expect((await onlyCorrelation()).ackStatus, AckStatus.received);
    final ack = (await events(PacketDirection.ack)).single;
    expect(ack.hopCount, 1);
    expect(ack.rxSnr, isNull);
    expect(ack.rxRssi, isNull);
    expect(probe.pingsOk, 1);
    expect(probe.lastAckSnr, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(samples.single.snr, isNull);
    expect(samples.single.fromBase, isFalse);
  });

  test('a relayed ACK keeps its signal when counting relayed is on', () async {
    probe.dispose();
    probe = ActiveProbeService(
        db: db, radio: radio, gps: GpsService(), countRelayed: () => true);
    probe.start(sessionId: sessionId, baseMeshNodeId: base);
    radio.script.add((id) => PingOutcome(
          pingId: id,
          status: PingStatus.received,
          responder: base,
          replyPacketId: 79,
          snr: 5.5,
          rssi: -90,
          hops: 1,
          roundTrip: const Duration(milliseconds: 1200),
        ));
    await probe.pingNow();
    final ack = (await events(PacketDirection.ack)).single;
    expect(ack.hopCount, 1);
    expect(ack.rxSnr, 5.5);
  });

  test('implicit: ACK from another node does not count as delivered', () async {
    radio.script.add((id) => PingOutcome(
          pingId: id,
          status: PingStatus.implicit,
          responder: 9,
          replyPacketId: 5,
          snr: 2,
          rssi: -100,
          roundTrip: const Duration(milliseconds: 900),
        ));
    await probe.pingNow();

    expect((await onlyCorrelation()).ackStatus, AckStatus.implicit);
    expect(probe.pingsAnswered, 1);
    expect(probe.pingsOk, 0);
    expect(probe.lastAckAt, isNull);
  });

  test('throttled: duty-cycle NAK is counted separately', () async {
    radio.script.add((id) => PingOutcome(
          pingId: id,
          status: PingStatus.throttled,
          errorReason: 'DUTY_CYCLE_LIMIT',
          responder: 1,
          roundTrip: const Duration(milliseconds: 50),
        ));
    await probe.pingNow();

    expect((await onlyCorrelation()).ackStatus, AckStatus.throttled);
    expect(probe.pingsThrottled, 1);
    expect(probe.pingsOk, 0);
    expect(probe.pingsAnswered, 1);
  });

  test('error: NAK reason is kept in the status', () async {
    radio.script.add((id) => PingOutcome(
          pingId: id,
          status: PingStatus.error,
          errorReason: 'PKI_UNKNOWN_PUBKEY',
          responder: base,
          roundTrip: const Duration(milliseconds: 300),
        ));
    await probe.pingNow();

    expect((await onlyCorrelation()).ackStatus,
        AckStatus.errorWithReason('PKI_UNKNOWN_PUBKEY'));
    expect(probe.pingsAnswered, 1);
    expect(probe.pingsOk, 0);
  });

  test('send failure: marked error, not counted as answered', () async {
    radio.script.add((id) => PingOutcome(
          pingId: id,
          status: PingStatus.error,
          errorReason: 'SEND_FAILED',
          roundTrip: Duration.zero,
        ));
    await probe.pingNow();

    expect((await onlyCorrelation()).ackStatus,
        AckStatus.errorWithReason('SEND_FAILED'));
    expect(probe.pingsAnswered, 0);
    expect(await events(PacketDirection.ack), isEmpty);
  });

  for (final reason in ['RADIO_BUSY', 'LINK_LOST']) {
    test('$reason: not evidence, no sample for beacons or out-of-range',
        () async {
      // A MeshCore trace the radio never confirmed sending, or one cut off
      // by a Bluetooth drop, says nothing about range.
      radio.script.add((id) => PingOutcome(
            pingId: id,
            status: PingStatus.error,
            errorReason: reason,
            roundTrip: const Duration(seconds: 5),
          ));
      final samples = <PingSample>[];
      probe.outcomes.listen(samples.add);
      await probe.pingNow();

      expect((await onlyCorrelation()).ackStatus,
          AckStatus.errorWithReason(reason));
      expect(probe.pingsAnswered, 0);
      await Future<void>.delayed(Duration.zero);
      expect(samples, isEmpty);
    });
  }

  test('timeout: counted as answered, no ack event', () async {
    radio.script.add((id) => PingOutcome(
          pingId: id,
          status: PingStatus.timeout,
          roundTrip: const Duration(seconds: 30),
        ));
    final samples = <PingSample>[];
    probe.outcomes.listen(samples.add);
    await probe.pingNow();

    final corr = await onlyCorrelation();
    expect(corr.ackStatus, AckStatus.timeout);
    expect(corr.ackEventId, isNull);
    expect(probe.pingsAnswered, 1);
    expect(probe.pingsOk, 0);
    expect(await events(PacketDirection.ack), isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(samples.single.status, AckStatus.timeout);
  });

  test('tx event and correlation are written before the radio transmits',
      () async {
    int txBefore = -1, corrBefore = -1;
    radio.onTransmit = (id) async {
      txBefore = (await events(PacketDirection.tx)).length;
      corrBefore = (await db.getPingsForSession(sessionId)).length;
      final tx = (await events(PacketDirection.tx)).single;
      expect(tx.meshPacketId, id);
      expect(tx.packetType, PacketType.ping);
    };
    await probe.pingNow();

    expect(txBefore, 1);
    expect(corrBefore, 1);
    expect(radio.log.first, startsWith('beforeSend:'));
    expect(radio.pingTargets, [base]);
  });

  test('stop() marks in-flight pings timed out and ignores later outcomes',
      () async {
    final gate = Completer<PingOutcome>();
    radio.script.add((id) => gate.future);
    final done = probe.pingNow();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    probe.stop();
    gate.complete(const PingOutcome(
      pingId: 1000,
      status: PingStatus.received,
      responder: base,
      roundTrip: Duration(seconds: 1),
    ));
    await done;

    expect((await onlyCorrelation()).ackStatus, AckStatus.timeout);
    expect(probe.pingsAnswered, 0);
    expect(await events(PacketDirection.ack), isEmpty);
  });

  group('public channel guard', () {
    Future<void> restartOnPublic() async {
      probe.stop();
      radio.preparedTargets.clear();
      radio.onPublicChannel = true;
      probe.start(sessionId: sessionId, baseMeshNodeId: base);
    }

    test('resumed on the public channel: no key exchange, no ping', () async {
      await restartOnPublic();
      expect(radio.preparedTargets, isEmpty);

      await probe.pingNow();

      expect(radio.pingTargets, isEmpty);
      expect(await db.getPingsForSession(sessionId), isEmpty);
      expect(probe.blockedReason.value, ActiveProbeService.publicChannelReason);
    });

    test('pings resume (after the key exchange) once the channel is private',
        () async {
      await restartOnPublic();
      await probe.pingNow();
      expect(radio.pingTargets, isEmpty);

      radio.onPublicChannel = false;
      await probe.pingNow();

      expect(radio.preparedTargets, [base]);
      expect(radio.pingTargets, [base]);
      expect(probe.blockedReason.value, isNull);
    });

    test('channel turning public mid-session stops pings', () async {
      await probe.pingNow();
      expect(radio.pingTargets, [base]);

      radio.onPublicChannel = true;
      await probe.pingNow();

      expect(radio.pingTargets, [base]);
      expect(probe.blockedReason.value, isNotNull);
    });
  });

  group('key exchange after reconnect', () {
    test('runs again when the radio becomes ready, before the next ping',
        () async {
      expect(radio.preparedTargets, [base]);
      await Future<void>.delayed(Duration.zero);

      radio.setState(RadioConnectionState.reconnecting);
      radio.setState(RadioConnectionState.ready);
      await Future<void>.delayed(Duration.zero);

      expect(radio.preparedTargets, [base, base]);
      await probe.pingNow();
      expect(radio.preparedTargets, [base, base]);
      expect(radio.pingTargets, [base]);
    });

    test('resumed before the radio connects: exchange runs on ready', () async {
      probe.stop();
      radio.preparedTargets.clear();
      radio.setState(RadioConnectionState.disconnected);
      probe.start(sessionId: sessionId, baseMeshNodeId: base);
      await Future<void>.delayed(Duration.zero);
      expect(radio.preparedTargets, isEmpty);

      radio.setState(RadioConnectionState.ready);
      await Future<void>.delayed(Duration.zero);

      expect(radio.preparedTargets, [base]);
    });

    test('a reconnect onto the public channel exchanges nothing', () async {
      await Future<void>.delayed(Duration.zero);
      radio.onPublicChannel = true;
      radio.setState(RadioConnectionState.disconnected);
      radio.setState(RadioConnectionState.ready);
      await Future<void>.delayed(Duration.zero);

      expect(radio.preparedTargets, [base]);
      await probe.pingNow();
      expect(radio.pingTargets, isEmpty);
    });

    test('no exchange after stop()', () async {
      await Future<void>.delayed(Duration.zero);
      probe.stop();
      radio.setState(RadioConnectionState.disconnected);
      radio.setState(RadioConnectionState.ready);
      await Future<void>.delayed(Duration.zero);

      expect(radio.preparedTargets, [base]);
    });
  });
}
