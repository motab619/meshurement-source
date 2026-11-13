// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Window sizes (logical pixels) for adaptive-layout tests. The Duo sizes
/// are developers' estimates (outer 1398 × 2034 px, inner 2007 × 2853 px,
/// assumed 3x), not Apple's numbers.
const phone = Size(402, 874); // iPhone 17/18 Pro
const phoneLandscape = Size(874, 402);
const phoneMaxLandscape = Size(956, 440); // Pro Max sideways
const duoOuter = Size(466, 678);
const duoInner = Size(669, 951);
const duoInnerLandscape = Size(951, 669);
const iPadMini = Size(744, 1133);
const iPad11 = Size(834, 1210);
const iPadPro105 = Size(834, 1112); // Andy's test iPad, held upright
const iPad13Landscape = Size(1376, 1032);

/// Sets the test window to [size] at 3x and resets it after the test.
Future<void> setWindow(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  addTearDown(tester.view.reset);
}
