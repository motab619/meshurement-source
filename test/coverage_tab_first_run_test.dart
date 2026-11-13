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
import 'package:mesh_analyzer/services/base_node.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:mesh_analyzer/ui/screens/coverage_map_list_screen.dart';
import 'package:mesh_analyzer/ui/widgets/empty_state.dart';

/// The Coverage tab on a first run (new-user walkthrough 2026-11-08):
/// "Plan a test" stays secondary until Radio Setup is done, the + hides
/// while the checklist's "New map" is the way in, and the empty state has
/// no tile that reads as a button.
Future<SharedPreferences> _prefs([Map<String, Object>? v]) async {
  SharedPreferences.setMockInitialValues(v ?? {});
  return SharedPreferences.getInstance();
}

Widget _app(SharedPreferences prefs, AppDatabase db) => ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        meshLinkStateProvider.overrideWith(
            (ref) => Stream.value(RadioConnectionState.disconnected)),
      ],
      child: const MaterialApp(home: CoverageMapListScreen()),
    );

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Finder get _planPrimary => find.widgetWithText(FilledButton, 'Plan a test');
Finder get _planOutlined =>
    find.widgetWithText(OutlinedButton, 'Plan a test');

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('fresh install: Plan a test outlined, no +, plain empty state',
      (tester) async {
    await tester.pumpWidget(_app(await _prefs(), db));
    await tester.pumpAndSettle();

    expect(_planOutlined, findsOneWidget);
    expect(_planPrimary, findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    // Below the checklist card: scroll down to it.
    await tester.scrollUntilVisible(find.byType(EmptyState), 300);
    expect(find.text('No maps yet'), findsOneWidget);
    expect(find.textContaining('a place with a base node'), findsOneWidget);
    final empty = find.byType(EmptyState);
    expect(
      find.descendant(
        of: empty,
        matching: find.byWidgetPredicate((w) =>
            w is Container && w.decoration is BoxDecoration),
      ),
      findsNothing,
    );
    expect(
        find.descendant(of: empty, matching: find.byType(DecoratedBox)),
        findsNothing);
    await _unmount(tester);
  });

  testWidgets('both roles set: Plan a test is the filled key', (tester) async {
    final prefs = await _prefs({
      baseNodePrefKey: 1,
      RadioRoles.mobileNodeKey: 2,
    });
    await tester.pumpWidget(_app(prefs, db));
    await tester.pumpAndSettle();
    expect(_planPrimary, findsOneWidget);
    expect(_planOutlined, findsNothing);
    // Still no map: the card's "New map" is the way in.
    expect(find.byType(FloatingActionButton), findsNothing);
    await _unmount(tester);
  });

  testWidgets('only the mobile set: Plan a test stays outlined',
      (tester) async {
    final prefs = await _prefs({RadioRoles.mobileNodeKey: 2});
    await tester.pumpWidget(_app(prefs, db));
    await tester.pumpAndSettle();
    expect(_planOutlined, findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('checklist hidden: filled Plan a test and the +',
      (tester) async {
    final prefs = await _prefs({onboardingChecklistHiddenKey: true});
    await tester.pumpWidget(_app(prefs, db));
    await tester.pumpAndSettle();
    expect(_planPrimary, findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a map exists: the + shows with the card', (tester) async {
    await db.createCoverageMap(name: 'Home');
    await tester.pumpWidget(_app(await _prefs(), db));
    await tester.pumpAndSettle();
    expect(find.text('GET STARTED · 1/4'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await _unmount(tester);
  });
}
