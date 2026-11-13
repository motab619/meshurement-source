// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:latlong2/latlong.dart';

import '../services/guided/plan_models.dart';
import 'demo_site.dart';

/// Scripted [PlanRunnerApi] for `-demoScreen guided` (screenshots): the
/// antenna test from the design mock, sitting on its second walk with the
/// mock's numbers. Nothing is sent, nothing is stored; every key just
/// re-emits the same state.
class DemoPlanRunner implements PlanRunnerApi {
  static const planId = 1;
  static const variants = ['Stock whip', '5.8 dBi fiberglass'];

  static final _created = DateTime(2026, 10, 31, 11, 40);

  static const _intent = PlanIntent(
    template: PlanTemplate.antennas,
    variants: variants,
    question: 'which antenna gets me further up the hill',
  );

  static final plan = PlanRecord(
    id: planId,
    coverageMapId: 1,
    title: 'Antenna test',
    intent: _intent,
    status: PlanStatus.running,
    currentStep: 5,
    remoteChanges: false,
    createdAt: _created,
  );

  static const _steps = <PlanStep>[
    PlanStep(
        ordinal: 0,
        kind: StepKind.preflight,
        title: 'Checking your setup',
        instruction: 'Nodes, channel, base location, GPS.',
        summary: 'Nodes, channel, base location, GPS'),
    PlanStep(
        ordinal: 1,
        kind: StepKind.swapHardware,
        variant: 0,
        title: 'Put the Stock whip on',
        instruction: 'On the mobile node (the one in your hand). Screw it '
            'on hand-tight, then stand it upright.',
        summary: 'On the mobile node, hand-tight, upright',
        params: {'side': 'mobile', 'name': 'Stock whip'}),
    PlanStep(
        ordinal: 2,
        kind: StepKind.goTo,
        title: 'Go to the start point',
        instruction: 'Same start point every time makes the walks comparable.',
        summary: 'Next to the base this first time',
        params: {'target': 'base'}),
    PlanStep(
        ordinal: 3,
        kind: StepKind.walk,
        variant: 0,
        title: 'Walk the route',
        instruction: 'Walk where you want coverage checked. The app '
            'remembers this route for the next walk.',
        summary: '≈12 min · the app records',
        params: {'minutes': 12, 'pass': 1}),
    PlanStep(
        ordinal: 4,
        kind: StepKind.swapHardware,
        variant: 1,
        title: 'Put the 5.8 dBi fiberglass on',
        instruction: 'Same node, same spot. Screw it on hand-tight, then '
            'stand it upright.',
        summary: 'Same node, same spot',
        params: {'side': 'mobile', 'name': '5.8 dBi fiberglass'}),
    PlanStep(
        ordinal: 5,
        kind: StepKind.walk,
        variant: 1,
        title: 'Walk the same route',
        instruction: 'Follow the dashed line. "Done walking" lights at 80 % '
            'route match.',
        summary: 'Follow the ghost line · route match shown live',
        params: {'minutes': 12, 'pass': 1}),
    PlanStep(
        ordinal: 6,
        kind: StepKind.analyze,
        title: 'Compare',
        instruction: 'Cell by cell on the shared route, farthest reach, '
            'pings answered.',
        summary: 'Cell by cell, farthest reach, pings answered'),
  ];

  static List<StepRecord> get stepRecords => [
        for (final s in _steps)
          StepRecord(
            id: s.ordinal + 1,
            step: s,
            status: s.ordinal < 5
                ? StepStatus.done
                : s.ordinal == 5
                    ? StepStatus.active
                    : StepStatus.todo,
            sessionId: s.kind == StepKind.walk ? s.ordinal : null,
          ),
      ];

  /// The recorded demo walk as the ghost route; this walk is its first
  /// two thirds.
  static List<LatLng> get _route => [
        for (final r in DemoSite.current.live) LatLng(r.lat, r.lon),
      ];

  static PlanProgress get progress {
    final steps = stepRecords;
    final route = _route;
    final heard = DateTime.now();
    return PlanProgress(
      plan: plan,
      steps: steps,
      current: steps[5],
      walk: WalkState(
        sessionId: 5,
        elapsedSec: 7 * 60 + 40,
        plannedSec: 12 * 60,
        routeMatchPct: 72,
        pingsSent: 29,
        pingsAnswered: 27,
        baseHeard: true,
        baseLastHeardAt: heard.subtract(const Duration(seconds: 4)),
        lastSnr: 7.5,
        ghostRoute: route,
        track: route.sublist(0, (route.length * 2 / 3).round()),
        canFinish: false,
      ),
    );
  }

  static const analysis = PlanAnalysisResult(
    headline: '5.8 dBi fiberglass reached 190 m further and held the link '
        'where the whip lost it.',
    fairness: 'Same route both times (match 91 %), base untouched.',
    variants: [
      VariantResult(
        variant: 0,
        name: 'Stock whip',
        sessionIds: [3],
        reach: Measure('610 m', 'farthest ping'),
        margin: Measure('−2.1 dB', '41 shared cells'),
        third: Measure('38 / 52', '73 % answered'),
        leadPct: 22,
      ),
      VariantResult(
        variant: 1,
        name: '5.8 dBi fiberglass',
        sessionIds: [5],
        reach: Measure('800 m', 'farthest ping'),
        margin: Measure('+2.1 dB', '78 % of cells better'),
        third: Measure('47 / 51', '92 % answered'),
        leadPct: 78,
      ),
    ],
    winner: 1,
    nextStep: 'Both reached the gate at 610 m. To see how much further the '
        'fiberglass goes, walk on past the gate next time; the base stayed '
        'quiet after 800 m.',
    dataNotes: [
      'Walk 2 started 9 minutes later than walk 1 and the base did not '
          'move. Route match 91 %.',
    ],
    thirdLabel: 'PINGS',
  );

  final _progress = StreamController<PlanProgress>.broadcast();

  @override
  Future<PlanRecord> createPlan(PlanIntent intent,
          {required int coverageMapId}) async =>
      plan;

  @override
  Future<List<StepRecord>> steps(int planId) async => stepRecords;

  @override
  Stream<List<PlanRecord>> watchPlans(int coverageMapId) =>
      Stream.value([plan]);

  @override
  Stream<PlanRecord?> watchActivePlan() => Stream.value(null);

  @override
  Future<void> start(int planId) async {}

  @override
  Stream<PlanProgress> watch(int planId) async* {
    yield progress;
    yield* _progress.stream;
  }

  @override
  Future<void> completeStep(int planId) async => _progress.add(progress);

  @override
  Future<void> redoStep(int planId) async => _progress.add(progress);

  @override
  Future<void> skipStep(int planId) async => _progress.add(progress);

  @override
  Future<void> useBluetoothPath(int planId) async {}

  @override
  Future<void> recheck(int planId) async {}

  @override
  Future<void> pause(int planId) async {}

  @override
  Future<void> abandon(int planId) async {}

  @override
  Future<PlanAnalysisResult?> result(int planId) async => analysis;

  @override
  Future<void> renameVariant(int planId, int variant, String name) async {}

  @override
  Future<void> updateDraft(int planId, PlanIntent intent) async {}
}
