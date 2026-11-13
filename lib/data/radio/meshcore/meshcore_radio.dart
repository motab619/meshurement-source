// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../../../services/airtime_model.dart';
import '../../../services/diag_log.dart';
import '../../../utils/constants.dart';
import '../../../utils/user_errors.dart' show isLostBondError;
import '../ble/ble_transport.dart';
import '../ble/radio_services.dart';
import '../mesh_radio.dart';
import 'meshcore_commander.dart';
import 'meshcore_frames.dart';
import 'meshcore_lpp.dart';
import 'meshcore_packets.dart';
import 'meshcore_presets.dart';
import 'meshcore_protocol.dart';
import 'meshcore_settings.dart';
import '../../../utils/app_info.dart';

/// MeshCore companion radio over the Nordic UART Service (frames written to
/// RX, notified on TX). Protocol reference: docs/design/meshcore.md
/// (companion firmware v1.18.0, meshcore-dev/MeshCore@81dbae5).
///
/// Connect: DEVICE_QUERY (tells the radio we speak protocol 3) →
/// APP_START (SELF_INFO) → SET_DEVICE_TIME → GET_CONTACTS → GET_CHANNEL
/// per slot → SYNC_NEXT_MESSAGE until empty → ready. Every logged LoRa
/// frame (PUSH_CODE_LOG_RX_DATA) becomes a [ReceivedPacket]; pings are
/// trace packets to the base, which must relay (client repeat on).
class MeshCoreRadio implements MeshRadio {
  static const serviceUuid = RadioServices.meshCore;
  static const rxUuid = RadioServices.meshCoreRx;
  static const txUuid = RadioServices.meshCoreTx;

  /// Name the radio logs for us on APP_START.
  static const appName = AppInfo.displayName;

  /// Name of our private channel slot.
  static const testChannelName = 'MeshTest';

  /// Bytes on air of one trace ping to a base: header + path_len + tag,
  /// auth, flags + a 4-byte hash (src/Mesh.cpp:693-704: a trace's hashes
  /// ride in the payload, its path starts empty).
  static const tracePingBytes = 2 + 9 + 4;

  /// The base's reply: the same plus one SNR byte in the path.
  static const traceReplyBytes = tracePingBytes + 1;

  /// Time for the iOS pairing prompt on the first subscribe / write.
  static const _pairingTimeout = Duration(seconds: 90);

  /// Shortest wait for a trace reply, whatever the radio estimates.
  static const _minPingWait = Duration(seconds: 5);

  MeshCoreRadio({
    RadioTransport? transport,
    Duration commandTimeout = const Duration(seconds: 5),
    this.contactsIdleTimeout = const Duration(seconds: 10),
    this.statsInterval = const Duration(seconds: 60),
    this.fixInterval = const Duration(seconds: 5),
    this.noGpsFixInterval = const Duration(seconds: 60),
    this.handshakeAttempts = 3,
    Duration? reconnectInitialDelay,
    Random? random,
    DateTime Function()? clock,
  })  : _transport = transport ??
            BleTransport(
              serviceUuid: serviceUuid,
              characteristicUuids: const [rxUuid, txUuid],
              protocolName: 'MeshCore',
            ),
        _reconnectInitialDelay = reconnectInitialDelay ??
            const Duration(seconds: AppConstants.bleReconnectInitialDelaySec),
        _random = random ?? Random.secure(),
        _now = clock ?? DateTime.now {
    _cmd = MeshCoreCommander(
      write: (frame, timeout) =>
          _transport.write(rxUuid, frame, timeout: timeout),
      defaultTimeout: commandTimeout,
    );
  }

  final RadioTransport _transport;
  late final MeshCoreCommander _cmd;
  final Duration contactsIdleTimeout;
  final Duration statsInterval;

  /// How often to ask our node for its GPS position (self telemetry,
  /// Bluetooth only); [noGpsFixInterval] once it answers without one.
  final Duration fixInterval;
  final Duration noGpsFixInterval;
  final int handshakeAttempts;
  final Duration _reconnectInitialDelay;
  final Random _random;
  final DateTime Function() _now;

  RadioDescriptor? _descriptor;
  StreamSubscription<List<int>>? _txSub;
  StreamSubscription<void>? _linkSub;
  Timer? _statsTimer;
  Timer? _fixTimer;

  /// Bumped on every connect/disconnect so a stale link-lost callback quits.
  int _linkGen = 0;
  bool _wantConnected = false;
  bool _reconnecting = false;

  /// The teardown started by a link loss; a reconnect waits for it so its
  /// late disconnect can't hit the new link.
  Future<void>? _lostTeardown;

  RadioConnectionState _state = RadioConnectionState.disconnected;
  ConnectProgress? _progress;

  MeshCoreDeviceInfo? _deviceInfo;
  MeshCoreSelfInfo? _selfInfo;
  final Map<int, RadioNode> _nodes = {};
  final Map<int, MeshCoreChannelInfo> _channels = {};
  final Map<int, _PendingPing> _pendingPings = {};
  RadioChannelStats? _lastChannelStats;
  final _ownFixController = StreamController<NodeFix>.broadcast();
  NodeFix? _lastOwnFix;

  /// Whether the last self telemetry carried a GPS position (null: no
  /// answer yet). Sets the polling pace.
  bool? _nodeHasGps;
  final List<_StatsSample> _statsSamples = [];
  bool _draining = false;
  bool _drainAgain = false;

  final _stateController = StreamController<RadioConnectionState>.broadcast();
  final _progressController = StreamController<ConnectProgress?>.broadcast();
  final _packetController = StreamController<ReceivedPacket>.broadcast();
  final _nodeController = StreamController<RadioNode>.broadcast();
  final _txAirtimeController = StreamController<double>.broadcast();
  final _channelStatsController =
      StreamController<RadioChannelStats>.broadcast();

  @override
  RadioProtocol get protocol => RadioProtocol.meshcore;

  // ─── Link ──────────────────────────────────────────────

  @override
  RadioConnectionState get state => _state;

  @override
  bool get isReady => _state == RadioConnectionState.ready;

