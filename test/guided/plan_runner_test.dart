// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/services/guided/plan_models.dart';
import 'package:mesh_analyzer/services/guided/plan_runner.dart';
import 'package:mesh_analyzer/utils/constants.dart';

import 'fake_plan_environment.dart';

const _base = LatLng(33.68, -116.24);
const _dist = Distance();
LatLng east(double m) => _dist.offset(_base, m, 90);

const antennas = PlanIntent(
    template: PlanTemplate.antennas,
    variants: ['Stock whip', '5.8 dBi fiberglass']);
const presets = PlanIntent(
    template: PlanTemplate.rangeSettings,
    variants: ['MEDIUM_FAST', 'LONG_FAST']);

/// Let timers and the serial queue drain.
Future<void> pump([int ms = 40]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late AppDatabase db;
  late FakePlanEnvironment env;
  late PlanRunner runner;
  late int mapId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    env = FakePlanEnvironment(db);
    runner = PlanRunner(
      env,
      settleDuration: const Duration(milliseconds: 10),
      listenDuration: const Duration(milliseconds: 60),
      rollbackListenDuration: const Duration(milliseconds: 40),
      pingEvery: const Duration(milliseconds: 5),
      advanceDelay: const Duration(milliseconds: 1),
      tick: const Duration(milliseconds: 5),
      minWalk: Duration.zero,
      minWalkPings: 2,
    );
    mapId = await db.createCoverageMap(
        name: 'Ranch', baseLat: _base.latitude, baseLon: _base.longitude);
    env.lastPosition = _base;
  });

  tearDown(() async {
    await runner.dispose();
    await env.dispose();
    await db.close();
  });

  Future<PlanProgress> progress(int planId) => runner.watch(planId).first;

  Future<StepKind> currentKind(int planId) async =>
      (await progress(planId)).current.step.kind;

  /// Walk east 200 m with two answered pings, then back.
  Future<void> walkOut(FakePlanEnvironment env) async {
    for (var m = 0.0; m <= 200; m += 20) {
      env.moveTo(east(m));
      await pump(2);
    }
    await env.pingOutcome(AckStatus.received);
    await env.pingOutcome(AckStatus.received);
    for (var m = 180.0; m >= 0; m -= 20) {
      env.moveTo(east(m));
      await pump(2);
    }
    await pump();
  }

  group('plans', () {
    test('createPlan stores the plan and its steps as a draft', () async {
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      expect(plan.status, PlanStatus.draft);
      expect(plan.title, 'Antenna test');
      expect(plan.remoteChanges, isFalse);
      expect(plan.intent.variants, antennas.variants);
      final steps = await runner.steps(plan.id);
      expect(steps.length, 8);
      expect(steps.first.step.kind, StepKind.preflight);
      expect(steps.first.status, StepStatus.todo);
      expect(await runner.result(plan.id), isNull);
      expect((await runner.watchPlans(mapId).first).single.id, plan.id);
      expect(await runner.watchActivePlan().first, isNull);
    });

    test('an invalid intent is a PlanError', () {
      expect(
          () => runner.createPlan(
              const PlanIntent(
                  template: PlanTemplate.antennas, variants: ['one']),
              coverageMapId: mapId),
          throwsA(isA<PlanError>()));
    });

    test('remote changes need the grant for this radio and a heard base',
        () async {
      env.remoteAdminMobileNode = env.myNodeId;
      var plan = await runner.createPlan(presets, coverageMapId: mapId);
      expect(plan.remoteChanges, isTrue);

      env.remoteAdminMobileNode = 0x9999; // granted to another radio
      plan = await runner.createPlan(presets, coverageMapId: mapId);
      expect(plan.remoteChanges, isFalse);

      env.remoteAdminMobileNode = env.myNodeId;
      env.baseLastHeardAt = DateTime.now().subtract(const Duration(hours: 1));
      plan = await runner.createPlan(presets, coverageMapId: mapId);
      expect(plan.remoteChanges, isFalse);

      env.baseLastHeardAt = DateTime.now();
      env.protocol = RadioProtocol.meshcore;
      plan = await runner.createPlan(presets, coverageMapId: mapId);
      expect(plan.remoteChanges, isFalse, reason: 'MeshCore: Bluetooth only');
      final change = (await runner.steps(plan.id))
          .firstWhere((s) => s.step.kind == StepKind.changeRadios);
      expect(change.step.summary, contains('Bluetooth'));
    });

    test('updateDraft rebuilds the steps; not after start', () async {
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      await runner.updateDraft(plan.id, antennas.copyWith(repeat: true));
      expect((await runner.steps(plan.id)).length, 13);
      await runner.start(plan.id);
      expect(() => runner.updateDraft(plan.id, antennas),
          throwsA(isA<PlanError>()));
    });

    test('renameVariant rewrites the titles of steps still to come', () async {
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      await runner.renameVariant(plan.id, 1, 'Big fiberglass');
      final steps = await runner.steps(plan.id);
      expect(steps[4].step.title, 'Put the Big fiberglass on');
      expect(steps[4].step.params['name'], 'Big fiberglass');
      final stored = await db.getTestPlan(plan.id);
      expect(stored!.intentJson, contains('Big fiberglass'));
      expect(() => runner.renameVariant(plan.id, 1, 'Stock whip'),
          throwsA(isA<PlanError>()),
          reason: 'duplicate name');
    });

    test('map delete takes the plans; session delete unlinks the step',
        () async {
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      final steps = await db.getTestSteps(plan.id);
      final sid = await db.createSession(coverageMapId: mapId);
      await db.linkSessionToStep(steps[3].id, sid);
      expect((await db.getSessionById(sid))!.testStepId, steps[3].id);
      await db.deleteSessions([sid]);
      expect((await db.getTestSteps(plan.id))[3].sessionId, isNull);
      await db.deleteCoverageMap(mapId);
      expect(await db.getTestPlan(plan.id), isNull);
      expect(await db.getTestSteps(plan.id), isEmpty);
    });
  });

  group('antenna test end to end', () {
    test('preflight auto-advances, swaps, walks, compares', () async {
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      final seen = <PlanProgress>[];
      final sub = runner.watch(plan.id).listen(seen.add);

      await runner.start(plan.id);
      await pump();
      expect(await runner.watchActivePlan().first, isNotNull);
      expect(env.gpsStarts, 1);
      var p = await progress(plan.id);
      expect(p.plan.status, PlanStatus.running);
      expect(p.current.step.kind, StepKind.swapHardware,
          reason: 'all preflight rows green → straight on');
      expect(p.steps[0].status, StepStatus.done);
      expect(p.stepNumber, 2);
      expect(p.stepCount, 8);
      // The preflight rows were shown on the way.
      final pre = seen.firstWhere((x) => x.preflight != null).preflight!;
      expect(
          pre.map((r) => r.label),
          containsAll([
            'Mobile node connected',
            'Base node known',
            'Both on MeshTest, same setting',
            'Base beacon on',
            'Base location',
            'GPS',
          ]));
      expect(pre.every((r) => r.status == CheckStatus.ok), isTrue);
      expect(pre.firstWhere((r) => r.label == 'Base beacon on').detail,
          'telemetry · every 60 s');
      expect(pre.firstWhere((r) => r.label == 'Base location').detail,
          '0 m from here');

      // Swap: done, it's on.
      await runner.completeStep(plan.id);
      p = await progress(plan.id);
      expect(p.current.step.kind, StepKind.goTo);
      expect(p.goTo!.target, _base, reason: 'no start pin yet: the base');
      expect(p.goTo!.arrived, isTrue);
      expect(p.goTo!.setsBaseLocation, isFalse);
      env.moveTo(east(100));
      await pump();
      p = await progress(plan.id);
      expect(p.goTo!.distanceM, closeTo(100, 1));
      expect(p.goTo!.bearingDeg, closeTo(270, 1));
      expect(p.goTo!.arrived, isFalse);
      env.moveTo(east(5));
      await pump();
      expect((await progress(plan.id)).goTo!.arrived, isTrue);

      // I'm here → the walk starts a session.
      await runner.completeStep(plan.id);
      p = await progress(plan.id);
      expect(p.current.step.kind, StepKind.walk);
      expect(env.startedNames, ['Antenna test · 1 of 2 · Stock whip']);
      final rig = await db.findRigProfileByName('Stock whip');
      expect(rig, isNotNull);
      expect(rig!.role, 'mobile');
      expect(rig.antennaName, 'Stock whip');
      expect(env.startedRigs.single, (rig.id, null));
      expect(p.current.sessionId, env.activeSession!.id);
      expect((await db.getSessionById(env.activeSession!.id))!.testStepId,
          p.current.id);
      expect(p.walk!.plannedSec, 12 * 60);
      expect(p.walk!.routeMatchPct, isNull, reason: 'first pass');
      expect(p.walk!.ghostRoute, isEmpty);

      await walkOut(env);
      env.hearBase(snr: 7.5);
      await pump();
      p = await progress(plan.id);
      expect(p.walk!.pingsSent, 2);
      expect(p.walk!.pingsAnswered, 2);
      expect(p.walk!.baseHeard, isTrue);
      expect(p.walk!.lastSnr, 7.5);
      expect(p.walk!.track.length, greaterThan(10));

      // Done walking.
      await runner.completeStep(plan.id);
      p = await progress(plan.id);
      expect(env.activeSession, isNull);
      expect(p.steps[3].status, StepStatus.done);
      expect(p.steps[3].step.params['ghost'], isA<List>());
      expect(p.steps[3].step.params['start'], isA<List>());
      expect(p.steps[3].step.params['pings'], 2);
      expect(p.current.step.kind, StepKind.swapHardware);
      expect(p.current.step.title, 'Put the 5.8 dBi fiberglass on');

      await runner.completeStep(plan.id);
      p = await progress(plan.id);
      expect(p.current.step.kind, StepKind.goTo);
      expect(p.goTo!.target, isNot(_base),
          reason: 'the start pin is where walk 1 began');
      expect(_dist(p.goTo!.target!, east(5)), lessThan(3));

      await runner.completeStep(plan.id);
      p = await progress(plan.id);
      expect(p.current.step.kind, StepKind.walk);
      expect(
          env.startedNames.last, 'Antenna test · 2 of 2 · 5.8 dBi fiberglass');
      expect(p.walk!.ghostRoute, isNotEmpty);
      expect(p.walk!.routeMatchPct, lessThan(100));
      expect(p.walk!.canFinish, isFalse);
      await walkOut(env);
      p = await progress(plan.id);
      expect(p.walk!.routeMatchPct, greaterThanOrEqualTo(80));
      expect(p.walk!.canFinish, isTrue);

      // Done walking → compare → done.
      await runner.completeStep(plan.id);
      await pump(200);
      p = await progress(plan.id);
      expect(p.plan.status, PlanStatus.done);
      expect(p.steps.last.status, StepStatus.done);
      expect(p.plan.finishedAt, isNotNull);
      final result = await runner.result(plan.id);
      expect(result, isNotNull);
      expect(result!.variants.length, 2);
      expect(result.variants[0].sessionIds, isNotEmpty);
      expect(result.headline, isNotEmpty);
      expect(result.nextStep, isNotEmpty);
      expect(await runner.watchActivePlan().first, isNull);
      expect(runner.activePlanId, isNull);
      await sub.cancel();
    });

    test('a thin walk waits: keep it or walk again', () async {
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      await runner.start(plan.id);
      await pump();
      await runner.completeStep(plan.id); // swap
      await runner.completeStep(plan.id); // I'm here
      expect(await currentKind(plan.id), StepKind.walk);
      final firstSession = env.activeSession!.id;
      env.moveTo(east(30));
      await pump();
      // Done walking with no pings: thin.
      await runner.completeStep(plan.id);
      var p = await progress(plan.id);
      expect(p.current.step.kind, StepKind.walk);
      expect(p.current.status, StepStatus.active);
      expect(p.current.note, PlanRunner.thinWalkNote);
      expect(env.activeSession, isNull, reason: 'the session is ended');
      expect(p.current.sessionId, firstSession);

      // Walk this one again: the session is kept but unlinked.
      await runner.redoStep(plan.id);
      p = await progress(plan.id);
      expect(p.current.sessionId, isNot(firstSession));
      expect(p.current.note, startsWith('walked again'));
      expect((await db.getSessionById(firstSession))!.testStepId, isNull);
      expect((await db.getSessionById(firstSession))!.isActive, isFalse);
      expect(env.startedNames.length, 2);

      await walkOut(env);
      await runner.completeStep(plan.id);
      expect(await currentKind(plan.id), StepKind.swapHardware);
    });

    test('a thin walk can be kept', () async {
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      await runner.start(plan.id);
      await pump();
      await runner.completeStep(plan.id);
      await runner.completeStep(plan.id);
      await runner.completeStep(plan.id); // thin
      expect((await progress(plan.id)).current.note, PlanRunner.thinWalkNote);
      await runner.completeStep(plan.id); // keep
      final p = await progress(plan.id);
      expect(p.current.step.kind, StepKind.swapHardware);
      expect(p.steps[3].status, StepStatus.done);
      expect(p.steps[3].note, startsWith('kept a short walk'));
    });

    test('the session ending from outside finishes the walk', () async {
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      await runner.start(plan.id);
      await pump();
      await runner.completeStep(plan.id);
      await runner.completeStep(plan.id);
      await walkOut(env);
      await env.endSessionExternally();
      await pump();
      expect(await currentKind(plan.id), StepKind.swapHardware);
    });

    test('a refused session start is a PlanError and the step stays', () async {
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      await runner.start(plan.id);
      await pump();
      await runner.completeStep(plan.id);
      env.startRefusal = 'Node not connected';
      await expectLater(
          runner.completeStep(plan.id),
          throwsA(isA<PlanError>()
              .having((e) => e.message, 'message', 'Node not connected')));
      var p = await progress(plan.id);
      expect(p.current.step.kind, StepKind.walk);
      expect(p.current.sessionId, isNull);
      expect(p.current.note, 'Node not connected');
      // Fixed: tapping again starts the walk.
      env.startRefusal = null;
      await runner.completeStep(plan.id);
      p = await progress(plan.id);
      expect(p.current.sessionId, isNotNull);
      expect(p.current.note, isEmpty);
    });

    test('skipStep moves on and the result notes it', () async {
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      await runner.start(plan.id);
      await pump();
      await runner.skipStep(plan.id);
      final p = await progress(plan.id);
      expect(p.steps[1].status, StepStatus.skipped);
      expect(p.current.step.kind, StepKind.goTo);
    });
  });

  group('preflight', () {
    test('a red row blocks and the fix is named; recheck follows the radio',
        () async {
      env.ready = false;
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      await runner.start(plan.id);
      await pump();
      var p = await progress(plan.id);
      expect(p.current.step.kind, StepKind.preflight);
      final row =
          p.preflight!.firstWhere((r) => r.label == 'Mobile node connected');
      expect(row.status, CheckStatus.fail);
      expect(row.fix, PreflightFix.connectRadio);
      expect(
          p.preflight!.firstWhere((r) => r.label.startsWith('Both on')).status,
          CheckStatus.busy);
      expect(() => runner.completeStep(plan.id), throwsA(isA<PlanError>()));

      env.setReady(true);
      await pump();
      p = await progress(plan.id);
      expect(p.current.step.kind, StepKind.swapHardware,
          reason: 'the node coming back re-runs the checks and advances');
    });

    test('a warning waits for the person; GPS searching is busy', () async {
      env.baseBeacon = null;
      env.gpsState = const GpsState(GpsStatus.searching);
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      await runner.start(plan.id);
      await pump();
      var p = await progress(plan.id);
      expect(p.current.step.kind, StepKind.preflight);
      expect(p.preflight!.firstWhere((r) => r.label == 'Base beacon').status,
          CheckStatus.warn);
      expect(p.preflight!.firstWhere((r) => r.label == 'GPS').status,
          CheckStatus.busy);
      env.setGps(const GpsState(GpsStatus.fix, accuracy: 6));
      await pump();
      p = await progress(plan.id);
      expect(p.preflight!.firstWhere((r) => r.label == 'GPS').detail, '±6 m');
      expect(p.current.step.kind, StepKind.preflight,
          reason: 'the beacon warning still waits');
      await runner.completeStep(plan.id);
      expect(await currentKind(plan.id), StepKind.swapHardware);
    });

    test('a mismatch is red with Radio Setup as the fix', () async {
      env.setupMismatch = 'preset: base LONG_FAST, mobile MEDIUM_FAST';
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      await runner.start(plan.id);
      await pump();
      final row = (await progress(plan.id))
          .preflight!
          .firstWhere((r) => r.label.startsWith('Both on'));
      expect(row.status, CheckStatus.fail);
      expect(row.fix, PreflightFix.openRadioSetup);
      expect(row.detail, contains('LONG_FAST'));
    });

    test('range settings: backup, remote grant and base location rows',
        () async {
      env.remoteAdminMobileNode = env.myNodeId;
      env.originalBackup = false;
      final plan = await runner.createPlan(presets, coverageMapId: mapId);
      expect(plan.remoteChanges, isTrue);
      await runner.start(plan.id);
      await pump();
      var p = await progress(plan.id);
      final saved =
          p.preflight!.firstWhere((r) => r.label == 'Base settings saved');
      expect(saved.status, CheckStatus.fail);
      expect(saved.fix, PreflightFix.walkToBaseInstead);
      expect(p.preflight!.firstWhere((r) => r.label == 'Remote changes').status,
          CheckStatus.ok);
      expect(p.preflight!.any((r) => r.label == 'Base beacon on'), isFalse);

      // I'll walk to it instead: the plan switches to the Bluetooth path.
      await runner.useBluetoothPath(plan.id);
      await pump();
      p = await progress(plan.id);
      expect(p.plan.remoteChanges, isFalse);
      expect(
          p.preflight!
              .firstWhere((r) => r.label == 'Base settings saved')
              .status,
          CheckStatus.warn);
      expect(p.preflight!.firstWhere((r) => r.label == 'Base changes').detail,
          contains('Bluetooth'));
      final change =
          p.steps.firstWhere((s) => s.step.kind == StepKind.changeRadios);
      expect(change.step.summary, contains('Bluetooth'));
    });

    test('remote not granted is a warning with the base fix', () async {
      env.remoteAdminMobileNode = env.myNodeId;
      final plan = await runner.createPlan(presets, coverageMapId: mapId);
      env.remoteAdminMobileNode = null; // grant lost before start
      await runner.start(plan.id);
      await pump();
      final row = (await progress(plan.id))
          .preflight!
          .firstWhere((r) => r.label == 'Remote changes');
      expect(row.status, CheckStatus.warn);
      expect(row.fix, PreflightFix.enableRemoteAtBase);
    });
  });

  group('goTo', () {
    test('a map without a base location gets it from the first stop', () async {
      final bare = await db.createCoverageMap(name: 'New');
      final plan = await runner.createPlan(antennas, coverageMapId: bare);
      await runner.start(plan.id);
      await pump();
      var p = await progress(plan.id);
      expect(p.preflight!.firstWhere((r) => r.label == 'Base location').status,
          CheckStatus.warn);
      await runner.completeStep(plan.id); // preflight (warning only)
      await runner.completeStep(plan.id); // swap
      p = await progress(plan.id);
      expect(p.goTo!.setsBaseLocation, isTrue);
      expect(p.goTo!.target, isNull);
      env.lastPosition = null;
      await expectLater(
          runner.completeStep(plan.id), throwsA(isA<PlanError>()));
      env.moveTo(east(3));
      await pump();
      await runner.completeStep(plan.id);
      final map = await db.getCoverageMap(bare);
      expect(map!.baseLat, isNotNull);
      expect(_dist(LatLng(map.baseLat!, map.baseLon!), east(3)), lessThan(1));
    });
  });

  group('pause and resume', () {
    test('pausing a walk ends its session; resuming walks it again', () async {
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      await runner.start(plan.id);
      await pump();
      await runner.completeStep(plan.id);
      await runner.completeStep(plan.id);
      final first = env.activeSession!.id;
      await runner.pause(plan.id);
      expect(env.activeSession, isNull);
      var p = await progress(plan.id);
      expect(p.plan.status, PlanStatus.paused);
      expect(p.plan.currentStep, 3);
      expect(p.walk, isNull, reason: 'a snapshot, no live state');
      expect(runner.activePlanId, isNull);
      expect((await runner.watchActivePlan().first)!.id, plan.id);
      expect(() => runner.completeStep(plan.id), throwsA(isA<PlanError>()));

      await runner.start(plan.id);
      p = await progress(plan.id);
      expect(p.plan.status, PlanStatus.running);
      expect(p.current.step.kind, StepKind.walk);
      expect(p.current.sessionId, isNot(first));
      expect(p.current.note, startsWith('restarted'));
      expect((await db.getSessionById(first))!.testStepId, isNull);
    });

    test('a plan left running by a crash resumes at its step', () async {
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      await runner.start(plan.id);
      await pump();
      await runner.completeStep(plan.id);
      await runner.completeStep(plan.id);
      final sid = env.activeSession!.id;
      // The app dies: a new runner over the same database.
      await runner.dispose();
      final env2 = FakePlanEnvironment(db)..lastPosition = _base;
      final runner2 =
          PlanRunner(env2, advanceDelay: const Duration(milliseconds: 1));
      expect((await db.getTestPlan(plan.id))!.status, 'running');
      expect((await db.getSessionById(sid))!.isActive, isTrue);
      await runner2.start(plan.id);
      final p = await runner2.watch(plan.id).first;
      expect(p.current.step.kind, StepKind.walk);
      expect(p.current.sessionId, isNot(sid));
      expect((await db.getSessionById(sid))!.isActive, isFalse,
          reason: 'the orphaned session is ended');
      await runner2.dispose();
      await env2.dispose();
      runner = PlanRunner(env); // for tearDown
    });

    test('abandon ends the session and the plan', () async {
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      await runner.start(plan.id);
      await pump();
      await runner.completeStep(plan.id);
      await runner.completeStep(plan.id);
      await runner.abandon(plan.id);
      expect(env.activeSession, isNull);
      final p = await progress(plan.id);
      expect(p.plan.status, PlanStatus.abandoned);
      expect(p.plan.finishedAt, isNotNull);
      expect(await runner.watchActivePlan().first, isNull);
      expect(() => runner.start(plan.id), throwsA(isA<PlanError>()));
    });

    test('only one plan runs at a time', () async {
      final a = await runner.createPlan(antennas, coverageMapId: mapId);
      final b = await runner.createPlan(antennas, coverageMapId: mapId);
      await runner.start(a.id);
      expect(() => runner.start(b.id), throwsA(isA<PlanError>()));
    });

    test('start on a plan already running here changes nothing', () async {
      final plan = await runner.createPlan(antennas, coverageMapId: mapId);
      await runner.start(plan.id);
      await pump();
      await runner.completeStep(plan.id);
      await runner.completeStep(plan.id);
      final sid = env.activeSession!.id;
      await runner.start(plan.id);
      expect(env.activeSession!.id, sid, reason: 'the walk keeps recording');
      expect((await progress(plan.id)).current.sessionId, sid);
    });
  });

  group('changeRadios (design §6)', () {
    Future<int> toFirstChange(PlanIntent intent) async {
      final plan = await runner.createPlan(intent, coverageMapId: mapId);
      await runner.start(plan.id);
      await pump();
      expect(await currentKind(plan.id), StepKind.goTo);
      await runner.completeStep(plan.id);
      expect(await currentKind(plan.id), StepKind.changeRadios);
      return plan.id;
    }

    test('restore step learns the setting the radios had at start', () async {
      final id = await toFirstChange(presets);
      final restore = (await runner.steps(id))
          .lastWhere((s) => s.step.kind == StepKind.changeRadios);
      expect(restore.step.params['restore'], isTrue);
      expect(restore.step.params['preset'], 'MEDIUM_FAST');
      expect(restore.step.title, 'Put both nodes back on Medium Fast');
    });

    test('remote path: backup check, base, settle, mobile, heard, on',
        () async {
      env.remoteAdminMobileNode = env.myNodeId;
      final id = await toFirstChange(presets);
      var p = await progress(id);
      expect(p.plan.remoteChanges, isTrue);
      expect(p.change!.phase, ChangePhase.ready);
      expect(p.change!.remote, isTrue);
      expect(p.change!.targetName, 'Medium Fast');
      expect(p.change!.baseDistanceM, closeTo(0, 1));
      expect(p.current.step.params['fromPreset'], 'MEDIUM_FAST');

      env.pingScript.add(PingStatus.received);
      final phases = <ChangePhase>{};
      final sub = runner.watch(id).listen((x) {
        if (x.change != null) phases.add(x.change!.phase);
      });
      await runner.completeStep(id);
      await pump(300);
      await sub.cancel();
      expect(
          phases,
          containsAll([
            ChangePhase.backingUp,
            ChangePhase.changingBase,
            ChangePhase.settling,
            ChangePhase.changingMobile,
            ChangePhase.listening,
            ChangePhase.done,
          ]));
      expect(env.remoteChanges, [('MEDIUM_FAST', null)]);
      expect(env.recordedBase, [('MEDIUM_FAST', null)]);
      expect(env.mobileChanges, [('MEDIUM_FAST', null)]);
      expect(env.prepared, [env.baseNodeNum]);
      p = await progress(id);
      expect(p.current.step.kind, StepKind.walk, reason: 'done → next step');
      expect(p.steps[2].status, StepStatus.done);
    });

    test('silent base, old setting answers: the change did not take', () async {
      env.remoteAdminMobileNode = env.myNodeId;
      env.currentPreset = MeshtasticPresets.longFast; // the radios' setting now
      final id = await toFirstChange(presets);
      // Listening: all timeouts (an empty script times out); rollback
      // check: answered. Wait for the events, not a fixed time: under load
      // a fixed pump landed before the change or after the rollback check.
      unawaited(runner.completeStep(id));
      for (var i = 0; i < 800 && env.mobileChanges.length < 2; i++) {
        await pump(5);
      }
      env.pingScript.add(PingStatus.received);
      var p = await progress(id);
      for (var i = 0;
          i < 800 &&
              (p.change?.phase != ChangePhase.failed ||
                  p.plan.status != PlanStatus.paused);
          i++) {
        await pump(5);
        p = await progress(id);
      }
      expect(p.change!.phase, ChangePhase.failed);
      expect(p.change!.baseChanged, isFalse);
      expect(p.change!.failure, startsWith("The base didn't take the change."));
      expect(p.plan.status, PlanStatus.paused);
      expect(p.current.step.kind, StepKind.changeRadios);
      expect(env.mobileChanges.length, 2, reason: 'new, then back');
      expect(env.mobileChanges.last, ('LONG_FAST', 27),
          reason: 'back to the old preset at the old power');
      expect(env.currentPreset, MeshtasticPresets.longFast);
      expect(p.change!.rows.any((r) => r.status == CheckStatus.fail), isTrue);
    });

    test('a remote save the base did not confirm is sent once more', () async {
      env.remoteAdminMobileNode = env.myNodeId;
      final id = await toFirstChange(presets);
      env.remoteConfirms.addAll([false, true]);
      env.pingScript.add(PingStatus.received);
      await runner.completeStep(id);
      await pump(300);
      expect(env.remoteChanges, [('MEDIUM_FAST', null), ('MEDIUM_FAST', null)]);
      expect(await currentKind(id), StepKind.walk);
    });

    test('still unconfirmed after the retry: the row says it may not be saved',
        () async {
      env.remoteAdminMobileNode = env.myNodeId;
      final id = await toFirstChange(presets);
      env.remoteConfirms.addAll([false, false]);
      final rows = <CheckRow>[];
      final sub = runner.watch(id).listen((x) {
        if (x.change != null) rows.addAll(x.change!.rows);
      });
      env.pingScript.add(PingStatus.received);
      await runner.completeStep(id);
      await pump(300);
      await sub.cancel();
      expect(env.remoteChanges.length, 2, reason: 'one retry, no more');
      final base = rows.lastWhere((r) => r.label.startsWith('Base:'));
      expect(base.status, CheckStatus.warn);
      expect(base.detail, contains('may not have saved'));
    });

    test('rollback with the old TX power unknown is not reported as done',
        () async {
      env.currentTxPowerDbm = null; // the radio never reported its power
      final id = await toFirstChange(const PlanIntent(
          template: PlanTemplate.txPower, variants: ['20', '27']));
      expect((await progress(id)).current.step.params['fromTxPower'], isNull);
      unawaited(runner.completeStep(id));
      await pump(400);
      final p = await progress(id);
      expect(p.change!.phase, ChangePhase.failed);
      expect(env.mobileChanges, [('MEDIUM_FAST', 20)],
          reason: 'nothing to put back, so nothing is sent');
      final back = p.change!.rows.firstWhere((r) => r.label.contains('back'));
      expect(back.status, CheckStatus.fail);
      expect(back.detail, contains('Node Setup'));
    });

    test('rollback reads the radio back and flags a setting that stuck',
        () async {
      env.remoteAdminMobileNode = env.myNodeId;
      env.currentPreset = MeshtasticPresets.longFast;
      final id = await toFirstChange(presets);
      unawaited(runner.completeStep(id));
      // Wait for the forward change itself, not a fixed time (under load a
      // fixed pump landed before it or after the rollback had started).
      for (var i = 0; i < 400 && env.mobileChanges.isEmpty; i++) {
        await pump(5);
      }
      expect(env.mobileChanges, [('MEDIUM_FAST', null)]);
      env.mobileIgnoresChanges = true; // the change went in, the undo won't
      env.currentPreset = MeshtasticPresets.mediumFast;
      await pump(400);
      final p = await progress(id);
      expect(env.mobileChanges.last, ('LONG_FAST', 27));
      final back = p.change!.rows.firstWhere((r) => r.label.contains('back'));
      expect(back.status, CheckStatus.fail);
      expect(back.detail, contains('Medium Fast'));
    });

    test('silent on both: the base is out of reach; Bluetooth path from there',
        () async {
      env.remoteAdminMobileNode = env.myNodeId;
      final id = await toFirstChange(presets);
      unawaited(runner.completeStep(id));
      await pump(400);
      var p = await progress(id);
      expect(p.change!.phase, ChangePhase.failed);
      expect(p.change!.baseChanged, isTrue);
      expect(p.change!.failure, contains('out of reach'));
      expect(p.plan.status, PlanStatus.paused);

      // I'll walk to it instead.
      env.pingScript.add(PingStatus.received);
      await runner.useBluetoothPath(id);
      p = await progress(id);
      expect(p.plan.status, PlanStatus.running);
      expect(p.change!.phase, ChangePhase.ready);
      expect(p.change!.remote, isFalse);
      expect(p.current.step.params['bluetooth'], isTrue);
      expect(p.current.step.summary, contains('Bluetooth'));
      await runner.completeStep(id);
      await pump(300);
      expect(env.bluetoothBaseChanges, [('MEDIUM_FAST', null)]);
      expect(env.remoteChanges.length, 1, reason: 'no second remote try');
      expect(await currentKind(id), StepKind.walk);
    });

    test('remote path without a base backup refuses before touching anything',
        () async {
      env.remoteAdminMobileNode = env.myNodeId;
      final id = await toFirstChange(presets);
      env.originalBackup = false;
      await runner.completeStep(id);
      await pump(100);
      final p = await progress(id);
      expect(p.change!.phase, ChangePhase.failed);
      expect(p.change!.baseChanged, isFalse);
      expect(env.remoteChanges, isEmpty);
      expect(env.mobileChanges, isEmpty);
    });

    test('a NAK from the base is a failure with the base unchanged', () async {
      env.remoteAdminMobileNode = env.myNodeId;
      final id = await toFirstChange(presets);
      env.remoteError = StateError('NAK: not an admin key');
      await runner.completeStep(id);
      await pump(100);
      final p = await progress(id);
      expect(p.change!.phase, ChangePhase.failed);
      expect(p.change!.baseChanged, isFalse);
      expect(p.change!.failure, contains("didn't take the change"));
      expect(env.mobileChanges, isEmpty, reason: 'the mobile is never moved');
    });

    test('TX power on the mobile only changes the mobile', () async {
      final id = await toFirstChange(const PlanIntent(
          template: PlanTemplate.txPower, variants: ['20', '27']));
      var p = await progress(id);
      expect(p.change!.targetName, '20 dBm');
      expect(p.change!.remote, isFalse);
      env.pingScript.add(PingStatus.received);
      await runner.completeStep(id);
      await pump(200);
      expect(env.remoteChanges, isEmpty);
      expect(env.bluetoothBaseChanges, isEmpty);
      expect(env.mobileChanges, [('MEDIUM_FAST', 20)]);
      expect(await currentKind(id), StepKind.walk);
    });

    test('pausing mid-change stops the sequence', () async {
      env.remoteAdminMobileNode = env.myNodeId;
      final id = await toFirstChange(presets);
      unawaited(runner.completeStep(id));
      await pump(5);
      await runner.pause(id);
      final before = env.pingsAsked;
      await pump(200);
      expect(env.pingsAsked - before, lessThanOrEqualTo(1));
      expect((await progress(id)).plan.status, PlanStatus.paused);
    });
  });

  group('switchRadio', () {
    test('finishes when another radio is connected as the mobile', () async {
      final plan = await runner.createPlan(
          const PlanIntent(
              template: PlanTemplate.radios, variants: ['T1000-E', 'Heltec']),
          coverageMapId: mapId);
      await runner.start(plan.id);
      await pump();
      expect(await currentKind(plan.id), StepKind.switchRadio);
      env.connectedIsMobile = false;
      await expectLater(
          runner.completeStep(plan.id), throwsA(isA<PlanError>()));
      env.connectedIsMobile = true;
      env.myNodeId = 0x1234;
      env.setReady(true);
      await pump();
      expect(await currentKind(plan.id), StepKind.goTo);
    });
  });
}
