// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;

import '../data/database/app_database.dart';
import '../data/radio/mesh_radio.dart';
import '../utils/constants.dart';
import 'airtime_model.dart';
import 'gps_service.dart';

/// Manages Tier 3 active probing: pings the base through the radio's
/// `ping` and records each outcome (the radio does the ACK matching).
class ActiveProbeService {
  final AppDatabase _db;
  final MeshRadio _radio;
  final GpsService _gps;

  Timer? _pingTimer;
  int? _activeSessionId;
  int? _baseMeshNodeId;
  int _pingIntervalSec = AppConstants.defaultPingIntervalSec;
  int _channelIndex = 0; // private channel index

  final StreamController<PingSample> _outcomes =
      StreamController<PingSample>.broadcast();

  /// Each ping's result as it is known (for live charts).
  Stream<PingSample> get outcomes => _outcomes.stream;

  /// Pings this session that got an answer (any outcome) / were delivered.
  int pingsAnswered = 0;
  int pingsOk = 0;

  /// Pings the radio refused because of its duty-cycle / rate limit.
  int pingsThrottled = 0;

  /// Signal of the latest ACK from the base (base → you).
  double? lastAckSnr;
  int? lastAckRssi;
  DateTime? lastAckAt;

  /// How well the base heard our latest delivered ping (you → base), when
  /// the protocol reports it (MeshCore trace).
  double? lastUplinkSnr;

  /// In-flight pings awaiting their outcome: ping id → pending ping
  final Map<int, _PendingPing> _pendingPings = {};

  bool get isActive => _pingTimer != null;

  /// Mesh node number pings go (or last went) to; null before any start.
  int? get targetMeshNodeId => _baseMeshNodeId;

  /// Why pings are on hold (null while they go out). Set when the radio's
  /// primary channel is the public one: we never test there.
  final ValueNotifier<String?> blockedReason = ValueNotifier<String?>(null);

  static const publicChannelReason =
      'Pings paused: your node is on the public channel. Run Node Setup.';

  /// The NodeInfo / contact swap with the base still has to run (set at
  /// start and whenever the radio becomes ready again, e.g. after a
  /// relaunch or a reboot); done before the next ping.
  bool _needsKeyExchange = false;
  Future<void>? _keyExchange;
  StreamSubscription<RadioConnectionState>? _stateSub;
  RadioConnectionState? _lastState;

  ActiveProbeService({
    required AppDatabase db,
    required MeshRadio radio,
    required GpsService gps,
    bool Function()? countRelayed,
  })  : _db = db,
        _radio = radio,
        _gps = gps,
        _countRelayed = countRelayed ?? (() => false);

  /// Whether relayed replies (hops > 0) count as signal samples (Settings →
  /// "Count relayed packets"); mirrors [PacketProcessor].
  final bool Function() _countRelayed;

  /// Start sending periodic pings to [baseMeshNodeId] (the mesh node
  /// number, not the local DB id).
  void start({
    required int sessionId,
    required int baseMeshNodeId,
    int intervalSec = 60,
    int channelIndex = 0,
  }) {
    _activeSessionId = sessionId;
    _baseMeshNodeId = baseMeshNodeId;
    pingsAnswered = 0;
    pingsOk = 0;
    pingsThrottled = 0;
    lastAckSnr = null;
    lastAckRssi = null;
    lastAckAt = null;
    lastUplinkSnr = null;
    _pingIntervalSec = max(intervalSec, _minIntervalSec);
    _channelIndex = channelIndex;

    // Swap NodeInfo (incl. public keys) with the base first: direct
    // messages are PKI-encrypted, and a base that doesn't know our key
    // rejects them with PKI_UNKNOWN_PUBKEY. Redo it whenever the radio
    // becomes ready again (a resumed session connects later; a rebooted
    // radio may have lost the base's key).
    _needsKeyExchange = true;
    blockedReason.value = null;
    unawaited(_ensureKeyExchange()); // logs its own failure
    _stateSub?.cancel();
    _lastState = _radio.state;
    _stateSub = _radio.connectionState.listen(_onConnectionState);

    _startTimer();
  }

