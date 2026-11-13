// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show protected, visibleForTesting;
import 'package:mesh_analyzer/proto/meshtastic/admin.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/channel.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/module_config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/portnums.pbenum.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/telemetry.pb.dart' as pb;
import 'package:protobuf/protobuf.dart' show GeneratedMessage;

import '../../../services/airtime_model.dart';
import '../../../services/diag_log.dart';
import '../../../utils/user_errors.dart' show isLostBondError, userMessage;
import '../../../utils/constants.dart';
import '../ble/ble_transport.dart';
import '../ble/radio_services.dart';
import '../mesh_radio.dart';
import 'meshtastic_admin_keys.dart';
import 'meshtastic_contacts.dart';
import 'meshtastic_frequency.dart';
import 'meshtastic_presets.dart';

/// A ROUTING_APP reply (ACK or NAK) for a packet we sent.
class RoutingReply {
  final int requestId;
  final pb.Routing_Error error;
  final pb.MeshPacket packet;

  /// The reply carried an error code the vendored protos don't know (a
  /// newer firmware). Dart decodes it as "no error", which would make a
  /// NAK look like an ACK, so it is tracked separately.
  final bool unknownError;

  const RoutingReply({
    required this.requestId,
    required this.error,
    required this.packet,
    this.unknownError = false,
  });

  bool get isAck => error == pb.Routing_Error.NONE && !unknownError;

  /// The error name as recorded (`error:<name>`), `UNKNOWN` for a code the
  /// protos don't know.
  String get errorName => unknownError ? 'UNKNOWN' : error.name;
}

/// An ADMIN_APP packet the radio handed to the phone (a reply to one of
/// our admin requests, local or from another node), decoded.
class AdminReply {
  final pb.MeshPacket packet;
  final pb.AdminMessage message;

  const AdminReply(this.packet, this.message);

  /// Id of the request this answers (firmware `setReplyTo`).
  int get requestId => packet.decoded.requestId;
  int get from => packet.from;
}

/// Another node refused (or our own radio refused to send) an admin
/// message: a ROUTING_APP NAK with [errorName] from node [from].
/// Why a send or a remote change is refused on the public channel.
const publicChannelRefusal = 'Your node is on the public channel. Run Node '
    'Setup first: the app never tests or changes nodes there.';

class RemoteAdminNak extends StateError {
  final String errorName;
  final int from;

  RemoteAdminNak(this.errorName, this.from, String message) : super(message);

  /// One side lacks the other's public key (fixable by [MeshtasticRadio.ensureContact]).
  bool get isKeyProblem => const {
        'PKI_SEND_FAIL_PUBLIC_KEY',
        'PKI_UNKNOWN_PUBKEY',
        'PKI_FAILED',
      }.contains(errorName);
}

/// The radio's own airtime figures from a TELEMETRY_APP [packet], or null
/// unless it comes from our own node ([myNodeNum]) and carries
/// DeviceMetrics (or LocalStats) with airtime fields. Other nodes'
/// telemetry says nothing about our radio and is ignored.
///
/// Firmware sends these to the phone about once a minute (DeviceMetrics)
/// and every 15 min (LocalStats): DeviceTelemetry.cpp runOnce.
RadioChannelStats? channelStatsFromTelemetry(
  pb.MeshPacket packet, {
  required int? myNodeNum,
  DateTime? now,
}) {
  if (myNodeNum == null || packet.from != myNodeNum) return null;
  if (!packet.hasDecoded() ||
      packet.decoded.portnum != pb.PortNum.TELEMETRY_APP) {
    return null;
  }
  final pb.Telemetry t;
  try {
    t = pb.Telemetry.fromBuffer(packet.decoded.payload);
  } catch (_) {
    return null;
  }
  final at = now ?? DateTime.now();
  if (t.hasDeviceMetrics()) {
    final m = t.deviceMetrics;
    if (!m.hasAirUtilTx() && !m.hasChannelUtilization()) return null;
    return RadioChannelStats(
      airUtilTxPercent: m.airUtilTx,
      channelUtilizationPercent: m.channelUtilization,
      measuredAt: at,
    );
  }
  if (t.hasLocalStats()) {
    final s = t.localStats;
    return RadioChannelStats(
      airUtilTxPercent: s.airUtilTx,
      channelUtilizationPercent: s.channelUtilization,
      measuredAt: at,
    );
  }
  return null;
}

/// Airtime figures from our own [node]'s stored DeviceMetrics (the node DB
/// download at connect carries the last values), or null when absent.
RadioChannelStats? channelStatsFromNodeInfo(
  pb.NodeInfo node, {
  required int? myNodeNum,
  DateTime? now,
}) {
  if (myNodeNum == null || node.num != myNodeNum || !node.hasDeviceMetrics()) {
    return null;
  }
  final m = node.deviceMetrics;
  if (!m.hasAirUtilTx() && !m.hasChannelUtilization()) return null;
  return RadioChannelStats(
    airUtilTxPercent: m.airUtilTx,
    channelUtilizationPercent: m.channelUtilization,
    measuredAt: now ?? DateTime.now(),
  );
}

/// Our own node's GPS fix from [node] (its NodeInfo at connect, or a
/// POSITION_APP packet from it), or null when [node] isn't ours or has no
/// usable position. Firmware 2.8 (PositionModule::sendOurPositionToPhone at
/// v2.8.1.8e6a88d) hands the phone its own position every 60 s, full
/// precision and never on air; 2.7.26 has no such path, so there the phone
/// only sees the position broadcasts the node sends on the channel anyway.
NodeFix? ownFixFromNodeInfo(
  pb.NodeInfo node, {
  required int? myNodeNum,
  DateTime? now,
}) {
  if (myNodeNum == null || node.num != myNodeNum || !node.hasPosition()) {
    return null;
  }
  final fix = nodeFixFromPosition(node.position, now: now ?? DateTime.now());
  return fix.isValid ? fix : null;
}

/// A [NodeFix] from a Meshtastic [pos]. The fix time is the position's own
/// `time` (or `timestamp`) when it is set and not in the future, else
/// [now]; the accuracy comes from DOP × the GPS's accuracy when the node
/// sends them (not by default), else 10 m.
NodeFix nodeFixFromPosition(pb.Position pos, {required DateTime now}) {
  final secs = pos.time != 0 ? pos.time : pos.timestamp;
  var time = now;
  if (secs > 0) {
    final t = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    if (!t.isAfter(now.add(const Duration(minutes: 1)))) time = t;
  }
  final dop = pos.hDOP > 0 ? pos.hDOP : pos.pDOP;
  final accuracy = dop > 0 && pos.gpsAccuracy > 0
      ? pos.gpsAccuracy / 1000 * dop / 100
      : 10.0;
  return NodeFix(
    latitude: pos.latitudeI / 1e7,
    longitude: pos.longitudeI / 1e7,
    altitudeM: pos.hasAltitude() ? pos.altitude.toDouble() : null,
    accuracyM: accuracy,
    time: time,
  );
}

/// How often Node Setup has a mobile node's GPS take a fix (seconds). The
/// firmware default is 120 s (Default.h `default_gps_update_interval`);
/// the phone is handed the position every 60 s on 2.8, so 30 s keeps that
/// at most a minute old. Smart position broadcasts stay at one per 5 min
/// at most (`min_default_broadcast_smart_minimum_interval_secs`), so this
/// adds nothing on air.
const mobileGpsUpdateIntervalSec = 30;

/// The position config Node Setup writes to a mobile node so its GPS can
/// stand in for the phone's (docs/design/ipad step 5): GPS on and fixing
/// every [mobileGpsUpdateIntervalSec], everything else as it was. Null when
/// there is nothing to write: config not read, no GPS chip (NOT_PRESENT),
/// a fixed position the owner set, or already on and fast enough.
pb.Config_PositionConfig? mobileGpsConfig(pb.Config_PositionConfig? current) {
  if (current == null ||
      current.fixedPosition ||
      current.gpsMode == pb.Config_PositionConfig_GpsMode.NOT_PRESENT) {
    return null;
  }
  final next = current.deepCopy();
  if (next.gpsMode == pb.Config_PositionConfig_GpsMode.DISABLED) {
    next.gpsMode = pb.Config_PositionConfig_GpsMode.ENABLED;
  }
  if (next.gpsUpdateInterval == 0 ||
      next.gpsUpdateInterval > mobileGpsUpdateIntervalSec) {
    next.gpsUpdateInterval = mobileGpsUpdateIntervalSec;
  }
  _clearUnknown(
      next, const [_positionGpsUpdateIntervalTag, _positionGpsModeTag]);
  final same = next.gpsMode == current.gpsMode &&
      next.gpsUpdateInterval == current.gpsUpdateInterval;
  return same ? null : next;
}

const _positionGpsUpdateIntervalTag = 5;
const _positionGpsModeTag = 13;

void _clearUnknown(GeneratedMessage msg, List<int> tags) {
  for (final tag in tags) {
    msg.unknownFields.clearField(tag);
  }
}

/// "on, every 30 s" etc., for the backup comparison.
String meshtasticGpsLabel(pb.Config_PositionConfig p) {
  if (p.fixedPosition) return 'fixed position';
  return switch (p.gpsMode) {
    pb.Config_PositionConfig_GpsMode.NOT_PRESENT => 'no GPS',
    pb.Config_PositionConfig_GpsMode.DISABLED => 'off',
    _ => p.gpsUpdateInterval == 0
        ? 'on, every 2 min (default)'
        : 'on, every ${p.gpsUpdateInterval} s',
  };
}

/// `ExcludedModules.RANGETEST_CONFIG` in `DeviceMetadata.excluded_modules`.
const int excludedRangeTest = 0x0010;

/// What the firmware behind [metadata] can do. Firmware 2.8 reports Range
/// Test as excluded; 2.7 never does, so absence proves nothing there.
RadioCapabilities capabilitiesFromMetadata(pb.DeviceMetadata? metadata) {
  if (metadata == null) return RadioCapabilities.unknown;
  final version = metadata.firmwareVersion;
  final caps = RadioCapabilities(
    firmwareVersion: version,
    rangeTestExcluded: metadata.excludedModules & excludedRangeTest != 0,
  );
  return RadioCapabilities(
    firmwareVersion: version,
    rangeTestExcluded: caps.rangeTestExcluded,
    hasTraceroute: caps.firmwareAtLeast(2, 3),
  );
}

