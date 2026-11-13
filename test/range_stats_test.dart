// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/services/airtime_model.dart';
import 'package:mesh_analyzer/services/range_stats.dart';
import 'package:mesh_analyzer/ui/widgets/range_polar_plot.dart';
import 'package:mesh_analyzer/utils/constants.dart';

const _base = LatLng(33.68, -116.24);
final _t0 = DateTime(2026, 10, 1, 12);

/// A point [m] metres due east of the base.
LatLng east(double m) => LatLng(_base.latitude,
    _base.longitude + m / (111320 * math.cos(33.68 * math.pi / 180)));

Session session(int id,
        {double? chanUtil,
        double? airTx,
        double airtime = 0,
        String preset = 'MEDIUM_FAST',
        int? txPower,
        int? slot,
        double? mhz}) =>
    Session(
      id: id,
      coverageMapId: 1,
      name: '',
      startedAt: _t0,
      isActive: false,
      hwAntenna: '',
      hwNodeModel: '',
      hwNotes: '',
      loraPreset: preset,
      protocol: 'meshtastic',
      pingIntervalSec: 30,
      packetAirtimeMs: airtime,
      radioChannelUtil: chanUtil,
      radioAirUtilTx: airTx,
      rangeTestActive: false,
      packetCount: 0,
      beaconKind: '',
      beaconIntervalSec: 0,
      txPowerDbm: txPower,
      frequencySlot: slot,
      frequencyMhz: mhz,
    );

/// One synthetic out-and-back walk along the east axis.
class Walk {
  final int sessionId;
  final events = <PacketEvent>[];
  final corrs = <PingCorrelation>[];
  var _id = 1;
  var _sec = 0;

  Walk(this.sessionId, {int idBase = 0}) {
    _id = idBase + 1;
  }

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

  /// A position fix (range-test style rx packet from the base).
  void heard(double m, {double snr = 5, int rssi = -100}) =>
      _ev(PacketDirection.rx, m,
          snr: snr, rssi: rssi, type: PacketType.rangeTest);

  /// A packet from another node (not the base) heard at [m] metres.
  void heardOther(double m, {int source = 77}) => _ev(PacketDirection.rx, m,
      snr: 2, rssi: -100, type: PacketType.telemetry, source: source);

  /// Ping sent at [m] metres with [status]; an ACK event when answered,
  /// from the base unless [ackSource] says otherwise.
  void ping(double m, String status,
      {int? rtMs, double snr = 4, int rssi = -105, int ackSource = 1}) {
    final tx = _ev(PacketDirection.tx, m, source: 2);
    int? ackId;
    if (status == AckStatus.received || status == AckStatus.implicit) {
      ackId = _ev(PacketDirection.ack, m,
              snr: snr, rssi: rssi, type: PacketType.ack, source: ackSource)
          .id;
    }
    corrs.add(PingCorrelation(
      id: corrs.length + 1 + sessionId * 1000,
      txEventId: tx.id,
      ackEventId: ackId,
      roundTripMs: rtMs,
      ackStatus: status,
    ));
  }
}

SideRangeStats stats(Walk w, {String name = 'X', Session? s, LatLng? base}) =>
    computeSideStats(
      name: name,
      sessions: [s ?? session(w.sessionId)],
      events: w.events,
      correlations: w.corrs,
      base: base ?? _base,
      baseNodeDbId: 1,
    );

