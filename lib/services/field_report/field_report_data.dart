// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import '../../data/database/app_database.dart';
import '../../ui/protocol_text.dart';
import '../../utils/constants.dart';
import '../../utils/link_margin.dart';
import '../../utils/signal_color_mapper.dart';
import '../rig_math.dart';
import '../track_distance.dart';

export '../../utils/link_margin.dart' show MarginBand;

/// The numbers on a Field Report card (docs/design/field-report/README.md),
/// built from a session's packet events and ping outcomes with the same
/// sample rules as the maps and exports. Positions are kept only as metres
/// from the report's origin (the base, or the first fix when the base
/// location doesn't fit the session); no coordinates leave this file.

/// Two readings this close together make a distance count as the farthest
/// point (one GPS spike can't be the headline).
const farthestPairM = 50.0;

/// A session whose track centre is farther than this from its map's base
/// was filed on the wrong map: no distance from the base is shown.
const wrongMapM = 5000.0;

/// Time bins in the "Margin over the session" chart.
const marginBins = 12;

class MarginBucket {
  final MarginBand band;
  final int count;

  /// Share of readings, rounded to a whole percent.
  final int pct;

  const MarginBucket(this.band, this.count, this.pct);
}

/// A GPS fix on the track, metres east and north of the report origin.
class ReportFix {
  final DateTime t;
  final double x, y;

  const ReportFix(this.t, this.x, this.y);

  double get distanceM => math.sqrt(x * x + y * y);
}

/// A signal reading at the phone's position.
class ReportSample extends ReportFix {
  final double marginDb;

  const ReportSample(super.t, super.x, super.y, this.marginDb);
}

/// Where the card's positions are measured from.
enum ReportOrigin {
  /// The map's base location: distances from the base are shown.
  base,

  /// The session's first fix (base unknown or on another map): usually
  /// still home, so it is hidden the same way, but no distances.
  start,

  /// No fixes at all.
  none,
}

/// Things the card says in a small note line.
sealed class ReportNote {
  const ReportNote();
}

/// The track is far from its map's base: probably filed on the wrong map.
class WrongMapNote extends ReportNote {
  const WrongMapNote();
}

/// The map has no base location.
class NoBaseNote extends ReportNote {
  const NoBaseNote();
}

/// The farthest reading had no second reading near it, so a shorter
/// distance is the headline.
class SingleFarReadingNote extends ReportNote {
  final double distanceM;
  const SingleFarReadingNote(this.distanceM);
}

/// Base and mobile hardware and the range setting.
class ReportSetup {
  final String baseRadio, baseAntenna, mobileRadio, mobileAntenna;
  final int? txPowerDbm;
  final double? frequencyMhz;

  const ReportSetup({
    this.baseRadio = '',
    this.baseAntenna = '',
    this.mobileRadio = '',
    this.mobileAntenna = '',
    this.txPowerDbm,
    this.frequencyMhz,
  });
}

/// One session's rows, as read from the database.
class SessionReportInput {
  final Session session;

  /// Every packet event of the session, `telemetry_miss` and `log_only`
  /// rows included (they count for "base heard" only).
  final List<PacketEvent> events;

  /// Ping outcomes keyed by tx event id (`AppDatabase.getPingsForSession`).
  final Map<int, PingCorrelation> pings;

  /// Base radio's hardware model (node row), when no base rig was saved.
  final String baseHwModel;

  const SessionReportInput({
    required this.session,
    required this.events,
    this.pings = const {},
    this.baseHwModel = '',
  });
}

/// A position on the earth, only used while building (never stored).
typedef GeoPoint = ({double lat, double lon});

/// Metres east and north of [o] (equirectangular, fine for a few km).
(double, double) _metres(GeoPoint o, double lat, double lon) {
  const k = 111320.0;
  return (
    (lon - o.lon) * k * math.cos(o.lat * math.pi / 180),
    (lat - o.lat) * k,
  );
}

double _median(List<double> v) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// The SNR decode limit of a stored preset id, either protocol.
double snrFloorForPreset(String presetId) =>
    presetForId(presetId)?.snrFloorDb ?? SignalColorMapper.defaultSnrFloorDb;

class FieldReportData {
  final List<int> sessionIds;
  final DateTime startedAt;
  final Duration duration;
  final String presetId;

  /// "Short Turbo"; empty when the sessions don't share one.
  final String presetName;
  final double snrFloorDb;

  /// `sessions.protocol` of the first session.
  final String protocol;

  final ReportOrigin origin;

  /// Where (0, 0) is on the earth, kept in memory only so an optional map
  /// background can be placed under the route; never drawn or exported.
  final GeoPoint? geoOrigin;
  final List<ReportFix> track;
  final List<ReportSample> samples;
  final double routeM;

