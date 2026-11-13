// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/services/last_radio.dart';
import 'package:mesh_analyzer/services/live_activity_service.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:mesh_analyzer/services/rig_comparison.dart';
import 'package:mesh_analyzer/services/session_manager.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_location_backend.dart';
import 'fakes/fake_mesh_radio.dart';

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;
  late FakeMeshRadio radio;
  late FakeLocationBackend location;
  late ProviderContainer container;
  late int mapId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    radio = FakeMeshRadio();
    location = FakeLocationBackend();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      meshRadioProvider.overrideWithValue(radio),
      gpsServiceProvider.overrideWithValue(GpsService(backend: location)),
    ]);
    final base = await db.upsertNode(nodeId: 2);
    mapId = await db.createCoverageMap(name: 'Polo', baseNodeId: base);
    addTearDown(() async {
      await container.read(sessionManagerProvider).endSession();
      container.dispose();
      await radio.dispose();
      await db.close();
    });
  });

  group('Start Session and location', () {
    test('refused with a clear message when location is denied', () async {
      location.permission = LocationPermission.deniedForever;
      final sessions = container.read(sessionManagerProvider);
      await expectLater(
        sessions.startSession(coverageMapId: mapId, baseMeshNodeId: 2),
        throwsA(isA<SessionStartError>().having(
            (e) => e.message, 'message', contains('Location permission'))),
      );
      expect(sessions.activeSession, isNull);
    });

    test('refused when Location Services are off', () async {
      location.serviceEnabled = false;
      await expectLater(
        container.read(sessionManagerProvider).startSession(
              coverageMapId: mapId,
              baseMeshNodeId: 2,
            ),
        throwsA(isA<SessionStartError>()),
      );
    });

    test('retries GPS: allowed since launch starts listening', () async {
      final gps = container.read(gpsServiceProvider);
      location.permission = LocationPermission.deniedForever;
      await gps.ensureStarted();
      expect(gps.isListening, isFalse);

      location.permission = LocationPermission.whileInUse;
      final session = await container
          .read(sessionManagerProvider)
          .startSession(coverageMapId: mapId, baseMeshNodeId: 2);
      expect(session.isActive, isTrue);
      expect(gps.isListening, isTrue);
      // No fix yet is only a warning: the session runs.
      expect(gps.state.status, GpsStatus.searching);
    });
  });

  group('deleting a coverage map', () {
    test('the recording map is protected', () async {
      final sessions = container.read(sessionManagerProvider);
      await sessions.startSession(coverageMapId: mapId, baseMeshNodeId: 2);
      expect(sessions.isRecordingInto(mapId), isTrue);
      expect(sessions.isRecordingInto(mapId + 1), isFalse);
      await sessions.endSession();
      expect(sessions.isRecordingInto(mapId), isFalse);
    });

    test('removes sessions, packets and ping links together', () async {
      final session = await db.createSession(coverageMapId: mapId);
      final source = await db.upsertNode(nodeId: 4);
      Future<int> event(String type) =>
          db.insertPacketEvent(PacketEventsCompanion.insert(
            sessionId: session,
            timestamp: DateTime(2026),
            direction: PacketDirection.tx,
            sourceNodeId: source,
            packetType: type,
          ));
      final tx = await event(PacketType.ping);
      final ack = await event(PacketType.ack);
      await db.insertPingCorrelation(PingCorrelationsCompanion.insert(
          txEventId: tx, ackEventId: Value(ack)));

      expect(await db.coverageMapCounts(mapId), (sessions: 1, packets: 2));
      await db.deleteCoverageMap(mapId);

      expect(await db.getAllCoverageMaps(), isEmpty);
      expect(await db.getEventsForSession(session), isEmpty);
      expect(await db.select(db.pingCorrelations).get(), isEmpty);
    });
  });

  group('deleting sessions', () {
    test('removes only the chosen sessions, with packets and ping links',
        () async {
      final gone = await db.createSession(coverageMapId: mapId);
      final kept = await db.createSession(coverageMapId: mapId);
      final source = await db.upsertNode(nodeId: 4);
      Future<int> event(int session, String type) =>
          db.insertPacketEvent(PacketEventsCompanion.insert(
            sessionId: session,
            timestamp: DateTime(2026),
            direction: PacketDirection.tx,
            sourceNodeId: source,
            packetType: type,
          ));
      final tx = await event(gone, PacketType.ping);
      final ack = await event(gone, PacketType.ack);
      await db.insertPingCorrelation(PingCorrelationsCompanion.insert(
          txEventId: tx, ackEventId: Value(ack)));
      await event(kept, PacketType.ping);

      await db.deleteSessions([gone]);

      expect(await db.getAllCoverageMaps(), hasLength(1));
      expect(await db.coverageMapCounts(mapId), (sessions: 1, packets: 1));
      expect(await db.getEventsForSession(gone), isEmpty);
      expect(await db.select(db.pingCorrelations).get(), isEmpty);
    });

    test('saved comparisons using a deleted session are dropped', () async {
      final store =
          SavedComparisonStore(container.read(sharedPreferencesProvider));
      SavedComparison cmp(List<int> a, List<int> b) => SavedComparison(
          mapId: mapId,
          sessionIdsA: a,
          sessionIdsB: b,
          createdAt: DateTime(2026));
      await store.add(cmp([1], [2]));
      await store.add(cmp([3], [4, 5]));
      await store.removeSessions({5});
      expect(store.all().map((c) => c.sessionIdsA), [
        [1]
      ]);
    });
  });

  group('Live Activity', () {
    // An iPhone (tests run as Android, where there is none).
    setUp(() => LiveActivityService.deviceSupported = true);
    tearDown(() => LiveActivityService.deviceSupported = false);

    test('an iPad starts nothing and reports no problem', () async {
      LiveActivityService.deviceSupported = false;
      final service = container.read(liveActivityServiceProvider)
        ..allowed = () => false; // not even the Pro line
      final calls = <String>[];
      service.invoke = (method, [args]) async {
        calls.add(method);
        return 'ok';
      };
      service.start();
      await container
          .read(sessionManagerProvider)
          .startSession(coverageMapId: mapId, baseMeshNodeId: 2);
      await pumpEventQueue();
      expect(calls, isNot(contains('start')));
      expect(service.problem.value, isNull);
      await service.dispose();
    });

    test('a session that ends while the activity starts leaves no orphan',
        () async {
      final service = container.read(liveActivityServiceProvider)
        ..allowed = () => true; // a Pro user
      final calls = <String>[];
      final started = Completer<String?>();
      service.invoke = (method, [args]) {
        calls.add(method);
        return method == 'start' ? started.future : Future.value(null);
      };
      service.start();

      final sessions = container.read(sessionManagerProvider);
      await sessions.startSession(coverageMapId: mapId, baseMeshNodeId: 2);
      await pumpEventQueue();
      expect(calls, ['start']);

      await sessions.endSession(); // while iOS is still starting it
      await pumpEventQueue();
      started.complete('ok');
      await pumpEventQueue();

      expect(calls, ['start', 'end']);
      expect(service.problem.value, isNull);
      await service.dispose();
    });

    test('without Pro no activity starts, and buying Pro starts it', () async {
      final service = container.read(liveActivityServiceProvider)
        ..allowed = () => true; // a Pro user
      final calls = <String>[];
      service.invoke = (method, [args]) async {
        calls.add(method);
        return 'ok';
      };
      var pro = false;
      service.allowed = () => pro;
      service.start();
      await container
          .read(sessionManagerProvider)
          .startSession(coverageMapId: mapId, baseMeshNodeId: 2);
      await pumpEventQueue();
      expect(calls, isEmpty);
      expect(service.problem.value, 'pro');
      await service.dispose();
    });

    test('a refused activity is reported as the problem', () async {
      final service = container.read(liveActivityServiceProvider)
        ..allowed = () => true; // a Pro user
      service.invoke = (method, [args]) async => 'disabled';
      service.start();
      await container
          .read(sessionManagerProvider)
          .startSession(coverageMapId: mapId, baseMeshNodeId: 2);
      await pumpEventQueue();
      expect(service.problem.value, 'disabled');
      await service.dispose();
    });

    test('a start refused in the background is retried on resume', () async {
      final service = container.read(liveActivityServiceProvider)
        ..allowed = () => true; // a Pro user
      final calls = <String>[];
      var reply = 'background';
      service.invoke = (method, [args]) async {
        calls.add(method);
        return method == 'start' ? reply : null;
      };
      service.start();
      await container
          .read(sessionManagerProvider)
          .startSession(coverageMapId: mapId, baseMeshNodeId: 2);
      await pumpEventQueue();
      expect(service.problem.value, 'background');
      expect(calls, ['start']);

      // Still backgrounded: another resume is harmless, and no activity
      // was started so nothing is ended.
      reply = 'ok';
      service.appResumed();
      await pumpEventQueue();
      expect(calls, ['start', 'start']);
      expect(service.problem.value, isNull);

      // Running now: a further resume does nothing.
      service.appResumed();
      await pumpEventQueue();
      expect(calls, ['start', 'start']);
      await service.dispose();
    });
  });

  group('LastRadio', () {
    test('remembers the last radio, but never prefers the base', () async {
      final last = LastRadio(prefs);
      expect(last.load(), isNull);

      await last.save(const RadioDescriptor(id: 'B', name: 'Base'));
      expect(last.load()!.id, 'B');

      final roles = RadioRoles(prefs);
      await roles.assign(RadioRole.base, deviceId: 'B');
      await roles.assign(RadioRole.mobile, deviceId: 'M');
      expect(last.load()!.id, 'M');

      await last.save(const RadioDescriptor(id: 'M2', name: 'Pocket'));
      expect(last.load(), const RadioDescriptor(id: 'M2', name: 'Pocket'));
      expect(last.load()!.name, 'Pocket');
    });
  });
}