void main() {
  group('band bucketing and counts', () {
    test('pings land in [lo, hi) bands', () {
      final w = Walk(1)
        ..ping(0, 'received', rtMs: 1000)
        ..ping(295, 'received', rtMs: 1000)
        ..ping(302, 'timeout')
        ..ping(495, 'received', rtMs: 1000)
        ..ping(502, 'received', rtMs: 1000)
        ..ping(695, 'timeout')
        ..ping(702, 'timeout')
        ..ping(995, 'received', rtMs: 1000)
        ..ping(1002, 'timeout')
        ..ping(1500, 'timeout');
      final s = stats(w);
      expect([for (final b in s.bands) b.sent], [2, 2, 2, 2, 2]);
      expect([for (final b in s.bands) b.acked], [2, 1, 1, 1, 0]);
      expect(s.bands.map((b) => b.label).toList(),
          ['0–300 m', '300–500 m', '500–700 m', '700–1000 m', '1000+ m']);
      expect(s.bands[1].rate, 0.5);
      expect(s.headlineBandSent, 6);
      expect(s.headlineBandAcked, 3);
    });

    test('ACK, implicit, timeout, error and throttled', () {
      final w = Walk(1)
        ..ping(100, 'received', rtMs: 2000)
        ..ping(110, 'implicit')
        ..ping(120, 'timeout')
        ..ping(130, 'error:NO_ROUTE')
        ..ping(140, 'throttled');
      final s = stats(w);
      expect(s.pingsSent, 4, reason: 'throttled pings never went on air');
      expect(s.pingsAcked, 1);
      expect(s.pingsImplicit, 1);
      expect(s.ackRate, 0.25);
      expect(s.bands[0].sent, 4);
      expect(s.bands[0].acked, 1, reason: 'implicit is not a base ACK');
      expect(s.pings.where((p) => p.implicit).length, 1);
      expect(s.pings.where((p) => p.missed).length, 2);
    });

    test('no pings gives null rates', () {
      final s = stats(Walk(1)..heard(10));
      expect(s.pingsSent, 0);
      expect(s.ackRate, isNull);
      expect(s.farthestAckM, isNull);
      expect(s.firstMissM, isNull);
      expect(s.bands.every((b) => b.rate == null), isTrue);
    });
  });

  group('distances and medians', () {
    test('farthest ACK, closest miss, farthest walked, heard base', () {
      final w = Walk(1)
        ..heard(50)
        ..ping(200, 'received', rtMs: 1000)
        ..ping(357, 'timeout')
        ..ping(600, 'received', rtMs: 3000)
        ..ping(900, 'timeout')
        ..heard(800)
        ..heard(1200, snr: -10, rssi: -120);
      final s = stats(w);
      expect(s.farthestAckM, closeTo(600, 2));
      expect(s.firstMissM, closeTo(357, 2));
      expect(s.farthestWalkedM, closeTo(1200, 3));
      expect(s.heardBaseOutToM, closeTo(1200, 3));
    });

    test('medians: round trip counts received only; SNR/RSSI base packets', () {
      final w = Walk(1)
        ..ping(100, 'received', rtMs: 1000, snr: 8, rssi: -90)
        ..ping(200, 'received', rtMs: 3000, snr: 4, rssi: -100)
        ..ping(300, 'received', rtMs: 2000, snr: 6, rssi: -95)
        ..ping(400, 'implicit', rtMs: 99999);
      final s = stats(w);
      expect(s.medianRoundTripMs, 2000);
      // Base ACK events carry SNR 8, 4, 6, and the implicit one 4 (default).
      expect(s.medianSnr, 5);
      expect(s.medianRssi, -97.5);
    });

    test('other nodes\' packets are not base packets', () {
      final w = Walk(1)..ping(100, 'received', rtMs: 1, snr: 9, rssi: -80);
      w.events.add(PacketEvent(
        id: 999,
        sessionId: 1,
        timestamp: _t0.add(const Duration(hours: 1)),
        direction: PacketDirection.rx,
        sourceNodeId: 77,
        rxSnr: -20,
        rxRssi: -130,
        hopCount: 0,
        rxLat: east(3000).latitude,
        rxLon: east(3000).longitude,
        packetType: PacketType.rangeTest,
        channelIndex: 0,
        viaMqtt: false,
        sourceKind: 'range_test',
      ));
      final s = stats(w);
      expect(s.medianSnr, 9);
      expect(s.heardBaseOutToM, closeTo(100, 2));
    });

    test('airtime and channel utilisation come from the sessions', () {
      final w = Walk(1)..ping(10, 'received', rtMs: 1);
      final s = stats(w, s: session(1, chanUtil: 12.5, airTx: 3, airtime: 410));
      expect(s.packetAirtimeMs, 410);
      expect(s.channelUtilPct, 12.5);
      expect(s.airUtilTxPct, 3);
    });
  });

  group('base position', () {
    test('order: user, node, radio setup, estimate', () {
      const u = LatLng(1, 1), n = LatLng(2, 2), r = LatLng(3, 3);
      expect(resolveBase(userBase: u, nodeBase: n, radioSetupBase: r)!.method,
          BaseMethod.placedByUser);
      expect(resolveBase(nodeBase: n, radioSetupBase: r)!.method,
          BaseMethod.baseNode);
      expect(resolveBase(radioSetupBase: r)!.method, BaseMethod.radioSetup);
      expect(resolveBase(), isNull);
    });

    test('estimated from clustered start/end points of several sessions', () {
      // Session 1 and 2 both start and end near the base (+-30 m jitter),
      // wandering out to 800 m / -600 m in between.
      final w1 = Walk(1)
        ..heard(20)
        ..heard(800)
        ..heard(-25);
      final w2 = Walk(2, idBase: 100)
        ..heard(-30)
        ..heard(-600)
        ..heard(15);
      final base = estimateBase([...w1.events, ...w2.events])!;
      expect(const Distance()(base, _base), lessThan(40));
      final r = resolveBase(events: [...w1.events, ...w2.events])!;
      expect(r.method, BaseMethod.estimated);
      expect(r.method.footnote, contains('stationary start and end points'));
    });

    test('a one-way walk gives no estimate', () {
      final w = Walk(1)
        ..heard(0)
        ..heard(2000);
      expect(estimateBase(w.events), isNull);
    });

    test('footnotes never contain coordinates', () {
      for (final m in BaseMethod.values) {
        expect(m.footnote, isNot(matches(RegExp(r'\d'))));
      }
    });
  });

  group('headline and caveats', () {
    /// Side with pings spread over the bands; [okAt] decides success.
    Walk walk(int id, List<double> at, bool Function(double) okAt,
        {int rt = 2000}) {
      final w = Walk(id, idBase: id * 1000);
      for (final m in at) {
        okAt(m) ? w.ping(m, 'received', rtMs: rt) : w.ping(m, 'timeout');
      }
      return w;
    }

    RangeComparison cmp(Walk a, Walk b,
        {Session? sa, Session? sb, int cells = 100}) {
      return compareRange(
        sessionsA: [sa ?? session(a.sessionId)],
        sessionsB: [sb ?? session(b.sessionId)],
        events: [...a.events, ...b.events],
        correlations: [...a.corrs, ...b.corrs],
        nameA: 'MediumFast',
        nameB: 'ShortFast',
        userBase: _base,
        baseNodeDbId: 1,
        matchedCells: cells,
        nodeNames: const {1: 'Base', 77: 'Spare Heltec'},
      )!;
    }

    final spread = <double>[350.0, 400, 450, 550, 600, 650, 750, 800, 850, 950];

    test('band-rate winner, exact wording and summary', () {
      final a = walk(1, spread, (m) => m < 900); // 8/10 in the band
      final b = walk(2, spread, (m) => m < 500, rt: 1000); // 3/10
      final r = cmp(
        a,
        b,
        sa: session(1, chanUtil: 25),
        sb: session(2, chanUtil: 5),
      );
      expect(r.aWins, isTrue);
      expect(r.headline, 'MediumFast held the link farther than ShortFast');
      expect(r.summary, contains('Both lost the base somewhere past'));
      expect(r.summary, contains('MediumFast kept 90% of pings acknowledged'));
      expect(r.summary, contains('ShortFast kept 30% of pings acknowledged'));
      expect(r.summary, contains('dropped its first ping at 55'));
      expect(
          r.summary,
          contains(
              'ShortFast answered faster and used about a fifth of the channel.'));
    });

    test('B wins when it keeps the higher rate', () {
      final a = walk(1, spread, (m) => m < 500);
      final b = walk(2, spread, (m) => m < 900);
      final r = cmp(a, b);
      expect(r.aWins, isFalse);
      expect(r.headline, startsWith('ShortFast held the link'));
    });

    test('equal rates fall back to the farther ACK, then to a tie', () {
      final a = walk(1, [350.0, 950], (m) => m < 400 || m > 900); // 100%/..
      final b = walk(2, [350.0, 950], (m) => m < 400 || m > 900);
      final r = cmp(a, b);
      expect(r.aWins, isNull);
      expect(r.headline, 'Both held the link over the whole route');
      expect(r.proved, contains('cover this whole route'));
      expect(r.proved, contains('MediumFast answered 2 of 2 pings'));
      expect(r.strengths, [
        'Neither side led on any measure here. On this '
            'route they are equivalent, so choose on price, weight or battery.'
      ]);
      expect(r.dataNotes, isEmpty);
    });

    test('a tie at the same wall names the wall, proves terrain, gives stops',
        () {
      // Both answered out to ~650 m, nothing past; edge ACKs at -106 dBm.
      final a = Walk(1, idBase: 1000);
      final b = Walk(2, idBase: 2000);
      for (final w in [a, b]) {
        for (final m in spread) {
          m < 700
              ? w.ping(m, 'received', rtMs: 3000, snr: -5, rssi: -106)
              : w.ping(m, 'timeout');
        }
      }
      final r = cmp(a, b);
      expect(r.aWins, isNull);
      expect(
          r.headline, 'Too close to call: both hit the same wall near 650 m');
      expect(
          r.proved, startsWith('You proved the link here is terrain-limited'));
      expect(r.proved, contains('(651 m vs 651 m)'));
      expect(r.proved, contains('near -106 dBm'));
      expect(r.proved, contains('raising or moving the base will'));
      expect(
          r.nextStep,
          startsWith('To split them: stop for a minute at about '
              '600, 700 and 800 m from the base'));
      expect(r.nextStep, contains('every other node off'));
    });

    test('strengths carry margins and are capped at two per side', () {
      // A: cleaner at the edge (SNR 2 vs -6) and faster; B: reaches farther
      // (950 vs 650 m) and more of the band.
      final a = Walk(1, idBase: 1000);
      final b = Walk(2, idBase: 2000);
      for (final m in spread) {
        m < 700
            ? a.ping(m, 'received', rtMs: 2000, snr: 2)
            : a.ping(m, 'timeout');
        b.ping(m, 'received', rtMs: 4000, snr: -6);
      }
      final r =
          cmp(a, b, sa: session(1, chanUtil: 20), sb: session(2, chanUtil: 5));
      expect(r.aWins, isFalse);
      expect(r.strengths.length, 2);
      expect(
          r.strengths[0],
          'MediumFast: held cleaner contact at the edge (median ACK SNR '
          '2.0 dB vs -6.0 dB past 300 m); answered faster (median 2.0 s vs '
          '4.0 s).');
      expect(
          r.strengths[1],
          'ShortFast: kept more pings answered between 300 and 1000 m '
          '(100% vs 60%); reached the farthest answered ping (951 m vs 651 m).');
      expect(r.proved, contains('ShortFast reaches where MediumFast does not'));
      expect(r.nextStep, startsWith('Confirm it: rerun MediumFast'));
    });

    test('a side that led nowhere says so', () {
      final a = walk(1, spread, (m) => m < 900);
      final b = walk(2, spread, (m) => m < 500);
      final r = cmp(a, b);
      expect(r.strengths.last, 'ShortFast: no measure where it led.');
    });

    test('another radio on the channel and relay-only ACKs are flagged', () {
      final a = walk(1, spread, (m) => m < 800)
        ..heardOther(100)
        ..heardOther(400);
      final b = walk(2, spread, (m) => m < 800)..ping(420, 'implicit');
      final r = cmp(a, b);
      expect(r.a.otherNodesHeard, {77: 2});
      expect(r.a.acksFromOtherNodes, isEmpty);
      expect(
          r.dataNotes,
          contains('MediumFast: Spare Heltec was heard 2 times on the test '
              'channel. A second base left on can answer pings through a relay '
              'and muddy the result; rerun with it off.'));
      expect(
          r.dataNotes,
          contains('ShortFast: 1 ping was answered only through a relay. They '
              'are shown but not counted as reaching the base.'));
    });

    test('answers from a node other than the base are flagged', () {
      final a = Walk(1, idBase: 1000);
      for (final m in spread) {
        a.ping(m, 'received', rtMs: 1000, ackSource: 77);
      }
      final b = walk(2, spread, (m) => true);
      final r = cmp(a, b);
      expect(r.a.acksFromOtherNodes, {77: 10});
      expect(r.a.otherNodesHeard, isEmpty, reason: 'ACKs are not "heard"');
      // The radio that answered is the target, not a stray second base.
      a.heardOther(100);
      expect(
          cmp(a, b).dataNotes.where((n) => n.contains('was heard')), isEmpty);
      expect(r.a.pingsAcked, 10, reason: 'the ACK still counts as answered');
      expect(
          r.dataNotes.first,
          "MediumFast: 10 answers came from Spare Heltec, not the map's base "
          'node. Check which node the pings were aimed at.');
    });

    test('an unnamed other node is "another radio"', () {
      final a = walk(1, spread, (m) => true)..heardOther(50, source: 99);
      final b = walk(2, spread, (m) => true);
      expect(cmp(a, b).dataNotes.first,
          contains('another node was heard 1 time'));
    });

    test('different transmit power is a data note, not a null result', () {
      final a = walk(1, spread, (m) => m < 900);
      final b = walk(2, spread, (m) => m < 500);
      final r = cmp(a, b,
          sa: session(1, txPower: 27, slot: 45, mhz: 913.125),
          sb: session(2, txPower: 22, slot: 45, mhz: 913.125));
      expect(r.a.txPowersDbm, {27});
      expect(r.b.frequencySlots, {45});
      final note = r.dataNotes.singleWhere((n) => n.startsWith('Sides ran'));
      expect(
          note,
          'Sides ran at different transmit power (27 vs 22 dBm): antenna '
          'differences are confounded. The comparison still stands as '
          'measured; for a clean one, rerun with both on the same power.');
      // The verdict is still given.
      expect(r.aWins, isTrue);
    });

    test('different frequency is noted; same settings or unknown are not', () {
      final a = walk(1, spread, (m) => m < 900);
      final b = walk(2, spread, (m) => m < 500);
      expect(
          cmp(a, b,
                  sa: session(1, txPower: 27, slot: 20, mhz: 906.875),
                  sb: session(2, txPower: 27, slot: 45, mhz: 913.125))
              .dataNotes,
          contains(startsWith('Sides ran at different frequency '
              '(906.875 vs 913.125 MHz)')));
      expect(
          cmp(a, b,
                  sa: session(1, txPower: 27, slot: 20),
                  sb: session(2, txPower: 27, slot: 20))
              .dataNotes
              .where((n) => n.startsWith('Sides ran')),
          isEmpty);
      // One side from before v9: nothing to compare against.
      expect(
          cmp(a, b, sa: session(1, txPower: 27), sb: session(2))
              .dataNotes
              .where((n) => n.startsWith('Sides ran')),
          isEmpty);
    });

    test('flattered caveat when >60% of pings were within 200 m', () {
      final close = [for (var i = 0; i < 90; i++) 20.0 + i];
      final far = [for (var i = 0; i < 33; i++) 300.0 + i * 20];
      final a = walk(1, [...close, ...far], (m) => m < 300 || m > 2000);
      final b = walk(2, spread, (m) => m < 900);
      final r = cmp(a, b);
      expect(
          r.readingIt.any((t) => t.contains(
              '73% overall is flattered: 90 of 123 pings were sent within 200 m. '
              'The distance chart is the fairer comparison.')),
          isTrue,
          reason: r.readingIt.join('\n'));
      // B is not flattered.
      expect(r.readingIt.where((t) => t.contains('flattered')).length, 1);
    });

    test('similar ceiling points to terrain and antennas', () {
      final a = walk(1, spread, (m) => m < 800);
      final b = walk(2, spread, (m) => m < 850);
      final r = cmp(a, b);
      expect(
          r.readingIt.any((t) => t.contains('terrain and antennas')), isTrue);
      final c = walk(3, spread, (m) => m < 400);
      final d = walk(4, spread, (m) => m < 950);
      expect(cmp(c, d).readingIt.any((t) => t.contains('terrain and antennas')),
          isFalse);
    });

    test('non-overlapping routes advise a rerun', () {
      final a = walk(1, spread, (m) => m < 800);
      final b = walk(2, spread, (m) => m < 600);
      const rerun = 'To isolate the preset, rerun both on the same route, '
          'back to back.';
      expect(
          cmp(a, b, cells: 0).readingIt.any((t) => t.contains(rerun)), isTrue);
      expect(
          cmp(a, b, cells: 3).readingIt.any((t) => t.contains(rerun)), isTrue);
      expect(cmp(a, b, cells: 80).readingIt.any((t) => t.contains(rerun)),
          isFalse);
    });

    test('shared plot scale is the farthest point of either side', () {
      final a = walk(1, [100.0, 1800], (m) => true);
      final b = walk(2, [100.0, 400], (m) => true);
      expect(cmp(a, b).maxDistanceM, closeTo(1800, 5));
      expect(cmp(a, b).baseLooksMisplaced, isFalse);

      // The same walks with the base placed 50 km away: every point is far
      // from it, which is a misplaced base, not a long walk.
      final far = compareRange(
        sessionsA: [session(a.sessionId)],
        sessionsB: [session(b.sessionId)],
        events: [...a.events, ...b.events],
        correlations: [...a.corrs, ...b.corrs],
        nameA: 'A',
        nameB: 'B',
        userBase: LatLng(_base.latitude, _base.longitude + 0.5),
        baseNodeDbId: 1,
      )!;
      expect(far.nearestPointM, greaterThan(40000));
      expect(far.baseLooksMisplaced, isTrue);
    });

    test('both held everywhere on one preset suggests a faster one', () {
      // Edge ACK SNR 4 dB on Medium Fast: Short Turbo (SF7, 500 kHz) still
      // has 4 - 3 = 1 dB, over its -7.5 dB floor by more than 3 dB.
      final a = walk(1, spread, (m) => true);
      final b = walk(2, spread, (m) => true);
      final r = cmp(a, b);
      expect(r.headline, 'Both held the link over the whole route');
      expect(
          r.nextStep,
          startsWith('Both held the link everywhere on Medium Fast, so you '
              'have airtime to spare. Try Short Turbo next: a ping takes '));
      expect(r.nextStep, contains('less channel time.'));
      expect(r.nextStep,
          endsWith('Your ACK SNR at the edge (4.0 dB) leaves room for it.'));
    });

    test('no preset suggestion when the presets differ or are unknown', () {
      final a = walk(1, spread, (m) => true);
      final b = walk(2, spread, (m) => true);
      expect(
          cmp(a, b, sb: session(2, preset: 'SHORT_FAST')).nextStep,
          'Both held the link everywhere you went. Drive farther next time '
          'to find the edge.');
      expect(
          cmp(a, b, sa: session(1, preset: ''), sb: session(2, preset: ''))
              .nextStep,
          contains('Drive farther'));
    });

    test('no base position gives null', () {
      expect(
          compareRange(
              sessionsA: [session(1)],
              sessionsB: [session(2)],
              events: const [],
              correlations: const [],
              nameA: 'A',
              nameB: 'B'),
          isNull);
    });
  });

  group('faster preset suggestion', () {
    test('picks the fastest preset the measured SNR still supports', () {
      // -7 dB at the edge on Long Moderate (125 kHz). Medium Slow (SF10,
      // 250 kHz) reads -10 dB there, 5 dB over its -15 dB floor: ok. Medium
      // Fast (SF9) would be -10 vs a -12.5 floor: under the 3 dB margin.
      final s = fasterPresetFor(MeshtasticPresets.longModerate, edgeSnrDb: -7)!;
      expect(s.to, MeshtasticPresets.mediumSlow);
      expect(s.withinMargin, isTrue);
      expect(s.fromAirtimeMs,
          AirtimeModel.pingAirtimeMs(MeshtasticPresets.longModerate));
      expect(s.toAirtimeMs, lessThan(s.fromAirtimeMs / 3));
    });

    test('falls back to the next faster preset when nothing has margin', () {
      final s =
          fasterPresetFor(MeshtasticPresets.longModerate, edgeSnrDb: -14)!;
      expect(s.withinMargin, isFalse);
      expect(s.to.deprecated, isFalse);
      expect(s.toAirtimeMs,
          lessThan(AirtimeModel.pingAirtimeMs(MeshtasticPresets.longModerate)));
      // The gentlest step: the slowest preset that is still 10%+ faster.
      for (final p in standardPresets) {
        final t = AirtimeModel.pingAirtimeMs(p);
        if (!p.deprecated && t < s.fromAirtimeMs * 0.9) {
          expect(t, lessThanOrEqualTo(s.toAirtimeMs));
        }
      }
    });

    test('no SNR known: next faster preset, not within margin', () {
      final s = fasterPresetFor(MeshtasticPresets.mediumFast)!;
      expect(s.withinMargin, isFalse);
      expect(s.to, MeshtasticPresets.shortSlow);
    });

    test('nothing faster than Short Turbo', () {
      expect(
          fasterPresetFor(MeshtasticPresets.shortTurbo, edgeSnrDb: 10), isNull);
    });
  });

  group('polar rings', () {
    test('step keeps at most six rings at any radius', () {
      expect(polarRingStepFor(400), 100);
      expect(polarRingStepFor(1200), 200);
      expect(polarRingStepFor(1500), 250);
      expect(polarRingStepFor(2400), 500);
      expect(polarRingStepFor(50000), 10000);
      for (final d in [10.0, 777.0, 4321.0, 48000.0, 250000.0]) {
        final outer = polarOuterRingM(d);
        final step = polarRingStepFor(outer);
        expect(outer, greaterThanOrEqualTo(d));
        expect(outer / step, lessThanOrEqualTo(polarMaxRings));
        expect((outer / step).round() * step, closeTo(outer, 1e-6));
      }
    });

    test('labels switch to km', () {
      expect(polarRingLabel(250), '250 m');
      expect(polarRingLabel(1000), '1 km');
      expect(polarRingLabel(2500), '2.5 km');
    });
  });
}
