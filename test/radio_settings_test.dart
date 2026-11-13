// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_frequency.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/proto/meshtastic/channel.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/services/session_radio_settings.dart';
import 'package:mesh_analyzer/ui/screens/coverage_map_detail_screen.dart';
import 'package:mesh_analyzer/ui/widgets/session_panel.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_location_backend.dart';
import 'fakes/fake_mesh_radio.dart';

typedef _P = pb.Config_LoRaConfig_ModemPreset;
typedef _R = pb.Config_LoRaConfig_RegionCode;

pb.Config_LoRaConfig _lora(_P preset,
        {_R region = _R.US,
        int channelNum = 0,
        int txPower = 27,
        int hopLimit = 3,
        double overrideFrequency = 0}) =>
    pb.Config_LoRaConfig(
      usePreset: true,
      modemPreset: preset,
      region: region,
      channelNum: channelNum,
      txPower: txPower,
      hopLimit: hopLimit,
      overrideFrequency: overrideFrequency,
    );

pb.Channel _primary(String name) => pb.Channel(
    index: 0,
    role: pb.Channel_Role.PRIMARY,
    settings: pb.ChannelSettings(name: name));

/// Radio settings beyond the preset (slot, power, hop limit, region) are
/// recorded on every session so a preset or antenna comparison is never
/// silently a frequency or power comparison.
void main() {
  group('frequency slot (firmware applyModemConfig)', () {
    RadioSettings s(_P p,
            {_R region = _R.US,
            String channel = '',
            int channelNum = 0,
            bool? fw28}) =>
        MeshtasticFrequency.settingsFor(
            _lora(p, region: region, channelNum: channelNum),
            primaryChannel: _primary(channel),
            firmware28: fw28)!;

    test('djb2 as the firmware hashes', () {
      expect(MeshtasticFrequency.djb2(''), 5381);
      expect(MeshtasticFrequency.djb2('a'), 5381 * 33 + 97);
      // Stays in uint32.
      expect(MeshtasticFrequency.djb2('MeshTest'), lessThan(1 << 32));
    });

    test('unnamed default channels land on the documented US slots', () {
      // Meshtastic's published US default slots / frequencies.
      for (final (p, slot, mhz) in [
        (_P.LONG_FAST, 20, 906.875),
        (_P.MEDIUM_SLOW, 52, 914.875),
        (_P.MEDIUM_FAST, 45, 913.125),
        (_P.SHORT_SLOW, 75, 920.625),
        (_P.SHORT_FAST, 68, 918.875),
      ]) {
        for (final fw28 in [true, false]) {
          final r = s(p, fw28: fw28);
          expect((r.frequencySlot, r.frequencyMHz), (slot, mhz),
              reason: '$p fw28=$fw28');
        }
      }
    });

    test('a named channel hashes its name; slot depends on the preset', () {
      const name = 'MeshTest';
      final lf = s(_P.LONG_FAST, channel: name);
      final mf = s(_P.MEDIUM_FAST, channel: name);
      final lm = s(_P.LONG_MODERATE, channel: name);
      final h = MeshtasticFrequency.djb2(name);
      expect(lf.frequencySlot, h % 104 + 1); // 26 MHz / 250 kHz
      expect(mf.frequencySlot, h % 104 + 1); // same bandwidth, same slot
      expect(lm.frequencySlot, h % 208 + 1); // 125 kHz: twice the slots
      expect(lf.frequencyMHz,
          closeTo(902 + 0.125 + (lf.frequencySlot! - 1) * 0.25, 0.0005));
    });

    test('an explicit channel_num wins', () {
      final r = s(_P.LONG_FAST, channel: 'MeshTest', channelNum: 7);
      expect(r.frequencySlot, 7);
      expect(r.frequencyMHz, 903.625);
    });

    test('EU 868 has a single 250 kHz slot', () {
      final r = s(_P.LONG_FAST, region: _R.EU_868);
      expect(
          (r.region, r.frequencySlot, r.frequencyMHz), ('EU_868', 1, 869.525));
    });

    test('2.8 rounds the slot count, 2.7 floors it (ANZ 433)', () {
      // 1.74 MHz / 250 kHz = 6.96: 7 slots on 2.8, 6 on 2.7.
      final h = MeshtasticFrequency.djb2('LongFast');
      expect(s(_P.LONG_FAST, region: _R.ANZ_433, fw28: true).frequencySlot,
          h % 7 + 1);
      expect(s(_P.LONG_FAST, region: _R.ANZ_433, fw28: false).frequencySlot,
          h % 6 + 1);
    });

    test('2.8 regions with a fixed default slot and padding', () {
      final r = s(_P.NARROW_SLOW, region: _R.EU_N_868);
      expect(r.frequencySlot, 1);
      expect(r.frequencyMHz, 869.442); // 869.4 + 31.25 kHz + 10.4 kHz
    });

    test('override frequency: no slot, the verbatim frequency', () {
      final r = MeshtasticFrequency.settingsFor(
          _lora(_P.LONG_FAST, overrideFrequency: 915.5),
          primaryChannel: _primary(''))!;
      expect(r.frequencySlot, isNull);
      expect(r.frequencyMHz, 915.5);
    });

    test('power 0 is the region limit; hop limit and region carried', () {
      final r = MeshtasticFrequency.settingsFor(
          _lora(_P.LONG_FAST, txPower: 0, hopLimit: 5))!;
      expect((r.region, r.txPowerDbm, r.hopLimit), ('US', 30, 5));
      expect(MeshtasticFrequency.settingsFor(null), isNull);
    });
  });

  group('MeshtasticRadio.radioSettings', () {
    test('from loraConfig and the primary channel', () {
      final radio = MeshtasticRadio()
        ..loraConfig = _lora(_P.LONG_FAST, txPower: 22, hopLimit: 4);
      radio.channels[0] = _primary('');
      expect(
          radio.radioSettings,
          const RadioSettings(
              region: 'US',
              frequencySlot: 20,
              txPowerDbm: 22,
              hopLimit: 4,
              frequencyMHz: 906.875));
      expect(MeshtasticRadio().radioSettings, isNull);
    });

    test('settingsAfter predicts what Radio Setup leaves (slot from name)', () {
      final radio = MeshtasticRadio()
        ..loraConfig =
            _lora(_P.SHORT_FAST, channelNum: 9, txPower: 22, hopLimit: 3);
      radio.channels[0] = _primary('');
      final after = radio.settingsAfter(TestProfile(
        channelName: 'MeshTest',
        channelKey: Uint8List(32),
        preset: MeshtasticPresets.longFast,
        isBase: false,
        regionName: 'US',
      ))!;
      // channelNum goes back to 0: the slot is the channel-name hash.
      expect(
          after.frequencySlot, MeshtasticFrequency.djb2('MeshTest') % 104 + 1);
      expect(after.txPowerDbm, 22, reason: 'each node keeps its power');
    });
  });

  test('schema v9 adds nullable radio settings to v8 sessions', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
      raw.execute('''
        CREATE TABLE coverage_maps (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          base_node_id INTEGER NULL,
          created_at INTEGER NOT NULL,
          description TEXT NOT NULL DEFAULT '',
          color_metric TEXT NOT NULL DEFAULT 'snr',
          signal_direction TEXT NOT NULL DEFAULT 'rx',
          base_lat REAL NULL,
          base_lon REAL NULL
        )''');
      raw.execute('''
        CREATE TABLE sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          coverage_map_id INTEGER NOT NULL,
          name TEXT NOT NULL DEFAULT '',
          started_at INTEGER NOT NULL,
          ended_at INTEGER NULL,
          is_active INTEGER NOT NULL DEFAULT 0,
          remote_node_id INTEGER NULL,
          base_node_id INTEGER NULL,
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
          beacon_kind TEXT NOT NULL DEFAULT '',
          beacon_interval_sec INTEGER NOT NULL DEFAULT 0,
          range_test_active INTEGER NOT NULL DEFAULT 0,
          packet_count INTEGER NOT NULL DEFAULT 0
        )''');
      // As of v9 (schema v10 adds uplink_snr to it).
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
          via_mqtt INTEGER NOT NULL DEFAULT 0,
          seq INTEGER NULL,
          source_kind TEXT NOT NULL DEFAULT 'passive',
          base_channel_util REAL NULL
        )''');
      raw.execute("INSERT INTO coverage_maps (name, created_at) "
          "VALUES ('Park', 1700000000)");
      raw.execute("INSERT INTO sessions (coverage_map_id, name, started_at, "
          "lora_preset) VALUES (1, 'old', 1700000000, 'LONG_FAST')");
      raw.execute('PRAGMA user_version = 8');
    }));
    addTearDown(db.close);

    expect(db.schemaVersion, 11);
    final old = (await db.getSessionById(1))!;
    expect(old.loraPreset, 'LONG_FAST');
    expect(old.region, isNull);
    expect(old.frequencySlot, isNull);
    expect(old.txPowerDbm, isNull);
    expect(old.hopLimit, isNull);
    expect(old.frequencyMhz, isNull);
    expect(old.radioSettings, isNull);
    expect(old.radioSettingsLine, '');

    final id = await db.createSession(
        coverageMapId: 1,
        radioSettings: const RadioSettings(
            region: 'US', frequencySlot: 20, txPowerDbm: 27));
    final s = (await db.getSessionById(id))!;
    expect((s.region, s.frequencySlot, s.txPowerDbm, s.hopLimit),
        ('US', 20, 27, null));
    expect(s.radioSettingsLine, 'Slot 20 · 27 dBm');
  });

  group('recording', () {
    const settings = RadioSettings(
        region: 'US',
        frequencySlot: 20,
        txPowerDbm: 27,
        hopLimit: 3,
        frequencyMHz: 906.875);

    testWidgets('startSession stores the settings; the panel shows them',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late AppDatabase db;
      late ProviderContainer container;
      late int mapId;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({'base_node_num': 2});
        final prefs = await SharedPreferences.getInstance();
        db = AppDatabase.forTesting(NativeDatabase.memory());
        final radio = FakeMeshRadio(currentPreset: MeshtasticPresets.longFast)
          ..radioSettings = settings;
        container = ProviderContainer(overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          meshRadioProvider.overrideWithValue(radio),
          gpsServiceProvider
              .overrideWithValue(GpsService(backend: FakeLocationBackend())),
        ]);
        final base = await db.upsertNode(nodeId: 2);
        mapId = await db.createCoverageMap(name: 'Polo', baseNodeId: base);
        final s = await container
            .read(sessionManagerProvider)
            .startSession(coverageMapId: mapId, baseMeshNodeId: 2);
        final row = (await db.getSessionById(s.id))!;
        expect(row.radioSettings, settings);
      });
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SessionPanel())),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      // Setup facts are folded under "Setup" while recording.
      await tester.tap(find.text('Setup'));
      await tester.pumpAndSettle();
      expect(find.text('Range setting: Long Fast'), findsOneWidget);
      expect(
          find.text('Slot 20 · 906.875 MHz · 27 dBm · hops 3'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await container.read(sessionManagerProvider).endSession();
        container.dispose();
      });
      // Close the database in teardown, outside the test's fake-time zone:
      // the panel's providers opened drift query streams there, and
      // db.close() waits for them to finish closing (a timer that never
      // fires inside runAsync).
      addTearDown(db.close);
    });

    testWidgets('the map\'s session tile lists the settings', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path);
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null));
      tester.view.physicalSize = const Size(430, 930);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final (db, map) = (await tester.runAsync(() async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final node = await db.upsertNode(nodeId: 1, longName: 'Base');
        final mapId =
            await db.createCoverageMap(name: 'Park', baseNodeId: node);
        final sid = await db.createSession(
            coverageMapId: mapId,
            name: 'walk',
            loraPreset: 'LONG_FAST',
            radioSettings: settings);
        await db.insertPacketEvent(PacketEventsCompanion.insert(
          sessionId: sid,
          timestamp: DateTime(2026, 10, 1, 12),
          direction: PacketDirection.rx,
          sourceNodeId: node,
          packetType: PacketType.telemetry,
          rxSnr: const Value(4),
          rxLat: const Value(33.68),
          rxLon: const Value(-116.24),
        ));
        await db.endSession(sid);
        final map =
            (await db.getAllCoverageMaps()).firstWhere((m) => m.id == mapId);
        return (db, map);
      }))!;
      addTearDown(() => tester.runAsync(db.close));
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(home: CoverageMapDetailScreen(map: map)),
      ));
      Future<void> settle([int rounds = 12]) async {
        for (var i = 0; i < rounds; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await settle(20);
      await tester.drag(
          find.text('Signal (base → you)'), const Offset(0, -700));
      await settle();
      expect(
          find.textContaining(
              'Long Fast · Slot 20 · 906.875 MHz · 27 dBm · hops 3'),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
