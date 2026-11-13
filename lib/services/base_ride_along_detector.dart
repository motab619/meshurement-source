// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/app_database.dart';
import '../demo/demo_mode.dart';
import '../models/processed_signal_event.dart';
import '../utils/constants.dart';
import 'active_probe_service.dart';
import 'base_location.dart';
import 'diag_log.dart';
import 'out_of_range_monitor.dart';

// ─── Tunables ────────────────────────────────────────────

/// Phone speed that counts as driving (m/s, ≈ 14 km/h).
const rideAlongMinSpeedMps = 4.0;

/// How long driving speed must be held before anything is judged.
/// Counts moving time only: stopped seconds inside the run don't add up.
const rideAlongMinDrive = Duration(seconds: 20);

/// A slow stretch (below [rideAlongMinSpeedMps]) up to this long, e.g. a
/// traffic light or stop sign, does not end the driving run, so the run
/// still starts at the real departure. Longer, and the run starts over.
const rideAlongMaxStopGap = Duration(seconds: 45);

/// GPS fixes less accurate than this are ignored (neither break nor
/// extend the driving window).
const rideAlongMaxAccuracyM = 30.0;

/// A base sample is "very strong" at or above this RSSI...
const rideAlongMinRssiDbm = -75;

/// ...or, when the radio gave no RSSI, at or above this SNR.
const rideAlongMinSnrDb = 9.0;

/// Base samples needed inside the driving window.
const rideAlongMinSamples = 3;

/// Largest RSSI spread (max − min) that still counts as steady.
const rideAlongMaxRssiSpreadDb = 10;

/// The phone must be at least this far from the base's location...
const rideAlongMinDistanceM = 150.0;

/// ...and have moved at least this much further away over the window...
const rideAlongMinDistanceGainM = 30.0;

/// ...without ever coming closer than the window's first fix by more than
/// this (GPS noise). Driving *past* the parked base dips well below it.
const rideAlongDistanceSlackM = 25.0;

/// Never fires this early in a session (setting off from the car).
const rideAlongSessionGrace = Duration(seconds: 60);

/// Samples older than this are dropped from the window.
const rideAlongKeep = Duration(minutes: 15);

// ─── Rule ────────────────────────────────────────────────

/// One input to the rule: a GPS fix ([speedMps], [accuracyM],
/// [distanceM] from the base's location) or a signal sample heard
/// directly from the base ([rssi], [snr]).
class RideAlongSample {
  final DateTime at;
  final double? speedMps;
  final double? accuracyM;
  final double? distanceM;
  final int? rssi;
  final double? snr;

  const RideAlongSample.fix(this.at,
      {required double this.speedMps, this.accuracyM = 5, this.distanceM})
      : rssi = null,
        snr = null;

  const RideAlongSample.signal(this.at, {this.rssi, this.snr})
      : speedMps = null,
        accuracyM = null,
        distanceM = null;

  bool get isFix => speedMps != null;
  bool get isSignal => !isFix;

  bool get isStrong => rssi != null
      ? rssi! >= rideAlongMinRssiDbm
      : (snr != null && snr! >= rideAlongMinSnrDb);
}

/// The base seems to be travelling with the phone since [startedAt] (when
/// the phone reached driving speed); [samplesSince] base samples have been
/// recorded since then.
@immutable
class RideAlongEvent {
  final DateTime startedAt;
  final int samplesSince;
  const RideAlongEvent({required this.startedAt, required this.samplesSince});

  RideAlongEvent withSamples(int n) =>
      RideAlongEvent(startedAt: startedAt, samplesSince: n);

  @override
  bool operator ==(Object other) =>
      other is RideAlongEvent &&
      other.startedAt == startedAt &&
      other.samplesSince == samplesSince;

  @override
  int get hashCode => Object.hash(startedAt, samplesSince);

  @override
  String toString() => 'RideAlongEvent($startedAt, $samplesSince samples)';
}

