// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

// Byte fixtures are hand-assembled from the firmware serialisation code in
// meshcore-dev/MeshCore examples/companion_radio/MyMesh.cpp at
// 81dbae592ffad40b4212bc0b37e82b38da08f4bc (line numbers in each group).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_frames.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_protocol.dart';

Uint8List b(List<int> bytes) => Uint8List.fromList(bytes);

List<int> le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];

List<int> le32(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

List<int> ascii(String s) => utf8.encode(s);

/// [s] NUL-padded to [width].
List<int> fixed(String s, int width) {
  final out = List<int>.filled(width, 0);
  final e = utf8.encode(s);
  out.setRange(0, e.length, e);
  return out;
}

final key = b(List.generate(32, (i) => 0xA0 + i)); // a0 a1 ... bf
final key2 = b(List.generate(32, (i) => 0x10 + i));

T parseAs<T extends MeshCoreFrame>(List<int> bytes) {
  final f = MeshCoreFrame.parse(b(bytes));
  expect(f, isA<T>(), reason: 'got $f');
  return f as T;
}

void main() {
  group('command builders (byte-exact against firmware parsing)', () {
    test('APP_START: [1][ver][6 reserved][name] (MyMesh.cpp:1076-1081)', () {
      expect(
          MeshCoreCommands.appStart(appName: 'MA'),
          b([
            0x01, // CMD_APP_START
            0x01, // app version (ignored by firmware)
            0, 0, 0, 0, 0, 0, // reserved, bytes 2-7
            ...ascii('MA'), // name from byte 8, no terminator
          ]));
      // Firmware needs len >= 8 even with no name.
      expect(MeshCoreCommands.appStart(appName: '').length, 8);
    });

    test('DEVICE_QUERY asks for protocol v3 (SNR in messages)', () {
      expect(MeshCoreCommands.deviceQuery(), b([22, 3]));
      expect(MeshCoreCommands.deviceQuery(protocolVersion: 1), b([22, 1]));
    });

    test('GET_CONTACTS with and without since (MyMesh.cpp:1238-1245)', () {
      expect(MeshCoreCommands.getContacts(), b([4]));
      expect(MeshCoreCommands.getContacts(since: 0x01020304),
          b([4, 0x04, 0x03, 0x02, 0x01]));
    });

    test('SEND_TXT_MSG layout (MyMesh.cpp:1132-1144)', () {
      expect(
          MeshCoreCommands.sendTextMessage(
              publicKeyPrefix: key, // longer than 6: only 6 used
              text: 'hi',
              timestamp: 0x65000001,
              attempt: 2),
          b([
            0x02, // CMD_SEND_TXT_MSG
            0x00, // TXT_TYPE_PLAIN
            0x02, // attempt
            ...le32(0x65000001), // msg_timestamp
            0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, // pub_key prefix x6
            ...ascii('hi'),
          ]));
      expect(
          () => MeshCoreCommands.sendTextMessage(
              publicKeyPrefix: b([1, 2, 3]), text: 'x', timestamp: 0),
          throwsArgumentError);
    });

    test('SEND_CHANNEL_TXT_MSG layout (MyMesh.cpp:1178-1186)', () {
      expect(
          MeshCoreCommands.sendChannelTextMessage(
              channelIndex: 1, text: 'ping', timestamp: 1000),
          b([
            0x03, // CMD_SEND_CHANNEL_TXT_MSG
            0x00, // txt_type plain
            0x01, // channel_idx
            ...le32(1000),
            ...ascii('ping'),
          ]));
    });

    test('SEND_CHANNEL_DATA flood and with a path (MyMesh.cpp:1198-1218)', () {
      expect(
          MeshCoreCommands.sendChannelData(
              channelIndex: 2, dataType: 0xFFFF, payload: b([9, 8])),
          b([62, 2, 0xFF, 0xFF, 0xFF, 9, 8]));
      // 2 hops of 2-byte hashes: path_len = (2-1)<<6 | 2 = 0x42, 4 bytes.
      expect(
          MeshCoreCommands.sendChannelData(
              channelIndex: 0,
              dataType: 0x1234,
              payload: b([7]),
              pathLen: MeshCorePathLen.encode(hops: 2, hashSize: 2),
              path: b([1, 2, 3, 4])),
          b([62, 0, 0x42, 1, 2, 3, 4, 0x34, 0x12, 7]));
      expect(
          () => MeshCoreCommands.sendChannelData(
              channelIndex: 0,
              dataType: 1,
              payload: b([]),
              pathLen: 0x02,
              path: b([1])),
          throwsArgumentError);
    });

    test('SEND_RAW_DATA: direct only, payload >= 4 (MyMesh.cpp:1557-1563)', () {
      expect(
          MeshCoreCommands.sendRawData(
              pathLen: 1, path: b([0xAB]), payload: b([1, 2, 3, 4])),
          b([25, 0x01, 0xAB, 1, 2, 3, 4]));
      expect(
          MeshCoreCommands.sendRawData(
              pathLen: 0, path: b([]), payload: b([1, 2, 3, 4])),
          b([25, 0x00, 1, 2, 3, 4]));
      expect(
          () => MeshCoreCommands.sendRawData(
              pathLen: 0xFF, path: b([]), payload: b([1, 2, 3, 4])),
          throwsArgumentError);
      expect(
          () => MeshCoreCommands.sendRawData(
              pathLen: 0, path: b([]), payload: b([1, 2, 3])),
          throwsArgumentError);
    });

    test(
        'SEND_TRACE_PATH: [36][tag][auth][flags][hashes] (MyMesh.cpp:1813-1824)',
        () {
      expect(
          MeshCoreCommands.sendTracePath(
              tag: 0xDEADBEEF, authCode: 7, path: b([0x11, 0x22, 0x11])),
          b([
            36,
            ...le32(0xDEADBEEF), // tag
            ...le32(7), // auth
            0x00, // flags: 1-byte hashes
            0x11, 0x22, 0x11, // out and back
          ]));
      // flags 1 = 2-byte hashes: path must be a multiple of 2.
      expect(
          () => MeshCoreCommands.sendTracePath(
              tag: 1, flags: 1, path: b([1, 2, 3])),
          throwsArgumentError);
      expect(() => MeshCoreCommands.sendTracePath(tag: 1, path: b([])),
          throwsArgumentError);
    });

    test('key commands, advert, sync', () {
      expect(MeshCoreCommands.sendStatusRequest(key), b([27, ...key]));
      expect(MeshCoreCommands.getContactByKey(key), b([30, ...key]));
      expect(MeshCoreCommands.removeContact(key), b([15, ...key]));
      expect(MeshCoreCommands.resetPath(key), b([13, ...key]));
      expect(() => MeshCoreCommands.sendStatusRequest(b([1])),
          throwsArgumentError);
      expect(MeshCoreCommands.sendSelfAdvert(), b([7, 0]));
      expect(MeshCoreCommands.sendSelfAdvert(flood: true), b([7, 1]));
      expect(MeshCoreCommands.syncNextMessage(), b([10]));
      expect(MeshCoreCommands.getDeviceTime(), b([5]));
      expect(MeshCoreCommands.setDeviceTime(0x65432100),
          b([6, ...le32(0x65432100)]));
      expect(MeshCoreCommands.getBattAndStorage(), b([20]));
      expect(MeshCoreCommands.getStats(MeshCoreStatsType.radio), b([56, 1]));
    });

    test('SET_RADIO_PARAMS: freq in kHz, bw in Hz (MyMesh.cpp:1424-1436)', () {
      expect(
          MeshCoreCommands.setRadioParams(
              frequencyMHz: 910.525,
              bandwidthKHz: 62.5,
              spreadingFactor: 7,
              codingRate: 5),
          b([
            11,
            ...le32(910525), // freq: firmware divides by 1000 -> MHz
            ...le32(62500), // bw: firmware divides by 1000 -> kHz
            7, // sf
            5, // cr
          ]));
      expect(
          MeshCoreCommands.setRadioParams(
                  frequencyMHz: 869.618,
                  bandwidthKHz: 250,
                  spreadingFactor: 11,
                  codingRate: 5,
                  clientRepeat: false)
              .length,
          12);
    });

    test('SET_RADIO_TX_POWER is int8 (MyMesh.cpp:1460-1461)', () {
      expect(MeshCoreCommands.setTxPower(22), b([12, 22]));
      expect(MeshCoreCommands.setTxPower(-9), b([12, 0xF7]));
    });

    test('GET/SET_CHANNEL (MyMesh.cpp:1752, 1769-1774)', () {
      expect(MeshCoreCommands.getChannel(3), b([31, 3]));
      final secret = b(List.generate(16, (i) => i));
      final f = MeshCoreCommands.setChannel(1, 'MeshTest', secret);
      expect(f, b([32, 1, ...fixed('MeshTest', 32), ...secret]));
      expect(f.length, 2 + 32 + 16);
      expect(() => MeshCoreCommands.setChannel(1, 'x', b(List.filled(32, 1))),
          throwsArgumentError);
      // A 40-byte name is cut to 31 bytes + NUL.
      final long = MeshCoreCommands.setChannel(0, 'x' * 40, secret);
      expect(long[2 + 31], 0);
      expect(long[2 + 30], 0x78);
    });

    test('SET_ADVERT_NAME / LATLON', () {
      expect(MeshCoreCommands.setAdvertName('Base'), b([8, ...ascii('Base')]));
      // 'é' is 2 bytes; never split a character at the 31-byte limit.
      final n = MeshCoreCommands.setAdvertName('${'a' * 30}é');
      expect(n.length, 1 + 30);
      expect(MeshCoreCommands.setAdvertLatLon(33.68, -116.24),
          b([14, ...le32(33680000), ...le32(-116240000)]));
    });

    test('ADD_UPDATE_CONTACT round-trips through the contact record', () {
      final c = MeshCoreContact(
        publicKey: key,
        type: MeshCoreAdvType.repeater,
        flags: MeshCoreContactFlags.favourite,
        outPathLen: MeshCorePathLen.encode(hops: 2),
        outPath: b([0x5A, 0x6B]),
        name: 'Base',
        lastAdvertTimestamp: 1700000000,
        latE6: -33868820,
        lonE6: 151209290,
        lastModified: 1700000100,
      );
      final cmd = MeshCoreCommands.addUpdateContact(c);
      expect(cmd.length, 148);
      expect(cmd[0], MeshCoreCmd.addUpdateContact);
      expect(cmd.sublist(1, 33), key);
      expect(cmd[35], 0x02); // out_path_len
      expect(cmd.sublist(36, 38), [0x5A, 0x6B]);
      expect(cmd.sublist(38, 100), everyElement(0)); // path pad to 64
      // Same layout as RESP_CODE_CONTACT (updateContactFromFrame mirrors
      // writeContactRespFrame), so parse it back as one.
      final asResp = Uint8List.fromList(cmd)..[0] = MeshCoreResp.contact;
      final parsed = parseAs<MeshCoreContactFrame>(asResp);
      expect(parsed.contact, c);
    });

    test('SET_CHANNEL round-trips through CHANNEL_INFO (same layout)', () {
      final secret = b(List.generate(16, (i) => 0xF0 - i));
      final cmd = MeshCoreCommands.setChannel(5, 'MeshTest', secret);
      final info = parseAs<MeshCoreChannelInfo>(
          Uint8List.fromList(cmd)..[0] = MeshCoreResp.channelInfo);
      expect(info.index, 5);
      expect(info.name, 'MeshTest');
      expect(info.secret, secret);
    });
  });

  group('response parsers', () {
    test('OK / ERR / DISABLED', () {
      parseAs<MeshCoreOk>([0]);
      expect(parseAs<MeshCoreError>([1, 2]).errorCode, MeshCoreErr.notFound);
      expect(parseAs<MeshCoreError>([1]).errorCode, isNull);
      parseAs<MeshCoreDisabled>([15]);
    });

    test('CONTACTS_START / END_OF_CONTACTS (MyMesh.cpp:1249, 2404)', () {
      expect(parseAs<MeshCoreContactsStart>([2, ...le32(42)]).count, 42);
      expect(
          parseAs<MeshCoreEndOfContacts>([4, ...le32(1700000123)])
              .mostRecentLastModified,
          1700000123);
    });

    // writeContactRespFrame, MyMesh.cpp:171-192.
    List<int> contactRecord(int code,
            {int pathLen = 0x01, List<int> path = const [0x77]}) =>
        [
          code,
          ...key, // pub_key x32
          MeshCoreAdvType.chat, // type
          0x03, // flags: favourite + telemetry base
          pathLen, // out_path_len
          ...path, ...List.filled(64 - path.length, 0), // out_path x64
          ...fixed('Mobile ✓', 32), // name x32 (strzcpy)
          ...le32(1700000000), // last_advert_timestamp
          ...le32(-33868820), // gps_lat
          ...le32(151209290), // gps_lon
          ...le32(1700000500), // lastmod
        ];

    test('CONTACT record', () {
      final f = parseAs<MeshCoreContactFrame>(contactRecord(3));
      final c = f.contact;
      expect(f.isNewAdvert, isFalse);
      expect(c.publicKey, key);
      expect(c.type, MeshCoreAdvType.chat);
      expect(c.flags, 3);
      expect(c.outPathLen, 1);
      expect(c.outPath, [0x77]);
      expect(c.hops, 1);
      expect(c.name, 'Mobile ✓');
      expect(c.lastAdvertTimestamp, 1700000000);
      expect(c.latitude, closeTo(-33.86882, 1e-9));
      expect(c.longitude, closeTo(151.20929, 1e-9));
      expect(c.hasPosition, isTrue);
      expect(c.lastModified, 1700000500);
    });

    test('CONTACT with no path (0xFF) and PUSH_CODE_NEW_ADVERT', () {
      final f = parseAs<MeshCoreContactFrame>(
          contactRecord(0x8A, pathLen: 0xFF, path: const []));
      expect(f.isNewAdvert, isTrue);
      expect(f.contact.hasPath, isFalse);
      expect(f.contact.hops, isNull);
      expect(f.contact.outPath, isEmpty);
    });

    test('CONTACT with 2-byte path hashes keeps 2 x hops bytes', () {
      final f = parseAs<MeshCoreContactFrame>(
          contactRecord(3, pathLen: 0x43, path: const [1, 2, 3, 4, 5, 6]));
      expect(f.contact.hops, 3);
      expect(f.contact.outPath, [1, 2, 3, 4, 5, 6]);
    });

    // MyMesh.cpp:1084-1116.
    List<int> selfInfo({String name = 'MeshTest Mobile'}) => [
          5, // RESP_CODE_SELF_INFO
          1, // ADV_TYPE_CHAT
          22, // tx_power_dbm
          30, // MAX_LORA_TX_POWER
          ...key, // pub_key x32
          ...le32(33680000), // lat * 1e6
          ...le32(-116240000), // lon * 1e6
          0, // multi_acks
          1, // advert_loc_policy
          0x15, // telemetry modes env<<4 | loc<<2 | base
          0, // manual_add_contacts
          ...le32(910525), // freq * 1000 (kHz)
          ...le32(62500), // bw * 1000 (Hz)
          7, // sf
          5, // cr
          ...ascii(name), // node_name, to end of frame
        ];

    test('SELF_INFO full frame', () {
      final i = parseAs<MeshCoreSelfInfoFrame>(selfInfo()).info;
      expect(i.advType, 1);
      expect(i.txPowerDbm, 22);
      expect(i.maxTxPowerDbm, 30);
      expect(i.publicKey, key);
      expect(i.latitude, closeTo(33.68, 1e-9));
      expect(i.longitude, closeTo(-116.24, 1e-9));
      expect(i.multiAcks, 0);
      expect(i.advertLocationPolicy, 1);
      expect(i.telemetryModes, 0x15);
      expect(i.manualAddContacts, 0);
      expect(i.frequencyKHz, 910525);
      expect(i.frequencyMHz, closeTo(910.525, 1e-9));
      expect(i.bandwidthHz, 62500);
      expect(i.bandwidthKHz, 62.5);
      expect(i.spreadingFactor, 7);
      expect(i.codingRate, 5);
      expect(i.name, 'MeshTest Mobile');
    });

    test('SELF_INFO negative tx power and empty name', () {
      final bytes = selfInfo(name: '')..[2] = 0xF7; // -9 dBm
      final i = parseAs<MeshCoreSelfInfoFrame>(bytes).info;
      expect(i.txPowerDbm, -9);
      expect(i.name, '');
      expect(i.hasRadioParams, isTrue);
    });

    test('SELF_INFO from old firmware stopping after the key', () {
      final i = parseAs<MeshCoreSelfInfoFrame>(selfInfo().sublist(0, 36)).info;
      expect(i.publicKey, key);
      expect(i.latE6, isNull);
      expect(i.hasRadioParams, isFalse);
    });

    test('SET_RADIO_PARAMS values read back the same in SELF_INFO', () {
      final cmd = MeshCoreCommands.setRadioParams(
          frequencyMHz: 910.525,
          bandwidthKHz: 62.5,
          spreadingFactor: 7,
          codingRate: 5);
      // freq/bw/sf/cr occupy cmd[1..10] and SELF_INFO[48..57].
      expect(b(selfInfo()).sublist(48, 58), cmd.sublist(1, 11));
    });

    // MyMesh.cpp:1059-1074.
    List<int> deviceInfo() => [
          13, // RESP_CODE_DEVICE_INFO
          14, // FIRMWARE_VER_CODE
          50, // MAX_CONTACTS / 2
          8, // MAX_GROUP_CHANNELS
          ...le32(123456), // ble_pin
          ...fixed('15 Oct 2026', 12), // FIRMWARE_BUILD_DATE x12
          ...fixed('Heltec V3', 40), // manufacturer x40
          ...fixed('v1.18.0', 20), // FIRMWARE_VERSION x20
          0, // client repeat (v9+)
          1, // path_hash_mode (v10+)
        ];

    test('DEVICE_INFO full frame (82 bytes)', () {
      expect(deviceInfo().length, 82);
      final i = parseAs<MeshCoreDeviceInfoFrame>(deviceInfo()).info;
      expect(i.firmwareVerCode, 14);
      expect(i.maxContacts, 100);
      expect(i.maxChannels, 8);
      expect(i.blePin, 123456);
      expect(i.buildDate, '15 Oct 2026');
      expect(i.manufacturer, 'Heltec V3');
      expect(i.firmwareVersion, 'v1.18.0');
      expect(i.clientRepeat, isFalse);
      expect(i.pathHashMode, 1);
    });

    test('DEVICE_INFO from older firmware: missing tail is null', () {
      final i =
          parseAs<MeshCoreDeviceInfoFrame>(deviceInfo().sublist(0, 80)).info;
      expect(i.firmwareVersion, 'v1.18.0');
      expect(i.clientRepeat, isNull);
      expect(i.pathHashMode, isNull);
      final tiny = parseAs<MeshCoreDeviceInfoFrame>([13, 2]).info;
      expect(tiny.firmwareVerCode, 2);
      expect(tiny.maxContacts, isNull);
    });

    test('SENT (MyMesh.cpp:1167-1171)', () {
      final s =
          parseAs<MeshCoreSent>([6, 1, ...le32(0xCAFEF00D), ...le32(5400)]);
      expect(s.isFlood, isTrue);
      expect(s.expectedAck, 0xCAFEF00D);
      expect(s.estimatedTimeoutMs, 5400);
    });

    test('CONTACT_MSG_RECV_V3 plain (MyMesh.cpp:443-466)', () {
      final m = parseAs<MeshCoreContactMessage>([
        16, // RESP_CODE_CONTACT_MSG_RECV_V3
        0xEB, // snr * 4 = -21 -> -5.25 dB
        0, 0, // reserved
        0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, // sender prefix x6
        2, // path_len: flooded over 2 hops
        0, // TXT_TYPE_PLAIN
        ...le32(1700000000), // sender_timestamp
        ...ascii('pong'),
      ]);
      expect(m.snr, -5.25);
      expect(m.senderKeyPrefix, key.sublist(0, 6));
      expect(m.hops, 2);
      expect(m.isDirect, isFalse);
      expect(m.txtType, MeshCoreTxtType.plain);
      expect(m.senderTimestamp, 1700000000);
      expect(m.signerKeyPrefix, isNull);
      expect(m.text, 'pong');
    });

    test('CONTACT_MSG_RECV_V3 signed carries a 4-byte prefix before text', () {
      final m = parseAs<MeshCoreContactMessage>([
        16, 0x28, 0, 0, // snr 10.0
        1, 2, 3, 4, 5, 6,
        0xFF, // direct
        2, // TXT_TYPE_SIGNED_PLAIN
        ...le32(5),
        9, 9, 9, 9, // signer prefix (extra, 4 bytes)
        ...ascii('signed'),
      ]);
      expect(m.snr, 10.0);
      expect(m.isDirect, isTrue);
      expect(m.hops, isNull);
      expect(m.signerKeyPrefix, [9, 9, 9, 9]);
      expect(m.text, 'signed');
    });

    test('legacy CONTACT_MSG_RECV (code 7) has no SNR', () {
      final m = parseAs<MeshCoreContactMessage>([
        7,
        1,
        2,
        3,
        4,
        5,
        6,
        0,
        0,
        ...le32(77),
        ...ascii('old'),
      ]);
      expect(m.snr, isNull);
      expect(m.hops, 0);
      expect(m.text, 'old');
    });

    test('CHANNEL_MSG_RECV_V3 and legacy (MyMesh.cpp:561-577)', () {
      final m = parseAs<MeshCoreChannelMessage>([
        17, // RESP_CODE_CHANNEL_MSG_RECV_V3
        0xFE, // snr -0.5
        0, 0,
        1, // channel_idx
        3, // path_len
        0, // TXT_TYPE_PLAIN
        ...le32(1700000001),
        ...ascii('Base: seq 4'),
      ]);
      expect(m.snr, -0.5);
      expect(m.channelIndex, 1);
      expect(m.hops, 3);
      expect(m.text, 'Base: seq 4');
      final l = parseAs<MeshCoreChannelMessage>(
          [8, 0, 0xFF, 0, ...le32(1), ...ascii('x')]);
      expect(l.snr, isNull);
      expect(l.isDirect, isTrue);
      expect(l.text, 'x');
    });

    test('CHANNEL_DATA_RECV (MyMesh.cpp:609-624)', () {
      final d = parseAs<MeshCoreChannelData>([
        27, // RESP_CODE_CHANNEL_DATA_RECV
        0x14, // snr 5.0
        0, 0,
        2, // channel_idx
        0, // path_len (zero hop)
        ...le16(0xFFFF), // data_type
        3, // data_len
        0xAA, 0xBB, 0xCC,
      ]);
      expect(d.snr, 5.0);
      expect(d.channelIndex, 2);
      expect(d.pathLen, 0);
      expect(d.dataType, 0xFFFF);
      expect(d.data, [0xAA, 0xBB, 0xCC]);
    });

    test('NO_MORE_MESSAGES, CURR_TIME, BATT_AND_STORAGE', () {
      parseAs<MeshCoreNoMoreMessages>([10]);
      expect(parseAs<MeshCoreCurrentTime>([9, ...le32(1700000000)]).unixSeconds,
          1700000000);
      final bs = parseAs<MeshCoreBattAndStorage>(
          [12, ...le16(4012), ...le32(100), ...le32(2048)]);
      expect(bs.battMilliVolts, 4012);
      expect(bs.storageUsedKb, 100);
      expect(bs.storageTotalKb, 2048);
      final old = parseAs<MeshCoreBattAndStorage>([12, ...le16(3900)]);
      expect(old.storageUsedKb, isNull);
    });

    test('CHANNEL_INFO ignores bytes after the strcpy NUL', () {
      final nameField = fixed('Public', 32)..[20] = 0x55; // stale byte
      final c = parseAs<MeshCoreChannelInfo>([
        18,
        0,
        ...nameField,
        ...List.generate(16, (i) => i + 1),
      ]);
      expect(c.name, 'Public');
      expect(c.secret, List.generate(16, (i) => i + 1));
      expect(c.isEmpty, isFalse);
      final empty = parseAs<MeshCoreChannelInfo>(
          [18, 7, ...List.filled(32, 0), ...List.filled(16, 0)]);
      expect(empty.isEmpty, isTrue);
    });

    test('STATS radio / core / packets (MyMesh.cpp:1916-1962)', () {
      final r = parseAs<MeshCoreRadioStats>([
        24, 1,
        ...le16(-112 & 0xFFFF), // noise_floor i16
        0xA6, // last_rssi -90
        0xE2, // last_snr*4 = -30 -> -7.5
        ...le32(360), // tx air secs
        ...le32(7200), // rx air secs
      ]);
      expect(r.noiseFloor, -112);
      expect(r.lastRssi, -90);
      expect(r.lastSnr, -7.5);
      expect(r.txAirSecs, 360);
      expect(r.rxAirSecs, 7200);
      final c = parseAs<MeshCoreCoreStats>(
          [24, 0, ...le16(4100), ...le32(86400), ...le16(0), 2]);
      expect(c.uptimeSecs, 86400);
      expect(c.txQueueLen, 2);
      final p = parseAs<MeshCorePacketStats>(
          [24, 2, for (var i = 1; i <= 7; i++) ...le32(i * 10)]);
      expect(p.recv, 10);
      expect(p.recvErrors, 70);
      parseAs<MeshCoreUnknownFrame>([24, 9]);
    });
  });

  group('push parsers', () {
    test('ADVERT / PATH_UPDATED / CONTACT_DELETED: [code][key x32]', () {
      expect(parseAs<MeshCoreKeyPush>([0x80, ...key]).isAdvert, isTrue);
      final p = parseAs<MeshCoreKeyPush>([0x81, ...key2]);
      expect(p.isPathUpdated, isTrue);
      expect(p.publicKey, key2);
      expect(parseAs<MeshCoreKeyPush>([0x8F, ...key]).isContactDeleted, isTrue);
    });

    test('SEND_CONFIRMED (MyMesh.cpp:426-430)', () {
      final c = parseAs<MeshCoreSendConfirmed>(
          [0x82, ...le32(0xCAFEF00D), ...le32(1834)]);
      expect(c.ackCode, 0xCAFEF00D);
      expect(c.roundTripMs, 1834);
      expect(c.isPush, isTrue);
    });

    test('MSG_WAITING, CONTACTS_FULL', () {
      parseAs<MeshCoreMsgWaiting>([0x83]);
      parseAs<MeshCoreContactsFull>([0x90]);
    });

    test('LOG_RX_DATA with a flood advert (MyMesh.cpp:291-302)', () {
      final rx = parseAs<MeshCoreRxLog>([
        0x88, // PUSH_CODE_LOG_RX_DATA
        0x1A, // snr*4 = 26 -> 6.5 dB
        0x9F, // rssi -97
        // raw packet (Packet::writeTo):
        0x11, // header: payload ADVERT(4)<<2 | ROUTE_TYPE_FLOOD(1)
        0x02, // path_len: 2 hops, 1-byte hashes
        0xAA, 0xBB, // path
        ...key, // payload starts with the advertiser's key
      ]);
      expect(rx.snr, 6.5);
      expect(rx.rssi, -97);
      expect(rx.raw.length, 2 + 2 + 32);
      final p = rx.packet!;
      expect(p.routeType, MeshCoreRouteType.flood);
      expect(p.payloadType, MeshCorePayloadType.advert);
      expect(p.isFlood, isTrue);
      expect(p.hops, 2);
      expect(p.path, [0xAA, 0xBB]);
      expect(p.payload, key);
      expect(p.transportCodes, isNull);
    });

    test('LOG_RX_DATA with transport codes and a garbage packet', () {
      final rx = parseAs<MeshCoreRxLog>([
        0x88, 0x00, 0x80, // snr 0, rssi -128
        0x08, // header: TXT_MSG(2)<<2 | ROUTE_TYPE_TRANSPORT_FLOOD(0)
        ...le16(0x1234), ...le16(0), // transport codes
        0x00, // path_len 0
        0x99, // payload
      ]);
      expect(rx.rssi, -128);
      final p = rx.packet!;
      expect(p.payloadType, MeshCorePayloadType.txtMsg);
      expect(p.transportCodes, [0x1234, 0]);
      expect(p.payload, [0x99]);
      // Reserved hash size 4 (0xC1) is invalid; empty payload is invalid.
      expect(parseAs<MeshCoreRxLog>([0x88, 0, 0, 0x11, 0xC1, 1, 2]).packet,
          isNull);
      expect(parseAs<MeshCoreRxLog>([0x88, 0, 0, 0x11, 0x00]).packet, isNull);
      expect(parseAs<MeshCoreRxLog>([0x88, 0, 0]).packet, isNull);
    });

    test('RAW_DATA and CONTROL_DATA (MyMesh.cpp:810-853)', () {
      final r = parseAs<MeshCoreDataPush>([0x84, 0x08, 0xB0, 0xFF, 1, 2, 3, 4]);
      expect(r.snr, 2.0);
      expect(r.rssi, -80);
      expect(r.pathLen, 0xFF);
      expect(r.payload, [1, 2, 3, 4]);
      expect(r.isControl, isFalse);
      expect(
          parseAs<MeshCoreDataPush>([0x8E, 0, 0, 0, 0x90]).isControl, isTrue);
    });

    test('TRACE_DATA, 1-byte hashes (MyMesh.cpp:855-879)', () {
      final t = parseAs<MeshCoreTraceData>([
        0x89, // PUSH_CODE_TRACE_DATA
        0, // reserved
        3, // path_len (hash bytes)
        0, // flags: path_sz 0 -> 1-byte hashes
        ...le32(0xDEADBEEF), // tag
        ...le32(7), // auth_code
        0x11, 0x22, 0x11, // path hashes
        0x28, 0xF0, 0x0C, // per-hop snr*4: 10.0, -4.0, 3.0
        0xEC, // final snr*4: -5.0
      ]);
      expect(t.tag, 0xDEADBEEF);
      expect(t.authCode, 7);
      expect(t.hashSize, 1);
      expect(t.pathHashes, [0x11, 0x22, 0x11]);
      expect(t.hopSnrs, [10.0, -4.0, 3.0]);
      expect(t.hopCount, 3);
      expect(t.finalSnr, -5.0);
    });

    test('TRACE_DATA, 2-byte hashes: path_len >> 1 SNRs', () {
      final t = parseAs<MeshCoreTraceData>([
        0x89, 0,
        4, // 4 hash bytes
        1, // flags: 2-byte hashes
        ...le32(1), ...le32(0),
        0x11, 0x11, 0x22, 0x22,
        0x04, 0x08, // 2 hop SNRs
        0x0C, // final
      ]);
      expect(t.hashSize, 2);
      expect(t.hopSnrs, [1.0, 2.0]);
      expect(t.finalSnr, 3.0);
    });

    test('STATUS_RESPONSE with RepeaterStats (MyMesh.cpp:732-737)', () {
      final stats = ByteData(56)
        ..setUint16(0, 4150, Endian.little) // batt_milli_volts
        ..setUint16(2, 1, Endian.little) // curr_tx_queue_len
        ..setInt16(4, -115, Endian.little) // noise_floor
        ..setInt16(6, -88, Endian.little) // last_rssi
        ..setUint32(8, 1000, Endian.little) // n_packets_recv
        ..setUint32(12, 500, Endian.little) // n_packets_sent
        ..setUint32(16, 321, Endian.little) // total_air_time_secs
        ..setUint32(20, 99999, Endian.little) // total_up_time_secs
        ..setUint32(24, 10, Endian.little) // n_sent_flood
        ..setUint32(28, 20, Endian.little) // n_sent_direct
        ..setUint32(32, 30, Endian.little) // n_recv_flood
        ..setUint32(36, 40, Endian.little) // n_recv_direct
        ..setUint16(40, 3, Endian.little) // err_events
        ..setInt16(42, -26, Endian.little) // last_snr x4 -> -6.5
        ..setUint16(44, 5, Endian.little) // n_direct_dups
        ..setUint16(46, 6, Endian.little) // n_flood_dups
        ..setUint32(48, 777, Endian.little) // total_rx_air_time_secs
        ..setUint32(52, 8, Endian.little); // n_recv_errors
      final r = parseAs<MeshCoreNodeResponse>([
        0x87, // PUSH_CODE_STATUS_RESPONSE
        0, // reserved
        0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, // key prefix x6
        ...stats.buffer.asUint8List(),
      ]);
      expect(r.isStatus, isTrue);
      expect(r.keyPrefix, key.sublist(0, 6));
      final s = r.repeaterStats!;
      expect(s.battMilliVolts, 4150);
      expect(s.noiseFloor, -115);
      expect(s.lastRssi, -88);
      expect(s.packetsRecv, 1000);
      expect(s.upTimeSecs, 99999);
      expect(s.recvDirect, 40);
      expect(s.errEvents, 3);
      expect(s.lastSnr, -6.5);
      expect(s.floodDups, 6);
      expect(s.rxAirTimeSecs, 777);
      expect(s.recvErrors, 8);
      // A short blob (e.g. a different node type) parses without stats.
      final short =
          parseAs<MeshCoreNodeResponse>([0x87, 0, 1, 2, 3, 4, 5, 6, 1, 2]);
      expect(short.repeaterStats, isNull);
      expect(short.data, [1, 2]);
      expect(
          parseAs<MeshCoreNodeResponse>([0x8B, 0, 1, 2, 3, 4, 5, 6])
              .isTelemetry,
          isTrue);
    });

    test('BINARY_RESPONSE: tag then data (MyMesh.cpp:754-758)', () {
      final r =
          parseAs<MeshCoreBinaryResponse>([0x8C, 0, ...le32(0x01020304), 7, 8]);
      expect(r.tag, 0x01020304);
      expect(r.data, [7, 8]);
    });
  });

  group('garbage in, never an exception', () {
    test('unknown codes', () {
      expect(parseAs<MeshCoreUnknownFrame>([0x55, 1, 2]).code, 0x55);
      parseAs<MeshCoreUnknownFrame>([0xFE]);
      parseAs<MeshCoreUnknownFrame>([MeshCoreResp.cliReply, ...ascii('ok')]);
    });

    test('empty and truncated frames are MeshCoreMalformedFrame', () {
      expect(MeshCoreFrame.parse(b([])), isA<MeshCoreMalformedFrame>());
      final truncated = <List<int>>[
        [2, 1, 2, 3], // CONTACTS_START needs u32
        [3, ...key], // CONTACT cut short
        [0x8A, ...List.filled(146, 0)], // NEW_ADVERT one byte short
        [5, 1, 22, 30, ...key.sublist(0, 31)], // SELF_INFO key cut
        [13], // DEVICE_INFO without version
        [6, 1, 0, 0, 0, 0, 0, 0, 0], // SENT 9 of 10 bytes
        [16, 0, 0, 0, 1, 2, 3, 4, 5, 6, 0, 0, 1, 2, 3], // V3 msg ts cut
        [16, 0, 0, 0, 1, 2, 3, 4, 5, 6, 0, 2, 1, 2, 3, 4, 9], // sig cut
        [17, 0, 0, 0, 1, 0, 0], // channel V3 cut
        [27, 0, 0, 0, 0, 0, 1, 0, 5, 1, 2], // data_len 5, only 2 bytes
        [18, 0, ...List.filled(40, 0)], // CHANNEL_INFO secret cut
        [24], // STATS without type
        [24, 1, 0, 0, 0], // radio stats cut
        [0x80, 1, 2, 3], // ADVERT key cut
        [0x82, 1, 2, 3, 4, 5], // SEND_CONFIRMED cut
        [0x88, 0], // LOG_RX without rssi
        [0x89, 0, 3, 0, ...le32(1), ...le32(2), 1, 2, 3, 4, 5, 6], // no final
        [0x87, 0, 1, 2], // STATUS key prefix cut
        [0x8C, 0, 1, 2], // BINARY tag cut
        [9, 1, 2], // CURR_TIME cut
        [12, 1], // BATT cut
      ];
      for (final t in truncated) {
        final f = MeshCoreFrame.parse(b(t));
        expect(f, isA<MeshCoreMalformedFrame>(),
            reason: 'code ${t[0]} len ${t.length} -> $f');
        expect((f as MeshCoreMalformedFrame).reason, contains('truncated'));
      }
    });

    test('random bytes never throw', () {
      final rnd = Random(42);
      for (var n = 0; n < 20000; n++) {
        final len = rnd.nextInt(180);
        final bytes = b(List.generate(len, (_) => rnd.nextInt(256)));
        if (len > 0 && rnd.nextBool()) {
          // Bias towards known codes.
          const codes = [
            0,
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            12,
            13,
            16,
            17,
            18,
            24,
            27,
            0x80,
            0x81,
            0x82,
            0x84,
            0x87,
            0x88,
            0x89,
            0x8A,
            0x8C
          ];
          bytes[0] = codes[rnd.nextInt(codes.length)];
        }
        final f = MeshCoreFrame.parse(bytes);
        if (f is MeshCoreRxLog) f.packet;
        if (f is MeshCoreNodeResponse) f.repeaterStats;
      }
    });
  });

  group('MeshCorePathLen', () {
    test('encoding mirrors Packet.h', () {
      expect(MeshCorePathLen.encode(hops: 3), 0x03);
      expect(MeshCorePathLen.encode(hops: 3, hashSize: 3), 0x83);
      expect(MeshCorePathLen.hashSize(0x83), 3);
      expect(MeshCorePathLen.hashCount(0x83), 3);
      expect(MeshCorePathLen.byteLength(0x83), 9);
      expect(MeshCorePathLen.isValid(0xC1), isFalse); // size 4 reserved
      expect(MeshCorePathLen.isValid(0xFF), isFalse);
      expect(MeshCorePathLen.isValid(0x95), isTrue); // 21 hops x 3 = 63
      expect(MeshCorePathLen.isValid(0x96), isFalse); // 22 x 3 = 66 > 64
      expect(() => MeshCorePathLen.encode(hops: 22, hashSize: 3),
          throwsArgumentError);
    });
  });
}
