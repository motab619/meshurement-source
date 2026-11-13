// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesh_analyzer/services/base_location.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('round-trips a fix for a base node', () async {
    final store = BaseLocationStore(prefs);
    final at = DateTime(2026, 10, 16, 12, 30);
    expect(
        await store.record(0xb0b0b0b0, const LatLng(33.72, -116.24),
            accuracyM: 8, at: at),
        isTrue);
    final loaded = store.load(0xb0b0b0b0)!;
    expect(loaded.point.latitude, closeTo(33.72, 1e-9));
    expect(loaded.point.longitude, closeTo(-116.24, 1e-9));
    expect(loaded.accuracyM, 8);
    expect(loaded.at, at);
    expect(store.load(1), isNull);
  });

  test('ignores poor fixes', () async {
    final store = BaseLocationStore(prefs);
    expect(await store.record(7, const LatLng(0, 0), accuracyM: 120), isFalse);
    expect(store.load(7), isNull);
  });

  test('clear forgets it', () async {
    final store = BaseLocationStore(prefs);
    await store.record(7, const LatLng(1, 2), accuracyM: 5);
    await store.clear(7);
    expect(store.load(7), isNull);
    expect(BaseLocationStore.isKey('base_loc_7'), isTrue);
    expect(BaseLocationStore.isKey('base_node_num'), isFalse);
  });
}