/// The ride-along rule, as a pure function of the [samples] seen so far
/// (any order), [now] and when the session started.
///
/// 1. Driving: the latest run of usable fixes (accuracy ≤ 30 m) at
///    ≥ 4 m/s, where slow stretches of ≤ 45 s (lights, stop signs) don't
///    break it, still going at the newest usable fix, with ≥ 20 s of
///    moving time (stopped seconds excluded). It starts at its first
///    moving fix.
/// 2. Strong and steady: ≥ 3 base samples since the run began, every one
///    strong (RSSI ≥ −75 dBm, or SNR ≥ 9 dB without RSSI), RSSI spread
///    ≤ 10 dB.
/// 3. Leaving: the newest fix is ≥ 150 m from the base, ≥ 30 m further
///    than the run's first fix, and no fix in the run came > 25 m closer
///    than that first one.
/// Never within 60 s of [sessionStart]. Returns the event, else null.
RideAlongEvent? evaluateRideAlong(
  List<RideAlongSample> samples, {
  required DateTime now,
  required DateTime sessionStart,
}) {
  if (now.difference(sessionStart) < rideAlongSessionGrace) return null;
  final sorted = [...samples]..sort((a, b) => a.at.compareTo(b.at));
  final fixes = [
    for (final s in sorted)
      if (s.isFix &&
          (s.accuracyM == null ||
              s.accuracyM! <= 0 ||
              s.accuracyM! <= rideAlongMaxAccuracyM))
        s
  ];
  if (fixes.isEmpty) return null;

  // 1. The latest driving run, short stops included.
  int? first; // index of the run's first moving fix
  var moving = Duration.zero; // closed moving segments
  DateTime? segStart, lastMoving, slowSince;
  for (var i = 0; i < fixes.length; i++) {
    final f = fixes[i];
    if (f.speedMps! >= rideAlongMinSpeedMps) {
      if (first == null ||
          (slowSince != null &&
              f.at.difference(slowSince) > rideAlongMaxStopGap)) {
        first = i; // first departure, or after a long stop
        moving = Duration.zero;
      }
      if (segStart == null || slowSince != null) segStart = f.at;
      slowSince = null;
      lastMoving = f.at;
    } else if (first != null && slowSince == null) {
      moving += lastMoving!.difference(segStart!);
      slowSince = f.at;
    }
  }
  if (first == null) return null;
  if (slowSince != null) {
    // Stopped now: still the same run unless the stop is already too long.
    if (fixes.last.at.difference(slowSince) > rideAlongMaxStopGap) {
      return null;
    }
  } else {
    moving += lastMoving!.difference(segStart!);
  }
  if (moving < rideAlongMinDrive) return null;
  final run = fixes.sublist(first);
  final start = run.first.at;

  // 2. Base signal in the run.
  final signals = [
    for (final s in sorted)
      if (s.isSignal && !s.at.isBefore(start)) s
  ];
  if (signals.length < rideAlongMinSamples) return null;
  if (!signals.every((s) => s.isStrong)) return null;
  final rssis = [
    for (final s in signals)
      if (s.rssi != null) s.rssi!
  ];
  if (rssis.isNotEmpty &&
      rssis.reduce(math.max) - rssis.reduce(math.min) >
          rideAlongMaxRssiSpreadDb) {
    return null;
  }

  // 3. Moving away from where the base should be.
  final dist = [
    for (final f in run)
      if (f.distanceM != null) f.distanceM!
  ];
  if (dist.length < 2) return null;
  final d0 = dist.first, dN = dist.last;
  if (dN < rideAlongMinDistanceM) return null;
  if (dN - d0 < rideAlongMinDistanceGainM) return null;
  if (dist.reduce(math.min) < d0 - rideAlongDistanceSlackM) return null;

  return RideAlongEvent(startedAt: start, samplesSince: signals.length);
}

// ─── Service ─────────────────────────────────────────────

/// Notices when the base radio has been put in the car with the phone
/// (left in the car for a survey, then driven off with the session still
/// recording): strong, steady signal at a growing distance from the base's
/// location, which would poison the map and the by-distance stats.
/// Started and stopped with each session by `SessionManager`; fires at
/// most once a session.
class BaseRideAlongDetector {
  final AppDatabase _db;
  final SharedPreferences? _prefs;
  final Stream<Position> _positions;
  final Stream<ProcessedSignalEvent> _signals;
  final Stream<PingSample> _pings;
  final OutOfRangeMonitor? _monitor;
  final DateTime Function() _clock;

  /// [signals] is `PacketProcessor.signalStream`, [pings]
  /// `ActiveProbeService.outcomes`.
  BaseRideAlongDetector({
    required AppDatabase db,
    required Stream<Position> positions,
    required Stream<ProcessedSignalEvent> signals,
    required Stream<PingSample> pings,
    OutOfRangeMonitor? monitor,
    SharedPreferences? prefs,
    DateTime Function()? clock,
  })  : _db = db,
        _prefs = prefs,
        _positions = positions,
        _signals = signals,
        _pings = pings,
        _monitor = monitor,
        _clock = clock ?? DateTime.now;

  final _events = StreamController<RideAlongEvent>.broadcast();
  Stream<RideAlongEvent> get events => _events.stream;

