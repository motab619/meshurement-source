// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../data/database/app_database.dart';
import '../../data/radio/meshcore/meshcore_presets.dart';
import '../../data/radio/meshtastic/meshtastic_presets.dart';
import '../../data/radio/radio_preset.dart';
import '../../data/radio/radio_types.dart' show RadioProtocol;
import '../ai_analysis.dart' show SideStats, assertNoLocationData;
import '../../utils/link_margin.dart';
import '../airtime_model.dart';
import '../range_stats.dart';
import '../rig_comparison.dart';
import 'plan_builder.dart';
import 'plan_models.dart';

/// Guided test: the result (design §7), written to the never-null rule:
/// what the test proved, one number with its margin per variant, one next
/// step; data problems as rescues. Built on `range_stats.dart`
/// (farthest ping, first miss, bands, `rangeNarrative`) and
/// `rig_comparison.dart` (50 m cells, median delta, % cells better).
///
/// [analyzePlanData] is pure (tested with synthetic sessions);
/// [analyzePlan] reads a plan's sessions from the database.

/// What one variant recorded.
class VariantData {
  final int variant;
  final String name;
  final List<Session> sessions;
  final List<PacketEvent> events;
  final List<PingCorrelation> correlations;

  /// Route match of its walks against the ghost route (null on the first
  /// walk, which set the route).
  final List<double> routeMatches;

  /// Rescue notes the runner attached ("walked again: first try was 90 s").
  final List<String> notes;

  const VariantData({
    required this.variant,
    required this.name,
    required this.sessions,
    required this.events,
    required this.correlations,
    this.routeMatches = const [],
    this.notes = const [],
  });
}

/// The preset id a variant ran: its sessions' (when they agree), else the
/// intent's.
String _presetIdOf(PlanIntent intent, VariantData v) {
  final ids = {
    for (final s in v.sessions)
      if (s.loraPreset.isNotEmpty) s.loraPreset,
  };
  if (ids.length == 1) return ids.first;
  return intent.template == PlanTemplate.rangeSettings
      ? intent.variants[v.variant]
      : '';
}

/// A [RadioPreset] for a stored id, either protocol.
RadioPreset? presetFromId(String id) {
  if (id.isEmpty) return null;
  return MeshtasticPresets.fromId(id) ??
      MeshCoreModulations.byId(MeshCoreModulations.ladderId(id))?.radioPreset;
}

/// Reads the plan's walks from [db] and analyses them. Sessions come from
/// the walk steps' `sessionId`; the base is the map's location, else the
/// one `resolveBase` finds in the walks.
Future<PlanAnalysisResult> analyzePlan(
  AppDatabase db, {
  required PlanRecord plan,
  required List<StepRecord> steps,
}) async {
  final intent = plan.intent;
  final byVariant = <int, List<StepRecord>>{};
  final skipped = <String>[];
  for (final s in steps) {
    if (s.step.kind != StepKind.walk) {
      if (s.status == StepStatus.skipped) skipped.add(s.step.title);
      continue;
    }
    if (s.status == StepStatus.skipped) {
      skipped.add(s.step.title);
      continue;
    }
    byVariant.putIfAbsent(s.step.variant ?? 0, () => []).add(s);
  }
  final variants = <VariantData>[];
  for (var i = 0; i < intent.variants.length; i++) {
    final walks = byVariant[i] ?? const [];
    final ids = [for (final w in walks) w.sessionId].nonNulls.toList();
    final sessions = ids.isEmpty ? <Session>[] : await db.getSessionsByIds(ids);
    sessions.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final events = <PacketEvent>[];
    final corrs = <PingCorrelation>[];
    for (final id in ids) {
      events.addAll(await db.getEventsForSession(id));
      corrs.addAll((await db.getPingsForSession(id)).values);
    }
    variants.add(VariantData(
      variant: i,
      name: variantName(intent, i),
      sessions: sessions,
      events: events,
      correlations: corrs,
      routeMatches: [
        for (final w in walks)
          if (w.step.params['match'] is num)
            (w.step.params['match'] as num).toDouble(),
      ],
      notes: [
        for (final w in walks)
          if (w.note.isNotEmpty && w.note != 'thin walk') w.note,
      ],
    ));
  }
  final map = await db.getCoverageMap(plan.coverageMapId);
  LatLng? base;
  if (map?.baseLat != null && map?.baseLon != null) {
    base = LatLng(map!.baseLat!, map.baseLon!);
  }
  final allEvents = [for (final v in variants) ...v.events];
  base ??= resolveBase(userBase: null, events: allEvents)?.point;
  final protocol = variants
          .expand((v) => v.sessions)
          .any((s) => s.protocol == RadioProtocol.meshcore.name)
      ? RadioProtocol.meshcore
      : RadioProtocol.meshtastic;
  return analyzePlanData(
    intent: intent,
    variants: variants,
    base: base,
    baseNodeDbId: map?.baseNodeId,
    protocol: protocol,
    extraNotes: [
      for (final t in skipped) 'Skipped: $t.',
    ],
  );
}

