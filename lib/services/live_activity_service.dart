// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/database/app_database.dart';
import '../data/radio/mesh_radio.dart';
import '../models/processed_signal_event.dart';
import '../ui/protocol_text.dart';
import '../utils/constants.dart';
import '../utils/link_margin.dart';
import 'active_probe_service.dart';
import 'out_of_range_monitor.dart';
import 'diag_log.dart';
import 'packet_processor.dart';
import 'session_manager.dart';

/// Mirrors the recording session into an iOS Live Activity (Dynamic Island
/// + lock screen) via the `mesh_analyzer/live_activity` channel.
///
/// Runs while the app is backgrounded because a recording session keeps
/// background location on. Updates are pushed on state changes and polled
/// every few seconds for counters, and only sent when something changed.
class LiveActivityService {
  static const _channel = MethodChannel('mesh_analyzer/live_activity');
  static const _poll = Duration(seconds: 5);

  /// Whether this device can show a Live Activity at all: iPhone only
  /// (not iPad, not Android). True on iOS until [checkDeviceSupport] asks
  /// the native side, which `main` does before the app starts. When false
  /// the service never starts one and the app says nothing about it.
  static bool deviceSupported = defaultTargetPlatform == TargetPlatform.iOS;

  /// Asks iOS whether this is an iPhone with ActivityKit (16.2+).
  static Future<void> checkDeviceSupport() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      deviceSupported = false;
      return;
    }
    try {
      deviceSupported =
          await _channel.invokeMethod<bool>('supported') ?? deviceSupported;
    } catch (e) {
      print('LiveActivity: supported check failed: $e');
    }
  }

  final AppDatabase _db;
  final MeshRadio _radio;
  final SessionManager _sessions;
  final PacketProcessor _packets;
  final ActiveProbeService _probe;
  final OutOfRangeMonitor _monitor;

  /// Pro turning on (bought from the session panel's "See Pro") starts the
  /// activity for the session already recording.
  final Stream<bool>? _proChanges;

  final List<StreamSubscription<dynamic>> _subs = [];
  StreamSubscription<int>? _countSub;
  Timer? _pollTimer;

  int? _sessionId;
  int? _baseMeshNodeId;

  /// The session preset's margin scale, so the lock screen colours the
  /// reading by the same link-margin bands as the map.
  MarginScale _marginScale = MarginScale.fallback;
  int _packetCount = 0;
  ProcessedSignalEvent? _lastFromBase;
  Map<String, Object?>? _lastSent;
  bool _running = false;
  bool _retryOnResume = false;

  /// Bumped on every session change, so a start that was overtaken while
  /// it awaited (session ended or replaced) can tell and back out.
  int _gen = 0;

  /// Whether this user may have a Live Activity (Pro,
  /// [ProFeature.liveActivity]). Checked when a session starts, so a lapse
  /// mid-session doesn't pull it.
  bool Function() allowed;
  StreamSubscription<bool>? _proSub;

  /// Why the Live Activity isn't showing for the current session (null when
  /// it is, or no session): "pro" (needs Pro), "disabled", "unsupported", "background" (iOS
  /// only starts one from a foreground app; retried on the next resume) or
  /// "error: …".
  final problem = ValueNotifier<String?>(null);

  /// The method channel call; replaceable in tests. Only iOS answers the
  /// channel: elsewhere (Android) a start reports "unsupported" without
  /// touching it, so nothing is retried and the session panel hides the row.
  @visibleForTesting
  Future<String?> Function(String method, [Object? args]) invoke =
      (method, [args]) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return method == 'start' ? 'unsupported' : null;
    }
    return _channel.invokeMethod<String>(method, args);
  };

  LiveActivityService({
    required AppDatabase db,
    required MeshRadio radio,
    required SessionManager sessions,
    required PacketProcessor packets,
    required ActiveProbeService probe,
    required OutOfRangeMonitor monitor,
    bool Function()? allowed,
    Stream<bool>? proChanges,
  })  : allowed = allowed ?? (() => true),
        _proChanges = proChanges,
        _db = db,
        _radio = radio,
        _sessions = sessions,
        _packets = packets,
        _probe = probe,
        _monitor = monitor;

  /// Begin following sessions. Picks up a session already in progress.
  void start() {
    if (_subs.isNotEmpty) return;
    _subs.add(_sessions.sessionStream.listen(_onSession));
    _subs.add(_radio.connectionState.listen((_) => _push()));
    _subs.add(_monitor.stateStream.listen((_) => _push()));
    _subs.add(_packets.signalStream.listen((e) {
      if (e.sourceNodeId == _baseMeshNodeId) _lastFromBase = e;
    }));
    _proSub = _proChanges?.listen((pro) {
      if (pro && problem.value == 'pro') _onSession(_sessions.activeSession);
    });
    _onSession(_sessions.activeSession);
  }

  Future<void> _onSession(Session? session) async {
    if (session != null && session.id == _sessionId && _running) return;
    final gen = ++_gen;
    await _end();
    if (session == null || gen != _gen) return;
    // iPad / Android: no Live Activity, and nothing to say about it.
    if (!deviceSupported) return;
    if (!allowed()) {
      _sessionId = session.id;
      problem.value = 'pro';
      return;
    }

    _sessionId = session.id;
    _marginScale = MarginScale.forPresetId(session.loraPreset);
    final baseId = await _db.baseMeshNodeIdForSession(session);
    if (gen != _gen) return; // overtaken; the newer call cleaned up
    _baseMeshNodeId = baseId;
    _lastFromBase = null;
    _packetCount = 0;
    _countSub = _db.watchPacketCount(session.id).listen((n) {
      _packetCount = n;
    });

    final base = _baseMeshNodeId == null ? null : _radio.nodes[_baseMeshNodeId];
    final baseName = base?.longName.isNotEmpty == true
        ? base!.longName
        : _baseMeshNodeId != null
            ? '!${_baseMeshNodeId!.toRadixString(16).padLeft(8, '0')}'
            : 'Base';
    final state = _state();
    String status;
    try {
      status = await invoke('start', {
            'sessionName': session.name.isNotEmpty ? session.name : 'Recording',
            'baseName': baseName,
            // Display names only: never "MEDIUM_FAST" on the lock screen.
            'preset': session.loraPreset.isEmpty
                ? ''
                : anyPresetDisplayName(session.loraPreset),
            'probeLabel': probeNounFor(session.protocol,
                plural: true, capital: true),
            ...state,
          }) ??
          'error: no reply';
    } catch (e) {
      status = 'error: $e';
    }
    if (gen != _gen) {
      // The session ended (or changed) while iOS was starting the
      // activity: don't leave an orphan on the lock screen.
      if (status == 'ok') {
        try {
          await invoke('end');
        } catch (e) {
          print('LiveActivity: end failed: $e');
        }
      }
      return;
    }
    _running = status == 'ok';
    problem.value = _running ? null : status;
    if (!_running) {
      DiagLog.instance.log('liveactivity', 'not started ($status)');
      _retryOnResume = status == 'background' || status.startsWith('error');
      return;
    }
    _retryOnResume = false;
    _lastSent = state;
    _pollTimer = Timer.periodic(_poll, (_) => _push());
  }

  Map<String, Object?> _state() {
    final link = switch (_radio.state) {
      RadioConnectionState.ready => 'connected',
      RadioConnectionState.disconnected => 'disconnected',
      _ => 'reconnecting',
    };
    final range = switch (_monitor.state) {
      RangeState.inRange => 'in',
      RangeState.outOfRange => 'out',
      RangeState.radioLost => 'radioLost',
      RangeState.unknown => 'unknown',
    };

    // Latest base → you signal: a received packet or a ping ACK.
    double? snr = _lastFromBase?.rxSnr;
    int? rssi = _lastFromBase?.rxRssi;
    final ackAt = _probe.lastAckAt;
    if (ackAt != null &&
        (_lastFromBase == null || ackAt.isAfter(_lastFromBase!.timestamp))) {
      snr = _probe.lastAckSnr ?? snr;
      rssi = _probe.lastAckRssi ?? rssi;
    }

    return {
      'link': link,
      'range': range,
      'snr': snr,
      'rssi': rssi,
      // Hybrid SNR/RSSI link margin (dB), coloured by MarginBand edges in
      // the widget; older widget builds ignore it.
      'margin': _marginScale.marginDb(snr: snr, rssi: rssi),
      'lastHeardMs': _monitor.lastHeardBase?.millisecondsSinceEpoch,
      'packets': _packetCount,
      'pingsOk': _probe.pingsOk,
      'pingsTotal': _probe.pingsAnswered,
    };
  }

  Future<void> _push() async {
    if (!_running) return;
    final state = _state();
    if (_sameState(state, _lastSent)) return;
    _lastSent = state;
    try {
      await invoke('update', state);
    } catch (e) {
      print('LiveActivity: update failed: $e');
    }
  }

  /// The app came to the foreground: a start that iOS refused while the
  /// app was in the background (or still launching) is tried again.
  void appResumed() {
    if (!_retryOnResume || _running) return;
    final session = _sessions.activeSession;
    if (session == null) return;
    _retryOnResume = false;
    DiagLog.instance.log('liveactivity', 'retrying start on resume');
    _onSession(session);
  }

  Future<void> _end() async {
    problem.value = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _countSub?.cancel();
    _countSub = null;
    _sessionId = null;
    _lastSent = null;
    if (_running) {
      _running = false;
      try {
        await invoke('end');
      } catch (e) {
        print('LiveActivity: end failed: $e');
      }
    }
  }

  static bool _sameState(Map<String, Object?> a, Map<String, Object?>? b) {
    if (b == null || a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _proSub?.cancel();
    _proSub = null;
    await _end();
  }
}
