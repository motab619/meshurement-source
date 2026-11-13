// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../data/database/app_database.dart';
import '../data/radio/meshtastic/meshtastic_presets.dart';
import '../data/radio/radio_preset.dart';
import '../utils/constants.dart';
import 'airtime_model.dart';
import 'link_asymmetry.dart';
import 'rig_comparison.dart' show median;

// Distance-from-base statistics for one or two groups of sessions. Pure
// Dart: everything (including the headline text) is derived from numbers,
// so it is deterministic and can also be fed to a summary elsewhere.

const _dist = Distance();

/// Success bands, metres from the base: [lo, hi); the last has no upper end.
const rangeBandEdgesM = [0.0, 300.0, 500.0, 700.0, 1000.0];

/// The band that headline logic looks at (300 up to 1000 m).
const headlineBandFromM = 300.0;
const headlineBandToM = 1000.0;

/// A side whose share of pings sent within [flatterRadiusM] of the base
/// exceeds [flatterShare] has an overall ACK rate that is flattered.
const flatterRadiusM = 200.0;
const flatterShare = 0.6;

/// Farthest ACKs within this fraction of each other count as a similar ceiling.
const similarCeilingFraction = 0.15;

/// Band success rates must differ by at least this many points to decide.
const _rateDecisiveGap = 0.05;

/// With this many matched cells or fewer the routes are treated as not
/// overlapping (too little to isolate the preset).
const smallOverlapCells = 5;

/// A "where each side led" line needs at least this much between the sides:
/// SNR in dB, distance as a share of the farther one and in metres.
const strengthSnrGapDb = 3.0;
const strengthDistanceGapFraction = 0.05;
const strengthDistanceGapM = 30.0;

/// Margin above a preset's decode floor before it is suggested as a faster
/// alternative.
const presetSuggestMarginDb = 3.0;

/// Named Meshtastic presets a faster-preset suggestion may pick from.
const standardPresets = [
  MeshtasticPresets.shortTurbo,
  MeshtasticPresets.shortFast,
  MeshtasticPresets.shortSlow,
  MeshtasticPresets.mediumFast,
  MeshtasticPresets.mediumSlow,
  MeshtasticPresets.longTurbo,
  MeshtasticPresets.longFast,
  MeshtasticPresets.longModerate,
  MeshtasticPresets.longSlow,
];

/// How the base position was found, best first.
enum BaseMethod {
  placedByUser('placed by you'),
  baseNode("the base node's reported position"),
  radioSetup('Node Setup'),
  estimated('estimated from the stationary start and end points');

  final String label;
  const BaseMethod(this.label);

  /// Footnote sentence (no coordinates).
  String get footnote => switch (this) {
        BaseMethod.placedByUser => 'Base position placed by you on the map.',
        BaseMethod.baseNode =>
          "Base position from the base node's own reported position.",
        BaseMethod.radioSetup => 'Base position from Node Setup.',
        BaseMethod.estimated =>
          'Base position estimated from the stationary start and end points '
              'of the sessions.',
      };
}

class ResolvedBase {
  final LatLng point;
  final BaseMethod method;

  const ResolvedBase(this.point, this.method);
}

/// Base position: user placement, else the base node's own position, else
/// the position remembered by Radio Setup, else [estimateBase]. Null when
/// none of them gives one.
ResolvedBase? resolveBase({
  LatLng? userBase,
  LatLng? nodeBase,
  LatLng? radioSetupBase,
  List<PacketEvent> events = const [],
}) {
  if (userBase != null) return ResolvedBase(userBase, BaseMethod.placedByUser);
  if (nodeBase != null) return ResolvedBase(nodeBase, BaseMethod.baseNode);
  if (radioSetupBase != null) {
    return ResolvedBase(radioSetupBase, BaseMethod.radioSetup);
  }
  final est = estimateBase(events);
  return est == null ? null : ResolvedBase(est, BaseMethod.estimated);
}

/// Radius within which the first / last positions of sessions must agree
/// for [estimateBase] to call them "the base".
const baseClusterRadiusM = 100.0;

/// Estimates the base from where the sessions started and ended. A mobile
/// walk normally starts and ends next to the base, so the first and last
/// GPS position of every session are collected and the densest cluster
/// (most points within [baseClusterRadiusM] of one point) is averaged.
/// Needs at least two points in the cluster; null otherwise (a one-way
/// walk gives no stationary evidence).
LatLng? estimateBase(List<PacketEvent> events) {
  final bySession = <int, List<PacketEvent>>{};
  for (final e in events) {
    if (e.rxLat == null || e.rxLon == null) continue;
    bySession.putIfAbsent(e.sessionId, () => []).add(e);
  }
  final pts = <LatLng>[];
  for (final list in bySession.values) {
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    pts.add(LatLng(list.first.rxLat!, list.first.rxLon!));
    if (list.length > 1) pts.add(LatLng(list.last.rxLat!, list.last.rxLon!));
  }
  List<LatLng> best = const [];
  for (final p in pts) {
    final near = [
      for (final q in pts)
        if (_dist(p, q) <= baseClusterRadiusM) q,
    ];
    if (near.length > best.length) best = near;
  }
  if (best.length < 2) return null;
  final lat = best.map((p) => p.latitude).reduce((a, b) => a + b) / best.length;
  final lon =
      best.map((p) => p.longitude).reduce((a, b) => a + b) / best.length;
  return LatLng(lat, lon);
}

/// One ping with where it was sent from and how it ended.
class PingPoint {
  final double distanceM;

  /// Metres east / north of the base (flat approximation, fine under ~10 km).
  final double eastM, northM;

  /// A real ACK from the base.
  final bool acked;

  /// Acked only by a relaying node (not counted as acked).
  final bool implicit;

