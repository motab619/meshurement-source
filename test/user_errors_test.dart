// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/services/guided/plan_models.dart';
import 'package:mesh_analyzer/services/session_manager.dart';
import 'package:mesh_analyzer/utils/user_errors.dart';

void main() {
  group('userMessage', () {
    test('keeps a worded StateError as written', () {
      expect(
          userMessage(StateError(
              'The base and the mobile must speak the same protocol')),
          'The base and the mobile must speak the same protocol.');
      expect(userMessage(StateError('That is the mobile node itself, not the base.')),
          'That is the mobile node itself, not the base.');
    });

    test('keeps the MeshCore relay refusal and its capital letters', () {
      final m = userMessage(StateError(
          'Node rejected setting: relaying is not allowed on 915.000 MHz. '
          'A MeshCore base can only relay on 433.000, 869.495, 918.000 MHz.'));
      expect(
          m,
          'The node refused that setting. Relaying is not allowed on '
          '915.000 MHz. A MeshCore base can only relay on 433.000, 869.495, '
          '918.000 MHz.');
      expect(m, isNot(contains('mhz')));
    });

    test('enum-style refusal reasons are made readable', () {
      expect(userMessage(StateError('Node rejected setting: NOT_AUTHORIZED')),
          'The node refused that setting (not authorized).');
      expect(
          userMessage(
              StateError('Node rejected setting (node params): ILLEGAL_ARG')),
          'The node refused that setting (illegal arg).');
    });

    test('worded exceptions (PlanError, SessionStartError) pass through', () {
      expect(userMessage(const PlanError('Pick at least two antennas')),
          'Pick at least two antennas.');
      expect(userMessage(const SessionStartError('No base node yet.')),
          'No base node yet.');
      expect(userMessage(Exception('The node has no free channel slot')),
          'The node has no free channel slot.');
    });

    test('non-sentences fall back to the generic text', () {
      for (final e in <Object>[
        StateError('No element'),
        StateError('bad'),
        StateError('Cannot add event after closing'),
        const FormatException('Unexpected character'),
        ArgumentError('Value is wrong'),
        RangeError('Index out of range'),
      ]) {
        final m = userMessage(e, doing: 'saving');
        expect(m, startsWith('Something went wrong while saving.'),
            reason: '$e');
        expect(m, isNot(contains('Error')), reason: '$e');
      }
    });

    test('no em-dashes in any message', () {
      expect(userMessage(const HttpStatusException(429)), isNot(contains('—')));
    });
  });

  group('Android Bluetooth errors', () {
    test('lost bond in flutter_blue_plus Android wording', () {
      for (final t in [
        'FlutterBluePlusException | setNotifyValue | android-code: 5 | '
            'GATT_INSUFFICIENT_AUTHENTICATION',
        'FlutterBluePlusException | readCharacteristic | android-code: 137 '
            '| GATT_AUTH_FAIL',
        'FlutterBluePlusException | connect | android-code: 6 | '
            'PIN_OR_KEY_MISSING',
        'FlutterBluePlusException | connect | android-code: 5 | '
            'AUTHENTICATION_FAILURE',
      ]) {
        expect(isLostBondError(t), isTrue, reason: t);
      }
      // CoreBluetooth's 14 is a lost bond; Android's 14 is not.
      expect(
          isLostBondError('FlutterBluePlusException | connect | apple-code: '
              '14 | Peer removed pairing information'),
          isTrue);
      expect(
          isLostBondError(
              'FlutterBluePlusException | connect | android-code: 14 | x'),
          isFalse);
    });

    test('startScan refusals on Android 11 and older', () {
      expect(
          userMessage(PlatformException(
              code: 'startScan',
              message: 'Location services are required for Bluetooth scan')),
          startsWith('Location is off.'));
      expect(
          userMessage(PlatformException(
              code: 'startScan',
              message: 'Permission android.permission.ACCESS_FINE_LOCATION '
                  'required to scan devices')),
          startsWith('Location permission is off.'));
      expect(
          userMessage(PlatformException(
              code: 'startScan', message: 'Bluetooth must be turned on')),
          startsWith('Bluetooth is off.'));
      expect(
          userMessage(PlatformException(
              code: 'startScan',
              message: 'Permission android.permission.BLUETOOTH_SCAN '
                  'required to scan devices')),
          startsWith('Bluetooth permission is off.'));
    });
  });

  test('isUserSentence', () {
    expect(isUserSentence('Connect the base first'), isTrue);
    expect(isUserSentence('lowercase start'), isFalse);
    expect(isUserSentence('Single'), isFalse);
    expect(isUserSentence('FormatException: x y'), isFalse);
  });
}
