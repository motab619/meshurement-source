// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/demo/demo_mode.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/ui/screens/about_screen.dart';
import 'package:mesh_analyzer/utils/constants.dart';

void main() {
  testWidgets('About screen shows version, trademark notice and source link',
      (WidgetTester tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Meshurement',
      packageName: 'com.example.meshAnalyzer',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
    );

    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: AboutScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('About'), findsOneWidget);
    expect(find.textContaining('Version 1.2.3 (45)'), findsOneWidget);
    expect(find.text(trademarkNotice), findsOneWidget);
    if (AppConstants.aiAnalysisUrl != null) {
      expect(find.text(aiDisclaimer), findsOneWidget);
    }
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    expect(find.textContaining('api.opentopodata.org'), findsOneWidget);
    expect(find.text('Source code'), findsOneWidget);
    expect(find.textContaining('github.com/motab619/meshurement-source'),
        findsOneWidget);
  });

  testWidgets('long-press on the app name turns the demo on for next launch',
      (WidgetTester tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Meshurement',
      packageName: 'com.example.meshAnalyzer',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: AboutScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('wordmark')));
    await tester.pumpAndSettle();
    expect(find.text('Open the demo?'), findsOneWidget);
    await tester.tap(find.text('Open demo'));
    await tester.pumpAndSettle();
    expect(prefs.getBool(DemoMode.nextLaunchPref), isTrue);

    await tester.longPress(find.byKey(const ValueKey('wordmark')));
    await tester.pumpAndSettle();
    expect(find.text('Leave the demo?'), findsOneWidget);
    await tester.tap(find.text('Leave demo'));
    await tester.pumpAndSettle();
    expect(prefs.getBool(DemoMode.nextLaunchPref), isFalse);
  });
}
