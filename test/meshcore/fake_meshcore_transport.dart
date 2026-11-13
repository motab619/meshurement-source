// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

// A scripted MeshCore companion for MeshCoreRadio tests: answers each
// written command with frames laid out as the firmware writes them
// (examples/companion_radio/MyMesh.cpp at MeshCore 81dbae5) and can inject
// pushes. No Bluetooth involved.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:mesh_analyzer/data/radio/ble/radio_transport.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_frames.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_protocol.dart';

List<int> le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];

List<int> le32(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

List<int> fixed(String s, int width) {
  final out = List<int>.filled(width, 0);
  final e = utf8.encode(s);
  out.setRange(0, e.length, e);
  return out;
}

int u32At(List<int> b, int o) =>
    ByteData.sublistView(Uint8List.fromList(b)).getUint32(o, Endian.little);

/// A 32-byte key starting with [first].
Uint8List keyOf(List<int> first) => Uint8List.fromList(
    [...first, ...List.generate(32 - first.length, (i) => i)]);

/// DEVICE_INFO (MyMesh.cpp:1059-1075).
List<int> deviceInfoFrame({
  int verCode = 14,
  int maxChannels = 4,
  String manufacturer = 'Seeed Wio Tracker L1',
  String version = 'v1.18.0',
  bool repeat = false,
  int pathHashMode = 0,
}) =>
    [
      13,
      verCode,
      175,
      maxChannels,
      ...le32(0),
      ...fixed('15 Oct 2026', 12),
      ...fixed(manufacturer, 40),
      ...fixed(version, 20),
      repeat ? 1 : 0,
      pathHashMode,
    ];

/// SELF_INFO (MyMesh.cpp:1084-1117).
List<int> selfInfoFrame({
  required Uint8List key,
  int txPower = 22,
  int freqKHz = 910525,
  int bwHz = 62500,
  int sf = 7,
  int cr = 5,
  String name = 'Mobile',
}) =>
    [
      5,
      1,
      txPower,
      22,
      ...key,
      ...le32(0),
      ...le32(0),
      0,
      0,
      0,
      0,
      ...le32(freqKHz),
      ...le32(bwHz),
      sf,
      cr,
      ...utf8.encode(name),
    ];

/// RESP_CODE_CONTACT (MyMesh.cpp:171-192).
List<int> contactFrame({
  required Uint8List key,
  required String name,
  int type = MeshCoreAdvType.chat,
  int outPathLen = 0xFF,
  List<int> outPath = const [],
  int latE6 = 0,
  int lonE6 = 0,
  int lastMod = 1700000000,
}) {
  final b = MeshCoreCommands.addUpdateContact(MeshCoreContact(
    publicKey: key,
    type: type,
    outPathLen: outPathLen,
    outPath: Uint8List.fromList(outPath),
    name: name,
    latE6: latE6,
    lonE6: lonE6,
    lastModified: lastMod,
  ));
  b[0] = MeshCoreResp.contact;
  return b;
}

List<int> channelFrame(int idx, String name, List<int> secret) =>
    [18, idx, ...fixed(name, 32), ...secret];

const ok = [0];
List<int> err(int code) => [1, code];

class FakeMeshCoreTransport implements RadioTransport {
  FakeMeshCoreTransport({
    required this.ownKey,
    this.contacts = const [],
    Map<int, List<int>>? channels,
    this.maxChannels = 4,
  }) : channels =
            channels ?? {0: channelFrame(0, 'Public', List.filled(16, 0x8b))};

  final Uint8List ownKey;
  List<List<int>> contacts;

  /// Slot → CHANNEL_INFO frame; missing slots below [maxChannels] read
  /// back empty, slots at or above it answer ERR NOT_FOUND.
  final Map<int, List<int>> channels;
  final int maxChannels;

  List<int> deviceInfo = deviceInfoFrame();
  late List<int> selfInfo = selfInfoFrame(key: ownKey);

  /// Per-command overrides: return the frames to send back (null = the
  /// default answer).
  final overrides = <int, List<List<int>>? Function(Uint8List cmd)>{};

  /// Commands whose Bluetooth write fails with the given error.
  final failWrites = <int, Object>{};

  /// Called after the default/override answer to a command was sent.
  final after = <int, void Function(Uint8List cmd)>{};

  final writes = <Uint8List>[];

  /// Everything that happened, in order ("write:36", "beforeSend", …).
  final events = <String>[];

  final _notify = StreamController<List<int>>.broadcast();
  void Function()? _onLost;
  bool connected = false;

  List<int> get writtenCodes => [for (final w in writes) w[0]];

  /// Send [frame] to the app as a notification.
  void push(List<int> frame) => _notify.add(frame);

  /// Simulate the radio going out of range.
  void dropLink() {
    connected = false;
    _onLost?.call();
  }

  List<List<int>> _answer(Uint8List cmd) {
    switch (cmd[0]) {
      case MeshCoreCmd.deviceQuery:
        return [deviceInfo];
      case MeshCoreCmd.appStart:
        return [selfInfo];
      case MeshCoreCmd.getContacts:
        return [
          [2, ...le32(contacts.length)],
          ...contacts,
          [4, ...le32(1700000000)],
        ];
      case MeshCoreCmd.getChannel:
        final i = cmd[1];
        if (i >= maxChannels) return [err(MeshCoreErr.notFound)];
        return [channels[i] ?? channelFrame(i, '', List.filled(16, 0))];
      case MeshCoreCmd.syncNextMessage:
        return [
          [MeshCoreResp.noMoreMessages]
        ];
      case MeshCoreCmd.getStats:
        return [
          [24, 1, ...le16(-110 & 0xFFFF), 0xA0, 20, ...le32(0), ...le32(0)]
        ];
      case MeshCoreCmd.sendTracePath:
        return [
          [6, 0, ...cmd.sublist(1, 5), ...le32(1200)]
        ];
      default:
        return [ok];
    }
  }

  @override
  String get platformName => 'MeshCore-Fake';

  @override
  Future<void> connect(String deviceId,
      {Duration timeout = const Duration(seconds: 15)}) async {
    events.add('connect');
    connected = true;
  }

  @override
  Future<void> discover() async => events.add('discover');

  @override
  StreamSubscription<void> listenLinkLost(void Function() onLost) {
    _onLost = onLost;
    final c = StreamController<void>();
    return c.stream.listen((_) {}, onDone: () => _onLost = null);
  }

  @override
  Future<void> setNotify(String uuid, {required Duration timeout}) async =>
      events.add('notify');

  @override
  Stream<List<int>> notifications(String uuid) => _notify.stream;

  @override
  Future<List<int>> read(String uuid) async => const [];

  @override
  Future<void> write(String uuid, List<int> data,
      {Duration timeout = const Duration(seconds: 15)}) async {
    final cmd = Uint8List.fromList(data);
    writes.add(cmd);
    events.add('write:${cmd[0]}');
    if (!connected) throw StateError('Not connected to a node');
    final fail = failWrites[cmd[0]];
    if (fail != null) throw fail;
    final o = overrides[cmd[0]];
    final frames = (o == null ? null : o(cmd)) ?? _answer(cmd);
    Timer.run(() {
      for (final f in frames) {
        _notify.add(f);
      }
      after[cmd[0]]?.call(cmd);
    });
  }

  @override
  void clearCharacteristics() {}

  @override
  Future<void> disconnect() async {
    if (connected) events.add('disconnect');
    connected = false;
  }
}
