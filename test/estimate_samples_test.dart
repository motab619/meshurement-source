// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/services/coverage_interpolation.dart';
import 'package:mesh_analyzer/services/estimate_samples.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:mesh_analyzer/utils/link_margin.dart';

PacketEvent _event(
  int id, {
  String direction = PacketDirection.rx,
  double? snr,
  int? rssi,
  double? lat = 33.68,
  double? lon = -116.24,
  String sourceKind = SourceKind.passive,
}) =>
    PacketEvent(
      id: id,
      sessionId: 1,
      timestamp: DateTime(2026, 11, 4),
      direction: direction,
      sourceNodeId: 1,
      rxSnr: snr,
      rxRssi: rssi,
      hopCount: 0,
      rxLat: lat,
      rxLon: lon,
      packetType: direction == PacketDirection.ack ? 'ack' : 'telemetry',
      channelIndex: 0,
      viaMqtt: false,
      sourceKind: sourceKind,
    );

PingResult _ping(int txId, String status, {double? lat = 33.681, int? ackId}) =>
    PingResult(
      tx: _event(txId, direction: PacketDirection.tx, lat: lat),
      correlation: PingCorrelation(
          id: txId, txEventId: txId, ackEventId: ackId, ackStatus: status),
    );

MarginScale _scale(PacketEvent _) => MarginScale.fallback;

/// The estimated layer counts silence: an unanswered ping, or a reply with
/// no usable signal, is a "no margin" sample where the phone was
/// (TestFlight report, 2026-11-04).
void main() {
  test('received signals become link margins', () {
    final s = EstimateSamples.from(
      rx: [_event(1, snr: -7.5), _event(2, snr: 2.5, rssi: -90)],
      pings: const [],
      rssi: false,
      scaleOf: _scale,
    );
    expect(s.values, [10.0, 20.0]);
    expect(s.ids, [1, 2]);
    expect(s.silent, 0);
  });

  test('a timed-out ping is no margin at the phone position', () {
    final s = EstimateSamples.from(
      rx: [_event(1, snr: 2.5)],
      pings: [
        _ping(10, AckStatus.timeout),
        _ping(11, AckStatus.received),
        _ping(12, 'error:PKI_UNKNOWN_PUBKEY'), // refused, not on air
        _ping(13, AckStatus.throttled),
        _ping(14, AckStatus.timeout, lat: null), // no position: skipped
      ],
      rssi: false,
      scaleOf: _scale,
    );
    expect(s.values, [20.0, EstimateSamples.silentMarginDb]);
    expect(s.lats, [33.68, 33.681]);
    expect(s.ids, [1, 10]);
    expect(s.silent, 1);
  });

  test('an older MAX_RETRANSMIT row is silence (sent, unanswered)', () {
    final s = EstimateSamples.from(
      rx: [],
      pings: [
        _ping(10, 'error:MAX_RETRANSMIT'),
        _ping(11, 'error:NO_CHANNEL'), // refused: not silence
      ],
      rssi: false,
      scaleOf: _scale,
    );
    expect(s.ids, [10]);
    expect(s.silent, 1);
  });

  test('a reply without a signal (relayed or implicit) is silence too', () {
    final s = EstimateSamples.from(
      rx: [
        _event(1, direction: PacketDirection.ack, sourceKind: SourceKind.ack),
        _event(2, snr: null), // a heard packet with no SNR: not evidence
        _event(3, direction: PacketDirection.ack, snr: -7.5, rssi: -100),
        _event(4, direction: PacketDirection.ack, sourceKind: SourceKind.ack),
      ],
      pings: [
        _ping(10, AckStatus.received, ackId: 1), // relayed: signal dropped
        _ping(11, AckStatus.received, ackId: 3), // direct: counted via rx
        _ping(12, AckStatus.implicit, ackId: 4),
      ],
      rssi: false,
      scaleOf: _scale,
    );
    expect(s.values, [
      10.0,
      EstimateSamples.silentMarginDb,
      EstimateSamples.silentMarginDb,
    ]);
    expect(s.ids, [3, 1, 4]);
    expect(s.silent, 2);
  });

  test('a refused or throttled ping leaves a reply row but is not silence', () {
    // The radio never put these on air (local PKI NAK, duty-cycle limit),
    // so their signal-less reply rows prove nothing about coverage.
    final s = EstimateSamples.from(
      rx: [
        _event(1, direction: PacketDirection.ack, sourceKind: SourceKind.ack),
        _event(2, direction: PacketDirection.ack, sourceKind: SourceKind.ack),
      ],
      pings: [
        _ping(10, 'error:PKI_SEND_FAIL_PUBLIC_KEY', ackId: 1),
        _ping(11, AckStatus.throttled, ackId: 2),
      ],
      rssi: false,
      scaleOf: _scale,
    );
    expect(s.isEmpty, isTrue);
    expect(s.silent, 0);
  });

  test('RSSI mode uses the red end of the ramp for silence', () {
    final s = EstimateSamples.from(
      rx: [_event(1, snr: 2.5, rssi: -80)],
      pings: [_ping(10, AckStatus.timeout)],
      rssi: true,
      scaleOf: _scale,
    );
    expect(s.values, [-80.0, EstimateSamples.silentRssi]);
  });

  test('silence between strong samples pulls the estimate down there', () {
    // Base-side greens at x = 0, a red at 150 m west, two timed-out pings
    // on the way: the cells around them are no longer green.
    const lat = 33.68007, lon = -116.24006;
    double east(double m) => lon + m / metersPerDegree(lat).$2;
    final rx = [
      for (var i = 0; i < 8; i++)
        _event(i, snr: 2.5, lat: lat + i * 0.00004, lon: east(10.0 * i)),
      _event(20, snr: -17.5, lat: lat, lon: east(-150)),
    ];
    final pings = [
      for (var i = 0; i < 2; i++)
        PingResult(
          tx: _event(30 + i,
              direction: PacketDirection.tx,
              lat: lat,
              lon: east(-60 - 40.0 * i)),
          correlation: PingCorrelation(
              id: 30 + i, txEventId: 30 + i, ackStatus: AckStatus.timeout),
        ),
    ];
    final without = EstimateSamples.from(
        rx: rx, pings: const [], rssi: false, scaleOf: _scale);
    final with_ = EstimateSamples.from(
        rx: rx, pings: pings, rssi: false, scaleOf: _scale);
    final gBefore =
        interpolateCoverage(without.lats, without.lons, without.values)!;
    final gAfter = interpolateCoverage(with_.lats, with_.lons, with_.values)!;
    final mid = gAfter.cellAt(lat, east(-80));
    final midBefore = gBefore.cellAt(lat, east(-80));
    expect(gBefore.values[midBefore], greaterThan(10)); // yellow-green before
    expect(gAfter.values[mid], lessThan(5)); // red-ish now
  });
}