  @override
  Stream<RadioConnectionState> get connectionState async* {
    yield _state;
    yield* _stateController.stream;
  }

  @override
  ConnectProgress? get connectProgress => _progress;

  @override
  Stream<ConnectProgress?> get connectProgressStream =>
      _progressController.stream;

  @override
  RadioDescriptor? get descriptor => _descriptor;

  @override
  String get displayName {
    final own = _selfInfo?.name ?? '';
    if (own.isNotEmpty) return own;
    final n = _descriptor?.name ?? '';
    if (n.isNotEmpty) return n;
    final live = _transport.platformName;
    return live.isNotEmpty ? live : 'node';
  }

  @override
  bool get isDemo => false;

  /// Connect to [radio] and run the handshake. Completes when the radio is
  /// ready; throws if this first attempt fails (later drops reconnect by
  /// themselves).
  @override
  Future<void> connect(RadioDescriptor radio) async {
    final gen = ++_linkGen;
    _wantConnected = true;
    await _teardown();
    if (_descriptor?.id != radio.id) {
      // Another radio: nothing we learnt about the last one applies.
      _nodes.clear();
      _channels.clear();
      _deviceInfo = null;
      _selfInfo = null;
      _lastChannelStats = null;
      _lastOwnFix = null;
      _nodeHasGps = null;
      _customVars = null;
      _statsSamples.clear();
    }
    _descriptor = radio;
    try {
      await _open(radio.id, gen);
    } catch (_) {
      if (gen == _linkGen) {
        _wantConnected = false;
        await _teardown();
        _setState(RadioConnectionState.disconnected);
      }
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _linkGen++;
    _wantConnected = false;
    await _teardown();
    _setState(RadioConnectionState.disconnected);
  }

  Future<void> _open(String deviceId, int gen) async {
    await _linkSub?.cancel();
    _linkSub = null;
    await _txSub?.cancel();
    _txSub = null;
    _setState(RadioConnectionState.connecting);
    _beginStep(RadioConnectionState.connecting, 'Connecting over Bluetooth');
    await _step('Bluetooth connect', _transport.connect(deviceId));
    _checkGen(gen);

    _beginStep(RadioConnectionState.connecting, 'Finding the node\'s service');
    await _step('Finding the MeshCore service', _transport.discover());
    _checkGen(gen);
    _linkSub = _transport.listenLinkLost(() => _onLinkLost(gen));

    // Subscribe before writing anything so no frame is missed. The first
    // access may show the iOS pairing prompt.
    _txSub = _transport.notifications(txUuid).listen(_onFrame);
    _setState(RadioConnectionState.pairing);
    _beginStep(RadioConnectionState.pairing, 'Pairing');
    await _step('Pairing (subscribe)',
        _transport.setNotify(txUuid, timeout: _pairingTimeout));
    _checkGen(gen);

    await _step('Reading radio settings', _handshake(gen));
    _checkGen(gen);
    _setState(RadioConnectionState.ready);
    _startStats();
    _scheduleFixPoll(Duration.zero);
  }

  void _checkGen(int gen) {
    if (gen != _linkGen) throw StateError('Connection superseded');
  }

  /// docs/design/meshcore.md §3. There is no "config complete" marker: the
  /// radio is ready once SELF_INFO is in, the contacts iterator has ended
  /// and the message queue is empty.
  Future<void> _handshake(int gen) async {
    _setState(RadioConnectionState.configuring);
    _beginStep(RadioConnectionState.configuring, 'Reading radio settings');

    // DEVICE_QUERY first: it is what tells the firmware our protocol
    // version (MyMesh.cpp:1056-1057), which picks the V3 message frames.
    // BLE writes right after bonding can be lost, so retry; the first
    // write gets the pairing allowance (ESP32 may prompt on it).
    _deviceInfo = (await _retry(
      () => _cmd.send(MeshCoreCommands.deviceQuery(),
          writeTimeout: _pairingTimeout),
      'DEVICE_QUERY',
    ))
        .expect<MeshCoreDeviceInfoFrame>('DEVICE_QUERY')
        .info;
    _checkGen(gen);
    _selfInfo = (await _retry(
      () => _cmd.send(MeshCoreCommands.appStart(
          appName: appName, appVersion: MeshCoreLimits.appProtocolVersion)),
      'APP_START',
    ))
        .expect<MeshCoreSelfInfoFrame>('APP_START')
        .info;
    _checkGen(gen);
    _addSelfNode();

    // Contact lastmod and advert timestamps run on the radio's clock. The
    // radio refuses to go backwards (ERR), which is fine.
    final secs = _now().millisecondsSinceEpoch ~/ 1000;
    final t = await _cmd.send(MeshCoreCommands.setDeviceTime(secs));
    if (t is MeshCoreError) {
      print('MeshCoreRadio: clock not set (${MeshCoreErr.name(t.errorCode)})');
    }
    _checkGen(gen);

    await _downloadContacts();
    _checkGen(gen);
    await _readChannels();
    _checkGen(gen);

    _beginStep(RadioConnectionState.configuring, 'Fetching queued messages');
    await _drainMessages();
  }

  Future<MeshCoreFrame> _retry(
      Future<MeshCoreFrame> Function() send, String name) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await send();
      } on TimeoutException {
        if (attempt >= handshakeAttempts) {
          throw TimeoutException('Node did not answer $name');
        }
        print('MeshCoreRadio: no answer to $name, retrying');
      }
    }
  }

  Future<void> _downloadContacts() async {
    _beginStep(RadioConnectionState.configuring, 'Downloading contacts');
    var total = 0;
    var got = 0;
    final frames = await _cmd.sendMulti(
      MeshCoreCommands.getContacts(),
      timeout: contactsIdleTimeout,
      isLast: (f) => f is MeshCoreEndOfContacts || f is MeshCoreError,
      onFrame: (f) {
        if (f is MeshCoreContactsStart) {
          total = f.count;
        } else if (f is MeshCoreContactFrame) {
          got++;
          _upsertNode(nodeFromContact(f.contact));
          if (total > 0) {
            _setProgress(ConnectProgress(
              state: RadioConnectionState.configuring,
              step: 'Downloading contacts',
              detail: '$got of $total',
              fraction: (got / total).clamp(0.0, 1.0),
              stepStartedAt: _progress?.stepStartedAt ?? _now(),
            ));
          }
        }
      },
    );
    final last = frames.last;
    if (last is MeshCoreError) {
      print('MeshCoreRadio: contacts refused '
          '(${MeshCoreErr.name(last.errorCode)})');
    }
  }

  /// Reads every channel slot, so the test channel can be found and a free
  /// slot picked. A slot the radio doesn't have answers ERR NOT_FOUND
  /// (MyMesh.cpp:1752-1766), which ends the scan.
  Future<void> _readChannels() async {
    _beginStep(RadioConnectionState.configuring, 'Reading channels');
    _channels.clear();
    final max = _deviceInfo?.maxChannels ?? 8;
    for (var i = 0; i < max; i++) {
      final f = await _cmd.send(MeshCoreCommands.getChannel(i));
      if (f is! MeshCoreChannelInfo) break;
      _channels[f.index] = f;
    }
  }

  /// SYNC_NEXT_MESSAGE until NO_MORE_MESSAGES. The queue holds DMs and
  /// channel messages only, which we don't use; draining keeps the radio's
  /// queue from filling up.
  Future<void> _drainMessages() async {
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _drainAgain = false;
        for (var n = 0; n < 500; n++) {
          final f = await _cmd.send(MeshCoreCommands.syncNextMessage());
          if (f is MeshCoreNoMoreMessages || f is MeshCoreError) break;
        }
      } while (_drainAgain);
    } finally {
      _draining = false;
    }
  }

  /// Run one connection step, naming it in any error.
  Future<T> _step<T>(String name, Future<T> step) async {
    try {
      return await step;
    } catch (e) {
      if (e is StateError && e.message == 'Connection superseded') rethrow;
      throw StateError('$name: $e');
    }
  }

  void _onLinkLost(int gen) {
    if (gen != _linkGen || !_wantConnected) return;
    print('MeshCoreRadio: link lost');
    DiagLog.instance.log('ble', 'MeshCore link lost');
    _lostTeardown = _teardown();
    if (_reconnecting) return;
    unawaited(_reconnectLoop(gen).catchError((Object e) {
      DiagLog.instance.log('ble', 'MeshCore reconnect stopped: $e');
    }));
  }

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
    var delay = _reconnectInitialDelay;
    const maxDelay = Duration(seconds: AppConstants.bleReconnectMaxDelaySec);
    var attempt = 0;
    while (gen == _linkGen && _wantConnected && _descriptor != null) {
      _setState(RadioConnectionState.reconnecting);
      attempt++;
      final now = _now();
      _setProgress(ConnectProgress(
        state: RadioConnectionState.reconnecting,
        step: 'Waiting to retry',
        stepStartedAt: now,
        attempt: attempt,
        retryAt: now.add(delay),
      ));
      await Future<void>.delayed(delay);
      if (gen != _linkGen || !_wantConnected) return;
      if (_state == RadioConnectionState.ready) return;
      try {
        await _lostTeardown;
        _lostTeardown = null;
        await _open(_descriptor!.id, gen);
        return;
      } catch (e) {
        if (gen != _linkGen) return;
        print('MeshCoreRadio: reconnect failed: $e');
        DiagLog.instance.log('ble', 'MeshCore reconnect failed: $e');
        await _teardown();
        if (isLostBondError(e)) {
          DiagLog.instance.log('ble', 'lost bond: giving up reconnecting');
          _wantConnected = false;
          _setState(RadioConnectionState.disconnected);
          return;
        }
        final next = delay * 2;
        delay = next > maxDelay ? maxDelay : next;
      }
    }
  }

  Future<void> _teardown() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    _fixTimer?.cancel();
    _fixTimer = null;
    _cmd.failAll(StateError('Not connected to a node'));
    _failPendingPings();
    _draining = false;
    // Detach before awaiting, so a link opened meanwhile keeps its own.
    final link = _linkSub, tx = _txSub;
    _linkSub = null;
    _txSub = null;
    await link?.cancel();
    await tx?.cancel();
    _transport.clearCharacteristics();
    await _transport.disconnect();
  }

  // ─── Incoming frames ───────────────────────────────────

  /// One frame notified by the radio on TX.
  void _onFrame(List<int> bytes) {
    final f = MeshCoreFrame.parse(Uint8List.fromList(bytes));
    if (!f.isPush) {
      _cmd.onResponse(f);
      return;
    }
    switch (f) {
      case MeshCoreRxLog():
        _onRxLog(f);
      case MeshCoreTraceData():
        _onTraceData(f);
      case MeshCoreContactFrame():
        _upsertNode(nodeFromContact(f.contact).copyWithHeard(_now()));
      case MeshCoreKeyPush(isAdvert: true):
        final n = _nodes[meshCoreNodeNum(f.publicKey)];
        if (n != null) _upsertNode(n.copyWithHeard(_now()));
      case MeshCoreNodeResponse(isTelemetry: true):
        _onTelemetry(f);
      case MeshCoreMsgWaiting():
        if (isReady) unawaited(_drainMessages().catchError((Object _) {}));
      default:
        break;
    }
  }

  void _onRxLog(MeshCoreRxLog log) {
    final p = log.packet;
    if (p == null) return; // the firmware drops it too
    final now = _now();
    if (p.payloadType == MeshCorePayloadType.trace && !p.isFlood) {
      final t = MeshCoreTracePayload.tryParse(p.payload);
      final pending = t == null ? null : _pendingPings[t.tag];
      if (t != null && pending != null && t.isComplete(p.hops)) {
        // Our own ping coming back: its signal belongs to the ping.
        pending.rssi = unwrapRssi(log.rssi);
        pending.replyPacketId = meshCorePacketId(p);
        return;
      }
    }
    if (p.payloadType == MeshCorePayloadType.advert) {
      final adv = MeshCoreAdvert.tryParse(p.payload);
      if (adv != null && meshCoreNodeNum(adv.publicKey) != myNodeId) {
        // A direct packet with hashes left says nothing about distance.
        final hops = p.isFlood ? p.hops : (p.hops == 0 ? 0 : null);
        _upsertNode(adv.toNode(hops: hops, heard: now));
      }
    }
    final packet = packetFromRxLog(log, nodeByPrefix: _nodeByPrefix, now: now);
    if (packet != null && !_packetController.isClosed) {
      _packetController.add(packet);
    }
  }

  void _onTraceData(MeshCoreTraceData t) {
    final pending = _pendingPings.remove(t.tag);
    if (pending == null) return;
    final rtt = _now().difference(pending.sentAt);
    pending.completer.complete(PingOutcome(
      pingId: t.tag,
      status: PingStatus.received,
      roundTrip: rtt,
      responder: pending.target,
      replyPacketId: pending.replyPacketId,
      snr: t.finalSnr,
      rssi: pending.rssi,
      hops: 0,
      uplinkSnr: t.hopSnrs.isNotEmpty ? t.hopSnrs.first : null,
    ));
  }

  /// The one known node (not us) whose key starts with [prefix].
  int? _nodeByPrefix(List<int> prefix) {
    if (prefix.isEmpty) return null;
    int? hit;
    for (final n in _nodes.values) {
      final k = n.publicKey;
      if (k == null || k.length < prefix.length || n.num == myNodeId) {
        continue;
      }
      var same = true;
      for (var i = 0; i < prefix.length; i++) {
        if (k[i] != prefix[i]) {
          same = false;
          break;
        }
      }
      if (!same) continue;
      if (hit != null && hit != n.num) return null; // ambiguous
      hit = n.num;
    }
    return hit;
  }

  void _addSelfNode() {
    final s = _selfInfo;
    if (s == null) return;
    final hasPos = (s.latE6 ?? 0) != 0 || (s.lonE6 ?? 0) != 0;
    _upsertNode(RadioNode(
      num: meshCoreNodeNum(s.publicKey),
      longName: s.name,
      shortName: meshCoreShortName(s.publicKey),
      hwModel: _deviceInfo?.manufacturer ?? '',
      latitude: hasPos ? s.latitude : null,
      longitude: hasPos ? s.longitude : null,
      hopsAway: 0,
      lastHeard: _now(),
      publicKey: s.publicKey,
      nodeKind: nodeKindFor(s.advType),
    ));
  }

  /// Store [n], keeping what an older entry knew that [n] doesn't say.
  void _upsertNode(RadioNode n) {
    final old = _nodes[n.num];
    final merged = old == null
        ? n
        : RadioNode(
            num: n.num,
            longName: n.longName.isNotEmpty ? n.longName : old.longName,
            shortName: n.shortName.isNotEmpty ? n.shortName : old.shortName,
            hwModel: n.hwModel.isNotEmpty ? n.hwModel : old.hwModel,
            latitude: n.hasPosition ? n.latitude : old.latitude,
            longitude: n.hasPosition ? n.longitude : old.longitude,
            hopsAway: n.hopsAway ?? old.hopsAway,
            lastHeard: _later(n.lastHeard, old.lastHeard),
            publicKey: n.publicKey ?? old.publicKey,
            nodeKind: n.nodeKind ?? old.nodeKind,
          );
    _nodes[n.num] = merged;
    if (!_nodeController.isClosed) _nodeController.add(merged);
  }

  static DateTime? _later(DateTime? a, DateTime? b) =>
      a == null ? b : (b == null || a.isAfter(b) ? a : b);

  void _setState(RadioConnectionState s) {
    if (_state == s || _stateController.isClosed) return;
    _state = s;
    _stateController.add(s);
    if (s == RadioConnectionState.disconnected ||
        s == RadioConnectionState.ready) {
      _setProgress(null);
    }
  }

  void _setProgress(ConnectProgress? p) {
    _progress = p;
    if (!_progressController.isClosed) _progressController.add(p);
  }

  void _beginStep(RadioConnectionState state, String step) => _setProgress(
      ConnectProgress(state: state, step: step, stepStartedAt: _now()));

  // ─── What the radio knows ──────────────────────────────

  @override
  RadioCapabilities get capabilities {
    final d = _deviceInfo;
    if (d == null) return RadioCapabilities.unknown;
    return RadioCapabilities(
      firmwareVersion: d.firmwareVersion ?? '',
      rangeTestExcluded: true,
      hasTraceroute: true,
      canRelay: d.clientRepeat,
      pathHashBytes: d.pathHashMode == null ? null : d.pathHashMode! + 1,
      protocolLevel: d.firmwareVerCode,
    );
  }

  @override
  Future<RadioInfo> queryDevice() async {
    if (isReady) {
      final f = await _cmd.send(MeshCoreCommands.deviceQuery());
      if (f is MeshCoreDeviceInfoFrame) _deviceInfo = f.info;
    }
    final d = _deviceInfo;
    return RadioInfo(
      protocol: RadioProtocol.meshcore,
      model: d?.manufacturer ?? '',
      firmwareVersion: d?.firmwareVersion ?? '',
      protocolVersion: d?.firmwareVerCode,
    );
  }

  /// First 4 bytes of our public key, big-endian.
  @override
  int? get myNodeId {
    final k = _selfInfo?.publicKey;
    return k == null ? null : meshCoreNodeNum(k);
  }

  @override
  Map<int, RadioNode> get nodes => Map.unmodifiable(_nodes);

  @override
  Stream<RadioNode> get nodeUpdates => _nodeController.stream;

  /// The community preset our parameters equal, if any.
  MeshCorePreset? get _communityPreset {
    final s = _selfInfo;
    if (s == null || !s.hasRadioParams) return null;
    return MeshCorePresets.match(
      frequencyKHz: s.frequencyKHz!,
      bandwidthHz: s.bandwidthHz!,
      spreadingFactor: s.spreadingFactor!,
      codingRate: s.codingRate!,
      pathHashSize: _deviceInfo?.pathHashMode == null
          ? null
          : _deviceInfo!.pathHashMode! + 1,
    );
  }

  @override
  RadioPreset? get currentPreset {
    final s = _selfInfo;
    if (s == null || !s.hasRadioParams) return null;
    return MeshCorePresets.radioPresetFor(
      bandwidthHz: s.bandwidthHz!,
      spreadingFactor: s.spreadingFactor!,
      codingRate: s.codingRate!,
    );
  }

  /// The radio's exact frequency (915 until known).
  @override
  double get regionFrequencyMHz => _frequencyMHz ?? 915;

  /// SELF_INFO's frequency, snapped to the community preset it equals: the
  /// firmware keeps MHz as a float and truncates ×1000 to kHz
  /// (MyMesh.cpp:1105), so 869.618 reads back as 869617 kHz.
  double? get _frequencyMHz =>
      _communityPreset?.frequencyMHz ?? _selfInfo?.frequencyMHz;

  /// Title of the community preset our parameters equal, else empty
  /// (MeshCore has no regions).
  @override
  String get regionName => _communityPreset?.title ?? '';

  @override
  RadioSettings? get radioSettings {
    final s = _selfInfo;
    if (s == null) return null;
    return RadioSettings(
      region: regionName,
      txPowerDbm: s.txPowerDbm,
      frequencyMHz: _frequencyMHz,
    );
  }

  /// Our private channel's name when the radio has it, else empty.
  @override
  String get primaryChannelName =>
      _testChannelSlot(testChannelName) == null ? '' : testChannelName;

  /// "Public" on MeshCore means the community mesh's radio parameters: our
  /// test traffic (traces) rides no channel, so isolation comes from the
  /// frequency and modulation (docs/design/meshcore.md §5). True until the
  /// parameters are known, so sessions refuse rather than guess.
  @override
  bool get onPublicChannel {
    final s = _selfInfo;
    if (s == null || !s.hasRadioParams) return true;
    return MeshCorePresets.matchAll(
      frequencyKHz: s.frequencyKHz!,
      bandwidthHz: s.bandwidthHz!,
      spreadingFactor: s.spreadingFactor!,
      codingRate: s.codingRate!,
    ).isNotEmpty;
  }

  int? _testChannelSlot(String name) {
    for (final c in _channels.values) {
      if (c.index > 0 && c.name == name) return c.index;
    }
    return null;
  }

  // ─── Traffic ───────────────────────────────────────────

  @override
  Stream<ReceivedPacket> get packets => _packetController.stream;

  @override
  Stream<double> get txAirtimeStream => _txAirtimeController.stream;

  // ─── Our node's GPS ───────────────────────────────────

  @override
  Stream<NodeFix> get ownFixes => _ownFixController.stream;

  @override
  NodeFix? get lastOwnFix => _lastOwnFix;

  bool _ownFixesWanted = true;

  @override
  bool get ownFixesWanted => _ownFixesWanted;

  /// Polling runs only while wanted; turning it back on asks at once.
  @override
  set ownFixesWanted(bool wanted) {
    if (wanted == _ownFixesWanted) return;
    _ownFixesWanted = wanted;
    if (!wanted) {
      _fixTimer?.cancel();
      _fixTimer = null;
    } else if (isReady) {
      _scheduleFixPoll(Duration.zero);
    }
  }

  void _scheduleFixPoll(Duration delay) {
    _fixTimer?.cancel();
    _fixTimer = null;
    if (!_ownFixesWanted) return;
    _fixTimer = Timer(delay, () => unawaited(_pollFix()));
  }

  Future<void> _pollFix() async {
    if (!isReady || isDemo) return;
    try {
      await _cmd.post(MeshCoreCommands.selfTelemetry());
    } catch (e) {
      print('MeshCoreRadio: self telemetry failed: $e');
    }
    if (!isReady || !_ownFixesWanted) return;
    _scheduleFixPoll(_nodeHasGps == false ? noGpsFixInterval : fixInterval);
  }

  /// A telemetry push: ours (our key prefix) may carry the GPS position.
  void _onTelemetry(MeshCoreNodeResponse r) {
    final self = _selfInfo?.publicKey;
    if (self == null ||
        self.length < r.keyPrefix.length ||
        !_samePrefix(self, r.keyPrefix)) {
      return;
    }
    final fix = nodeFixFromLpp(r.data, now: _now());
    _nodeHasGps = fix != null;
    if (fix == null || _ownFixController.isClosed) return;
    _lastOwnFix = fix;
    _ownFixController.add(fix);
  }

  static bool _samePrefix(List<int> key, List<int> prefix) {
    for (var i = 0; i < prefix.length; i++) {
      if (key[i] != prefix[i]) return false;
    }
    return true;
  }

  /// From GET_STATS (radio) every [statsInterval].
  @override
  Stream<RadioChannelStats> get channelStats => _channelStatsController.stream;

  @override
  RadioChannelStats? get lastChannelStats => _lastChannelStats;

  void _startStats() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(statsInterval, (_) => unawaited(_pollStats()));
    unawaited(_pollStats()); // logs its own failure
  }

  Future<void> _pollStats() async {
    if (!isReady) return;
    try {
      final f =
          await _cmd.send(MeshCoreCommands.getStats(MeshCoreStatsType.radio));
      if (f is MeshCoreRadioStats) addStatsSample(f.txAirSecs, f.rxAirSecs);
    } catch (e) {
      print('MeshCoreRadio: stats failed: $e');
    }
  }

  /// Feed one GET_STATS reading (cumulative seconds the radio transmitted
  /// and received since boot) taken now. Visible for tests.
  ///
  /// `airUtilTxPercent` = transmit seconds over the samples of the last
  /// hour (or since connecting, when shorter) as a share of that time;
  /// `channelUtilizationPercent` = receive seconds since the previous
  /// sample (about a minute) as a share of it. The radio counts whole
  /// seconds, so a one-minute figure moves in steps of ~1.7 %, and it
  /// counts only packets it decoded (src/Dispatcher.cpp:204-209).
  void addStatsSample(int txAirSecs, int rxAirSecs) {
    final now = _now();
    final s = _StatsSample(now, txAirSecs, rxAirSecs);
    if (_statsSamples.isNotEmpty) {
      final last = _statsSamples.last;
      if (txAirSecs < last.tx || rxAirSecs < last.rx) {
        _statsSamples.clear(); // the radio rebooted: counters restarted
      }
    }
    _statsSamples.add(s);
    const hour = Duration(hours: 1);
    while (_statsSamples.length > 2 &&
        now.difference(_statsSamples[1].at) >= hour) {
      _statsSamples.removeAt(0);
    }
    if (_statsSamples.length < 2) return;
    final first = _statsSamples.first;
    final prev = _statsSamples[_statsSamples.length - 2];
    final spanAll = now.difference(first.at).inMilliseconds / 1000;
    final spanLast = now.difference(prev.at).inMilliseconds / 1000;
    if (spanAll <= 0 || spanLast <= 0) return;
    final stats = RadioChannelStats(
      airUtilTxPercent:
          ((s.tx - first.tx) / spanAll * 100).clamp(0.0, 100.0).toDouble(),
      channelUtilizationPercent:
          ((s.rx - prev.rx) / spanLast * 100).clamp(0.0, 100.0).toDouble(),
      measuredAt: now,
    );
    _lastChannelStats = stats;
    if (!_channelStatsController.isClosed) _channelStatsController.add(stats);
  }

  /// Traces need no key exchange.
  @override
  Future<void> prepareToPing(int target) async {}

  /// Time on air of a [bytes]-byte packet at the radio's modulation.
  double airtimeMsFor(int bytes) => AirtimeModel.airtimeMs(
      AirtimeModel.paramsFor(currentPreset ?? AirtimeModel.defaultPreset),
      payloadBytes: bytes);

  /// A trace to [target] and back (docs/design/meshcore.md §7c): the
  /// target finds its 4-byte key prefix on the path, adds the SNR it heard
  /// us at and sends it on; the path is then used up, so our radio reports
  /// it (PUSH_CODE_TRACE_DATA, src/Mesh.cpp:42-66). The target must relay
  /// (client repeat on). Never throws.
  @override
  Future<PingOutcome> ping(
    int target, {
    Duration timeout = const Duration(seconds: 30),
    int channel = 0,
    FutureOr<void> Function(int pingId)? beforeSend,
  }) async {
    PingOutcome fail(int id, String reason, [Duration? rtt]) => PingOutcome(
          pingId: id,
          status: PingStatus.error,
          errorReason: reason,
          roundTrip: rtt ?? Duration.zero,
        );
    if (!isReady) return fail(0, 'not connected');
    // Never test on the public mesh (ActiveProbeService checks first; the
    // guided listen loop and any other caller rely on this).
    if (onPublicChannel) return fail(0, 'PUBLIC_CHANNEL');
    final key = _nodes[target]?.publicKey;
    if (key == null || key.length < 4) return fail(0, 'unknown node');

    final tag = _newTag();
    try {
      await beforeSend?.call(tag);
    } catch (e) {
      return fail(tag, 'error:$e');
    }
    final pending = _PendingPing(target, _now());
    _pendingPings[tag] = pending;
    // flags & 3 = log2(hash size): 2 → 4-byte hashes (MyMesh.cpp:1815-
    // 1817), so a relay sharing a 1-byte prefix can't answer for the base.
    final frame = MeshCoreCommands.sendTracePath(
        tag: tag, path: Uint8List.sublistView(key, 0, 4), flags: 2);
    // Until the radio answers SENT nothing is known to be on air: a radio
    // that never answers (busy, rebooting) or a failed Bluetooth write is
    // an error, never a trace timeout (which reads as out of range).
    final MeshCoreFrame resp;
    try {
      resp = await _cmd.send(frame);
    } on MeshCoreNoReply {
      _pendingPings.remove(tag);
      return fail(tag, 'RADIO_BUSY', _now().difference(pending.sentAt));
    } catch (e) {
      _pendingPings.remove(tag);
      DiagLog.instance.log('ping', 'trace not sent: $e');
      return fail(tag, 'LINK_LOST', _now().difference(pending.sentAt));
    }
    try {
      if (resp is MeshCoreError) {
        _pendingPings.remove(tag);
        return fail(tag, 'error:${MeshCoreErr.name(resp.errorCode)}',
            _now().difference(pending.sentAt));
      }
      if (resp is! MeshCoreSent) {
        _pendingPings.remove(tag);
        return fail(tag, 'error:unexpected reply ${resp.code}');
      }
      if (!_txAirtimeController.isClosed) {
        _txAirtimeController.add(airtimeMsFor(tracePingBytes));
      }
      var wait = Duration(milliseconds: resp.estimatedTimeoutMs * 2);
      if (wait < _minPingWait) wait = _minPingWait;
      if (timeout < wait) wait = timeout;
      final left = wait - _now().difference(pending.sentAt);
      return await pending.completer.future
          .timeout(left.isNegative ? Duration.zero : left);
    } on TimeoutException {
      _pendingPings.remove(tag);
      if (pending.completer.isCompleted) {
        return pending.completer.future;
      }
      return PingOutcome(
        pingId: tag,
        status: PingStatus.timeout,
        roundTrip: _now().difference(pending.sentAt),
      );
    } catch (e) {
      _pendingPings.remove(tag);
      return fail(tag, 'error:$e', _now().difference(pending.sentAt));
    }
  }

  /// The link is gone: traces in flight can't be answered through it, and
  /// that says nothing about range, so they end as `LINK_LOST` errors.
  void _failPendingPings() {
    final pending = Map.of(_pendingPings);
    _pendingPings.clear();
    pending.forEach((tag, p) {
      if (p.completer.isCompleted) return;
      p.completer.complete(PingOutcome(
        pingId: tag,
        status: PingStatus.error,
        errorReason: 'LINK_LOST',
        roundTrip: _now().difference(p.sentAt),
      ));
    });
  }

  /// Random non-zero u32.
  int _newTag() => _random.nextInt(0xFFFFFFFE) + 1;

  // ─── Configuration ─────────────────────────────────────

  /// docs/design/meshcore.md §6: rename, our channel, TX power, then the
  /// radio parameters (client repeat on for a base). A companion applies
  /// all of it at once, without a reboot; SELF_INFO is read back after.
  @override
  Future<BeaconConfig?> applyTestProfile(
    TestProfile profile, {
    void Function(String step)? onStep,
  }) async {
    if (!isReady) throw StateError('Not connected to a node');
    final self = _selfInfo;
    if (self == null || !self.hasRadioParams) {
      throw StateError('Radio settings not read yet');
    }

    final name = profile.radioLongName;
    if (name != null && name.isNotEmpty) {
      onStep?.call('Renaming the node');
      _ok(await _cmd.send(MeshCoreCommands.setAdvertName(name)), 'name');
    }

    onStep?.call('Adding the ${profile.channelName} channel');
    if (_channels.isEmpty) await _readChannels();
    final slot = _testChannelSlot(profile.channelName) ?? _freeChannelSlot();
    if (slot == null) {
      throw StateError('The node has no free channel slot for '
          '${profile.channelName}');
    }
    _ok(
        await _cmd.send(MeshCoreCommands.setChannel(slot, profile.channelName,
            Uint8List.fromList(profile.channelKey16))),
        'channel');
    _channels[slot] = MeshCoreChannelInfo(Uint8List(0), slot,
        profile.channelName, Uint8List.fromList(profile.channelKey16));

    final power = profile.txPowerDbm;
    if (power != null) {
      onStep?.call('Setting transmit power');
      _ok(await _cmd.send(MeshCoreCommands.setTxPower(power)), 'tx power');
    }

    onStep?.call('Setting frequency and modulation');
    final repeat = profile.isBase && profile.baseRelays;
    final freq = profile.frequencyMHz ?? _frequencyMHz!;
    final r = await _cmd.send(MeshCoreCommands.setRadioParams(
      frequencyMHz: freq,
      bandwidthKHz: profile.preset.bwKHz,
      spreadingFactor: profile.preset.sf,
      codingRate: profile.preset.cr,
      clientRepeat: repeat,
    ));
    if (r is MeshCoreError && repeat) {
      // Client repeat only on fixed frequencies (MyMesh.cpp:1032-1048,
      // 1439-1440); the build may have its own list.
      final allowed = await _allowedRepeatFrequencies();
      final list = allowed.isEmpty
          ? 'the frequencies its firmware allows'
          : allowed.map(formatFrequencyMHz).join(', ');
      throw StateError('Node rejected setting: relaying is not allowed on '
          '${formatFrequencyMHz(freq)} MHz. A MeshCore base can only relay '
          'on $list MHz.');
    }
    _ok(r, 'radio params');

    // The mobile's GPS stands in for a phone without one (a Wi-Fi iPad):
    // switched on where the board has the switch (a T1000-E; off by
    // default). The backup taken before Node Setup keeps the old value.
    if (!profile.isBase) {
      try {
        final vars = _customVars ?? await readCustomVars();
        if (vars.containsKey('gps') && vars['gps'] != '1') {
          onStep?.call('Turning on this node\'s GPS');
          await _setGps('1');
        }
      } catch (e) {
        // Not worth failing Node Setup over: the phone's GPS still works.
        DiagLog.instance.log('meshcore', 'GPS switch skipped: $e');
      }
    }

    onStep?.call('Reading back the settings');
    await _rereadSelf();

    if (!profile.isBase) return null;
    return BeaconConfig(
        intervalSec: profile.beacon?.intervalSec ?? 0, kind: BeaconKind.trace);
  }

  /// DEVICE_INFO and SELF_INFO again, after settings were written.
  Future<void> _rereadSelf() async {
    final d = await _cmd.send(MeshCoreCommands.deviceQuery());
    if (d is MeshCoreDeviceInfoFrame) _deviceInfo = d.info;
    final s = await _cmd.send(MeshCoreCommands.appStart(
        appName: appName, appVersion: MeshCoreLimits.appProtocolVersion));
    if (s is MeshCoreSelfInfoFrame) {
      _selfInfo = s.info;
      _addSelfNode();
    }
  }

  /// What Radio Setup can change, as the radio last reported it (name,
  /// power, radio parameters, client repeat, every channel slot); null
  /// until SELF_INFO with radio parameters was read. A backup saves this.
  MeshCoreSettings? get settings => MeshCoreSettings.of(
      self: _selfInfo,
      device: _deviceInfo,
      channels: _channels.values,
      gps: _customVars?['gps']);

  /// The board's custom vars as last read ([readCustomVars]); null until
  /// then.
  Map<String, String>? _customVars;

  /// Read the board's custom vars (a T1000-E: `gps`). A backup reads them
  /// first so [settings] includes the GPS switch. Firmware that answers
  /// with an error leaves none.
  Future<Map<String, String>> readCustomVars() async {
    if (!isReady) throw StateError('Not connected to a node');
    final f = await _cmd.send(MeshCoreCommands.getCustomVars());
    _customVars = f is MeshCoreCustomVars ? f.vars : const {};
    return _customVars!;
  }

  Future<void> _setGps(String value) async {
    _ok(await _cmd.send(MeshCoreCommands.setCustomVar('gps', value)), 'gps');
    _customVars = {...?_customVars, 'gps': value};
    // Asked again soon: a node that answered "no GPS" may have one now.
    _nodeHasGps = null;
    _scheduleFixPoll(fixInterval);
  }

  /// Write [s] back (a restore): name, every channel slot, transmit
  /// power, then the radio parameters with the saved repeat flag. No
  /// reboot; SELF_INFO is read back after.
  Future<void> applySettings(
    MeshCoreSettings s, {
    void Function(String step)? onStep,
  }) async {
    if (!isReady) throw StateError('Not connected to a node');
    if (s.name.isNotEmpty && s.name != _selfInfo?.name) {
      onStep?.call('Restoring name "${s.name}"');
      _ok(await _cmd.send(MeshCoreCommands.setAdvertName(s.name)), 'name');
    }
    final max = _deviceInfo?.maxChannels;
    final slots = s.channels.where((c) => max == null || c.index < max);
    if (slots.isNotEmpty) {
      final names = s.usedChannels.map((c) => c.name).join(', ');
      onStep?.call('Restoring channels${names.isEmpty ? '' : ' ($names)'}');
    }
    for (final c in slots) {
      _ok(
          await _cmd.send(MeshCoreCommands.setChannel(
              c.index, c.name, Uint8List.fromList(c.secret))),
          'channel ${c.index}');
      _channels[c.index] =
          MeshCoreChannelInfo(Uint8List(0), c.index, c.name, c.secret);
    }
    final gps = s.gps;
    if (gps != null && gps != _customVars?['gps']) {
      onStep?.call(
          gps == '1' ? 'Turning the GPS back on' : 'Turning the GPS off again');
      await _setGps(gps);
    }
    onStep?.call('Restoring transmit power (${s.txPowerDbm} dBm)');
    _ok(await _cmd.send(MeshCoreCommands.setTxPower(s.txPowerDbm)), 'tx power');
    final mod = s.modulation;
    onStep?.call('Restoring ${formatFrequencyMHz(s.frequencyMHz)} MHz, '
        '${mod?.name ?? 'custom modulation'}'
        '${s.clientRepeat == true ? ', relaying on' : ''}');
    _ok(
        await _cmd.send(MeshCoreCommands.setRadioParams(
          frequencyMHz: s.frequencyMHz,
          bandwidthKHz: s.bandwidthKHz,
          spreadingFactor: s.spreadingFactor,
          codingRate: s.codingRate,
          clientRepeat: s.clientRepeat,
        )),
        'radio params');
    onStep?.call('Reading back the settings');
    await _rereadSelf();
  }

  int? _freeChannelSlot() {
    final max = _deviceInfo?.maxChannels ?? 8;
    for (var i = 1; i < max; i++) {
      final c = _channels[i];
      if (c == null) return null; // past the slots the radio has
      if (c.isEmpty) return i;
    }
    return null;
  }

  Future<List<double>> _allowedRepeatFrequencies() async {
    try {
      final f = await _cmd.send(MeshCoreCommands.getAllowedRepeatFreq());
      if (f is! MeshCoreAllowedRepeatFreq) return const [];
      return [
        for (final (lo, hi) in f.rangesKHz) ...[
          lo / 1000,
          if (hi != lo) hi / 1000,
        ]
      ];
    } catch (_) {
      return const [];
    }
  }

  void _ok(MeshCoreFrame f, String what) {
    if (f is MeshCoreOk) return;
    if (f is MeshCoreError) {
      throw StateError(
          'Node rejected setting ($what): ${MeshCoreErr.name(f.errorCode)}');
    }
    throw StateError('Unexpected reply to $what: $f');
  }

  @override
  RadioSettings? settingsAfter(TestProfile profile) {
    final s = _selfInfo;
    final freq = profile.frequencyMHz ?? _frequencyMHz;
    final preset = freq == null
        ? null
        : MeshCorePresets.match(
            frequencyKHz: (freq * 1000).round(),
            bandwidthHz: (profile.preset.bwKHz * 1000).round(),
            spreadingFactor: profile.preset.sf,
            codingRate: profile.preset.cr);
    return RadioSettings(
      region: preset?.title ?? '',
      txPowerDbm: profile.txPowerDbm ?? s?.txPowerDbm,
      frequencyMHz: freq,
    );
  }

  @override
  bool get supportsRemoteAdmin => false;

  @override
  Future<void> grantRemoteAdmin(List<int> publicKey) =>
      throw UnsupportedError('No remote administration on $protocol');

  @override
  Future<void> setRemoteLora(
    int nodeNum, {
    RadioPreset? preset,
    int? txPowerDbm,
    void Function(String step)? onStep,
  }) =>
      throw UnsupportedError('No remote administration on $protocol');

  /// A MeshCore base sends nothing periodic: the mobile pulls the beacon
  /// with traces on its own timer. Nothing is written.
  @override
  Future<BeaconConfig> setBeacon(BeaconConfig config) async => BeaconConfig(
        intervalSec: config.intervalSec,
        kind: config.enabled ? BeaconKind.trace : BeaconKind.none,
      );

  @override
  Future<void> dispose() async {
    await disconnect();
    _failPendingPings();
    await _stateController.close();
    await _progressController.close();
    await _packetController.close();
    await _nodeController.close();
    await _txAirtimeController.close();
    await _channelStatsController.close();
    await _ownFixController.close();
  }
}

