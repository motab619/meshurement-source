// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/services/test_build.dart';

void main() {
  test('TESTFLIGHT_PRO is off unless the build passes the define', () {
    // `flutter test` (like `flutter build` for the App Store) passes no
    // define, so the tester unlock must be off.
    expect(TestBuild.unlockPro, isFalse);
  });

  test('only the fastlane beta lane passes TESTFLIGHT_PRO', () {
    final fastfile = File('ios/fastlane/Fastfile').readAsStringSync();
    expect(fastfile,
        // The bench gate (tool/bench, warning mode) runs first in beta.
        contains('lane :beta do\n    bench_gate\n    upload_build(testflight_pro: true)'));
    expect(fastfile,
        contains('lane :release do\n    upload_build(testflight_pro: false)'));
    // The define is added only behind the lane's flag.
    expect(
        fastfile,
        contains(
            'args << "--dart-define=TESTFLIGHT_PRO=true" if testflight_pro'));
  });

  test('Android: Pro is free until Play sells it; iOS keeps the paywall', () {
    expect(TestBuild.proFreeOn(TargetPlatform.android), isTrue);
    expect(TestBuild.proFreeOn(TargetPlatform.iOS), isFalse);
  });
}
