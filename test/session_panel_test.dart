// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/base_node.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:mesh_analyzer/ui/screens/radio_setup_screen.dart';
import 'package:mesh_analyzer/ui/widgets/session_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_mesh_radio.dart';

void main() {
  testWidgets('new session: the preset links to Radio Setup', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final radio = FakeMeshRadio(
        myNodeId: 0x1234abcd, currentPreset: MeshtasticPresets.longFast);
    await radio.connect(const RadioDescriptor(id: 'A', name: 'Pocket'));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(radio),
        activeSessionProvider.overrideWith((ref) => Stream.value(null)),
        meshLinkStateProvider
            .overrideWith((ref) => Stream.value(RadioConnectionState.ready)),
      ],
      child: const MaterialApp(home: Scaffold(body: SessionPanel())),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(find.textContaining('Range setting: Long Fast'), findsOneWidget);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.byType(RadioSetupScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  // The idle form on a fresh install; [setUp] = the first three Get started
  // steps done (a radio is connected, both roles recorded, one map).
  Future<void> pumpIdle(WidgetTester tester,
      {required bool checklistHidden,
      bool setUp = true,
      bool connected = true}) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(
        setUp ? {baseNodePrefKey: 2, RadioRoles.mobileNodeKey: 1} : {});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    if (setUp) {
      final base = await db.upsertNode(nodeId: 2);
      await db.createCoverageMap(name: 'Yard', baseNodeId: base);
    }
    final radio = FakeMeshRadio(myNodeId: 1);
    await radio.connect(const RadioDescriptor(id: 'A', name: 'Pocket'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(radio),
        activeSessionProvider.overrideWith((ref) => Stream.value(null)),
        meshLinkStateProvider.overrideWith((ref) => Stream.value(connected
            ? RadioConnectionState.ready
            : RadioConnectionState.disconnected)),
        checklistHiddenProvider.overrideWith((ref) => checklistHidden),
      ],
      child: const MaterialApp(home: Scaffold(body: SessionPanel())),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  testWidgets('first run: the start form names itself as the last step',
      (tester) async {
    await pumpIdle(tester, checklistHidden: false);
    expect(find.byKey(const ValueKey('start-last-step')), findsOneWidget);
    expect(find.textContaining('then tap Start session'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('no last-step line once the checklist is gone', (tester) async {
    await pumpIdle(tester, checklistHidden: true);
    expect(find.byKey(const ValueKey('start-last-step')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('nothing connected: the blocker first, profiles folded, '
      'guided test last', (tester) async {
    await pumpIdle(tester, checklistHidden: true, connected: false);
    final blocker = find.textContaining('Connect to your node first');
    expect(blocker, findsOneWidget);
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(top(blocker), lessThan(top(find.text('Session name (optional)'))));
    expect(top(find.text('Start session')),
        lessThan(top(find.byKey(const ValueKey('guided-test-row')))));
    expect(find.text('Hardware profiles (optional)'), findsOneWidget);
    expect(find.text('Mobile hardware profile'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('no last-step line while earlier steps are open', (tester) async {
    await pumpIdle(tester, checklistHidden: false, setUp: false);
    expect(find.byKey(const ValueKey('start-last-step')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