/// Our node's position from its self telemetry [data] (Cayenne LPP), or
/// null without a usable GPS entry. LPP keeps 0.0001° (≈ 11 m), so the
/// accuracy is never better than that; the firmware gives no fix quality,
/// and a T1000-E keeps its last position when the fix is lost.
NodeFix? nodeFixFromLpp(Uint8List data, {required DateTime now}) {
  final g = lppGps(data);
  if (g == null) return null;
  final fix = NodeFix(
    latitude: g.latitude,
    longitude: g.longitude,
    altitudeM: g.altitudeM,
    accuracyM: 15,
    time: now,
  );
  return fix.isValid ? fix : null;
}

class _PendingPing {
  _PendingPing(this.target, this.sentAt);
  final int target;
  final DateTime sentAt;
  final completer = Completer<PingOutcome>();
  int? rssi;
  int? replyPacketId;
}

class _StatsSample {
  const _StatsSample(this.at, this.tx, this.rx);
  final DateTime at;
  final int tx;
  final int rx;
}

extension on MeshCoreFrame {
  T expect<T extends MeshCoreFrame>(String command) {
    final f = this;
    if (f is T) return f;
    if (f is MeshCoreError) {
      throw StateError(
          'Node rejected $command: ${MeshCoreErr.name(f.errorCode)}');
    }
    throw StateError('Unexpected reply to $command: $f');
  }
}

extension on RadioNode {
  /// The same node, heard at [at] (a push means we heard it just now).
  RadioNode copyWithHeard(DateTime at) => RadioNode(
        num: this.num,
        longName: longName,
        shortName: shortName,
        hwModel: hwModel,
        latitude: latitude,
        longitude: longitude,
        hopsAway: hopsAway,
        lastHeard: at,
        publicKey: publicKey,
        nodeKind: nodeKind,
      );
}
