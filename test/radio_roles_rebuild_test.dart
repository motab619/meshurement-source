// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_mesh_radio.dart';

/// A remote base change records the base's new setting in [RadioRoles]
/// mid-sequence. That notification must not rebuild Radio Setup's service
/// (and the guided engine built on it), or the running change loses its
/// screen.
void main() {
  test('a roles notification keeps the same RadioProfileService', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      meshRadioProvider.overrideWithValue(
          FakeMeshRadio(currentPreset: MeshtasticPresets.mediumFast)),
    ]);
    addTearDown(container.dispose);
    final before = container.read(radioProfileServiceProvider);
    await container.read(radioRolesProvider).recordSetup(RadioRole.base,
        presetId: 'LONG_FAST', region: 'US', txPowerDbm: 20);
    await Future<void>.delayed(Duration.zero);
    expect(
        identical(container.read(radioProfileServiceProvider), before), isTrue);
  });
}
