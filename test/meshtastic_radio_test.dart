// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/proto/meshtastic/admin.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/channel.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/portnums.pbenum.dart' as pb;
import 'package:mesh_analyzer/utils/constants.dart';

void main() {
  group('MeshtasticPresets', () {
    test('every enum preset round-trips through id and enum', () {
      for (final p in MeshtasticPresets.testPresets) {
        expect(MeshtasticPresets.fromId(p.id), p);
        final e = MeshtasticPresets.toModemPreset(p.id)!;
        expect(MeshtasticPresets.fromModemPreset(e), p);
        expect(
            MeshtasticPresets.fromConfig(
                pb.Config_LoRaConfig(usePreset: true, modemPreset: e)),
            p);
      }
    });

    // firmware src/mesh/MeshRadio.h modemPresetToParams (non-wide LoRa):
    // v2.7.26.54e0d8d l.132-181; MEDIUM_TURBO, LITE_*, NARROW_*, TINY_*
    // from v2.8.2.d5f1619 l.215-299; VERY_LONG_SLOW has no case in either
    // (default: LONG_FAST).
    const firmware = {
      'SHORT_TURBO': (7, 500.0, 5),
      'SHORT_FAST': (7, 250.0, 5),
      'SHORT_SLOW': (8, 250.0, 5),
      'MEDIUM_FAST': (9, 250.0, 5),
      'MEDIUM_SLOW': (10, 250.0, 5),
      'LONG_FAST': (11, 250.0, 5),
      'LONG_MODERATE': (11, 125.0, 8),
      'LONG_SLOW': (12, 125.0, 8),
      'LONG_TURBO': (11, 500.0, 8),
      'VERY_LONG_SLOW': (11, 250.0, 5),
      'LITE_FAST': (9, 125.0, 5),
      'LITE_SLOW': (10, 125.0, 5),
      'NARROW_FAST': (7, 62.5, 6),
      'NARROW_SLOW': (8, 62.5, 6),
      'MEDIUM_TURBO': (9, 500.0, 5),
      'TINY_FAST': (7, 15.6, 5),
      'TINY_SLOW': (8, 15.6, 6),
    };

    test('table matches the firmware parameters', () {
      for (final e in firmware.entries) {
        final p = MeshtasticPresets.fromId(e.key)!;
        expect((p.sf, p.bwKHz, p.cr), e.value, reason: e.key);
      }
      expect(MeshtasticPresets.longSlow.deprecated, isTrue);
      expect(MeshtasticPresets.longSlow.displayName, 'Long Slow (deprecated)');
      expect(MeshtasticPresets.longSlow.label, 'Long Slow (deprecated)');
      expect(MeshtasticPresets.longFast.deprecated, isFalse);
      expect(MeshtasticPresets.longFast.displayName, 'Long Fast');
      expect(MeshtasticPresets.narrowSlow.displayName, 'Narrow Slow');
      expect(MeshtasticPresets.liteFast.displayName, 'Lite Fast');
      // Deprecated LONG_SLOW is kept (old sessions use it) but last.
      expect(MeshtasticPresets.testPresets.last, MeshtasticPresets.longSlow);
      expect(
          MeshtasticPresets.testPresets, contains(MeshtasticPresets.longTurbo));
    });

    test('every protobuf ModemPreset maps to its own firmware parameters', () {
      for (final e in pb.Config_LoRaConfig_ModemPreset.values) {
        final p = MeshtasticPresets.fromModemPreset(e);
        expect(p.id, e.name);
        expect(firmware.containsKey(e.name), isTrue,
            reason: '${e.name} missing from the firmware table');
        expect((p.sf, p.bwKHz, p.cr), firmware[e.name], reason: e.name);
        // Only LONG_FAST itself and VERY_LONG_SLOW (no firmware case)
        // run with LONG_FAST's parameters.
        final asLongFast = (p.sf, p.bwKHz, p.cr) ==
            (
              MeshtasticPresets.longFast.sf,
              MeshtasticPresets.longFast.bwKHz,
              MeshtasticPresets.longFast.cr
            );
        expect(asLongFast, e.name == 'LONG_FAST' || e.name == 'VERY_LONG_SLOW',
            reason: e.name);
      }
    });

    test('VERY_LONG_SLOW runs with LONG_FAST parameters', () {
      final p = MeshtasticPresets.fromModemPreset(
          pb.Config_LoRaConfig_ModemPreset.VERY_LONG_SLOW);
      expect(p.id, 'VERY_LONG_SLOW');
      expect(p.deprecated, isTrue);
      expect((p.sf, p.bwKHz, p.cr), (11, 250.0, 5));
    });

    group('presetsForRegion', () {
      List<String> ids(String region) =>
          [for (final p in MeshtasticPresets.presetsForRegion(region)) p.id];

      test('US and ANZ: the standard set incl. both 500 kHz presets', () {
        for (final r in ['US', 'ANZ', 'UNSET', '']) {
          expect(
              ids(r),
              [
                'LONG_MODERATE', 'LONG_FAST', 'LONG_TURBO', 'MEDIUM_SLOW', //
                'MEDIUM_FAST', 'MEDIUM_TURBO', 'SHORT_SLOW', 'SHORT_FAST',
                'SHORT_TURBO', 'LONG_SLOW',
              ],
              reason: r);
        }
      });

      test('firmware older than 2.8: no MEDIUM_TURBO (it would run Long Fast)',
          () {
        List<String> on(String fw) => [
              for (final p in MeshtasticPresets.presetsForRegion('US',
                  firmwareVersion: fw))
                p.id
            ];
        expect(on('2.7.26.54e0d8d'), isNot(contains('MEDIUM_TURBO')));
        expect(on('2.7.26.54e0d8d'), contains('SHORT_TURBO'));
        expect(on('2.8.2.d5f1619'), contains('MEDIUM_TURBO'));
        expect(on('3.0.0'), contains('MEDIUM_TURBO'));
        expect(on(''), contains('MEDIUM_TURBO'), reason: 'unknown firmware');
      });

      test('ham regions: 2 m gets the tiny presets, 1.25 m and 70 cm narrow',
          () {
        for (final r in ['ITU1_2M', 'ITU2_2M', 'ITU3_2M']) {
          expect(ids(r), ['TINY_SLOW', 'TINY_FAST'], reason: r);
          expect(MeshtasticPresets.defaultForRegion(r),
              MeshtasticPresets.tinyFast);
        }
        for (final r in ['ITU2_125CM', 'ITU1_70CM', 'ITU2_70CM', 'ITU3_70CM']) {
          expect(ids(r), ['NARROW_SLOW', 'NARROW_FAST'], reason: r);
          expect(MeshtasticPresets.defaultForRegion(r),
              MeshtasticPresets.narrowSlow);
        }
      });

      test('a 2.8 radio on Medium Turbo reads back as Medium Turbo', () {
        // With the 2.7.26 protobufs the value 16 was unknown: Dart read it
        // as LONG_FAST (the raw 16 went to unknownFields), so the app
        // showed and recorded a Medium Turbo radio as Long Fast.
        final cfg = pb.Config_LoRaConfig(
            usePreset: true,
            modemPreset: pb.Config_LoRaConfig_ModemPreset.MEDIUM_TURBO);
        final back = pb.Config_LoRaConfig.fromBuffer(cfg.writeToBuffer());
        expect(back.unknownFields.isEmpty, isTrue);
        expect(
            MeshtasticPresets.fromConfig(back), MeshtasticPresets.mediumTurbo);
        back.modemPreset = pb.Config_LoRaConfig_ModemPreset.LONG_FAST;
        final written = pb.Config_LoRaConfig.fromBuffer(back.writeToBuffer());
        expect(written.modemPreset, pb.Config_LoRaConfig_ModemPreset.LONG_FAST);
      });

      test('EU_868: no 500 kHz presets, no EU narrow/lite ones', () {
        final list = MeshtasticPresets.presetsForRegion('EU_868');
        expect(list.every((p) => p.bwKHz <= 250), isTrue);
        expect(ids('EU_868'), [
          'LONG_MODERATE', 'LONG_FAST', 'MEDIUM_SLOW', 'MEDIUM_FAST', //
          'SHORT_SLOW', 'SHORT_FAST', 'LONG_SLOW',
        ]);
        expect(MeshtasticPresets.defaultForRegion('EU_868'),
            MeshtasticPresets.longFast);
      });

      test('EU_N_868: only the narrow presets, NARROW_SLOW by default', () {
        expect(ids('EU_N_868'), ['NARROW_SLOW', 'NARROW_FAST']);
        expect(MeshtasticPresets.defaultForRegion('EU_N_868'),
            MeshtasticPresets.narrowSlow);
      });

      test('EU_866: only the lite presets, LITE_FAST by default', () {
        expect(ids('EU_866'), ['LITE_SLOW', 'LITE_FAST']);
        expect(MeshtasticPresets.defaultForRegion('EU_866'),
            MeshtasticPresets.liteFast);
      });

      test("a region's default is always one it offers", () {
        for (final r in pb.Config_LoRaConfig_RegionCode.values) {
          expect(MeshtasticPresets.presetsForRegion(r.name),
              contains(MeshtasticPresets.defaultForRegion(r.name)),
              reason: r.name);
        }
      });
    });

    test('custom config maps to a CUSTOM preset with bandwidth codes', () {
      final p = MeshtasticPresets.fromConfig(pb.Config_LoRaConfig(
        usePreset: false,
        spreadFactor: 10,
        bandwidth: 62,
        codingRate: 6,
      ))!;
      expect(p.id, 'CUSTOM');
      expect((p.sf, p.bwKHz, p.cr), (10, 62.5, 6));

      final noCr = MeshtasticPresets.fromConfig(pb.Config_LoRaConfig(
          usePreset: false, spreadFactor: 9, bandwidth: 250))!;
      expect(noCr.cr, 5);
      expect(noCr.bwKHz, 250);
    });

    test('null config is unknown', () {
      expect(MeshtasticPresets.fromConfig(null), isNull);
    });
  });

  group('receivedPacketFrom', () {
    pb.MeshPacket packet({
      int from = 5,
      int hopStart = 0,
      int hopLimit = 0,
      double snr = 0,
      int rssi = 0,
      pb.PortNum port = pb.PortNum.POSITION_APP,
    }) =>
        pb.MeshPacket(
          from: from,
          id: 99,
          channel: 3,
          viaMqtt: true,
          hopStart: hopStart,
          hopLimit: hopLimit,
          rxSnr: snr,
          rxRssi: rssi,
          decoded: pb.Data(portnum: port, payload: [1, 2, 3]),
        );

    test('maps signal, hops, type and payload', () {
      final r = receivedPacketFrom(
          packet(hopStart: 3, hopLimit: 1, snr: 7.5, rssi: -88),
          myNodeNum: 1)!;
      expect(r.from, 5);
      expect(r.packetId, 99);
      expect(r.type, PacketType.position);
      expect(r.snr, 7.5);
      expect(r.rssi, -88);
      expect(r.hops, 2);
      expect(r.channelIndex, 3);
      expect(r.viaMqtt, isTrue);
      expect(r.payload, [1, 2, 3]);
    });

    test('SNR 0.0 dB is a valid reading when RSSI is present', () {
      final r = receivedPacketFrom(packet(snr: 0, rssi: -95), myNodeNum: 1)!;
      expect(r.snr, 0.0);
      expect(r.rssi, -95);
    });

    test('rssi 0 (local / queued packet) means no signal data at all', () {
      final r = receivedPacketFrom(packet(snr: 4.5, rssi: 0), myNodeNum: 1)!;
      expect(r.snr, isNull);
      expect(r.rssi, isNull);
    });

    test('rx_time and the handshake flag mark replayed packets stale', () {
      final fresh = receivedPacketFrom(packet(), myNodeNum: 1)!;
      expect(fresh.rxTime, isNull, reason: 'rx_time 0 = node has no clock');
      expect(fresh.isStale(DateTime.now()), isFalse);

      final old = packet()..rxTime = 1700000000;
      final r = receivedPacketFrom(old, myNodeNum: 1)!;
      expect(r.rxTime, DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(r.isStale(DateTime.now()), isTrue);

      final queued = receivedPacketFrom(packet(), myNodeNum: 1, queued: true)!;
      expect(queued.queued, isTrue);
      expect(queued.isStale(DateTime.now()), isTrue);
    });

    test('zero signal is null; old firmware (hopStart 0) is direct', () {
      final r = receivedPacketFrom(packet(hopLimit: 2), myNodeNum: 1)!;
      expect(r.snr, isNull);
      expect(r.rssi, isNull);
      expect(r.hops, 0);
    });

    test('hops are clamped to 0..7', () {
      expect(receivedPacketFrom(packet(hopStart: 7, hopLimit: 0))!.hops, 7);
      expect(receivedPacketFrom(packet(hopStart: 1, hopLimit: 3))!.hops, 0);
    });

    test('routing replies are emitted as ack type', () {
      final r = receivedPacketFrom(packet(port: pb.PortNum.ROUTING_APP))!;
      expect(r.type, PacketType.ack);
    });

    test('encrypted packets (no decoded data) are type other, no payload', () {
      final r = receivedPacketFrom(pb.MeshPacket(from: 5, id: 1))!;
      expect(r.type, PacketType.other);
      expect(r.payload, isEmpty);
    });

    test('packets from node 0 or our own radio are skipped', () {
      expect(receivedPacketFrom(packet(from: 0), myNodeNum: 1), isNull);
      expect(receivedPacketFrom(packet(from: 1), myNodeNum: 1), isNull);
    });
  });

  group('ping packet', () {
    test('uses the minimum hop limit and asks for an ACK', () {
      final p = buildDataPacket(
        id: 7,
        to: 2,
        portnum: pb.PortNum.PRIVATE_APP,
        payload: 'ping'.codeUnits,
        wantAck: true,
        hopLimit: pingHopLimit,
      );
      final decoded =
          pb.ToRadio.fromBuffer(pb.ToRadio(packet: p).writeToBuffer());
      expect(decoded.packet.hopLimit, 1);
      expect(decoded.packet.wantAck, isTrue);
    });

    test('other data packets leave the hop limit to the firmware', () {
      final p = buildDataPacket(
          id: 7, to: 2, portnum: pb.PortNum.NODEINFO_APP, payload: [1]);
      expect(p.hopLimit, 0);
    });
  });

  group('radioNodeFrom', () {
    test('maps name, hardware, position, hops and last heard', () {
      final n = radioNodeFrom(pb.NodeInfo(
        num: 5,
        user: pb.User(
            longName: 'Base',
            shortName: 'BS',
            hwModel: pb.HardwareModel.TRACKER_T1000_E),
        position: pb.Position(latitudeI: 336800000, longitudeI: -1162400000),
        hopsAway: 2,
        lastHeard: 1700000000,
      ));
      expect(n.num, 5);
      expect(n.longName, 'Base');
      expect(n.shortName, 'BS');
      expect(n.hwModel, 'TRACKER_T1000_E');
      expect(n.latitude, closeTo(33.68, 1e-9));
      expect(n.longitude, closeTo(-116.24, 1e-9));
      expect(n.hasPosition, isTrue);
      expect(n.hopsAway, 2);
      expect(
          n.lastHeard, DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
    });

    test('missing fields stay null/empty', () {
      final n = radioNodeFrom(pb.NodeInfo(num: 6));
      expect(n.hasUser, isFalse);
      expect(n.hasPosition, isFalse);
      expect(n.hopsAway, isNull);
      expect(n.lastHeard, isNull);
    });
  });

  group('MeshtasticRadio (demo radio)', () {
    MeshtasticRadio radio({
      pb.Config_LoRaConfig? lora,
      List<int>? psk,
    }) =>
        MeshtasticRadio()
          ..enterDemo(
            name: 'demo',
            myNodeNum: 1,
            nodeInfos: [
              pb.NodeInfo(
                  num: 1,
                  user: pb.User(
                      longName: 'Me', hwModel: pb.HardwareModel.RAK4631))
            ],
            lora: lora ??
                pb.Config_LoRaConfig(
                  usePreset: true,
                  modemPreset: pb.Config_LoRaConfig_ModemPreset.MEDIUM_FAST,
                  region: pb.Config_LoRaConfig_RegionCode.EU_868,
                ),
            channelTable: [
              pb.Channel(
                index: 0,
                role: pb.Channel_Role.PRIMARY,
                settings: pb.ChannelSettings(
                    name: 'MeshTest', psk: psk ?? List.filled(32, 1)),
              ),
            ],
          );

    test('exposes protocol-neutral state', () async {
      final r = radio();
      expect(r.protocol, RadioProtocol.meshtastic);
      expect(r.isReady, isTrue);
      expect(r.currentPreset, MeshtasticPresets.mediumFast);
      expect(r.regionName, 'EU_868');
      expect(r.regionFrequencyMHz, 868);
      expect(r.primaryChannelName, 'MeshTest');
      expect(r.onPublicChannel, isFalse);
      expect(r.myNodeId, 1);
      expect(r.nodes[1]!.longName, 'Me');
      expect(await r.connectionState.first, RadioConnectionState.ready);
      final info = await r.queryDevice();
      expect(info.model, 'RAK4631');
      expect(info.firmwareVersion, '');
    });

    test('1-byte key is the public channel', () {
      expect(radio(psk: [1]).onPublicChannel, isTrue);
    });

    test('the default key with any last byte is the public channel', () {
      // Firmware expands every 1-byte shorthand 1..255 to the default key
      // plus (n - 1) on the last byte, so all of them are well known.
      const defaultKey = MeshtasticRadio.defaultPsk;
      expect(defaultKey.last, 0x01);
      expect(radio(psk: [...defaultKey]).onPublicChannel, isTrue);
      for (var last = 0x00; last <= 0xff; last++) {
        final key = [...defaultKey]..[15] = last;
        expect(radio(psk: key).onPublicChannel, isTrue, reason: 'last=$last');
      }
      expect(radio(psk: []).onPublicChannel, isTrue);
      expect(radio(psk: [0]).onPublicChannel, isTrue);
    });

    test('other keys are private', () {
      final rnd = Random(42);
      final key32 = List.generate(32, (_) => rnd.nextInt(256));
      expect(radio(psk: key32).onPublicChannel, isFalse);
      // Default key with a different first byte.
      expect(
          radio(psk: [...MeshtasticRadio.defaultPsk]..[0] = 0x00)
              .onPublicChannel,
          isFalse);
      // 32-byte key that starts with the default key.
      expect(
          radio(psk: [...MeshtasticRadio.defaultPsk, ...List.filled(16, 1)])
              .onPublicChannel,
          isFalse);
    });

    test('region frequency rule', () {
      expect(MeshtasticRadio.frequencyForRegion(null), 915);
      expect(
          MeshtasticRadio.frequencyForRegion(
              pb.Config_LoRaConfig_RegionCode.US),
          915);
      expect(
          MeshtasticRadio.frequencyForRegion(
              pb.Config_LoRaConfig_RegionCode.EU_868),
          868);
      expect(
          MeshtasticRadio.frequencyForRegion(
              pb.Config_LoRaConfig_RegionCode.ANZ),
          915);
      expect(
          MeshtasticRadio.frequencyForRegion(
              pb.Config_LoRaConfig_RegionCode.UNSET),
          915);
    });

    test('a demo radio never pings', () async {
      final r = radio();
      var called = false;
      final o = await r.ping(2, beforeSend: (_) => called = true);
      expect(o.status, PingStatus.error);
      expect(called, isFalse);
    });

    test('a ping that cannot be sent is an error outcome, never a throw',
        () async {
      // Not connected, not demo: sendData throws StateError.
      final r = MeshtasticRadio();
      var recorded = 0;
      final o = await r.ping(2, beforeSend: (id) => recorded = id);
      expect(o.status, PingStatus.error);
      expect(o.errorReason, 'SEND_FAILED');
      expect(o.pingId, recorded);
    });
  });

  group('schema v5', () {
    test('a session created without protocol reads meshtastic', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      expect(db.schemaVersion, greaterThanOrEqualTo(5));
      final baseId = await db.upsertNode(nodeId: 2);
      final mapId = await db.createCoverageMap(name: 'm', baseNodeId: baseId);

      final a = await db.createSession(coverageMapId: mapId);
      expect((await db.getSessionById(a))!.protocol, 'meshtastic');

      final b =
          await db.createSession(coverageMapId: mapId, protocol: 'meshcore');
      expect((await db.getSessionById(b))!.protocol, 'meshcore');
    });

    test('inserting a session row without the column uses the default',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final baseId = await db.upsertNode(nodeId: 2);
      final mapId = await db.createCoverageMap(name: 'm', baseNodeId: baseId);
      final id = await db.into(db.sessions).insert(SessionsCompanion.insert(
            coverageMapId: mapId,
            startedAt: DateTime(2026),
            name: const Value('x'),
          ));
      expect((await db.getSessionById(id))!.protocol, 'meshtastic');
    });
  });

  group('sendAdmin retry', () {
    final msg = pb.AdminMessage(beginEditSettings: true);
    TimeoutException timeout() => TimeoutException('no ACK');

    test('one unanswered write is sent again, then succeeds', () async {
      final r = _AdminAttempts([timeout(), null]);
      await r.sendAdmin(msg);
      expect(r.attempts, hasLength(2));
    });

    test('two unanswered writes give up', () async {
      final r = _AdminAttempts([timeout(), timeout()]);
      await expectLater(r.sendAdmin(msg), throwsA(isA<TimeoutException>()));
      expect(r.attempts, hasLength(2));
    });

    test('a NAK is never retried', () async {
      final r = _AdminAttempts([StateError('Node rejected setting: BAD')]);
      await expectLater(r.sendAdmin(msg), throwsStateError);
      expect(r.attempts, hasLength(1));
    });

    test('no retry once the link is gone (the radio rebooted)', () async {
      final r = _AdminAttempts([timeout(), null])..ready = false;
      // The attempt itself is scripted, so only the retry check sees ready.
      await expectLater(r.sendAdmin(msg), throwsA(isA<TimeoutException>()));
      expect(r.attempts, hasLength(1));
    });

    test('retries: 0 (the commit) sends once', () async {
      final r = _AdminAttempts([timeout()]);
      await expectLater(
          r.sendAdmin(msg, retries: 0), throwsA(isA<TimeoutException>()));
      expect(r.attempts, hasLength(1));
    });
  });

  group('commitSettings', () {
    test('a commit never sent (link already gone) fails instead of passing',
        () async {
      final r = _AdminAttempts([null])..ready = false;
      await expectLater(r.commitSettings(), throwsStateError);
      expect(r.attempts, isEmpty);
    });

    test('silence after a sent commit is the reboot', () async {
      final r = _AdminAttempts([TimeoutException('no ACK')]);
      await r.commitSettings();
      expect(r.attempts, hasLength(1));
    });
  });

  group('newer firmware enum values', () {
    test('a preset the protos do not know is dropped, so the change sticks',
        () async {
      // LoRaConfig field 2 (modem_preset) = 99: unknown to v2.7.26 protos.
      final current = pb.Config_LoRaConfig.fromBuffer([0x10, 99])
        ..usePreset = true;
      expect(current.unknownFields.hasField(2), isTrue);
      final radio = _AdminCapture()
        ..enterDemo(
          name: 'base',
          myNodeNum: 7,
          nodeInfos: [pb.NodeInfo(num: 7)],
          lora: current,
          channelTable: [pb.Channel(index: 0, role: pb.Channel_Role.PRIMARY)],
        );
      await radio.applyTestProfile(TestProfile(
        channelName: 'MeshTest',
        channelKey: Uint8List.fromList(List.generate(32, (i) => i)),
        preset: MeshtasticPresets.fromId('MEDIUM_FAST')!,
        isBase: false,
      ));
      final lora = radio.sent
          .firstWhere((m) => m.hasSetConfig() && m.setConfig.hasLora())
          .setConfig
          .lora;
      // What the firmware decodes: field 2 once, with our value.
      final decoded = pb.Config_LoRaConfig.fromBuffer(lora.writeToBuffer());
      expect(decoded.modemPreset, pb.Config_LoRaConfig_ModemPreset.MEDIUM_FAST);
      expect(decoded.unknownFields.hasField(2), isFalse);
    });

    test('a routing error code the protos do not know is a NAK, not an ACK',
        () {
      // Routing field 3 (error_reason) = 99.
      final routing = pb.Routing.fromBuffer([0x18, 99]);
      expect(routing.hasErrorReason(), isFalse,
          reason: 'Dart hides the value, which would read as NONE');
      expect(routing.unknownFields.hasField(3), isTrue);
      final reply = RoutingReply(
          requestId: 1,
          error: pb.Routing_Error.NONE,
          packet: pb.MeshPacket(),
          unknownError: true);
      expect(reply.isAck, isFalse);
      expect(reply.errorName, 'UNKNOWN');
    });
  });

  group('applyTestProfile', () {
    test('writes the private channel, preset and beacon in one edit', () async {
      final radio = _AdminCapture()
        ..enterDemo(
          name: 'base',
          myNodeNum: 7,
          nodeInfos: [pb.NodeInfo(num: 7)],
          lora: pb.Config_LoRaConfig(
            usePreset: true,
            modemPreset: pb.Config_LoRaConfig_ModemPreset.LONG_FAST,
            region: pb.Config_LoRaConfig_RegionCode.UNSET,
            txPower: 27,
            overrideFrequency: 906.5,
            channelNum: 20,
          ),
          channelTable: [
            pb.Channel(index: 0, role: pb.Channel_Role.PRIMARY),
          ],
        );
      final key = List<int>.generate(32, (i) => i);
      await radio.applyTestProfile(TestProfile(
        channelName: 'MeshTest',
        channelKey: Uint8List.fromList(key),
        preset: MeshtasticPresets.fromId('MEDIUM_SLOW')!,
        isBase: true,
        beacon: const BeaconConfig(intervalSec: 30, kind: BeaconKind.rangeTest),
      ));

      final sent = radio.sent;
      expect(sent.first.beginEditSettings, isTrue);
      expect(sent.last.commitEditSettings, isTrue);

      final channels = sent.where((m) => m.hasSetChannel()).toList();
      expect(channels, hasLength(8));
      expect(channels.first.setChannel.settings.name, 'MeshTest');
      expect(channels.first.setChannel.settings.psk, key);
      expect(
          channels
              .skip(1)
              .every((m) => m.setChannel.role == pb.Channel_Role.DISABLED),
          isTrue);

      final lora = sent
          .firstWhere((m) => m.hasSetConfig() && m.setConfig.hasLora())
          .setConfig
          .lora;
      expect(lora.modemPreset, pb.Config_LoRaConfig_ModemPreset.MEDIUM_SLOW);
      expect(lora.usePreset, isTrue);
      expect(lora.region, pb.Config_LoRaConfig_RegionCode.US);
      expect(lora.txPower, 27, reason: 'keeps the node\'s own tx power');
      expect(lora.channelNum, 0);
      expect(lora.hasOverrideFrequency(), isFalse,
          reason: 'both nodes must derive the slot from the channel name');

      final rt = sent
          .firstWhere(
              (m) => m.hasSetModuleConfig() && m.setModuleConfig.hasRangeTest())
          .setModuleConfig
          .rangeTest;
      expect(rt.enabled, isTrue);
      expect(rt.sender, 30);
    });

    // docs/design/ipad step 5: the mobile's GPS stands in for a phone
    // without one, so Node Setup switches it on and to a fix every 30 s.
    _AdminCapture gpsRadio(pb.Config_PositionConfig? position) {
      final radio = _AdminCapture()
        ..enterDemo(
          name: 'mobile',
          myNodeNum: 7,
          nodeInfos: [pb.NodeInfo(num: 7)],
          lora: pb.Config_LoRaConfig(
            usePreset: true,
            modemPreset: pb.Config_LoRaConfig_ModemPreset.LONG_FAST,
            region: pb.Config_LoRaConfig_RegionCode.US,
          ),
          channelTable: [pb.Channel(index: 0, role: pb.Channel_Role.PRIMARY)],
        );
      if (position != null) {
        radio.configs[pb.Config_PayloadVariant.position] =
            pb.Config(position: position);
      }
      return radio;
    }

    TestProfile gpsProfile({required bool base}) => TestProfile(
          channelName: 'MeshTest',
          channelKey: Uint8List(32),
          preset: MeshtasticPresets.fromId('MEDIUM_FAST')!,
          isBase: base,
          beacon: base ? const BeaconConfig.off() : null,
        );

    pb.Config_PositionConfig? positionWritten(_AdminCapture r) {
      final m =
          r.sent.where((m) => m.hasSetConfig() && m.setConfig.hasPosition());
      return m.isEmpty ? null : m.single.setConfig.position;
    }

    test('mobile: GPS on and a fix every 30 s, the rest kept', () async {
      final radio = gpsRadio(pb.Config_PositionConfig(
        gpsMode: pb.Config_PositionConfig_GpsMode.DISABLED,
        positionBroadcastSecs: 900,
      ));
      await radio.applyTestProfile(gpsProfile(base: false));
      final p = positionWritten(radio)!;
      expect(p.gpsMode, pb.Config_PositionConfig_GpsMode.ENABLED);
      expect(p.gpsUpdateInterval, 30);
      expect(p.positionBroadcastSecs, 900, reason: 'broadcasts unchanged');
      expect(radio.sent.last.commitEditSettings, isTrue,
          reason: 'inside the one edit transaction');
    });

    test('base, no GPS chip, fixed position or already fast: not written',
        () async {
      for (final (pos, base) in [
        (pb.Config_PositionConfig(), true),
        (
          pb.Config_PositionConfig(
              gpsMode: pb.Config_PositionConfig_GpsMode.NOT_PRESENT),
          false
        ),
        (pb.Config_PositionConfig(fixedPosition: true), false),
        (
          pb.Config_PositionConfig(
              gpsMode: pb.Config_PositionConfig_GpsMode.ENABLED,
              gpsUpdateInterval: 10),
          false
        ),
        (null, false),
      ]) {
        final radio = gpsRadio(pos);
        await radio.applyTestProfile(gpsProfile(base: base));
        expect(positionWritten(radio), isNull, reason: '$pos base=$base');
      }
    });

    test('labels for the backup comparison', () {
      expect(meshtasticGpsLabel(pb.Config_PositionConfig()), 'off');
      expect(
          meshtasticGpsLabel(pb.Config_PositionConfig(
              gpsMode: pb.Config_PositionConfig_GpsMode.ENABLED)),
          'on, every 2 min (default)');
      expect(
          meshtasticGpsLabel(pb.Config_PositionConfig(
              gpsMode: pb.Config_PositionConfig_GpsMode.ENABLED,
              gpsUpdateInterval: 30)),
          'on, every 30 s');
    });
  });
}

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
}

/// Scripts the outcome of each admin attempt, to test sendAdmin's retry.
class _AdminAttempts extends MeshtasticRadio {
  final List<Object?> outcomes; // null = ACK, else thrown
  final attempts = <pb.AdminMessage>[];
  bool ready = true;
  _AdminAttempts(this.outcomes);

  @override
  bool get isReady => ready;

  @override
  Future<void> sendAdminAttempt(
    pb.AdminMessage msg, {
    required Duration timeout,
  }) async {
    attempts.add(msg);
    final o = outcomes[attempts.length - 1];
    if (o != null) throw o;
  }
}