/// The whole result from the variants' recorded material. [base] null (no
/// map location, no stationary start) is a rescue, not a failure: reach is
/// then unknown and the walks are still compared cell by cell.
PlanAnalysisResult analyzePlanData({
  required PlanIntent intent,
  required List<VariantData> variants,
  required LatLng? base,
  int? baseNodeDbId,
  RadioProtocol protocol = RadioProtocol.meshtastic,
  List<String> extraNotes = const [],
}) {
  final n = variants.length;
  final rangeSettings = intent.template == PlanTemplate.rangeSettings;
  final notes = <String>[...extraNotes];

  // Where the base stands: the map's, else estimated from the walks.
  LatLng? origin = base;
  var baseEstimated = false;
  if (origin == null) {
    origin = estimateBase([for (final v in variants) ...v.events]);
    baseEstimated = origin != null;
  }
  final anchor = origin ?? _firstFix(variants) ?? const LatLng(0, 0);
  final noBase = origin == null;
  if (baseEstimated) {
    notes.add('The map has no base location; distances are from where the '
        'walks started and ended. Set the base location on the map for '
        'exact reach figures.');
  } else if (noBase) {
    notes.add('No base location and no stationary start, so reach could not '
        'be measured. Set the base location on the map and the result '
        'will show distances.');
  }

  final stats = <SideRangeStats>[
    for (final v in variants)
      computeSideStats(
        name: v.name,
        sessions: v.sessions,
        events: v.events,
        correlations: v.correlations,
        base: anchor,
        baseNodeDbId: baseNodeDbId,
      ),
  ];
  final presets = <RadioPreset?>[
    for (final v in variants) presetFromId(_presetIdOf(intent, v)),
  ];
  final airtimes = <double?>[
    for (var i = 0; i < n; i++)
      presets[i] == null
          ? null
          : AirtimeModel.probeAirtimeMsFor(presets[i], protocol: protocol),
  ];

  // Everything against the first variant ("your current setup").
  final comparisons = <int, RouteComparison?>{};
  final narratives = <int, RangeNarrative>{};
  for (var i = 1; i < n; i++) {
    final cmp = compareRoutes(_points(variants[0]), _points(variants[i]));
    comparisons[i] = cmp;
    narratives[i] =
        rangeNarrative(stats[0], stats[i], matchedCells: cmp?.snr.cells ?? 0);
  }

  // Thin or missing material is said, not hidden.
  for (var i = 0; i < n; i++) {
    final v = variants[i];
    if (v.sessions.isEmpty) {
      notes.add('${v.name}: no walk was recorded, so it has no result.');
      continue;
    }
    if (stats[i].pingsSent == 0) {
      notes.add('${v.name}: no pings were sent; only what the base '
          'broadcast was measured.');
    } else if (stats[i].pingsSent < 10) {
      notes.add('${v.name}: only ${stats[i].pingsSent} pings, so its '
          'numbers are rough. Walk it again for a firmer result.');
    }
    notes.addAll(v.notes);
  }

  // Rescues from the range narrative (other radios, relay-only answers,
  // different power or frequency), once each.
  for (final nar in narratives.values) {
    for (final note in nar.dataNotes) {
      if (!notes.contains(note)) notes.add(note);
    }
  }

  // Walks at different times: a data note, not a verdict.
  final starts = <(String, DateTime)>[
    for (final v in variants)
      for (final s in v.sessions) (v.name, s.startedAt),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  if (starts.length >= 2) {
    final gap = starts.last.$2.difference(starts.first.$2).inMinutes;
    if (gap >= 60) {
      notes.add('${starts.last.$1} was walked $gap min after '
          '${starts.first.$1}; conditions may have changed in between.');
    }
  }

  // Route match: the fairness line.
  final matches = [for (final v in variants) ...v.routeMatches];
  final matchPct =
      matches.isEmpty ? null : matches.reduce((a, b) => a + b) / matches.length;
  if (matchPct != null && matchPct < 60) {
    notes.add('Route match was only ${matchPct.round()} %: the walks took '
        'different paths, so the cell-by-cell comparison covers less '
        'ground.');
  }
  final walks = variants.fold<int>(0, (a, v) => a + v.sessions.length);
  final String fairness;
  final sameRoute = matchPct == null
      ? (walks <= 1 ? 'One walk' : 'Same route')
      : 'Same route ${walks == 2 ? 'both times' : 'every time'} '
          '(match ${matchPct.round()} %)';
  if (intent.template == PlanTemplate.reach) {
    fairness = 'One walk, base untouched.';
  } else if (intent.template.changesRadios) {
    fairness =
        '$sameRoute; only the ${intent.template == PlanTemplate.txPower ? 'TX power' : 'range setting'} '
        'changed between walks${intent.repeat ? ', two passes in opposite order' : ''}.';
  } else {
    fairness =
        '$sameRoute, base untouched${intent.repeat ? ', two passes in opposite order' : ''}.';
  }

  // The winner, by the measure the person asked about.
  final wantsMargin = _asksForMargin(intent.question);
  int? winner = _pickWinner(stats, narratives, comparisons,
      wantsMargin: wantsMargin, noBase: noBase);
  if (rangeSettings && stats.every((s) => s.pingsSent > 0 && !_lost(s))) {
    // All held the route: the cheapest setting wins.
    winner = _fastest(airtimes);
  }
  if (n == 1) winner = null;

  final rows = <VariantResult>[
    for (var i = 0; i < n; i++)
      VariantResult(
        variant: i,
        name: variants[i].name,
        sessionIds: [for (final s in variants[i].sessions) s.id],
        reach: _reachMeasure(stats[i], noBase: noBase),
        margin: rangeSettings
            ? _floorMargin(stats[i], presets[i])
            : _deltaMargin(i, comparisons, winner: winner, stats: stats),
        third: rangeSettings
            ? _airtimeMeasure(airtimes[i])
            : _pingsMeasure(stats[i]),
        leadPct: _leadPct(i, comparisons, winner: winner, stats: stats),
      ),
  ];

  final headline = _headline(intent, stats, airtimes, winner,
      narratives: narratives, noBase: noBase);
  final nextStep = _nextStep(intent, stats, presets, airtimes, winner,
      narratives: narratives, noBase: noBase, protocol: protocol);

  final digest = _digest(
    intent: intent,
    variants: variants,
    stats: stats,
    airtimes: airtimes,
    comparisons: comparisons,
    headline: headline,
    fairness: fairness,
    nextStep: nextStep,
    notes: notes,
    winner: winner,
    protocol: protocol,
  );
  assertNoLocationData(digest);

  return PlanAnalysisResult(
    headline: headline,
    fairness: fairness,
    variants: rows,
    winner: winner,
    nextStep: nextStep,
    dataNotes: notes,
    thirdLabel: rangeSettings
        ? 'AIRTIME'
        : (protocol == RadioProtocol.meshcore ? 'LINK CHECKS' : 'PINGS'),
    digest: digest,
  );
}

// ─── Winner ─────────────────────────────────────────────────────────────

bool _asksForMargin(String? q) {
  if (q == null) return false;
  final t = q.toLowerCase();
  return t.contains('reliab') ||
      t.contains('margin') ||
      t.contains('drop') ||
      t.contains('solid') ||
      t.contains('stable');
}

bool _lost(SideRangeStats s) =>
    s.firstMissM != null && s.pingsSent > s.pingsAcked + s.pingsImplicit;

double? _reachOf(SideRangeStats s) => s.farthestAckM ?? s.heardBaseOutToM;

/// Index of the variant that led, or null for a tie. Two variants: the
/// range narrative's call (ACK rate in the 300–1000 m band, then farthest
/// ACK, then overall ACK rate); when it has none and the person asked about
/// reliability, a 3 dB median SNR edge decides. Three or four: every
/// variant that beats the first; the farthest-reaching of those wins;
/// the first wins only when it beats them all.
int? _pickWinner(
  List<SideRangeStats> stats,
  Map<int, RangeNarrative> narratives,
  Map<int, RouteComparison?> comparisons, {
  required bool wantsMargin,
  required bool noBase,
}) {
  final n = stats.length;
  if (n < 2) return null;
  bool? snrEdge(int i) {
    final m = comparisons[i]?.snr;
    if (m == null ||
        m.cells == 0 ||
        m.medianDelta.abs() < comparisonClearDeltaDb) {
      return null;
    }
    return m.medianDelta > 0; // B (i) stronger
  }

  if (n == 2) {
    final aWins = noBase ? null : narratives[1]!.aWins;
    if (aWins != null && !(wantsMargin && snrEdge(1) != null)) {
      return aWins ? 0 : 1;
    }
    final edge = snrEdge(1);
    if (edge != null) return edge ? 1 : 0;
    return aWins == null ? null : (aWins ? 0 : 1);
  }
  final beatsFirst = <int>[];
  var firstBeatsAll = true;
  for (var i = 1; i < n; i++) {
    final aWins = noBase ? null : narratives[i]!.aWins;
    final edge = snrEdge(i);
    final iWins = aWins == false || (aWins == null && edge == true);
    final firstWins = aWins == true || (aWins == null && edge == false);
    if (iWins) beatsFirst.add(i);
    if (!firstWins) firstBeatsAll = false;
  }
  if (beatsFirst.isEmpty) return firstBeatsAll ? 0 : null;
  beatsFirst.sort((x, y) {
    final r = (_reachOf(stats[y]) ?? 0).compareTo(_reachOf(stats[x]) ?? 0);
    if (r != 0) return r;
    return (stats[y].headlineBandRate ?? 0)
        .compareTo(stats[x].headlineBandRate ?? 0);
  });
  return beatsFirst.first;
}

int? _fastest(List<double?> airtimes) {
  int? best;
  for (var i = 0; i < airtimes.length; i++) {
    final a = airtimes[i];
    if (a == null) continue;
    if (best == null || a < airtimes[best]!) best = i;
  }
  if (best == null) return null;
  // Equal airtime is a tie.
  for (var i = 0; i < airtimes.length; i++) {
    if (i != best &&
        airtimes[i] != null &&
        (airtimes[i]! - airtimes[best]!).abs() < 1) {
      return null;
    }
  }
  return best;
}

// ─── Measures ───────────────────────────────────────────────────────────

String _m(double v) => '${v.round()} m';
String _db(double v) => '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1)} dB';
String _sec(double ms) => '${(ms / 1000).toStringAsFixed(2)} s';
String _pct(double rate) => '${(rate * 100).round()} %';

Measure _reachMeasure(SideRangeStats s, {required bool noBase}) {
  if (noBase) return const Measure('—', 'no base location');
  final ack = s.farthestAckM;
  if (ack != null) {
    return Measure(_m(ack), _lost(s) ? 'farthest ping' : 'end of route');
  }
  final heard = s.heardBaseOutToM;
  if (heard != null) return Measure(_m(heard), 'heard out to');
  if (s.pingsSent > 0) return const Measure('0 m', 'no answers');
  return const Measure('—', 'nothing heard');
}

Measure _pingsMeasure(SideRangeStats s) {
  if (s.pingsSent == 0) return const Measure('0', 'no pings sent');
  return Measure(
      '${s.pingsAcked} / ${s.pingsSent}', '${_pct(s.ackRate!)} answered');
}

Measure _airtimeMeasure(double? ms) => ms == null
    ? const Measure('—', 'preset unknown')
    : Measure(_sec(ms), 'airtime per ping');

Measure _floorMargin(SideRangeStats s, RadioPreset? preset) {
  final snr = s.medianAckSnr() ?? s.medianSnr;
  if (snr == null) return const Measure('—', 'no signal readings');
  if (preset == null) return Measure(_db(snr), 'median SNR');
  // Hybrid SNR/RSSI margin per ACK (linkMarginDb), like the maps; with
  // fewer than three ACKs, the margin of the side's median SNR and RSSI.
  final scale = MarginScale.of(preset);
  final perAck = [
    for (final p in s.pings)
      if (p.acked && p.snr != null) scale.marginDb(snr: p.snr, rssi: p.rssi)!,
  ];
  final margin = perAck.length >= 3
      ? median(perAck)
      : scale.marginDb(snr: snr, rssi: s.medianRssi)!;
  return Measure(_db(margin), 'margin above floor');
}

/// The comparison the first variant's row speaks against: the winner's
/// when another variant won, else the farthest-reaching other.
int _referenceOf(Map<int, RouteComparison?> comparisons,
    {required int? winner, required List<SideRangeStats> stats}) {
  if (comparisons.isEmpty) return -1;
  if (winner != null && winner != 0 && comparisons.containsKey(winner)) {
    return winner;
  }
  var best = comparisons.keys.first;
  for (final i in comparisons.keys) {
    if ((_reachOf(stats[i]) ?? 0) > (_reachOf(stats[best]) ?? 0)) best = i;
  }
  return best;
}

Measure _deltaMargin(int i, Map<int, RouteComparison?> comparisons,
    {required int? winner, required List<SideRangeStats> stats}) {
  if (comparisons.isEmpty) {
    // One variant: its own margin over the median.
    final s = stats[i];
    final snr = s.medianAckSnr() ?? s.medianSnr;
    return snr == null
        ? const Measure('—', 'no signal readings')
        : Measure(_db(snr), 'median SNR');
  }
  if (i == 0) {
    final ref = _referenceOf(comparisons, winner: winner, stats: stats);
    final m = comparisons[ref]?.snr;
    if (m == null || m.cells == 0) {
      return const Measure('—', 'routes don\'t overlap');
    }
    return Measure(_db(-m.medianDelta), '${m.cells} shared cells');
  }
  final m = comparisons[i]?.snr;
  if (m == null || m.cells == 0) {
    return const Measure('—', 'routes don\'t overlap');
  }
  final better = m.pctBBetter >= m.pctABetter;
  return Measure(_db(m.medianDelta),
      '${(better ? m.pctBBetter : m.pctABetter).round()} % of cells ${better ? 'better' : 'worse'}');
}

double _leadPct(int i, Map<int, RouteComparison?> comparisons,
    {required int? winner, required List<SideRangeStats> stats}) {
  if (comparisons.isEmpty) return 0;
  if (i == 0) {
    final ref = _referenceOf(comparisons, winner: winner, stats: stats);
    return comparisons[ref]?.snr.pctABetter ?? 0;
  }
  return comparisons[i]?.snr.pctBBetter ?? 0;
}

// ─── Words ──────────────────────────────────────────────────────────────

String _headline(
  PlanIntent intent,
  List<SideRangeStats> stats,
  List<double?> airtimes,
  int? winner, {
  required Map<int, RangeNarrative> narratives,
  required bool noBase,
}) {
  final n = stats.length;
  if (stats.every((s) => s.sessionCount == 0)) {
    return 'No walk was recorded, so there is nothing to compare yet.';
  }
  if (intent.template == PlanTemplate.reach) {
    final s = stats[0];
    final ack = s.farthestAckM;
    if (noBase) {
      return 'The base answered ${s.pingsAcked} of ${s.pingsSent} pings; '
          'without a base location the distance is unknown.';
    }
    if (ack == null) {
      return s.pingsSent == 0
          ? 'No pings were sent, so reach was not measured on this walk.'
          : 'No ping was answered: the base was never heard on this walk.';
    }
    if (_lost(s)) {
      return 'Your setup reached ${_m(ack)}; the base was lost at '
          '${_m(s.firstMissM!)}.';
    }
    return 'Your setup held the link the whole way, out to ${_m(ack)}.';
  }

  final rangeSettings = intent.template == PlanTemplate.rangeSettings;
  final allHeld = stats.every((s) => s.pingsSent > 0 && !_lost(s));
  final far = stats.map(_reachOf).nonNulls.fold<double>(0, math.max);
  final all = n == 2 ? 'Both' : 'All $n';

  if (rangeSettings && allHeld) {
    if (winner == null) {
      return '$all settings held the whole route (out to ${_m(far)}) and '
          'cost the same airtime: nothing separates them here.';
    }
    final others = [
      for (var i = 0; i < n; i++)
        if (i != winner && airtimes[i] != null) airtimes[i]!,
    ];
    final saving = others.isEmpty
        ? null
        : (others.reduce(math.min) - airtimes[winner]!) / 1000;
    return '$all settings held the whole route. ${stats[winner].name} did '
        'it with ${saving == null ? 'less' : '${saving.toStringAsFixed(1)} s less'} '
        'airtime per ping.';
  }

  if (winner == null) {
    if (noBase) {
      return 'Too close to call on the shared cells; without a base '
          'location reach could not be compared.';
    }
    if (allHeld) {
      return '$all held the whole route out to ${_m(far)}: on this route '
          'they are equivalent.';
    }
    final lostAll = stats.every(_lost);
    final acks = stats.map((s) => s.farthestAckM).nonNulls.toList();
    if (lostAll && acks.length == n) {
      final lo = acks.reduce(math.min), hi = acks.reduce(math.max);
      if (hi > 0 && (hi - lo) / hi <= similarCeilingFraction) {
        return 'Too close to call: ${all.toLowerCase()} lost the base near '
            '${_m((hi / 50).round() * 50)}.';
      }
    }
    return 'Too close to call: ${[
      for (final s in stats)
        '${s.name} ${_reachOf(s) == null ? 'had no answers' : _m(_reachOf(s)!)}'
    ].join(', ')}.';
  }

  final w = stats[winner];
  final loserIdx =
      winner == 0 ? _runnerUp(stats, exclude: 0) : (n == 2 ? 1 - winner : 0);
  final l = stats[loserIdx];
  final rw = _reachOf(w), rl = _reachOf(l);
  final gap = rw != null && rl != null ? rw - rl : null;
  String cost = '';
  if (rangeSettings && airtimes[winner] != null && airtimes[loserIdx] != null) {
    final d = (airtimes[winner]! - airtimes[loserIdx]!) / 1000;
    cost = d > 0
        ? ' It costs ${d.toStringAsFixed(1)} s more airtime per ping.'
        : ' It also uses ${(-d).toStringAsFixed(1)} s less airtime per ping.';
  }
  if (gap != null && gap >= strengthDistanceGapM) {
    // The loser dropped pings inside the winner's reach.
    final held = _lost(l) && rw != null && l.firstMissM! < rw
        ? ' and held the link where ${l.name} lost it'
        : '';
    return '${w.name} reached ${_m((gap / 10).round() * 10)} further'
        '$held.$cost';
  }
  final rw2 = w.headlineBandRate, rl2 = l.headlineBandRate;
  if (rw2 != null && rl2 != null) {
    return '${w.name} held the link better than ${l.name}: ${_pct(rw2)} vs '
        '${_pct(rl2)} of pings answered past ${headlineBandFromM.round()} m.'
        '$cost';
  }
  if (w.ackRate != null && l.ackRate != null) {
    return '${w.name} held the link better than ${l.name}: '
        '${_pct(w.ackRate!)} vs ${_pct(l.ackRate!)} of pings answered.$cost';
  }
  return '${w.name} came out ahead of ${l.name} on the shared cells.$cost';
}

