// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/guided/plan_models.dart';
import 'package:mesh_analyzer/services/privacy_settings.dart';
import 'package:mesh_analyzer/services/pro_entitlement.dart';
import 'package:mesh_analyzer/ui/theme/app_theme.dart';

import '../fakes/fake_mesh_radio.dart';
import '../pro_entitlement_test.dart' show FakeStore;

/// A [PlanRunnerApi] driven by the test: every call is logged, the
/// progress stream is fed by [emit], and the plan/steps/result are
/// whatever the test set.
class FakePlanRunner implements PlanRunnerApi {
  FakePlanRunner({
    PlanRecord? plan,
    List<StepRecord>? steps,
    this.analysis,
    this.activePlan,
  })  : plan = plan ?? samplePlan(),
        stepRecords = steps ?? sampleSteps();

  PlanRecord plan;
  List<StepRecord> stepRecords;
  PlanAnalysisResult? analysis;
  PlanRecord? activePlan;

  /// Thrown by [createPlan] when set.
  PlanError? createError;

  /// Method names in call order, with arguments ("completeStep:1",
  /// "renameVariant:1:0:Whip").
  final calls = <String>[];
  final created = <PlanIntent>[];
  final drafts = <PlanIntent>[];

  final _progress = StreamController<PlanProgress>.broadcast();
  PlanProgress? _last;

  /// Push a progress state to every Run screen watching.
  void emit(PlanProgress p) {
    _last = p;
    _progress.add(p);
  }

  void dispose() => _progress.close();

  @override
  Future<PlanRecord> createPlan(PlanIntent intent,
      {required int coverageMapId}) async {
    calls.add('createPlan:$coverageMapId');
    created.add(intent);
    if (createError != null) throw createError!;
    return plan;
  }

  @override
  Future<List<StepRecord>> steps(int planId) async {
    calls.add('steps:$planId');
    return stepRecords;
  }

  @override
  Stream<List<PlanRecord>> watchPlans(int coverageMapId) =>
      Stream.value(plan.coverageMapId == coverageMapId ? [plan] : const []);

  @override
  Stream<PlanRecord?> watchActivePlan() => Stream.value(activePlan);

  @override
  Future<void> start(int planId) async => calls.add('start:$planId');

  @override
  Stream<PlanProgress> watch(int planId) async* {
    calls.add('watch:$planId');
    if (_last != null) yield _last!;
    yield* _progress.stream;
  }

  @override
  Future<void> completeStep(int planId) async =>
      calls.add('completeStep:$planId');

  @override
  Future<void> redoStep(int planId) async => calls.add('redoStep:$planId');

  @override
  Future<void> skipStep(int planId) async => calls.add('skipStep:$planId');

  @override
  Future<void> useBluetoothPath(int planId) async =>
      calls.add('useBluetoothPath:$planId');

  @override
  Future<void> recheck(int planId) async => calls.add('recheck:$planId');

  @override
  Future<void> pause(int planId) async => calls.add('pause:$planId');

  @override
  Future<void> abandon(int planId) async => calls.add('abandon:$planId');

  @override
  Future<PlanAnalysisResult?> result(int planId) async {
    calls.add('result:$planId');
    return analysis;
  }

  @override
  Future<void> renameVariant(int planId, int variant, String name) async {
    calls.add('renameVariant:$planId:$variant:$name');
    final variants = [...plan.intent.variants]..[variant] = name;
    plan = withIntent(plan, plan.intent.copyWith(variants: variants));
  }

  @override
  Future<void> updateDraft(int planId, PlanIntent intent) async {
    calls.add('updateDraft:$planId');
    drafts.add(intent);
    plan = withIntent(plan, intent);
  }
}

/// A parser with a canned answer; records what it was asked.
class FakePlanIntentParser implements PlanIntentParser {
  FakePlanIntentParser({this.guess});

  PlanIntentGuess? guess;
  final asked = <String>[];
  ParserContext? lastContext;

  @override
  Future<PlanIntentGuess> parse(String text,
      {required ParserContext ctx}) async {
    asked.add(text);
    lastContext = ctx;
    return guess ??
        const PlanIntentGuess(
          intent: PlanIntent(
              template: PlanTemplate.antennas, variants: ['Whip', 'Fiber']),
          confidence: 0.9,
          fromAi: true,
        );
  }
}

PlanRecord withIntent(PlanRecord p, PlanIntent intent,
        {PlanStatus? status, int? currentStep}) =>
    PlanRecord(
      id: p.id,
      coverageMapId: p.coverageMapId,
      title: p.title,
      intent: intent,
      status: status ?? p.status,
      currentStep: currentStep ?? p.currentStep,
      remoteChanges: p.remoteChanges,
      createdAt: p.createdAt,
      finishedAt: p.finishedAt,
    );

const sampleVariants = ['Stock whip', '5.8 dBi fiberglass'];

PlanRecord samplePlan({
  PlanStatus status = PlanStatus.draft,
  int currentStep = 0,
  bool remote = false,
  PlanTemplate template = PlanTemplate.antennas,
  List<String> variants = sampleVariants,
  int mapId = 1,
}) =>
    PlanRecord(
      id: 1,
      coverageMapId: mapId,
      title: 'Antenna test',
      intent: PlanIntent(template: template, variants: variants),
      status: status,
      currentStep: currentStep,
      remoteChanges: remote,
      createdAt: DateTime(2026, 10, 31, 11, 40),
    );

