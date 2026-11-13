// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mesh_analyzer/services/guided/plan_models.dart';
import 'package:mesh_analyzer/ui/screens/guided/result_screen.dart';
import 'package:mesh_analyzer/ui/widgets/guided/lead_bars.dart';
import 'package:mesh_analyzer/ui/widgets/guided/result_table.dart';

import 'fakes.dart';

void main() {
  List<StepRecord> doneSteps() => [
        for (final s in sampleSteps(active: 7))
          StepRecord(
            id: s.id,
            step: s.step,
            status: StepStatus.done,
            startedAt: s.step.kind == StepKind.walk
                ? DateTime(2026, 10, 31, 12)
                : null,
            endedAt: s.step.kind == StepKind.walk
                ? DateTime(2026, 10, 31, 12, 12)
                : null,
          ),
      ];

  testWidgets('caption, verdict, table, lead bars, next step, data note, keys',
      (tester) async {
    final env = await GuidedEnv.create(
      runner: FakePlanRunner(
        plan: samplePlan(status: PlanStatus.done, currentStep: 6),
        steps: doneSteps(),
        analysis: sampleResult,
      ),
    );
    await tester.pumpWidget(env.app(ResultScreen(plan: env.runner.plan)));
    await settle(tester);

    expect(find.text('What you found out'), findsOneWidget);
    expect(find.text('ANTENNA TEST · 2 WALKS · 24 MIN'), findsOneWidget);
    expect(find.text(sampleResult.headline), findsOneWidget);
    expect(find.text(sampleResult.fairness), findsOneWidget);

    expect(find.byType(ResultTable), findsOneWidget);
    for (final h in ['SETUP', 'REACH', 'MARGIN', 'PINGS']) {
      expect(find.text(h), findsOneWidget);
    }
    expect(find.text('610 m'), findsOneWidget);
    expect(find.text('800 m'), findsOneWidget);
    expect(find.text('+2.1 dB'), findsOneWidget);
    expect(find.text('47 / 51'), findsOneWidget);
    expect(find.text('92 % answered'), findsOneWidget);

    expect(find.byType(LeadBars), findsOneWidget);
    expect(find.text('WHERE EACH ONE LED · SHARED CELLS'), findsOneWidget);
    expect(find.text('22 %'), findsOneWidget);
    expect(find.text('78 %'), findsOneWidget);

    await scrollTo(tester, find.text('NEXT STEP'));
    expect(find.text('NEXT STEP'), findsOneWidget);
    expect(find.text(sampleResult.nextStep), findsOneWidget);
    await scrollTo(tester, find.text('DATA NOTE'));
    expect(find.text('DATA NOTE'), findsOneWidget);
    expect(find.text(sampleResult.dataNotes.single), findsOneWidget);
    // AI backend not configured in tests: no card.
    expect(find.text('READING IT · AI'), findsNothing);

    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Open on map'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(env.runner.calls, contains('result:1'));
    await unmount(tester);
    await env.close();
  });

  testWidgets('a tie: every bar reads "tie", no orange row', (tester) async {
    final tie = PlanAnalysisResult(
      headline: 'Both settings held the whole route.',
      fairness: '',
      variants: sampleResult.variants,
      winner: null,
      nextStep: 'Keep Medium Fast.',
      thirdLabel: 'AIRTIME',
    );
    final env = await GuidedEnv.create(
      runner: FakePlanRunner(
          plan: samplePlan(status: PlanStatus.done), analysis: tie),
    );
    await tester.pumpWidget(env.app(ResultScreen(plan: env.runner.plan, result: tie)));
    await settle(tester);
    expect(find.text('tie'), findsNWidgets(2));
    expect(find.text('AIRTIME'), findsOneWidget);
    await scrollTo(tester, find.text('NEXT STEP'));
    expect(find.text('DATA NOTE'), findsNothing);
    await unmount(tester);
    await env.close();
  });

  testWidgets('no stored result yet: a calm line, Share off', (tester) async {
    final env = await GuidedEnv.create(
      runner: FakePlanRunner(plan: samplePlan(status: PlanStatus.done)),
    );
    await tester.pumpWidget(env.app(ResultScreen(plan: env.runner.plan)));
    await settle(tester);
    expect(find.textContaining('still being worked out'), findsOneWidget);
    final share = tester.widget<OutlinedButton>(find.ancestor(
        of: find.text('Share'), matching: find.byType(OutlinedButton)));
    expect(share.onPressed, isNull);
    await unmount(tester);
    await env.close();
  });

  test('share text carries the headline and the table', () {
    final text = resultTableText(sampleResult);
    expect(text, contains('SETUP · REACH · MARGIN · PINGS'));
    expect(text, contains('5.8 dBi fiberglass ★ · 800 m (farthest ping)'));
    expect(text, contains('Stock whip · 610 m'));
  });
}
