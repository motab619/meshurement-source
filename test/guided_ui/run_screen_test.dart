// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/guided/plan_models.dart';
import 'package:mesh_analyzer/ui/screens/guided/result_screen.dart';
import 'package:mesh_analyzer/ui/screens/guided/run_screen.dart';
import 'package:mesh_analyzer/ui/widgets/guided/go_to_compass.dart';
import 'package:mesh_analyzer/ui/widgets/guided/walk_map.dart';

import 'fakes.dart';

Future<GuidedEnv> pumpRun(WidgetTester tester, PlanProgress p,
    {Map<String, Object>? prefs,
    RadioConnectionState link = RadioConnectionState.ready}) async {
  final env = await GuidedEnv.create(prefs: prefs);
  env.runner.emit(p);
  await tester.pumpWidget(env.app(const RunScreen(planId: 1), link: link));
  await settle(tester);
  return env;
}

FilledButton keyNamed(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.ancestor(
        of: find.text(label), matching: find.byType(FilledButton)));

void main() {
  group('chrome', () {
    testWidgets('title, clock, STEP n OF N, strip, Pause and I\'m stuck',
        (tester) async {
      final env = await pumpRun(tester, progressAt(1));
      expect(find.text('Antenna test'), findsOneWidget);
      expect(find.byKey(const ValueKey('run-clock')), findsOneWidget);
      expect(find.text('STEP 2 OF 7'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text("I'm stuck"), findsOneWidget);
      await unmount(tester);
      await env.close();
    });

    testWidgets('Pause calls pause and leaves the screen', (tester) async {
      final env = await pumpRun(tester, progressAt(1));
      await tester.tap(find.text('Pause'));
      await settle(tester);
      expect(env.runner.calls, contains('pause:1'));
      await unmount(tester);
      await env.close();
    });

    testWidgets("I'm stuck: Skip calls skipStep; Stop confirms then abandons",
        (tester) async {
      final env = await pumpRun(tester, progressAt(1));
      await tester.tap(find.text("I'm stuck"));
      await tester.pumpAndSettle();
      expect(find.text('Skip this step'), findsOneWidget);
      // Not a walk: no redo.
      expect(find.text('Walk this one again'), findsNothing);
      await tester.tap(find.text('Skip this step'));
      await settle(tester);
      expect(env.runner.calls, contains('skipStep:1'));

      await tester.tap(find.text("I'm stuck"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop the test'));
      await tester.pumpAndSettle();
      expect(find.text('Stop the test?'), findsOneWidget);
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(env.runner.calls, isNot(contains('abandon:1')));

      await tester.tap(find.text("I'm stuck"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop the test'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop'));
      await settle(tester);
      expect(env.runner.calls, contains('abandon:1'));
      await unmount(tester);
      await env.close();
    });
  });

  group('preflight', () {
    testWidgets('all green: Continue completes the step', (tester) async {
      final env = await pumpRun(
          tester,
          progressAt(0, preflight: const [
            CheckRow(
                label: 'Mobile node connected',
                detail: 'MeshTest Mobile · T1000-E',
                status: CheckStatus.ok),
            CheckRow(label: 'GPS', detail: '±4 m', status: CheckStatus.ok),
          ]));
      expect(find.text('Checking your setup'), findsOneWidget);
      expect(find.text('Mobile node connected'), findsOneWidget);
      expect(find.text('MeshTest Mobile · T1000-E'), findsOneWidget);
      expect(find.textContaining('Nothing to do here'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(env.runner.calls, contains('completeStep:1'));
      await unmount(tester);
      await env.close();
    });

    testWidgets('a row with a fix shows its key; remote fix offers the walk',
        (tester) async {
      final env = await pumpRun(
          tester,
          progressAt(0, preflight: const [
            CheckRow(label: 'Base node known', status: CheckStatus.ok),
            CheckRow(
                label: 'Remote changes',
                detail: 'Not enabled on the base',
                status: CheckStatus.warn,
                fix: PreflightFix.enableRemoteAtBase),
            CheckRow(
                label: 'Base location',
                status: CheckStatus.fail,
                fix: PreflightFix.walkToBaseInstead),
          ]));
      expect(find.text('Enable at the base'), findsOneWidget);
      expect(find.textContaining('Remote changes need one Bluetooth'),
          findsOneWidget);
      expect(find.text('Walk to the base for changes instead'), findsOneWidget);
      await tester.tap(find.text('Walk to it instead'));
      await settle(tester);
      expect(env.runner.calls, contains('useBluetoothPath:1'));
      await unmount(tester);
      await env.close();
    });

    testWidgets('a plain problem: Check again rechecks', (tester) async {
      final env = await pumpRun(
          tester,
          progressAt(0, preflight: const [
            CheckRow(label: 'GPS', detail: 'getting a fix…', status: CheckStatus.busy),
          ]));
      await tester.tap(find.text('Check again'));
      await settle(tester);
      expect(env.runner.calls, contains('recheck:1'));
      await unmount(tester);
      await env.close();
    });
  });

  group('swapHardware', () {
    testWidgets('variant in the title, the saved-as card, Done completes',
        (tester) async {
      final env = await pumpRun(tester, progressAt(1));
      expect(find.textContaining('Put the'), findsWidgets);
      expect(find.text('THIS WALK WILL BE SAVED AS'), findsOneWidget);
      expect(find.textContaining('Antenna test · 1 of 2 · '), findsOneWidget);
      expect(find.text('Hardware profile "Stock whip" · mobile'), findsOneWidget);
      await tester.tap(find.text("Done, it's on"));
      await settle(tester);
      expect(env.runner.calls, contains('completeStep:1'));
      await unmount(tester);
      await env.close();
    });
  });

  group('goTo', () {
    testWidgets('compass distance and caption; I\'m here always tappable',
        (tester) async {
      final env = await pumpRun(
          tester,
          progressAt(2,
              goTo: const GoToState(
                  target: demoLatLng,
                  distanceM: 112,
                  bearingDeg: 32,
                  arrived: false)));
      expect(find.text('Go to the start point'), findsOneWidget);
      expect(find.byType(GoToCompass), findsOneWidget);
      expect(find.textContaining('112'), findsOneWidget);
      expect(find.text('TO THE START PIN'), findsOneWidget);
      expect(find.textContaining('lights up within 15 m'), findsOneWidget);
      await tester.tap(find.text("I'm here"));
      await settle(tester);
      expect(env.runner.calls, contains('completeStep:1'));
      await unmount(tester);
      await env.close();
    });

    testWidgets('no base location yet: the key sets it here', (tester) async {
      final env = await pumpRun(
          tester,
          progressWithStep(
              const PlanStep(
                  ordinal: 2,
                  kind: StepKind.goTo,
                  title: 'Stand next to the base',
                  instruction: 'x',
                  summary: 'y',
                  params: {'target': 'base'}),
              goTo: const GoToState(setsBaseLocation: true, arrived: true)));
      expect(find.text('TO THE BASE'), findsOneWidget);
      expect(find.text('Set base location here'), findsOneWidget);
      expect(find.textContaining('no base location yet'), findsOneWidget);
      await unmount(tester);
      await env.close();
    });

    test('distance formatting', () {
      expect(formatGoToDistance(null), '—');
      expect(formatGoToDistance(38.4), '38 m');
      expect(formatGoToDistance(1840), '1.8 km');
    });
  });

  group('walk', () {
    const walk = WalkState(
      sessionId: 5,
      elapsedSec: 7 * 60 + 40,
      plannedSec: 12 * 60,
      routeMatchPct: 72,
      pingsSent: 29,
      pingsAnswered: 27,
      baseHeard: true,
      lastSnr: 7.5,
      ghostRoute: [LatLng(33.6798, -116.2372), LatLng(33.6805, -116.2365)],
      track: [LatLng(33.6798, -116.2372), LatLng(33.6801, -116.2370)],
      canFinish: false,
    );

    testWidgets('band, HUD, map and legend; Done walking waits for canFinish',
        (tester) async {
      final env = await pumpRun(tester, progressAt(5, walk: walk));
      expect(find.textContaining('● Base heard'), findsOneWidget);
      expect(find.text('SNR +7.5'), findsOneWidget);
      expect(find.text('ELAPSED'), findsOneWidget);
      expect(find.text('07:40'), findsOneWidget);
      expect(find.text('12:00'), findsOneWidget);
      expect(find.text('72 %'), findsOneWidget);
      expect(find.text('27/29'), findsOneWidget);
      expect(find.byType(WalkMap), findsOneWidget);
      expect(find.text('this walk'), findsOneWidget);
      expect(find.text('walk 1 (follow it)'), findsOneWidget);
      // Drag from the HUD, not the map (the map eats the gesture).
      await tester.drag(find.byType(WalkHud), const Offset(0, -400));
      await tester.pump();
      expect(find.textContaining('Follow the dashed line'), findsOneWidget);
      expect(keyNamed(tester, 'Done walking').onPressed, isNull);
      expect(find.text('Finish anyway'), findsOneWidget);

      await tester.tap(find.text('Finish anyway'));
      await settle(tester);
      expect(env.runner.calls, contains('completeStep:1'));
      await unmount(tester);
      await env.close();
    });

    testWidgets('a drag on the map pauses following; it comes back',
        (tester) async {
      // TestFlight 2026-11-10: the walk map stopped following for good.
      final env = await pumpRun(tester, progressAt(5, walk: walk));
      final follow = find.byKey(const ValueKey('walk-map-follow'));
      expect(follow, findsNothing);
      await tester.drag(find.byType(WalkMap), const Offset(0, -120));
      await tester.pump();
      expect(follow, findsOneWidget);
      // Under the footer at the test's screen size: press it directly.
      tester.widget<IconButton>(follow).onPressed!();
      await tester.pump();
      expect(follow, findsNothing);
      // And by itself after a while.
      await tester.drag(find.byType(WalkMap), const Offset(0, -120));
      await tester.pump();
      expect(follow, findsOneWidget);
      await tester.pump(WalkMap.resumeFollowAfter + const Duration(seconds: 1));
      expect(follow, findsNothing);
      await unmount(tester);
      await env.close();
    });

    testWidgets('canFinish lights the key; first pass has no ghost legend',
        (tester) async {
      final env = await pumpRun(
          tester,
          progressAt(3,
              walk: const WalkState(
                  plannedSec: 720,
                  elapsedSec: 60,
                  baseHeard: false,
                  pingsSent: 3,
                  pingsAnswered: 1,
                  canFinish: true)));
      expect(find.textContaining('● Base not heard'), findsOneWidget);
      expect(find.text('—'), findsOneWidget, reason: 'no route match yet');
      expect(find.text('walk 1 (follow it)'), findsNothing);
      expect(find.text('Finish anyway'), findsNothing);
      expect(keyNamed(tester, 'Done walking').onPressed, isNotNull);
      await tester.tap(find.text('Done walking'));
      await settle(tester);
      expect(env.runner.calls, contains('completeStep:1'));
      await unmount(tester);
      await env.close();
    });

    testWidgets('thin walk: Keep it or walk again', (tester) async {
      final env = await pumpRun(
          tester,
          progressAt(3,
              walk: const WalkState(plannedSec: 720, elapsedSec: 90),
              note: 'thin walk: 90 s and 4 pings'));
      expect(find.text('Keep it or walk this one again?'), findsOneWidget);
      expect(find.text('thin walk: 90 s and 4 pings'), findsOneWidget);
      await tester.tap(find.text('Walk this one again'));
      await settle(tester);
      expect(env.runner.calls, contains('redoStep:1'));
      await tester.tap(find.text('Keep it'));
      await settle(tester);
      expect(env.runner.calls, contains('completeStep:1'));
      await unmount(tester);
      await env.close();
    });

    testWidgets("I'm stuck on a walk offers Walk this one again",
        (tester) async {
      final env = await pumpRun(tester, progressAt(3, walk: walk));
      await tester.tap(find.text("I'm stuck"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Walk this one again'));
      await settle(tester);
      expect(env.runner.calls, contains('redoStep:1'));
      await unmount(tester);
      await env.close();
    });
  });

  group('changeRadios', () {
    PlanStep change(int ordinal) => PlanStep(
          ordinal: ordinal,
          kind: StepKind.changeRadios,
          variant: 1,
          title: 'Switch both nodes to Long Fast',
          instruction: 'Base first, then yours.',
          summary: 'Base first, then yours · checks the base is heard',
          params: const {'preset': 'LONG_FAST'},
        );
    const rows = [
      CheckRow(label: "Saving the base's settings", status: CheckStatus.ok),
      CheckRow(label: 'Base: switching to Long Fast', status: CheckStatus.busy),
    ];

    testWidgets('ready, remote, first time: the risk sheet gates the change',
        (tester) async {
      final env = await pumpRun(
          tester,
          progressWithStep(change(2),
              plan: samplePlan(
                  status: PlanStatus.running,
                  remote: true,
                  template: PlanTemplate.rangeSettings,
                  variants: ['Medium Fast', 'Long Fast']),
              change: const ChangeState(
                  phase: ChangePhase.ready,
                  rows: rows,
                  remote: true,
                  baseDistanceM: 38,
                  targetName: 'Long Fast')));
      expect(find.textContaining('Switch both nodes to'), findsOneWidget);
      expect(find.textContaining('The app explains it before it starts'),
          findsOneWidget);
      await tester.tap(find.text('Change both nodes'));
      // A busy dot blinks forever: pumpAndSettle would never return.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Changing the base from here'), findsOneWidget);
      expect(find.textContaining('What can go wrong:'), findsOneWidget);
      expect(find.text('38 m'), findsOneWidget);
      expect(find.textContaining('What the app does to keep you safe:'),
          findsOneWidget);
      expect(keyNamed(tester, 'Change base from here').onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('risk-check')));
      await tester.pump();
      expect(keyNamed(tester, 'Change base from here').onPressed, isNotNull);
      await tester.tap(find.text('Change base from here'));
      await tester.pump();
      await settle(tester);

      expect(env.prefs.getBool(guidedRiskSeenKey), isTrue);
      expect(env.runner.calls, contains('completeStep:1'));
      await unmount(tester);
      await env.close();
    });

    testWidgets('"I\'ll walk to it instead" takes the Bluetooth path',
        (tester) async {
      final env = await pumpRun(
          tester,
          progressWithStep(change(2),
              change: const ChangeState(
                  phase: ChangePhase.ready,
                  remote: true,
                  baseDistanceM: 340,
                  targetName: 'Long Fast')));
      await tester.tap(find.text('Change both nodes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("I'll walk to it instead"));
      await settle(tester);
      expect(env.runner.calls, contains('useBluetoothPath:1'));
      expect(env.runner.calls, isNot(contains('completeStep:1')));
      expect(env.prefs.getBool(guidedRiskSeenKey), isNull);
      await unmount(tester);
      await env.close();
    });

    testWidgets('seen before: the reminder line with ⓘ, no sheet on the key',
        (tester) async {
      final env = await pumpRun(
          tester,
          progressWithStep(change(2),
              change: const ChangeState(
                  phase: ChangePhase.ready,
                  remote: true,
                  baseDistanceM: 38,
                  targetName: 'Long Fast')),
          prefs: {guidedRiskSeenKey: true});
      expect(find.text('Changing the base from here has a risk'), findsOneWidget);
      expect(find.byTooltip('What can go wrong?'), findsOneWidget);
      await tester.tap(find.text('Change both nodes'));
      await settle(tester);
      expect(find.text('Changing the base from here'), findsNothing);
      expect(env.runner.calls, contains('completeStep:1'));

      await tester.tap(find.byTooltip('What can go wrong?'));
      await tester.pumpAndSettle();
      expect(find.text('Changing the base from here'), findsOneWidget);
      await unmount(tester);
      await env.close();
    });

    testWidgets('Bluetooth path: no sheet, no reminder', (tester) async {
      final env = await pumpRun(
          tester,
          progressWithStep(change(2),
              change: const ChangeState(
                  phase: ChangePhase.ready,
                  remote: false,
                  targetName: 'Long Fast')));
      expect(find.textContaining('over Bluetooth'), findsOneWidget);
      await tester.tap(find.text('Change both nodes'));
      await settle(tester);
      expect(find.text('Changing the base from here'), findsNothing);
      expect(env.runner.calls, contains('completeStep:1'));
      await unmount(tester);
      await env.close();
    });

    testWidgets('working, done and failed phases', (tester) async {
      final env = await pumpRun(
          tester,
          progressWithStep(change(2),
              change: const ChangeState(
                  phase: ChangePhase.changingBase,
                  rows: rows,
                  remote: true,
                  targetName: 'Long Fast')));
      expect(keyNamed(tester, 'Working…').onPressed, isNull);
      expect(find.text("Saving the base's settings"), findsOneWidget);

      env.runner.emit(progressWithStep(change(2),
          change: const ChangeState(
              phase: ChangePhase.done, remote: true, targetName: 'Long Fast')));
      await settle(tester);
      expect(find.textContaining('the base answered'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(env.runner.calls, contains('completeStep:1'));

      env.runner.emit(progressWithStep(change(2),
          change: const ChangeState(
              phase: ChangePhase.failed,
              remote: true,
              targetName: 'Long Fast',
              failure: "The base didn't take the change.",
              baseChanged: false)));
      await settle(tester);
      expect(find.text("The base didn't take the change."), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.text('Walk to it instead'));
      await settle(tester);
      expect(env.runner.calls, contains('useBluetoothPath:1'));
      await tester.tap(find.text('Stop'));
      await settle(tester);
      expect(env.runner.calls, contains('pause:1'));
      await unmount(tester);
      await env.close();
    });
  });

  group('settle, analyze, done', () {
    testWidgets('settle shows the countdown', (tester) async {
      final env = await pumpRun(
          tester,
          progressWithStep(
              const PlanStep(
                  ordinal: 2,
                  kind: StepKind.settle,
                  title: 'Letting the nodes settle',
                  instruction: '',
                  summary: '20 s',
                  params: {'seconds': 20}),
              settleRemainingSec: 17));
      expect(find.text('Letting the nodes settle'), findsOneWidget);
      // By key: the run clock in the corner can also read 17:xx.
      final countdown =
          tester.widget<Text>(find.byKey(const ValueKey('settle-countdown')));
      expect(countdown.textSpan!.toPlainText(), startsWith('17'));
      await unmount(tester);
      await env.close();
    });

    testWidgets('analyze lists the walks, then a finished plan opens the result',
        (tester) async {
      final env = await pumpRun(tester, progressAt(6, analyzing: true));
      env.runner.analysis = sampleResult;
      expect(find.text('Comparing'), findsOneWidget);
      expect(find.text('Walk the route'), findsOneWidget);
      expect(find.text('Walk the same route'), findsOneWidget);
      expect(find.text('Working out the result…'), findsOneWidget);

      env.runner.emit(progressAt(6,
          plan: samplePlan(status: PlanStatus.done, currentStep: 6)));
      await settle(tester);
      expect(find.byType(ResultScreen), findsOneWidget);
      expect(find.text('What you found out'), findsOneWidget);
      await unmount(tester);
      await env.close();
    });
  });

  group('switchRadio', () {
    testWidgets('not connected: Connect key; connected: Continue',
        (tester) async {
      const step = PlanStep(
          ordinal: 4,
          kind: StepKind.switchRadio,
          variant: 1,
          title: 'Connect the other node',
          instruction: 'Pick the second node in the list.',
          summary: 'The other node',
          params: {'name': 'T1000-E'});
      var env = await pumpRun(tester, progressWithStep(step),
          link: RadioConnectionState.disconnected);
      expect(find.text('Connect the other node'), findsWidgets);
      expect(find.text('No node connected'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
      await unmount(tester);
      await env.close();

      env = await pumpRun(tester, progressWithStep(step));
      expect(find.text('Connected: fake'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(env.runner.calls, contains('completeStep:1'));
      await unmount(tester);
      await env.close();
    });
  });
}
