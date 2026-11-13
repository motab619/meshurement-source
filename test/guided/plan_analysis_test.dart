// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/services/ai_analysis.dart';
import 'package:mesh_analyzer/services/guided/plan_analysis.dart';
import 'package:mesh_analyzer/services/guided/plan_models.dart';
import 'package:mesh_analyzer/utils/constants.dart';

const _base = LatLng(33.68, -116.24);
final _t0 = DateTime(2026, 10, 31, 10);

const _dist = Distance();

/// [m] metres due east of the base (haversine, so distances read back
/// exactly).
LatLng east(double m) => _dist.offset(_base, m, 90);

Session session(int id,
        {String preset = 'MEDIUM_FAST', DateTime? start, int minutes = 12}) =>
    Session(
      id: id,
      coverageMapId: 1,
      name: 'test',
      startedAt: start ?? _t0,
      endedAt: (start ?? _t0).add(Duration(minutes: minutes)),
      isActive: false,
      hwAntenna: '',
      hwNodeModel: '',
      hwNotes: '',
      loraPreset: preset,
      protocol: 'meshtastic',
      pingIntervalSec: 15,
      packetAirtimeMs: 0,
      rangeTestActive: false,
      packetCount: 0,
      beaconKind: '',
      beaconIntervalSec: 0,
    );

/// A straight walk east from the base and back: the base is heard every
/// 25 m with an SNR that falls with distance; a ping every 50 m is
/// answered until [reachM] and lost after it. [snrOffset] lifts or lowers
/// every reading (a better antenna).
class Walk {
  final int sessionId;
  final events = <PacketEvent>[];
  final corrs = <PingCorrelation>[];
  int _id;
  int _sec = 0;

  Walk(this.sessionId, int idBase) : _id = idBase;

  PacketEvent _ev(String dir, double m,
      {double? snr, int? rssi, String type = 'ping', int source = 1}) {
    final p = east(m);
    final e = PacketEvent(
      id: _id++,
      sessionId: sessionId,
      timestamp: _t0.add(Duration(seconds: _sec++)),
      direction: dir,
      sourceNodeId: source,
      rxSnr: snr,
      rxRssi: rssi,
      hopCount: 0,
      rxLat: p.latitude,
      rxLon: p.longitude,
      packetType: type,
      channelIndex: 0,
      viaMqtt: false,
      sourceKind: 'passive',
    );
    events.add(e);
    return e;
  }

  void outAndBack(
      {required double toM,
      required double reachM,
      double snrOffset = 0,
      bool pings = true}) {
    void leg(double m) {
      final snr = 12 - m / 80 + snrOffset;
      _ev(PacketDirection.rx, m,
          snr: snr, rssi: (-80 - m / 10).round(), type: PacketType.telemetry);
      if (pings && m % 50 == 0) {
        final ok = m <= reachM;
        final tx = _ev(PacketDirection.tx, m, source: 2);
        int? ackId;
        if (ok) {
          ackId = _ev(PacketDirection.ack, m,
                  snr: snr, rssi: (-85 - m / 10).round(), type: PacketType.ack)
              .id;
        }
        corrs.add(PingCorrelation(
          id: _id++,
          txEventId: tx.id,
          ackEventId: ackId,
          roundTripMs: ok ? 900 : null,
          ackStatus: ok ? AckStatus.received : AckStatus.timeout,
        ));
      }
    }

    for (var m = 0.0; m <= toM; m += 25) {
      leg(m);
    }
    for (var m = toM - 25; m >= 0; m -= 25) {
      leg(m);
    }
  }
}

VariantData variant(int i, String name, Walk w, Session s,
        {List<double> match = const []}) =>
    VariantData(
      variant: i,
      name: name,
      sessions: [s],
      events: w.events,
      correlations: w.corrs,
      routeMatches: match,
    );

const antennas = PlanIntent(
    template: PlanTemplate.antennas,
    variants: ['Stock whip', '5.8 dBi fiberglass']);