  /// Farthest distance from the base with a second reading near it; null
  /// when the origin isn't the base or nothing qualifies.
  final double? farthestM;
  final double? medianMarginDb;
  final List<MarginBucket> buckets;

  /// Median margin per time bin ([marginBins]), null where a bin is empty.
  final List<double?> marginOverTime;

  /// Beacons heard + pings answered, and beacons expected + pings on air.
  final int baseHeard, baseExpected;
  final ReportSetup setup;
  final List<ReportNote> notes;

  const FieldReportData({
    required this.sessionIds,
    required this.startedAt,
    required this.duration,
    required this.presetId,
    required this.presetName,
    required this.snrFloorDb,
    required this.protocol,
    required this.origin,
    this.geoOrigin,
    required this.track,
    required this.samples,
    required this.routeM,
    required this.farthestM,
    required this.medianMarginDb,
    required this.buckets,
    required this.marginOverTime,
    required this.baseHeard,
    required this.baseExpected,
    required this.setup,
    this.notes = const [],
  });

  /// Seed for the route's fixed rotation: the same session always turns
  /// the same way, so two shares of it can't be overlaid to undo it.
  int get rotationSeed => sessionIds.reduce(math.min);

  /// Base heard as a whole percent; null with nothing expected.
  int? get baseHeardPct =>
      baseExpected == 0 ? null : (100 * baseHeard / baseExpected).round();

