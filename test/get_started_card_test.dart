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
import 'package:mesh_analyzer/services/last_radio.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:mesh_analyzer/ui/widgets/get_started_card.dart';

Future<SharedPreferences> _prefs([Map<String, Object>? v]) async {
  SharedPreferences.setMockInitialValues(v ?? {});
  return SharedPreferences.getInstance();
}

/// The card on a tab probe that shows the selected main tab, with a
/// button that moves off the Live tab.
Widget _app(SharedPreferences prefs, AppDatabase db,
        {RadioConnectionState link = RadioConnectionState.disconnected}) =>
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        meshLinkStateProvider.overrideWith((ref) => Stream.value(link)),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: ListView(children: [
              Text('tab=${ref.watch(mainTabProvider)}'),
              Text('open=${ref.watch(openStartFormProvider)}'),
              TextButton(
                onPressed: () => ref.read(mainTabProvider.notifier).state = 1,
                child: const Text('coverage'),
              ),
              const GetStartedCard(),
            ]),
          ),
        ),
      ),
    );

/// Unmount so the providers (and drift's query streams) dispose before the
/// test ends; the stream close schedules a timer that must run first.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  // pump() without a duration doesn't fire zero-length timers; elapse.
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('getStartedSteps', () {
    test('fresh install: nothing done, connect first', () async {
      final roles = RadioRoles(await _prefs());
      final steps = getStartedSteps(
        link: RadioConnectionState.disconnected,
        roles: roles,
        lastRadio: null,
        mapCount: 0,
        sessionCount: 0,
      );
      expect(steps.map((s) => s.done), everyElement(isFalse));
      expect(steps.first.action, 'Connect');
    });

    test('a past connection counts, Radio Setup needs both roles', () async {
      final roles = RadioRoles(await _prefs({RadioRoles.mobileNodeKey: 7}));
      final steps = getStartedSteps(
        link: RadioConnectionState.disconnected,
        roles: roles,
        lastRadio: const RadioDescriptor(id: 'x', name: 'Heltec'),
        mapCount: 0,
        sessionCount: 0,
      );
      expect(steps[0].done, isTrue);
      expect(steps[0].detail, 'Heltec');
      expect(steps[1].done, isFalse);
      expect(steps[1].detail, contains('base still needs doing'));
    });

    test('both roles, a map and a session: all done', () async {
      final roles = RadioRoles(await _prefs({
        baseNodePrefKey: 0x1234abcd,
        RadioRoles.mobileNodeKey: 0x12345678,
      }));
      final steps = getStartedSteps(
        link: RadioConnectionState.ready,
        roles: roles,
        lastRadio: const RadioDescriptor(id: 'x', name: 'Heltec'),
        mapCount: 1,
        sessionCount: 2,
      );
      expect(steps.map((s) => s.done), everyElement(isTrue));
      expect(steps[0].detail, 'Connected: Heltec');
      expect(steps[1].detail, 'Base: !abcd · Mobile: !5678');
      expect(steps[2].detail, '1 map');
      expect(steps[3].detail, '2 sessions');
    });
  });

  testWidgets('fresh install shows step 1 with its button', (tester) async {
    final prefs = await _prefs();
    await tester.pumpWidget(_app(prefs, db));
    await tester.pumpAndSettle();
    expect(find.text('GET STARTED · 1/4'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    // Steps ahead have their button too (outlined), so they can be done
    // out of order.
    expect(find.text('Open Node Setup'), findsOneWidget);
    expect(find.text('New map'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
    expect(
        find.widgetWithText(OutlinedButton, 'New map'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('steps tick off from real state; Go to Live switches tab',
      (tester) async {
    final prefs = await _prefs({
      LastRadio.prefKey: '{"id":"a","name":"Heltec","protocol":"meshtastic"}',
      baseNodePrefKey: 1,
      RadioRoles.mobileNodeKey: 2,
    });
    await db.createCoverageMap(name: 'Home');
    await tester.pumpWidget(_app(prefs, db));
    await tester.pumpAndSettle();

    expect(find.text('GET STARTED · 4/4'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(3));
    expect(find.text('tab=0'), findsOneWidget);
    // Done steps have no button.
    expect(find.text('New map'), findsNothing);

    await tester.tap(find.text('coverage'));
    await tester.pump();
    expect(find.text('tab=1'), findsOneWidget);
    expect(find.text('open=false'), findsOneWidget);
    await tester.tap(find.text('Go to Live'));
    await tester.pump();
    expect(find.text('tab=0'), findsOneWidget);
    // …and the Live tab is asked to open the start form.
    expect(find.text('open=true'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a session completes the card; Done hides it for good',
      (tester) async {
    final prefs = await _prefs({baseNodePrefKey: 1, RadioRoles.mobileNodeKey: 2});
    final mapId = await db.createCoverageMap(name: 'Home');
    await db.createSession(coverageMapId: mapId);
    await tester.pumpWidget(_app(prefs, db));
    await tester.pumpAndSettle();

    expect(find.text('ALL SET'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
    expect(prefs.getBool(onboardingChecklistHiddenKey), isTrue);
    await _unmount(tester);
  });

  testWidgets('the close button hides the card', (tester) async {
    final prefs = await _prefs();
    await tester.pumpWidget(_app(prefs, db));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Hide checklist'));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
    expect(prefs.getBool(onboardingChecklistHiddenKey), isTrue);
    await _unmount(tester);
  });

  testWidgets('hidden flag: nothing rendered', (tester) async {
    final prefs = await _prefs({onboardingChecklistHiddenKey: true});
    await tester.pumpWidget(_app(prefs, db));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
    await _unmount(tester);
  });
}