void main() {
  group('antennas', () {
    late PlanAnalysisResult r;
    setUp(() {
      final a = Walk(1, 1)..outAndBack(toM: 900, reachM: 600);
      final b = Walk(2, 10000)..outAndBack(toM: 900, reachM: 800, snrOffset: 3);
      r = analyzePlanData(
        intent: antennas,
        variants: [
          variant(0, 'Stock whip', a, session(1)),
          variant(1, '5.8 dBi fiberglass', b,
              session(2, start: _t0.add(const Duration(minutes: 20))),
              match: [91]),
        ],
        base: _base,
      );
    });

    test('names the winner with reach and where the other lost the link', () {
      expect(r.winner, 1);
      expect(
          r.headline,
          '5.8 dBi fiberglass reached 200 m further and held the link where '
          'Stock whip lost it.');
      expect(r.thirdLabel, 'PINGS');
    });

    test('one number with margin per side', () {
      expect(r.variants.length, 2);
      final a = r.variants[0], b = r.variants[1];
      expect(a.reach.value, '600 m');
      expect(a.reach.caption, 'farthest ping');
      expect(b.reach.value, '800 m');
      expect(a.third.value, '26 / 37');
      expect(a.third.caption, '70 % answered');
      expect(b.third.value, '34 / 37');
      expect(b.margin.value, startsWith('+'));
      expect(b.margin.caption, endsWith('% of cells better'));
      expect(a.margin.value, startsWith('−'));
      expect(a.margin.caption, endsWith('shared cells'));
      expect(b.leadPct, greaterThan(a.leadPct));
      expect(b.sessionIds, [2]);
    });

    test('fairness and next step', () {
      expect(r.fairness, 'Same route both times (match 91 %), base untouched.');
      expect(r.nextStep, contains('Both reached 600 m'));
      expect(r.nextStep, contains('walk on past 600 m'));
      expect(r.nextStep, contains('after 800 m'));
    });

    test('digest is numbers only and survives the location scrubber', () {
      expect(() => assertNoLocationData(r.digest), returnsNormally);
      final text = jsonEncode(r.digest);
      expect(text, isNot(contains('33.68')));
      expect(text, isNot(contains('116.24')));
      final v = (r.digest['variants'] as List).cast<Map>();
      expect(v[1]['farthestAckM'], 800);
      expect(v[0]['firstMissM'], 650);
      expect(v[0]['pingsTotal'], 37);
      expect(v[1]['routeMatchPct'], 91);
      expect((r.digest['comparisons'] as List).length, 1);
      expect((r.digest['appReading'] as Map)['winner'], '5.8 dBi fiberglass');
      expect(r.digest['template'], 'antennas');
    });

    test('result round-trips through JSON', () {
      final back = PlanAnalysisResult.fromJson(
          jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
      expect(back.headline, r.headline);
      expect(back.winner, 1);
      expect(back.variants[1].reach.value, '800 m');
      expect(back.digest['template'], 'antennas');
      expect(decodePlanResult(encodePlanResult(r))?.nextStep, r.nextStep);
      expect(decodePlanResult('garbage'), isNull);
    });
  });

  group('range settings', () {
    test('both held: the faster setting wins on airtime', () {
      final a = Walk(1, 1)..outAndBack(toM: 800, reachM: 800);
      final b = Walk(2, 10000)..outAndBack(toM: 800, reachM: 800, snrOffset: 2);
      final r = analyzePlanData(
        intent: const PlanIntent(
            template: PlanTemplate.rangeSettings,
            variants: ['MEDIUM_FAST', 'LONG_FAST']),
        variants: [
          variant(0, 'Medium Fast', a, session(1, preset: 'MEDIUM_FAST')),
          variant(1, 'Long Fast', b, session(2, preset: 'LONG_FAST'),
              match: [88]),
        ],
        base: _base,
      );
      expect(r.winner, 0);
      expect(r.thirdLabel, 'AIRTIME');
      expect(r.headline, startsWith('Both settings held the whole route.'));
      expect(r.headline, contains('Medium Fast did it with'));
      expect(r.headline, contains('s less airtime per ping.'));
      expect(r.variants[0].third.caption, 'airtime per ping');
      expect(r.variants[0].third.value, endsWith(' s'));
      expect(r.variants[0].reach.caption, 'end of route');
      expect(r.variants[0].margin.caption, 'margin above floor');
      expect(r.variants[0].margin.value, startsWith('+'));
      expect(r.nextStep, contains('Nothing on this route needs Long Fast.'));
      expect(r.nextStep, contains('Keep Medium Fast'));
      expect(r.fairness, contains('only the range setting changed'));
      expect(() => assertNoLocationData(r.digest), returnsNormally);
    });

    test('one lost the base: reach decides, airtime is the cost', () {
      final a = Walk(1, 1)..outAndBack(toM: 900, reachM: 500);
      final b = Walk(2, 10000)..outAndBack(toM: 900, reachM: 850, snrOffset: 4);
      final r = analyzePlanData(
        intent: const PlanIntent(
            template: PlanTemplate.rangeSettings,
            variants: ['SHORT_FAST', 'LONG_FAST']),
        variants: [
          variant(0, 'Short Fast', a, session(1, preset: 'SHORT_FAST')),
          variant(1, 'Long Fast', b, session(2, preset: 'LONG_FAST')),
        ],
        base: _base,
      );
      expect(r.winner, 1);
      expect(r.headline, contains('Long Fast reached 350 m further'));
      expect(r.headline, contains('more airtime per ping'));
    });
  });

  group('reach', () {
    test('one setup, lost on the way out', () {
      final w = Walk(1, 1)..outAndBack(toM: 900, reachM: 600);
      final r = analyzePlanData(
        intent: const PlanIntent(
            template: PlanTemplate.reach, variants: ['My setup']),
        variants: [variant(0, 'My setup', w, session(1))],
        base: _base,
      );
      expect(r.winner, isNull);
      expect(r.headline,
          'Your setup reached 600 m; the base was lost at 650 m.');
      expect(r.nextStep, contains('between 600 m and 650 m'));
      expect(r.fairness, 'One walk, base untouched.');
      expect(r.variants.single.margin.caption, 'median SNR');
    });

    test('never lost', () {
      final w = Walk(1, 1)..outAndBack(toM: 400, reachM: 400);
      final r = analyzePlanData(
        intent: const PlanIntent(
            template: PlanTemplate.reach, variants: ['My setup']),
        variants: [variant(0, 'My setup', w, session(1))],
        base: _base,
      );
      expect(r.headline,
          'Your setup held the link the whole way, out to 400 m.');
      expect(r.nextStep, contains('Go further next time'));
    });
  });

  group('ties and rescues', () {
    test('identical walks that both held are equivalent, not nothing', () {
      final a = Walk(1, 1)..outAndBack(toM: 500, reachM: 500);
      final b = Walk(2, 10000)..outAndBack(toM: 500, reachM: 500);
      final r = analyzePlanData(
        intent: antennas,
        variants: [
          variant(0, 'Stock whip', a, session(1)),
          variant(1, '5.8 dBi fiberglass', b, session(2)),
        ],
        base: _base,
      );
      expect(r.winner, isNull);
      expect(r.headline,
          'Both held the whole route out to 500 m: on this route they are '
          'equivalent.');
      expect(r.nextStep, contains('price, weight or battery'));
    });

    test('both lost at the same wall', () {
      final a = Walk(1, 1)..outAndBack(toM: 900, reachM: 600);
      final b = Walk(2, 10000)..outAndBack(toM: 900, reachM: 600);
      final r = analyzePlanData(
        intent: antennas,
        variants: [
          variant(0, 'Stock whip', a, session(1)),
          variant(1, '5.8 dBi fiberglass', b, session(2)),
        ],
        base: _base,
      );
      expect(r.winner, isNull);
      expect(r.headline, 'Too close to call: both lost the base near 600 m.');
      expect(r.nextStep, isNotEmpty);
    });

    test('three variants: the farthest of those beating the first wins', () {
      final a = Walk(1, 1)..outAndBack(toM: 900, reachM: 500);
      final b = Walk(2, 10000)..outAndBack(toM: 900, reachM: 700, snrOffset: 2);
      final c = Walk(3, 20000)..outAndBack(toM: 900, reachM: 850, snrOffset: 4);
      final r = analyzePlanData(
        intent: antennas.copyWith(variants: ['A', 'B', 'C']),
        variants: [
          variant(0, 'A', a, session(1)),
          variant(1, 'B', b, session(2)),
          variant(2, 'C', c, session(3)),
        ],
        base: _base,
      );
      expect(r.winner, 2);
      expect(r.headline, startsWith('C reached 350 m further'));
      expect(r.variants.length, 3);
      expect((r.digest['comparisons'] as List).length, 2);
    });

    test('no base location: estimated from the walks, said as a note', () {
      final a = Walk(1, 1)..outAndBack(toM: 900, reachM: 600);
      final b = Walk(2, 10000)..outAndBack(toM: 900, reachM: 800, snrOffset: 3);
      final r = analyzePlanData(
        intent: antennas,
        variants: [
          variant(0, 'Stock whip', a, session(1)),
          variant(1, '5.8 dBi fiberglass', b, session(2)),
        ],
        base: null,
      );
      expect(r.winner, 1);
      expect(r.dataNotes.any((n) => n.contains('no base location')), isTrue);
      expect(r.variants[1].reach.value, '800 m');
    });

    test('thin variant and a long gap between walks are noted', () {
      final a = Walk(1, 1)..outAndBack(toM: 900, reachM: 600);
      final b = Walk(2, 10000)..outAndBack(toM: 100, reachM: 100, snrOffset: 3);
      final r = analyzePlanData(
        intent: antennas,
        variants: [
          variant(0, 'Stock whip', a, session(1)),
          variant(1, '5.8 dBi fiberglass', b,
              session(2, start: _t0.add(const Duration(minutes: 95)))),
        ],
        base: _base,
      );
      expect(
          r.dataNotes.any((n) => n.startsWith('5.8 dBi fiberglass: only')),
          isTrue);
      expect(r.dataNotes.any((n) => n.contains('was walked 95 min after')),
          isTrue);
    });

    test('nothing recorded is still a sentence and a next step', () {
      final r = analyzePlanData(
        intent: antennas,
        variants: const [
          VariantData(
              variant: 0,
              name: 'Stock whip',
              sessions: [],
              events: [],
              correlations: []),
          VariantData(
              variant: 1,
              name: '5.8 dBi fiberglass',
              sessions: [],
              events: [],
              correlations: []),
        ],
        base: _base,
      );
      expect(r.headline, contains('No walk was recorded'));
      expect(r.nextStep, isNotEmpty);
      expect(r.dataNotes.length, greaterThanOrEqualTo(2));
      expect(r.variants[0].reach.value, '—');
    });
  });

  test('digest shape follows SessionDigest sides', () {
    final a = Walk(1, 1)..outAndBack(toM: 300, reachM: 300);
    final b = Walk(2, 10000)..outAndBack(toM: 300, reachM: 300);
    final r = analyzePlanData(
      intent: antennas,
      variants: [
        variant(0, 'A', a, session(1)),
        variant(1, 'B', b, session(2)),
      ],
      base: _base,
    );
    final v = (r.digest['variants'] as List).first as Map;
    for (final k in ['sessions', 'presets', 'durationMin', 'rxCount',
        'pingsTotal', 'pingsOk', 'snrMedianDb', 'successPerBand']) {
      expect(v.keys, contains(k), reason: k);
    }
    final cmp = (r.digest['comparisons'] as List).first as Map;
    expect(cmp.keys, containsAll(['cellsMatched', 'snrMedianDeltaDb',
        'pctBBetterBy3Db', 'pctABetterBy3Db']));
  });
}
