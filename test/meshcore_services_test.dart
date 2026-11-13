// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_presets.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_protocol.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/models/processed_signal_event.dart';
import 'package:mesh_analyzer/services/active_probe_service.dart';
import 'package:mesh_analyzer/services/airtime_model.dart';
import 'package:mesh_analyzer/services/beacon_tracker.dart';
import 'package:mesh_analyzer/services/export/csv_v2.dart';
import 'package:mesh_analyzer/services/export/export_data.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/services/out_of_range_monitor.dart';
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/services/packet_processor.dart';
import 'package:mesh_analyzer/services/radio_backup_service.dart';
import 'package:mesh_analyzer/services/radio_profile_service.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:mesh_analyzer/services/range_test_detector.dart';
import 'package:mesh_analyzer/services/session_manager.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_location_backend.dart';
import 'fakes/fake_mesh_radio.dart';
import 'meshcore/fake_meshcore_transport.dart' as mc;

/// MeshCore in the service layer: the pulled (trace) beacon, uplink SNR,
/// log-only packets and protocol-neutral Radio Setup.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final usa = MeshCorePresets.usa.radioPreset;

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  group('AirtimeModel trace', () {
    test('a trace exchange is both legs (USA ≈ 109 + 119 ms)', () {
      final ms = AirtimeModel.traceAirtimeMs(usa);
      expect(ms, closeTo(228, 3));
      expect(
          AirtimeModel.probeAirtimeMsFor(usa, protocol: RadioProtocol.meshcore),
          ms);
      // Meshtastic keeps its DM ping size.
      expect(AirtimeModel.probeAirtimeMsFor(usa),
          AirtimeModel.pingAirtimeMs(usa));
    });

    test('the floor uses the trace airtime on MeshCore', () {
      final slow = MeshCorePresets.euUkDeprecated.radioPreset; // SF11/250
      final trace = AirtimeModel.minIntervalSecFor(slow,
          protocol: RadioProtocol.meshcore);
      expect(trace,
          AirtimeModel.minIntervalForAirtime(AirtimeModel.traceAirtimeMs(slow)));
      expect(trace, isNot(AirtimeModel.minIntervalSecFor(slow)));
      expect(
          AirtimeModel.minIntervalSecFor(usa, protocol: RadioProtocol.meshcore),
          AirtimeModel.minIntervalFloorSec);
      expect(
          AirtimeModel.fastestIntervalSecFor(usa,
              protocol: RadioProtocol.meshcore),
          AirtimeModel.overrideFloorSec);
    });
  });

  group('BeaconTracker trace kind', () {
    test('timeouts are misses, 3 in a row is absent, no timing misses', () {
      final t = BeaconTracker();
      final t0 = DateTime(2026, 10, 29, 12);
      t.start(baseNodeId: 2, kind: BeaconKind.trace, intervalSec: 10, now: t0);
      expect(t.accepts(BeaconKind.rangeTest), isFalse);
      expect(t.accepts(BeaconKind.telemetry), isFalse);
      t.onBeacon(BeaconKind.trace, t0.add(const Duration(seconds: 10)));
      t.onTraceTimeout(t0.add(const Duration(seconds: 20)));
      t.onTraceTimeout(t0.add(const Duration(seconds: 30)));
      expect(t.absent, isFalse);
      expect(t.dueMisses(t0.add(const Duration(minutes: 5))), isEmpty);
      t.onTraceTimeout(t0.add(const Duration(seconds: 40)));
      expect(t.traceMissed, 3);
      expect(t.absent, isTrue);
      // The next answer brings it back.
      t.onBeacon(BeaconKind.trace, t0.add(const Duration(seconds: 50)));
      expect(t.absent, isFalse);
      expect(t.heard, 2);
      // Timing never makes misses up, however long the silence.
      expect(t.dueMisses(t0.add(const Duration(hours: 1))), isEmpty);
      expect(t.absent, isFalse);
      t.dispose();
    });

    test('timeouts are ignored for other kinds', () {
      final t = BeaconTracker()
        ..start(baseNodeId: 2, kind: BeaconKind.telemetry, intervalSec: 60);
      for (var i = 0; i < 5; i++) {
        t.onTraceTimeout(DateTime.now());
      }
      expect(t.traceMissed, 0);
      expect(t.absent, isFalse);
      t.dispose();
    });
  });

  group('MeshCore session', () {
    const base = 2;
    late AppDatabase db;
    late FakeMeshRadio radio;
    late SharedPreferences prefs;
    late OutOfRangeMonitor monitor;
    late PacketProcessor processor;
    late ActiveProbeService probe;
    late SessionManager manager;
    late int mapId;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      radio = FakeMeshRadio(
          myNodeId: 1, currentPreset: usa, protocol: RadioProtocol.meshcore);
      final gps = GpsService(backend: FakeLocationBackend());
      monitor = OutOfRangeMonitor(
          notifications: FlutterLocalNotificationsPlugin(), radio: radio);
      processor = PacketProcessor(
        db: db,
        radio: radio,
        gps: gps,
        rangeTestDetector: RangeTestDetector(),
        outOfRangeMonitor: monitor,
      )..start();
      probe = ActiveProbeService(db: db, radio: radio, gps: gps);
      manager = SessionManager(
        db: db,
        radio: radio,
        gps: gps,
        packetProcessor: processor,
        rangeTestDetector: RangeTestDetector(),
        activeProbeService: probe,
        outOfRangeMonitor: monitor,
        prefs: prefs,
      );
      await db.upsertNode(nodeId: base, longName: 'MeshTest Base');
      mapId = await db.createCoverageMap(name: 'Polo');
    });

    tearDown(() async {
      await manager.endSession();
      manager.dispose();
      probe.dispose();
      processor.dispose();
      monitor.dispose();
      await radio.dispose();
      await db.close();
    });

    Future<void> setBeacon(int secs) => RadioRoles(prefs).recordBeacon(secs > 0
        ? BeaconConfig(intervalSec: secs, kind: BeaconKind.trace)
        : const BeaconConfig.off());

    Future<Session> start({int ping = 0}) => manager.startSession(
        coverageMapId: mapId, baseMeshNodeId: base, pingIntervalSec: ping);

    test('base beacon only: the probe runs at the beacon interval', () async {
      await setBeacon(20);
      final s = await start();
      expect(s.protocol, 'meshcore');
      expect(s.beaconKind, 'trace');
      expect(s.beaconIntervalSec, 20);
      expect(s.pingIntervalSec, 0);
      expect(s.packetAirtimeMs, AirtimeModel.traceAirtimeMs(usa));
      expect(probe.isActive, isTrue);
      expect(probe.intervalSec, 20);
      expect(processor.beacons.kind, BeaconKind.trace);
      expect(processor.beacons.intervalSec, 20);
    });

    test('pings only: the probe runs at the ping interval', () async {
      await setBeacon(0);
      final s = await start(ping: 30);
      expect(s.beaconKind, 'trace');
      expect(s.beaconIntervalSec, 0);
      expect(s.pingIntervalSec, 30);
      expect(probe.intervalSec, 30);
    });

    test('both on: the smaller interval wins', () async {
      await setBeacon(20);
      await start(ping: 10);
      expect(probe.intervalSec, 10);
      await manager.endSession();
      await setBeacon(15);
      await start(ping: 60);
      expect(probe.intervalSec, 15);
    });

    test('both off: refused, nothing recorded', () async {
      await setBeacon(0);
      await expectLater(start(), throwsA(isA<StateError>()));
      await expectLater(start(), throwsA(isA<SessionStartError>()));
      expect(manager.activeSession, isNull);
      expect(await db.getSessionsForMap(mapId), isEmpty);
      expect(SessionManager.meshCoreProbeIntervalSec(
              pingIntervalSec: 0, beaconIntervalSec: 0),
          0);
    });

    test('a Meshtastic beacon kind left in Radio Setup does not count',
        () async {
      await RadioRoles(prefs).recordBeacon(
          const BeaconConfig(intervalSec: 60, kind: BeaconKind.telemetry));
      await expectLater(start(), throwsA(isA<SessionProbeOffError>()));
    });

    test('a received trace is a beacon sample with uplink SNR, and the base '
        'is heard', () async {
      await setBeacon(20);
      final s = await start();
      radio.script.add((id) => PingOutcome(
            pingId: id,
            status: PingStatus.received,
            responder: base,
            snr: 4.5,
            rssi: -97,
            uplinkSnr: 7.25,
            roundTrip: const Duration(milliseconds: 300),
          ));
      final samples = <PingSample>[];
      final sub = probe.outcomes.listen(samples.add);
      await probe.pingNow();
      await settle();
      await sub.cancel();

      final ack = (await db.getEventsForSession(s.id))
          .singleWhere((e) => e.direction == PacketDirection.ack);
      expect(ack.uplinkSnr, 7.25);
      expect(ack.rxSnr, 4.5);
      expect(samples.single.uplinkSnr, 7.25);
      expect(probe.lastUplinkSnr, 7.25);
      expect(processor.beacons.heard, 1);
      expect(monitor.lastHeardBase, isNotNull);

      final stats = await db.watchBeaconStats(s.id).first;
      expect((stats.heard, stats.missed, stats.exact), (1, 0, true));

      // Full CSV carries it; older columns keep their place.
      final exp = await ExportLoader(db).session(s.id);
      final header = csvV2Header;
      expect(header.last, 'uplink_snr');
      final props = eventProperties(
          exp!, exp.events.singleWhere((e) => e.event.id == ack.id));
      expect(props['uplink_snr'], 7.25);
    });

    test('trace timeouts are beacon misses; 3 in a row is absent; no '
        'timing-made misses', () async {
      await setBeacon(20);
      final s = await start();
      for (var i = 0; i < 3; i++) {
        await probe.pingNow(); // empty script: timeout
        await settle();
      }
      expect(processor.beacons.traceMissed, 3);
      expect(processor.beacons.absent, isTrue);
      await processor.tickBeacons(DateTime.now().add(const Duration(hours: 1)));
      final all = await db.getEventsForSession(s.id, includeMisses: true);
      expect(all.where((e) => e.sourceKind == SourceKind.telemetryMiss),
          isEmpty);
      // The newest timed-out ping may still read as in flight; the two
      // before it are counted.
      final stats = await db.watchBeaconStats(s.id).first;
      expect(stats.heard, 0);
      expect(stats.missed, greaterThanOrEqualTo(2));
      expect(stats.exact, isTrue);
    });

    test('a beacon change in Radio Setup retunes the running probe',
        () async {
      await setBeacon(30);
      final s = await start(ping: 60);
      expect(probe.intervalSec, 30);
      final service = RadioProfileService(radio, prefs);
      final applied = await service.setBaseBeacon(
          const BeaconConfig(intervalSec: 12, kind: BeaconKind.telemetry));
      expect(applied.kind, BeaconKind.trace);
      expect(radio.beacons, isEmpty); // nothing written to any radio
      await settle();
      expect(probe.intervalSec, 12);
      expect((await db.getSessionById(s.id))!.beaconIntervalSec, 12);
      // Off: the pings still run, at their own interval.
      await service.stopBaseBeacon();
      await settle();
      expect(probe.intervalSec, 60);
      expect(probe.isActive, isTrue);
    });

    test('a beacon change racing End never brings the session back',
        () async {
      await setBeacon(30);
      final s = await start(ping: 60);
      final emitted = <Session?>[];
      final sub = manager.sessionStream.listen(emitted.add);
      // The change is delivered at once: the retune is now waiting on its
      // database write when End is tapped.
      await setBeacon(12);
      await manager.endSession();
      await settle();
      expect(manager.activeSession, isNull);
      expect(probe.isActive, isFalse);
      expect(emitted, isNotEmpty);
      expect(emitted.last, isNull);
      expect((await db.getSessionById(s.id))!.endedAt, isNotNull);
      await sub.cancel();
    });

    test('resume restarts the trace schedule from the session row', () async {
      await setBeacon(20);
      final s = await start(ping: 40);
      await prefs.setInt(AppConstants.prefActiveSessionId, s.id);
      probe.stop();
      processor.stopBeaconTracking();
      await manager.initialize();
      expect(probe.intervalSec, 20);
      expect(processor.beacons.kind, BeaconKind.trace);
    });
  });

  group('log-only packets', () {
    const base = 2;
    late AppDatabase db;
    late FakeMeshRadio radio;
    late OutOfRangeMonitor monitor;
    late PacketProcessor processor;
    late int sessionId;
    late int mapId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      radio = FakeMeshRadio(protocol: RadioProtocol.meshcore);
      monitor = OutOfRangeMonitor(
          notifications: FlutterLocalNotificationsPlugin(), radio: radio);
      processor = PacketProcessor(
        db: db,
        radio: radio,
        gps: GpsService(),
        rangeTestDetector: RangeTestDetector(),
        outOfRangeMonitor: monitor,
      )..start();
      await db.upsertNode(nodeId: base);
      mapId = await db.createCoverageMap(name: 'm');
      sessionId = await db.createSession(
          coverageMapId: mapId,
          protocol: 'meshcore',
          beaconKind: BeaconKind.trace.dbValue,
          beaconIntervalSec: 20);
      processor.activeSessionId = sessionId;
      monitor.configure(baseNodeId: base, timeoutSec: 600);
      processor.startBeaconTracking(
          baseNodeId: base, kind: BeaconKind.trace, intervalSec: 20);
    });

    tearDown(() async {
      processor.dispose();
      monitor.dispose();
      await radio.dispose();
      await db.close();
    });

    test('stored, but never a sample, a dot or the base heard', () async {
      final emitted = <ProcessedSignalEvent>[];
      final sub = processor.signalStream.listen(emitted.add);
      radio.pushPacket(ReceivedPacket(
          from: base,
          type: PacketType.direct,
          snr: 6,
          rssi: -80,
          hops: 0,
          hopsKnown: false,
          routeDirect: true));
      await settle();
      await sub.cancel();

      final all = await db.getEventsForSession(sessionId, includeMisses: true);
      expect(all.single.sourceKind, SourceKind.logOnly);
      expect(all.single.rxSnr, 6);
      expect(await db.getEventsForSession(sessionId), isEmpty);
      expect(await db.watchEventsForMap(mapId).first, isEmpty);
      expect(
          await db.getEventsInBounds(
              coverageMapId: mapId,
              southLat: -90,
              northLat: 90,
              westLon: -180,
              eastLon: 180),
          isEmpty);
      expect(await db.watchPacketCount(sessionId).first, 0);
      expect(emitted, isEmpty);
      expect(monitor.lastHeardBase, isNull);
      expect(processor.beacons.heard, 0);

      final exp = (await ExportLoader(db).session(sessionId))!;
      expect(exp.events, hasLength(1));
      expect(exp.heardEvents, isEmpty);
    });

    test('a trace from another node is an ordinary passive sample', () async {
      radio.pushPacket(
          ReceivedPacket(from: 9, type: PacketType.trace, snr: 2, rssi: -90));
      await settle();
      final e = (await db.getEventsForSession(sessionId)).single;
      expect(e.sourceKind, SourceKind.passive);
      expect(e.packetType, PacketType.trace);
      expect(processor.beacons.heard, 0);
    });

    test('Meshtastic beacon packets do not count on a trace session',
        () async {
      radio.pushPacket(ReceivedPacket(
          from: base,
          type: PacketType.telemetry,
          snr: 3,
          rssi: -100,
          senderChannelUtil: 5));
      radio.pushPacket(ReceivedPacket(
          from: base, type: PacketType.rangeTest, beaconSeq: 4, snr: 1));
      await settle();
      expect(processor.beacons.heard, 0);
      expect(processor.beacons.kind, BeaconKind.trace);
      final kinds = {
        for (final e in await db.getEventsForSession(sessionId)) e.sourceKind
      };
      expect(kinds.contains(SourceKind.telemetry), isFalse);
    });
  });

  group('Radio Setup on MeshCore', () {
    late SharedPreferences prefs;
    late RadioRoles roles;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      roles = RadioRoles(prefs);
    });

    test('skips key exchange, passes frequency and power',
        () async {
      final phone = FakeMeshRadio(
          myNodeId: 10, currentPreset: usa, protocol: RadioProtocol.meshcore)
        ..settingsAfterProfile = const RadioSettings(
            region: '', frequencyMHz: 918.0, txPowerDbm: 20);
      await phone.connect(const RadioDescriptor(
          id: 'A', name: 'a', protocol: RadioProtocol.meshcore));
      final service = RadioProfileService(phone, prefs, null, null, roles);
      final steps = <String>[];
      await service.applyToConnected(RadioRole.base,
          preset: usa,
          beaconSecs: 20,
          onStep: steps.add,
          frequencyMHz: 918.0,
          txPowerDbm: 20);
      final p = phone.appliedProfiles.single;
      expect(p.isBase, isTrue);
      expect(p.frequencyMHz, 918.0);
      expect(p.txPowerDbm, 20);
      expect(p.baseRelays, isTrue);
      expect(p.channelKey, hasLength(32));
      expect(p.channelKey16, hasLength(16));
      expect(p.beacon?.kind, BeaconKind.trace);
      // The fake is neither radio class: no backup, and the steps say so
      // instead of claiming one.
      expect(steps.any((s) => s.contains('No backup for this node')), isTrue);
      expect(steps.any((s) => s.contains('Backing up')), isFalse);
      expect(steps.any((s) => s.contains('public key')), isFalse);
      expect(steps,
          contains('Link check from the mobile every 20 s'));
      expect(phone.beacons, isEmpty);
      expect(roles.baseBeacon?.kind, BeaconKind.trace);
      expect(roles.baseBeacon?.intervalSec, 20);
      expect(roles.frequencyOf(RadioRole.base), 918.0);
      expect(roles.txPowerOf(RadioRole.base), 20);

      // The mobile on another frequency is a mismatch.
      phone.settingsAfterProfile =
          const RadioSettings(frequencyMHz: 869.495, txPowerDbm: 20);
      phone.myNodeId = 20;
      await service.switchToAndApplyMobile(
          const RadioDescriptor(
              id: 'B', name: 'b', protocol: RadioProtocol.meshcore),
          preset: usa,
          onStep: (_) {},
          frequencyMHz: 869.495);
      expect(phone.appliedProfiles.last.frequencyMHz, 869.495);
      expect(roles.setupMismatch(), contains('frequency'));
    });

    test('a base over a second connection uses a MeshCore radio', () async {
      final phone =
          FakeMeshRadio(myNodeId: 10, protocol: RadioProtocol.meshcore);
      await phone.connect(const RadioDescriptor(
          id: 'M', name: 'm', protocol: RadioProtocol.meshcore));
      final made = <FakeMeshRadio>[];
      final service = RadioProfileService(phone, prefs, null, (p) {
        final r = FakeMeshRadio(myNodeId: 30, protocol: p);
        made.add(r);
        return r;
      }, roles);
      await service.applyToBase(
          const RadioDescriptor(
              id: 'B', name: 'b', protocol: RadioProtocol.meshcore),
          preset: usa,
          beaconSecs: 15,
          onStep: (_) {},
          frequencyMHz: 918.0,
          txPowerDbm: 22);
      expect(made.single.protocol, RadioProtocol.meshcore);
      expect(made.single.appliedProfiles.single.txPowerDbm, 22);
      expect(made.single.disposed, isTrue);
      expect(roles.nodeOf(RadioRole.base), 30);
    });

    test('refuses a base of another protocol', () async {
      final phone =
          FakeMeshRadio(myNodeId: 10, protocol: RadioProtocol.meshcore);
      await phone.connect(const RadioDescriptor(
          id: 'M', name: 'm', protocol: RadioProtocol.meshcore));
      final service = RadioProfileService(
          phone, prefs, null, (p) => FakeMeshRadio(protocol: p), roles);
      await expectLater(
          service.applyToBase(const RadioDescriptor(id: 'B', name: 'b'),
              preset: MeshtasticPresets.longFast,
              beaconSecs: 30,
              onStep: (_) {}),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              RadioProfileService.sameProtocolMessage)));
      // Base set up on the connected radio, mobile of another protocol.
      await expectLater(
          service.switchToAndApplyMobile(
              const RadioDescriptor(id: 'C', name: 'c'),
              preset: usa,
              onStep: (_) {}),
          throwsA(isA<StateError>()));
      expect(phone.descriptor?.id, 'M');
    });

    test('Meshtastic setup still writes the beacon to the base', () async {
      final phone = FakeMeshRadio(myNodeId: 10);
      await phone.connect(const RadioDescriptor(id: 'A', name: 'a'));
      final service = RadioProfileService(phone, prefs, null, null, roles);
      final steps = <String>[];
      await service.applyToConnected(RadioRole.base,
          preset: MeshtasticPresets.longFast,
          beaconSecs: 60,
          onStep: steps.add);
      expect(phone.appliedProfiles.single.frequencyMHz, isNull);
      expect(steps.any((s) => s.contains('link checks')), isFalse);
      expect(roles.baseBeacon?.kind, BeaconKind.telemetry);
    });

    test('backs up a MeshCore radio before setup; Restore puts it back',
        () async {
      final dir = Directory.systemTemp.createTempSync('mc_setup_backup');
      addTearDown(() => dir.deleteSync(recursive: true));
      final t = mc.FakeMeshCoreTransport(
          ownKey: mc.keyOf([0x11, 0x22, 0x33, 0x44]));
      final radio = MeshCoreRadio(
        transport: t,
        commandTimeout: const Duration(milliseconds: 500),
        contactsIdleTimeout: const Duration(milliseconds: 200),
        statsInterval: const Duration(hours: 1),
        reconnectInitialDelay: const Duration(milliseconds: 10),
      );
      await radio.connect(const RadioDescriptor(
          id: 'mc', name: 'L1', protocol: RadioProtocol.meshcore));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Once SET_RADIO_PARAMS is written the fake reads back as set up.
      t.after[MeshCoreCmd.setRadioParams] = (cmd) {
        t.selfInfo = mc.selfInfoFrame(
            key: t.ownKey,
            freqKHz: mc.u32At(cmd, 1),
            name: 'MeshTest Base',
            txPower: 20);
        t.deviceInfo = mc.deviceInfoFrame(repeat: cmd[11] == 1);
      };
      final backups = RadioBackupService(directory: dir);
      final service = RadioProfileService(radio, prefs, backups, null, roles);
      final steps = <String>[];
      await service.applyToConnected(RadioRole.base,
          preset: MeshCoreModulations.fast.radioPreset,
          beaconSecs: 20,
          rename: true,
          onStep: steps.add,
          frequencyMHz: 918.0,
          txPowerDbm: 20);
      expect(
          steps.any((s) =>
              s.startsWith('Saved backup (Fast · 910.525 MHz, USA · 22 dBm')),
          isTrue,
          reason: steps.join('\n'));
      expect(steps.any((s) => s.contains('No backup')), isFalse);
      final original = (await backups.list()).single as MeshCoreBackup;
      expect(original.original, isTrue);
      expect(original.reason, backupReasonBeforeSetup);
      expect(original.nodeNum, 0x11223344);
      expect(original.settings.name, 'Mobile');
      expect(original.settings.frequencyKHz, 910525);
      expect(original.settings.clientRepeat, isFalse);
      expect(original.settings.usedChannels.map((c) => c.name), ['Public']);
      expect(radio.settings!.frequencyKHz, 918000);
      expect(radio.settings!.clientRepeat, isTrue);
      expect(service.isOnTestChannel(radio), isTrue);

      // Running setup again on a set-up radio adds no backup.
      await service.applyToConnected(RadioRole.base,
          preset: MeshCoreModulations.fast.radioPreset,
          beaconSecs: 20,
          onStep: steps.add,
          frequencyMHz: 918.0,
          txPowerDbm: 20);
      expect(await backups.list(), hasLength(1));

      // Restore.
      t.after[MeshCoreCmd.setRadioParams] = (_) {
        t.selfInfo = mc.selfInfoFrame(key: t.ownKey);
        t.deviceInfo = mc.deviceInfoFrame();
      };
      t.writes.clear();
      final diff = restoreDiff(await backups.snapshot(radio), original);
      expect(diff.firstWhere((l) => l.label == 'Frequency').from, '918.000 MHz');
      expect(diff.firstWhere((l) => l.label == 'Frequency').to,
          '910.525 MHz, USA');
      expect(diff.firstWhere((l) => l.label == 'Relaying').to, 'off');
      await backups.restore(radio, original, onStep: steps.add);
      final params =
          t.writes.firstWhere((w) => w[0] == MeshCoreCmd.setRadioParams);
      expect(mc.u32At(params, 1), 910525);
      expect(params[11], 0);
      final name =
          t.writes.firstWhere((w) => w[0] == MeshCoreCmd.setAdvertName);
      expect(utf8.decode(name.sublist(1)), 'Mobile');
      expect(radio.settings!.sameAs(original.settings), isTrue);
      expect(service.isOnTestChannel(radio), isFalse);
      expect(steps.last, 'Done');

      // A Meshtastic backup can't go onto this radio.
      await expectLater(
          backups.restore(
              radio,
              MeshtasticBackup(
                path: '',
                nodeNum: 0x11223344,
                radioName: 'x',
                savedAt: DateTime.utc(2026),
                reason: '',
                channels: const [],
                lora: pb.Config_LoRaConfig(),
                rangeTest: null,
              ),
              onStep: (_) {}),
          throwsA(isA<StateError>()));
      await radio.dispose();
    });
  });

  group('schema v10', () {
    test('a v9 database gains packet_events.uplink_snr', () async {
      // The current schema without the v10 column, as a v9 database.
      final fresh = AppDatabase.forTesting(NativeDatabase.memory());
      final rows = await fresh
          .customSelect("SELECT sql FROM sqlite_master WHERE type = 'table' "
              "AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%' "
              "AND name NOT IN ('test_plans', 'test_steps')")
          .get();
      final ddl = [
        for (final r in rows)
          r
              .read<String>('sql')
              .replaceAll(RegExp(r',\s*"uplink_snr" REAL NULL'), '')
              // v11 (guided tests): not in a v9 database either.
              .replaceAll(
                  RegExp(r',\s*"test_step_id" INTEGER NULL( REFERENCES[^,)]*\([^)]*\))?'),
                  ''),
      ];
      await fresh.close();
      expect(ddl.any((d) => d.contains('uplink_snr')), isFalse);

      final db = AppDatabase.forTesting(
          NativeDatabase.memory(setup: (raw) {
        for (final d in ddl) {
          raw.execute(d);
        }
        raw.execute("INSERT INTO nodes (node_id, first_seen_at, "
            "last_heard_at) VALUES (2, 1, 1)");
        raw.execute("INSERT INTO coverage_maps (name, created_at) "
            "VALUES ('Park', 1700000000)");
        raw.execute("INSERT INTO sessions (coverage_map_id, started_at) "
            "VALUES (1, 1700000000)");
        raw.execute("INSERT INTO packet_events (session_id, timestamp, "
            "direction, source_node_id, packet_type, rx_snr) "
            "VALUES (1, 1700000001, 'ack', 1, 'ack', 3.5)");
        raw.execute('PRAGMA user_version = 9');
      }));
      addTearDown(db.close);

      expect(db.schemaVersion, 11);
      final old = (await db.getEventsForSession(1)).single;
      expect(old.rxSnr, 3.5);
      expect(old.uplinkSnr, isNull);
      final id = await db.insertPacketEvent(PacketEventsCompanion.insert(
        sessionId: 1,
        timestamp: DateTime(2026, 10, 29),
        direction: PacketDirection.ack,
        sourceNodeId: 1,
        packetType: PacketType.ack,
        uplinkSnr: const Value(-2.25),
      ));
      final e = (await db.getEventsForSession(1)).singleWhere((e) => e.id == id);
      expect(e.uplinkSnr, -2.25);
    });
  });
}