  /// SNR / RSSI of the base's ACK, null when none: a base → you reading.
  final double? snr;
  final int? rssi;

  /// How well the base heard the ping (you → base, dB): MeshCore traces
  /// only, null otherwise.
  final double? uplinkSnr;
  final int? roundTripMs;

  const PingPoint({
    required this.distanceM,
    required this.eastM,
    required this.northM,
    required this.acked,
    required this.implicit,
    this.snr,
    this.rssi,
    this.uplinkSnr,
    this.roundTripMs,
  });

  bool get missed => !acked && !implicit;
}

class RoutePoint {
  final double eastM, northM, distanceM;

  const RoutePoint(this.eastM, this.northM, this.distanceM);
}

class BandStat {
  final double fromM;

  /// Null for the open-ended last band.
  final double? toM;
  final int sent, acked;

  const BandStat(this.fromM, this.toM, this.sent, this.acked);

  /// 0..1, null when no ping was sent in the band.
  double? get rate => sent == 0 ? null : acked / sent;

  String get label {
    String m(double v) => v.round().toString();
    return toM == null ? '${m(fromM)}+ m' : '${m(fromM)}–${m(toM!)} m';
  }
}

class SideRangeStats {
  final String name;
  final int sessionCount;

  /// Pings that went on air (throttled ones never did and are left out).
  final int pingsSent;

  /// ACK from the base itself.
  final int pingsAcked;

  /// ACK from a relaying node only; counted separately, not as acked.
  final int pingsImplicit;
  final List<BandStat> bands;

  /// Pings with a known position.
  final List<PingPoint> pings;

  /// Walked path, one list per session.
  final List<List<RoutePoint>> routes;
  final double? farthestAckM;

  /// Distance of the closest ping that went unanswered.
  final double? firstMissM;
  final double farthestWalkedM;

  /// Farthest rx packet from the base.
  final double? heardBaseOutToM;
  final double? medianRoundTripMs;
  final double? medianSnr, medianRssi;
  final double packetAirtimeMs;

  /// Highest radio-reported channel utilisation / own air utilisation (%).
  final double? channelUtilPct, airUtilTxPct;
  final int pingsWithin200m;

  /// The one modem preset all of this side's sessions used; '' when they
  /// differ or none recorded one.
  final String presetId;

  /// Radio settings this side's sessions recorded (schema v9), each the set
  /// of distinct values; empty when no session recorded one.
  final Set<int> frequencySlots;
  final Set<double> frequenciesMHz;
  final Set<int> txPowersDbm;
  final Set<int> hopLimits;

  /// Received packets from nodes other than the map's base, by node DB id
  /// (ACKs are left out: see [acksFromOtherNodes] and [pingsImplicit]). On a
  /// private test channel these are usually a second base left on. Empty
  /// when the base node is unknown.
  final Map<int, int> otherNodesHeard;

  /// Direct ACKs (status received) that came from a node other than the
  /// map's base, by node DB id: the pings were aimed at a different radio.
  final Map<int, int> acksFromOtherNodes;

  const SideRangeStats({
    required this.name,
    required this.sessionCount,
    required this.pingsSent,
    required this.pingsAcked,
    required this.pingsImplicit,
    required this.bands,
    required this.pings,
    required this.routes,
    required this.farthestAckM,
    required this.firstMissM,
    required this.farthestWalkedM,
    required this.heardBaseOutToM,
    required this.medianRoundTripMs,
    required this.medianSnr,
    required this.medianRssi,
    required this.packetAirtimeMs,
    required this.channelUtilPct,
    required this.airUtilTxPct,
    required this.pingsWithin200m,
    this.presetId = '',
    this.frequencySlots = const {},
    this.frequenciesMHz = const {},
    this.txPowersDbm = const {},
    this.hopLimits = const {},
    this.otherNodesHeard = const {},
    this.acksFromOtherNodes = const {},
  });

  /// 0..1, null without pings.
  double? get ackRate => pingsSent == 0 ? null : pingsAcked / pingsSent;

  /// Median SNR of the base's ACKs to pings sent from [fromM] (inclusive)
  /// up to [toM] (exclusive, open when null); null with fewer than
  /// [minCount] such ACKs.
  double? medianAckSnr({double fromM = 0, double? toM, int minCount = 3}) {
    final v = [
      for (final p in pings)
        if (p.acked &&
            p.snr != null &&
            p.distanceM >= fromM &&
            (toM == null || p.distanceM < toM))
          p.snr!,
    ];
    return v.length < minCount ? null : median(v);
  }

  /// Same for RSSI (dBm).
  double? medianAckRssi({double fromM = 0, double? toM, int minCount = 3}) {
    final v = [
      for (final p in pings)
        if (p.acked &&
            p.rssi != null &&
            p.distanceM >= fromM &&
            (toM == null || p.distanceM < toM))
          p.rssi!.toDouble(),
    ];
    return v.length < minCount ? null : median(v);
  }

  /// Median ACK SNR at the edge (300 m and beyond) / close in (under 300 m).
  double? get edgeAckSnr => medianAckSnr(fromM: headlineBandFromM);
  double? get closeAckSnr => medianAckSnr(toM: headlineBandFromM);

  /// Uplink vs downlink SNR over this side's replies that carry both
  /// (MeshCore traces); null without enough of them.
  LinkAsymmetry? get linkAsymmetry => linkAsymmetryOf([
        for (final p in pings)
          if (p.acked && p.snr != null && p.uplinkSnr != null)
            (up: p.uplinkSnr!, down: p.snr!),
      ]);

  /// Pings in the 300–1000 m band.
  int get headlineBandSent => _headlineBand.$1;
  int get headlineBandAcked => _headlineBand.$2;
  double? get headlineBandRate =>
      headlineBandSent == 0 ? null : headlineBandAcked / headlineBandSent;

