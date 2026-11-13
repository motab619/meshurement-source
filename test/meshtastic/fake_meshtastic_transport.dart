// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

// A scripted Meshtastic radio for MeshtasticRadio tests: answers the
// config handshake with a node list and settings, hands back FromRadio
// frames for every packet the phone writes (default: the firmware's own
// replies for local admin, silence for remote nodes, which tests script
// with [FakeMeshtasticTransport.onPacket]). No Bluetooth involved.

import 'dart:async';

import 'package:mesh_analyzer/data/radio/ble/radio_transport.dart';
import 'package:mesh_analyzer/proto/meshtastic/admin.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/channel.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/portnums.pbenum.dart' as pb;

/// A 32-byte key starting with [first].
List<int> keyOf(List<int> first) =>
    [...first, ...List.generate(32 - first.length, (i) => i)];

/// The ROUTING_APP reply node [from] sends for [request] (firmware
/// `allocErrorResponse` + `setReplyTo`): an ACK unless [error] is given.
pb.FromRadio routingFrame(
  pb.MeshPacket request, {
  required int from,
  pb.Routing_Error error = pb.Routing_Error.NONE,
  int rssi = -70,
  double snr = 8,
}) =>
    pb.FromRadio(
      packet: pb.MeshPacket(
        from: from,
        to: 0,
        // Distinct from the request's id, and still a uint32: a real id is
        // drawn up to 0xFFFFFFFE, so a plain + overflowed ~1 in 4,300 runs.
        id: (request.id + 1000000) & 0xFFFFFFFF,
        rxRssi: rssi,
        rxSnr: snr,
        decoded: pb.Data(
          portnum: pb.PortNum.ROUTING_APP,
          requestId: request.id,
          payload: pb.Routing(errorReason: error).writeToBuffer(),
        ),
      ),
    );

/// The ADMIN_APP response node [from] sends for [request].
pb.FromRadio adminFrame(
  pb.MeshPacket request, {
  required int from,
  required pb.AdminMessage message,
}) =>
    pb.FromRadio(
      packet: pb.MeshPacket(
        from: from,
        to: 0,
        id: request.id + 2000000,
        rxRssi: from == 0 ? 0 : -70,
        decoded: pb.Data(
          portnum: pb.PortNum.ADMIN_APP,
          requestId: request.id,
          payload: message.writeToBuffer(),
        ),
      ),
    );

pb.AdminMessage adminOf(pb.MeshPacket packet) =>
    pb.AdminMessage.fromBuffer(packet.decoded.payload);

class FakeMeshtasticTransport implements RadioTransport {
  FakeMeshtasticTransport({
    required this.myNodeNum,
    List<pb.NodeInfo> nodes = const [],
    pb.Config_LoRaConfig? lora,
    this.security,
    List<pb.Channel>? channels,
  })  : nodes = List.of(nodes),
        lora = lora ??
            pb.Config_LoRaConfig(
              usePreset: true,
              modemPreset: pb.Config_LoRaConfig_ModemPreset.LONG_FAST,
              region: pb.Config_LoRaConfig_RegionCode.US,
              txPower: 27,
              hopLimit: 3,
            ),
        channels = channels ??
            [
              pb.Channel(
                index: 0,
                role: pb.Channel_Role.PRIMARY,
                settings: pb.ChannelSettings(
                    name: 'MeshTest', psk: List.filled(32, 7)),
              ),
            ];

  final int myNodeNum;
  final List<pb.NodeInfo> nodes;
  pb.Config_LoRaConfig lora;

  /// Sent in the handshake and returned for a local get_config(SECURITY)
  /// when set.
  pb.Config_SecurityConfig? security;
  final List<pb.Channel> channels;

  /// Reported in the handshake's metadata.
  String firmwareVersion = '2.8.1.8e6a88d';

  /// Sent in the handshake when set (the node's GPS settings).
  pb.Config_PositionConfig? position;

  /// Scripted answers: the frames the radio hands back for [packet], or
  /// null for the default (firmware-like replies to local admin, nothing
  /// for packets to other nodes).
  List<pb.FromRadio>? Function(pb.MeshPacket packet)? onPacket;

  /// Every ToRadio message written, in order.
  final written = <pb.ToRadio>[];

  List<pb.MeshPacket> get packets =>
      [for (final w in written) if (w.hasPacket()) w.packet];

  /// Admin messages sent to the radio itself (local admin), in order.
  List<pb.AdminMessage> get localAdmin => [
        for (final p in packets)
          if (p.to == myNodeNum && p.decoded.portnum == pb.PortNum.ADMIN_APP)
            adminOf(p)
      ];

