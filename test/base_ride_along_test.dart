// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/models/processed_signal_event.dart';
import 'package:mesh_analyzer/services/active_probe_service.dart';
import 'package:mesh_analyzer/services/base_ride_along_detector.dart';
import 'package:mesh_analyzer/utils/constants.dart';

/// The base left in the car, then driven off with the session still
/// recording (field use, 2026-10-28): noticed, and the tail can be trimmed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime(2026, 10, 28, 14, 0);

  /// A walk near the base (slow, close, strong), then [driveSecs] of
  /// driving starting at [driveAt]: one fix a second at [speed] m/s with
  /// the distance from the base going `d0 + i * dStep` (or [dist] when
  /// given), and a base sample every [every] s at `rssi0 + i * rssiStep`.
  List<RideAlongSample> scenario({
    required DateTime driveAt,
    int driveSecs = 60,
    double speed = 10,
    double d0 = 60,
    double dStep = 10,
    double Function(int i)? dist,
    int rssi0 = -58,
    double rssiStep = 0,
    int every = 10,
  }) {
    final out = <RideAlongSample>[];
    for (var i = 0; i < 120; i += 5) {
      final at = driveAt.subtract(Duration(seconds: 120 - i));
      out
        ..add(RideAlongSample.fix(at, speedMps: 1.2, distanceM: 40))
        ..add(RideAlongSample.signal(at, rssi: -60));
    }
    for (var i = 0; i <= driveSecs; i++) {
      final at = driveAt.add(Duration(seconds: i));
      out.add(RideAlongSample.fix(at,
          speedMps: speed, distanceM: dist?.call(i) ?? d0 + i * dStep));
      if (i % every == every - 1) {
        out.add(
            RideAlongSample.signal(at, rssi: (rssi0 + i * rssiStep).round()));
      }
    }
    return out;
  }

  final driveAt = t0.add(const Duration(minutes: 20));
  RideAlongEvent? eval(List<RideAlongSample> s, {int afterSecs = 60}) =>
      evaluateRideAlong(s,
          now: driveAt.add(Duration(seconds: afterSecs)), sessionStart: t0);

  group('rule', () {
    test('driving away with the base fires from the start of the drive', () {
      final e = eval(scenario(driveAt: driveAt));
      expect(e, isNotNull);
      expect(e!.startedAt, driveAt);
      expect(e.samplesSince, 6);
    });

    test('driving past the parked base does not fire', () {
      // 300 m out, past the base, 400 m the other side.
      final e = eval(scenario(
          driveAt: driveAt,
          driveSecs: 70,
          dist: (i) => (300 - 10.0 * i).abs()));
      expect(e, isNull);
    });

    test('walking fast with a strong signal does not fire', () {
      expect(eval(scenario(driveAt: driveAt, speed: 2.5, d0: 150, dStep: 3)),
          isNull);
    });

    test('driving away at normal range with a weakening signal does not fire',
        () {
      // Fading below −75 dBm.
      expect(
          eval(scenario(driveAt: driveAt, d0: 500, rssi0: -70, rssiStep: -0.4)),
          isNull);
      // Still strong but not steady (−60 → −74 dBm).
      expect(
          eval(
              scenario(driveAt: driveAt, d0: 500, rssi0: -60, rssiStep: -0.25)),
          isNull);
    });

    test('never within the first 60 s of a session', () {
      final s = scenario(driveAt: driveAt);
      expect(
          evaluateRideAlong(s,
              now: driveAt.add(const Duration(seconds: 50)),
              sessionStart: driveAt.subtract(const Duration(seconds: 5))),
          isNull);
    });

    test('not before 20 s of driving, nor with too few base samples', () {
      expect(
          eval(scenario(driveAt: driveAt, driveSecs: 15, dStep: 20)), isNull);
      expect(eval(scenario(driveAt: driveAt, every: 30)), isNull);
    });

    test('inaccurate fixes are ignored, not a break in the drive', () {
      final s = scenario(driveAt: driveAt)
        ..add(RideAlongSample.fix(driveAt.add(const Duration(seconds: 30)),
            speedMps: 0, accuracyM: 80, distanceM: 10));
      expect(eval(s)?.startedAt, driveAt);
    });
  });

  group('short stops', () {
    /// Fixes once a second through [legs] of (seconds, m/s) from
    /// [driveAt] (walking before it), the distance growing with the
    /// speed; a strong base sample every 10 s.
    List<RideAlongSample> legs(List<(int, double)> legs) {
      final out = <RideAlongSample>[
        RideAlongSample.fix(driveAt.subtract(const Duration(seconds: 30)),
            speedMps: 1.2, distanceM: 40),
      ];
      var t = 0;
      var d = 60.0;
      for (final (secs, speed) in legs) {
        for (var i = 0; i < secs; i++, t++) {
          final at = driveAt.add(Duration(seconds: t));
          out.add(RideAlongSample.fix(at, speedMps: speed, distanceM: d));
          if (t % 10 == 9) out.add(RideAlongSample.signal(at, rssi: -58));
          d += speed;
        }
      }
      return out;
    }

    RideAlongEvent? evalAt(List<RideAlongSample> s) => evaluateRideAlong(s,
        now: s.last.at.add(const Duration(seconds: 1)), sessionStart: t0);

    test('a 30 s red light keeps the original departure', () {
      final e = evalAt(legs([(15, 12), (30, 0), (40, 12)]));
      expect(e?.startedAt, driveAt);
    });

    test('a 2 minute stop starts the run again at the second departure', () {
      final e = evalAt(legs([(30, 12), (120, 0), (40, 12)]));
      expect(e, isNotNull);
      expect(e!.startedAt, driveAt.add(const Duration(seconds: 150)));
    });

    test('stopped seconds do not count toward the moving minimum', () {
      // 10 s moving (fixes 0..10), 29 s stopped, then moving again: the
      // run has 20 s of movement once the second leg has 10 s of its own.
      final s = legs([(11, 15), (29, 0), (11, 15)]);
      final secondLeg = driveAt.add(const Duration(seconds: 40));
      List<RideAlongSample> upTo(int secs) => [
            for (final x in s)
              if (!x.at.isAfter(secondLeg.add(Duration(seconds: secs)))) x
          ];
      // 10 + 9 s moving, though 49 s since departure.
      expect(evalAt(upTo(9)), isNull);
      expect(evalAt(upTo(10))?.startedAt, driveAt);
    });
  });

  group('service', () {
    late AppDatabase db;
    late int mapId;
    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      final base = await db.upsertNode(nodeId: 2);
      mapId = await db.createCoverageMap(name: 'Polo', baseNodeId: base);
      await db.setMapBaseLocation(mapId, 33.68, -116.24);
    });
    tearDown(() => db.close());

    test('fires once a session, again after a new start', () async {
      var now = driveAt.add(const Duration(seconds: 60));
      final positions = StreamController<Position>.broadcast();
      final signals = StreamController<ProcessedSignalEvent>.broadcast();
      final pings = StreamController<PingSample>.broadcast();
      final d = BaseRideAlongDetector(
        db: db,
        positions: positions.stream,
        signals: signals.stream,
        pings: pings.stream,
        clock: () => now,
      );
      addTearDown(d.dispose);
      final fired = <RideAlongEvent>[];
      d.events.listen(fired.add);
      final sid = await db.createSession(coverageMapId: mapId);
      final session = (await db.getSessionById(sid))!
          .copyWith(startedAt: t0); // started 20 min before the drive
      await d.start(session, 2);
      expect(d.sessionId, sid);

      for (final s in scenario(driveAt: driveAt)) {
        d.addSample(s);
      }
      await Future<void>.delayed(Duration.zero);
      expect(fired, hasLength(1));
      expect(fired.single.startedAt, driveAt);
      expect(d.pending.value, isNotNull);

      // More of the same: no second event; the banner's count follows.
      final before = d.pending.value!.samplesSince;
      for (final s in scenario(
          driveAt: driveAt.add(const Duration(seconds: 61)), d0: 700)) {
        d.addSample(s);
      }
      await Future<void>.delayed(Duration.zero);
      expect(fired, hasLength(1));
      expect(d.pending.value!.samplesSince, greaterThan(before));

      d.dismiss();
      expect(d.pending.value, isNull);
      for (final s in scenario(driveAt: driveAt)) {
        d.addSample(s);
      }
      expect(d.pending.value, isNull);

      // A new session may fire again.
      d.stop();
      now = driveAt.add(const Duration(seconds: 60));
      await d.start(session, 2);
      for (final s in scenario(driveAt: driveAt)) {
        d.addSample(s);
      }
      await Future<void>.delayed(Duration.zero);
      expect(fired, hasLength(2));
    });

    test('ignores relayed and other radios\' packets', () async {
      final now = driveAt.add(const Duration(seconds: 60));
      final positions = StreamController<Position>.broadcast();
      final signals = StreamController<ProcessedSignalEvent>.broadcast();
      final pings = StreamController<PingSample>.broadcast();
      final d = BaseRideAlongDetector(
        db: db,
        positions: positions.stream,
        signals: signals.stream,
        pings: pings.stream,
        clock: () => now,
      );
      addTearDown(d.dispose);
      final sid = await db.createSession(coverageMapId: mapId);
      await d.start((await db.getSessionById(sid))!.copyWith(startedAt: t0), 2);
      for (final s in scenario(driveAt: driveAt)) {
        if (s.isFix) d.addSample(s);
      }
      for (var i = 0; i < 6; i++) {
        final at = driveAt.add(Duration(seconds: 10 * i + 5));
        signals.add(ProcessedSignalEvent(
            timestamp: at,
            sourceNodeId: 3, // not the base
            rxRssi: -50,
            packetType: PacketType.telemetry,
            direction: PacketDirection.rx));
        signals.add(ProcessedSignalEvent(
            timestamp: at,
            sourceNodeId: 2,
            hopCount: 1, // relayed
            rxRssi: -50,
            packetType: PacketType.telemetry,
            direction: PacketDirection.rx));
      }
      await Future<void>.delayed(Duration.zero);
      expect(d.pending.value, isNull);
      // Ping replies from the base count.
      for (var i = 0; i < 3; i++) {
        final at = driveAt.add(Duration(seconds: 10 * i + 30));
        pings.add(PingSample(
            sentAt: at,
            answeredAt: at,
            status: AckStatus.received,
            rssi: -55,
            fromBase: true));
      }
      await Future<void>.delayed(Duration.zero);
      expect(d.pending.value?.startedAt, driveAt);
    });
  });

  group('trimSessionAfter', () {
    test('drops events from the time on, with their correlations', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final base = await db.upsertNode(nodeId: 2);
      final map = await db.createCoverageMap(name: 'Polo', baseNodeId: base);
      final a = await db.createSession(coverageMapId: map);
      final b = await db.createSession(coverageMapId: map);
      final cut = DateTime(2025, 6, 1, 14, 32);

      Future<int> ev(int sid, DateTime at, String dir) =>
          db.insertPacketEvent(PacketEventsCompanion.insert(
            sessionId: sid,
            timestamp: at,
            direction: dir,
            sourceNodeId: base,
            packetType: PacketType.ping,
            rxRssi: const Value(-60),
          ));
      Future<void> pair(int sid, DateTime at) async {
        final tx = await ev(sid, at, PacketDirection.tx);
        final ack = await ev(
            sid, at.add(const Duration(seconds: 1)), PacketDirection.ack);
        await db.insertPingCorrelation(PingCorrelationsCompanion.insert(
            txEventId: tx, ackEventId: Value(ack)));
      }

      await pair(a, cut.subtract(const Duration(minutes: 5)));
      await ev(a, cut.subtract(const Duration(minutes: 1)), PacketDirection.rx);
      await pair(a, cut);
      await pair(a, cut.add(const Duration(minutes: 3)));
      await ev(a, cut.add(const Duration(minutes: 4)), PacketDirection.rx);
      await pair(b, cut.add(const Duration(minutes: 3)));
      await db.endSession(a);

      final r = await db.trimSessionAfter(a, cut);
      expect(r.deleted, 5);
      expect(r.received, 3); // two ACKs and one rx; TX pings aren't points

      final left = await db.getEventsForSession(a);
      expect(left, hasLength(3));
      expect(left.every((e) => e.timestamp.isBefore(cut)), isTrue);
      expect(await db.getEventsForSession(b), hasLength(2));
      final corr = await db.select(db.pingCorrelations).get();
      expect(corr, hasLength(2)); // a's first pair and b's
      final s = (await db.getSessionById(a))!;
      expect(s.endedAt, cut);
      expect(s.packetCount, 3);
    });
  });
}