/// The antenna plan's seven steps from the design mock.
List<StepRecord> sampleSteps({int active = 0}) {
  const steps = [
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
        params: {'target': 'start'}),
    PlanStep(
        ordinal: 3,
        kind: StepKind.walk,
        variant: 0,
        title: 'Walk the route',
        instruction: 'Walk where you want coverage checked.',
        summary: '≈12 min · the app records',
        params: {'minutes': 12, 'pass': 1}),
    PlanStep(
        ordinal: 4,
        kind: StepKind.swapHardware,
        variant: 1,
        title: 'Put the 5.8 dBi fiberglass on',
        instruction: 'Same node, same spot.',
        summary: 'Same node, same spot',
        params: {'side': 'mobile', 'name': '5.8 dBi fiberglass'}),
    PlanStep(
        ordinal: 5,
        kind: StepKind.walk,
        variant: 1,
        title: 'Walk the same route',
        instruction: 'Follow the dashed line.',
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
  return [
    for (final s in steps)
      StepRecord(
        id: s.ordinal + 1,
        step: s,
        status: s.ordinal < active
            ? StepStatus.done
            : s.ordinal == active
                ? StepStatus.active
                : StepStatus.todo,
      ),
  ];
}

/// A progress snapshot at step [ordinal] of the sample plan, with the
/// typed state the test supplies.
PlanProgress progressAt(
  int ordinal, {
  PlanRecord? plan,
  List<StepRecord>? steps,
  List<CheckRow>? preflight,
  GoToState? goTo,
  WalkState? walk,
  ChangeState? change,
  int? settleRemainingSec,
  bool analyzing = false,
  String note = '',
}) {
  final all = steps ?? sampleSteps(active: ordinal);
  final cur = all[ordinal];
  final current = note.isEmpty
      ? cur
      : StepRecord(id: cur.id, step: cur.step, status: cur.status, note: note);
  return PlanProgress(
    plan: plan ?? samplePlan(status: PlanStatus.running, currentStep: ordinal),
    steps: all,
    current: current,
    preflight: preflight,
    goTo: goTo,
    walk: walk,
    change: change,
    settleRemainingSec: settleRemainingSec,
    analyzing: analyzing,
  );
}

/// A step of another kind spliced into the sample plan at [ordinal].
PlanProgress progressWithStep(
  PlanStep step, {
  PlanRecord? plan,
  List<CheckRow>? preflight,
  GoToState? goTo,
  WalkState? walk,
  ChangeState? change,
  int? settleRemainingSec,
}) {
  final steps = sampleSteps(active: step.ordinal);
  steps[step.ordinal] =
      StepRecord(id: step.ordinal + 1, step: step, status: StepStatus.active);
  return progressAt(step.ordinal,
      plan: plan,
      steps: steps,
      preflight: preflight,
      goTo: goTo,
      walk: walk,
      change: change,
      settleRemainingSec: settleRemainingSec);
}

const sampleResult = PlanAnalysisResult(
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
  nextStep: 'Both reached the gate at 610 m. Walk on past the gate next time.',
  dataNotes: ['Walk 2 started 9 minutes later than walk 1. Route match 91 %.'],
  thirdLabel: 'PINGS',
  digest: {'variants': 2},
);

const demoLatLng = LatLng(33.6798, -116.2372);

/// Everything a guided-test screen needs under test.
class GuidedEnv {
  GuidedEnv._(this.db, this.prefs, this.runner, this.parser, this.radio);

  final AppDatabase db;
  final SharedPreferences prefs;
  final FakePlanRunner runner;
  final FakePlanIntentParser parser;
  final FakeMeshRadio radio;

  static Future<GuidedEnv> create({
    Map<String, Object>? prefs,
    FakePlanRunner? runner,
    FakePlanIntentParser? parser,
    int maps = 1,
  }) async {
    SharedPreferences.setMockInitialValues(prefs ?? {});
    final p = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    for (var i = 0; i < maps; i++) {
      await db.createCoverageMap(name: 'Map ${i + 1}');
    }
    final radio = FakeMeshRadio(currentPreset: MeshtasticPresets.mediumFast);
    return GuidedEnv._(db, p, runner ?? FakePlanRunner(),
        parser ?? FakePlanIntentParser(), radio);
  }

  Future<void> close() async {
    runner.dispose();
    await db.close();
  }

  /// A [MaterialApp] with the app theme and every provider the screens
  /// read overridden.
  Widget app(Widget home,
      {bool pro = true,
      RadioConnectionState link = RadioConnectionState.ready,
      List<Override> overrides = const []}) {
    final service = ProEntitlement(
        prefs: prefs,
        store: FakeStore(),
        clock: () => DateTime(2026, 10, 31),
        proOverride: pro);
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        planRunnerProvider.overrideWithValue(runner),
        planIntentParserProvider.overrideWithValue(parser),
        meshRadioProvider.overrideWithValue(radio),
        meshLinkStateProvider.overrideWith((ref) => Stream.value(link)),
        proEntitlementProvider.overrideWithValue(service),
        aiAnalysisAvailableProvider.overrideWithValue(false),
        mapTilesEnabledProvider.overrideWithValue(false),
        ...overrides,
      ],
      child: MaterialApp(theme: AppTheme.dark(), home: home),
    );
  }
}

/// Lets real async work (drift, futures) finish between pumps.
Future<void> settle(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Scrolls the screen's first list until [finder] is built and visible
/// (lazy lists don't build what is off screen).
Future<void> scrollTo(WidgetTester tester, Finder finder) => tester
    .scrollUntilVisible(finder, 120, scrollable: find.byType(Scrollable).first);

/// Unmount so provider streams dispose before the test ends.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}