int _runnerUp(List<SideRangeStats> stats, {required int exclude}) {
  var best = -1;
  for (var i = 0; i < stats.length; i++) {
    if (i == exclude) continue;
    if (best < 0 || (_reachOf(stats[i]) ?? 0) > (_reachOf(stats[best]) ?? 0)) {
      best = i;
    }
  }
  return best < 0 ? exclude : best;
}

String _nextStep(
  PlanIntent intent,
  List<SideRangeStats> stats,
  List<RadioPreset?> presets,
  List<double?> airtimes,
  int? winner, {
  required Map<int, RangeNarrative> narratives,
  required bool noBase,
  RadioProtocol protocol = RadioProtocol.meshtastic,
}) {
  final n = stats.length;
  final probes = protocol == RadioProtocol.meshcore ? 'link checks' : 'pings';
  if (stats.every((s) => s.sessionCount == 0)) {
    return 'Run the test again and record every walk.';
  }
  if (noBase) {
    return 'Set the base location on the map (map detail → base), then open '
        'this result again: the reach figures fill in from the walks you '
        'already made.';
  }
  final rangeSettings = intent.template == PlanTemplate.rangeSettings;
  final allHeld = stats.every((s) => s.pingsSent > 0 && !_lost(s));
  final far = stats.map(_reachOf).nonNulls.fold<double>(0, math.max);

  if (intent.template == PlanTemplate.reach) {
    final s = stats[0];
    if (s.farthestAckM == null) {
      return s.pingsSent == 0
          ? 'Turn $probes on (Settings → Active Probing) and walk again: '
              '$probes are what measure reach.'
          : 'Check both nodes are on MeshTest and the same setting, then '
              'walk the first 100 m again slowly.';
    }
    if (_lost(s)) {
      final lo = math.min(s.farthestAckM!, s.firstMissM!);
      final hi = math.max(s.farthestAckM!, s.firstMissM!);
      return 'The edge is between ${_m(lo)} and ${_m(hi)}. Walk that '
          'stretch again with one-minute stops to pin it down.';
    }
    return 'Go further next time: the base answered all the way to '
        '${_m(far)}.';
  }

  if (rangeSettings && allHeld) {
    final idx = winner ?? _fastest(airtimes) ?? 0;
    final fast = presets[idx];
    final slower = [
      for (var i = 0; i < n; i++)
        if (i != idx) stats[i].name,
    ];
    if (fast == null) {
      return 'Nothing on this route needs the slower setting. Extend the '
          'route past ${_m(far)} next time to find the edge.';
    }
    final edge = stats[idx].edgeAckSnr ?? stats[idx].medianAckSnr();
    final s = fasterPresetFor(fast, edgeSnrDb: edge);
    final keep = 'Nothing on this route needs ${slower.join(' or ')}. Keep '
        '${fast.displayName}';
    if (s == null) {
      return '$keep: nothing faster is available. Extend the route past '
          '${_m(far)} next time to find its edge.';
    }
    final room = edge == null
        ? ''
        : s.withinMargin
            ? ' Your ${edge.toStringAsFixed(1)} dB at the edge leaves room for it.'
            : ' Your ${edge.toStringAsFixed(1)} dB at the edge is close to its floor, so expect to lose some range.';
    return '$keep and try ${s.to.displayName} on a day when the route is '
        'extended past ${_m(far)}: a ping takes ${_sec(s.toAirtimeMs)} on '
        'air instead of ${_sec(s.fromAirtimeMs)}.$room';
  }

  if (winner != null) {
    final w = stats[winner];
    final others = [
      for (var i = 0; i < n; i++)
        if (i != winner) stats[i],
    ];
    final minReach = others
        .map(_reachOf)
        .nonNulls
        .fold<double?>(null, (a, b) => a == null ? b : math.min(a, b));
    final rw = _reachOf(w);
    if (rw != null && !_lost(w)) {
      return '${w.name} never lost the base here. Walk on past ${_m(rw)} '
          'next time to find where it does.';
    }
    if (rw != null && minReach != null) {
      return '${n == 2 ? 'Both' : 'All'} reached ${_m(minReach)}. To see how '
          'much further ${w.name} goes, walk on past ${_m(minReach)} next '
          'time and stop for a minute every 100 m; the base stayed quiet '
          'after ${_m(rw)}.';
    }
    return 'Confirm it: rerun ${others.first.name} on the same route '
        'another day. If it loses by a similar margin the result is solid.';
  }

  // A tie.
  if (allHeld) {
    return 'Everything you compared covers this route. Drive or walk '
        'further next time to find the edge, or pick on price, weight or '
        'battery.';
  }
  final fromNarrative = narratives.values
      .map((nar) => nar.nextStep)
      .nonNulls
      .firstWhere((_) => true, orElse: () => '');
  if (fromNarrative.isNotEmpty) return fromNarrative;
  return 'Rerun ${n == 2 ? 'both' : 'all of them'} on the same route, back '
      'to back, with one-minute stops near the edge.';
}