  (int, int) get _headlineBand {
    var s = 0, a = 0;
    for (final b in bands) {
      if (b.fromM >= headlineBandFromM &&
          (b.toM ?? double.infinity) <= headlineBandToM) {
        s += b.sent;
        a += b.acked;
      }
    }
    return (s, a);
  }
}

/// A route that never comes closer than this to the base means the base
/// location is probably wrong, not that the walk started far away.
const baseMisplacedM = 2000.0;

class RangeComparison {
  final ResolvedBase base;
  final SideRangeStats a, b;

  /// Shared plot scale: farthest point of either side, metres.
  final double maxDistanceM;

  /// Nearest any route point of either side came to the base, metres
  /// (infinity with no positions).
  final double nearestPointM;

  /// Every point is far from the base: the map's base location is
  /// probably wrong (a map made with a stale Radio Setup location, 2026-10-27).
  bool get baseLooksMisplaced =>
      nearestPointM.isFinite && nearestPointM > baseMisplacedM;

  /// Null side = no clear winner.
  final String headline;
  final String summary;
  final bool? aWins;

  /// "Reading it" bullets.
  final List<String> readingIt;
  final String footnote;

  /// What the two tests proved together; null when a side sent no pings.
  final String? proved;

  /// One line per side naming the measures it led on, with the margin; or a
  /// single line saying the sides were equivalent.
  final List<String> strengths;

  /// Data-quality notes: another radio heard, answers from a node other than
  /// the base, relay-only ACKs.
  final List<String> dataNotes;

  /// One concrete thing to do next.
  final String? nextStep;

  const RangeComparison({
    required this.base,
    required this.a,
    required this.b,
    required this.maxDistanceM,
    this.nearestPointM = double.infinity,
    required this.headline,
    required this.summary,
    required this.aWins,
    required this.readingIt,
    required this.footnote,
    this.proved,
    this.strengths = const [],
    this.dataNotes = const [],
    this.nextStep,
  });
}

