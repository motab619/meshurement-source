// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'mesh_radio.dart';

/// [r] as a [T]: itself, or the radio inside it when [r] is a
/// [SwitchableRadio]. Null when it is neither. Use this instead of `is` for
/// protocol-only extras (`radioAs<MeshtasticRadio>(radio)?.channels`).
T? radioAs<T extends MeshRadio>(MeshRadio? r) {
  if (r is T) return r;
  if (r is SwitchableRadio) {
    final inner = r.inner;
    if (inner is T) return inner;
  }
  return null;
}

/// The phone's radio, for whichever protocol the radio it connects to
/// speaks. Delegates every member to an inner [MeshRadio] and replaces that
/// radio when the protocol changes; its streams stay the same objects
/// across a switch, so services that subscribed once at app start
/// (`PacketProcessor`, `OutOfRangeMonitor`, ...) keep receiving.
///
/// [connect] switches by itself when the radio picked speaks another
/// protocol. A switch only happens while disconnected (connect disconnects
/// the old radio first) and is refused when [switchBlockedReason] says so
/// (a recording session on another protocol).
class SwitchableRadio implements MeshRadio {
  SwitchableRadio({
    required MeshRadio Function(RadioProtocol) factory,
    RadioProtocol initial = RadioProtocol.meshtastic,
    this.switchBlockedReason,
  }) : _factory = factory {
    _bind(_factory(initial));
  }

  final MeshRadio Function(RadioProtocol) _factory;

  /// Why the radio can't switch to the given protocol now, or null when it
  /// can. Asked before every switch.
  String? Function(RadioProtocol to)? switchBlockedReason;

  late MeshRadio _inner;

  /// The radio doing the work now.
  MeshRadio get inner => _inner;

  final List<StreamSubscription<dynamic>> _subs = [];

  // Synchronous: they only forward events the inner radio already
  // delivered asynchronously, so listeners see them with no extra delay.
  final _state = StreamController<RadioConnectionState>.broadcast(sync: true);
  final _progress = StreamController<ConnectProgress?>.broadcast(sync: true);
  final _packets = StreamController<ReceivedPacket>.broadcast(sync: true);
  final _nodes = StreamController<RadioNode>.broadcast(sync: true);
  final _txAirtime = StreamController<double>.broadcast(sync: true);
  final _channelStats =
      StreamController<RadioChannelStats>.broadcast(sync: true);
  final _ownFixes = StreamController<NodeFix>.broadcast(sync: true);
  final _innerChanged = StreamController<MeshRadio>.broadcast();

  /// The new inner radio after each switch (to give it protocol extras,
  /// e.g. Meshtastic contacts).
  Stream<MeshRadio> get innerChanged => _innerChanged.stream;

  /// Last state forwarded, so a switch between two disconnected radios
  /// emits nothing.
  RadioConnectionState? _lastState;

  void _bind(MeshRadio radio) {
    _inner = radio;
    radio.ownFixesWanted = _ownFixesWanted;
    // The inner's connectionState replays its current state first.
    _subs.add(radio.connectionState.listen((s) {
      if (s == _lastState || _state.isClosed) return;
      _lastState = s;
      _state.add(s);
    }));
    _subs.add(radio.connectProgressStream.listen(_progress.add));
    _subs.add(radio.packets.listen(_packets.add));
    _subs.add(radio.nodeUpdates.listen(_nodes.add));
    _subs.add(radio.txAirtimeStream.listen(_txAirtime.add));
    _subs.add(radio.channelStats.listen(_channelStats.add));
    _subs.add(radio.ownFixes.listen(_ownFixes.add));
  }

  Future<void> _unbind() async {
    final subs = List.of(_subs);
    _subs.clear();
    for (final s in subs) {
      await s.cancel();
    }
  }

  /// Why [switchTo] would refuse [to] now, or null when it wouldn't (also
  /// null when already on [to]).
  String? whyCantSwitchTo(RadioProtocol to) {
    if (to == _inner.protocol) return null;
    if (_inner.isDemo) return 'Demo mode uses its own node';
    return switchBlockedReason?.call(to);
  }

  /// Replace the inner radio with a new one for [to]. Only while
  /// disconnected; throws [StateError] otherwise or when
  /// [switchBlockedReason] refuses. No-op when already on [to].
  Future<void> switchTo(RadioProtocol to) async {
    if (to == _inner.protocol) return;
    if (_inner.state != RadioConnectionState.disconnected) {
      throw StateError('Disconnect the node before switching protocol');
    }
    final why = whyCantSwitchTo(to);
    if (why != null) throw StateError(why);
    final old = _inner;
    await _unbind();
    _bind(_factory(to));
    print('SwitchableRadio: ${old.protocol.name} -> ${to.name}');
    if (!_innerChanged.isClosed) _innerChanged.add(_inner);
    await old.dispose();
  }

