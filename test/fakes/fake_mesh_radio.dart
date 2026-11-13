// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:mesh_analyzer/data/radio/mesh_radio.dart';

/// A scriptable [MeshRadio] for service tests: push packets and node
/// updates, and decide how each ping ends.
class FakeMeshRadio implements MeshRadio {
  FakeMeshRadio({
    this.myNodeId = 1,
    this.currentPreset,
    this.protocol = RadioProtocol.meshtastic,
    RadioConnectionState state = RadioConnectionState.ready,
  }) : _state = state;

  RadioConnectionState _state;
  final _packets = StreamController<ReceivedPacket>.broadcast();
  final _nodeUpdates = StreamController<RadioNode>.broadcast();
  final _states = StreamController<RadioConnectionState>.broadcast();
  final _channelStats = StreamController<RadioChannelStats>.broadcast();
  final _ownFixes = StreamController<NodeFix>.broadcast();

  /// Push a fix as if our node's GPS had reported it.
  void pushOwnFix(NodeFix fix) {
    lastOwnFix = fix;
    _ownFixes.add(fix);
  }

  @override
  Stream<NodeFix> get ownFixes => _ownFixes.stream;

  @override
  NodeFix? lastOwnFix;

  @override
  bool ownFixesWanted = true;
  final _txAirtime = StreamController<double>.broadcast();

  /// Push the radio's own airtime report.
  void pushChannelStats(RadioChannelStats stats) {
    lastChannelStats = stats;
    _channelStats.add(stats);
  }

  /// Push a packet as if the radio had heard it.
  void pushPacket(ReceivedPacket packet) => _packets.add(packet);

  /// Push a node DB update (also stored in [nodes]).
  void pushNode(RadioNode node) {
    nodes[node.num] = node;
    _nodeUpdates.add(node);
  }

  void setState(RadioConnectionState s) {
    _state = s;
    _states.add(s);
  }

  // ─── Ping scripting ───────────────────────────────────

  /// What each ping ends with, in order. The function gets the ping id.
  /// When empty a ping times out.
  final List<FutureOr<PingOutcome> Function(int pingId)> script = [];

  /// Called after `beforeSend` and right before "transmitting" (so tests
  /// can check what was recorded first).
  Future<void> Function(int pingId)? onTransmit;

  /// Events in order: `beforeSend:<id>`, `transmit:<id>`.
  final List<String> log = [];
  final List<int> pingTargets = [];
  final List<int> preparedTargets = [];
  int _nextId = 1000;

  @override
  Future<PingOutcome> ping(
    int target, {
    Duration timeout = const Duration(seconds: 30),
    int channel = 0,
    FutureOr<void> Function(int pingId)? beforeSend,
  }) async {
    final id = _nextId++;
    pingTargets.add(target);
    await beforeSend?.call(id);
    log.add('beforeSend:$id');
    log.add('transmit:$id');
    await onTransmit?.call(id);
    if (script.isEmpty) {
      return PingOutcome(
          pingId: id, status: PingStatus.timeout, roundTrip: timeout);
    }
    return await script.removeAt(0)(id);
  }

  @override
  Future<void> prepareToPing(int target) async => preparedTargets.add(target);

  // ─── MeshRadio ────────────────────────────────────────

  @override
  final RadioProtocol protocol;

  @override
  RadioConnectionState get state => _state;

  @override
  bool get isReady => _state == RadioConnectionState.ready;

  @override
  Stream<RadioConnectionState> get connectionState async* {
    yield _state;
    yield* _states.stream;
  }

  @override
  ConnectProgress? connectProgress;

  @override
  Stream<ConnectProgress?> get connectProgressStream => const Stream.empty();

  @override
  Future<void> connect(RadioDescriptor radio) async {
    descriptor = radio;
    setState(RadioConnectionState.ready);
  }

  @override
  Future<void> disconnect() async =>
      setState(RadioConnectionState.disconnected);

  @override
  RadioDescriptor? descriptor;

  @override
  String displayName = 'fake';

  @override
  bool isDemo = false;

  @override
  Future<RadioInfo> queryDevice() async => const RadioInfo(
      protocol: RadioProtocol.meshtastic, model: 'FAKE', firmwareVersion: '');

  @override
  int? myNodeId;

  @override
  final Map<int, RadioNode> nodes = {};

  @override
  Stream<RadioNode> get nodeUpdates => _nodeUpdates.stream;

  @override
  RadioPreset? currentPreset;

  @override
  double regionFrequencyMHz = 915;

  @override
  String regionName = 'US';

  @override
  String primaryChannelName = 'MeshTest';

  /// Null unless a test sets one.
  @override
  RadioSettings? radioSettings;

  @override
  bool onPublicChannel = false;

  @override
  Stream<ReceivedPacket> get packets => _packets.stream;

  @override
  Stream<RadioChannelStats> get channelStats => _channelStats.stream;

  @override
  RadioChannelStats? lastChannelStats;

  @override
  Stream<double> get txAirtimeStream => _txAirtime.stream;

  @override
  Future<BeaconConfig?> applyTestProfile(
    TestProfile profile, {
    void Function(String step)? onStep,
  }) async {
    appliedProfiles.add(profile);
    if (applyError case final e?) throw e;
    return profile.isBase
        ? (profile.beacon ?? const BeaconConfig.off())
            .resolved(capabilities, protocol: protocol)
        : null;
  }

  @override
  RadioCapabilities capabilities = RadioCapabilities.unknown;

  /// Every config passed to [setBeacon], in order.
  final List<BeaconConfig> beacons = [];

  /// What [settingsAfter] returns; defaults to [radioSettings].
  RadioSettings? settingsAfterProfile;

  @override
  RadioSettings? settingsAfter(TestProfile profile) =>
      settingsAfterProfile ?? radioSettings;

  /// Thrown by [applyTestProfile] (after recording the profile) when set.
  Object? applyError;

  /// Every profile passed to [applyTestProfile], in order.
  final List<TestProfile> appliedProfiles = [];

  /// What [supportsRemoteAdmin] reports.
  bool remoteAdmin = false;

  /// Every key passed to [grantRemoteAdmin].
  final List<List<int>> grantedKeys = [];

  /// Every [setRemoteLora] call: (nodeNum, preset id, txPowerDbm).
  final List<(int, String?, int?)> remoteLoraCalls = [];

  @override
  bool get supportsRemoteAdmin => remoteAdmin;

  @override
  Future<void> grantRemoteAdmin(List<int> publicKey) async {
    if (!remoteAdmin) throw UnsupportedError('No remote administration');
    grantedKeys.add(List.of(publicKey));
  }

  @override
  Future<void> setRemoteLora(
    int nodeNum, {
    RadioPreset? preset,
    int? txPowerDbm,
    void Function(String step)? onStep,
  }) async {
    if (!remoteAdmin) throw UnsupportedError('No remote administration');
    remoteLoraCalls.add((nodeNum, preset?.id, txPowerDbm));
  }

  @override
  Future<BeaconConfig> setBeacon(BeaconConfig config) async {
    beacons.add(config);
    return config.resolved(capabilities);
  }

  /// Set once [dispose] ran.
  bool disposed = false;

  /// Push an airtime estimate as if the radio had sent something.
  void pushTxAirtime(double ms) => _txAirtime.add(ms);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _packets.close();
    await _nodeUpdates.close();
    await _states.close();
    await _channelStats.close();
    await _txAirtime.close();
  }
}