/// Stats of one side. [events] may hold other sessions' events too.
/// Each session's own base radio (`Session.baseNodeId`, schema v8) decides
/// what counts as "the base"; [baseNodeDbId] (the map's pre-v8 base) is
/// the fallback for sessions without one.
SideRangeStats computeSideStats({
  required String name,
  required List<Session> sessions,
  required List<PacketEvent> events,
  required List<PingCorrelation> correlations,
  required LatLng base,
  int? baseNodeDbId,
}) {
  final ids = {for (final s in sessions) s.id};
  final baseOf = {for (final s in sessions) s.id: s.baseNodeId ?? baseNodeDbId};
  bool notBase(PacketEvent e) {
    final b = baseOf[e.sessionId];
    return b != null && e.sourceNodeId != b;
  }

  final mine = [
    for (final e in events)
      if (ids.contains(e.sessionId)) e,
  ];
  final byId = {for (final e in mine) e.id: e};

  final cosLat = math.cos(base.latitude * math.pi / 180);
  const mPerDeg = 111320.0;
  double east(double lon) => (lon - base.longitude) * mPerDeg * cosLat;
  double north(double lat) => (lat - base.latitude) * mPerDeg;
  RoutePoint routePoint(double lat, double lon) =>
      RoutePoint(east(lon), north(lat), _dist(base, LatLng(lat, lon)));

  // Route and farthest point walked.
  final perSession = <int, List<PacketEvent>>{};
  for (final e in mine) {
    if (e.rxLat == null || e.rxLon == null) continue;
    perSession.putIfAbsent(e.sessionId, () => []).add(e);
  }
  final routes = <List<RoutePoint>>[];
  var farthestWalked = 0.0;
  for (final list in perSession.values) {
    list.sort((x, y) => x.timestamp.compareTo(y.timestamp));
    final r = [for (final e in list) routePoint(e.rxLat!, e.rxLon!)];
    for (final p in r) {
      farthestWalked = math.max(farthestWalked, p.distanceM);
    }
    routes.add(r);
  }

  // Pings.
  var sent = 0, acked = 0, implicit = 0, within200 = 0;
  final acksFromOthers = <int, int>{};
  final pings = <PingPoint>[];
  final bandSent = List.filled(rangeBandEdgesM.length, 0);
  final bandAcked = List.filled(rangeBandEdgesM.length, 0);
  final roundTrips = <double>[];
  for (final c in correlations) {
    final tx = byId[c.txEventId];
    if (tx == null) continue;
    if (c.ackStatus == AckStatus.throttled) continue; // never transmitted
    final ok = c.ackStatus == AckStatus.received;
    final imp = c.ackStatus == AckStatus.implicit;
    sent++;
    if (ok) acked++;
    if (imp) implicit++;
    if (ok && c.roundTripMs != null) roundTrips.add(c.roundTripMs!.toDouble());
    if (tx.rxLat == null || tx.rxLon == null) continue;
    final rp = routePoint(tx.rxLat!, tx.rxLon!);
    final ack = c.ackEventId == null ? null : byId[c.ackEventId!];
    if (ok && ack != null && notBase(ack)) {
      acksFromOthers[ack.sourceNodeId] =
          (acksFromOthers[ack.sourceNodeId] ?? 0) + 1;
    }
    pings.add(PingPoint(
      distanceM: rp.distanceM,
      eastM: rp.eastM,
      northM: rp.northM,
      acked: ok,
      implicit: imp,
      snr: ack?.rxSnr,
      rssi: ack?.rxRssi,
      uplinkSnr: ack?.uplinkSnr,
      roundTripMs: c.roundTripMs,
    ));
    if (rp.distanceM < flatterRadiusM) within200++;
    final band = _bandIndex(rp.distanceM);
    bandSent[band]++;
    if (ok) bandAcked[band]++;
  }
  final bands = [
    for (var i = 0; i < rangeBandEdgesM.length; i++)
      BandStat(
          rangeBandEdgesM[i],
          i + 1 < rangeBandEdgesM.length ? rangeBandEdgesM[i + 1] : null,
          bandSent[i],
          bandAcked[i]),
  ];
  double? farthestAck, firstMiss;
  for (final p in pings) {
    if (p.acked) {
      farthestAck = math.max(farthestAck ?? 0, p.distanceM);
    } else if (p.missed) {
      firstMiss = math.min(firstMiss ?? double.infinity, p.distanceM);
    }
  }

  // Packets heard from the base (received packets and ping ACKs), and
  // anything heard from other nodes.
  final snrs = <double>[], rssis = <double>[];
  final otherHeard = <int, int>{};
  double? heardOut;
  for (final e in mine) {
    if (e.direction == PacketDirection.tx) continue;
    // Misses and log-only packets are not samples.
    if (SourceKind.notSamples.contains(e.sourceKind)) continue;
    if (notBase(e)) {
      // Relay ACKs are attributed to whoever relayed (often our own node)
      // and are already reported as implicit; only received packets count
      // as "another radio on the channel".
      if (e.direction != PacketDirection.ack) {
        otherHeard[e.sourceNodeId] = (otherHeard[e.sourceNodeId] ?? 0) + 1;
      }
      continue;
    }
    if (e.rxSnr != null) snrs.add(e.rxSnr!);
    if (e.rxRssi != null) rssis.add(e.rxRssi!.toDouble());
    if (e.rxLat != null && e.rxLon != null) {
      heardOut =
          math.max(heardOut ?? 0, _dist(base, LatLng(e.rxLat!, e.rxLon!)));
    }
  }

  double? maxOf(Iterable<double?> v) {
    final l = v.whereType<double>().toList();
    return l.isEmpty ? null : l.reduce(math.max);
  }

  final airtimes = [
    for (final s in sessions)
      if (s.packetAirtimeMs > 0) s.packetAirtimeMs,
  ];
  final presetIds = {
    for (final s in sessions)
      if (s.loraPreset.isNotEmpty) s.loraPreset,
  };
  return SideRangeStats(
    name: name,
    sessionCount: sessions.length,
    pingsSent: sent,
    pingsAcked: acked,
    pingsImplicit: implicit,
    bands: bands,
    pings: pings,
    routes: routes,
    farthestAckM: farthestAck,
    firstMissM: firstMiss == double.infinity ? null : firstMiss,
    farthestWalkedM: farthestWalked,
    heardBaseOutToM: heardOut,
    medianRoundTripMs: roundTrips.isEmpty ? null : median(roundTrips),
    medianSnr: snrs.isEmpty ? null : median(snrs),
    medianRssi: rssis.isEmpty ? null : median(rssis),
    packetAirtimeMs: airtimes.isEmpty ? 0 : median(airtimes),
    channelUtilPct: maxOf(sessions.map((s) => s.radioChannelUtil)),
    airUtilTxPct: maxOf(sessions.map((s) => s.radioAirUtilTx)),
    pingsWithin200m: within200,
    presetId: presetIds.length == 1 ? presetIds.first : '',
    frequencySlots: {...sessions.map((s) => s.frequencySlot).nonNulls},
    frequenciesMHz: {...sessions.map((s) => s.frequencyMhz).nonNulls},
    txPowersDbm: {...sessions.map((s) => s.txPowerDbm).nonNulls},
    hopLimits: {...sessions.map((s) => s.hopLimit).nonNulls},
    otherNodesHeard: otherHeard,
    acksFromOtherNodes: acksFromOthers,
  );
}

int _bandIndex(double m) {
  for (var i = rangeBandEdgesM.length - 1; i > 0; i--) {
    if (m >= rangeBandEdgesM[i]) return i;
  }
  return 0;
}

/// Everything for the "By distance from base" section. Null when no base
/// position can be found (nothing to measure distance from).
///
/// [events] and [correlations] may cover the whole coverage map; they are
/// filtered to the sessions of each side. [matchedCells] is the number of
/// cells the two routes overlap in (0 when they do not).
RangeComparison? compareRange({
  required List<Session> sessionsA,
  required List<Session> sessionsB,
  required List<PacketEvent> events,
  required List<PingCorrelation> correlations,
  required String nameA,
  required String nameB,
  LatLng? userBase,
  LatLng? nodeBase,
  LatLng? radioSetupBase,
  int? baseNodeDbId,
  int matchedCells = 0,
  Map<int, String> nodeNames = const {},
}) {
  final ids = {
    for (final s in [...sessionsA, ...sessionsB]) s.id
  };
  final base = resolveBase(
    userBase: userBase,
    nodeBase: nodeBase,
    radioSetupBase: radioSetupBase,
    events: [
      for (final e in events)
        if (ids.contains(e.sessionId)) e,
    ],
  );
  if (base == null) return null;
  final a = computeSideStats(
      name: nameA,
      sessions: sessionsA,
      events: events,
      correlations: correlations,
      base: base.point,
      baseNodeDbId: baseNodeDbId);
  final b = computeSideStats(
      name: nameB,
      sessions: sessionsB,
      events: events,
      correlations: correlations,
      base: base.point,
      baseNodeDbId: baseNodeDbId);
  final maxD = [a.farthestWalkedM, b.farthestWalkedM].reduce(math.max);
  var nearest = double.infinity;
  for (final route in [...a.routes, ...b.routes]) {
    for (final p in route) {
      nearest = math.min(nearest, p.distanceM);
    }
  }
  final text =
      rangeNarrative(a, b, matchedCells: matchedCells, nodeNames: nodeNames);
  return RangeComparison(
    base: base,
    a: a,
    b: b,
    maxDistanceM: maxD,
    nearestPointM: nearest,
    headline: text.headline,
    summary: text.summary,
    aWins: text.aWins,
    readingIt: text.readingIt,
    footnote: base.method.footnote,
    proved: text.proved,
    strengths: text.strengths,
    dataNotes: text.dataNotes,
    nextStep: text.nextStep,
  );
}

