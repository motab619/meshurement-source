// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/proto/meshtastic/admin.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/channel.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/module_config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/portnums.pbenum.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/telemetry.pb.dart' as pb;
import 'package:mesh_analyzer/services/beacon_tracker.dart';
import 'package:mesh_analyzer/services/export/csv_v2.dart';
import 'package:mesh_analyzer/services/export/export_data.dart';
import 'package:mesh_analyzer/services/export/geojson.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/services/out_of_range_monitor.dart';
import 'package:mesh_analyzer/services/packet_processor.dart';
import 'package:mesh_analyzer/services/radio_backup_service.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:mesh_analyzer/services/range_test_detector.dart';
import 'package:mesh_analyzer/ui/widgets/beacon_status.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';

import 'fakes/fake_mesh_radio.dart';

/// Records admin messages instead of sending them over Bluetooth.
class _AdminCapture extends MeshtasticRadio {
  final sent = <pb.AdminMessage>[];

  @override
  Future<void> sendAdmin(
    pb.AdminMessage msg, {
    Duration timeout = const Duration(seconds: 10),
    int retries = 1,
  }) async =>
      sent.add(msg);

  pb.ModuleConfig_TelemetryConfig get telemetry => sent
      .firstWhere(
          (m) => m.hasSetModuleConfig() && m.setModuleConfig.hasTelemetry())
      .setModuleConfig
      .telemetry;

  pb.ModuleConfig_RangeTestConfig get rangeTest => sent
      .firstWhere(
          (m) => m.hasSetModuleConfig() && m.setModuleConfig.hasRangeTest())
      .setModuleConfig
      .rangeTest;

  pb.Config_DeviceConfig get device => sent
      .firstWhere((m) => m.hasSetConfig() && m.setConfig.hasDevice())
      .setConfig
      .device;
}

_AdminCapture _radio({String firmware = '', int excluded = 0}) {
  final r = _AdminCapture()
    ..enterDemo(
      name: 'r',
      myNodeNum: 7,
      nodeInfos: [pb.NodeInfo(num: 7)],
      lora: pb.Config_LoRaConfig(usePreset: true, hopLimit: 3),
      channelTable: [pb.Channel(index: 0, role: pb.Channel_Role.PRIMARY)],
    );
  if (firmware.isNotEmpty) {
    r.metadata =
        pb.DeviceMetadata(firmwareVersion: firmware, excludedModules: excluded);
  }
  return r;
}

TestProfile _profile({required bool base, BeaconConfig? beacon}) => TestProfile(
      channelName: 'MeshTest',
      channelKey: Uint8List.fromList(List.generate(32, (i) => i)),
      preset: MeshtasticPresets.fromId('MEDIUM_FAST')!,
      isBase: base,
      beacon: beacon,
    );

pb.MeshPacket _telemetryPacket({
  required int from,
  double util = 7.5,
  int hopStart = 3,
  int hopLimit = 3,
}) =>
    pb.MeshPacket(
      from: from,
      id: 5,
      rxRssi: -90,
      rxSnr: 4.5,
      hopStart: hopStart,
      hopLimit: hopLimit,
      decoded: pb.Data(
        portnum: pb.PortNum.TELEMETRY_APP,
        payload: pb.Telemetry(
          deviceMetrics: pb.DeviceMetrics(channelUtilization: util),
        ).writeToBuffer(),
      ),
    );

