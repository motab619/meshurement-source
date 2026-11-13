// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/units.dart';
import 'package:mesh_analyzer/utils/constants.dart';

void main() {
  test('Automatic follows the region; the override wins', () {
    expect(DistanceUnits.automatic.useMiles('US'), isTrue);
    expect(DistanceUnits.automatic.useMiles('GB'), isTrue);
    expect(DistanceUnits.automatic.useMiles('DE'), isFalse);
    expect(DistanceUnits.automatic.useMiles(null), isFalse);
    expect(DistanceUnits.miles.useMiles('DE'), isTrue);
    expect(DistanceUnits.kilometres.useMiles('US'), isFalse);
    expect(DistanceUnits.fromName('nonsense'), DistanceUnits.automatic);
  });

  test('distances: miles and feet, kilometres and metres', () {
    expect(formatDistance(650, miles: true), '0.4 mi');
    expect(formatDistance(120, miles: true), '390 ft');
    expect(formatDistance(2896, miles: true), '1.8 mi');
    expect(formatDistance(650, miles: false), '650 m');
    expect(formatDistance(2896, miles: false), '2.9 km');
    expect(formatDistance(25000, miles: false), '25 km');
  });

  test('Hide base area: 120 / 300 m, or 400 / 1,000 ft (never less)', () {
    expect(hideRadiusChoicesM(miles: false), [0, 120, 300]);
    final ft = hideRadiusChoicesM(miles: true);
    expect(ft[1], greaterThanOrEqualTo(120));
    expect(ft[2], greaterThanOrEqualTo(300));
    expect([for (final m in ft) hideRadiusLabel(m, miles: true)],
        ['Off', '400 ft', '1,000 ft']);
    expect(hideRadiusLabel(120, miles: false), '120 m');
  });

  test('scale bar picks a round length', () {
    expect(niceScaleBar(130, miles: false), (100.0, '100 m'));
    expect(niceScaleBar(1500, miles: false).$2, '1 km');
    expect(niceScaleBar(200, miles: true).$2, '500 ft');
    expect(niceScaleBar(2000, miles: true).$2, '1 mi');
  });

  test('the setting persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    expect(c.read(distanceUnitsProvider), DistanceUnits.automatic);
    c.read(distanceUnitsProvider.notifier).set(DistanceUnits.kilometres);
    expect(c.read(useMilesProvider), isFalse);
    expect(prefs.getString(AppConstants.prefDistanceUnits), 'kilometres');
    c.read(distanceUnitsProvider.notifier).set(DistanceUnits.miles);
    expect(c.read(useMilesProvider), isTrue);
  });
}
