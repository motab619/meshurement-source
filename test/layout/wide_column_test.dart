// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/ui/layout/window_class.dart';
import 'package:mesh_analyzer/ui/screens/coverage_map_list_screen.dart';

import 'window_sizes.dart';

/// Settings-like screens sit in a centred column on a wide window and are
/// untouched on a phone.
void main() {
  Widget column() => MaterialApp(
        home: Scaffold(
          body: WideColumn(child: ListView(children: const [Text('row')])),
        ),
      );

  testWidgets('phone: the child is the body, no wrapper', (tester) async {
    await setWindow(tester, phone);
    await tester.pumpWidget(column());
    expect(
        find.descendant(
            of: find.byType(WideColumn), matching: find.byType(Align)),
        findsNothing);
    expect(tester.getSize(find.byType(ListView)).width, phone.width);
  });

  testWidgets('iPad: centred, at most 640 wide, full height', (tester) async {
    await setWindow(tester, iPad13Landscape);
    await tester.pumpWidget(column());
    final box = tester.getRect(find.byType(ListView));
    expect(box.width, WindowClass.columnMaxWidth);
    expect(box.center.dx, iPad13Landscape.width / 2);
    expect(box.height, iPad13Landscape.height);
  });

  testWidgets('Coverage tab on an iPad: centred cards, no overflow',
      (tester) async {
    await setWindow(tester, iPad11);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.createCoverageMap(name: 'Home');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        meshLinkStateProvider.overrideWith(
            (ref) => Stream.value(RadioConnectionState.disconnected)),
      ],
      child: const MaterialApp(home: CoverageMapListScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(tester.getRect(find.text('Home')).left,
        greaterThan((iPad11.width - WindowClass.columnMaxWidth) / 2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