class RangeNarrative {
  final String headline, summary;
  final bool? aWins;
  final List<String> readingIt;
  final String? proved;
  final List<String> strengths, dataNotes;
  final String? nextStep;

  const RangeNarrative(this.headline, this.summary, this.aWins, this.readingIt,
      {this.proved,
      this.strengths = const [],
      this.dataNotes = const [],
      this.nextStep});
}

String _pct(double rate) => '${(rate * 100).round()}%';
String _m(double v) => '${v.round()} m';

/// Headline, 2–3 sentence summary and "Reading it" bullets, plus the parts
/// that keep a tie from reading as "nothing happened": what the two tests
/// proved together, where each side led (with the margin), data-quality
/// notes and one concrete next step. All from numbers.
///
/// Winner: higher ACK rate in the 300–1000 m band (needs both sides to
/// have pings there and a gap of 5+ points), else the farther farthest ACK,
/// else the higher overall ACK rate.
RangeNarrative rangeNarrative(SideRangeStats a, SideRangeStats b,
    {int matchedCells = 0, Map<int, String> nodeNames = const {}}) {
  bool? aWins;
  final ra = a.headlineBandRate, rb = b.headlineBandRate;
  if (ra != null && rb != null && (ra - rb).abs() >= _rateDecisiveGap) {
    aWins = ra > rb;
  } else {
    final fa = a.farthestAckM ?? 0, fb = b.farthestAckM ?? 0;
    if (fa != fb && !_similar(fa, fb)) {
      aWins = fa > fb;
    } else if (a.ackRate != null &&
        b.ackRate != null &&
        (a.ackRate! - b.ackRate!).abs() >= _rateDecisiveGap) {
      aWins = a.ackRate! > b.ackRate!;
    }
  }
  final win = aWins == null ? null : (aWins ? a : b);
  final lose = aWins == null ? null : (aWins ? b : a);

  final bothPinged = a.pingsSent > 0 && b.pingsSent > 0;
  final lostA = _lostBase(a), lostB = _lostBase(b);
  final bothLost = lostA && lostB;
  final neitherLost = bothPinged && !lostA && !lostB;
  final fa = a.farthestAckM, fb = b.farthestAckM;
  final sameCeiling =
      fa != null && fb != null && fa > 0 && fb > 0 && _similar(fa, fb);

  final String headline;
  if (win == null) {
    if (neitherLost) {
      headline = 'Both held the link over the whole route';
    } else if (bothLost && sameCeiling) {
      headline = 'Too close to call: both hit the same wall near '
          '${_near50(math.max(fa, fb))}';
    } else {
      headline = 'Too close to call';
    }
  } else if ((win.farthestAckM ?? 0) >= (lose!.farthestAckM ?? 0)) {
    headline = '${win.name} held the link farther than ${lose.name}';
  } else {
    headline = '${win.name} held the link better than ${lose.name}';
  }

  final sentences = <String>[];

  // 1. Where the base was lost.
  if (lostA && lostB) {
    final floor = math.min(a.farthestAckM ?? 0, b.farthestAckM ?? 0) / 100;
    final past = (floor.floor() * 100);
    sentences.add(past >= 100
        ? 'Both lost the base somewhere past $past m.'
        : 'Both lost the base within 100 m.');
  } else if (lostA != lostB) {
    final held = lostA ? b : a;
    sentences.add('${(lostA ? a : b).name} lost the base; '
        '${held.name} kept an answer out to '
        '${_m(held.farthestAckM ?? held.farthestWalkedM)}.');
  } else if (bothPinged) {
    sentences.add('Neither side lost the base on this walk.');
  }

  // 2. The 300–1000 m band.
  String bandPart(SideRangeStats s, {bool withMiss = false}) {
    final r = s.headlineBandRate;
    if (r == null) return '${s.name} sent no pings in that band';
    final miss = withMiss && s.firstMissM != null
        ? ' and dropped its first ping at ${_m(s.firstMissM!)}'
        : '';
    return '${s.name} kept ${_pct(r)} of pings acknowledged$miss';
  }

  if (ra != null || rb != null) {
    final first = win ?? a, second = lose ?? b;
    sentences.add('In the ${headlineBandFromM.round()}–'
        '${headlineBandToM.round()} m band, ${bandPart(first)}; '
        '${bandPart(second, withMiss: true)}.');
  }

  // 3. Speed and channel use.
  final speed = _answeredFaster(a, b);
  final chan = _channelRatio(a, b);
  String? chanText;
  if (chan != null) {
    chanText = 'used ${_fraction(chan.$2)} of the channel';
  }
  if (speed != null && chan != null && speed == chan.$1) {
    sentences.add('${speed.name} answered faster and $chanText.');
  } else {
    if (speed != null) sentences.add('${speed.name} answered faster.');
    if (chan != null) sentences.add('${chan.$1.name} $chanText.');
  }

  // What the test proved. A tie is a finding too.
  String? proved;
  if (bothPinged) {
    if (bothLost && sameCeiling) {
      final rssi = _edgeRssi(a, b);
      proved = 'You proved the link here is terrain-limited: both sides '
          'stopped getting answers at about the same distance '
          '(${_m(fa)} vs ${_m(fb)})'
          '${rssi == null ? '' : ', with the last answers near ${rssi.round()} dBm'}'
          '. A different antenna will not move that edge much; raising or '
          'moving the base will.';
    } else if (neitherLost) {
      final far = math.max(fa ?? 0, fb ?? 0);
      proved = 'You proved both setups cover this whole route: ${a.name} '
          'answered ${a.pingsAcked} of ${a.pingsSent} pings and ${b.name} '
          '${b.pingsAcked} of ${b.pingsSent}, out to ${_m(far)}.';
    } else if (lostA != lostB) {
      final held = lostA ? b : a, lost = lostA ? a : b;
      proved = 'You proved ${held.name} reaches where ${lost.name} does not: '
          '${lost.name} ${_lastAnswer(lost)}, ${held.name} was still '
          'answered at ${_m(held.farthestAckM ?? held.farthestWalkedM)}.';
    } else if (bothLost) {
      final farSide = (fa ?? 0) >= (fb ?? 0) ? a : b;
      final nearSide = farSide == a ? b : a;
      final gap = (farSide.farthestAckM ?? 0) - (nearSide.farthestAckM ?? 0);
      proved = 'You proved ${farSide.name} holds the link farther here: last '
          'answer at ${_m(farSide.farthestAckM ?? 0)} against '
          '${nearSide.name} which ${_lastAnswer(nearSide)}, ${_m(gap)} more.';
    }
  }

  // Where each side led. Every line carries its margin.
  final ledA = <String>[], ledB = <String>[];
  void led(SideRangeStats s, String what) =>
      (identical(s, a) ? ledA : ledB).add(what);
  if (ra != null && rb != null && (ra - rb).abs() >= _rateDecisiveGap) {
    led(
        ra > rb ? a : b,
        'kept more pings answered between ${headlineBandFromM.round()} and '
        '${headlineBandToM.round()} m (${_pct(math.max(ra, rb))} vs '
        '${_pct(math.min(ra, rb))})');
  }
  if (fa != null && fb != null && fa != fb) {
    final gap = (fa - fb).abs();
    if (gap >= strengthDistanceGapM &&
        gap / math.max(fa, fb) >= strengthDistanceGapFraction) {
      led(
          fa > fb ? a : b,
          'reached the farthest answered ping (${_m(math.max(fa, fb))} vs '
          '${_m(math.min(fa, fb))}${sameCeiling ? ', a small margin' : ''})');
    }
  }
  final ea = a.edgeAckSnr, eb = b.edgeAckSnr;
  if (ea != null && eb != null && (ea - eb).abs() >= strengthSnrGapDb) {
    led(
        ea > eb ? a : b,
        'held cleaner contact at the edge (median ACK SNR '
        '${_db(math.max(ea, eb))} vs ${_db(math.min(ea, eb))} past '
        '${headlineBandFromM.round()} m)');
  }
  final ca = a.closeAckSnr, cb = b.closeAckSnr;
  if (ca != null && cb != null && (ca - cb).abs() >= strengthSnrGapDb) {
    led(
        ca > cb ? a : b,
        'came in stronger close to the base (median ACK SNR '
        '${_db(math.max(ca, cb))} vs ${_db(math.min(ca, cb))} within '
        '${headlineBandFromM.round()} m)');
  }
  if (speed != null) {
    final x = a.medianRoundTripMs!, y = b.medianRoundTripMs!;
    led(speed,
        'answered faster (median ${_sec(math.min(x, y))} vs ${_sec(math.max(x, y))})');
  }
  if (chan != null) led(chan.$1, 'used less of the channel ($chanText)');

  final strengths = <String>[];
  if (bothPinged) {
    if (ledA.isEmpty && ledB.isEmpty) {
      strengths.add('Neither side led on any measure here. On this route they '
          'are equivalent, so choose on price, weight or battery.');
    } else {
      for (final (s, l) in [(a, ledA), (b, ledB)]) {
        strengths.add(l.isEmpty
            ? '${s.name}: no measure where it led.'
            : '${s.name}: ${l.take(2).join('; ')}.');
      }
    }
  }

  // Data-quality notes.
  final notes = <String>[];
  for (final s in [a, b]) {
    if (s.acksFromOtherNodes.isNotEmpty) {
      final n = s.acksFromOtherNodes.values.reduce((x, y) => x + y);
      notes.add('${s.name}: $n ${n == 1 ? 'answer' : 'answers'} came from '
          "${_names(s.acksFromOtherNodes.keys, nodeNames)}, not the map's "
          'base node. Check which node the pings were aimed at.');
    }
    // A radio that answered the pings is the target, not a stray.
    final strays = {
      for (final e in s.otherNodesHeard.entries)
        if (!s.acksFromOtherNodes.containsKey(e.key)) e.key: e.value,
    };
    if (strays.isNotEmpty) {
      final n = strays.values.reduce((x, y) => x + y);
      notes.add('${s.name}: ${_names(strays.keys, nodeNames)} '
          'was heard $n ${n == 1 ? 'time' : 'times'} on the test channel. '
          'A second base left on can answer pings through a relay and muddy '
          'the result; rerun with it off.');
    }
    if (s.pingsImplicit > 0) {
      notes.add('${s.name}: ${s.pingsImplicit} '
          '${s.pingsImplicit == 1 ? 'ping was' : 'pings were'} answered only '
          'through a relay. They are shown but not counted as reaching the '
          'base.');
    }
  }

  // Different power or frequency confounds an antenna/preset comparison.
  final radioNote = radioSettingsNote(a, b);
  if (radioNote != null) notes.add(radioNote);

  // Next step.
  String? next;
  if (bothPinged) {
    if (neitherLost) {
      next = presetNextStep(a, b) ??
          'Both held the link everywhere you went. Drive farther next time '
              'to find the edge.';
    } else if (win == null && bothLost) {
      next = _stopsRecipe(a, b);
    } else if (win != null) {
      next = 'Confirm it: rerun ${lose!.name} on the same route another day. '
          'If it loses by a similar margin the result is solid.';
    } else {
      next = 'Rerun both on the same route, back to back, with one-minute '
          'stops near the edge.';
    }
  }

  // Reading it.
  final bullets = <String>[];
  for (final s in [a, b]) {
    if (s.pingsSent > 0 && s.pingsWithin200m / s.pingsSent > flatterShare) {
      bullets.add('${s.name}: ${_pct(s.ackRate ?? 0)} overall is flattered: '
          '${s.pingsWithin200m} of ${s.pingsSent} pings were sent within '
          '${flatterRadiusM.round()} m. The distance chart is the fairer '
          'comparison.');
    }
  }
  if (sameCeiling) {
    bullets.add('Both held the link out to a similar distance '
        '(${_m(fa)} vs ${_m(fb)}). That points to terrain and antennas, '
        'not the preset.');
  }
  if (matchedCells <= smallOverlapCells) {
    bullets.add('The routes barely overlap, so the signal map cannot compare '
        'them spot by spot. To isolate the preset, rerun both on the same '
        'route, back to back.');
  }
  bullets.add('Distance is straight-line from the base; hills and buildings '
      'between you and the base count against the link.');
  bullets.add('An ACK means the base itself answered. Pings acknowledged only '
      'by a relaying node are listed separately and not counted as success.');

  return RangeNarrative(headline, sentences.join(' '), aWins, bullets,
      proved: proved, strengths: strengths, dataNotes: notes, nextStep: next);
}