/// The `N` of a Range Test payload `seq N`, or null.
int? rangeTestSeqFrom(List<int> payload) {
  if (payload.isEmpty || payload.length > 32) return null;
  final text = String.fromCharCodes(payload);
  final m = RegExp(r'^seq\s+(\d+)').firstMatch(text);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// The sender's channel utilisation (%) from a DeviceMetrics telemetry
/// payload, or null when it isn't one or doesn't carry the field.
double? senderChannelUtilFrom(List<int> payload) {
  if (payload.isEmpty) return null;
  try {
    final t = pb.Telemetry.fromBuffer(payload);
    if (t.hasDeviceMetrics() && t.deviceMetrics.hasChannelUtilization()) {
      return t.deviceMetrics.channelUtilization;
    }
  } catch (_) {}
  return null;
}

/// Map a Meshtastic [packet] to the neutral [ReceivedPacket]. Null for
/// packets from node 0 or from our own radio ([myNodeNum]): those (e.g.
/// locally generated NAKs) carry no over-the-air signal data.
ReceivedPacket? receivedPacketFrom(pb.MeshPacket packet,
    {int? myNodeNum, bool queued = false}) {
  final from = packet.from;
  if (from == 0 || from == myNodeNum) return null;
  // rx_time is epoch seconds from the radio's clock, 0 when it has no time.
  final rxTime = packet.rxTime == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(packet.rxTime * 1000, isUtc: true);

  // Encrypted packets (channel we don't have the key for) have no portnum.
  final int portNum = packet.hasDecoded() ? packet.decoded.portnum.value : 0;
  final payload = packet.hasDecoded() ? packet.decoded.payload : const <int>[];
  return ReceivedPacket(
    from: from,
    packetId: packet.id,
    type: PacketType.fromPortNum(portNum),
    snr: _rxSnrOf(packet),
    rssi: _rxRssiOf(packet),
    // hopStart is 0 on firmware older than 2.3; treat as direct then.
    // Note: SNR/RSSI describe the last hop only, so they reflect the
    // source node's link only when hops == 0.
    hops: _hopsOf(packet),
    channelIndex: packet.channel,
    viaMqtt: packet.viaMqtt,
    payload:
        packet.hasDecoded() ? Uint8List.fromList(packet.decoded.payload) : null,
    rxTime: rxTime,
    queued: queued,
    beaconSeq: portNum == pb.PortNum.RANGE_TEST_APP.value
        ? rangeTestSeqFrom(payload)
        : null,
    senderChannelUtil: portNum == pb.PortNum.TELEMETRY_APP.value
        ? senderChannelUtilFrom(payload)
        : null,
  );
}

/// RSSI is never 0 for a packet actually received over the air; locally
/// generated or queued packets carry rssi 0 and no signal data.
double? _rxSnrOf(pb.MeshPacket packet) =>
    packet.rxRssi != 0 ? packet.rxSnr : null;

int? _rxRssiOf(pb.MeshPacket packet) =>
    packet.rxRssi != 0 ? packet.rxRssi : null;

/// Hop limit for pings. The firmware replaces 0 on want_ack packets from the
/// phone with the configured default, so 1 is the minimum that still sends.
const int pingHopLimit = 1;

/// The MeshPacket [MeshtasticRadio.sendData] puts on the air.
pb.MeshPacket buildDataPacket({
  required int id,
  required int to,
  required pb.PortNum portnum,
  required List<int> payload,
  int channel = 0,
  bool wantAck = false,
  bool wantResponse = false,
  int? hopLimit,
  bool pkiEncrypted = false,
}) =>
    pb.MeshPacket(
      id: id,
      to: to,
      channel: channel,
      wantAck: wantAck,
      hopLimit: hopLimit,
      // Asking for PKI makes the firmware refuse (PKI_FAILED) rather than
      // fall back to channel encryption (Router.cpp perhapsEncode).
      pkiEncrypted: pkiEncrypted ? true : null,
      decoded: pb.Data(
        portnum: portnum,
        payload: payload,
        wantResponse: wantResponse,
      ),
    );

int _hopsOf(pb.MeshPacket packet) =>
    packet.hopStart > 0 ? (packet.hopStart - packet.hopLimit).clamp(0, 7) : 0;

/// Map a Meshtastic [info] (node DB entry) to the neutral [RadioNode].
RadioNode radioNodeFrom(pb.NodeInfo info) {
  final hasPos = info.hasPosition();
  return RadioNode(
    num: info.num,
    longName: info.hasUser() ? info.user.longName : '',
    shortName: info.hasUser() ? info.user.shortName : '',
    hwModel: info.hasUser() ? info.user.hwModel.name : '',
    latitude: hasPos ? info.position.latitudeI / 1e7 : null,
    longitude: hasPos ? info.position.longitudeI / 1e7 : null,
    hopsAway: info.hasHopsAway() ? info.hopsAway : null,
    lastHeard: info.lastHeard != 0
        ? DateTime.fromMillisecondsSinceEpoch(info.lastHeard * 1000)
        : null,
  );
}

class _PendingPing {
  final int target;
  final Stopwatch clock;
  final Completer<PingOutcome> completer;
  Timer? timeout;

  _PendingPing(this.target, this.clock, this.completer);
}

/// Meshtastic BLE client on top of [BleTransport].
///
/// Mirrors the transport proven against a real T1000-E (firmware 2.7.x) in
/// the coachella-mesh app:
///   connect → discover → subscribe FromNum → write ToRadio{wantConfigId: N}
///   → read FromRadio until empty, repeatedly, until configCompleteId == N.
/// After that, every FromNum notify triggers a read-until-empty drain.
/// FromNum's payload is ignored; it is only a "data waiting" signal.
///
/// Messages are the upstream Meshtastic protobufs, vendored and generated in
/// `lib/proto/` (see lib/proto/UPSTREAM.md).
class MeshtasticRadio implements MeshRadio {
  static const serviceUuid = RadioServices.meshtastic;
  static const toRadioUuid = 'f75c76d2-129e-4dad-a1dd-7866124401e7';
  static const fromRadioUuid = '2c55e69e-4993-11ed-b878-0242ac120002';
  static const fromNumUuid = 'ed9da18c-a800-4f66-a670-aa7547e34453';

  static const broadcastAddr = 0xFFFFFFFF;
  static const _handshakeTimeout = Duration(seconds: 60);
  static const _handshakePoll = Duration(milliseconds: 250);
  static const _heartbeatInterval = Duration(seconds: 60);
  static const _pairingTimeout = Duration(seconds: 90);

  /// Carrier frequency (MHz) used for Fresnel zones and path loss, from the
  /// radio's LoRa region: EU_868 is 868, everything else is treated as 915
  /// (US, ANZ, ... and unknown). A coarse choice: the Fresnel radius changes
  /// by under 3 % between 868 and 915 MHz.
  static double frequencyForRegion(pb.Config_LoRaConfig_RegionCode? region) =>
      region == pb.Config_LoRaConfig_RegionCode.EU_868 ? 868.0 : 915.0;

  final _random = Random.secure();

  /// [transport] replaces Bluetooth in tests (a scripted fake).
  /// [remoteExchangeTimeout] is how long one admin exchange with another
  /// node over the mesh may take (a remote radio answers slower than the
  /// one on the phone's link).
  MeshtasticRadio({
    RadioTransport? transport,
    this.remoteExchangeTimeout = const Duration(seconds: 15),
  }) : _transport = transport ??
            BleTransport(
              serviceUuid: serviceUuid,
              characteristicUuids: const [
                toRadioUuid,
                fromRadioUuid,
                fromNumUuid
              ],
              protocolName: 'Meshtastic',
            );

  final RadioTransport _transport;
  final Duration remoteExchangeTimeout;
  RadioDescriptor? _descriptor;
  bool _hasLink = false;
  StreamSubscription<List<int>>? _fromNumSub;
  StreamSubscription<void>? _linkSub;
  Timer? _heartbeatTimer;

  /// Bumped on every user connect/disconnect so stale reconnect loops quit.
  int _linkGen = 0;
  bool _wantConnected = false;

  int? _configId;
  Completer<void>? _configComplete;
  bool _draining = false;

  /// Set when the handshake completes and cleared at the next empty read:
  /// in between, the radio is handing over what it buffered while the
  /// phone was away (firmware PhoneAPI sends the queue right after
  /// config_complete_id). Those packets are not "heard now".
  bool _replaying = false;
  bool _drainAgain = false;

  RadioConnectionState _state = RadioConnectionState.disconnected;
  final _stateController = StreamController<RadioConnectionState>.broadcast();
  final _packetController = StreamController<ReceivedPacket>.broadcast();
  final _nodeController = StreamController<RadioNode>.broadcast();
  final _routingController = StreamController<RoutingReply>.broadcast();
  final _adminController = StreamController<AdminReply>.broadcast();
  final _txAirtimeController = StreamController<double>.broadcast();
  final _channelStatsController =
      StreamController<RadioChannelStats>.broadcast();
  RadioChannelStats? _lastChannelStats;
  final _ownFixController = StreamController<NodeFix>.broadcast();
  NodeFix? _lastOwnFix;

  @override
  Stream<NodeFix> get ownFixes => _ownFixController.stream;

  @override
  NodeFix? get lastOwnFix => _lastOwnFix;

  bool _ownFixesWanted = true;

  @override
  bool get ownFixesWanted => _ownFixesWanted;

  @override
  set ownFixesWanted(bool wanted) {
    if (wanted == _ownFixesWanted) return;
    _ownFixesWanted = wanted;
    if (wanted && isReady) _refreshOwnFix();
  }

  /// How often to re-read the node list for our own position on firmware
  /// before 2.8 ([needsOwnFixRefresh]).
  static const ownFixRefreshInterval = Duration(seconds: 30);

  /// `SPECIAL_NONCE_ONLY_NODES` (PhoneAPI.h): the node sends our own
  /// NodeInfo first, then the others, then config_complete_id = this.
  static const nodesOnlyConfigId = 69421;
  Timer? _ownFixTimer;

  /// Firmware before 2.8 never hands the phone its own position (2.8's
  /// PositionModule::sendOurPositionToPhone does, every 60 s), and its
  /// broadcasts are minutes apart. A "nodes only" config read
  /// (want_config_id 69421, PhoneAPI.cpp handleStartConfig at
  /// v2.7.26.54e0d8d) brings our own NodeInfo, with the GPS's latest fix,
  /// over Bluetooth only. Only while the node's GPS is on.
  bool get needsOwnFixRefresh {
    final caps = capabilities;
    if (isDemo || caps.firmwareVersion.isEmpty || caps.firmwareAtLeast(2, 8)) {
      return false;
    }
    final pos = configs[pb.Config_PayloadVariant.position]?.position;
    return pos != null &&
        !pos.fixedPosition &&
        pos.gpsMode == pb.Config_PositionConfig_GpsMode.ENABLED;
  }

  /// One refresh now (the timer does it every [ownFixRefreshInterval]).
  @visibleForTesting
  void refreshOwnFixNow() => _refreshOwnFix();

  void _refreshOwnFix() {
    if (!isReady || !_ownFixesWanted || !needsOwnFixRefresh) return;
    _write(pb.ToRadio(wantConfigId: nodesOnlyConfigId))
        .then((_) => _requestDrain())
        .catchError((Object e) {
      print('MeshRadio: own position refresh failed: $e');
    });
  }

  @override
  Stream<RadioChannelStats> get channelStats => _channelStatsController.stream;

  @override
  RadioChannelStats? get lastChannelStats => _lastChannelStats;

  /// Demo mode: pretend the radio reported these figures.
  void feedChannelStats(RadioChannelStats stats) => _publishChannelStats(stats);

  void _publishChannelStats(RadioChannelStats? stats) {
    if (stats == null || _channelStatsController.isClosed) return;
    _lastChannelStats = stats;
    _channelStatsController.add(stats);
  }

  ConnectProgress? _progress;
  final _progressController = StreamController<ConnectProgress?>.broadcast();
  DateTime? _lastProgressAt;

  /// Config download counts, for progress. [_expectedNodes] comes from
  /// MyNodeInfo.nodedb_count (0 on firmware that doesn't send it).
  int _configNodes = 0;
  int _expectedNodes = 0;

  @override
  ConnectProgress? get connectProgress => _progress;

  @override
  Stream<ConnectProgress?> get connectProgressStream =>
      _progressController.stream;

  void _setProgress(ConnectProgress? p) {
    if (_progressController.isClosed) return;
    _progress = p;
    _lastProgressAt = DateTime.now();
    _progressController.add(p);
  }

  /// Start a new connect step (resets the elapsed clock).
  void _beginStep(RadioConnectionState state, String step) => _setProgress(
      ConnectProgress(state: state, step: step, stepStartedAt: DateTime.now()));

  /// Update counts during the config download, at most ~5 times a second.
  void _configProgress() {
    final p = _progress;
    if (p == null || p.state != RadioConnectionState.configuring) return;
    final now = DateTime.now();
    if (_lastProgressAt != null &&
        now.difference(_lastProgressAt!) < const Duration(milliseconds: 200)) {
      return;
    }
    final expected = _expectedNodes;
    final String step;
    final String? detail;
    final double? fraction;
    if (_configNodes <= 1) {
      // Our own node, channels and settings come before the node list.
      step = 'Reading radio settings';
      final parts = [
        if (channels.isNotEmpty) '${channels.length} channels',
        if (configs.isNotEmpty || moduleConfigs.isNotEmpty)
          '${configs.length + moduleConfigs.length} settings',
      ];
      detail = parts.isEmpty ? null : parts.join(' · ');
      fraction = null;
    } else {
      step = 'Downloading node list';
      if (expected > 0) {
        final n = min(_configNodes, expected);
        detail = '$n of $expected nodes';
        fraction = n / expected;
      } else {
        detail = '$_configNodes nodes';
        fraction = null;
      }
    }
    _setProgress(ConnectProgress(
      state: RadioConnectionState.configuring,
      step: step,
      detail: detail,
      fraction: fraction,
      // The node list is the long part: restart the clock when it begins.
      stepStartedAt: step == p.step ? p.stepStartedAt : now,
    ));
  }

  /// Saved user records of our own radios (set by the app). Used to give
  /// a radio back a key it has lost; see [ensureContact].
  MeshtasticContacts? contacts;

  /// Pings awaiting their ACK/NAK, keyed by packet id.
  final Map<int, _PendingPing> _pendingPings = {};
  DateTime? _lastKeyExchange;

  @override
  RadioProtocol get protocol => RadioProtocol.meshtastic;

  /// Estimated airtime (ms) of each packet we ask the radio to send over
  /// the air (not admin messages to the local radio; nothing in demo mode).
  @override
  Stream<double> get txAirtimeStream => _txAirtimeController.stream;

  /// Node DB as reported by the radio (mesh node num → NodeInfo).
  final Map<int, pb.NodeInfo> nodeInfos = {};

  @override
  Map<int, RadioNode> get nodes =>
      nodeInfos.map((k, v) => MapEntry(k, radioNodeFrom(v)));

  /// Mesh node number of the connected radio (from MyNodeInfo).
  int? myNodeNum;

  @override
  int? get myNodeId => myNodeNum;

  /// The radio's LoRa settings and channel table, from the config download.
  pb.Config_LoRaConfig? loraConfig;
  final Map<int, pb.Channel> channels = {};

  /// Every config / module-config section from the config download.
  final Map<pb.Config_PayloadVariant, pb.Config> configs = {};
  final Map<pb.ModuleConfig_PayloadVariant, pb.ModuleConfig> moduleConfigs = {};

  /// Firmware details from the config download, when the radio sent them.
  pb.DeviceMetadata? metadata;

  /// The firmware's default channel key, which the 1-byte shorthand `1`
  /// expands to. Any other 1-byte shorthand `n` (2..255; "simple1".. for
  /// the low ones) is this key with n - 1 added to the last byte.
  /// Source: upstream `channel.proto` (ChannelSettings.psk, vendored in
  /// lib/proto/meshtastic/channel.proto) and firmware `src/mesh/Channels.cpp`
  /// (`defaultpsk`, `getKey`: `*last = *last + pskIndex - 1`).
  static const List<int> defaultPsk = [
    0xd4, 0xf1, 0xbb, 0x3a, 0x20, 0x29, 0x07, 0x59, //
    0xf0, 0xbc, 0xff, 0xab, 0xcf, 0x4e, 0x69, 0x01,
  ];

  /// Whether [psk] is no key, a 1-byte shorthand, or the expanded form of
  /// one: any 16-byte key whose first 15 bytes are the default key's,
  /// whatever its last byte (all well known, so effectively public).
  static bool isPublicPsk(List<int> psk) {
    if (psk.length <= 1) return true;
    if (psk.length != defaultPsk.length) return false;
    for (var i = 0; i < defaultPsk.length - 1; i++) {
      if (psk[i] != defaultPsk[i]) return false;
    }
    return true;
  }

  /// Primary channel has no key, a well-known 1-byte "simple" key or its
  /// expanded 16-byte form (the public mesh), or the channel table isn't
  /// known yet.
  @override
  bool get onPublicChannel {
    final primary = channels.values
        .where((c) => c.role == pb.Channel_Role.PRIMARY)
        .firstOrNull;
    if (primary == null) return true;
    return isPublicPsk(primary.settings.psk);
  }

  @override
  RadioCapabilities get capabilities => capabilitiesFromMetadata(metadata);

  @override
  RadioPreset? get currentPreset => MeshtasticPresets.fromConfig(loraConfig);

  @override
  double get regionFrequencyMHz => frequencyForRegion(loraConfig?.region);

  @override
  String get regionName => loraConfig?.region.name ?? '';

  @override
  String get primaryChannelName => channels[0]?.settings.name ?? '';

  @override
  RadioSettings? get radioSettings {
    final caps = capabilities;
    return MeshtasticFrequency.settingsFor(
      loraConfig,
      primaryChannel: channels.values
              .where((c) => c.role == pb.Channel_Role.PRIMARY)
              .firstOrNull ??
          channels[0],
      firmware28:
          caps.firmwareVersion.isEmpty ? null : caps.firmwareAtLeast(2, 8),
    );
  }

  /// Bluetooth name of the connected radio (or the demo radio's).
  @override
  String get displayName {
    if (_demoName != null) return _demoName!;
    final n = _descriptor?.name ?? '';
    if (n.isNotEmpty) return n;
    final live = _transport.platformName;
    return live.isNotEmpty ? live : 'node';
  }

  @override
  RadioDescriptor? get descriptor => _descriptor;

  /// Demo mode (screenshots): pretends to be a connected radio. Nothing is
  /// ever sent over Bluetooth.
  @override
  bool get isDemo => _demoName != null;
  String? _demoName;

  void enterDemo({
    required String name,
    required int myNodeNum,
    required List<pb.NodeInfo> nodeInfos,
    required pb.Config_LoRaConfig lora,
    required List<pb.Channel> channelTable,
  }) {
    _demoName = name;
    this.myNodeNum = myNodeNum;
    for (final n in nodeInfos) {
      _updateNode(n);
    }
    loraConfig = lora;
    channels
      ..clear()
      ..addEntries(channelTable.map((c) => MapEntry(c.index, c)));
    _setState(RadioConnectionState.ready);
  }

  @override
  RadioConnectionState get state => _state;
  @override
  bool get isReady => _state == RadioConnectionState.ready;

  @override
  Stream<RadioConnectionState> get connectionState async* {
    yield _state;
    yield* _stateController.stream;
  }

  /// Every packet the radio forwards to the phone (after config), as
  /// neutral [ReceivedPacket]s. ROUTING_APP replies are included (type
  /// `ack`); pings are answered through [ping] as well.
  @override
  Stream<ReceivedPacket> get packets => _packetController.stream;

  /// Node DB entries from the config download and later NODEINFO_APP /
  /// POSITION_APP updates.
  @override
  Stream<RadioNode> get nodeUpdates => _nodeController.stream;

  /// ACK/NAK replies keyed by the id of the packet they answer.
  Stream<RoutingReply> get routingStream => _routingController.stream;

  /// Every ADMIN_APP packet the radio hands over, decoded: replies to our
  /// local admin requests and to the ones we send other nodes. Tapped
  /// before the own-node filter, like [routingStream].
  Stream<AdminReply> get adminStream => _adminController.stream;

  // ─── Connect / disconnect ────────────────────────────

  /// Connect to [radio] and run the config handshake. Completes when the
  /// radio is ready; throws if the first attempt fails.
  @override
  Future<void> connect(RadioDescriptor radio) async {
    final gen = ++_linkGen;
    _wantConnected = true;
    await _teardown(sendDisconnect: true);
    if (_descriptor?.id != radio.id) {
      // Another radio: its node list, own number and airtime figures are
      // not this one's (ensureContact would trust a key the new radio
      // doesn't have, and a mobile session would record the base's airtime).
      nodeInfos.clear();
      myNodeNum = null;
      _lastChannelStats = null;
      _lastOwnFix = null;
    }
    _descriptor = radio;
    try {
      await _open(radio.id, gen);
    } catch (_) {
      _wantConnected = false;
      await _teardown(sendDisconnect: false);
      _setState(RadioConnectionState.disconnected);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _linkGen++;
    _wantConnected = false;
    await _teardown(sendDisconnect: true);
    _setState(RadioConnectionState.disconnected);
  }

  Future<void> _open(String deviceId, int gen) async {
    // Leftovers of a previous link (a teardown still in flight) must not
    // survive next to this one's: a leaked link listener restarts the
    // reconnect loop on every later drop.
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _linkSub?.cancel();
    _linkSub = null;
    await _fromNumSub?.cancel();
    _fromNumSub = null;
    _setState(RadioConnectionState.connecting);
    _beginStep(RadioConnectionState.connecting, 'Connecting over Bluetooth');

    // mtu: 512 is applied on Android only; iOS negotiates MTU itself.
    await _step(
      'Bluetooth connect',
      _transport.connect(deviceId, timeout: const Duration(seconds: 15)),
    );
    if (gen != _linkGen) return;

    _beginStep(RadioConnectionState.connecting, 'Finding the node\'s service');
    await _step('Finding the Meshtastic service', _transport.discover());
    _hasLink = true;

    _linkSub = _transport.listenLinkLost(() => _onLinkLost(gen));

    // Subscribe before want_config so no notify is missed. On iOS the first
    // access to an encrypted characteristic shows the system PIN prompt;
    // radios with a screen show a random PIN to type in, so allow time for
    // that (the library default of 15 s is too short).
    _fromNumSub =
        _transport.notifications(fromNumUuid).listen((_) => _requestDrain());
    _setState(RadioConnectionState.pairing);
    _beginStep(RadioConnectionState.pairing, 'Pairing');
    await _step(
      'Pairing (subscribe)',
      _transport.setNotify(fromNumUuid, timeout: _pairingTimeout),
    );

    await _step('Reading radio settings', _runHandshake());
    if (gen != _linkGen) return;

    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      _write(pb.ToRadio(heartbeat: pb.Heartbeat())).catchError((_) {});
    });
    _ownFixTimer?.cancel();
    _ownFixTimer =
        Timer.periodic(ownFixRefreshInterval, (_) => _refreshOwnFix());
    _setState(RadioConnectionState.ready);
    _rememberSelf();
    _requestDrain(); // catch anything that arrived during the handshake
  }

  Future<void> _runHandshake() async {
    final id = newPacketId();
    _configId = id;
    _configComplete = Completer<void>();
    loraConfig = null;
    channels.clear();
    configs.clear();
    moduleConfigs.clear();
    metadata = null;
    _configNodes = 0;
    _expectedNodes = 0;
    // On ESP32 radios iOS may show the PIN prompt on this first write
    // rather than on the subscribe, so it gets the pairing allowance too.
    await _write(pb.ToRadio(wantConfigId: id), timeout: _pairingTimeout);
    _setState(RadioConnectionState.configuring);
    _beginStep(RadioConnectionState.configuring, 'Reading radio settings');

    // Poll as well as relying on FromNum: some firmware doesn't notify for
    // the config stream.
    final poll = Timer.periodic(_handshakePoll, (_) => _requestDrain());
    _requestDrain();
    try {
      await _configComplete!.future.timeout(_handshakeTimeout);
    } on TimeoutException {
      throw TimeoutException('Node did not finish sending its config');
    } finally {
      poll.cancel();
    }
  }

  /// Run one connection step, naming it in any error so a failure says
  /// where it stopped (e.g. "Pairing (subscribe): Timed out after 90s").
  Future<T> _step<T>(String name, Future<T> step) async {
    try {
      return await step;
    } catch (e) {
      throw StateError('$name: $e');
    }
  }

  void _onLinkLost(int gen) {
    if (gen != _linkGen || !_wantConnected) return;
    print('MeshRadio: link lost');
    _teardown(sendDisconnect: false);
    // A drop during a reconnect's own handshake makes that _open fail and
    // the running loop retries; a second loop here would run two
    // handshakes on one link and leak the first one's timers.
    if (_reconnecting) return;
    _reconnectLoop(gen);
  }

  bool _reconnecting = false;

  Future<void> _reconnectLoop(int gen) async {
    if (_reconnecting) return;
    _reconnecting = true;
    try {
      await _reconnectAttempts(gen);
    } finally {
      _reconnecting = false;
    }
  }

  Future<void> _reconnectAttempts(int gen) async {
    var delay = AppConstants.bleReconnectInitialDelaySec;
    var attempt = 0;
    while (gen == _linkGen && _wantConnected && _descriptor != null) {
      _setState(RadioConnectionState.reconnecting);
      attempt++;
      final now = DateTime.now();
      _setProgress(ConnectProgress(
        state: RadioConnectionState.reconnecting,
        step: 'Waiting to retry',
        stepStartedAt: now,
        attempt: attempt,
        retryAt: now.add(Duration(seconds: delay)),
      ));
      await Future<void>.delayed(Duration(seconds: delay));
      if (gen != _linkGen || !_wantConnected) return;
      if (_state == RadioConnectionState.ready) return; // came back meanwhile
      try {
        await _open(_descriptor!.id, gen);
        return;
      } catch (e) {
        print('MeshRadio: reconnect failed: $e');
        DiagLog.instance.log('ble', 'reconnect failed: $e');
        await _teardown(sendDisconnect: false);
        if (isLostBondError(e)) {
          // The phone's pairing no longer matches the radio's: no retry
          // will ever succeed, only "Forget This Device" in iOS Settings.
          // Stop so the user gets the hint on the next manual connect
          // instead of "Retry N" for ever.
          DiagLog.instance.log('ble', 'lost bond: giving up reconnecting');
          _wantConnected = false;
          _setState(RadioConnectionState.disconnected);
          return;
        }
        delay = min(delay * 2, AppConstants.bleReconnectMaxDelaySec);
      }
    }
  }

  Future<void> _teardown({required bool sendDisconnect}) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _ownFixTimer?.cancel();
    _ownFixTimer = null;
    await _linkSub?.cancel();
    _linkSub = null;
    await _fromNumSub?.cancel();
    _fromNumSub = null;
    if (sendDisconnect && _hasLink) {
      try {
        await _write(pb.ToRadio(disconnect: true));
      } catch (_) {}
    }
    _hasLink = false;
    _failPendingPings();
    _transport.clearCharacteristics();
    _configId = null;
    final pending = _configComplete;
    _configComplete = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('Disconnected during config'));
      pending.future.ignore();
    }
    await _transport.disconnect();
  }

  // ─── Reading ─────────────────────────────────────────

  /// Single-flight read-until-empty drain of FromRadio.
  Future<void> _requestDrain() async {
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _drainAgain = false;
        while (true) {
          if (!_hasLink) return;
          final data = await _transport.read(fromRadioUuid);
          if (data.isEmpty) {
            _replaying = false;
            break;
          }
          _handleFrame(data);
        }
      } while (_drainAgain);
    } catch (e) {
      print('MeshRadio: drain error: $e');
    } finally {
      _draining = false;
    }
  }

  void _handleFrame(List<int> data) {
    final pb.FromRadio frame;
    try {
      frame = pb.FromRadio.fromBuffer(data);
    } catch (e) {
      print('MeshRadio: undecodable frame (${data.length} bytes): $e');
      return;
    }

    _handleFrameKind(frame);
    _configProgress();
  }

  void _handleFrameKind(pb.FromRadio frame) {
    switch (frame.whichPayloadVariant()) {
      case pb.FromRadio_PayloadVariant.myInfo:
        myNodeNum = frame.myInfo.myNodeNum;
        _expectedNodes = frame.myInfo.nodedbCount;
      case pb.FromRadio_PayloadVariant.nodeInfo:
        _updateNode(frame.nodeInfo);
        _configNodes++;
      case pb.FromRadio_PayloadVariant.config:
        configs[frame.config.whichPayloadVariant()] = frame.config;
        if (frame.config.hasLora()) loraConfig = frame.config.lora;
      case pb.FromRadio_PayloadVariant.moduleConfig:
        moduleConfigs[frame.moduleConfig.whichPayloadVariant()] =
            frame.moduleConfig;
      case pb.FromRadio_PayloadVariant.channel:
        channels[frame.channel.index] = frame.channel;
      case pb.FromRadio_PayloadVariant.metadata:
        metadata = frame.metadata;
      case pb.FromRadio_PayloadVariant.configCompleteId:
        if (frame.configCompleteId == _configId) {
          // What follows in this drain is the backlog, until a read comes
          // back empty.
          _replaying = true;
          final c = _configComplete;
          if (c != null && !c.isCompleted) c.complete();
        }
      case pb.FromRadio_PayloadVariant.packet:
        _handlePacket(frame.packet);
      default:
        break;
    }
  }

  void _handlePacket(pb.MeshPacket packet) {
    if (packet.hasDecoded()) {
      final data = packet.decoded;
      if (data.portnum == pb.PortNum.NODEINFO_APP) {
        try {
          final user =
              _keepTrustedKey(packet.from, pb.User.fromBuffer(data.payload));
          final node = (nodeInfos[packet.from] ?? pb.NodeInfo(num: packet.from))
              .deepCopy()
            ..user = user;
          _updateNode(node);
        } catch (_) {}
      } else if (data.portnum == pb.PortNum.POSITION_APP) {
        try {
          final pos = pb.Position.fromBuffer(data.payload);
          final node = (nodeInfos[packet.from] ?? pb.NodeInfo(num: packet.from))
              .deepCopy()
            ..position = pos;
          _updateNode(node);
        } catch (_) {}
      } else if (data.portnum == pb.PortNum.ROUTING_APP &&
          data.requestId != 0) {
        RoutingReply? reply;
        try {
          final routing = pb.Routing.fromBuffer(data.payload);
          reply = RoutingReply(
            requestId: data.requestId,
            error: routing.hasErrorReason()
                ? routing.errorReason
                : pb.Routing_Error.NONE,
            // error_reason (tag 3) with a value newer than our protos.
            unknownError: !routing.hasErrorReason() &&
                routing.unknownFields.hasField(_routingErrorTag),
            packet: packet,
          );
        } catch (e) {
          DiagLog.instance.log('radio', 'routing reply not parsed: $e');
        }
        if (reply != null) {
          // A failing listener must not cost the ping its reply, nor stop
          // the packet pipeline.
          try {
            _routingController.add(reply);
          } catch (e) {
            DiagLog.instance.log('radio', 'routing reply listener: $e');
          }
          try {
            _onPingReply(reply);
          } catch (e) {
            DiagLog.instance.log('radio', 'ping reply not handled: $e');
          }
        }
      } else if (data.portnum == pb.PortNum.ADMIN_APP) {
        try {
          _adminController.add(
              AdminReply(packet, pb.AdminMessage.fromBuffer(data.payload)));
        } catch (_) {}
      }
    }
    // Our own node's telemetry never becomes a ReceivedPacket (no over-the-air
    // signal), so read the radio's airtime figures before that filter.
    _publishChannelStats(
        channelStatsFromTelemetry(packet, myNodeNum: myNodeNum));
    // Before the handshake finishes, and in the drain right after it, the
    // radio is replaying what it buffered while the phone was away; those
    // are not "heard now" (bench 2026-10-26: two beacons from a 9-minute
    // Bluetooth outage were recorded at the reconnect time and place).
    final received = receivedPacketFrom(packet,
        myNodeNum: myNodeNum, queued: _replaying || !isReady);
    if (received != null) _packetController.add(received);
  }

  /// [user] as heard over the air from [from], with the public key we
  /// already trust for that node (the phone's saved contact, else the
  /// radio's node list) when it claims a different one. Like the firmware
  /// (which refuses a key change for a known node), first key wins: a
  /// NodeInfo with another key is someone else, or a reset radio that has
  /// to be set up again over Bluetooth (Radio Setup saves its new key).
  pb.User _keepTrustedKey(int from, pb.User user) {
    if (from == myNodeNum) return user; // our own radio, over the link
    final heard = user.publicKey;
    final saved = contacts?.get(from)?.publicKey;
    final known = nodeInfos[from];
    final trusted = saved != null && saved.length == 32
        ? saved
        : (known != null && known.hasUser() && known.user.publicKey.length == 32
            ? known.user.publicKey
            : null);
    if (trusted == null || heard.isEmpty || sameKey(trusted, heard)) {
      return user;
    }
    final msg = 'NodeInfo from ${nodeIdHex(from)} over the air claims key '
        '${keyPrefixHex(heard)}, kept ${keyPrefixHex(trusted)}';
    print('MeshRadio: $msg');
    DiagLog.instance.log('contacts', msg);
    return user.deepCopy()..publicKey = trusted;
  }

  void _updateNode(pb.NodeInfo node) {
    nodeInfos[node.num] = node;
    // The node DB value is only the last stored one: use it until a live
    // report arrives.
    if (_lastChannelStats == null) {
      _publishChannelStats(
          channelStatsFromNodeInfo(node, myNodeNum: myNodeNum));
    }
    final fix = ownFixFromNodeInfo(node, myNodeNum: myNodeNum);
    if (fix != null && !_ownFixController.isClosed) {
      _lastOwnFix = fix;
      _ownFixController.add(fix);
    }
    _nodeController.add(radioNodeFrom(node));
  }

  // ─── Writing ─────────────────────────────────────────

  Future<void> _write(pb.ToRadio msg, {Duration? timeout}) async {
    if (isDemo) throw StateError('Demo node: nothing is sent');
    if (!_hasLink) throw StateError('Not connected to a node');
    // One raw ToRadio protobuf per write, with response (no framing).
    await _transport.write(
      toRadioUuid,
      msg.writeToBuffer(),
      timeout: timeout ?? const Duration(seconds: 15),
    );
  }

  /// Estimate and publish the airtime of [packet] if it goes over the air.
  void _meterTx(pb.MeshPacket packet) {
    if (isDemo || packet.to == myNodeNum || _txAirtimeController.isClosed) {
      return;
    }
    final pki = packet.to != broadcastAddr;
    final bytes = 16 + packet.decoded.writeToBuffer().length + (pki ? 12 : 0);
    final params =
        AirtimeModel.paramsFor(currentPreset ?? AirtimeModel.defaultPreset);
    _txAirtimeController
        .add(AirtimeModel.airtimeMs(params, payloadBytes: bytes));
  }

  /// Random packet id, never 0 or 0xFFFFFFFF.
  int newPacketId() => _random.nextInt(0xFFFFFFFE) + 1;

  /// Send a text message. Returns the packet id so callers can match the
  /// ROUTING_APP reply (via [routingStream]) by `requestId`.
  Future<int> sendText(
    String text, {
    int to = broadcastAddr,
    int channel = 0,
    bool wantAck = true,
  }) async {
    if (!isReady) throw StateError('Node not ready');
    final id = newPacketId();
    final packet = pb.MeshPacket(
      id: id,
      to: to,
      channel: channel,
      wantAck: wantAck,
      decoded: pb.Data(
        portnum: pb.PortNum.TEXT_MESSAGE_APP,
        payload: utf8.encode(text),
      ),
    );
    await _write(pb.ToRadio(packet: packet));
    _meterTx(packet);
    return id;
  }

  /// Send a data packet with a caller-chosen [id] (from [newPacketId]) so
  /// the caller can register for its ACK before it goes out.
  Future<void> sendData({
    required int id,
    required int to,
    required pb.PortNum portnum,
    required List<int> payload,
    int channel = 0,
    bool wantAck = false,
    bool wantResponse = false,
    int? hopLimit,
  }) async {
    if (!isReady) throw StateError('Node not ready');
    final packet = buildDataPacket(
      id: id,
      to: to,
      portnum: portnum,
      payload: payload,
      channel: channel,
      wantAck: wantAck,
      wantResponse: wantResponse,
      hopLimit: hopLimit,
    );
    await _write(pb.ToRadio(packet: packet));
    _meterTx(packet);
  }

  /// Send our NodeInfo (name + public key) to [to] and ask for theirs, so
  /// both radios can encrypt direct messages to each other.
  Future<void> exchangeNodeInfo(int to) async {
    // Never announce ourselves on the public mesh (also covers the NAK
    // handler's resend).
    if (onPublicChannel) return;
    final me = myNodeNum == null ? null : nodeInfos[myNodeNum!];
    if (me == null || !me.hasUser()) return;
    await sendData(
      id: newPacketId(),
      to: to,
      portnum: pb.PortNum.NODEINFO_APP,
      payload: me.user.writeToBuffer(),
      wantResponse: true,
    );
  }

  @override
  Future<void> prepareToPing(int target) async {
    if (isDemo) return;
    _rememberNode(target);
    try {
      await ensureContact(target);
    } catch (e) {
      print('MeshRadio: add_contact failed: $e');
    }
    await exchangeNodeInfo(target);
  }

  /// Save our own user record, so the other radio can be given it.
  void _rememberSelf() {
    final num = myNodeNum;
    // Our own radio's record comes over the phone's link: its key may
    // replace a saved one (a reset radio has a new key).
    if (num != null) _rememberNode(num, replaceKey: true);
  }

  /// Save [num]'s user record. A key that differs from the saved one is
  /// only taken with [replaceKey] (our own radio, over Bluetooth).
  void _rememberNode(int num, {bool replaceKey = false}) {
    final node = nodeInfos[num];
    if (node != null && node.hasUser()) {
      contacts?.save(num, node.user, replaceKey: replaceKey);
    }
  }

  /// The connected radio has [num]'s public key. If it doesn't, but the
  /// phone has it saved, add it (AdminMessage.add_contact, firmware 2.6+).
  /// Returns whether the radio now has a key for [num]. [force] writes the
  /// saved key even when the phone's copy of the node list shows one: a
  /// local PKI NAK is proof the radio itself lacks it.
  Future<bool> ensureContact(int num, {bool force = false}) async {
    final node = nodeInfos[num];
    if (!force &&
        node != null &&
        node.hasUser() &&
        node.user.publicKey.length == 32) {
      return true;
    }
    final user = contacts?.get(num);
    if (user == null) return false;
    await addContact(num, user);
    return true;
  }

  /// Write [user] (with its public key) into the radio's node list.
  Future<void> addContact(int num, pb.User user) async {
    await sendAdmin(pb.AdminMessage(
      addContact: pb.SharedContact(nodeNum: num, user: user),
    ));
    nodeInfos[num] = (nodeInfos[num]?.deepCopy() ?? pb.NodeInfo(num: num))
      ..user = user;
  }

  // ─── Ping ────────────────────────────────────────────

  @override
  Future<PingOutcome> ping(
    int target, {
    Duration timeout =
        const Duration(seconds: AppConstants.defaultAckTimeoutSec),
    int channel = 0,
    FutureOr<void> Function(int pingId)? beforeSend,
  }) async {
    final id = newPacketId();
    final clock = Stopwatch()..start();
    PingOutcome failed(String reason) => PingOutcome(
          pingId: id,
          status: PingStatus.error,
          errorReason: reason,
          roundTrip: clock.elapsed,
        );
    if (isDemo) return failed('DEMO_RADIO');
    // Never test on the public channel (ActiveProbeService checks first).
    // Not ready: the channel table isn't known and the send fails anyway.
    if (isReady && onPublicChannel) return failed('PUBLIC_CHANNEL');

    try {
      await beforeSend?.call(id);

      // Register before sending, so even a very fast ACK finds it.
      final pending = _PendingPing(target, clock, Completer<PingOutcome>());
      pending.timeout = Timer(timeout, () {
        if (_pendingPings.remove(id) != null) {
          pending.completer.complete(PingOutcome(
            pingId: id,
            status: PingStatus.timeout,
            roundTrip: clock.elapsed,
          ));
        }
      });
      _pendingPings[id] = pending;

      try {
        // PRIVATE_APP rather than a text message, so the base doesn't show
        // a "ping" notification every interval. The firmware ACKs any DM
        // with want_ack regardless of port.
        await sendData(
          id: id,
          to: target,
          portnum: pb.PortNum.PRIVATE_APP,
          payload: 'ping'.codeUnits,
          channel: channel,
          wantAck: true,
          hopLimit: pingHopLimit,
        );
      } catch (_) {
        _pendingPings.remove(id)?.timeout?.cancel();
        rethrow;
      }
      return await pending.completer.future;
    } catch (e) {
      print('MeshRadio: ping failed: $e');
      return failed('SEND_FAILED');
    }
  }

  /// Complete the pending ping that [reply] answers (ignored when it isn't
  /// one of ours).
  void _onPingReply(RoutingReply reply) {
    final pending = _pendingPings.remove(reply.requestId);
    if (pending == null) return;
    pending.timeout?.cancel();

    final packet = reply.packet;
    final PingStatus status;
    String? errorReason;
    // An ACK from the destination itself means delivered; an ACK from any
    // other node is an implicit ack (a relay was heard rebroadcasting it).
    if (!reply.isAck &&
        packet.from == myNodeNum &&
        AckStatus.noReplyReasons.contains(reply.errorName)) {
      // Our radio sent it, retried, and heard no ACK: that is a timeout
      // (the base didn't answer), not a refusal to send.
      status = PingStatus.timeout;
      errorReason = reply.errorName;
      print('MeshRadio: ping unanswered (${reply.errorName})');
    } else if (!reply.isAck) {
      if (AckStatus.throttleReasons.contains(reply.errorName)) {
        status = PingStatus.throttled;
      } else {
        status = PingStatus.error;
      }
      errorReason = reply.errorName;
      // A key is missing on one side. PKI_SEND_FAIL_PUBLIC_KEY (firmware
      // 2.7.19+) is our own radio refusing to send because it lacks the
      // base's key: nothing went on air, and the NAK comes from our node.
      // PKI_UNKNOWN_PUBKEY / PKI_FAILED come back from the base when it
      // can't decrypt ours. Either way: give our radio the base's saved
      // key (forced on a local NAK, whatever the phone's node cache says)
      // and resend our NodeInfo, at most once a minute.
      if (reply.error == pb.Routing_Error.PKI_SEND_FAIL_PUBLIC_KEY ||
          reply.error == pb.Routing_Error.PKI_UNKNOWN_PUBKEY ||
          reply.error == pb.Routing_Error.PKI_FAILED) {
        final now = DateTime.now();
        if (_lastKeyExchange == null ||
            now.difference(_lastKeyExchange!).inSeconds >= 60) {
          _lastKeyExchange = now;
          final local = packet.from == myNodeNum;
          ensureContact(pending.target, force: local)
              .catchError((_) => false)
              .then((_) => exchangeNodeInfo(pending.target))
              .catchError((_) {});
        }
      }
      print('MeshRadio: ping NAK ${reply.errorName}');
    } else if (packet.from == pending.target) {
      status = PingStatus.received;
    } else {
      status = PingStatus.implicit;
    }

    pending.completer.complete(PingOutcome(
      pingId: reply.requestId,
      status: status,
      errorReason: errorReason,
      responder: packet.from,
      replyPacketId: packet.id,
      snr: _rxSnrOf(packet),
      rssi: _rxRssiOf(packet),
      hops: _hopsOf(packet),
      roundTrip: pending.clock.elapsed,
    ));
  }

  // ─── Admin / configuration ───────────────────────────

  // Protobuf tag numbers (config.proto / mesh.proto) of enum fields whose
  // value may be newer than the vendored protos know.
  static const _loraModemPresetTag = 2;
  static const _loraRegionTag = 7;
  static const _deviceRoleTag = 1;
  static const _deviceRebroadcastModeTag = 6;
  static const _routingErrorTag = 3;

  /// Forget the raw value of [tags] in [msg] that the vendored protos don't
  /// know (an enum value from a newer firmware than lib/proto/UPSTREAM.md).
  /// Dart keeps such a value as an unknown field and writes it *after* the
  /// value we set; the firmware takes the last one, so the change would
  /// silently not stick.
  static void _dropUnknown(GeneratedMessage msg, List<int> tags) {
    for (final tag in tags) {
      msg.unknownFields.clearField(tag);
    }
  }

  /// Send an admin message to the connected radio itself and wait for its
  /// ACK. Throws on NAK or if no reply arrives within [timeout].
  ///
  /// A write the radio never answers is sent again, [retries] times, with a
  /// fresh packet id: one lost reply (a solar node mid-setup, 2026-10-24)
  /// shouldn't end Radio Setup with the radio half-configured. A NAK is
  /// never retried, nor is anything once the link has dropped.
  ///
  /// Local admin over BLE needs no session passkey.
  Future<void> sendAdmin(
    pb.AdminMessage msg, {
    Duration timeout = const Duration(seconds: 10),
    int retries = 1,
  }) async {
    for (var attempt = 0;; attempt++) {
      try {
        await sendAdminAttempt(msg, timeout: timeout);
        return;
      } on TimeoutException {
        if (attempt >= retries || !isReady) rethrow;
        print('MeshRadio: admin write unanswered, sending it again');
      }
    }
  }

  /// One send of [msg] and one wait for its ACK (what [sendAdmin] retries).
  @protected
  Future<void> sendAdminAttempt(
    pb.AdminMessage msg, {
    required Duration timeout,
  }) async {
    if (!isReady || myNodeNum == null) throw StateError('Node not ready');
    final id = newPacketId();
    // Listen before writing so a fast ACK isn't missed.
    final reply =
        routingStream.firstWhere((r) => r.requestId == id).timeout(timeout);
    await _write(pb.ToRadio(
      packet: pb.MeshPacket(
        id: id,
        to: myNodeNum,
        wantAck: true,
        decoded: pb.Data(
          portnum: pb.PortNum.ADMIN_APP,
          payload: msg.writeToBuffer(),
        ),
      ),
    ));
    final r = await reply;
    if (!r.isAck) throw StateError('Node rejected setting: ${r.errorName}');
  }

  /// Make the radio forget every node it has heard except itself and
  /// [keep] (marked as favourites first, which the reset preserves).
  /// Returns how many nodes it forgot. The radio restarts afterwards and the
  /// app reconnects on its own. Firmware before 2.7.14 ignores "keep
  /// favourites" and forgets [keep] too; they come back when heard again.
  Future<int> resetNodeDb({Iterable<int> keep = const []}) async {
    final kept = {...keep}..remove(myNodeNum);
    for (final num in kept) {
      await sendAdmin(pb.AdminMessage(setFavoriteNode: num));
    }
    final forgotten = nodeInfos.keys
        .where((n) => n != myNodeNum && !kept.contains(n))
        .toList();
    try {
      await sendAdmin(pb.AdminMessage(nodedbReset: true));
    } on TimeoutException {
      // Restarted before it could ACK.
    } on StateError catch (e) {
      if (isReady) rethrow; // a real NAK, not a restart
      print('MeshRadio: node-db reset reply lost to restart: $e');
    }
    for (final n in forgotten) {
      nodeInfos.remove(n);
    }
    return forgotten.length;
  }

  /// Commit a beginEditSettings batch. The radio usually reboots, which can
  /// drop Bluetooth before the ACK arrives; that counts as success.
  Future<void> commitSettings() async {
    // Only a commit that was actually written can be "lost to the reboot".
    // With the link already gone nothing was saved: the settings written so
    // far are in RAM (2.7) or will be auto-committed piecemeal after 60 s
    // idle (2.8), and the caller must not report success.
    if (!isReady) {
      throw StateError('Lost the Bluetooth link to the node before it could '
          'save: nothing was saved. Power-cycle it and run Node Setup again.');
    }
    try {
      // No retry: silence here is the reboot, not a lost reply.
      await sendAdmin(pb.AdminMessage(commitEditSettings: true), retries: 0);
    } on TimeoutException {
      // Rebooted before it could ACK.
    } on StateError catch (e) {
      if (isReady) rethrow; // a real NAK, not a reboot
      print('MeshRadio: commit reply lost to reboot: $e');
    }
  }

  /// Restart the radio (firmware reboot after [afterSeconds]). The ACK can
  /// be lost to the reboot itself, which counts as success; the app
  /// reconnects on its own. A restart re-arms a Range Test sender's 8-hour
  /// clock.
  Future<void> reboot({int afterSeconds = 1}) async {
    try {
      await sendAdmin(pb.AdminMessage(rebootSeconds: afterSeconds), retries: 0);
    } on TimeoutException {
      // Rebooted before it could ACK.
    }
  }

  /// The LoRa config [applyTestProfile] writes for [profile].
  ///
  /// Each radio keeps its own LoRa settings (tx power, crystal offset…)
  /// with the chosen preset and region. channelNum 0 and no frequency
  /// override let the firmware pick the slot from the channel name, which
  /// both radios share, so they always land on the same frequency.
  pb.Config_LoRaConfig _testLora(TestProfile profile) {
    final modemPreset = MeshtasticPresets.toModemPreset(profile.preset.id);
    if (modemPreset == null) {
      throw ArgumentError('Not a Meshtastic preset: ${profile.preset.id}');
    }
    final lora = (loraConfig?.deepCopy() ?? pb.Config_LoRaConfig(hopLimit: 3))
      ..usePreset = true
      ..modemPreset = modemPreset
      ..region = _regionFor(profile)
      ..channelNum = 0
      ..clearOverrideFrequency()
      ..txEnabled = true;
    _dropUnknown(lora, [_loraModemPresetTag, _loraRegionTag]);
    return lora;
  }

  @override
  RadioSettings? settingsAfter(TestProfile profile) {
    final caps = capabilities;
    return MeshtasticFrequency.settingsFor(
      _testLora(profile),
      primaryChannel: pb.Channel(
        role: pb.Channel_Role.PRIMARY,
        settings: pb.ChannelSettings(name: profile.channelName),
      ),
      firmware28:
          caps.firmwareVersion.isEmpty ? null : caps.firmwareAtLeast(2, 8),
    );
  }

  /// Admin sequence (as in coachella-mesh): beginEdit → setChannel × 8 →
  /// setConfig(lora) → setConfig(device) → setModuleConfig(telemetry) →
  /// setModuleConfig(rangeTest) → commitEdit. The commit reboots the radio,
  /// which may drop BLE before the ACK; that counts as success.
  ///
  /// The base gets one beacon: device telemetry where Range Test is gone
  /// (firmware 2.8, or reported excluded), Range Test otherwise. Returns
  /// the beacon written (null for the mobile).
  ///
  /// [remoteAdminKey] (a base only): the mobile radio's public key goes
  /// into `security.admin_key` in the same transaction, so the mobile can
  /// change this radio over the mesh later ([setRemoteLora]) and the
  /// radio reboots once, not twice. Nothing is written when it is there
  /// already. [onRemoteAdmin] says whether the key is in the list after
  /// the commit (false when the security settings couldn't be read, or
  /// the list was full and [confirmReplaceAdminKey] didn't say to replace
  /// its oldest key; without it a full list is left alone).
  @override
  Future<BeaconConfig?> applyTestProfile(
    TestProfile profile, {
    void Function(String step)? onStep,
    List<int>? remoteAdminKey,
    void Function(bool granted)? onRemoteAdmin,
    ReplaceAdminKeyPrompt? confirmReplaceAdminKey,
  }) async {
    void step(String s) => onStep?.call(s);
    final lora = _testLora(profile);

    // Read before the edit begins, so the transaction holds only writes.
    pb.Config? security;
    var remoteGranted = false;
    if (remoteAdminKey != null && profile.isBase) {
      try {
        security = await _securityWithAdminKey(remoteAdminKey,
            confirmReplace: confirmReplaceAdminKey);
        remoteGranted = true; // present already, or written below
      } on AdminKeyListFull catch (e) {
        step('Remote changes not set up: the base node already has '
            '$maxAdminKeys admin keys and none was replaced');
        DiagLog.instance.log('admin', 'remote admin grant skipped: $e');
      } catch (e) {
        step('Remote changes not set up: ${userMessage(e)}');
        DiagLog.instance.log('admin', 'remote admin grant skipped: $e');
      }
    }

    // Test radios never relay third parties' traffic.
    // A plain client: TRACKER/SENSOR change broadcast priority and sleep,
    // ROUTER roles change relaying, CLIENT_HIDDEN never beacons. Backups
    // keep the original role, so Restore puts it back.
    final device = (configs[pb.Config_PayloadVariant.device]
            ?.device
            .deepCopy() ??
        pb.Config_DeviceConfig())
      ..role = pb.Config_DeviceConfig_Role.CLIENT
      ..rebroadcastMode = pb.Config_DeviceConfig_RebroadcastMode.LOCAL_ONLY;
    _dropUnknown(device, [_deviceRoleTag, _deviceRebroadcastModeTag]);

    final beacon = profile.isBase
        ? (profile.beacon ?? const BeaconConfig.off()).resolved(capabilities)
        : null;
    final kind = beacon?.activeKind ?? BeaconKind.none;

    // Other telemetry settings stay as the owner had them; only the device
    // broadcast changes. On the base it is the beacon, everywhere else off.
    final telemetry = (moduleConfigs[pb.ModuleConfig_PayloadVariant.telemetry]
            ?.telemetry
            .deepCopy() ??
        pb.ModuleConfig_TelemetryConfig())
      ..deviceTelemetryEnabled = kind == BeaconKind.telemetry;
    if (kind == BeaconKind.telemetry) {
      telemetry.deviceUpdateInterval = beacon!.intervalSec;
    }

    final rangeTest = profile.isBase
        ? pb.ModuleConfig_RangeTestConfig(
            enabled: kind == BeaconKind.rangeTest,
            sender: kind == BeaconKind.rangeTest ? beacon!.intervalSec : 0,
          )
        // Receiver only: Range Test on, not sending.
        : pb.ModuleConfig_RangeTestConfig(enabled: true, sender: 0);

    step('Writing private channel "${profile.channelName}"…');
    await sendAdmin(pb.AdminMessage(beginEditSettings: true));
    for (final channel in _testChannels(profile)) {
      await sendAdmin(pb.AdminMessage(setChannel: channel));
    }

    step('Writing ${lora.modemPreset.name} / ${lora.region.name}…');
    await sendAdmin(pb.AdminMessage(setConfig: pb.Config(lora: lora)));

    step('Keeping this node from relaying other networks…');
    await sendAdmin(pb.AdminMessage(setConfig: pb.Config(device: device)));

    // The mobile's GPS stands in for a phone without one (a Wi-Fi iPad):
    // on, and fixing every 30 s. Bluetooth only to the phone; the backup
    // keeps the old settings for Restore.
    final gps = profile.isBase
        ? null
        : mobileGpsConfig(configs[pb.Config_PayloadVariant.position]?.position);
    if (gps != null) {
      step('Turning on this node\'s GPS (a fix every '
          '${gps.gpsUpdateInterval} s)…');
      await sendAdmin(pb.AdminMessage(setConfig: pb.Config(position: gps)));
    }

    if (remoteAdminKey != null && profile.isBase) {
      if (security != null) {
        step('Allowing the mobile node to change this base from a distance…');
        await sendAdmin(pb.AdminMessage(setConfig: security));
      } else if (remoteGranted) {
        step('The mobile node may already change this base from a distance');
      }
      onRemoteAdmin?.call(remoteGranted);
    }

    step(switch (kind) {
      BeaconKind.telemetry =>
        'Base beacon: telemetry every ${beacon!.intervalSec}s…',
      BeaconKind.rangeTest =>
        'Base beacon: test signal every ${beacon!.intervalSec}s…',
      BeaconKind.none =>
        profile.isBase ? 'Base beacon: off…' : 'Base beacon: listening only…',
      // Not a Meshtastic beacon; nothing is written for it.
      BeaconKind.trace => 'Base beacon: off…',
    });
    await sendAdmin(pb.AdminMessage(
      setModuleConfig: pb.ModuleConfig(telemetry: telemetry),
    ));
    await sendAdmin(pb.AdminMessage(
      setModuleConfig: pb.ModuleConfig(rangeTest: rangeTest),
    ));

    final longName = profile.radioLongName;
    final shortName = profile.radioShortName;
    if (longName != null && shortName != null) {
      step('Naming it "$longName" ($shortName)…');
      // Start from the radio's own user record so only the names change.
      final me = myNodeNum == null ? null : nodeInfos[myNodeNum!];
      final owner =
          (me != null && me.hasUser() ? me.user.deepCopy() : pb.User())
            ..longName = longName
            ..shortName = shortName;
      await sendAdmin(pb.AdminMessage(setOwner: owner));
    }

    step('Saving — the node restarts…');
    await commitSettings();
    step('Done');
    return beacon;
  }

  /// An out-of-the-box radio: it reported its LoRa settings and the region
  /// is UNSET, so its firmware won't transmit until one is chosen.
  bool get regionUnset =>
      loraConfig != null &&
      loraConfig!.region == pb.Config_LoRaConfig_RegionCode.UNSET;

  /// Set the LoRa region ([code] is a `RegionCode` name, e.g. `EU_868`),
  /// keeping every other LoRa setting. Transmit is switched on (a new
  /// radio has it off until it has a region). The radio reboots and the
  /// app reconnects on its own.
  Future<void> setRegion(String code) async {
    final region = pb.Config_LoRaConfig_RegionCode.values.firstWhere(
        (r) => r.name == code && r != pb.Config_LoRaConfig_RegionCode.UNSET,
        orElse: () => throw ArgumentError('Unknown region: $code'));
    final lora = (loraConfig?.deepCopy() ??
        pb.Config_LoRaConfig(usePreset: true, hopLimit: 3))
      ..region = region
      ..txEnabled = true;
    _dropUnknown(lora, [_loraRegionTag]);
    await sendAdmin(pb.AdminMessage(beginEditSettings: true));
    await sendAdmin(pb.AdminMessage(setConfig: pb.Config(lora: lora)));
    await commitSettings();
    loraConfig = lora;
  }

  /// Region to write: the profile's, else the radio's own, else US.
  pb.Config_LoRaConfig_RegionCode _regionFor(TestProfile profile) {
    final wanted = profile.regionName;
    if (wanted != null && wanted.isNotEmpty) {
      for (final r in pb.Config_LoRaConfig_RegionCode.values) {
        if (r.name == wanted && r != pb.Config_LoRaConfig_RegionCode.UNSET) {
          return r;
        }
      }
    }
    final r = loraConfig?.region;
    return (r == null || r == pb.Config_LoRaConfig_RegionCode.UNSET)
        ? pb.Config_LoRaConfig_RegionCode.US
        : r;
  }

  List<pb.Channel> _testChannels(TestProfile profile) => [
        pb.Channel(
          index: 0,
          role: pb.Channel_Role.PRIMARY,
          settings: pb.ChannelSettings(
            name: profile.channelName,
            psk: profile.channelKey,
            uplinkEnabled: false,
            downlinkEnabled: false,
            moduleSettings: pb.ModuleSettings(positionPrecision: 32),
          ),
        ),
        // Everything else off, including the public channel.
        for (var i = 1; i < 8; i++)
          pb.Channel(index: i, role: pb.Channel_Role.DISABLED),
      ];

  // ─── Remote administration (guided test, design §5) ─────────────────
  //
  // Firmware facts (src/modules/AdminModule.cpp at v2.8.1.8e6a88d, the
  // bench radios' version; master 6d41e27 agrees):
  //  * A PKI-encrypted ADMIN_APP packet is authorised when the sender's
  //    public key is one of the up to three `security.admin_key`s
  //    (handleReceivedProtobuf l.189-225; otherwise NAK
  //    ADMIN_PUBLIC_KEY_UNAUTHORIZED). The legacy "admin" channel is a
  //    separate branch we never use. Local admin (from == 0, the phone's
  //    link) skips both.
  //  * Every state-changing message from another node must echo the
  //    8-byte `session_passkey` the node put on its last get_* response
  //    (l.239-243 → NAK ADMIN_BAD_SESSION_KEY; checkPassKey: valid 300 s,
  //    setPassKey regenerates it when older than 150 s). get_* requests
  //    and responses need none; neither does local admin.
  //  * commit_edit_settings saves and reboots (l.485-490; saveChanges'
  //    shouldReboot defaults to true, AdminModule.h l.58), so the ACK can
  //    be lost to the reboot. A LoRa set applies live on 2.8 (l.1122
  //    requiresReboot = false; 2.7 rebooted) and a security set always
  //    asks for a reboot (l.1235); inside an open transaction both wait
  //    for the commit (l.1243, saveChanges l.1864). An abandoned
  //    transaction commits itself without a reboot after 60 s idle.
  //  * Our own radio only hands a get_* response to the phone when it
  //    sent the matching request (MeshService.cpp l.335
  //    noteOutgoingAdminRequest; responseIsSolicited matches `to`,
  //    `request_id` and the key), which phone-originated packets are.
  //  * A DM is PKI-encrypted whenever we hold the destination's key
  //    (Router.cpp wouldEncryptWithPKC l.1189); without it the send fails
  //    locally with PKI_SEND_FAIL_PUBLIC_KEY (l.1354). The Python CLI
  //    sets pki_encrypted on remote admin; so do we (never channel-encoded).

  @override
  bool get supportsRemoteAdmin => true;

  /// Add [publicKey] to this radio's `security.admin_key` over the phone's
  /// link (local admin: no passkey). Nothing is written when the key is
  /// in the list already; otherwise begin → set_config(security) → commit,
  /// and the radio reboots (a lost commit ACK counts as saved, like Radio
  /// Setup). Radio Setup's base flow uses [applyTestProfile]'s
  /// `remoteAdminKey` instead, so the base reboots once.
  ///
  /// A full admin list throws [AdminKeyListFull] unless [confirmReplace]
  /// says to replace its oldest key.
  @override
  Future<void> grantRemoteAdmin(
    List<int> publicKey, {
    void Function(String step)? onStep,
    ReplaceAdminKeyPrompt? confirmReplace,
  }) async {
    final security =
        await _securityWithAdminKey(publicKey, confirmReplace: confirmReplace);
    if (security == null) {
      onStep?.call('This node already accepts changes from that key');
      return;
    }
    onStep?.call('Allowing changes from a distance…');
    await sendAdmin(pb.AdminMessage(beginEditSettings: true));
    await sendAdmin(pb.AdminMessage(setConfig: security));
    onStep?.call('Saving — the node restarts…');
    await commitSettings();
    configs[pb.Config_PayloadVariant.security] = security;
  }

  /// Take [publicKey] out of this radio's `security.admin_key` over the
  /// phone's link (local admin), so that radio can no longer change this
  /// one from a distance. begin → set_config(security, same record with the
  /// shorter list) → commit; the radio reboots. Returns false (nothing
  /// written) when the key isn't in the list.
  Future<bool> revokeRemoteAdmin(
    List<int> publicKey, {
    void Function(String step)? onStep,
  }) async {
    final current = await _readLocalSecurity();
    final keys =
        adminKeysWithout([for (final k in current.adminKey) k], publicKey);
    if (keys == null) {
      onStep?.call('This node does not accept changes from that key');
      return false;
    }
    final security = _securityWith(current, keys);
    onStep?.call('Removing the mobile node\'s admin access…');
    await sendAdmin(pb.AdminMessage(beginEditSettings: true));
    await sendAdmin(pb.AdminMessage(setConfig: security));
    onStep?.call('Saving; the node restarts…');
    await commitSettings();
    configs[pb.Config_PayloadVariant.security] = security;
    DiagLog.instance
        .log('admin', 'admin key ${keyPrefixHex(publicKey)} removed');
    return true;
  }

  /// The admin keys from the config download (what a backup saves), or
  /// null when the radio didn't send its security settings.
  List<List<int>>? get downloadedAdminKeys {
    final c = configs[pb.Config_PayloadVariant.security];
    if (c == null || !c.hasSecurity()) return null;
    return [for (final k in c.security.adminKey) List<int>.of(k)];
  }

  /// This radio's security settings with the admin list [edit] makes of
  /// the current one (a restore), read fresh so the identity keypair is
  /// written back unchanged. The config is null when the list stays the
  /// same; the list is what the radio holds afterwards.
  Future<(pb.Config?, List<List<int>>)> securityWithAdminKeys(
      List<List<int>> Function(List<List<int>> current) edit) async {
    final current = await _readLocalSecurity();
    final before = [for (final k in current.adminKey) List<int>.of(k)];
    final keys = edit(before);
    if (sameKeyList(before, keys)) return (null, keys);
    return (_securityWith(current, keys), keys);
  }

  /// This radio's security settings with [publicKey] added to the admin
  /// list, ready to write back, or null when it is there already. A full
  /// list throws [AdminKeyListFull] unless [confirmReplace] agrees to
  /// replace its oldest key.
  Future<pb.Config?> _securityWithAdminKey(
    List<int> publicKey, {
    ReplaceAdminKeyPrompt? confirmReplace,
  }) async {
    if (publicKey.length != 32) {
      throw ArgumentError('A public key is 32 bytes, not ${publicKey.length}');
    }
    final current = await _readLocalSecurity();
    final own = current.publicKey;
    if (own.length == 32 && sameKey(own, publicKey)) {
      throw ArgumentError('That is this node\'s own key');
    }
    final existing = [for (final k in current.adminKey) k];
    List<List<int>>? keys;
    try {
      keys = adminKeysWith(existing, publicKey, ownKey: own);
    } on AdminKeyListFull catch (full) {
      final replace =
          confirmReplace != null && await confirmReplace(full.oldestHex);
      if (!replace) rethrow;
      keys = adminKeysWith(
        existing,
        publicKey,
        ownKey: own,
        replaceOldest: true,
        onReplace: (k) {
          final msg = 'admin_key list full: replacing ${keyPrefixHex(k)} '
              'with ${keyPrefixHex(publicKey)} (user agreed)';
          print('MeshRadio: $msg');
          DiagLog.instance.log('admin', msg);
        },
      );
    }
    if (keys == null) return null;
    return _securityWith(current, keys);
  }

  /// [current] with [keys] as its admin list, as a config to write.
  pb.Config _securityWith(
      pb.Config_SecurityConfig current, List<List<int>> keys) {
    // Firmware regenerates the keypair when a security set arrives
    // without the private key (2.7; 2.8.1 keeps it, l.1180), and on 2.8 the
    // node number is derived from the key. Never write back a half-read
    // record.
    if (current.publicKey.length == 32 && current.privateKey.length != 32) {
      throw StateError('The node did not hand over its private key, so '
          'its security settings can\'t be written back safely');
    }
    final updated = current.deepCopy()
      ..adminKey.clear()
      ..adminKey.addAll(keys);
    return pb.Config(security: updated);
  }

  /// The radio's current security settings: asked for fresh
  /// (get_config_request SECURITY_CONFIG; a local request gets the private
  /// key too, AdminModule.cpp l.1562), falling back to the copy from the
  /// config download when the request goes unanswered.
  Future<pb.Config_SecurityConfig> _readLocalSecurity() async {
    try {
      final c =
          await _getLocalConfig(pb.AdminMessage_ConfigType.SECURITY_CONFIG);
      if (c.hasSecurity()) return c.security;
    } on TimeoutException catch (e) {
      print('MeshRadio: $e; using the security settings from connect');
    }
    final downloaded = configs[pb.Config_PayloadVariant.security];
    if (downloaded != null && downloaded.hasSecurity()) {
      return downloaded.security;
    }
    throw StateError('The node did not report its security settings');
  }

  /// Ask the connected radio for one of its config sections and wait for
  /// the get_config_response (matched by request id).
  Future<pb.Config> _getLocalConfig(
    pb.AdminMessage_ConfigType type, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!isReady || myNodeNum == null) throw StateError('Node not ready');
    final id = newPacketId();
    final reply = adminStream
        .firstWhere(
            (r) => r.requestId == id && r.message.hasGetConfigResponse())
        .timeout(timeout,
            onTimeout: () => throw TimeoutException(
                'The node did not answer the ${type.name} request'));
    try {
      await _write(pb.ToRadio(
        packet: pb.MeshPacket(
          id: id,
          to: myNodeNum,
          decoded: pb.Data(
            portnum: pb.PortNum.ADMIN_APP,
            payload: pb.AdminMessage(getConfigRequest: type).writeToBuffer(),
            wantResponse: true,
          ),
        ),
      ));
    } catch (_) {
      reply.ignore();
      rethrow;
    }
    return (await reply).message.getConfigResponse;
  }

  /// Change node [nodeNum]'s modem preset and/or TX power over the mesh.
  ///
  /// Sequence (each step waits for the node's own answer, at most
  /// [remoteExchangeTimeout]): get_config_request(LORA) with want_response
  /// → its response carries the session passkey and the current LoRa
  /// settings → begin_edit_settings → set_config(lora: as read, with the
  /// preset and/or power changed) → commit_edit_settings, every one with
  /// the passkey. The commit reboots the node, so its lost ACK counts as
  /// sent. [txPowerDbm] 0 means "maximum" to the firmware and is passed
  /// through unchanged.
  ///
  /// Throws [ArgumentError] for nothing to change or a non-Meshtastic
  /// preset, [RemoteAdminNak] (a [StateError]) on a NAK — after one
  /// retry when a key was missing on either side, like pings — and
  /// [TimeoutException] when the node stays silent.
  @override
  Future<void> setRemoteLora(
    int nodeNum, {
    RadioPreset? preset,
    int? txPowerDbm,
    void Function(String step)? onStep,
  }) async {
    void step(String s) => onStep?.call(s);
    if (preset == null && txPowerDbm == null) {
      throw ArgumentError('Nothing to change: give a preset or a power');
    }
    pb.Config_LoRaConfig_ModemPreset? modem;
    if (preset != null) {
      modem = MeshtasticPresets.toModemPreset(preset.id);
      if (modem == null) {
        throw ArgumentError('Not a Meshtastic preset: ${preset.id}');
      }
    }
    if (isDemo) throw StateError('Demo node: nothing is sent');
    if (!isReady || myNodeNum == null) throw StateError('Node not ready');
    if (nodeNum == myNodeNum) {
      throw ArgumentError('That is this node itself; use Node Setup');
    }
    // Never on the public channel (the same rule as pings): remote admin
    // goes out on channel 0.
    if (onPublicChannel) throw StateError(publicChannelRefusal);

    // Our radio PKI-encrypts the request only with the base's key.
    try {
      await ensureContact(nodeNum);
    } catch (e) {
      print('MeshRadio: add_contact before remote admin failed: $e');
    }

    var retried = false;
    while (true) {
      try {
        await _setRemoteLoraOnce(nodeNum,
            modem: modem, txPowerDbm: txPowerDbm, preset: preset, step: step);
        return;
      } on RemoteAdminNak catch (e) {
        if (retried || !e.isKeyProblem) rethrow;
        retried = true;
        step('A key is missing on one side; swapping keys and trying again…');
        DiagLog.instance.log(
            'admin',
            'remote admin NAK ${e.errorName}, '
                'swapping keys with ${nodeIdHex(nodeNum)} and retrying');
        // A local NAK is proof our radio lacks the key, whatever the
        // phone's node cache says; the base's NAK means it lacks ours.
        await ensureContact(nodeNum, force: e.from == myNodeNum)
            .catchError((_) => false);
        try {
          await exchangeNodeInfo(nodeNum);
        } catch (_) {}
      }
    }
  }

  Future<void> _setRemoteLoraOnce(
    int nodeNum, {
    required pb.Config_LoRaConfig_ModemPreset? modem,
    required int? txPowerDbm,
    required RadioPreset? preset,
    required void Function(String) step,
  }) async {
    final name = _nodeLabel(nodeNum);
    step('Asking $name for its settings…');
    final answer = await _remoteAdmin(
      nodeNum,
      pb.AdminMessage(getConfigRequest: pb.AdminMessage_ConfigType.LORA_CONFIG),
      wantResponse: true,
    );
    final reply = answer.response!.message;
    if (!reply.getConfigResponse.hasLora()) {
      throw StateError('$name answered without its LoRa settings');
    }
    final passkey = reply.sessionPasskey;
    final lora = reply.getConfigResponse.lora.deepCopy();
    if (modem != null) {
      lora
        ..usePreset = true
        ..modemPreset = modem;
      _dropUnknown(lora, [_loraModemPresetTag]);
    }
    if (txPowerDbm != null) lora.txPower = txPowerDbm;

    final what = [
      if (preset != null) 'switching to ${preset.displayName}',
      if (txPowerDbm != null)
        txPowerDbm == 0 ? 'full power' : 'power $txPowerDbm dBm',
    ].join(', ');
    step('$name: $what…');
    await _remoteAdmin(
      nodeNum,
      pb.AdminMessage(beginEditSettings: true, sessionPasskey: passkey),
    );
    await _remoteAdmin(
      nodeNum,
      pb.AdminMessage(
          setConfig: pb.Config(lora: lora), sessionPasskey: passkey),
    );
    step('$name: saving — it restarts…');
    try {
      await _remoteAdmin(
        nodeNum,
        pb.AdminMessage(commitEditSettings: true, sessionPasskey: passkey),
      );
    } on TimeoutException {
      // The commit reboots the node, which can take its ACK with it; the
      // two writes before it were acknowledged, so the change is in.
      step('$name did not confirm the save; it is restarting with the new '
          'settings');
      DiagLog.instance.log(
          'admin', 'commit ACK from ${nodeIdHex(nodeNum)} lost to the reboot');
    }
    step('Done');
  }

  /// Send [msg] to [nodeNum] over the mesh (PKI, want_ack) and wait for
  /// its answer: the ADMIN_APP response when [wantResponse], else the
  /// ROUTING_APP ACK from [nodeNum] itself (a relay's implicit ACK is no
  /// proof it arrived). A NAK from anyone, our own radio included, throws
  /// [RemoteAdminNak]; silence throws [TimeoutException] after
  /// [remoteExchangeTimeout].
  Future<_RemoteAnswer> _remoteAdmin(
    int nodeNum,
    pb.AdminMessage msg, {
    bool wantResponse = false,
  }) async {
    final id = newPacketId();
    // Listen before writing so a fast answer isn't missed.
    final answer = _awaitRemoteAnswer(id, nodeNum, wantResponse: wantResponse);
    final packet = buildDataPacket(
      id: id,
      to: nodeNum,
      portnum: pb.PortNum.ADMIN_APP,
      payload: msg.writeToBuffer(),
      wantAck: true,
      wantResponse: wantResponse,
      pkiEncrypted: true,
    );
    try {
      await _write(pb.ToRadio(packet: packet));
    } catch (_) {
      answer.ignore();
      rethrow;
    }
    _meterTx(packet);
    return answer;
  }

  Future<_RemoteAnswer> _awaitRemoteAnswer(
    int id,
    int nodeNum, {
    required bool wantResponse,
  }) {
    final c = Completer<_RemoteAnswer>();
    final admin = adminStream.listen((r) {
      if (c.isCompleted || r.requestId != id || r.from != nodeNum) return;
      if (wantResponse) c.complete(_RemoteAnswer(response: r));
    });
    final routing = routingStream.listen((r) {
      if (c.isCompleted || r.requestId != id) return;
      if (!r.isAck) {
        c.completeError(RemoteAdminNak(
            r.errorName, r.packet.from, _nakMessage(r, nodeNum)));
      } else if (!wantResponse && r.packet.from == nodeNum) {
        c.complete(_RemoteAnswer(ack: r));
      }
    });
    return c.future
        .timeout(remoteExchangeTimeout,
            onTimeout: () => throw TimeoutException(
                'No answer from ${_nodeLabel(nodeNum)} in '
                '${remoteExchangeTimeout.inSeconds} s'))
        .whenComplete(() {
      admin.cancel();
      routing.cancel();
    });
  }

  String _nakMessage(RoutingReply r, int nodeNum) {
    final target = _nodeLabel(nodeNum);
    final who =
        r.packet.from == myNodeNum ? 'Our node' : _nodeLabel(r.packet.from);
    return switch (r.errorName) {
      'ADMIN_PUBLIC_KEY_UNAUTHORIZED' =>
        '$target does not accept changes from this node: its key is not '
            'an admin key there. Allow it in Node Setup at the base.',
      'ADMIN_BAD_SESSION_KEY' => '$target rejected the session key; try again.',
      'PKI_SEND_FAIL_PUBLIC_KEY' =>
        'Our node has no key for $target, so it refused to send.',
      'PKI_UNKNOWN_PUBKEY' =>
        '$target could not decrypt our message: it lacks our key.',
      _ => '$who refused: ${r.errorName}',
    };
  }

  /// A node's long name, else `!xxxxxxxx`.
  String _nodeLabel(int nodeNum) {
    final info = nodeInfos[nodeNum];
    final name = info != null && info.hasUser() ? info.user.longName : '';
    return name.isEmpty ? nodeIdHex(nodeNum) : name;
  }

  @override
  Future<BeaconConfig> setBeacon(BeaconConfig config) async {
    final beacon = config.resolved(capabilities);
    final kind = beacon.activeKind;
    final telemetry = (moduleConfigs[pb.ModuleConfig_PayloadVariant.telemetry]
            ?.telemetry
            .deepCopy() ??
        pb.ModuleConfig_TelemetryConfig())
      ..deviceTelemetryEnabled = kind == BeaconKind.telemetry;
    if (kind == BeaconKind.telemetry) {
      telemetry.deviceUpdateInterval = beacon.intervalSec;
    }
    await sendAdmin(pb.AdminMessage(beginEditSettings: true));
    await sendAdmin(pb.AdminMessage(
      setModuleConfig: pb.ModuleConfig(telemetry: telemetry),
    ));
    await sendAdmin(pb.AdminMessage(
      setModuleConfig: pb.ModuleConfig(
        rangeTest: pb.ModuleConfig_RangeTestConfig(
          enabled: kind == BeaconKind.rangeTest,
          sender: kind == BeaconKind.rangeTest ? beacon.intervalSec : 0,
        ),
      ),
    ));
    await commitSettings();
    moduleConfigs[pb.ModuleConfig_PayloadVariant.telemetry] =
        pb.ModuleConfig(telemetry: telemetry);
    return beacon;
  }

  @override
  Future<RadioInfo> queryDevice() async {
    final me = myNodeNum == null ? null : nodeInfos[myNodeNum!];
    return RadioInfo(
      protocol: RadioProtocol.meshtastic,
      model: me != null && me.hasUser() ? me.user.hwModel.name : '',
      firmwareVersion: metadata?.firmwareVersion ?? '',
    );
  }

  void _setState(RadioConnectionState s) {
    if (_state == s || _stateController.isClosed) return;
    _state = s;
    _stateController.add(s);
    if (s == RadioConnectionState.disconnected ||
        s == RadioConnectionState.ready) {
      _setProgress(null);
    }
  }

  /// The link is gone: a ping in flight can't be answered through it, and
  /// that says nothing about range, so it ends as a `LINK_LOST` error
  /// instead of waiting for its timeout.
  void _failPendingPings() {
    final pending = Map.of(_pendingPings);
    _pendingPings.clear();
    pending.forEach((id, p) {
      p.timeout?.cancel();
      if (p.completer.isCompleted) return;
      p.completer.complete(PingOutcome(
        pingId: id,
        status: PingStatus.error,
        errorReason: 'LINK_LOST',
        roundTrip: p.clock.elapsed,
      ));
    });
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    _failPendingPings();
    await _stateController.close();
    await _progressController.close();
    await _packetController.close();
    await _nodeController.close();
    await _routingController.close();
    await _adminController.close();
    await _txAirtimeController.close();
    await _channelStatsController.close();
    await _ownFixController.close();
  }
}

/// What a remote admin exchange ended with: the node's response (a get)
/// or its ACK (a set).
class _RemoteAnswer {
  final AdminReply? response;
  final RoutingReply? ack;
  const _RemoteAnswer({this.response, this.ack});
}
