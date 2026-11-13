// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mesh_analyzer/services/guided/plan_models.dart';
import 'package:mesh_analyzer/ui/screens/guided/plan_copy.dart';
import 'package:mesh_analyzer/ui/screens/guided/plan_screen.dart';
import 'package:mesh_analyzer/ui/screens/guided/run_screen.dart';
import 'package:mesh_analyzer/ui/widgets/guided/step_track.dart';

import 'fakes.dart';

/// Taps the first tappable span whose text is [text] inside a Text.rich.
void tapSpan(WidgetTester tester, String text) {
  for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
    TapGestureRecognizer? found;
    w.text.visitChildren((span) {
      if (span is TextSpan &&
          span.text == text &&
          span.recognizer is TapGestureRecognizer) {
        found = span.recognizer as TapGestureRecognizer;
        return false;
      }
      return true;
    });
    if (found != null) {
      found!.onTap!();
      return;
    }
  }
  fail('no tappable span "$text"');
}

void main() {
  test('time estimate: walks at their minutes, hands-on steps at 3',
      () {
    final steps = sampleSteps();
    final intent = samplePlan().intent;
    // preflight 1 + swap 3 + goTo 3 + walk 12 + swap 3 + walk 12 + analyze 1
    expect(PlanCopy.totalMinutes(steps, intent), 35);
    expect(PlanCopy.walkCount(steps), 2);
    expect(PlanCopy.secondPassMinutes(intent), 24);
  });

  testWidgets('renders readouts, why, seven stops, who-does lines, the switch '
      'and the note', (tester) async {
    final env = await GuidedEnv.create();
    await tester.pumpWidget(env.app(PlanScreen(plan: env.runner.plan)));
    await settle(tester);

    expect(find.text('Antenna test'), findsOneWidget);
    expect(find.text('MINUTES'), findsOneWidget);
    expect(find.text('35'), findsOneWidget);
    expect(find.text('STEPS'), findsOneWidget);
    expect(find.text('7'), findsWidgets);
    expect(find.text('WALKS'), findsOneWidget);
    expect(find.textContaining('Two walks on the same route'), findsOneWidget);
    expect(find.byType(StepTrack), findsOneWidget);
    for (var i = 1; i <= 7; i++) {
      expect(find.text('$i'), findsWidgets);
    }
    expect(find.text('● YOU'), findsWidgets);
    expect(find.text('● AUTOMATIC'), findsWidgets);
    expect(find.text('● WALK · RECORDED'), findsWidgets);
    await scrollTo(tester, find.text('Second pass, other order'));
    expect(find.text('Second pass, other order'), findsOneWidget);
    expect(
        find.text('+24 min · cancels out changes over time (battery, people, '
            'weather)'),
        findsOneWidget);
    await scrollTo(tester, find.textContaining('Nothing on the nodes changes'));
    expect(find.textContaining('Nothing on the nodes changes'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    await unmount(tester);
    await env.close();
  });

  testWidgets('the switch calls updateDraft with repeat on', (tester) async {
    final env = await GuidedEnv.create();
    await tester.pumpWidget(env.app(PlanScreen(plan: env.runner.plan)));
    await settle(tester);
    await scrollTo(tester, find.byKey(const ValueKey('repeat-switch')));
    // Fully into view (the Add a setup row moved it to the list's edge).
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('repeat-switch')));
    await settle(tester);
    expect(env.runner.calls, contains('updateDraft:1'));
    expect(env.runner.drafts.single.repeat, isTrue);
    expect(
        tester.widget<Switch>(find.byKey(const ValueKey('repeat-switch'))).value,
        isTrue);
    await unmount(tester);
    await env.close();
  });

  testWidgets('tapping a variant name renames it', (tester) async {
    final env = await GuidedEnv.create();
    await tester.pumpWidget(env.app(PlanScreen(plan: env.runner.plan)));
    await settle(tester);
    tapSpan(tester, 'Stock whip');
    await tester.pumpAndSettle();
    expect(find.text('Name this setup'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Rubber duck');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(env.runner.calls, contains('renameVariant:1:0:Rubber duck'));
    await unmount(tester);
    await env.close();
  });

  testWidgets('a duplicate name is refused with a line', (tester) async {
    final env = await GuidedEnv.create();
    await tester.pumpWidget(env.app(PlanScreen(plan: env.runner.plan)));
    await settle(tester);
    tapSpan(tester, 'Stock whip');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '5.8 dBi fiberglass');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Two setups have the same name.'), findsOneWidget);
    expect(env.runner.calls.where((c) => c.startsWith('renameVariant')), isEmpty);
    await unmount(tester);
    await env.close();
  });

  testWidgets('Start calls start and opens the Run screen', (tester) async {
    final env = await GuidedEnv.create();
    env.runner.emit(progressAt(0, preflight: const [
      CheckRow(label: 'GPS', status: CheckStatus.ok),
    ]));
    await tester.pumpWidget(env.app(PlanScreen(plan: env.runner.plan)));
    await settle(tester);
    await tester.tap(find.text('Start'));
    await settle(tester);
    expect(env.runner.calls, contains('start:1'));
    expect(find.byType(RunScreen), findsOneWidget);
    expect(find.text('STEP 1 OF 7'), findsOneWidget);
    await unmount(tester);
    await env.close();
  });

  testWidgets('reach plan has no second-pass switch', (tester) async {
    final env = await GuidedEnv.create(
      runner: FakePlanRunner(
        plan: samplePlan(
            template: PlanTemplate.reach, variants: ['Current setup']),
      ),
    );
    await tester.pumpWidget(env.app(PlanScreen(plan: env.runner.plan)));
    await settle(tester);
    expect(find.text('Second pass, other order'), findsNothing);
    expect(find.textContaining('head away from the base'), findsOneWidget);
    await unmount(tester);
    await env.close();
  });

  testWidgets('Add a setup adds a third antenna (Pro)', (tester) async {
    final env = await GuidedEnv.create();
    await tester.pumpWidget(env.app(PlanScreen(plan: env.runner.plan)));
    await settle(tester);
    await scrollTo(tester, find.byKey(const ValueKey('add-setup')));
    // Built is not visible: bring it out from under the footer.
    await tester.ensureVisible(find.byKey(const ValueKey('add-setup')));
    await tester.pumpAndSettle();
    expect(find.text('Add a setup'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-setup')));
    await tester.pumpAndSettle();
    expect(find.text('Add a setup'), findsWidgets); // dialog title too
    await tester.enterText(find.byType(TextField), 'Roof yagi');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(env.runner.calls, contains('updateDraft:1'));
    expect(env.runner.drafts.last.variants.length, 3);
    expect(env.runner.drafts.last.variants.last, 'Roof yagi');
    await unmount(tester);
    await env.close();
  });

  testWidgets('without Pro the third setup is locked behind the paywall',
      (tester) async {
    final env = await GuidedEnv.create();
    await tester.pumpWidget(
        env.app(PlanScreen(plan: env.runner.plan), pro: false));
    await settle(tester);
    await scrollTo(tester, find.byKey(const ValueKey('add-setup')));
    expect(find.text('Add a setup (Pro)'), findsOneWidget);
    await unmount(tester);
    await env.close();
  });

  testWidgets('no Add a setup on a reach test or with four setups',
      (tester) async {
    final env = await GuidedEnv.create(
      runner: FakePlanRunner(
        plan: samplePlan(variants: ['A', 'B', 'C', 'D']),
      ),
    );
    await tester.pumpWidget(env.app(PlanScreen(plan: env.runner.plan)));
    await settle(tester);
    expect(find.byKey(const ValueKey('add-setup')), findsNothing);
    await unmount(tester);
    await env.close();
  });
}
