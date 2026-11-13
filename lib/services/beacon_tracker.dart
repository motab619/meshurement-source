// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import '../data/radio/radio_types.dart';

/// A place and time, for interpolating where a missed beacon would have
/// been heard.
class BeaconFix {
  final DateTime at;
  final double? lat;
  final double? lon;
  const BeaconFix(this.at, this.lat, this.lon);
}

/// Follows the base's beacon during a session: how many were heard, which
/// were missed, and whether the beacon seems to be off altogether.
///
/// Range Test beacons carry a sequence number, so a gap is an exact count of
/// misses. Telemetry beacons don't: a miss is a slot (last beacon + n *
/// interval) that passed by half an interval with nothing heard. The base
/// skips a send when its channel is busy, so timing-based misses are
/// slightly over-counted.
///
/// Trace beacons (MeshCore "pulled" beacon, [BeaconKind.trace]) are the
/// mobile's own trace pings to the base: an answer is a beacon heard
/// ([onBeacon]), a timeout one miss ([onTraceTimeout]). Every miss is a
/// known timeout, so nothing is made up from timing ([dueMisses] returns
/// nothing), and the beacon counts as [absent] after [absentIntervals]
/// timeouts in a row (the base stopped answering: out of range, switched
/// off, or no longer relaying), until the next answer.
///
/// "Absent": the base has been reachable (we hear its ping ACKs or other
/// packets) for 3 intervals with no beacon. Then silence is not a dead zone
/// and no misses are made up. Reachability is measured from when the base
/// was last heard *after a gap*, so the first ACK on coming back from a
/// dead zone doesn't count the dead zone's silence against the beacon.
class BeaconTracker {
  /// Beacon silence, in intervals, after which the beacon counts as off.
  static const absentIntervals = 3;

  /// How far past a slot (in intervals) we wait before calling it missed.
  static const missGraceIntervals = 0.5;

  BeaconKind _kind = BeaconKind.none;
  int _intervalSec = 0;
  int? _baseNodeId;
  DateTime? _startedAt;
  DateTime? _lastBeaconAt;
  DateTime? _lastBaseHeardAt;
  DateTime? _reachableSince;
  BeaconFix? _lastFix;
  DateTime? _nextSlot;
  int? _lastSeq;
  int _heard = 0;

  /// The session started without a beacon interval (the base was set up
  /// before this app version, or outside Radio Setup), so it is learned
  /// from the beacons themselves.
  bool _learningInterval = false;
  int? _learnedInterval;
  int _seqMissed = 0;
  int _traceMissed = 0;
  int _traceTimeoutsInARow = 0;
  bool _absent = false;

  final StreamController<bool> _absentController =
      StreamController<bool>.broadcast();

  bool get active => _baseNodeId != null;
  int? get baseNodeId => _baseNodeId;
  BeaconKind get kind => _kind;
  int get intervalSec => _intervalSec;

  /// Beacons heard this session.
  int get heard => _heard;

  /// Misses counted from sequence gaps (exact).
  int get seqMissed => _seqMissed;

  /// Trace pings that timed out this session (trace kind only; exact).
  int get traceMissed => _traceMissed;

  /// The base answers but its beacon is not arriving.
  bool get absent => _absent;
  Stream<bool> get absentStream => _absentController.stream;

  /// Begin following [baseNodeId]. [kind] none means unknown: the first
  /// beacon heard decides it (returned by [onBeacon] callers via [kind]).
  void start({
    required int baseNodeId,
    required BeaconKind kind,
    required int intervalSec,
    DateTime? now,
  }) {
    _baseNodeId = baseNodeId;
    _kind = kind;
    _intervalSec = intervalSec;
    _startedAt = now ?? DateTime.now();
    _lastBeaconAt = null;
    _lastBaseHeardAt = null;
    _reachableSince = null;
    _lastFix = null;
    _nextSlot = null;
    _lastSeq = null;
    _heard = 0;
    _seqMissed = 0;
    _traceMissed = 0;
    _traceTimeoutsInARow = 0;
    _learningInterval = intervalSec <= 0 && kind != BeaconKind.trace;
    _learnedInterval = null;
    _setAbsent(false);
  }

  /// A beacon interval learned since the last call (to save on the
  /// session), else null.
  int? takeLearnedInterval() {
    final v = _learnedInterval;
    _learnedInterval = null;
    return v;
  }

  /// Learn the interval from two beacons: Range Test's sequence numbers
  /// give it exactly; telemetry goes out on whole minutes, so the shortest
  /// gap seen, rounded to a minute (a missed beacon only lengthens a gap).
  void _learnInterval(DateTime at, int? seq) {
    final last = _lastBeaconAt;
    if (!_learningInterval || last == null) return;
    final gapMs = at.difference(last).inMilliseconds;
    int est;
    if (seq != null && _lastSeq != null && seq > _lastSeq!) {
      est = (gapMs / (seq - _lastSeq!) / 1000).round();
    } else if (seq == null && _kind == BeaconKind.telemetry) {
      est = (gapMs / 60000).round() * 60;
    } else {
      return;
    }
    if (est <= 0 || (_intervalSec > 0 && est >= _intervalSec)) return;
    _intervalSec = est;
    _learnedInterval = est;
  }

  /// The probe interval changed mid-session (trace kind: the base beacon
  /// or ping interval was changed in Radio Setup).
  void retune(int intervalSec) {
    if (!active) return;
    _intervalSec = intervalSec;
  }