  /// Seconds between pings right now.
  int get intervalSec => _pingIntervalSec;

  /// Change the ping interval of a running probe (MeshCore: the base
  /// beacon interval changed mid-session). Never below the physical floor.
  void retune(int intervalSec) {
    if (!isActive) return;
    final next = max(intervalSec, _minIntervalSec);
    if (next == _pingIntervalSec) return;
    _pingIntervalSec = next;
    _startTimer();
  }

  void _onConnectionState(RadioConnectionState s) {
    final wasReady = _lastState == RadioConnectionState.ready;
    _lastState = s;
    if (s == RadioConnectionState.ready && !wasReady && isActive) {
      _needsKeyExchange = true;
      unawaited(_ensureKeyExchange());
    }
  }

  /// True (and [blockedReason] set) when sending now would transmit on the
  /// public channel.
  bool _blockedByPublicChannel() {
    if (!_radio.onPublicChannel) return false;
    if (blockedReason.value != publicChannelReason) {
      print('ActiveProbeService: radio on the public channel; '
          'not pinging or exchanging keys');
      blockedReason.value = publicChannelReason;
    }
    return true;
  }

  /// Run the pending key exchange once, if the radio can send and is not on
  /// the public channel. Concurrent callers share the same run.
  Future<void> _ensureKeyExchange() {
    final running = _keyExchange;
    if (running != null) return running;
    final base = _baseMeshNodeId;
    if (!_needsKeyExchange ||
        base == null ||
        _radio.isDemo ||
        !_radio.isReady ||
        _blockedByPublicChannel()) {
      return Future<void>.value();
    }
    _needsKeyExchange = false;
    final run = _radio.prepareToPing(base).catchError((Object e) {
      print('ActiveProbeService: NodeInfo exchange failed: $e');
      _needsKeyExchange = true; // try again before the next ping
    }).whenComplete(() => _keyExchange = null);
    return _keyExchange = run;
  }

  /// Safety floor only: SessionManager already applied the airtime budget
  /// (or the user's "Faster than recommended" override).
  int get _minIntervalSec =>
      AirtimeModel.fastestIntervalSecFor(_radio.currentPreset,
          protocol: _radio.protocol);

  /// How long the radio waits for a reply. A MeshCore trace answers in
  /// well under a second, so it times out within one interval (5 s at
  /// least), which keeps one trace in flight at a time and makes every
  /// miss known before the next ping; Meshtastic DMs may be relayed and
  /// get the usual 30 s.
  Duration get _pingTimeout =>
      Duration(seconds: pingTimeoutSecFor(_radio.protocol, _pingIntervalSec));

  /// [_pingTimeout] in seconds for [protocol] at [intervalSec] (also sizes
  /// the out-of-range window in SessionManager).
  static int pingTimeoutSecFor(RadioProtocol protocol, int intervalSec) =>
      protocol == RadioProtocol.meshcore
          ? intervalSec.clamp(5, AppConstants.defaultAckTimeoutSec)
          : AppConstants.defaultAckTimeoutSec;