/// One data note when the sides ran at different transmit power or on a
/// different frequency (schema v9 settings; sessions without them can't
/// differ). Null when they match or either side is unknown.
String? radioSettingsNote(SideRangeStats a, SideRangeStats b) {
  bool differ<T>(Set<T> x, Set<T> y) =>
      x.isNotEmpty && y.isNotEmpty && !_sameSet(x, y);
  final power = differ(a.txPowersDbm, b.txPowersDbm);
  final slot = differ(a.frequencySlots, b.frequencySlots) ||
      differ(a.frequenciesMHz, b.frequenciesMHz);
  if (!power && !slot) return null;
  final parts = <String>[
    if (power)
      'transmit power (${_vals(a.txPowersDbm)} vs '
          '${_vals(b.txPowersDbm)} dBm)',
    if (slot)
      a.frequenciesMHz.isNotEmpty && b.frequenciesMHz.isNotEmpty
          ? 'frequency (${_vals(a.frequenciesMHz, mhz: true)} vs '
              '${_vals(b.frequenciesMHz, mhz: true)} MHz)'
          : 'frequency slot (${_vals(a.frequencySlots)} vs '
              '${_vals(b.frequencySlots)})',
  ];
  return 'Sides ran at different ${parts.join(' and ')}: antenna '
      'differences are confounded. The comparison still stands as '
      'measured; for a clean one, rerun with both on the same '
      '${power && slot ? 'power and slot' : power ? 'power' : 'slot'}.';
}

