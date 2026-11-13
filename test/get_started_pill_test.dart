// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/base_node.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:mesh_analyzer/ui/widgets/get_started_card.dart';
import 'package:mesh_analyzer/utils/user_errors.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(SharedPreferences prefs, AppDatabase db, List<String> taps) =>
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshLinkStateProvider.overrideWith(
            (ref) => Stream.value(RadioConnectionState.disconnected)),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: ListView(children: [
              Text('tab=${ref.watch(mainTabProvider)}'),
              GetStartedPill(onStartSession: () => taps.add('session')),
              const GetStartedCard(),
            ]),
          ),
        ),
      ),
    );

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('Live pill names the current step and opens Coverage',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final taps = <String>[];
    await tester.pumpWidget(_app(prefs, db, taps));
    await tester.pumpAndSettle();

    expect(find.text('Get started · 1 of 4: Connect one of your nodes'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('get-started-pill')));
    await tester.pump();
    expect(find.text('tab=1'), findsOneWidget);
    expect(taps, isEmpty);
    await _unmount(tester);
  });

  testWidgets('last step opens the session panel', (tester) async {
    SharedPreferences.setMockInitialValues(
        {baseNodePrefKey: 1, RadioRoles.mobileNodeKey: 2});
    final prefs = await SharedPreferences.getInstance();
    await db.createCoverageMap(name: 'Home');
    final taps = <String>[];
    await tester.pumpWidget(_app(prefs, db, taps));
    await tester.pumpAndSettle();
    expect(find.textContaining('4 of 4'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('get-started-pill')));
    expect(taps, ['session']);
    await _unmount(tester);
  });

  testWidgets('hiding the pill hides the Coverage card too (one preference)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(_app(prefs, db, []));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsOneWidget);
    // The pill's close button is the first "Hide checklist".
    await tester.tap(find.byTooltip('Hide checklist').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('get-started-pill')), findsNothing);
    expect(find.byType(Card), findsNothing);
    expect(prefs.getBool(onboardingChecklistHiddenKey), isTrue);
    await _unmount(tester);
  });

  test('userMessage maps common errors to plain English', () {
    expect(userMessage(TimeoutException('x')), contains('didn\'t answer'));
    expect(userMessage(StateError('Node not ready')),
        'Connect to your node first.');
    final other = userMessage(ArgumentError('boom'), doing: 'saving');
    expect(other, startsWith('Something went wrong while saving.'));
    expect(other, isNot(contains('boom')));
  });
}