  /// Build from one session or several (one side of a comparison).
  ///
  /// [base] is the map's base location. [fallbackOrigin] replaces the first
  /// fix as origin when the base can't be used (a comparison passes one so
  /// every side shares the grid). [forceStartOrigin] skips the base (the
  /// comparison decided it doesn't fit).
  factory FieldReportData.build(
    List<SessionReportInput> inputs, {
    GeoPoint? base,
    GeoPoint? fallbackOrigin,
    bool forceStartOrigin = false,
  }) {
    assert(inputs.isNotEmpty);
    final sessions = [for (final i in inputs) i.session];
    final first = sessions.reduce(
        (a, b) => a.startedAt.isBefore(b.startedAt) ? a : b);
    final floors = {
      for (final s in sessions) s.id: snrFloorForPreset(s.loraPreset),
    };
    final scales = {
      for (final s in sessions) s.id: MarginScale.forPresetId(s.loraPreset),
    };
    final presetIds = {for (final s in sessions) s.loraPreset};
    final presetId = presetIds.length == 1 ? presetIds.first : '';

    final allEvents = [
      for (final i in inputs) ...i.events,
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final fixEvents = [
      for (final e in allEvents)
        if (e.rxLat != null &&
            e.rxLon != null &&
            e.sourceKind != SourceKind.telemetryMiss)
          e,
    ];
    final sampleEvents = [
      for (final e in fixEvents)
        if (e.direction != PacketDirection.tx &&
            e.rxSnr != null &&
            !SourceKind.notSamples.contains(e.sourceKind))
          e,
    ];

    // Origin: the base, unless the track is far from it (wrong map).
    final notes = <ReportNote>[];
    var origin = ReportOrigin.none;
    GeoPoint? o;
    if (fixEvents.isNotEmpty) {
      var useBase = base != null && !forceStartOrigin;
      if (useBase) {
        final cLat =
            fixEvents.map((e) => e.rxLat!).reduce((a, b) => a + b) /
                fixEvents.length;
        final cLon =
            fixEvents.map((e) => e.rxLon!).reduce((a, b) => a + b) /
                fixEvents.length;
        final (dx, dy) = _metres(base, cLat, cLon);
        if (math.sqrt(dx * dx + dy * dy) > wrongMapM) {
          useBase = false;
          notes.add(const WrongMapNote());
        }
      } else if (base == null) {
        notes.add(const NoBaseNote());
      } else {
        notes.add(const WrongMapNote());
      }
      if (useBase) {
        o = base;
        origin = ReportOrigin.base;
      } else {
        o = fallbackOrigin ??
            (lat: fixEvents.first.rxLat!, lon: fixEvents.first.rxLon!);
        origin = ReportOrigin.start;
      }
    }

    ReportFix fix(PacketEvent e) {
      final (x, y) = _metres(o!, e.rxLat!, e.rxLon!);
      return ReportFix(e.timestamp, x, y);
    }

    final track = [for (final e in fixEvents) fix(e)];
    final samples = [
      for (final e in sampleEvents)
        () {
          final f = fix(e);
          return ReportSample(f.t, f.x, f.y,
              scales[e.sessionId]!.marginDb(snr: e.rxSnr, rssi: e.rxRssi)!);
        }(),
    ];
    final margins = [for (final s in samples) s.marginDb];

    // Route length per session (a side's sessions aren't one track).
    var routeM = 0.0;
    for (final i in inputs) {
      routeM += trackDistanceM(i.events);
    }

    // Farthest from the base, needing a second reading within 50 m.
    double? farthest;
    if (origin == ReportOrigin.base && samples.isNotEmpty) {
      final byDist = [...samples]
        ..sort((a, b) => b.distanceM.compareTo(a.distanceM));
      for (final s in byDist) {
        final paired = samples.any((t) =>
            !identical(t, s) &&
            t.t != s.t &&
            math.sqrt(math.pow(t.x - s.x, 2) + math.pow(t.y - s.y, 2)) <=
                farthestPairM);
        if (paired) {
          farthest = s.distanceM;
          break;
        }
      }
      final top = byDist.first.distanceM;
      if (farthest == null || top - farthest > farthestPairM) {
        notes.add(SingleFarReadingNote(top));
      }
    }

    final buckets = [
      for (final band in MarginBand.values)
        () {
          final n = margins.where((m) => MarginBand.of(m) == band).length;
          return MarginBucket(
              band, n, margins.isEmpty ? 0 : (100 * n / margins.length).round());
        }(),
    ];

    final bins = List<double?>.filled(marginBins, null);
    if (samples.length > 1) {
      final t0 = samples.first.t.millisecondsSinceEpoch;
      final span = samples.last.t.millisecondsSinceEpoch - t0;
      final perBin = List.generate(marginBins, (_) => <double>[]);
      for (final s in samples) {
        final i = span == 0
            ? 0
            : ((s.t.millisecondsSinceEpoch - t0) * marginBins ~/ span)
                .clamp(0, marginBins - 1);
        perBin[i].add(s.marginDb);
      }
      for (var i = 0; i < marginBins; i++) {
        if (perBin[i].isNotEmpty) bins[i] = _median(perBin[i]);
      }
    } else if (samples.length == 1) {
      bins[0] = samples.first.marginDb;
    }

    // Base heard: beacons heard + pings answered over beacons expected +
    // pings on air. NAKs and throttled pings never went on air.
    var heard = 0, expected = 0;
    for (final i in inputs) {
      final beaconRows = [
        for (final e in i.events)
          if (e.sourceKind == SourceKind.telemetry ||
              e.sourceKind == SourceKind.rangeTest ||
              e.sourceKind == SourceKind.telemetryMiss)
            e,
      ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final beacons = BeaconStats.fromRows(
          [for (final e in beaconRows) (e.sourceKind, e.seq)]);
      heard += beacons.heard;
      expected += beacons.heard + beacons.missed;
      for (final p in i.pings.values) {
        final st = p.ackStatus;
        if ((AckStatus.isError(st) && !AckStatus.isNoReply(st)) ||
            st == AckStatus.throttled) {
          continue; // never on air
        }
        expected++;
        if (st == AckStatus.received || st == AckStatus.implicit) heard++;
      }
    }

    var duration = Duration.zero;
    for (final i in inputs) {
      final s = i.session;
      final end = s.endedAt ??
          (i.events.isEmpty
              ? s.startedAt
              : i.events
                  .map((e) => e.timestamp)
                  .reduce((a, b) => a.isAfter(b) ? a : b));
      if (end.isAfter(s.startedAt)) duration += end.difference(s.startedAt);
    }

    return FieldReportData(
      sessionIds: [for (final s in sessions) s.id],
      startedAt: first.startedAt,
      duration: duration,
      presetId: presetId,
      presetName: presetId.isEmpty ? '' : anyPresetDisplayName(presetId),
      snrFloorDb: presetId.isEmpty
          ? floors[first.id]!
          : snrFloorForPreset(presetId),
      protocol: first.protocol,
      origin: origin,
      geoOrigin: o,
      track: track,
      samples: samples,
      routeM: routeM,
      farthestM: farthest,
      medianMarginDb: margins.isEmpty ? null : _median(margins),
      buckets: buckets,
      marginOverTime: bins,
      baseHeard: heard,
      baseExpected: expected,
      setup: _setup(first, inputs.first.baseHwModel),
      notes: notes,
    );
  }

  static ReportSetup _setup(Session s, String baseHwModel) {
    final mobile = RigSpec.decode(s.mobileRigJson);
    final baseRig = RigSpec.decode(s.baseRigJson);
    String pick(String? a, String b) =>
        (a != null && a.trim().isNotEmpty) ? a.trim() : b.trim();
    return ReportSetup(
      mobileRadio: pick(mobile?.radioModel, radioModelName(s.hwNodeModel).isEmpty
          ? s.hwNodeModel
          : radioModelName(s.hwNodeModel)),
      mobileAntenna: pick(mobile?.antennaName, s.hwAntenna),
      baseRadio: pick(baseRig?.radioModel, radioModelName(baseHwModel)),
      baseAntenna: pick(baseRig?.antennaName, ''),
      txPowerDbm: s.txPowerDbm,
      frequencyMhz: s.frequencyMhz,
    );
  }
}
