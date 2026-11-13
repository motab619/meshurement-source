// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mesh_analyzer/services/guided/plan_models.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:mesh_analyzer/ui/screens/guided/ask_screen.dart';
import 'package:mesh_analyzer/ui/screens/guided/plan_screen.dart';

import 'fakes.dart';

void main() {
  group('chip helpers', () {
    test('every chip sentence maps back to its template', () {
      for (final t in PlanTemplate.values) {
        expect(templateForSentence(chipSentence(t)), t);
        expect(templateForSentence(t.chip), t);
      }
      expect(templateForSentence('which antenna is best up the hill'), isNull);
    });

    test('default variants: ladder neighbour for range settings', () {
      const ctx = ParserContext(presetNames: {
        'LONG_FAST': 'Long Fast',
        'MEDIUM_FAST': 'Medium Fast',
        'SHORT_FAST': 'Short Fast',
      });
      expect(
          defaultVariants(PlanTemplate.rangeSettings, ctx,
              currentPresetId: 'MEDIUM_FAST'),
          ['MEDIUM_FAST', 'SHORT_FAST']);
      // Last on the ladder: the one before it.
      expect(
          defaultVariants(PlanTemplate.rangeSettings, ctx,
              currentPresetId: 'SHORT_FAST'),
          ['SHORT_FAST', 'MEDIUM_FAST']);
      // Unknown preset: the first two.
      expect(defaultVariants(PlanTemplate.rangeSettings, ctx),
          ['LONG_FAST', 'MEDIUM_FAST']);
      expect(defaultVariants(PlanTemplate.reach, ctx), ['Current setup']);
      expect(defaultVariants(PlanTemplate.txPower, ctx, currentTxPower: 27),
          ['27', '17']);
    });
  });

  testWidgets('renders caption, title, five chips and the privacy line',
      (tester) async {
    final env = await GuidedEnv.create();
    await tester.pumpWidget(env.app(const AskScreen()));
    await tester.pumpAndSettle();
    expect(find.text('WHAT DO YOU WANT TO FIND OUT?'), findsOneWidget);
    expect(find.text('Say it in your own words, or pick one.'), findsOneWidget);
    for (final t in PlanTemplate.values) {
      expect(find.textContaining(t.chip), findsOneWidget);
    }
    // AI help off (the default): typed text stays on the phone.
    expect(find.textContaining('read on this phone only'), findsOneWidget);
    expect(find.textContaining('is sent to an AI helper'), findsNothing);
    expect(find.text('Next'), findsOneWidget);
    await unmount(tester);
    await env.close();
  });

  testWidgets(
      'chip fills the field; Next builds the intent locally and '
      'opens the plan', (tester) async {
    final env = await GuidedEnv.create();
    await tester.pumpWidget(env.app(const AskScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Compare antennas'));
    await tester.pump();
    final field =
        tester.widget<TextField>(find.byKey(const ValueKey('ask-field')));
    expect(field.controller!.text, 'I want to compare antennas');

    await tester.tap(find.text('Next'));
    await settle(tester);

    expect(env.parser.asked, isEmpty, reason: 'a chip never calls the parser');
    expect(env.runner.created, hasLength(1));
    final intent = env.runner.created.single;
    expect(intent.template, PlanTemplate.antennas);
    expect(intent.variants, ['Antenna A', 'Antenna B']);
    expect(intent.question, 'I want to compare antennas');
    expect(env.runner.calls, contains('createPlan:1'));
    expect(find.byType(PlanScreen), findsOneWidget);
    await unmount(tester);
    await env.close();
  });

  testWidgets('range settings chip: current preset plus the next ladder step',
      (tester) async {
    final env = await GuidedEnv.create();
    await tester.pumpWidget(env.app(const AskScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Compare range settings'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await settle(tester);
    // US ladder: … MEDIUM_SLOW, MEDIUM_FAST, MEDIUM_TURBO, SHORT_SLOW …
    expect(env.runner.created.single.variants, ['MEDIUM_FAST', 'MEDIUM_TURBO']);
    await unmount(tester);
    await env.close();
  });

  testWidgets('typed text goes to the parser with the setup context',
      (tester) async {
    final env = await GuidedEnv.create();
    await tester.pumpWidget(env.app(const AskScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ask-field')),
        'test my two antennas up the hill');
    await tester.tap(find.text('Next'));
    await settle(tester);
    expect(env.parser.asked, ['test my two antennas up the hill']);
    expect(env.parser.lastContext!.protocol, 'meshtastic');
    expect(env.parser.lastContext!.presetNames, contains('MEDIUM_FAST'));
    expect(env.runner.created.single.variants, ['Whip', 'Fiber']);
    expect(
        env.runner.created.single.question, 'test my two antennas up the hill');
    await unmount(tester);
    await env.close();
  });

  testWidgets(
      'low confidence: clarification line and the chip pre-selected, '
      'no plan yet; second Next goes on', (tester) async {
    final env = await GuidedEnv.create(
      parser: FakePlanIntentParser(
        guess: const PlanIntentGuess(
          intent: PlanIntent(
              template: PlanTemplate.txPower, variants: ['20', '27']),
          confidence: 0.3,
          clarification: 'Which two power levels? Tap to name them.',
        ),
      ),
    );
    await tester.pumpWidget(env.app(const AskScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('ask-field')), 'power stuff');
    await tester.tap(find.text('Next'));
    await settle(tester);

    expect(find.byKey(const ValueKey('ask-clarification')), findsOneWidget);
    expect(
        find.text('Which two power levels? Tap to name them.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(env.runner.created, isEmpty);

    await tester.tap(find.text('Next'));
    await settle(tester);
    expect(env.parser.asked, hasLength(1), reason: 'not parsed twice');
    expect(env.runner.created.single.template, PlanTemplate.txPower);
    expect(env.runner.created.single.variants, ['20', '27']);
    await unmount(tester);
    await env.close();
  });

  testWidgets('empty field and no chip: a line, nothing created',
      (tester) async {
    final env = await GuidedEnv.create();
    await tester.pumpWidget(env.app(const AskScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await settle(tester);
    expect(find.byKey(const ValueKey('ask-clarification')), findsOneWidget);
    expect(env.runner.created, isEmpty);
    await unmount(tester);
    await env.close();
  });

  testWidgets('prefill from Compare keeps the two rig names', (tester) async {
    final env = await GuidedEnv.create();
    await tester.pumpWidget(env.app(const AskScreen(
      mapId: 1,
      prefill: PlanIntent(
          template: PlanTemplate.antennas, variants: ['Whip', 'Fiberglass']),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await settle(tester);
    expect(env.runner.created.single.variants, ['Whip', 'Fiberglass']);
    await unmount(tester);
    await env.close();
  });

  testWidgets('several maps: a picker sheet; none: a "Guided tests" map',
      (tester) async {
    final env = await GuidedEnv.create(maps: 2);
    await tester.pumpWidget(env.app(const AskScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('How far does it reach?'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await settle(tester);
    expect(find.text('Which map is this test for?'), findsOneWidget);
    await tester.tap(find.text('Map 2'));
    await settle(tester);
    expect(env.runner.calls, contains('createPlan:2'));
    expect(env.runner.created.single.variants, ['Current setup']);
    await unmount(tester);
    await env.close();

    final none = await GuidedEnv.create(maps: 0);
    await tester.pumpWidget(none.app(const AskScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Compare two nodes'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await settle(tester);
    final maps = await none.db.getAllCoverageMaps();
    expect(maps.map((m) => m.name), ['Guided tests']);
    expect(none.runner.calls, contains('createPlan:${maps.single.id}'));
    await unmount(tester);
    await none.close();
  });

  testWidgets('a PlanError from createPlan shows as the clarification line',
      (tester) async {
    final env = await GuidedEnv.create();
    env.runner.createError =
        const PlanError('Name at least two things to compare.');
    await tester.pumpWidget(env.app(const AskScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Compare antennas'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await settle(tester);
    expect(find.text('Name at least two things to compare.'), findsOneWidget);
    expect(find.byType(PlanScreen), findsNothing);
    await unmount(tester);
    await env.close();
  });

  testWidgets('three setups without Pro open the paywall first',
      (tester) async {
    final env = await GuidedEnv.create(
      parser: FakePlanIntentParser(
        guess: const PlanIntentGuess(
          intent: PlanIntent(
              template: PlanTemplate.antennas, variants: ['A', 'B', 'C']),
          confidence: 0.9,
        ),
      ),
    );
    await tester.pumpWidget(env.app(const AskScreen(), pro: false));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('ask-field')), 'three antennas');
    await tester.tap(find.text('Next'));
    await settle(tester);
    expect(find.text('Meshurement Pro'), findsWidgets);
    expect(env.runner.created, isEmpty);
    await unmount(tester);
    await env.close();
  });

  testWidgets('with AI help on, the privacy line says typed text is sent',
      (tester) async {
    final env =
        await GuidedEnv.create(prefs: {AppConstants.prefAiConsent: true});
    await tester.pumpWidget(env.app(const AskScreen()));
    await settle(tester);
    expect(find.textContaining('When AI help is on, what you type is sent'),
        findsOneWidget);
    expect(
        find.textContaining('No positions, node ids or keys'), findsOneWidget);
    await unmount(tester);
    await env.close();
  });
}
