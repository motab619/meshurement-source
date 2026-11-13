// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mesh_analyzer/ui/widgets/splash_overlay.dart';

void main() {
  testWidgets('the splash covers the app briefly, then is gone', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: SplashOverlay(child: Text('app'))));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('app'), findsOneWidget); // built underneath
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });
}
