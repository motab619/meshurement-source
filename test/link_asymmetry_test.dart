// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/services/link_asymmetry.dart';
import 'package:mesh_analyzer/services/range_stats.dart';
import 'package:mesh_analyzer/utils/constants.dart';

const _base = LatLng(33.68, -116.24);
final _t0 = DateTime(2026, 10, 1, 12);

LatLng _east(double m) => LatLng(_base.latitude,
    _base.longitude + m / (111320 * math.cos(33.68 * math.pi / 180)));

var _id = 1;

PacketEvent _event(String dir,
        {double? snr, int? rssi, double? up, double m = 100}) =>
    PacketEvent(
      id: _id++,
      sessionId: 1,
      timestamp: _t0.add(Duration(seconds: _id)),
      direction: dir,
      sourceNodeId: 1,
      rxSnr: snr,
      rxRssi: rssi,
      uplinkSnr: up,
      hopCount: 0,
      rxLat: _east(m).latitude,
      rxLon: _east(m).longitude,
      packetType: dir == PacketDirection.ack ? PacketType.ack : 'ping',
      channelIndex: 0,
      viaMqtt: false,
      sourceKind: dir == PacketDirection.ack ? SourceKind.ack : 'passive',
    );

Session _session(String protocol) => Session(
      id: 1,
      coverageMapId: 1,
      name: '',
      startedAt: _t0,
      isActive: false,
      hwAntenna: '',
      hwNodeModel: '',
      hwNotes: '',
      loraPreset: '',
      protocol: protocol,
      pingIntervalSec: 30,
      packetAirtimeMs: 0,
      rangeTestActive: false,
      packetCount: 0,
      beaconKind: '',
      beaconIntervalSec: 0,
    );

/// [n] answered link checks whose replies read [down] here and [up] at
/// the base (null = Meshtastic, no uplink).
({List<PacketEvent> events, List<PingCorrelation> corrs}) _walk(int n,
    {required double down, double? up}) {
  final events = <PacketEvent>[];
  final corrs = <PingCorrelation>[];
  for (var i = 0; i < n; i++) {
    final tx = _event(PacketDirection.tx, m: 100.0 + i * 50);
    final ack = _event(PacketDirection.ack,
        snr: down, rssi: -100, up: up, m: 100.0 + i * 50);
    events.addAll([tx, ack]);
    corrs.add(PingCorrelation(
      id: i + 1,
      txEventId: tx.id,
      ackEventId: ack.id,
      roundTripMs: 1200,
      ackStatus: AckStatus.received,
    ));
  }
  return (events: events, corrs: corrs);
}

void main() {
  group('linkAsymmetryOf', () {
    test('null under five pairs', () {
      expect(
          linkAsymmetryOf([for (var i = 0; i < 4; i++) (up: -3.0, down: -1.0)]),
          isNull);
      expect(linkAsymmetryOf(const []), isNull);
    });

    test('median of uplink minus downlink, with the count', () {
      final a = linkAsymmetryOf([
        (up: -5.0, down: -3.0), // -2
        (up: -4.0, down: -1.0), // -3
        (up: 0.0, down: 1.0), // -1
        (up: 2.0, down: 0.0), // +2
        (up: -6.0, down: -4.0), // -2
      ])!;
      expect(a.medianDeltaDb, -2);
      expect(a.count, 5);
      expect(a.aboutTheSame, isFalse);
    });
  });

  group('linkAsymmetryText', () {
    test('weaker, stronger and about the same', () {
      expect(linkAsymmetryText(const LinkAsymmetry(-2.1, 34)),
          'Uplink 2.1 dB weaker than downlink (median of 34 link checks)');
      expect(linkAsymmetryText(const LinkAsymmetry(3.0, 6)),
          'Uplink 3.0 dB stronger than downlink (median of 6 link checks)');
      expect(linkAsymmetryText(const LinkAsymmetry(-1.0, 8)),
          'Uplink and downlink about the same (median of 8 link checks)');
      expect(linkAsymmetryText(const LinkAsymmetry(0.4, 8)),
          startsWith('Uplink and downlink about the same'));
    });
  });

  group('from stored events', () {
    test('MeshCore replies with both legs give a line', () {
      final w = _walk(6, down: -5, up: -7.5);
      final a = linkAsymmetryFromEvents(w.events)!;
      expect(a.medianDeltaDb, -2.5);
      expect(a.count, 6);
    });

    test('Meshtastic replies (no uplink) give nothing', () {
      final w = _walk(20, down: -5);
      expect(linkAsymmetryFromEvents(w.events), isNull);
    });

    test('rx packets and relayed replies (no SNR) are left out', () {
      final events = [
        for (var i = 0; i < 4; i++) _event(PacketDirection.ack, snr: 1, up: 0),
        _event(PacketDirection.ack, up: 0), // relayed: no SNR
        _event(PacketDirection.rx, snr: 1, up: 0),
      ];
      expect(linkAsymmetryFromEvents(events), isNull);
      expect(linkAsymmetryFromEvents(events, minCount: 4)!.count, 4);
    });
  });

  group('SideRangeStats', () {
    SideRangeStats side(
            ({List<PacketEvent> events, List<PingCorrelation> corrs}) w,
            String protocol) =>
        computeSideStats(
          name: 'X',
          sessions: [_session(protocol)],
          events: w.events,
          correlations: w.corrs,
          base: _base,
          baseNodeDbId: 1,
        );

    test('carries the uplink per ping and the side asymmetry (MeshCore)', () {
      final s = side(_walk(5, down: -4, up: -1), 'meshcore');
      expect(s.pings.first.uplinkSnr, -1);
      expect(s.pings.first.snr, -4);
      expect(s.linkAsymmetry!.medianDeltaDb, 3);
      expect(s.linkAsymmetry!.count, 5);
    });

    test('no asymmetry on Meshtastic', () {
      final s = side(_walk(10, down: -4), 'meshtastic');
      expect(s.pings.first.uplinkSnr, isNull);
      expect(s.linkAsymmetry, isNull);
    });
  });

  group('roundTripReadout', () {
    test('MeshCore reply shows both legs', () {
      expect(
          roundTripReadout(
              status: AckStatus.received,
              downSnr: -5,
              upSnr: -3.2,
              downRssi: -110,
              roundTripMs: 1400),
          'Base replied · Up −3.2 dB · Down −5.0 dB · -110 dBm · '
          'round trip 1.4 s');
    });

    test('Meshtastic reply labels its SNR as base → you', () {
      expect(roundTripReadout(status: AckStatus.received, downSnr: 2.5),
          'Base replied · Reply 2.5 dB SNR (base → you)');
    });

    test('other outcomes', () {
      expect(roundTripReadout(status: AckStatus.timeout), 'No reply');
      expect(roundTripReadout(status: AckStatus.implicit), 'Relayed only');
      expect(roundTripReadout(status: AckStatus.throttled),
          'Held back by radio (not sent)');
      expect(roundTripReadout(status: AckStatus.errorWithReason('NO_CHANNEL')),
          'Refused (NO_CHANNEL)');
    });

    test('formatDb uses a real minus sign', () {
      expect(formatDb(-3.24), '−3.2 dB');
      expect(formatDb(0.04), '0.0 dB');
      expect(formatDb(-0.01), '0.0 dB');
      expect(upDownText(1, -2), 'Up 1.0 dB · Down −2.0 dB');
    });
  });
}
