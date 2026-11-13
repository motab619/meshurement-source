// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/foundation.dart';

/// Tester builds (TestFlight, Google Play internal/closed testing) unlock
/// every Pro feature so testers can try them without a purchase.
///
/// Decided at build time, not from the install's receipt: App Review runs
/// submitted builds with a sandbox receipt too, so a receipt check would
/// hide the subscription from the reviewer (Play's review and licence
/// testers are the same story). Only the fastlane `beta` lanes pass the
/// flag: `ios/fastlane` passes `--dart-define=TESTFLIGHT_PRO=true`,
/// `android/fastlane` passes the platform-neutral
/// `--dart-define=TESTER_PRO=true`. The `release` lanes (builds meant for
/// App Review / the App Store and Play production) never do, and check that.
/// Debug runs keep the real paywall (use `PRO_OVERRIDE` there).
class TestBuild {
  TestBuild._();

  /// Whether this binary was built by a `beta` lane for testers.
  static const unlockPro = bool.fromEnvironment('TESTFLIGHT_PRO') ||
      bool.fromEnvironment('TESTER_PRO');

  /// Android ships free, with every Pro feature unlocked and Play Billing
  /// never touched, until Pro goes on sale on Google Play (Andy, 2026-11-09:
  /// planned for January 2027 with the LLC, whose address the store page
  /// will show; Android testers need the Pro features now). Set to false
  /// when the Play products are live.
  static const androidProFree = true;

  /// Whether Pro is free on [platform] (see [androidProFree]).
  static bool proFreeOn(TargetPlatform platform) =>
      !kIsWeb && androidProFree && platform == TargetPlatform.android;
}