  /// Packets addressed to [nodeNum] on the ADMIN_APP port, in order.
  List<pb.MeshPacket> adminPacketsTo(int nodeNum) => [
        for (final p in packets)
          if (p.to == nodeNum && p.decoded.portnum == pb.PortNum.ADMIN_APP) p
      ];

  final _queue = <List<int>>[];
  final _notify = StreamController<List<int>>.broadcast();
  bool connected = false;

  /// Hand [frame] to the phone (read on the next drain).
  void push(pb.FromRadio frame) {
    _queue.add(frame.writeToBuffer());
    _notify.add(const [0, 0, 0, 0]);
  }

  void _pushConfig(int configId) {
    push(pb.FromRadio(
        myInfo: pb.MyNodeInfo(myNodeNum: myNodeNum, nodedbCount: nodes.length)));
    for (final n in nodes) {
      push(pb.FromRadio(nodeInfo: n));
    }
    push(pb.FromRadio(config: pb.Config(lora: lora)));
    if (security != null) {
      push(pb.FromRadio(config: pb.Config(security: security)));
    }
    if (position != null) {
      push(pb.FromRadio(config: pb.Config(position: position)));
    }
    for (final c in channels) {
      push(pb.FromRadio(channel: c));
    }
    push(pb.FromRadio(
        metadata: pb.DeviceMetadata(firmwareVersion: firmwareVersion)));
    push(pb.FromRadio(configCompleteId: configId));
  }

  /// SPECIAL_NONCE_ONLY_NODES (69421): our own NodeInfo first, the others,
  /// then the complete id; nothing else (PhoneAPI.cpp at v2.7.26).
  void _pushNodesOnly(int configId) {
    final own = nodes.where((n) => n.num == myNodeNum);
    for (final n in [...own, ...nodes.where((n) => n.num != myNodeNum)]) {
      push(pb.FromRadio(nodeInfo: n));
    }
    push(pb.FromRadio(configCompleteId: configId));
  }

  List<pb.FromRadio> _defaultAnswer(pb.MeshPacket p) {
    if (p.to != myNodeNum || p.decoded.portnum != pb.PortNum.ADMIN_APP) {
      return const [];
    }
    final admin = adminOf(p);
    if (admin.hasGetConfigRequest()) {
      final pb.Config? config = switch (admin.getConfigRequest) {
        pb.AdminMessage_ConfigType.LORA_CONFIG => pb.Config(lora: lora),
        pb.AdminMessage_ConfigType.SECURITY_CONFIG =>
          security == null ? null : pb.Config(security: security),
        _ => null,
      };
      if (config == null) return [routingFrame(p, from: myNodeNum)];
      return [
        adminFrame(p,
            from: myNodeNum,
            message: pb.AdminMessage(
                getConfigResponse: config, sessionPasskey: List.filled(8, 9))),
      ];
    }
    return [routingFrame(p, from: myNodeNum)];
  }

  @override
  String get platformName => 'Meshtastic-Fake';

  @override
  Future<void> connect(String deviceId,
      {Duration timeout = const Duration(seconds: 15)}) async {
    connected = true;
  }

  @override
  Future<void> discover() async {}

  @override
  StreamSubscription<void> listenLinkLost(void Function() onLost) =>
      const Stream<void>.empty().listen((_) {});

  @override
  Future<void> setNotify(String uuid, {required Duration timeout}) async {}

  @override
  Stream<List<int>> notifications(String uuid) => _notify.stream;

  @override
  Future<List<int>> read(String uuid) async =>
      _queue.isEmpty ? const [] : _queue.removeAt(0);

  @override
  Future<void> write(String uuid, List<int> data,
      {Duration timeout = const Duration(seconds: 15)}) async {
    if (!connected) throw StateError('Not connected to a node');
    final msg = pb.ToRadio.fromBuffer(data);
    written.add(msg);
    if (msg.hasWantConfigId() && msg.wantConfigId == 69421) {
      _pushNodesOnly(msg.wantConfigId);
    } else if (msg.hasWantConfigId()) {
      _pushConfig(msg.wantConfigId);
    } else if (msg.hasPacket()) {
      final p = msg.packet;
      final frames = onPacket?.call(p) ?? _defaultAnswer(p);
      // Replies arrive after the write returns, as over the air.
      Timer.run(() {
        for (final f in frames) {
          push(f);
        }
      });
    }
  }

  @override
  void clearCharacteristics() {}

  @override
  Future<void> disconnect() async => connected = false;
}