  void stop() {
    _baseNodeId = null;
    _kind = BeaconKind.none;
    _intervalSec = 0;
    _lastBeaconAt = null;
    _lastBaseHeardAt = null;
    _reachableSince = null;
    _lastFix = null;
    _nextSlot = null;
    _setAbsent(false);
  }

  /// Does a packet of beacon kind [k] from the base count as a beacon? Yes
  /// when the session's kind is that, or still unknown.
  bool accepts(BeaconKind k) => _kind == BeaconKind.none || _kind == k;

  /// The base was heard directly (a ping ACK or any packet), proof it is
  /// reachable even when no beacon arrives.
  void onBaseHeard(DateTime at) => _noteReachable(at);

  /// Record the base as heard at [at]. A gap longer than the absence
  /// threshold since it was last heard starts a new stretch of
  /// reachability (we were in a dead zone, or the link was down).
  void _noteReachable(DateTime at) {
    final last = _lastBaseHeardAt;
    if (_reachableSince == null ||
        last == null ||
        at.difference(last) >
            Duration(seconds: _intervalSec) * absentIntervals) {
      _reachableSince = at;
    }
    _lastBaseHeardAt = at;
  }

  /// The phone could not hear beacons until [now] (its link to the radio
  /// was down): move the schedule past them so they are not called missed.
  void skipSlots(DateTime now) {
    var slot = _nextSlot;
    if (slot == null || _intervalSec <= 0) return;
    final interval = Duration(seconds: _intervalSec);
    while (!slot!.isAfter(now)) {
      slot = slot.add(interval);
    }
    _nextSlot = slot;
  }

  /// A beacon of [k] arrived from the base at [at], heard at [lat],[lon].
  /// Returns how many beacons the sequence number says were missed just
  /// before it (0 when the beacon has no sequence number).
  int onBeacon(
    BeaconKind k,
    DateTime at, {
    int? seq,
    double? lat,
    double? lon,
  }) {
    if (_kind == BeaconKind.none) _kind = k;
    _heard++;
    _traceTimeoutsInARow = 0;
    _learnInterval(at, seq);
    var missed = 0;
    if (seq != null) {
      final last = _lastSeq;
      // A lower number means the base restarted its counter.
      if (last != null && seq > last + 1) {
        missed = seq - last - 1;
        _seqMissed += missed;
      }
      _lastSeq = seq;
    }
    _lastBeaconAt = at;
    _noteReachable(at);
    _lastFix = BeaconFix(at, lat, lon);
    _nextSlot =
        _intervalSec > 0 ? at.add(Duration(seconds: _intervalSec)) : null;
    _setAbsent(false);
    return missed;
  }

  /// A trace ping to the base timed out at [at] (trace kind only): one
  /// beacon missed. After [absentIntervals] in a row the beacon counts as
  /// absent. Ignored for other kinds.
  void onTraceTimeout(DateTime at) {
    if (!active || _kind != BeaconKind.trace) return;
    _traceMissed++;
    _traceTimeoutsInARow++;
    if (_traceTimeoutsInARow >= absentIntervals) _setAbsent(true);
  }

  /// Slot times that passed without a beacon (telemetry only), oldest
  /// first, as of [now]. Also updates [absent]. Call while the link is up
  /// and the session records.
  List<DateTime> dueMisses(DateTime now) {
    // Trace misses are known timeouts ([onTraceTimeout]), never timing.
    if (!active ||
        _intervalSec <= 0 ||
        _kind == BeaconKind.none ||
        _kind == BeaconKind.trace) {
      return const [];
    }
    final interval = Duration(seconds: _intervalSec);
    // Silence counts from the last beacon, or from when the base became
    // reachable again if that is later (a dead zone is not the beacon's
    // fault).
    var silentSince = _lastBeaconAt ?? _startedAt!;
    final since = _reachableSince;
    if (since != null && since.isAfter(silentSince)) silentSince = since;
    final heardBase = _lastBaseHeardAt;
    final reachable = heardBase != null &&
        now.difference(heardBase) <= interval * absentIntervals;
    if (now.difference(silentSince) > interval * absentIntervals && reachable) {
      _setAbsent(true);
    }
    if (_absent || _kind != BeaconKind.telemetry) return const [];
    // Nothing to measure from until the first beacon fixes the schedule.
    var slot = _nextSlot;
    if (slot == null) return const [];
    final grace = Duration(
        milliseconds: (_intervalSec * 1000 * missGraceIntervals).round());
    final out = <DateTime>[];
    while (now.difference(slot!) > grace) {
      out.add(slot);
      slot = slot.add(interval);
    }
    _nextSlot = slot;
    return out;
  }

  /// Where the phone probably was at [slot]: a straight line from the last
  /// beacon's fix to the current one ([lat],[lon] at [now]). With only one
  /// end known, that one; with neither, null,null.
  (double?, double?) positionAt(
      DateTime slot, DateTime now, double? lat, double? lon) {
    final from = _lastFix;
    if (from == null ||
        from.lat == null ||
        from.lon == null ||
        lat == null ||
        lon == null) {
      return (lat ?? from?.lat, lon ?? from?.lon);
    }
    final span = now.difference(from.at).inMilliseconds;
    if (span <= 0) return (lat, lon);
    final f = (slot.difference(from.at).inMilliseconds / span).clamp(0.0, 1.0);
    return (
      from.lat! + (lat - from.lat!) * f,
      from.lon! + (lon - from.lon!) * f
    );
  }

  void _setAbsent(bool v) {
    if (_absent == v) return;
    _absent = v;
    if (!_absentController.isClosed) _absentController.add(v);
  }

  void dispose() => _absentController.close();
}