  // ─── Link ──────────────────────────────────────────────

  @override
  RadioProtocol get protocol => _inner.protocol;

  @override
  RadioConnectionState get state => _inner.state;

  @override
  Stream<RadioConnectionState> get connectionState async* {
    yield _inner.state;
    yield* _state.stream;
  }

  @override
  ConnectProgress? get connectProgress => _inner.connectProgress;

  @override
  Stream<ConnectProgress?> get connectProgressStream => _progress.stream;

  @override
  bool get isReady => _inner.isReady;

  /// Connect to [radio], first switching to its protocol (disconnecting
  /// the current radio) when that differs.
  @override
  Future<void> connect(RadioDescriptor radio) async {
    if (radio.protocol != _inner.protocol) {
      final why = whyCantSwitchTo(radio.protocol);
      if (why != null) throw StateError(why);
      if (_inner.state != RadioConnectionState.disconnected) {
        await _inner.disconnect();
      }
      await switchTo(radio.protocol);
    }
    await _inner.connect(radio);
  }

  @override
  Future<void> disconnect() => _inner.disconnect();

  @override
  RadioDescriptor? get descriptor => _inner.descriptor;

  @override
  String get displayName => _inner.displayName;

  @override
  bool get isDemo => _inner.isDemo;

  // ─── What the radio knows ──────────────────────────────

  @override
  RadioCapabilities get capabilities => _inner.capabilities;

  @override
  Future<RadioInfo> queryDevice() => _inner.queryDevice();

  @override
  int? get myNodeId => _inner.myNodeId;

  @override
  Map<int, RadioNode> get nodes => _inner.nodes;

  @override
  Stream<RadioNode> get nodeUpdates => _nodes.stream;

  @override
  RadioPreset? get currentPreset => _inner.currentPreset;

  @override
  double get regionFrequencyMHz => _inner.regionFrequencyMHz;

  @override
  String get regionName => _inner.regionName;

  @override
  RadioSettings? get radioSettings => _inner.radioSettings;

  @override
  String get primaryChannelName => _inner.primaryChannelName;

  @override
  bool get onPublicChannel => _inner.onPublicChannel;

  // ─── Traffic ───────────────────────────────────────────

  @override
  Stream<ReceivedPacket> get packets => _packets.stream;

  @override
  Stream<double> get txAirtimeStream => _txAirtime.stream;

  @override
  Stream<RadioChannelStats> get channelStats => _channelStats.stream;

  @override
  RadioChannelStats? get lastChannelStats => _inner.lastChannelStats;

  @override
  Stream<NodeFix> get ownFixes => _ownFixes.stream;

  @override
  NodeFix? get lastOwnFix => _inner.lastOwnFix;

  bool _ownFixesWanted = true;

  @override
  bool get ownFixesWanted => _ownFixesWanted;

  @override
  set ownFixesWanted(bool wanted) {
    _ownFixesWanted = wanted;
    _inner.ownFixesWanted = wanted;
  }

  @override
  Future<void> prepareToPing(int target) => _inner.prepareToPing(target);

  /// Arguments left out keep the inner radio's own defaults.
  @override
  Future<PingOutcome> ping(
    int target, {
    Duration? timeout,
    int? channel,
    FutureOr<void> Function(int pingId)? beforeSend,
  }) =>
      Function.apply(_inner.ping, [
        target
      ], {
        if (timeout != null) #timeout: timeout,
        if (channel != null) #channel: channel,
        #beforeSend: beforeSend,
      }) as Future<PingOutcome>;

  // ─── Configuration ─────────────────────────────────────

  @override
  Future<BeaconConfig?> applyTestProfile(
    TestProfile profile, {
    void Function(String step)? onStep,
  }) =>
      _inner.applyTestProfile(profile, onStep: onStep);

  @override
  RadioSettings? settingsAfter(TestProfile profile) =>
      _inner.settingsAfter(profile);

  @override
  bool get supportsRemoteAdmin => _inner.supportsRemoteAdmin;

  @override
  Future<void> grantRemoteAdmin(List<int> publicKey) =>
      _inner.grantRemoteAdmin(publicKey);

  @override
  Future<void> setRemoteLora(
    int nodeNum, {
    RadioPreset? preset,
    int? txPowerDbm,
    void Function(String step)? onStep,
  }) =>
      _inner.setRemoteLora(nodeNum,
          preset: preset, txPowerDbm: txPowerDbm, onStep: onStep);

  @override
  Future<BeaconConfig> setBeacon(BeaconConfig config) =>
      _inner.setBeacon(config);

  @override
  Future<void> dispose() async {
    await _unbind();
    await _inner.dispose();
    await _state.close();
    await _progress.close();
    await _packets.close();
    await _nodes.close();
    await _txAirtime.close();
    await _channelStats.close();
    await _ownFixes.close();
    await _innerChanged.close();
  }
}