  void _startTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      Duration(seconds: _pingIntervalSec),
      (_) => _sendPing(),
    );
  }

  void stop() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _stateSub?.cancel();
    _stateSub = null;
    _needsKeyExchange = false;
    blockedReason.value = null;
    // Timeout all remaining pending pings; their later outcomes are ignored
    for (final pending in _pendingPings.values) {
      _markTimedOut(pending.txEventId);
    }
    _pendingPings.clear();
  }

  /// Mark a ping timed out in the background; a failed write is logged.
  void _markTimedOut(int txEventId) {
    unawaited(_db.timeoutPendingPing(txEventId).catchError((Object e) {
      print('ActiveProbeService: timeout not saved: $e');
    }));
  }

  /// Send one ping now instead of waiting for the timer.
  @visibleForTesting
  Future<void> pingNow() => _sendPing();

  Future<void> _sendPing() async {
    if (_activeSessionId == null || _baseMeshNodeId == null) return;
    // The radio's preset may have changed (e.g. after a reconnect): never
    // ping faster than its airtime allows.
    final minSec = _minIntervalSec;
    if (_pingIntervalSec < minSec) {
      _pingIntervalSec = minSec;
      _startTimer();
      return; // next tick (at the slower pace) sends
    }
    if (!_radio.isReady || _radio.myNodeId == null || _radio.isDemo) return;
    // Never test on the public channel, whatever radio is connected now
    // (resumed session, radio switched or restored mid-session).
    if (_blockedByPublicChannel()) return;
    blockedReason.value = null;
    if (_needsKeyExchange || _keyExchange != null) {
      await _ensureKeyExchange();
    }
    if (!isActive || !_radio.isReady || _radio.onPublicChannel) return;

    final outcome = await _radio.ping(
      _baseMeshNodeId!,
      timeout: _pingTimeout,
      channel: _channelIndex,
      // Record and register the ping before it is transmitted, so even a
      // very fast ACK finds it in _pendingPings.
      beforeSend: (packetId) async {
        final position = _gps.lastPosition;
        final selfLocalId = await _localNodeId(_radio.myNodeId!);
        final sentAt = DateTime.now();
        final txEventId = await _db.insertPacketEvent(
          PacketEventsCompanion.insert(
            sessionId: _activeSessionId!,
            timestamp: sentAt,
            direction: PacketDirection.tx,
            sourceNodeId: selfLocalId,
            packetType: PacketType.ping,
            meshPacketId: Value(packetId),
            rxLat: Value(position?.latitude),
            rxLon: Value(position?.longitude),
            rxAlt: Value(position?.altitude),
            gpsAccuracy: Value(position?.accuracy),
          ),
        );
        _pendingPings[packetId] =
            _PendingPing(txEventId: txEventId, sentAt: sentAt);
        await _db.insertPingCorrelation(
          PingCorrelationsCompanion.insert(txEventId: txEventId),
        );
      },
    );
    await _onOutcome(outcome);
  }

  /// Record how a ping ended. Ignores outcomes of pings from before the
  /// last [stop] (those were already marked timed out).
  Future<void> _onOutcome(PingOutcome outcome) async {
    final pending = _pendingPings.remove(outcome.pingId);
    if (pending == null || _activeSessionId == null) return;

    // The send itself failed (nothing was transmitted).
    if (outcome.status == PingStatus.error && outcome.responder == null) {
      print('ActiveProbeService: ping failed: ${outcome.errorReason}');
      await _db.updatePingCorrelation(
        txEventId: pending.txEventId,
        ackEventId: null,
        roundTripMs: null,
        status: AckStatus.errorWithReason(outcome.errorReason ?? 'SEND_FAILED'),
      );
      return;
    }

    pingsAnswered++;

    if (outcome.status == PingStatus.timeout) {
      _markTimedOut(pending.txEventId);
      _emit(pending.sentAt, AckStatus.timeout);
      return;
    }

    final roundTripMs = outcome.roundTrip.inMilliseconds;
    // A relayed ACK still proves delivery, but its SNR/RSSI belong to the
    // relay's last hop, not the base link: keep the row (with its real hop
    // count) and drop the signal unless relayed packets are counted.
    final relayed = outcome.hops > 0 && !_countRelayed();
    final double? snr = relayed ? null : outcome.snr;
    final int? rssi = relayed ? null : outcome.rssi;
    final fromBase = outcome.responder == _baseMeshNodeId && !relayed;

    final String status;
    switch (outcome.status) {
      case PingStatus.received:
        status = AckStatus.received;
        pingsOk++;
        if (snr != null) lastAckSnr = snr;
        if (rssi != null) lastAckRssi = rssi;
        if (outcome.uplinkSnr != null) lastUplinkSnr = outcome.uplinkSnr;
        lastAckAt = DateTime.now();
      case PingStatus.implicit:
        status = AckStatus.implicit;
      case PingStatus.throttled:
        status = AckStatus.throttled;
        pingsThrottled++;
      case PingStatus.error:
        status = outcome.errorReason == null
            ? AckStatus.error
            : AckStatus.errorWithReason(outcome.errorReason!);
      case PingStatus.timeout:
        status = AckStatus.timeout; // handled above
    }

    final position = _gps.lastPosition;
    final ackEventId = await _db.insertPacketEvent(
      PacketEventsCompanion.insert(
        sessionId: _activeSessionId!,
        timestamp: DateTime.now(),
        direction: PacketDirection.ack,
        sourceNodeId: await _localNodeId(outcome.responder!),
        packetType: PacketType.ack,
        sourceKind: const Value(SourceKind.ack),
        rxSnr: Value(snr),
        rxRssi: Value(rssi),
        uplinkSnr: Value(outcome.uplinkSnr),
        hopCount: Value(outcome.hops),
        meshPacketId: Value(outcome.replyPacketId),
        rxLat: Value(position?.latitude),
        rxLon: Value(position?.longitude),
        rxAlt: Value(position?.altitude),
        gpsAccuracy: Value(position?.accuracy),
      ),
    );

    _emit(
      pending.sentAt,
      status,
      snr: snr,
      rssi: rssi,
      fromBase: fromBase,
      latitude: position?.latitude,
      longitude: position?.longitude,
      hops: outcome.hops,
      uplinkSnr: outcome.uplinkSnr,
    );

    await _db.updatePingCorrelation(
      txEventId: pending.txEventId,
      ackEventId: ackEventId,
      roundTripMs: roundTripMs,
      status: status,
    );
  }

  Future<int> _localNodeId(int meshNodeId) async {
    final existing = await _db.getNodeByMeshId(meshNodeId);
    if (existing != null) return existing.id;
    final node = _radio.nodes[meshNodeId];
    return _db.upsertNode(
      nodeId: meshNodeId,
      longName: node?.longName ?? '',
      shortName: node?.shortName ?? '',
      hwModel: node?.hwModel ?? '',
    );
  }

  void _emit(
    DateTime sentAt,
    String status, {
    double? snr,
    int? rssi,
    bool fromBase = false,
    double? latitude,
    double? longitude,
    int hops = 0,
    double? uplinkSnr,
  }) {
    if (_outcomes.isClosed) return;
    _outcomes.add(PingSample(
      sentAt: sentAt,
      answeredAt: DateTime.now(),
      status: status,
      snr: snr,
      rssi: rssi,
      fromBase: fromBase,
      latitude: latitude,
      longitude: longitude,
      hops: hops,
      uplinkSnr: uplinkSnr,
    ));
  }

  /// Push a sample as if a reply had just been recorded (Live map tests).
  @visibleForTesting
  void injectSample(PingSample s) {
    if (!_outcomes.isClosed) _outcomes.add(s);
  }

  void dispose() {
    stop();
    _outcomes.close();
    blockedReason.dispose();
  }
}

class _PendingPing {
  final int txEventId;
  final DateTime sentAt;

  _PendingPing({required this.txEventId, required this.sentAt});
}

/// Result of one ping, for the live charts. [snr]/[rssi] are of the reply (base → you) when
/// the base itself answered.
class PingSample {
  final DateTime sentAt;
  final DateTime answeredAt;
  final String status;
  final double? snr;
  final int? rssi;
  final bool fromBase;

  /// Where the phone was when the reply arrived, so the Live map can drop
  /// a dot for it (replies never pass through PacketProcessor's stream).
  final double? latitude;
  final double? longitude;
  final int hops;

  /// How well the base heard the ping (you → base, dB), when the protocol
  /// reports it (MeshCore trace). Null otherwise.
  final double? uplinkSnr;

  const PingSample({
    required this.sentAt,
    required this.answeredAt,
    required this.status,
    this.snr,
    this.rssi,
    this.fromBase = false,
    this.latitude,
    this.longitude,
    this.hops = 0,
    this.uplinkSnr,
  });

  bool get hasGps => latitude != null && longitude != null;
}
