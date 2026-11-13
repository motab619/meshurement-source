// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

// MeshCoreRadio against a scripted companion (fake_meshcore_transport.dart).
// Frame layouts follow meshcore-dev/MeshCore@81dbae5; line numbers in the
// test names are examples/companion_radio/MyMesh.cpp (MM) or src/ files.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_packets.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_presets.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_protocol.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_radio.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_sha256.dart';
import 'package:mesh_analyzer/utils/constants.dart';

import 'fake_meshcore_transport.dart';

final ownKey = keyOf([0x11, 0x22, 0x33, 0x44]);
final baseKey = keyOf([0xB0, 0x5E, 0x00, 0x01]);
final relayKey = keyOf([0xC7, 0x01]);
final otherKey = keyOf([0xD4, 0x02]);

const desc = RadioDescriptor(
    id: 'mc-1', name: 'MeshCore-Mobile', protocol: RadioProtocol.meshcore);

FakeMeshCoreTransport fakeRadio({List<List<int>>? contacts}) =>
    FakeMeshCoreTransport(
      ownKey: ownKey,
      contacts: contacts ??
          [
            contactFrame(key: baseKey, name: 'MeshTest Base', outPathLen: 0),
            contactFrame(
                key: relayKey,
                name: 'Hilltop',
                type: MeshCoreAdvType.repeater,
                outPathLen: 1,
                outPath: [0xC7],
                latE6: 33680000,
                lonE6: -116240000),
          ],
    );

MeshCoreRadio radioOn(FakeMeshCoreTransport t, {DateTime Function()? clock}) =>
    MeshCoreRadio(
      transport: t,
      commandTimeout: const Duration(milliseconds: 500),
      contactsIdleTimeout: const Duration(milliseconds: 500),
      statsInterval: const Duration(hours: 1),
      reconnectInitialDelay: const Duration(milliseconds: 10),
      clock: clock,
    );

Future<MeshCoreRadio> connected(FakeMeshCoreTransport t) async {
  final r = radioOn(t);
  await r.connect(desc);
  await pump();
  return r;
}