  /// The event the user hasn't answered yet (the Live map banner).
  final pending = ValueNotifier<RideAlongEvent?>(null);

  final _subs = <StreamSubscription<Object?>>[];
  final _window = <RideAlongSample>[];
  int? _sessionId;
  int? _baseNodeNum;
  LatLng? _base;
  DateTime _sessionStart = DateTime.now();
  bool _fired = false;
  int _generation = 0;

  /// Session being watched (null when stopped).
  int? get sessionId => _sessionId;

  /// Watch [session], whose base radio is [baseNodeNum]. The base's place
  /// is the session map's base location, else where Radio Setup last saw
  /// it; without either there is nothing to measure from and it stays off.
  Future<void> start(Session session, int baseNodeNum) async {
    stop();
    if (DemoMode.enabled) return;
    final gen = ++_generation;
    final map = await _db.getCoverageMap(session.coverageMapId);
    LatLng? base;
    if (map?.baseLat != null && map?.baseLon != null) {
      base = LatLng(map!.baseLat!, map.baseLon!);
    } else if (_prefs != null) {
      base = BaseLocationStore(_prefs).load(baseNodeNum)?.point;
    }
    if (gen != _generation) return; // stopped meanwhile
    if (base == null) {
      DiagLog.instance.log('rideAlong', 'off: no base location');
      return;
    }
    _sessionId = session.id;
    _baseNodeNum = baseNodeNum;
    _base = base;
    _sessionStart = session.startedAt;
    DiagLog.instance.log('rideAlong', 'watching #${session.id}');
    _subs
      ..add(_positions.listen(_onPosition, onError: (_) {}))
      ..add(_signals.listen(_onSignal, onError: (_) {}))
      ..add(_pings.listen(_onPing, onError: (_) {}));
  }

  /// Session ended: forget everything (the next session may fire again).
  void stop() {
    _generation++;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _window.clear();
    _sessionId = null;
    _baseNodeNum = null;
    _base = null;
    _fired = false;
    pending.value = null;
  }

  /// "Keep going": hide the banner; it won't come back this session.
  void dismiss() {
    if (pending.value != null) {
      DiagLog.instance.log('rideAlong', 'dismissed');
    }
    pending.value = null;
  }

  void _onPosition(Position p) {
    final base = _base;
    if (base == null) return;
    final d = const Distance()
        .as(LengthUnit.Meter, base, LatLng(p.latitude, p.longitude));
    _add(RideAlongSample.fix(_clock(),
        speedMps: p.speed, accuracyM: p.accuracy, distanceM: d));
  }

  void _onSignal(ProcessedSignalEvent e) {
    if (e.sourceNodeId != _baseNodeNum || e.hopCount != 0 || e.viaMqtt) {
      return;
    }
    if (e.rxRssi == null && e.rxSnr == null) return;
    _add(RideAlongSample.signal(e.timestamp, rssi: e.rxRssi, snr: e.rxSnr));
  }

  void _onPing(PingSample s) {
    if (!s.fromBase || s.hops != 0 || (s.rssi == null && s.snr == null)) {
      return;
    }
    if (s.status != AckStatus.received) return;
    _add(RideAlongSample.signal(s.answeredAt, rssi: s.rssi, snr: s.snr));
  }

  /// Feed a sample directly (tests).
  @visibleForTesting
  void addSample(RideAlongSample s) => _add(s);

  void _add(RideAlongSample s) {
    if (_sessionId == null) return;
    final now = _clock();
    _window
      ..add(s)
      ..removeWhere((x) => now.difference(x.at) > rideAlongKeep);
    final shown = pending.value;
    if (_fired) {
      // Keep the banner's count current while it waits for an answer.
      if (shown != null && s.isSignal && !s.at.isBefore(shown.startedAt)) {
        pending.value = shown.withSamples(shown.samplesSince + 1);
      }
      return;
    }
    final event =
        evaluateRideAlong(_window, now: now, sessionStart: _sessionStart);
    if (event == null) return;
    _fired = true;
    DiagLog.instance.log(
        'rideAlong',
        'base riding along since ${event.startedAt.toIso8601String()}, '
            '${event.samplesSince} samples');
    pending.value = event;
    if (!_events.isClosed) _events.add(event);
    final monitor = _monitor;
    if (monitor != null && !monitor.isAppInForeground) {
      unawaited(monitor.notify(
        title: 'Base riding with you?',
        body: 'Strong signal from the base while you drive away from it. '
            'Open the app to stop the session and drop the points since '
            '${_hhmm(event.startedAt)}.',
      ));
    }
  }

  void dispose() {
    stop();
    pending.dispose();
    _events.close();
  }
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