bool _sameSet<T>(Set<T> x, Set<T> y) =>
    x.length == y.length && x.containsAll(y);

String _vals(Set<num> v, {bool mhz = false}) {
  final l = v.toList()..sort();
  return l.map((e) => mhz ? e.toStringAsFixed(3) : '$e').join('/');
}

/// "last answer at 640 m", or "never got an answer".
String _lastAnswer(SideRangeStats s) => s.farthestAckM == null
    ? 'never got an answer'
    : 'stopped getting answers at ${_m(s.farthestAckM!)}';

/// Median RSSI of both sides' edge ACKs together, null when too few.
double? _edgeRssi(SideRangeStats a, SideRangeStats b) {
  final v = [
    for (final s in [a, b])
      for (final p in s.pings)
        if (p.acked && p.rssi != null && p.distanceM >= headlineBandFromM)
          p.rssi!.toDouble(),
  ];
  return v.length < 3 ? null : median(v);
}

/// Three one-minute stops spanning the edge both sides found.
String _stopsRecipe(SideRangeStats a, SideRangeStats b) {
  final acks = [a.farthestAckM, b.farthestAckM].whereType<double>().toList();
  final misses = [a.firstMissM, b.firstMissM].whereType<double>().toList();
  if (acks.isEmpty || misses.isEmpty) {
    return 'Rerun both on the same route, back to back, with one-minute '
        'stops near the edge.';
  }
  var lo = misses.reduce(math.min), hi = acks.reduce(math.max);
  if (lo > hi) (lo, hi) = (hi, lo);
  if (hi - lo < 200) {
    final c = (lo + hi) / 2;
    lo = c - 100;
    hi = c + 100;
  }
  lo = math.max(lo, 50);
  final mid = (lo + hi) / 2;
  return 'To split them: stop for a minute at about ${_r50(lo)}, ${_r50(mid)} '
      'and ${_r50(hi)} m from the base, ten pings at each, the same spots for '
      'both, with every other node off.';
}