Future<void> pump([int ms = 20]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// `[0x88][snr*4][rssi][raw]` (MM:291-302).
List<int> rxLog(List<int> raw, {int snrQ = 30, int rssi = -90}) =>
    [0x88, snrQ & 0xFF, rssi & 0xFF, ...raw];

/// A signed advert payload (src/Mesh.cpp:252-289, AdvertDataHelpers.cpp).
List<int> advertPayload(Uint8List key, String name,
        {int type = MeshCoreAdvType.repeater, int? latE6, int? lonE6}) =>
    [
      ...key,
      ...le32(1700000100),
      ...List.filled(64, 0x5A),
      type | 0x80 | (latE6 != null ? 0x10 : 0),
      if (latE6 != null) ...[...le32(latE6), ...le32(lonE6!)],
      ...utf8.encode(name),
    ];

void main() {
  settingsBackupTests();
  group('connect handshake (design §3)', () {
    test(
        'DEVICE_QUERY first, then APP_START, time, contacts, channels, '
        'message drain; ready', () async {
      final t = fakeRadio();
      final r = radioOn(t);
      final states = <RadioConnectionState>[];
      final steps = <ConnectProgress?>[];
      final s1 = r.connectionState.listen(states.add);
      final s2 = r.connectProgressStream.listen(steps.add);
      await r.connect(desc);
      await pump();

      expect(t.writtenCodes, [
        MeshCoreCmd.deviceQuery,
        MeshCoreCmd.appStart,
        MeshCoreCmd.setDeviceTime,
        MeshCoreCmd.getContacts,
        MeshCoreCmd.getChannel, // slots 0-3 (max 4)
        MeshCoreCmd.getChannel,
        MeshCoreCmd.getChannel,
        MeshCoreCmd.getChannel,
        MeshCoreCmd.syncNextMessage,
        MeshCoreCmd.getStats, // first stats poll once ready
        MeshCoreCmd.sendTelemetryReq, // first own-GPS poll once ready
      ]);
      // App protocol 3 (V3 frames with SNR, MM:443/561).
      expect(t.writes[0], [22, 3]);
      // APP_START: name from byte 8 (MM:1076-1081).
      expect(t.writes[1].length, greaterThanOrEqualTo(8));
      expect(utf8.decode(t.writes[1].sublist(8)), 'Meshurement');
      expect(t.writes[2].length, 5);
      expect(states, [
        RadioConnectionState.disconnected,
        RadioConnectionState.connecting,
        RadioConnectionState.pairing,
        RadioConnectionState.configuring,
        RadioConnectionState.ready,
      ]);
      final contactSteps =
          steps.whereType<ConnectProgress>().where((p) => p.fraction != null);
      expect(contactSteps.map((p) => p.detail), ['1 of 2', '2 of 2']);
      expect(contactSteps.last.fraction, 1.0);
      expect(contactSteps.first.step, 'Downloading contacts');
      expect(r.isReady, isTrue);
      expect(r.connectProgress, isNull);
      expect(r.displayName, 'Mobile');

      await s1.cancel();
      await s2.cancel();
      await r.dispose();
    });

    test('retries DEVICE_QUERY when the first write gets no answer', () async {
      final t = fakeRadio();
      var n = 0;
      t.overrides[MeshCoreCmd.deviceQuery] = (_) => n++ == 0 ? [] : null;
      final r = await connected(t);
      expect(t.writtenCodes.take(3), [22, 22, 1]);
      expect(r.isReady, isTrue);
      await r.dispose();
    });

    test('capabilities and queryDevice from DEVICE_INFO', () async {
      final t = fakeRadio()
        ..deviceInfo = deviceInfoFrame(repeat: true, pathHashMode: 1);
      final r = await connected(t);
      final c = r.capabilities;
      expect(c.firmwareVersion, 'v1.18.0');
      expect(c.rangeTestExcluded, isTrue);
      expect(c.hasTraceroute, isTrue);
      expect(c.canRelay, isTrue);
      expect(c.pathHashBytes, 2);
      expect(c.protocolLevel, 14);
      expect(selectBeaconKind(c, protocol: r.protocol), BeaconKind.trace);
      final info = await r.queryDevice();
      expect(info.protocol, RadioProtocol.meshcore);
      expect(info.model, 'Seeed Wio Tracker L1');
      expect(info.firmwareVersion, 'v1.18.0');
      expect(info.protocolVersion, 14);
      await r.dispose();
    });
  });

  group('identity and nodes (design §5, §8)', () {
    test('myNodeId is the key prefix, big-endian', () async {
      final r = await connected(fakeRadio());
      expect(r.myNodeId, 0x11223344);
      expect(r.nodes[0x11223344]?.longName, 'Mobile');
      await r.dispose();
    });

    test('contacts become nodes', () async {
      final r = await connected(fakeRadio());
      final base = r.nodes[0xB05E0001]!;
      expect(base.longName, 'MeshTest Base');
      expect(base.shortName, 'b05e');
      expect(base.publicKey, baseKey);
      expect(base.nodeKind, NodeKind.chat);
      expect(base.hopsAway, 0);
      expect(base.hasPosition, isFalse);
      expect(base.lastHeard,
          DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
      final relay = r.nodes[meshCoreNodeNum(relayKey)]!;
      expect(relay.nodeKind, NodeKind.repeater);
      expect(relay.hopsAway, 1);
      expect(relay.latitude, closeTo(33.68, 1e-9));
      expect(relay.longitude, closeTo(-116.24, 1e-9));
      await r.dispose();
    });

    test('a contact with no path (0xFF) has unknown hops', () async {
      final r = await connected(
          fakeRadio(contacts: [contactFrame(key: otherKey, name: 'Far')]));
      expect(r.nodes[meshCoreNodeNum(otherKey)]!.hopsAway, isNull);
      await r.dispose();
    });

    test('NEW_ADVERT push (0x8A) adds a node', () async {
      final t = fakeRadio(contacts: []);
      final r = await connected(t);
      final updates = <RadioNode>[];
      final sub = r.nodeUpdates.listen(updates.add);
      final f = contactFrame(
          key: otherKey, name: 'Newcomer', type: MeshCoreAdvType.room);
      f[0] = MeshCorePush.newAdvert;
      t.push(f);
      await pump();
      expect(updates.single.longName, 'Newcomer');
      expect(r.nodes[meshCoreNodeNum(otherKey)]!.nodeKind, NodeKind.room);
      await sub.cancel();
      await r.dispose();
    });
  });

  group('packets from 0x88 (design §7a, §8)', () {
    late FakeMeshCoreTransport t;
    late MeshCoreRadio r;
    late List<ReceivedPacket> got;
    late StreamSubscription<ReceivedPacket> sub;

    setUp(() async {
      t = fakeRadio();
      r = await connected(t);
      got = [];
      sub = r.packets.listen(got.add);
    });

    tearDown(() async {
      await sub.cancel();
      await r.dispose();
    });

    test('a zero-hop flood advert: sender from the key, node added', () async {
      // header: route flood (1) | ADVERT (4) << 2, path_len 0.
      t.push(rxLog([
        0x11,
        0x00,
        ...advertPayload(otherKey, 'Ridge Rpt',
            latE6: 33000000, lonE6: -116e6.toInt()),
      ], snrQ: 26, rssi: -97));
      await pump();
      final p = got.single;
      expect(p.type, PacketType.advert);
      expect(p.from, meshCoreNodeNum(otherKey));
      expect(p.hops, 0);
      expect(p.hopsKnown, isTrue);
      expect(p.routeDirect, isFalse);
      expect(p.lastHopId, isNull);
      expect(p.snr, 6.5);
      expect(p.rssi, -97);
      expect(p.rxTime, isNotNull);
      final n = r.nodes[meshCoreNodeNum(otherKey)]!;
      expect(n.longName, 'Ridge Rpt');
      expect(n.nodeKind, NodeKind.repeater);
      expect(n.latitude, 33.0);
      expect(n.hopsAway, 0);
    });

    test(
        'a flood with 2 relays: hops 2, last hop resolved, sender from the '
        'source hash', () async {
      // TXT_MSG (2) flood: dest_hash, src_hash, MAC + ciphertext.
      t.push(rxLog([
        0x09, 0x02, 0xB0, 0xC7, // path: base, then the relay
        0x11, 0xD4, ...List.filled(18, 0xEE),
      ]));
      t.contacts = [];
      // otherKey (0xD4…) must be known for the source to resolve.
      final f = contactFrame(key: otherKey, name: 'Sender');
      f[0] = MeshCorePush.newAdvert;
      t.push(f);
      t.push(rxLog([
        0x09,
        0x02,
        0xB0,
        0xC7,
        0x11,
        0xD4,
        ...List.filled(18, 0xEE),
      ]));
      await pump();
      expect(got, hasLength(2));
      expect(got[0].from, 0, reason: 'source hash unknown before the advert');
      final p = got[1];
      expect(p.type, PacketType.direct);
      expect(p.from, meshCoreNodeNum(otherKey));
      expect(p.hops, 2);
      expect(p.hopsKnown, isTrue);
      expect(p.routeDirect, isFalse);
      expect(p.lastHopId, meshCoreNodeNum(relayKey));
    });

    test('an unknown last hop keeps its hash, left-aligned', () async {
      t.push(rxLog([0x15, 0x01, 0x99, ...List.filled(10, 1)])); // GRP_TXT
      await pump();
      expect(got.single.type, PacketType.group);
      expect(got.single.hops, 1);
      expect(got.single.lastHopId, 0x99000000);
    });

    test('a direct packet with hashes left on its path: hops unknown',
        () async {
      t.push(rxLog([0x0A, 0x01, 0x42, 0xB0, 0xD4, ...List.filled(18, 1)]));
      await pump();
      final p = got.single;
      expect(p.routeDirect, isTrue);
      expect(p.hopsKnown, isFalse);
      expect(p.hops, 0);
    });

    test('a zero-hop direct packet is heard from its sender', () async {
      t.push(rxLog([0x0A, 0x00, 0x11, 0xB0, ...List.filled(18, 1)]));
      await pump();
      final p = got.single;
      expect(p.routeDirect, isTrue);
      expect(p.hopsKnown, isTrue);
      expect(p.from, 0xB05E0001);
    });

    test('RSSI below -128 dBm wraps in the int8 and is unwrapped', () async {
      t.push(rxLog([0x15, 0x00, ...List.filled(10, 1)], rssi: 126));
      t.push(rxLog([0x15, 0x00, ...List.filled(10, 2)], rssi: -128));
      await pump();
      expect(got[0].rssi, -130);
      expect(got[1].rssi, -128);
    });

    test(
        'packet id = first 4 bytes of the firmware packet hash '
        '(src/Packet.cpp:41-50)', () async {
      final payload = [0x11, 0xB0, ...List.filled(18, 7)];
      t.push(rxLog([0x09, 0x01, 0xC7, ...payload]));
      // TRACE also hashes path_len.
      final trace = [...le32(5), ...le32(0), 2, ...baseKey.sublist(0, 4)];
      t.push(rxLog([0x26, 0x01, 0x28, ...trace]));
      await pump();
      final h = sha256([MeshCorePayloadType.txtMsg, ...payload]);
      expect(got[0].packetId, prefixNum(h));
      final ht = sha256([MeshCorePayloadType.trace, 0x01, ...trace]);
      expect(got[1].packetId, prefixNum(ht));
      expect(got[1].type, PacketType.trace);
      expect(got[1].from, 0xB05E0001,
          reason: 'a trace was last sent by the hop of its last SNR');
    });

    test('an unparseable raw packet is dropped', () async {
      t.push(rxLog([0x09, 0x05, 1])); // path longer than the frame
      await pump();
      expect(got, isEmpty);
    });
  });

  group('ping = trace (design §7c)', () {
    /// Off the community presets: pings are refused on the public mesh.
    FakeMeshCoreTransport testFreqRadio() =>
        fakeRadio()..selfInfo = selfInfoFrame(key: ownKey, freqKHz: 918000);

    test('refused on the public mesh before anything is sent', () async {
      final t = fakeRadio(); // a community preset
      final r = await connected(t);
      expect(r.onPublicChannel, isTrue);
      final before = t.writes.length;
      var called = false;
      final out = await r.ping(0xB05E0001, beforeSend: (_) => called = true);
      expect(out.status, PingStatus.error);
      expect(out.errorReason, 'PUBLIC_CHANNEL');
      expect(called, isFalse);
      expect(t.writes.length, before);
      await r.dispose();
    });

    /// Answers SEND_TRACE_PATH like a relaying base: the radio logs the
    /// returning frame (0x88), then reports the trace (0x89, MM:855-886).
    void baseAnswers(FakeMeshCoreTransport t,
        {int upSnrQ = 24, int downSnrQ = -10, int rssi = -101}) {
      t.after[MeshCoreCmd.sendTracePath] = (cmd) {
        final tag = cmd.sublist(1, 5);
        final hash = cmd.sublist(10);
        Timer(const Duration(milliseconds: 30), () {
          t.push(rxLog([
            0x26, 0x01, upSnrQ & 0xFF, // direct TRACE, one SNR in the path
            ...tag, ...le32(0), 2, ...hash,
          ], snrQ: downSnrQ, rssi: rssi));
          t.push([
            0x89,
            0,
            hash.length,
            2,
            ...tag,
            ...le32(0),
            ...hash,
            upSnrQ & 0xFF,
            downSnrQ & 0xFF,
          ]);
        });
      };
    }

    test('a full trace ping', () async {
      final t = testFreqRadio();
      baseAnswers(t);
      final r = await connected(t);
      final heard = <ReceivedPacket>[];
      final airtime = <double>[];
      final s1 = r.packets.listen(heard.add);
      final s2 = r.txAirtimeStream.listen(airtime.add);
      int? id;
      final out = await r.ping(0xB05E0001, beforeSend: (pid) {
        id = pid;
        t.events.add('beforeSend');
      });

      final cmd = t.writes.last;
      expect(t.events.indexOf('beforeSend'),
          lessThan(t.events.lastIndexOf('write:36')));
      // [36][tag][auth 0][flags 2 = 4-byte hashes][base key prefix]
      // (MM:1813-1838).
      expect(cmd.length, 14);
      expect(u32At(cmd, 1), id);
      expect(cmd.sublist(5, 9), [0, 0, 0, 0]);
      expect(cmd[9], 2);
      expect(cmd.sublist(10), baseKey.sublist(0, 4));

      expect(out.status, PingStatus.received);
      expect(out.pingId, id);
      expect(out.responder, 0xB05E0001);
      expect(out.uplinkSnr, 6.0);
      expect(out.snr, -2.5);
      expect(out.rssi, -101);
      expect(out.hops, 0);
      expect(out.replyPacketId, isNotNull);
      expect(out.roundTrip, greaterThan(const Duration(milliseconds: 20)));
      await pump();
      expect(heard, isEmpty, reason: 'our own trace return is the ping\'s');
      expect(airtime.single,
          closeTo(r.airtimeMsFor(MeshCoreRadio.tracePingBytes), 1e-9));
      // 15 bytes at USA SF7 / 62.5 kHz / 4/5.
      expect(airtime.single, inInclusiveRange(90, 130));
      await s1.cancel();
      await s2.cancel();
      await r.dispose();
    });

    test('times out when the base never answers', () async {
      final t = testFreqRadio();
      final r = await connected(t);
      final out =
          await r.ping(0xB05E0001, timeout: const Duration(milliseconds: 100));
      expect(out.status, PingStatus.timeout);
      expect(out.pingId, isNot(0));
      expect(out.roundTrip,
          greaterThanOrEqualTo(const Duration(milliseconds: 100)));
      await r.dispose();
    });

    test('a late trace after the timeout is not reported', () async {
      final t = testFreqRadio();
      baseAnswers(t);
      final r = await connected(t);
      final heard = <ReceivedPacket>[];
      final sub = r.packets.listen(heard.add);
      final out =
          await r.ping(0xB05E0001, timeout: const Duration(milliseconds: 5));
      expect(out.status, PingStatus.timeout);
      await pump(60);
      expect(heard.single.type, PacketType.trace,
          reason: 'no longer pending: logged like any other trace');
      await sub.cancel();
      await r.dispose();
    });

    test('an error reply is error:<ERR name>', () async {
      final t = testFreqRadio();
      t.overrides[MeshCoreCmd.sendTracePath] =
          (_) => [err(MeshCoreErr.tableFull)];
      final r = await connected(t);
      final out = await r.ping(0xB05E0001);
      expect(out.status, PingStatus.error);
      expect(out.errorReason, 'error:TABLE_FULL');
      await r.dispose();
    });

    test('no answer to SEND_TRACE_PATH is an error, not a trace timeout',
        () async {
      // Nothing confirmed the trace went on air (busy or rebooting radio):
      // a timeout would read as the base out of range.
      final t = testFreqRadio();
      t.overrides[MeshCoreCmd.sendTracePath] = (_) => [];
      final r = await connected(t);
      final out = await r.ping(0xB05E0001);
      expect(out.status, PingStatus.error);
      expect(out.errorReason, 'RADIO_BUSY');
      expect(out.responder, isNull);
      await r.dispose();
    });

    test('a failed Bluetooth write is a link error, not a trace timeout',
        () async {
      final t = testFreqRadio();
      t.failWrites[MeshCoreCmd.sendTracePath] =
          TimeoutException('write timed out');
      final r = await connected(t);
      final out = await r.ping(0xB05E0001);
      expect(out.status, PingStatus.error);
      expect(out.errorReason, 'LINK_LOST');
      await r.dispose();
    });

    test('a trace in flight when the link drops ends as a link error',
        () async {
      final t = testFreqRadio();
      final r = await connected(t);
      final f = r.ping(0xB05E0001, timeout: const Duration(seconds: 10));
      await pump();
      t.dropLink();
      final out = await f.timeout(const Duration(seconds: 1));
      expect(out.status, PingStatus.error);
      expect(out.errorReason, 'LINK_LOST');
      await r.dispose();
    });

    test('dispose ends a trace in flight as a link error', () async {
      final t = testFreqRadio();
      final r = await connected(t);
      final f = r.ping(0xB05E0001, timeout: const Duration(seconds: 10));
      await pump();
      await r.dispose();
      final out = await f.timeout(const Duration(seconds: 1));
      expect(out.status, PingStatus.error);
      expect(out.errorReason, 'LINK_LOST');
    });

    test('a node without a key is refused before anything is sent', () async {
      final t = testFreqRadio();
      final r = await connected(t);
      final before = t.writes.length;
      var called = false;
      final out = await r.ping(0x12345678, beforeSend: (_) => called = true);
      expect(out.status, PingStatus.error);
      expect(out.errorReason, 'unknown node');
      expect(called, isFalse);
      expect(t.writes.length, before);
      await r.dispose();
    });
  });

  group('radio params (design §5, §6)', () {
    test('on a community preset: preset, region, settings, public', () async {
      final r = await connected(fakeRadio());
      // The ladder names the modulation; the community is the "region".
      expect(r.currentPreset, MeshCoreModulations.fast.radioPreset);
      expect(r.regionName, 'USA');
      expect(r.regionFrequencyMHz, closeTo(910.525, 1e-9));
      expect(
          r.radioSettings,
          const RadioSettings(
              region: 'USA', txPowerDbm: 22, frequencyMHz: 910.525));
      expect(r.onPublicChannel, isTrue);
      expect(r.primaryChannelName, '');
      await r.dispose();
    });

    test('off the community presets: custom and not public', () async {
      final t = fakeRadio()
        ..selfInfo = selfInfoFrame(key: ownKey, freqKHz: 918000);
      t.channels[1] = channelFrame(1, 'MeshTest', List.filled(16, 3));
      final r = await connected(t);
      expect(r.onPublicChannel, isFalse);
      // Off the community frequencies but still a known modulation.
      expect(r.currentPreset, MeshCoreModulations.fast.radioPreset);
      expect(r.regionName, '');
      expect(r.primaryChannelName, 'MeshTest');
      await r.dispose();
    });

    test('a float-truncated frequency snaps to its preset (MM:1105)', () async {
      final t = fakeRadio()
        ..selfInfo = selfInfoFrame(key: ownKey, freqKHz: 869617, sf: 8, cr: 8);
      final r = await connected(t);
      expect(r.regionName, 'EU/UK (Narrow)');
      expect(r.regionFrequencyMHz, 869.618);
      expect(r.radioSettings?.frequencyMHz, 869.618);
      await r.dispose();
    });

    test('public until the parameters are known', () {
      final r = radioOn(fakeRadio());
      expect(r.onPublicChannel, isTrue);
      expect(r.currentPreset, isNull);
      expect(r.radioSettings, isNull);
      expect(r.capabilities, same(RadioCapabilities.unknown));
    });
  });

  group('applyTestProfile (design §6)', () {
    final key32 = Uint8List.fromList(List.generate(32, (i) => 0x40 + i));
    const preset = RadioPreset(
        id: 'MC_TEST', displayName: 'Test', sf: 8, bwKHz: 62.5, cr: 5);

    TestProfile profile({required bool base, bool relays = true}) =>
        TestProfile(
          channelName: 'MeshTest',
          channelKey: key32,
          preset: preset,
          isBase: base,
          baseRelays: relays,
          beacon: base ? const BeaconConfig(intervalSec: 10) : null,
          radioLongName: base ? 'MeshTest Base' : 'MeshTest Mobile',
          frequencyMHz: 918.0,
          txPowerDbm: 20,
        );

    test(
        'base: name, channel in slot 1, power, params with repeat, read '
        'back', () async {
      final t = fakeRadio();
      final r = await connected(t);
      final from = t.writes.length;
      // The radio reports the new settings afterwards.
      t.after[MeshCoreCmd.setRadioParams] = (_) {
        t.deviceInfo = deviceInfoFrame(repeat: true);
        t.selfInfo = selfInfoFrame(
            key: ownKey, txPower: 20, freqKHz: 918000, sf: 8, cr: 5);
      };
      final steps = <String>[];
      final beacon =
          await r.applyTestProfile(profile(base: true), onStep: steps.add);
      final w = t.writes.sublist(from);
      expect([
        for (final c in w) c[0]
      ], [
        MeshCoreCmd.setAdvertName,
        MeshCoreCmd.setChannel,
        MeshCoreCmd.setRadioTxPower,
        MeshCoreCmd.setRadioParams,
        MeshCoreCmd.deviceQuery,
        MeshCoreCmd.appStart,
      ]);
      expect(utf8.decode(w[0].sublist(1)), 'MeshTest Base');
      // [32][idx][name 32][secret 16], exactly 50 bytes (MM:1767-1780).
      expect(w[1].length, 50);
      expect(w[1][1], 1, reason: 'never slot 0 (Public)');
      expect(utf8.decode(w[1].sublist(2, 10)), 'MeshTest');
      expect(w[1].sublist(34), key32.sublist(0, 16));
      expect(w[2], [12, 20]);
      // [11][freq kHz][bw Hz][sf][cr][repeat] (MM:1424-1459).
      expect(w[3], [11, ...le32(918000), ...le32(62500), 8, 5, 1]);
      expect(beacon?.kind, BeaconKind.trace);
      expect(beacon?.intervalSec, 10);
      expect(steps, isNotEmpty);
      expect(r.radioSettings?.frequencyMHz, 918.0);
      expect(r.radioSettings?.txPowerDbm, 20);
      expect(r.capabilities.canRelay, isTrue);
      expect(r.onPublicChannel, isFalse);
      expect(r.primaryChannelName, 'MeshTest');
      await r.dispose();
    });

    test('mobile: repeat off, returns no beacon, no reboot', () async {
      final t = fakeRadio();
      final r = await connected(t);
      final beacon = await r.applyTestProfile(profile(base: false));
      final params =
          t.writes.lastWhere((c) => c[0] == MeshCoreCmd.setRadioParams);
      expect(params.last, 0);
      expect(beacon, isNull);
      expect(t.writtenCodes, isNot(contains(MeshCoreCmd.reboot)));
      expect(r.isReady, isTrue);
      await r.dispose();
    });

    test('reuses an existing MeshTest slot, never slot 0', () async {
      final t = fakeRadio();
      t.channels[0] = channelFrame(0, 'MeshTest', List.filled(16, 1));
      t.channels[1] = channelFrame(1, 'Friends', List.filled(16, 2));
      t.channels[3] = channelFrame(3, 'MeshTest', List.filled(16, 3));
      final r = await connected(t);
      await r.applyTestProfile(profile(base: false));
      final set = t.writes.firstWhere((c) => c[0] == MeshCoreCmd.setChannel);
      expect(set[1], 3, reason: 'its own slot, not the empty slot 2');
      await r.dispose();
    });

    test('takes the first empty slot after 0', () async {
      final t = fakeRadio();
      t.channels[0] = channelFrame(0, 'MeshTest', List.filled(16, 1));
      t.channels[1] = channelFrame(1, 'Friends', List.filled(16, 2));
      final r = await connected(t);
      await r.applyTestProfile(profile(base: false));
      final set = t.writes.firstWhere((c) => c[0] == MeshCoreCmd.setChannel);
      expect(set[1], 2);
      await r.dispose();
    });

    test('a refused repeat names the allowed frequencies', () async {
      final t = fakeRadio();
      t.overrides[MeshCoreCmd.setRadioParams] =
          (_) => [err(MeshCoreErr.illegalArg)];
      t.overrides[MeshCoreCmd.getAllowedRepeatFreq] = (_) => [
            [
              26, // RESP_ALLOWED_REPEAT_FREQ (MM:2036-2044)
              ...le32(433000), ...le32(433000),
              ...le32(869495), ...le32(869495),
              ...le32(918000), ...le32(918000),
            ]
          ];
      final r = await connected(t);
      await expectLater(
          r.applyTestProfile(profile(base: true)),
          throwsA(isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(contains('433.000'), contains('869.495'),
                  contains('918.000')))));
      expect(t.writtenCodes, contains(MeshCoreCmd.getAllowedRepeatFreq));
      await r.dispose();
    });

    test('settingsAfter and setBeacon', () async {
      final r = await connected(fakeRadio());
      expect(r.settingsAfter(profile(base: true)),
          const RadioSettings(txPowerDbm: 20, frequencyMHz: 918.0));
      expect((await r.setBeacon(const BeaconConfig(intervalSec: 15))).kind,
          BeaconKind.trace);
      final off = await r.setBeacon(const BeaconConfig.off());
      expect(off.kind, BeaconKind.none);
      await r.dispose();
    });
  });

  group('channel stats from GET_STATS (design §5)', () {
    test('tx over the window, rx over the last minute', () {
      var now = DateTime(2026, 10, 29, 12);
      final r = radioOn(fakeRadio(), clock: () => now);
      final got = <RadioChannelStats>[];
      final sub = r.channelStats.listen(got.add);
      r.addStatsSample(100, 200);
      expect(r.lastChannelStats, isNull, reason: 'one sample is no rate');
      now = now.add(const Duration(seconds: 60));
      r.addStatsSample(103, 206);
      expect(r.lastChannelStats!.airUtilTxPercent, closeTo(5, 1e-9));
      expect(r.lastChannelStats!.channelUtilizationPercent, closeTo(10, 1e-9));
      now = now.add(const Duration(seconds: 60));
      r.addStatsSample(103, 209);
      expect(r.lastChannelStats!.airUtilTxPercent, closeTo(2.5, 1e-9));
      expect(r.lastChannelStats!.channelUtilizationPercent, closeTo(5, 1e-9));
      expect(r.lastChannelStats!.measuredAt, now);
      // Counters going backwards = the radio rebooted: start over.
      now = now.add(const Duration(seconds: 60));
      r.addStatsSample(1, 1);
      expect(r.lastChannelStats!.measuredAt, isNot(now));
      sub.cancel();
    });

    test('the window is at most an hour', () {
      var now = DateTime(2026, 10, 29, 12);
      final r = radioOn(fakeRadio(), clock: () => now);
      r.addStatsSample(0, 0);
      for (var m = 1; m <= 90; m++) {
        now = now.add(const Duration(minutes: 1));
        // 36 s per minute for the first half hour, then nothing.
        r.addStatsSample(m <= 30 ? m * 36 : 30 * 36, 0);
      }
      // The last hour (minutes 30-90) had no transmissions.
      expect(r.lastChannelStats!.airUtilTxPercent, closeTo(0, 1e-9));
    });
  });

  group('link', () {
    test('MSG_WAITING push drains the queue', () async {
      final t = fakeRadio();
      final r = await connected(t);
      final before = t.writes.length;
      t.push([MeshCorePush.msgWaiting]);
      await pump();
      expect(t.writtenCodes.sublist(before), [MeshCoreCmd.syncNextMessage]);
      await r.dispose();
    });

    test('a dropped link reconnects and redoes the handshake', () async {
      final t = fakeRadio();
      final r = await connected(t);
      final states = <RadioConnectionState>[];
      final sub = r.connectionState.listen(states.add);
      final before = t.writes.length;
      t.dropLink();
      await pump(150);
      expect(
          states,
          containsAllInOrder([
            RadioConnectionState.reconnecting,
            RadioConnectionState.configuring,
            RadioConnectionState.ready,
          ]));
      expect(t.writtenCodes.sublist(before).take(2),
          [MeshCoreCmd.deviceQuery, MeshCoreCmd.appStart]);
      expect(r.isReady, isTrue);
      await sub.cancel();
      await r.dispose();
    });

    test('disconnect stops everything', () async {
      final t = fakeRadio();
      final r = await connected(t);
      await r.disconnect();
      expect(r.state, RadioConnectionState.disconnected);
      t.dropLink();
      await pump(50);
      expect(r.state, RadioConnectionState.disconnected);
      await r.dispose();
    });
  });

  test('sha256 matches the FIPS 180-2 vectors', () {
    String hex(List<int> b) =>
        b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    expect(hex(sha256(utf8.encode('abc'))),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(hex(sha256(const [])),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(
        hex(sha256(utf8.encode(
            'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'))),
        '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
  });
}

// ─── Settings backup (Radio Setup undo) ────────────────────

void settingsBackupTests() {
  group('settings backup', () {
    test(
        'settings holds name, power, node params, repeat and every slot '
        'after the handshake', () async {
      final t = fakeRadio();
      final r = await connected(t);
      final s = r.settings!;
      expect(s.name, 'Mobile');
      expect(s.txPowerDbm, 22);
      expect(s.frequencyKHz, 910525);
      expect(s.bandwidthHz, 62500);
      expect(s.spreadingFactor, 7);
      expect(s.codingRate, 5);
      expect(s.clientRepeat, isFalse);
      expect(s.manufacturer, 'Seeed Wio Tracker L1');
      expect(s.firmwareVersion, 'v1.18.0');
      expect(s.channels.map((c) => c.index), [0, 1, 2, 3]);
      expect(s.usedChannels.single.name, 'Public');
      expect(s.modulation, MeshCoreModulations.fast);
      expect(s.community?.title, 'USA');
      expect(s.paramsLabel, 'SF7 / 62.5 kHz / 4/5');
      await r.dispose();
    });

    test(
        'applySettings after a setup writes the old name, every slot, power '
        'and params with the old repeat flag, then re-reads', () async {
      final t = fakeRadio();
      final r = await connected(t);
      final before = r.settings!;
      // The fake reads back as set up once SET_RADIO_PARAMS was written.
      t.after[MeshCoreCmd.setRadioParams] = (cmd) {
        t.selfInfo = selfInfoFrame(
            key: ownKey,
            freqKHz: u32At(cmd, 1),
            name: 'MeshTest Base',
            txPower: 20);
        t.deviceInfo = deviceInfoFrame(repeat: cmd[11] == 1);
      };
      await r.applyTestProfile(TestProfile(
        channelName: 'MeshTest',
        channelKey: Uint8List.fromList(List.filled(32, 0x42)),
        preset: MeshCoreModulations.fast.radioPreset,
        isBase: true,
        radioLongName: 'MeshTest Base',
        frequencyMHz: 918.0,
        txPowerDbm: 20,
      ));
      final setUp = r.settings!;
      expect(setUp.name, 'MeshTest Base');
      expect(setUp.frequencyKHz, 918000);
      expect(setUp.clientRepeat, isTrue);
      expect(setUp.usedChannels.map((c) => c.name), ['Public', 'MeshTest']);
      expect(setUp.sameAs(before), isFalse);

      // Restore: the fake goes back to its original state on the params.
      t.after[MeshCoreCmd.setRadioParams] = (cmd) {
        t.selfInfo = selfInfoFrame(key: ownKey);
        t.deviceInfo = deviceInfoFrame();
      };
      t.writes.clear();
      final steps = <String>[];
      await r.applySettings(before, onStep: steps.add);
      expect(t.writtenCodes, [
        MeshCoreCmd.setAdvertName,
        MeshCoreCmd.setChannel, // slots 0-3, the test slot cleared
        MeshCoreCmd.setChannel,
        MeshCoreCmd.setChannel,
        MeshCoreCmd.setChannel,
        MeshCoreCmd.setRadioTxPower,
        MeshCoreCmd.setRadioParams,
        MeshCoreCmd.deviceQuery,
        MeshCoreCmd.appStart,
      ]);
      expect(utf8.decode(t.writes[0].sublist(1)), 'Mobile');
      // Slot 0 keeps Public; slot 1 (where MeshTest went) is written empty.
      expect(t.writes[1][1], 0);
      expect(utf8.decode(t.writes[1].sublist(2, 8)), 'Public');
      expect(t.writes[2][1], 1);
      expect(t.writes[2].sublist(2), List.filled(32 + 16, 0));
      expect(t.writes[5], [MeshCoreCmd.setRadioTxPower, 22]);
      expect(t.writes[6], [
        MeshCoreCmd.setRadioParams,
        ...le32(910525),
        ...le32(62500),
        7,
        5,
        0
      ]);
      expect(steps.first, 'Restoring name "Mobile"');
      expect(steps, contains('Restoring channels (Public)'));
      expect(steps, contains('Restoring 910.525 MHz, Fast'));
      expect(r.settings!.sameAs(before), isTrue);
      expect(r.onPublicChannel, isTrue);
      expect(r.primaryChannelName, '');
      await r.dispose();
    });

    test('applySettings skips the name when it already matches', () async {
      final t = fakeRadio();
      final r = await connected(t);
      t.writes.clear();
      await r.applySettings(r.settings!);
      expect(t.writtenCodes.first, MeshCoreCmd.setChannel);
      expect(t.writtenCodes, isNot(contains(MeshCoreCmd.setAdvertName)));
      await r.dispose();
    });

    test('applySettings reports a refused command', () async {
      final t = fakeRadio();
      final r = await connected(t);
      t.overrides[MeshCoreCmd.setRadioTxPower] =
          (_) => [err(MeshCoreErr.illegalArg)];
      await expectLater(
          r.applySettings(r.settings!),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('tx power'))));
      await r.dispose();
    });
  });
}
