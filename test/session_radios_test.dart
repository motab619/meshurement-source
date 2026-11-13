// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/base_node.dart';
import 'package:mesh_analyzer/ui/widgets/session_radios.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_mesh_radio.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required int myNum}) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({baseNodePrefKey: 0xb0b0b0b0});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.upsertNode(
        nodeId: 0xb0b0b0b0, longName: 'Hill Base', hwModel: 'HELTEC_V3');
    final radio = FakeMeshRadio(myNodeId: myNum);
    await radio.connect(const RadioDescriptor(id: 'A', name: 'Pocket'));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(radio),
      ],
      child: const MaterialApp(
          home: Scaffold(body: SessionRadios(baseNodeNum: 0xb0b0b0b0))),
    ));
    // Let the drift streams deliver the map and node.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  // Unmount before the database closes so no stream is left waiting.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // drift cancels its query streams on a zero-length timer.
    await tester.pump(Duration.zero);
  }

  testWidgets('shows the mobile and base radio names', (tester) async {
    await pump(tester, myNum: 0x1234abcd);
    expect(
        find.textContaining('Hill Base · Heltec V3 · !b0b0'), findsOneWidget);
    expect(find.textContaining('!b0b0'), findsOneWidget);
    expect(find.textContaining('!abcd'), findsOneWidget);
    expect(find.textContaining('connected to the base node'), findsNothing);
    await unmount(tester);
  });

  testWidgets('warns when the phone is connected to the base',
      (tester) async {
    await pump(tester, myNum: 0xb0b0b0b0);
    expect(find.textContaining('connected to the base node'), findsOneWidget);
    await unmount(tester);
  });
}
