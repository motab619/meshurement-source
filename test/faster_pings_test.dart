// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/airtime_model.dart';
import 'package:mesh_analyzer/services/pro_entitlement.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_mesh_radio.dart';
import 'pro_entitlement_test.dart' show FakeStore;

void main() {
  Future<int> effective(bool faster, int requested, {bool pro = true}) async {
    SharedPreferences.setMockInitialValues(
        {AppConstants.prefFasterThanRecommended: faster});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final radio = FakeMeshRadio()..currentPreset = MeshtasticPresets.longFast;
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      meshRadioProvider.overrideWithValue(radio),
      proEntitlementProvider.overrideWithValue(ProEntitlement(
          prefs: prefs, store: FakeStore(), proOverride: pro)),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    return container
        .read(sessionManagerProvider)
        .effectivePingIntervalSec(requested);
  }

  test('pings are raised to the airtime budget by default', () async {
    expect(await effective(false, 3),
        AirtimeModel.minIntervalSec(MeshtasticPresets.longFast));
  });

  test('"Faster than recommended" keeps a short interval', () async {
    final floor =
        AirtimeModel.fastestIntervalSecFor(MeshtasticPresets.longFast);
    expect(await effective(true, 4), 4 < floor ? floor : 4);
    expect(await effective(true, 1), floor); // never below the floor
  });

  test('without Pro "Faster than recommended" does nothing', () async {
    expect(await effective(true, 3, pro: false),
        AirtimeModel.minIntervalSec(MeshtasticPresets.longFast));
  });
}
