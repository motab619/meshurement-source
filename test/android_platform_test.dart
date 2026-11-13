// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/services/battery_hint.dart';
import 'package:mesh_analyzer/services/last_radio.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AndroidBatteryHint', () {
    test('once on Android, never on iOS', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(AndroidBatteryHint.takeOnce(prefs, android: false), isNull);
      expect(AndroidBatteryHint.takeOnce(prefs, android: true),
          contains('Unrestricted'));
      expect(AndroidBatteryHint.takeOnce(prefs, android: true), isNull);
    });
  });

  group('LastRadio.knownRadios', () {
    test('nothing known: empty', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(LastRadio(prefs).knownRadios(), isEmpty);
    });

    test('roles by id (protocol unknown) and the last radio with its own',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final roles = RadioRoles(prefs);
      await roles.assign(RadioRole.base, deviceId: 'AA:01');
      await roles.assign(RadioRole.mobile, deviceId: 'AA:02');
      await LastRadio(prefs).save(const RadioDescriptor(
          id: 'AA:02', name: 'MeshCore-mob', protocol: RadioProtocol.meshcore));
      expect(LastRadio(prefs).knownRadios(), {
        'AA:01': null,
        'AA:02': RadioProtocol.meshcore,
      });
    });
  });
}