void main() {
  group('capabilities', () {
    test('no metadata: nothing known', () {
      final c = capabilitiesFromMetadata(null);
      expect(c.firmwareVersion, '');
      expect(c.rangeTestExcluded, isFalse);
      expect(c.hasTraceroute, isFalse);
    });

    test('2.8 reports Range Test excluded (bit 0x10)', () {
      final c = capabilitiesFromMetadata(pb.DeviceMetadata(
          firmwareVersion: '2.8.1.8e6a88d', excludedModules: 0x0010 | 0x0001));
      expect(c.rangeTestExcluded, isTrue);
      expect(c.hasTraceroute, isTrue);
      expect(c.firmwareAtLeast(2, 8), isTrue);
    });

    test('2.7 never sets the bit, so absence proves nothing', () {
      final c = capabilitiesFromMetadata(pb.DeviceMetadata(
          firmwareVersion: '2.7.26.abc', excludedModules: 0x0001));
      expect(c.rangeTestExcluded, isFalse);
      expect(c.firmwareAtLeast(2, 8), isFalse);
      expect(c.firmwareAtLeast(2, 7), isTrue);
    });

    test('old firmware has no traceroute', () {
      final c = capabilitiesFromMetadata(
          pb.DeviceMetadata(firmwareVersion: '2.2.24.x'));
      expect(c.hasTraceroute, isFalse);
    });

    test('the radio exposes them', () {
      expect(
          _radio(firmware: '2.8.1.x', excluded: 0x10)
              .capabilities
              .rangeTestExcluded,
          isTrue);
      expect(_radio().capabilities.firmwareVersion, '');
    });
  });

  group('beacon selection', () {
    test('excluded or 2.8+: telemetry', () {
      expect(
          selectBeaconKind(const RadioCapabilities(
              firmwareVersion: '2.7.26', rangeTestExcluded: true)),
          BeaconKind.telemetry);
      expect(
          selectBeaconKind(const RadioCapabilities(firmwareVersion: '2.8.0')),
          BeaconKind.telemetry);
      expect(
          selectBeaconKind(const RadioCapabilities(firmwareVersion: '3.0.1')),
          BeaconKind.telemetry);
    });

    test('2.7 without the exclusion bit: Range Test', () {
      expect(
          selectBeaconKind(const RadioCapabilities(firmwareVersion: '2.7.26')),
          BeaconKind.rangeTest);
      expect(
          selectBeaconKind(const RadioCapabilities(firmwareVersion: '2.5.11')),
          BeaconKind.rangeTest);
    });

    test('unknown firmware: telemetry, which every version carries', () {
      expect(selectBeaconKind(RadioCapabilities.unknown), BeaconKind.telemetry);
    });

    test('an explicit kind is kept; an open one resolves', () {
      const caps = RadioCapabilities(firmwareVersion: '2.8.1');
      expect(
          const BeaconConfig(intervalSec: 30, kind: BeaconKind.rangeTest)
              .resolved(caps)
              .kind,
          BeaconKind.rangeTest);
      expect(const BeaconConfig(intervalSec: 30).resolved(caps).kind,
          BeaconKind.telemetry);
      expect(const BeaconConfig.off().enabled, isFalse);
      expect(
          const BeaconConfig(intervalSec: 0).resolved(caps).enabled, isFalse);
    });
  });

  group('telemetry interval', () {
    test('rounds up to a whole minute, at least 60 s', () {
      expect(BeaconConfig.telemetryIntervalSec(15), 60);
      expect(BeaconConfig.telemetryIntervalSec(60), 60);
      expect(BeaconConfig.telemetryIntervalSec(61), 120);
      expect(BeaconConfig.telemetryIntervalSec(300), 300);
    });

    test('only telemetry beacons are changed', () {
      const rt = BeaconConfig(intervalSec: 30, kind: BeaconKind.rangeTest);
      expect(rt.normalized().intervalSec, 30);
      const tel = BeaconConfig(intervalSec: 30, kind: BeaconKind.telemetry);
      expect(tel.normalized().intervalSec, 60);
      expect(const BeaconConfig.off().normalized().intervalSec, 0);
    });

    test('resolved picks the kind, then the real interval', () {
      const caps = RadioCapabilities(
          firmwareVersion: '2.8.1.8e6a88d', rangeTestExcluded: true);
      final b = const BeaconConfig(intervalSec: 20).resolved(caps);
      expect(b.kind, BeaconKind.telemetry);
      expect(b.intervalSec, 60);
    });
  });

  group('applyTestProfile writes the beacon', () {
    test('base on 2.8: telemetry on, Range Test off, local-only relaying',
        () async {
      final r = _radio(firmware: '2.8.1.x', excluded: 0x10);
      final applied = await r.applyTestProfile(
          _profile(base: true, beacon: const BeaconConfig(intervalSec: 30)));
      expect(applied!.kind, BeaconKind.telemetry);
      expect(r.telemetry.deviceTelemetryEnabled, isTrue);
      // Telemetry goes out at most once a minute: 30 s is written as 60.
      expect(r.telemetry.deviceUpdateInterval, 60);
      expect(r.rangeTest.enabled, isFalse);
      expect(r.rangeTest.sender, 0);
      expect(r.device.rebroadcastMode,
          pb.Config_DeviceConfig_RebroadcastMode.LOCAL_ONLY);
      expect(r.device.role, pb.Config_DeviceConfig_Role.CLIENT);
      // One transaction.
      expect(r.sent.first.beginEditSettings, isTrue);
      expect(r.sent.last.commitEditSettings, isTrue);
    });

    test('base on 2.7 with Range Test: sender on, telemetry off', () async {
      final r = _radio(firmware: '2.7.26.x');
      final applied = await r.applyTestProfile(
          _profile(base: true, beacon: const BeaconConfig(intervalSec: 15)));
      expect(applied!.kind, BeaconKind.rangeTest);
      expect(r.rangeTest.enabled, isTrue);
      expect(r.rangeTest.sender, 15);
      expect(r.telemetry.deviceTelemetryEnabled, isFalse);
    });

    test('other telemetry settings are kept', () async {
      final r = _radio(firmware: '2.8.1.x');
      r.moduleConfigs[pb.ModuleConfig_PayloadVariant.telemetry] =
          pb.ModuleConfig(
              telemetry: pb.ModuleConfig_TelemetryConfig(
                  environmentMeasurementEnabled: true,
                  environmentUpdateInterval: 600));
      await r.applyTestProfile(
          _profile(base: true, beacon: const BeaconConfig(intervalSec: 30)));
      expect(r.telemetry.environmentMeasurementEnabled, isTrue);
      expect(r.telemetry.environmentUpdateInterval, 600);
      expect(r.telemetry.deviceTelemetryEnabled, isTrue);
    });

    test('mobile: telemetry broadcast off, local-only relaying, no beacon',
        () async {
      final r = _radio(firmware: '2.8.1.x');
      r.moduleConfigs[pb.ModuleConfig_PayloadVariant.telemetry] =
          pb.ModuleConfig(
              telemetry: pb.ModuleConfig_TelemetryConfig(
                  deviceTelemetryEnabled: true, deviceUpdateInterval: 900));
      final applied = await r.applyTestProfile(_profile(base: false));
      expect(applied, isNull);
      expect(r.telemetry.deviceTelemetryEnabled, isFalse);
      expect(r.rangeTest.sender, 0);
      expect(r.device.rebroadcastMode,
          pb.Config_DeviceConfig_RebroadcastMode.LOCAL_ONLY);
    });

    test('beacon off on the base turns both off', () async {
      final r = _radio(firmware: '2.7.26.x');
      final applied = await r.applyTestProfile(
          _profile(base: true, beacon: const BeaconConfig(intervalSec: 0)));
      expect(applied!.enabled, isFalse);
      expect(r.telemetry.deviceTelemetryEnabled, isFalse);
      expect(r.rangeTest.enabled, isFalse);
    });

    test('setBeacon switches a base to telemetry', () async {
      final r = _radio(firmware: '2.7.26.x');
      final applied = await r.setBeacon(
          const BeaconConfig(intervalSec: 30, kind: BeaconKind.telemetry));
      expect(applied.kind, BeaconKind.telemetry);
      // Telemetry goes out at most once a minute: 30 s is written as 60.
      expect(r.telemetry.deviceUpdateInterval, 60);
      expect(r.rangeTest.enabled, isFalse);
    });
  });

  group('backups keep the beacon settings', () {
    MeshtasticBackup sample() => MeshtasticBackup(
          path: '/x',
          nodeNum: 7,
          radioName: 'r',
          savedAt: DateTime.utc(2026, 10, 20),
          reason: 'test',
          channels: [
            for (var i = 0; i < 8; i++)
              pb.Channel(index: i, role: pb.Channel_Role.DISABLED),
          ],
          lora: pb.Config_LoRaConfig(usePreset: true),
          rangeTest: pb.ModuleConfig_RangeTestConfig(enabled: false),
          telemetry: pb.ModuleConfig_TelemetryConfig(
              deviceTelemetryEnabled: true, deviceUpdateInterval: 1800),
          device: pb.Config_DeviceConfig(
              rebroadcastMode: pb.Config_DeviceConfig_RebroadcastMode.ALL),
        );

    test('JSON round trip', () {
      final b = sample();
      final back = RadioBackup.fromJson('/x',
          jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>) as MeshtasticBackup;
      expect(back.telemetry, b.telemetry);
      expect(back.device, b.device);
      expect(back.sameSettingsAs(b), isTrue);
    });

    test('a change in either counts as a different backup', () {
      final other = sample();
      final changed = MeshtasticBackup(
        path: '/y',
        nodeNum: 7,
        radioName: 'r',
        savedAt: other.savedAt,
        reason: 'test',
        channels: other.channels,
        lora: other.lora,
        rangeTest: other.rangeTest,
        telemetry: pb.ModuleConfig_TelemetryConfig(deviceUpdateInterval: 20),
        device: other.device,
      );
      expect(changed.sameSettingsAs(other), isFalse);
    });

    test('restore writes telemetry and device config back', () async {
      final r = _radio(firmware: '2.8.1.x');
      await RadioBackupService().restore(r, sample(), onStep: (_) {});
      expect(r.telemetry.deviceUpdateInterval, 1800);
      expect(r.telemetry.deviceTelemetryEnabled, isTrue);
      expect(
          r.device.rebroadcastMode, pb.Config_DeviceConfig_RebroadcastMode.ALL);
      expect(r.sent.last.commitEditSettings, isTrue);
    });

    test('the restore diff shows telemetry and relaying', () {
      final now = sample();
      final target = sample();
      final lines = restoreDiff(now, target).map((l) => l.label);
      expect(lines, containsAll(['Telemetry beacon', 'Relaying']));
    });
  });

  group('parsing beacon packets', () {
    test('Range Test payload "seq N"', () {
      expect(rangeTestSeqFrom('seq 12'.codeUnits), 12);
      expect(rangeTestSeqFrom('seq 0'.codeUnits), 0);
      expect(rangeTestSeqFrom('hello'.codeUnits), isNull);
      expect(rangeTestSeqFrom(const []), isNull);
    });

    test('a RANGE_TEST packet carries its seq', () {
      final p = receivedPacketFrom(
          pb.MeshPacket(
              from: 2,
              rxRssi: -80,
              decoded: pb.Data(
                  portnum: pb.PortNum.RANGE_TEST_APP,
                  payload: 'seq 41'.codeUnits)),
          myNodeNum: 1)!;
      expect(p.type, PacketType.rangeTest);
      expect(p.beaconSeq, 41);
    });

    test('a device telemetry packet carries the sender channel use', () {
      final p = receivedPacketFrom(_telemetryPacket(from: 2, util: 12.5),
          myNodeNum: 1)!;
      expect(p.type, PacketType.telemetry);
      expect(p.senderChannelUtil, 12.5);
      expect(p.snr, 4.5);
    });

    test('telemetry without device metrics has no channel use', () {
      final p = receivedPacketFrom(
          pb.MeshPacket(
              from: 2,
              rxRssi: -80,
              decoded: pb.Data(
                  portnum: pb.PortNum.TELEMETRY_APP,
                  payload: pb.Telemetry(
                          environmentMetrics:
                              pb.EnvironmentMetrics(temperature: 20))
                      .writeToBuffer())),
          myNodeNum: 1)!;
      expect(p.senderChannelUtil, isNull);
    });
  });

  group('BeaconTracker', () {
    final t0 = DateTime(2026, 10, 20, 12);
    DateTime at(int s) => t0.add(Duration(seconds: s));

    BeaconTracker telemetry({int interval = 30}) => BeaconTracker()
      ..start(
          baseNodeId: 2,
          kind: BeaconKind.telemetry,
          intervalSec: interval,
          now: t0);

    test('sequence gaps are counted exactly; a restart is not a gap', () {
      final t = BeaconTracker()
        ..start(
            baseNodeId: 2,
            kind: BeaconKind.rangeTest,
            intervalSec: 30,
            now: t0);
      expect(t.onBeacon(BeaconKind.rangeTest, at(0), seq: 4), 0);
      expect(t.onBeacon(BeaconKind.rangeTest, at(30), seq: 5), 0);
      expect(t.onBeacon(BeaconKind.rangeTest, at(120), seq: 9), 3);
      expect(t.onBeacon(BeaconKind.rangeTest, at(150), seq: 1), 0);
      expect(t.heard, 4);
      expect(t.seqMissed, 3);
    });

    test('a missed telemetry slot is called after half an interval', () {
      final t = telemetry();
      expect(t.dueMisses(at(100)), isEmpty,
          reason: 'nothing to measure from before the first beacon');
      t.onBeacon(BeaconKind.telemetry, at(0));
      expect(t.dueMisses(at(40)), isEmpty);
      expect(t.dueMisses(at(44)), isEmpty);
      expect(t.dueMisses(at(46)), [at(30)]);
      expect(t.dueMisses(at(46)), isEmpty, reason: 'each slot only once');
      // 80 s on: slots at 60 (due at 75) and 90 (due at 105).
      expect(t.dueMisses(at(80)), [at(60)]);
    });

    test('several slots at once after a long silence', () {
      final t = telemetry()..onBeacon(BeaconKind.telemetry, at(0));
      expect(t.dueMisses(at(130)), [at(30), at(60), at(90)]);
    });

    test('a beacon resets the schedule', () {
      final t = telemetry()..onBeacon(BeaconKind.telemetry, at(0));
      t.dueMisses(at(46));
      t.onBeacon(BeaconKind.telemetry, at(70));
      expect(t.dueMisses(at(110)), isEmpty);
      expect(t.dueMisses(at(116)), [at(100)]);
    });

    test('Range Test sessions make no timing misses', () {
      final t = BeaconTracker()
        ..start(
            baseNodeId: 2,
            kind: BeaconKind.rangeTest,
            intervalSec: 30,
            now: t0);
      t.onBeacon(BeaconKind.rangeTest, at(0), seq: 1);
      expect(t.dueMisses(at(80)), isEmpty);
    });

    test(
        'base answering pings but no beacon for 3 intervals: absent, and '
        'no misses are made up', () {
      final t = telemetry();
      final changes = <bool>[];
      t.absentStream.listen(changes.add);
      t.onBeacon(BeaconKind.telemetry, at(0));
      t.onBaseHeard(at(80));
      expect(t.dueMisses(at(85)), isNotEmpty, reason: 'still 2.8 intervals');
      t.onBaseHeard(at(95));
      expect(t.dueMisses(at(95)), isEmpty);
      expect(t.absent, isTrue);
      // The beacon coming back clears it.
      t.onBeacon(BeaconKind.telemetry, at(100));
      expect(t.absent, isFalse);
    });

    test('silence with the base unreachable is a dead zone, not absence', () {
      final t = telemetry()..onBeacon(BeaconKind.telemetry, at(0));
      t.dueMisses(at(300));
      expect(t.absent, isFalse);
    });

    test('coming back from a dead zone: the first ACK is not "beacon off"', () {
      final t = telemetry()..onBeacon(BeaconKind.telemetry, at(0));
      t.dueMisses(at(600)); // out of range for 20 intervals
      t.onBaseHeard(at(610));
      t.dueMisses(at(611));
      expect(t.absent, isFalse, reason: 'reachable for 1 s, not 3 intervals');
      // Still answering 3 intervals later with no beacon: now it is off.
      for (var s = 625; s <= 700; s += 15) {
        t.onBaseHeard(at(s));
      }
      t.dueMisses(at(705));
      expect(t.absent, isTrue);
    });

    test('slots that passed while the phone was not linked are skipped', () {
      final t = telemetry()..onBeacon(BeaconKind.telemetry, at(0));
      t.skipSlots(at(100));
      expect(t.dueMisses(at(101)), isEmpty);
      expect(t.dueMisses(at(150)), [at(120)]);
    });

    test('never heard a beacon but the base answers: absent from the start',
        () {
      final t = telemetry();
      t.onBaseHeard(at(5));
      t.onBaseHeard(at(95));
      t.dueMisses(at(96));
      expect(t.absent, isTrue);
    });

    test('an unknown kind is decided by the first beacon', () {
      final t = BeaconTracker()
        ..start(baseNodeId: 2, kind: BeaconKind.none, intervalSec: 0, now: t0);
      expect(t.accepts(BeaconKind.telemetry), isTrue);
      t.onBeacon(BeaconKind.telemetry, at(0));
      expect(t.kind, BeaconKind.telemetry);
      expect(t.accepts(BeaconKind.rangeTest), isFalse);
    });

    group('no interval known (base set up outside Radio Setup)', () {
      BeaconTracker unknown(BeaconKind kind) => BeaconTracker()
        ..start(baseNodeId: 2, kind: kind, intervalSec: 0, now: t0);

      test('Range Test: learned exactly from the sequence numbers, once', () {
        final t = unknown(BeaconKind.rangeTest);
        t.onBeacon(BeaconKind.rangeTest, at(0), seq: 448);
        expect(t.takeLearnedInterval(), isNull, reason: 'one beacon only');
        // Two missed in between: 45 s over 3 numbers.
        t.onBeacon(BeaconKind.rangeTest, at(45), seq: 451);
        expect(t.takeLearnedInterval(), 15);
        expect(t.intervalSec, 15);
        t.onBeacon(BeaconKind.rangeTest, at(60), seq: 452);
        expect(t.takeLearnedInterval(), isNull, reason: 'unchanged');
      });

      test(
          'telemetry: shortest gap, in whole minutes; then misses are '
          'counted', () {
        final t = unknown(BeaconKind.telemetry);
        t.onBeacon(BeaconKind.telemetry, at(0));
        t.onBeacon(BeaconKind.telemetry, at(121)); // one missed
        expect(t.takeLearnedInterval(), 120);
        t.onBeacon(BeaconKind.telemetry, at(181));
        expect(t.takeLearnedInterval(), 60);
        expect(t.dueMisses(at(272)), [at(241)]);
      });

      test('a known interval is never overridden', () {
        final t = telemetry(interval: 60);
        t.onBeacon(BeaconKind.telemetry, at(0));
        t.onBeacon(BeaconKind.telemetry, at(20));
        expect(t.takeLearnedInterval(), isNull);
        expect(t.intervalSec, 60);
      });
    });

    test('missed slots get a position between the last beacon and now', () {
      final t = telemetry()
        ..onBeacon(BeaconKind.telemetry, at(0), lat: 10, lon: 20);
      final (lat, lon) = t.positionAt(at(30), at(60), 12, 24);
      expect(lat, closeTo(11, 1e-9));
      expect(lon, closeTo(22, 1e-9));
      // No fix now: the last beacon's position stands in.
      expect(t.positionAt(at(30), at(60), null, null), (10.0, 20.0));
      expect(telemetry().positionAt(at(30), at(60), null, null), (null, null));
    });
  });

  group('PacketProcessor beacon samples', () {
    const base = 2;
    late AppDatabase db;
    late FakeMeshRadio radio;
    late OutOfRangeMonitor monitor;
    late PacketProcessor processor;
    late int sessionId;

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    Future<void> setUpSession(BeaconKind kind, int interval) async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      radio = FakeMeshRadio();
      monitor = OutOfRangeMonitor(
          notifications: FlutterLocalNotificationsPlugin(), radio: radio);
      processor = PacketProcessor(
        db: db,
        radio: radio,
        gps: GpsService(),
        rangeTestDetector: RangeTestDetector(),
        outOfRangeMonitor: monitor,
      )..start();
      final baseId = await db.upsertNode(nodeId: base);
      final mapId = await db.createCoverageMap(name: 'm', baseNodeId: baseId);
      sessionId = await db.createSession(
          coverageMapId: mapId,
          beaconKind: kind.dbValue,
          beaconIntervalSec: interval);
      processor.activeSessionId = sessionId;
      monitor.configure(baseNodeId: base, timeoutSec: 600);
      processor.startBeaconTracking(
          baseNodeId: base, kind: kind, intervalSec: interval);
    }

    tearDown(() async {
      processor.dispose();
      monitor.dispose();
      await radio.dispose();
      await db.close();
    });

    ReceivedPacket telemetry(
            {int from = base, int hops = 0, double? util = 6.5}) =>
        ReceivedPacket(
            from: from,
            type: PacketType.telemetry,
            snr: 3,
            rssi: -100,
            hops: hops,
            senderChannelUtil: util);

    test('telemetry from the base, heard directly, is a beacon sample',
        () async {
      await setUpSession(BeaconKind.telemetry, 30);
      radio.pushPacket(telemetry());
      await settle();
      final e = (await db.getEventsForSession(sessionId)).single;
      expect(e.sourceKind, SourceKind.telemetry);
      expect(e.baseChannelUtil, 6.5);
      expect(e.rxSnr, 3);
      expect(processor.beacons.heard, 1);
    });

    test('telemetry from another node is passive', () async {
      await setUpSession(BeaconKind.telemetry, 30);
      radio.pushPacket(telemetry(from: 9));
      await settle();
      final e = (await db.getEventsForSession(sessionId)).single;
      expect(e.sourceKind, SourceKind.passive);
      expect(e.baseChannelUtil, isNull);
      expect(processor.beacons.heard, 0);
    });

    test('a relayed copy of the base telemetry is never a sample', () async {
      await setUpSession(BeaconKind.telemetry, 30);
      final relayed = PacketProcessor(
        db: db,
        radio: radio,
        gps: GpsService(),
        rangeTestDetector: RangeTestDetector(),
        outOfRangeMonitor: monitor,
        countRelayed: () => true,
      )..activeSessionId = sessionId;
      relayed.startBeaconTracking(
          baseNodeId: base, kind: BeaconKind.telemetry, intervalSec: 30);
      relayed.start();
      radio.pushPacket(telemetry(hops: 1));
      await settle();
      final events = await db.getEventsForSession(sessionId);
      expect(
          events.where((e) => e.sourceKind == SourceKind.telemetry), isEmpty);
      expect(relayed.beacons.heard, 0);
      relayed.dispose();
    });

    test('telemetry from the base is not a beacon in a Range Test session',
        () async {
      await setUpSession(BeaconKind.rangeTest, 30);
      radio.pushPacket(telemetry());
      await settle();
      final e = (await db.getEventsForSession(sessionId)).single;
      expect(e.sourceKind, SourceKind.passive);
    });

    test('Range Test from the base keeps its seq', () async {
      await setUpSession(BeaconKind.rangeTest, 30);
      radio.pushPacket(ReceivedPacket(
          from: base,
          type: PacketType.rangeTest,
          snr: 2,
          rssi: -105,
          beaconSeq: 8));
      radio.pushPacket(ReceivedPacket(
          from: base,
          type: PacketType.rangeTest,
          snr: 2,
          rssi: -105,
          beaconSeq: 11));
      await settle();
      final events = await db.getEventsForSession(sessionId);
      expect(events.map((e) => e.seq), [8, 11]);
      expect(events.every((e) => e.sourceKind == SourceKind.rangeTest), isTrue);
      expect(processor.beacons.seqMissed, 2);
      final stats = await db.watchBeaconStats(sessionId).first;
      expect(stats.heard, 2);
      expect(stats.missed, 2);
      expect(stats.exact, isTrue);
    });

    test('an unknown session beacon is learned from the first one', () async {
      await setUpSession(BeaconKind.none, 0);
      radio.pushPacket(telemetry());
      await settle();
      expect((await db.getSessionById(sessionId))!.beaconKind, 'telemetry');
    });

    test('missed telemetry beacons become telemetry_miss rows', () async {
      await setUpSession(BeaconKind.telemetry, 30);
      radio.pushPacket(telemetry());
      await settle();
      await processor
          .tickBeacons(DateTime.now().add(const Duration(seconds: 110)));
      final all = await db.getEventsForSession(sessionId, includeMisses: true);
      final misses =
          all.where((e) => e.sourceKind == SourceKind.telemetryMiss).toList();
      expect(misses, hasLength(3));
      expect(misses.every((e) => e.rxSnr == null && e.rxRssi == null), isTrue);
      // Hidden from everything that draws or counts real packets.
      expect(await db.getEventsForSession(sessionId), hasLength(1));
      expect(await db.watchPacketCount(sessionId).first, 1);
      final stats = await db.watchBeaconStats(sessionId).first;
      expect(stats.heard, 1);
      expect(stats.missed, 3);
      expect(stats.exact, isFalse);
      expect(beaconStatsText(stats), 'Beacons 1 of ~4 (25 %)');
    });

    test('no misses while the phone is not linked to its radio', () async {
      await setUpSession(BeaconKind.telemetry, 30);
      radio.pushPacket(telemetry());
      await settle();
      radio.setState(RadioConnectionState.reconnecting);
      await processor
          .tickBeacons(DateTime.now().add(const Duration(seconds: 100)));
      expect(await db.getEventsForSession(sessionId, includeMisses: true),
          hasLength(1));
    });

    test('misses during a radio outage are not made up after it reconnects',
        () async {
      await setUpSession(BeaconKind.telemetry, 30);
      radio.pushPacket(telemetry());
      await settle();
      final t0 = DateTime.now();
      radio.setState(RadioConnectionState.reconnecting);
      await processor.tickBeacons(t0.add(const Duration(seconds: 100)));
      radio.setState(RadioConnectionState.ready);
      await processor.tickBeacons(t0.add(const Duration(seconds: 101)));
      expect(await db.getEventsForSession(sessionId, includeMisses: true),
          hasLength(1),
          reason: 'the outage is not a dead zone');
      // The schedule resumes from the first slot after the reconnect.
      await processor.tickBeacons(t0.add(const Duration(seconds: 150)));
      expect(await db.getEventsForSession(sessionId, includeMisses: true),
          hasLength(2));
    });
  });

  test('the stats text for exact counts has no tilde', () {
    expect(beaconStatsText(const BeaconStats(41, 3, exact: true)),
        'Beacons 41 of 44 (93 %)');
    expect(beaconStatsText(BeaconStats.none), isNull);
  });

  group('BeaconStats.fromRows', () {
    test('sequence gaps beat timing misses', () {
      final s = BeaconStats.fromRows([
        (SourceKind.rangeTest, 1),
        (SourceKind.rangeTest, 4),
        (SourceKind.rangeTest, 5),
      ]);
      expect((s.heard, s.missed, s.exact), (3, 2, true));
    });

    test('telemetry counts the synthesised rows', () {
      final s = BeaconStats.fromRows([
        (SourceKind.telemetry, null),
        (SourceKind.telemetryMiss, null),
        (SourceKind.telemetry, null),
      ]);
      expect((s.heard, s.missed, s.exact), (2, 1, false));
    });
  });

  group('schema v7', () {
    test('migrates a v6 database; old rows are passive', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
        raw.execute('''
          CREATE TABLE sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            coverage_map_id INTEGER NOT NULL,
            name TEXT NOT NULL DEFAULT '',
            started_at INTEGER NOT NULL,
            ended_at INTEGER NULL,
            is_active INTEGER NOT NULL DEFAULT 0,
            remote_node_id INTEGER NULL,
            hw_antenna TEXT NOT NULL DEFAULT '',
            hw_node_model TEXT NOT NULL DEFAULT '',
            hw_notes TEXT NOT NULL DEFAULT '',
            lora_preset TEXT NOT NULL DEFAULT '',
            protocol TEXT NOT NULL DEFAULT 'meshtastic',
            ping_interval_sec INTEGER NOT NULL DEFAULT 0,
            packet_airtime_ms REAL NOT NULL DEFAULT 0,
            mobile_rig_id INTEGER NULL,
            base_rig_id INTEGER NULL,
            mobile_rig_json TEXT NULL,
            base_rig_json TEXT NULL,
            radio_air_util_tx REAL NULL,
            radio_channel_util REAL NULL,
            range_test_active INTEGER NOT NULL DEFAULT 0,
            packet_count INTEGER NOT NULL DEFAULT 0
          )''');
        raw.execute('''
          CREATE TABLE packet_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            timestamp INTEGER NOT NULL,
            direction TEXT NOT NULL,
            source_node_id INTEGER NOT NULL,
            rx_snr REAL NULL,
            rx_rssi INTEGER NULL,
            hop_count INTEGER NOT NULL DEFAULT 0,
            rx_lat REAL NULL,
            rx_lon REAL NULL,
            rx_alt REAL NULL,
            gps_accuracy REAL NULL,
            packet_type TEXT NOT NULL,
            mesh_packet_id INTEGER NULL,
            channel_index INTEGER NOT NULL DEFAULT 0,
            via_mqtt INTEGER NOT NULL DEFAULT 0
          )''');
        raw.execute('''
          CREATE TABLE nodes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              node_id INTEGER NOT NULL UNIQUE,
              long_name TEXT NOT NULL DEFAULT '',
              short_name TEXT NOT NULL DEFAULT '',
              user_label TEXT NULL,
              hw_model TEXT NOT NULL DEFAULT '',
              first_seen_at INTEGER NOT NULL,
              last_heard_at INTEGER NOT NULL,
              last_lat REAL NULL,
              last_lon REAL NULL
            )''');
        raw.execute('''
            CREATE TABLE coverage_maps (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              base_node_id INTEGER NOT NULL,
              created_at INTEGER NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              color_metric TEXT NOT NULL DEFAULT 'snr',
              signal_direction TEXT NOT NULL DEFAULT 'rx'
            )''');
        raw.execute("INSERT INTO sessions (coverage_map_id, name, started_at) "
            "VALUES (1, 'old', 1700000000)");
        raw.execute("INSERT INTO packet_events (session_id, timestamp, "
            "direction, source_node_id, packet_type) "
            "VALUES (1, 1700000001, 'rx', 1, 'range_test')");
        raw.execute('PRAGMA user_version = 6');
      }));
      addTearDown(db.close);

      final s = (await db.getSessionById(1))!;
      expect(s.name, 'old');
      expect(s.beaconKind, '');
      expect(s.beaconIntervalSec, 0);
      final e = (await db.getEventsForSession(1)).single;
      expect(e.sourceKind, SourceKind.passive);
      expect(e.seq, isNull);
      expect(e.baseChannelUtil, isNull);
      expect(db.schemaVersion, 11);
    });
  });

  group('CSV v2 and exports', () {
    late AppDatabase db;
    late int sessionId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      final baseId = await db.upsertNode(nodeId: 2, longName: 'Base');
      final mapId =
          await db.createCoverageMap(name: 'Park', baseNodeId: baseId);
      sessionId = await db.createSession(
          coverageMapId: mapId,
          loraPreset: 'LONG_FAST',
          beaconKind: 'telemetry',
          beaconIntervalSec: 30);
      Future<void> ev(String kind, String type, int s,
          {int? seq, double? util, double? snr}) async {
        await db.insertPacketEvent(PacketEventsCompanion.insert(
          sessionId: sessionId,
          timestamp: DateTime.utc(2026, 10, 20, 12, 0, s),
          direction: 'rx',
          sourceNodeId: baseId,
          packetType: type,
          sourceKind: Value(kind),
          seq: Value(seq),
          baseChannelUtil: Value(util),
          rxSnr: Value(snr),
          rxLat: const Value(33.0),
          rxLon: const Value(-116.0),
        ));
      }

      await ev(SourceKind.telemetry, PacketType.telemetry, 0,
          util: 4.25, snr: 5);
      await ev(SourceKind.telemetryMiss, PacketType.telemetry, 30);
      await ev(SourceKind.rangeTest, PacketType.rangeTest, 45, seq: 17, snr: 2);
    });
    tearDown(() => db.close());

    test('the new columns are appended after the earlier ones', () {
      final h = csvV2Header;
      // session_distance_m and the v9 radio settings came later and sit
      // after these.
      final i = h.indexOf('seq');
      expect(i, h.indexOf('radio_channel_util_pct') + 1);
      expect(h.indexOf('session_distance_m'), i + 5);
      expect(h.sublist(i, i + 5), [
        'seq',
        'source_kind',
        'base_channel_util',
        'beacon_kind',
        'beacon_interval_sec',
      ]);
    });

    test('values land in the right columns, misses included', () async {
      final s = (await ExportLoader(db).session(sessionId))!;
      final csv = buildCsvV2([s]).split(RegExp(r'\r?\n'));
      final header = csv.first.split(',');
      final rows = csv.skip(1).where((l) => l.isNotEmpty).map((l) {
        final cells = l.split(',');
        return {for (var i = 0; i < header.length; i++) header[i]: cells[i]};
      }).toList();
      expect(rows, hasLength(3));
      expect(rows[0]['source_kind'], 'telemetry');
      expect(rows[0]['base_channel_util'], '4.25');
      expect(rows[0]['beacon_kind'], 'telemetry');
      expect(rows[0]['beacon_interval_sec'], '30');
      expect(rows[1]['source_kind'], 'telemetry_miss');
      expect(rows[1]['rx_snr'], '');
      expect(rows[2]['source_kind'], 'range_test');
      expect(rows[2]['seq'], '17');
    });

    test('maps leave the synthesised misses out', () async {
      final s = (await ExportLoader(db).session(sessionId))!;
      expect(s.events, hasLength(3));
      expect(s.heardEvents, hasLength(2));
      final geo = buildGeoJson([s]);
      expect(geo, isNot(contains('telemetry_miss')));
    });
  });

  group('base beacon memory', () {
    test('RadioRoles remembers the beacon and when it started', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final roles = RadioRoles(prefs);
      expect(roles.baseBeacon, isNull);
      await roles.recordBeacon(
          const BeaconConfig(intervalSec: 30, kind: BeaconKind.telemetry));
      final first = roles.baseBeacon!;
      expect(first.kind, BeaconKind.telemetry);
      expect(first.intervalSec, 30);
      expect(first.since, isNotNull);

      // Writing again restarts the base, so the start date moves on (the
      // base may even be a different radio now).
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await roles.recordBeacon(
          const BeaconConfig(intervalSec: 60, kind: BeaconKind.telemetry));
      expect(roles.baseBeacon!.since!.isAfter(first.since!), isTrue);

      // An install from before: a restart after the start date wins.
      final startMs = first.since!.millisecondsSinceEpoch;
      await prefs.setInt(RadioRoles.baseBeaconSinceKey, startMs);
      await prefs.setInt(RadioRoles.baseRestartedKey, startMs + 86400000);
      expect(roles.baseBeacon!.since!.millisecondsSinceEpoch,
          startMs + 86400000);

      await roles.recordBeacon(const BeaconConfig.off());
      expect(roles.baseBeacon!.kind, BeaconKind.none);
      expect(roles.baseBeacon!.since, isNull);
    });

    test('reboot sends the admin reboot and tolerates a lost ACK', () async {
      final r = _AdminCapture();
      await r.reboot();
      expect(r.sent.single.rebootSeconds, 1);
    });

    test('recordBaseRestart stamps the restart time', () async {
      SharedPreferences.setMockInitialValues({});
      final roles = RadioRoles(await SharedPreferences.getInstance());
      await roles.recordBaseRestart();
      expect(roles.baseRestartedAt, isNotNull);
    });

    test('every write to the base records a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final roles = RadioRoles(await SharedPreferences.getInstance());
      expect(roles.baseRestartedAt, isNull);
      await roles.recordBeacon(
          const BeaconConfig(intervalSec: 30, kind: BeaconKind.rangeTest));
      expect(roles.baseRestartedAt, isNotNull);
    });
  });

  group('base stopped broadcasting (Range Test 8 h cut-off)', () {
    final setUp = DateTime(2026, 10, 24, 8);
    const rangeTest = (
      kind: BeaconKind.rangeTest,
      intervalSec: 30,
      since: null as DateTime?,
    );

    test('quiet for the first 8 hours after the base restarted', () {
      expect(
          baseBeaconAgeWarning(rangeTest, setUp,
              setUp.add(const Duration(hours: 7, minutes: 59))),
          isNull);
    });

    test('warns from 8 hours, saying how long ago', () {
      final text = baseBeaconAgeWarning(
          rangeTest, setUp, setUp.add(const Duration(hours: 9)));
      expect(text, contains("isn't broadcasting"));
      expect(text, contains('9 h ago'));
    });

    test('telemetry beacons never switch off', () {
      expect(
          baseBeaconAgeWarning(
              (kind: BeaconKind.telemetry, intervalSec: 60, since: setUp),
              setUp,
              setUp.add(const Duration(days: 2))),
          isNull);
    });

    test('no restart recorded: falls back to when the beacon started', () {
      final old = (kind: BeaconKind.rangeTest, intervalSec: 30, since: setUp);
      expect(
          baseBeaconAgeWarning(old, null, setUp.add(const Duration(hours: 10))),
          isNotNull);
      expect(
          baseBeaconAgeWarning(
              rangeTest, null, setUp.add(const Duration(days: 1))),
          isNull);
    });
  });
}