// ─── Digest (numbers only) ──────────────────────────────────────────────

double _r(double v) => (v * 10).round() / 10;

Map<String, dynamic> _digest({
  required PlanIntent intent,
  required List<VariantData> variants,
  required List<SideRangeStats> stats,
  required List<double?> airtimes,
  required Map<int, RouteComparison?> comparisons,
  required String headline,
  required String fairness,
  required String nextStep,
  required List<String> notes,
  required int? winner,
  required RadioProtocol protocol,
}) {
  Map<String, dynamic> side(int i) {
    final v = variants[i], s = stats[i];
    final ss = SideStats.from(v.sessions,
        events: v.events,
        pingStatuses: [for (final c in v.correlations) c.ackStatus]);
    return {
      'name': v.name,
      ...ss.toJson(),
      if (s.farthestAckM != null) 'farthestAckM': s.farthestAckM!.round(),
      if (s.firstMissM != null) 'firstMissM': s.firstMissM!.round(),
      if (s.heardBaseOutToM != null) 'heardOutToM': s.heardBaseOutToM!.round(),
      'farthestWalkedM': s.farthestWalkedM.round(),
      'pingsImplicit': s.pingsImplicit,
      if (s.headlineBandRate != null)
        'ackRate300to1000mPct': _r(100 * s.headlineBandRate!),
      'successPerBand': [
        for (final b in s.bands)
          {
            'fromM': b.fromM.round(),
            if (b.toM != null) 'toM': b.toM!.round(),
            'ok': b.acked,
            'total': b.sent,
          },
      ],
      if (airtimes[i] != null) 'airtimePerPingMs': _r(airtimes[i]!),
      if (v.routeMatches.isNotEmpty)
        'routeMatchPct':
            _r(v.routeMatches.reduce((a, b) => a + b) / v.routeMatches.length),
    };
  }

  return {
    'schema': 1,
    'kind': 'guidedTest',
    'template': intent.template.name,
    'side': intent.side.name,
    'repeat': intent.repeat,
    'routeMinutes': intent.route.minutes,
    'protocol': protocol.name,
    if (intent.question != null && intent.question!.isNotEmpty)
      'question': intent.question!.length > 300
          ? intent.question!.substring(0, 300)
          : intent.question,
    'variants': [for (var i = 0; i < variants.length; i++) side(i)],
    'comparisons': [
      for (final e in comparisons.entries)
        {
          'a': variants[0].name,
          'b': variants[e.key].name,
          'meaning': 'delta is B minus A; positive means B is stronger',
          'cellMeters': e.value?.grid.cellMeters.round() ?? 0,
          'cellsMatched': e.value?.snr.cells ?? 0,
          'snrMedianDeltaDb': _r(e.value?.snr.medianDelta ?? 0),
          'pctBBetterBy3Db': _r(e.value?.snr.pctBBetter ?? 0),
          'pctABetterBy3Db': _r(e.value?.snr.pctABetter ?? 0),
          'rssiMedianDeltaDb': _r(e.value?.rssi.medianDelta ?? 0),
        },
    ],
    'appReading': {
      'headline': headline,
      'fairness': fairness,
      'nextStep': nextStep,
      'dataNotes': notes,
      if (winner != null) 'winner': variants[winner].name,
    },
  };
}

// ─── Helpers ────────────────────────────────────────────────────────────

SidePoints _points(VariantData v) {
  final lats = <double>[], lons = <double>[];
  final rssi = <double?>[], snr = <double?>[];
  for (final e in v.events) {
    if (e.rxLat == null || e.rxLon == null) continue;
    if (e.direction == 'tx') continue;
    if (e.rxSnr == null && e.rxRssi == null) continue;
    lats.add(e.rxLat!);
    lons.add(e.rxLon!);
    rssi.add(e.rxRssi?.toDouble());
    snr.add(e.rxSnr);
  }
  return SidePoints(lats, lons, rssi, snr);
}

LatLng? _firstFix(List<VariantData> variants) {
  for (final v in variants) {
    for (final e in v.events) {
      if (e.rxLat != null && e.rxLon != null) return LatLng(e.rxLat!, e.rxLon!);
    }
  }
  return null;
}

/// The result as stored in `test_plans.result_json`.
String encodePlanResult(PlanAnalysisResult r) => jsonEncode(r.toJson());

PlanAnalysisResult? decodePlanResult(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    return PlanAnalysisResult.fromJson(
        Map<String, dynamic>.from(jsonDecode(json) as Map));
  } catch (_) {
    return null;
  }
}
