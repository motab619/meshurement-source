// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/services/track_distance.dart';
import 'package:mesh_analyzer/utils/constants.dart';

const _degPerM = 1 / 111320;

PacketEvent _ev(int sec, double? lat, double? lon, {String kind = ''}) =>
    PacketEvent(
      id: sec,
      sessionId: 1,
      timestamp: DateTime(2026, 10, 1, 12).add(Duration(seconds: sec)),
      direction: 'rx',
      sourceNodeId: 1,
      packetType: 'range_test',
      rxLat: lat,
      rxLon: lon,
      hopCount: 0,
      viaMqtt: false,
      channelIndex: 0,
      sourceKind: kind,
    );

void main() {
  test('straight line north: 1 km in ten 100 m steps', () {
    final evs = [
      for (var i = 0; i <= 10; i++) _ev(i, 33 + i * 100 * _degPerM, -116)
    ];
    expect(trackDistanceM(evs), closeTo(1000, 5));
  });

  test('unsorted input is ordered by time, not by list position', () {
    final evs = [
      for (var i = 0; i <= 10; i++) _ev(i, 33 + i * 100 * _degPerM, -116)
    ];
    final shuffled = [...evs]..shuffle();
    expect(trackDistanceM(shuffled), closeTo(1000, 5));
    // Sorted by position but zig-zagging in time would be ~5x longer.
  });

  test('stationary jitter under 3 m adds nothing', () {
    final evs = [
      for (var i = 0; i < 20; i++)
        _ev(i, 33 + (i.isEven ? 0 : 2) * _degPerM, -116),
    ];
    expect(trackDistanceM(evs), 0);
  });

  test('rows without a fix and beacon misses are ignored', () {
    final evs = [
      _ev(0, 33, -116),
      _ev(1, null, null),
      _ev(2, 34, -116, kind: SourceKind.telemetryMiss), // 111 km away
      _ev(3, 33 + 500 * _degPerM, -116),
    ];
    expect(trackDistanceM(evs), closeTo(500, 3));
  });

  test('fewer than two fixes is zero', () {
    expect(trackDistanceM([]), 0);
    expect(trackDistanceM([_ev(0, 33, -116)]), 0);
  });

  test('track length helper', () {
    expect(trackLengthM([const LatLng(0, 0), const LatLng(0, 1)]),
        closeTo(111320, 200));
  });

  test('formatting: miles or km, nothing under 50 m', () {
    expect(formatTrackDistance(8208, miles: true), '5.1 mi');
    expect(formatTrackDistance(8208, miles: false), '8.2 km');
    expect(formatTrackDistance(49, miles: true), isNull);
    expect(milesForCountry('US'), isTrue);
    expect(milesForCountry('gb'), isTrue);
    expect(milesForCountry('DE'), isFalse);
    expect(milesForCountry(null), isFalse);
  });
}
