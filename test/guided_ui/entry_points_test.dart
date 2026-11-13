// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/guided/plan_models.dart';
import 'package:mesh_analyzer/ui/screens/coverage_map_list_screen.dart';
import 'package:mesh_analyzer/ui/screens/guided/ask_screen.dart';
import 'package:mesh_analyzer/ui/screens/guided/result_screen.dart';
import 'package:mesh_analyzer/ui/screens/guided/run_screen.dart';
import 'package:mesh_analyzer/ui/widgets/guided/resume_banner.dart';
import 'package:mesh_analyzer/ui/widgets/guided/tests_section.dart';

import 'fakes.dart';

void main() {
  testWidgets('Coverage tab: "Plan a test" under the checklist opens Ask',
      (tester) async {
    final env =
        await GuidedEnv.create(prefs: {onboardingChecklistHiddenKey: true});
    await tester.pumpWidget(env.app(const CoverageMapListScreen()));
    await settle(tester);
    expect(find.byType(PlanATestKey), findsOneWidget);
    await tester.tap(find.text('Plan a test'));
    await settle(tester);
    expect(find.byType(AskScreen), findsOneWidget);
    await unmount(tester);
    await env.close();
  });

  testWidgets(
      'Tests section: rows per plan; paused shows Continue and '
      'resumes; done opens the result', (tester) async {
    final env = await GuidedEnv.create(
      runner: FakePlanRunner(
        plan: samplePlan(status: PlanStatus.paused, currentStep: 2),
      ),
    );
    env.runner.emit(progressAt(2, goTo: const GoToState()));
    await tester.pumpWidget(env.app(const Scaffold(
      body: SingleChildScrollView(child: GuidedTestsSection(mapId: 1)),
    )));
    await settle(tester);
    expect(find.text('Tests'), findsOneWidget);
    expect(find.text('Antenna test'), findsOneWidget);
    expect(find.text('Paused at step 3'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(env.runner.calls, contains('start:1'));
    expect(find.byType(RunScreen), findsOneWidget);
    await unmount(tester);
    await env.close();

    final done = await GuidedEnv.create(
      runner: FakePlanRunner(
          plan: samplePlan(status: PlanStatus.done), analysis: sampleResult),
    );
    Set<int>? shown;
    await tester.pumpWidget(done.app(Scaffold(
      body: SingleChildScrollView(
          child:
              GuidedTestsSection(mapId: 1, onShowOnly: (ids) => shown = ids)),
    )));
    await settle(tester);
    expect(find.text('Continue'), findsNothing);
    // A finished test has its own map and report buttons (TestFlight
    // 2026-11-10).
    expect(find.byTooltip('Field report'), findsOneWidget);
    await tester.tap(find.byTooltip('Show only this test on the map'));
    await settle(tester);
    expect(shown, isNotNull);
    await tester.tap(find.text('Antenna test'));
    await settle(tester);
    expect(find.byType(ResultScreen), findsOneWidget);
    await unmount(tester);
    await done.close();
  });

  testWidgets('Tests section draws nothing for a map without plans',
      (tester) async {
    final env = await GuidedEnv.create();
    await tester.pumpWidget(env.app(const Scaffold(
      body: GuidedTestsSection(mapId: 99),
    )));
    await settle(tester);
    expect(find.text('Tests'), findsNothing);
    await unmount(tester);
    await env.close();
  });

  testWidgets('resume banner: shown for a paused plan, hidden otherwise',
      (tester) async {
    final env = await GuidedEnv.create(
      runner: FakePlanRunner(
        activePlan: samplePlan(status: PlanStatus.paused, currentStep: 2),
      ),
    );
    await tester
        .pumpWidget(env.app(const Scaffold(body: GuidedResumeBanner())));
    await settle(tester);
    expect(find.text('Guided test paused at step 3'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    await unmount(tester);
    await env.close();

    final idle = await GuidedEnv.create();
    await tester
        .pumpWidget(idle.app(const Scaffold(body: GuidedResumeBanner())));
    await settle(tester);
    expect(find.textContaining('Guided test'), findsNothing);
    await unmount(tester);
    await idle.close();
  });

  testWidgets('engine not wired: the banner and section read as empty',
      (tester) async {
    // No planRunnerProvider override: the placeholder throws.
    {
      final env = await GuidedEnv.create();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(env.db),
          sharedPreferencesProvider.overrideWithValue(env.prefs),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Column(children: [
              GuidedResumeBanner(),
              GuidedTestsSection(mapId: 1),
            ]),
          ),
        ),
      ));
      await settle(tester);
      expect(find.textContaining('Guided test'), findsNothing);
      expect(find.text('Tests'), findsNothing);
      await unmount(tester);
      await env.close();
    }
  });

  test('status lines', () {
    expect(planStatusLine(samplePlan()), 'Planned · 2 setups');
    expect(
        planStatusLine(samplePlan(status: PlanStatus.running, currentStep: 4)),
        'Under way · step 5');
    expect(
        planStatusLine(samplePlan(
            status: PlanStatus.done,
            template: PlanTemplate.reach,
            variants: ['Current setup'])),
        contains('· reach'));
  });
}