/// A faster preset to try when both sides held the link everywhere, or
/// null when the sides ran different (or unknown) presets, or nothing
/// faster exists.
String? presetNextStep(SideRangeStats a, SideRangeStats b) {
  if (a.presetId.isEmpty || a.presetId != b.presetId) return null;
  final cur = MeshtasticPresets.fromId(a.presetId);
  if (cur == null) return null;
  final edge = [a.edgeAckSnr, b.edgeAckSnr].whereType<double>().toList();
  final overall =
      [a.medianAckSnr(), b.medianAckSnr()].whereType<double>().toList();
  final snr = edge.isNotEmpty
      ? edge.reduce(math.min)
      : overall.isNotEmpty
          ? overall.reduce(math.min)
          : null;
  final s = fasterPresetFor(cur, edgeSnrDb: snr);
  if (s == null) return null;
  final ratio = s.fromAirtimeMs / s.toAirtimeMs;
  final text = 'Both held the link everywhere on ${cur.displayName}, so you '
      'have airtime to spare. Try ${s.to.displayName} next: a ping takes '
      '${_sec(s.toAirtimeMs)} on air instead of ${_sec(s.fromAirtimeMs)}, '
      'about ${ratio >= 3 ? ratio.round() : ratio.toStringAsFixed(1)}x less '
      'channel time.';
  if (snr == null) {
    return '$text It decodes less deep than ${cur.displayName}, so watch the '
        'far end.';
  }
  final where = edge.isNotEmpty ? 'at the edge' : 'over the route';
  return s.withinMargin
      ? '$text Your ACK SNR $where (${_db(snr)}) leaves room for it.'
      : '$text Your ACK SNR $where (${_db(snr)}) is close to its floor, so '
          'expect to lose some range at the far end.';
}

/// A faster preset than [current] and what it costs in decode depth.
class PresetSuggestion {
  final RadioPreset from, to;
  final double fromAirtimeMs, toAirtimeMs;

  /// [to] still decodes with [presetSuggestMarginDb] to spare at the SNR
  /// that was measured (false when no SNR was given or none qualified).
  final bool withinMargin;

  const PresetSuggestion(this.from, this.to, this.fromAirtimeMs,
      this.toAirtimeMs, this.withinMargin);
}

/// The fastest standard preset whose decode floor, corrected for its
/// bandwidth, still sits [presetSuggestMarginDb] under [edgeSnrDb] (as
/// measured on [current]); else the next faster preset by airtime. Null
/// when nothing is at least 10% faster.
PresetSuggestion? fasterPresetFor(RadioPreset current, {double? edgeSnrDb}) {
  final cur = AirtimeModel.pingAirtimeMs(current);
  final faster = [
    for (final p in standardPresets)
      if (!p.deprecated && AirtimeModel.pingAirtimeMs(p) < cur * 0.9) p,
  ]..sort((x, y) =>
      AirtimeModel.pingAirtimeMs(x).compareTo(AirtimeModel.pingAirtimeMs(y)));
  if (faster.isEmpty) return null;
  RadioPreset? pick;
  if (edgeSnrDb != null) {
    for (final p in faster) {
      // Wider bandwidth lets in more noise: the same signal reads lower.
      final snrOnP = edgeSnrDb - 10 * _log10(p.bwKHz / current.bwKHz);
      if (snrOnP >= p.snrFloorDb + presetSuggestMarginDb) {
        pick = p;
        break;
      }
    }
  }
  final within = pick != null;
  pick ??= faster.last;
  return PresetSuggestion(
      current, pick, cur, AirtimeModel.pingAirtimeMs(pick), within);
}

double _log10(double x) => math.log(x) / math.ln10;
String _db(double v) => '${v.toStringAsFixed(1)} dB';
String _sec(double ms) => '${(ms / 1000).toStringAsFixed(1)} s';
String _r50(double v) => '${(v / 50).round() * 50}';
String _near50(double v) => '${_r50(v)} m';

/// "MeshTest Base", "MeshTest Base and Solar", or "another radio".
String _names(Iterable<int> ids, Map<int, String> names) {
  final n = [
    for (final id in ids)
      if ((names[id] ?? '').isNotEmpty) names[id]!,
  ];
  if (n.isEmpty) return ids.length > 1 ? 'other nodes' : 'another node';
  if (n.length == 1) return n.first;
  return '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';
}

bool _similar(double x, double y) {
  final hi = math.max(x, y);
  return hi > 0 && (x - y).abs() / hi <= similarCeilingFraction;
}

/// Pings went unanswered beyond the farthest ACK (or at all).
bool _lostBase(SideRangeStats s) =>
    s.firstMissM != null && s.pingsSent > s.pingsAcked + s.pingsImplicit;

/// The side with the clearly lower median round trip (10 %+), or null.
SideRangeStats? _answeredFaster(SideRangeStats a, SideRangeStats b) {
  final x = a.medianRoundTripMs, y = b.medianRoundTripMs;
  if (x == null || y == null || x <= 0 || y <= 0) return null;
  if ((x - y).abs() / math.max(x, y) < 0.1) return null;
  return x < y ? a : b;
}

/// (side using less, its share of the other's use) when the difference is
/// at least 1.5x, comparing channel utilisation, else own air utilisation.
(SideRangeStats, double)? _channelRatio(SideRangeStats a, SideRangeStats b) {
  double? x = a.channelUtilPct, y = b.channelUtilPct;
  if (x == null || y == null || x <= 0 || y <= 0) {
    x = a.airUtilTxPct;
    y = b.airUtilTxPct;
  }
  if (x == null || y == null || x <= 0 || y <= 0) return null;
  final lo = math.min(x, y), hi = math.max(x, y);
  if (hi / lo < 1.5) return null;
  return (x < y ? a : b, lo / hi);
}

/// "about a fifth", "about half", "about 35%" for a 0..1 share.
String _fraction(double share) {
  const words = {
    2: 'half',
    3: 'a third',
    4: 'a quarter',
    5: 'a fifth',
    6: 'a sixth',
    8: 'an eighth',
    10: 'a tenth',
  };
  final n = (1 / share).round();
  final w = words[n];
  if (w != null && (1 / share - n).abs() < 0.3) return 'about $w';
  return 'about ${(share * 100).round()}% as much';
}
