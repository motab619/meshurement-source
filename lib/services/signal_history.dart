// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/database/app_database.dart';
import '../models/processed_signal_event.dart';
import '../utils/constants.dart';
import 'active_probe_service.dart';
import 'packet_processor.dart';
import 'session_manager.dart';

/// One base → you signal sample (a received packet or a ping reply).
class SignalSample {
  final DateTime time;
  final double? snr;
  final int? rssi;
  final int hops;
  final String source;

  const SignalSample({
    required this.time,
    this.snr,
    this.rssi,
    this.hops = 0,
    this.source = '',
  });
}

/// In-memory rolling history of signal samples and ping outcomes for the
/// live charts. Collects from app start, keeps the last [_keep]. When a
/// session that already has data becomes active (e.g. resumed after an app
/// restart) its recorded history is loaded from the database.
class SignalHistory extends ChangeNotifier {
  static const _keep = Duration(hours: 2);

  final PacketProcessor _packets;
  final ActiveProbeService _probe;
  final AppDatabase _db;
  final SessionManager _sessions;
  int? _loadedSessionId;
  final List<StreamSubscription<dynamic>> _subs = [];

  final List<SignalSample> samples = [];
  final List<PingSample> pings = [];

  SignalHistory({
    required PacketProcessor packets,
    required ActiveProbeService probe,
    required AppDatabase db,
    required SessionManager sessions,
  })  : _packets = packets,
        _probe = probe,
        _db = db,
        _sessions = sessions;

  void start() {
    if (_subs.isNotEmpty) return;
    _subs.add(_packets.signalStream.listen(_onSignal));
    _subs.add(_probe.outcomes.listen(_onPing));
    _subs.add(_sessions.sessionStream.listen(_loadSession));
    _loadSession(_sessions.activeSession);
  }

  /// Most recent sample as an event, for the readout before any live
  /// packet arrives.
  ProcessedSignalEvent? get latestEvent {
    if (samples.isEmpty) return null;
    final s = samples.last;
    return ProcessedSignalEvent(
      timestamp: s.time,
      sourceNodeId: 0,
      sourceNodeName: s.source,
      rxSnr: s.snr,
      rxRssi: s.rssi,
      hopCount: s.hops,
      packetType: '',
      direction: PacketDirection.rx,
    );
  }

  Future<void> _loadSession(Session? session) async {
    if (session == null || session.id == _loadedSessionId) return;
    _loadedSessionId = session.id;
    final events = await _db.getEventsForSession(session.id);
    if (events.isEmpty) return; // new session: keep what we have
    final pingRows = await _db.getPingsForSession(session.id);
    final nodes = {for (final n in await _db.getAllNodes()) n.id: n};

    final loaded = <SignalSample>[];
    final loadedPings = <PingSample>[];
    final byId = {for (final e in events) e.id: e};
    for (final e in events) {
      if (e.direction == PacketDirection.tx) {
        final c = pingRows[e.id];
        if (c == null) continue;
        final ack = byId[c.ackEventId];
        loadedPings.add(PingSample(
          sentAt: e.timestamp,
          answeredAt:
              e.timestamp.add(Duration(milliseconds: c.roundTripMs ?? 0)),
          status: c.ackStatus,
          // The reply's own signal (base → you), for the charts' readout.
          snr: ack?.rxSnr,
          rssi: ack?.rxRssi,
          uplinkSnr: ack?.uplinkSnr,
        ));
      } else if (e.rxSnr != null || e.rxRssi != null) {
        final n = nodes[e.sourceNodeId];
        loaded.add(SignalSample(
          time: e.timestamp,
          snr: e.rxSnr,
          rssi: e.rxRssi,
          hops: e.hopCount,
          source: n == null
              ? ''
              : (n.userLabel?.isNotEmpty == true ? n.userLabel! : n.longName),
        ));
      }
    }
    samples
      ..removeWhere((s) => !s.time.isAfter(events.last.timestamp))
      ..insertAll(0, loaded);
    pings
      ..removeWhere((p) => !p.sentAt.isAfter(events.last.timestamp))
      ..insertAll(0, loadedPings);
    _trimAndNotify();
  }

  void _onSignal(ProcessedSignalEvent e) {
    samples.add(SignalSample(
      time: e.timestamp,
      snr: e.rxSnr,
      rssi: e.rxRssi,
      hops: e.hopCount,
      source: e.sourceNodeName,
    ));
    _trimAndNotify();
  }

  void _onPing(PingSample p) {
    pings.add(p);
    // The base's reply is a base → you measurement too.
    if (p.fromBase && (p.snr != null || p.rssi != null)) {
      samples.add(SignalSample(
        time: p.answeredAt,
        snr: p.snr,
        rssi: p.rssi,
        source: 'ping reply',
      ));
    }
    _trimAndNotify();
  }

  /// Drop everything shown in the charts (after history was erased).
  void clear() {
    samples.clear();
    pings.clear();
    _loadedSessionId = null;
    notifyListeners();
  }

  void _trimAndNotify() {
    final cutoff = DateTime.now().subtract(_keep);
    samples.removeWhere((s) => s.time.isBefore(cutoff));
    pings.removeWhere((p) => p.sentAt.isBefore(cutoff));
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
