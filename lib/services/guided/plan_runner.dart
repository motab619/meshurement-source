// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:latlong2/latlong.dart';

import '../../data/database/app_database.dart';
import '../../data/radio/mesh_radio.dart';
import '../../utils/constants.dart' show AckStatus;
import '../../utils/user_errors.dart';
import '../gps_service.dart' show GpsStatus;
import '../session_manager.dart' show SessionStartError;
import 'base_change_sequence.dart';
import 'plan_analysis.dart';
import 'plan_builder.dart';
import 'plan_environment.dart';
import 'plan_models.dart';
import 'route_match.dart';

/// Guided test: the state machine behind Ask → Plan → Run → Result
/// (design `docs/design/guided-test/README.md` §3, §6).
///
/// One plan runs at a time. Everything that matters is in the database
/// (`test_plans`, `test_steps`, `sessions.test_step_id`), so a plan
/// survives the app being killed: [start] on a running or paused plan
/// resumes at `current_step`; a walk that was recording is ended and
/// walked again. Live state (checks, compass, walk HUD, radio-change
/// progress) is in memory and streamed per plan through [watch].
///
/// The runner talks to the app only through [PlanEnvironment], so its
/// behaviour is unit tested with a fake environment.
class PlanRunner implements PlanRunnerApi {
  PlanRunner(
    this._env, {
    DateTime Function()? clock,
    this.settleDuration = const Duration(seconds: 20),
    this.listenDuration = const Duration(seconds: 120),
    this.rollbackListenDuration = const Duration(seconds: 60),
    this.pingEvery = const Duration(seconds: 10),
    this.advanceDelay = const Duration(milliseconds: 800),
    this.tick = const Duration(seconds: 1),
    this.minWalk = const Duration(minutes: 2),
    this.minWalkPings = 10,
    this.arriveWithinM = 15,
  }) : _clock = clock ?? DateTime.now;

  final PlanEnvironment _env;
  final DateTime Function() _clock;

  /// Design §6 timings; tests shorten them.
  final Duration settleDuration;
  final Duration listenDuration;
  final Duration rollbackListenDuration;
  final Duration pingEvery;

  /// Pause between an automatic step finishing and the next one starting,
  /// so the person sees the green rows.
  final Duration advanceDelay;
  final Duration tick;

  /// A walk shorter than this, or with fewer pings, is "thin" (§3).
  final Duration minWalk;
  final int minWalkPings;
  final double arriveWithinM;

  /// Base heard within this long counts as "heard" for the remote path.
  static const baseHeardWithin = Duration(minutes: 10);

  /// Note the runner leaves on a thin walk; the UI offers "Walk this one
  /// again" when it sees it on the active step.
  static const thinWalkNote = 'thin walk';

  AppDatabase get _db => _env.db;

  _Run? _run;
  final _progress = <int, StreamController<PlanProgress>>{};
  Future<void> _chain = Future.value();
  bool _disposed = false;

  /// The plan running in memory right now, if any.
  int? get activePlanId => _run?.planId;

  // ─── API ──────────────────────────────────────────────────────────────

  @override
  Future<PlanRecord> createPlan(PlanIntent intent,
          {required int coverageMapId}) =>
      _serial(() async {
        final problem = intent.validate();
        if (problem != null) throw PlanError(problem);
        final remote = _remoteAvailable(intent);
        final steps = buildSteps(intent,
            remoteChanges: remote,
            protocol: _env.protocol.name,
            restoreTo: _currentSettingText(intent));
        final id = await _db.insertTestPlan(TestPlansCompanion.insert(
          coverageMapId: coverageMapId,
          title: planTitle(intent),
          template: intent.template.name,
          intentJson: jsonEncode(intent.toJson()),
          remoteChanges: Value(remote),
          createdAt: _clock(),
        ));
        await _db.insertTestSteps([for (final s in steps) _companion(id, s)]);
        return planRecordFrom((await _db.getTestPlan(id))!);
      });

  @override
  Future<List<StepRecord>> steps(int planId) async =>
      [for (final s in await _db.getTestSteps(planId)) stepRecordFrom(s)];

  @override
  Stream<List<PlanRecord>> watchPlans(int coverageMapId) => _db
      .watchTestPlansForMap(coverageMapId)
      .map((rows) => [for (final r in rows) planRecordFrom(r)]);

  @override
  Stream<PlanRecord?> watchActivePlan() => _db
      .watchActiveTestPlan()
      .map((p) => p == null ? null : planRecordFrom(p));

  @override
  Future<void> start(int planId) => _serial(() async {
        final plan = await _plan(planId);
        final status = PlanStatus.values.byName(plan.status);
        if (status == PlanStatus.done || status == PlanStatus.abandoned) {
          throw const PlanError('This test is finished.');
        }
        if (_run != null && _run!.planId != planId) {
          throw const PlanError('Finish or stop the other test first.');
        }
        if (_run != null && plan.status == PlanStatus.running.name) {
          return; // already running here: nothing to resume
        }
        // Another plan left "running" by a crash: it isn't.
        for (final other in await _db.getActiveTestPlans()) {
          if (other.id != planId && other.status == PlanStatus.running.name) {
            await _db.updateTestPlan(other.id,
                TestPlansCompanion(status: Value(PlanStatus.paused.name)));
          }
        }
        var steps = await _db.getTestSteps(planId);
        if (steps.isEmpty) throw const PlanError('This test has no steps.');
        final intent = _intentOf(plan);
        await _fillRestore(plan, intent, steps);
        steps = await _db.getTestSteps(planId);
        final run = _run ?? _Run(planId);
        _run = run;
        run.plan = plan;
        run.steps = steps;
        run.intent = intent;
        await _db.updateTestPlan(
            planId, TestPlansCompanion(status: Value(PlanStatus.running.name)));
        final ordinal = plan.currentStep.clamp(0, steps.length - 1);
        final step = steps[ordinal];
        if (step.kind == StepKind.walk.name && step.sessionId != null) {
          // Recording when the app died or the plan was paused: that walk
          // is over; the step is walked again.
          await _dropWalkSession(step, reason: 'restarted');
        }
        await _enterStep(run, ordinal);
      });

  @override
  Stream<PlanProgress> watch(int planId) async* {
    final run = _run;
    if (run != null && run.planId == planId && run.latest != null) {
      yield run.latest!;
    } else {
      yield await _snapshot(planId);
    }
    yield* _controller(planId).stream;
  }

  @override
  Future<void> completeStep(int planId) => _serial(() async {
        final run = _requireRun(planId);
        final step = run.current;
        switch (StepKind.values.byName(step.kind)) {
          case StepKind.preflight:
            final fail = run.preflight
                ?.where((r) => r.status == CheckStatus.fail)
                .firstOrNull;
            if (fail != null) {
              throw PlanError(
                  '${fail.label}: ${fail.detail.isEmpty ? 'not ready' : fail.detail}');
            }
            await _finishStep(run);
          case StepKind.swapHardware:
            await _finishStep(run);
          case StepKind.switchRadio:
            if (!_env.radioReady || !_env.connectedIsMobile) {
              throw const PlanError('Connect the other node first; it has '
                  'to be set up as the mobile node.');
            }
            await _finishStep(run);
          case StepKind.goTo:
            await _completeGoTo(run);
          case StepKind.walk:
            await _completeWalk(run);
          case StepKind.changeRadios:
            final phase = run.change?.phase;
            if (phase == ChangePhase.ready || phase == ChangePhase.failed) {
              unawaited(_runChange(run, run.gen));
            } else if (phase == ChangePhase.done) {
              await _finishStep(run);
            }
          case StepKind.settle:
          case StepKind.analyze:
            break;
        }
      });

  @override
  Future<void> redoStep(int planId) => _serial(() async {
        final run = _requireRun(planId);
        final step = run.current;
        if (step.kind != StepKind.walk.name) {
          throw const PlanError('Only a walk can be done again.');
        }
        if (run.session != null && !run.walkEnded) await _env.endSession();
        await _dropWalkSession(await _step(step.id), reason: 'walked again');
        await _enterStep(run, run.ordinal);
      });

  @override
  Future<void> skipStep(int planId) => _serial(() async {
        final run = _requireRun(planId);
        if (run.current.kind == StepKind.analyze.name) {
          throw const PlanError('The result cannot be skipped.');
        }
        if (run.session != null && !run.walkEnded) await _env.endSession();
        await _db.updateTestStep(
            run.current.id, const TestStepsCompanion(note: Value('skipped')));
        await _finishStep(run, status: StepStatus.skipped);
      });

  @override
  Future<void> useBluetoothPath(int planId) => _serial(() async {
        final run = _requireRun(planId);
        final step = run.current;
        final kind = StepKind.values.byName(step.kind);
        if (kind == StepKind.changeRadios) {
          final params = _params(step)..['bluetooth'] = true;
          final rebuilt = _rebuilt(run, remote: false)[run.ordinal];
          await _db.updateTestStep(
              step.id,
              TestStepsCompanion(
                paramsJson: Value(jsonEncode(params)),
                summary: Value(rebuilt.summary),
                instruction: Value(rebuilt.instruction),
              ));
          await _enterStep(run, run.ordinal);
        } else if (kind == StepKind.preflight) {
          await _db.updateTestPlan(
              planId, const TestPlansCompanion(remoteChanges: Value(false)));
          await _reload(run);
          await _retext(run, remote: false);
          await _runPreflight(run, run.gen);
        } else {
          throw const PlanError('Nothing to switch on this step.');
        }
      });

  @override
  Future<void> recheck(int planId) => _serial(() async {
        final run = _requireRun(planId);
        if (run.current.kind == StepKind.preflight.name) {
          await _runPreflight(run, run.gen);
        }
      });

  @override
  Future<void> pause(int planId) => _serial(() async {
        final run = _run;
        if (run == null || run.planId != planId) {
          final plan = await _plan(planId);
          if (plan.status == PlanStatus.running.name) {
            await _db.updateTestPlan(planId,
                TestPlansCompanion(status: Value(PlanStatus.paused.name)));
          }
          return;
        }
        await _stop(run, PlanStatus.paused);
      });

  @override
  Future<void> abandon(int planId) => _serial(() async {
        final run = _run;
        if (run != null && run.planId == planId) {
          await _stop(run, PlanStatus.abandoned);
          return;
        }
        final plan = await _plan(planId);
        if (plan.status == PlanStatus.done.name) {
          throw const PlanError('This test is already finished.');
        }
        await _db.updateTestPlan(
            planId,
            TestPlansCompanion(
                status: Value(PlanStatus.abandoned.name),
                finishedAt: Value(_clock())));
        await _emitSnapshot(planId);
      });

  @override
  Future<PlanAnalysisResult?> result(int planId) async =>
      decodePlanResult((await _db.getTestPlan(planId))?.resultJson);

  @override
  Future<void> renameVariant(int planId, int variant, String name) =>
      _serial(() async {
        final plan = await _plan(planId);
        final intent = _intentOf(plan);
        if (variant < 0 || variant >= intent.variants.length) {
          throw const PlanError('No such setup.');
        }
        final variants = [...intent.variants]..[variant] = name.trim();
        final renamed = intent.copyWith(variants: variants);
        final problem = renamed.validate();
        if (problem != null) throw PlanError(problem);
        final steps = await _db.getTestSteps(planId);
        final rebuilt = buildSteps(renamed,
            remoteChanges: plan.remoteChanges,
            protocol: _env.protocol.name,
            restoreTo: _restoreOf(steps));
        for (final s in steps) {
          if (s.status == StepStatus.done.name ||
              s.status == StepStatus.skipped.name) {
            continue;
          }
          if (s.ordinal >= rebuilt.length) break;
          final r = rebuilt[s.ordinal];
          if (r.kind.name != s.kind) continue;
          // Keep what the runner wrote into the params (ghost, start…).
          final params = _params(s)..addAll(r.params);
          await _db.updateTestStep(
              s.id,
              TestStepsCompanion(
                title: Value(r.title),
                instruction: Value(r.instruction),
                summary: Value(r.summary),
                paramsJson: Value(jsonEncode(params)),
              ));
        }
        await _db.updateTestPlan(
            planId,
            TestPlansCompanion(
                intentJson: Value(jsonEncode(renamed.toJson()))));
        final run = _run;
        if (run != null && run.planId == planId) {
          await _reload(run);
          _emit(run);
        } else {
          await _emitSnapshot(planId);
        }
      });

  @override
  Future<void> updateDraft(int planId, PlanIntent intent) => _serial(() async {
        final plan = await _plan(planId);
        if (plan.status != PlanStatus.draft.name) {
          throw const PlanError('Only a plan that has not started can be '
              'changed.');
        }
        final problem = intent.validate();
        if (problem != null) throw PlanError(problem);
        final remote = _remoteAvailable(intent);
        final steps = buildSteps(intent,
            remoteChanges: remote,
            protocol: _env.protocol.name,
            restoreTo: _currentSettingText(intent));
        await _db.replaceTestSteps(
            planId, [for (final s in steps) _companion(planId, s)]);
        await _db.updateTestPlan(
            planId,
            TestPlansCompanion(
              title: Value(planTitle(intent)),
              template: Value(intent.template.name),
              intentJson: Value(jsonEncode(intent.toJson())),
              remoteChanges: Value(remote),
            ));
        await _emitSnapshot(planId);
      });

  Future<void> dispose() async {
    _disposed = true;
    final run = _run;
    if (run != null) _cancelStepRuntime(run);
    _run = null;
    for (final c in _progress.values) {
      await c.close();
    }
    _progress.clear();
  }

  // ─── Plan bookkeeping ─────────────────────────────────────────────────

  Future<T> _serial<T>(Future<T> Function() f) {
    final next = _chain.then((_) => f());
    _chain = next.then((_) {}, onError: (_) {});
    return next;
  }

  _Run _requireRun(int planId) {
    final run = _run;
    if (run == null || run.planId != planId) {
      throw const PlanError('This test is not running. Tap Continue first.');
    }
    return run;
  }

  Future<TestPlan> _plan(int planId) async {
    final plan = await _db.getTestPlan(planId);
    if (plan == null) throw const PlanError('This test no longer exists.');
    return plan;
  }

  Future<TestStep> _step(int id) async {
    final steps = await _db.getTestSteps(_run!.planId);
    return steps.firstWhere((s) => s.id == id);
  }

  StreamController<PlanProgress> _controller(int planId) =>
      _progress.putIfAbsent(planId, StreamController<PlanProgress>.broadcast);

  Future<void> _reload(_Run run) async {
    run.plan = await _plan(run.planId);
    run.steps = await _db.getTestSteps(run.planId);
    run.intent = _intentOf(run.plan);
  }

  void _emit(_Run run) {
    if (_disposed) return;
    final p = _progressOf(run);
    run.latest = p;
    _controller(run.planId).add(p);
  }

  Future<void> _emitSnapshot(int planId) async {
    if (_disposed) return;
    final c = _progress[planId];
    if (c == null || !c.hasListener) return;
    try {
      c.add(await _snapshot(planId));
    } on PlanError {
      // Deleted: nothing to show.
    }
  }

  Future<PlanProgress> _snapshot(int planId) async {
    final plan = await _plan(planId);
    final steps = await _db.getTestSteps(planId);
    if (steps.isEmpty) throw const PlanError('This test has no steps.');
    final ordinal = plan.currentStep.clamp(0, steps.length - 1);
    final records = [for (final s in steps) stepRecordFrom(s)];
    return PlanProgress(
      plan: planRecordFrom(plan),
      steps: records,
      current: records[ordinal],
    );
  }

  PlanProgress _progressOf(_Run run) {
    final records = [for (final s in run.steps) stepRecordFrom(s)];
    final ordinal = run.ordinal.clamp(0, records.length - 1);
    return PlanProgress(
      plan: planRecordFrom(run.plan),
      steps: records,
      current: records[ordinal],
      preflight: run.preflight,
      goTo: run.goTo,
      walk: run.walk,
      change: run.change,
      settleRemainingSec: run.settleRemaining,
      analyzing: run.analyzing,
    );
  }

  /// Whether this plan may change the base from a distance right now:
  /// Meshtastic with the grant made for the radio in hand and the base
  /// heard lately.
  bool _remoteAvailable(PlanIntent intent) {
    if (!intent.template.changesRadios) return false;
    if (_env.protocol == RadioProtocol.meshcore) return false;
    if (!_env.supportsRemoteAdmin) return false;
    final granted = _env.remoteAdminMobileNode;
    if (granted == null || granted != _env.myNodeId) return false;
    return _baseHeardRecently();
  }

  bool _baseHeardRecently() {
    final t = _env.baseLastHeardAt;
    return t != null && _clock().difference(t) <= baseHeardWithin;
  }

  /// The setting the radios are on now, as the builder's `restoreTo`.
  String? _currentSettingText(PlanIntent intent) {
    if (!intent.template.changesRadios) return null;
    return intent.template == PlanTemplate.txPower
        ? _env.currentTxPowerDbm?.toString()
        : _env.currentPreset?.id;
  }

  /// A `restore` step's recorded setting, as text for the builder.
  String? _restoreOf(List<TestStep> steps) {
    for (final s in steps) {
      final p = _params(s);
      if (p['restore'] == true) {
        final preset = p['preset'];
        if (preset is String && preset.isNotEmpty) return preset;
        final tx = p['txPower'];
        if (tx is num) return tx.toInt().toString();
      }
    }
    return null;
  }

  /// At start, a restore step still missing its setting takes what the
  /// radios are on now (the setting from before the plan changes them).
  Future<void> _fillRestore(
      TestPlan plan, PlanIntent intent, List<TestStep> steps) async {
    if (!intent.template.changesRadios) return;
    if (_restoreOf(steps) != null) return;
    final now = _currentSettingText(intent);
    if (now == null) return;
    final rebuilt = buildSteps(intent,
        remoteChanges: plan.remoteChanges,
        protocol: _env.protocol.name,
        restoreTo: now);
    for (final s in steps) {
      final p = _params(s);
      if (p['restore'] != true || s.ordinal >= rebuilt.length) continue;
      final r = rebuilt[s.ordinal];
      await _db.updateTestStep(
          s.id,
          TestStepsCompanion(
            title: Value(r.title),
            paramsJson: Value(jsonEncode({...p, ...r.params})),
          ));
    }
  }

  List<PlanStep> _rebuilt(_Run run, {required bool remote}) =>
      buildSteps(run.intent,
          remoteChanges: remote,
          protocol: _env.protocol.name,
          restoreTo: _restoreOf(run.steps));

  /// Rewrite the words of every step still to come for the other base path.
  Future<void> _retext(_Run run, {required bool remote}) async {
    final rebuilt = _rebuilt(run, remote: remote);
    for (final s in run.steps) {
      if (s.status == StepStatus.done.name ||
          s.status == StepStatus.skipped.name ||
          s.ordinal >= rebuilt.length) {
        continue;
      }
      final r = rebuilt[s.ordinal];
      if (r.kind.name != s.kind) continue;
      await _db.updateTestStep(
          s.id,
          TestStepsCompanion(
            instruction: Value(r.instruction),
            summary: Value(r.summary),
          ));
    }
    await _reload(run);
  }

  // ─── Steps ────────────────────────────────────────────────────────────

  Future<void> _enterStep(_Run run, int ordinal) async {
    _cancelStepRuntime(run);
    run.gen++;
    final gen = run.gen;
    run.resetStepState();
    run.ordinal = ordinal;
    final step = run.steps[ordinal];
    await _db.updateTestPlan(
        run.planId,
        TestPlansCompanion(
            currentStep: Value(ordinal),
            status: Value(PlanStatus.running.name)));
    await _db.updateTestStep(
        step.id,
        TestStepsCompanion(
          status: Value(StepStatus.active.name),
          startedAt: Value(step.startedAt ?? _clock()),
          endedAt: const Value(null),
        ));
    await _reload(run);
    switch (StepKind.values.byName(step.kind)) {
      case StepKind.preflight:
        await _startPreflight(run, gen);
      case StepKind.swapHardware:
        break;
      case StepKind.switchRadio:
        _startSwitchRadio(run, gen);
      case StepKind.goTo:
        await _startGoTo(run);
      case StepKind.walk:
        _emit(run);
        await _startWalk(run, gen);
      case StepKind.changeRadios:
        await _startChange(run);
      case StepKind.settle:
        _startSettle(run, gen);
      case StepKind.analyze:
        run.analyzing = true;
        unawaited(_runAnalyze(run, gen));
    }
    _emit(run);
  }

  Future<void> _finishStep(_Run run,
      {StepStatus status = StepStatus.done}) async {
    final step = run.current;
    _cancelStepRuntime(run);
    await _db.updateTestStep(
        step.id,
        TestStepsCompanion(
            status: Value(status.name), endedAt: Value(_clock())));
    await _reload(run);
    if (run.ordinal + 1 < run.steps.length) {
      await _enterStep(run, run.ordinal + 1);
      return;
    }
    // A plan whose last step is not `analyze` (never built that way, but
    // never leave one hanging).
    await _db.updateTestPlan(
        run.planId,
        TestPlansCompanion(
            status: Value(PlanStatus.done.name), finishedAt: Value(_clock())));
    await _reload(run);
    _emit(run);
    _run = null;
  }

  /// Advance after a short beat, so an automatic step's last state shows.
  void _advanceSoon(_Run run, int gen) {
    run.timers.add(Timer(advanceDelay, () {
      if (_run != run || run.gen != gen) return;
      unawaited(_serial(() async {
        if (_run != run || run.gen != gen) return;
        await _finishStep(run);
      }));
    }));
  }

  void _cancelStepRuntime(_Run run) {
    for (final s in run.subs) {
      s.cancel();
    }
    run.subs.clear();
    for (final t in run.timers) {
      t.cancel();
    }
    run.timers.clear();
  }

  Future<void> _stop(_Run run, PlanStatus status) async {
    _cancelStepRuntime(run);
    run.gen++;
    if (run.session != null && !run.walkEnded) {
      final active = _env.activeSession;
      if (active != null && active.id == run.session!.id) {
        await _env.endSession();
      }
    }
    await _db.updateTestPlan(
        run.planId,
        TestPlansCompanion(
          status: Value(status.name),
          finishedAt: status == PlanStatus.abandoned
              ? Value(_clock())
              : const Value.absent(),
        ));
    _run = null;
    await _emitSnapshot(run.planId);
  }

  /// A walk step's session is over (crash, pause, redo): keep the session
  /// on the map, unlink it and say so on the step.
  Future<void> _dropWalkSession(TestStep step, {required String reason}) async {
    final sessionId = step.sessionId;
    if (sessionId == null) return;
    final session = await _db.getSessionById(sessionId);
    if (session != null && session.isActive) {
      final active = _env.activeSession;
      if (active != null && active.id == sessionId) {
        await _env.endSession();
      } else {
        await _db.endSession(sessionId);
      }
    }
    await _db.unlinkStepSession(step.id);
    final ended = await _db.getSessionById(sessionId);
    final secs = ended == null || ended.endedAt == null
        ? null
        : ended.endedAt!.difference(ended.startedAt).inSeconds;
    final tried = secs == null
        ? ''
        : secs >= 120
            ? '${(secs / 60).round()} min'
            : '$secs s';
    await _db.updateTestStep(
        step.id,
        TestStepsCompanion(
            note: Value(tried.isEmpty
                ? '$reason: the first try is kept as a session'
                : '$reason: first try was $tried')));
  }

  // ─── preflight ────────────────────────────────────────────────────────

  Future<void> _startPreflight(_Run run, int gen) async {
    unawaited(_env.ensureGps());
    run.subs.add(_env.gpsStates.listen((_) => _recheckSoon(run, gen)));
    run.subs.add(_env.radioReadyChanges.listen((_) => _recheckSoon(run, gen)));
    await _runPreflight(run, gen);
  }

  void _recheckSoon(_Run run, int gen) {
    if (_run != run || run.gen != gen) return;
    unawaited(_serial(() async {
      if (_run != run || run.gen != gen) return;
      await _runPreflight(run, gen);
    }));
  }

  Future<void> _runPreflight(_Run run, int gen) async {
    final rows = await preflightRows(run.plan, run.intent);
    if (_run != run || run.gen != gen) return;
    run.preflight = rows;
    _emit(run);
    final allOk = rows.every((r) => r.status == CheckStatus.ok);
    if (allOk) _advanceSoon(run, gen);
  }

  /// The "Checking your setup" rows for [plan]. Public so the UI can show
  /// the same list elsewhere (the Plan screen's readiness line).
  Future<List<CheckRow>> preflightRows(TestPlan plan, PlanIntent intent) async {
    final rows = <CheckRow>[];
    final changes = intent.template.changesRadios;
    final ready = _env.radioReady;

    rows.add(ready
        ? CheckRow(
            label: 'Mobile node connected',
            detail: _env.radioDisplayName,
            status: CheckStatus.ok)
        : const CheckRow(
            label: 'Mobile node connected',
            detail: 'Not connected',
            status: CheckStatus.fail,
            fix: PreflightFix.connectRadio));

    final base = _env.baseNodeNum;
    rows.add(base != null
        ? CheckRow(
            label: 'Base node known',
            detail: _env.baseLabel,
            status: CheckStatus.ok)
        : const CheckRow(
            label: 'Base node known',
            detail: 'Run Node Setup to choose the base',
            status: CheckStatus.fail,
            fix: PreflightFix.openRadioSetup));

    if (!ready) {
      rows.add(const CheckRow(
          label: 'Both on MeshTest, same setting',
          detail: 'Waiting for your node',
          status: CheckStatus.busy));
    } else if (!_env.onTestChannel) {
      rows.add(const CheckRow(
          label: 'Both on MeshTest, same setting',
          detail: 'Your node is not on MeshTest',
          status: CheckStatus.fail,
          fix: PreflightFix.openRadioSetup));
    } else {
      final mismatch = _env.setupMismatch;
      final preset = _env.currentPreset;
      rows.add(mismatch == null
          ? CheckRow(
              label: 'Both on MeshTest, same setting',
              detail: preset == null ? 'MeshTest' : preset.displayName,
              status: CheckStatus.ok)
          : CheckRow(
              label: 'Both on MeshTest, same setting',
              detail: 'Settings differ ($mismatch)',
              status: CheckStatus.fail,
              fix: PreflightFix.openRadioSetup));
    }

    if (!changes) {
      final b = _env.baseBeacon;
      final on = b != null && b.kind != BeaconKind.none && b.intervalSec > 0;
      rows.add(on
          ? CheckRow(
              label: 'Base beacon on',
              detail: '${_beaconName(b.kind)} · every ${b.intervalSec} s',
              status: CheckStatus.ok)
          : const CheckRow(
              label: 'Base beacon',
              detail: 'Off: pings alone measure the link',
              status: CheckStatus.warn,
              fix: PreflightFix.openRadioSetup));
    } else {
      final saved = await _env.hasOriginalBaseBackup();
      rows.add(saved
          ? const CheckRow(
              label: 'Base settings saved',
              detail: 'original backup',
              status: CheckStatus.ok)
          : CheckRow(
              label: 'Base settings saved',
              detail: 'No backup of the base yet',
              status: plan.remoteChanges ? CheckStatus.fail : CheckStatus.warn,
              fix: plan.remoteChanges
                  ? PreflightFix.walkToBaseInstead
                  : PreflightFix.openRadioSetup));
      if (plan.remoteChanges) {
        final granted = _env.supportsRemoteAdmin &&
            _env.remoteAdminMobileNode != null &&
            _env.remoteAdminMobileNode == _env.myNodeId;
        final heardAt = _env.baseLastHeardAt;
        final heard = _baseHeardRecently();
        rows.add(granted && heard
            ? CheckRow(
                label: 'Remote changes',
                detail: 'Enabled · base heard ${_ago(heardAt!)}',
                status: CheckStatus.ok)
            : !granted
                ? const CheckRow(
                    label: 'Remote changes',
                    detail: 'Not enabled on the base',
                    status: CheckStatus.warn,
                    fix: PreflightFix.enableRemoteAtBase)
                : const CheckRow(
                    label: 'Remote changes',
                    detail: 'Base not heard yet',
                    status: CheckStatus.warn,
                    fix: PreflightFix.walkToBaseInstead));
      } else {
        rows.add(CheckRow(
            label: 'Base changes',
            detail: _env.protocol == RadioProtocol.meshcore
                ? 'MeshCore: by Bluetooth, the plan walks you to the base'
                : 'Over Bluetooth: the plan walks you to the base',
            status: CheckStatus.ok));
      }
    }

    final map = await _db.getCoverageMap(plan.coverageMapId);
    final baseLoc = _mapBase(map);
    final here = _env.lastPosition;
    rows.add(baseLoc != null
        ? CheckRow(
            label: 'Base location',
            detail: here == null
                ? 'Known'
                : '${flatDistanceM(here, baseLoc).round()} m from here',
            status: CheckStatus.ok)
        : const CheckRow(
            label: 'Base location',
            detail: 'Set when you stand next to it',
            status: CheckStatus.warn,
            fix: PreflightFix.setBaseLocation));

    final gps = _env.gpsState;
    rows.add(switch (gps.status) {
      GpsStatus.fix => CheckRow(
          label: 'GPS',
          detail: '±${(gps.accuracy ?? 0).round()} m',
          status: CheckStatus.ok),
      GpsStatus.denied => const CheckRow(
          label: 'GPS',
          detail: 'Location permission is off',
          status: CheckStatus.fail),
      GpsStatus.off => const CheckRow(
          label: 'GPS',
          detail: 'Location Services are off',
          status: CheckStatus.fail),
      _ => const CheckRow(
          label: 'GPS', detail: 'getting a fix…', status: CheckStatus.busy),
    });
    return rows;
  }

  static String _beaconName(BeaconKind k) => switch (k) {
        BeaconKind.telemetry => 'telemetry',
        BeaconKind.rangeTest => 'test signal',
        BeaconKind.trace => 'link check',
        BeaconKind.none => 'off',
      };

  String _ago(DateTime t) {
    final d = _clock().difference(t);
    if (d.inSeconds < 90) return '${d.inSeconds} s ago';
    return '${d.inMinutes} min ago';
  }

  // ─── switchRadio ──────────────────────────────────────────────────────

  void _startSwitchRadio(_Run run, int gen) {
    run.nodeAtEntry = _env.myNodeId;
    run.subs.add(_env.radioReadyChanges.listen((ready) {
      if (_run != run || run.gen != gen || !ready) return;
      if (_env.connectedIsMobile && _env.myNodeId != run.nodeAtEntry) {
        unawaited(_serial(() async {
          if (_run != run || run.gen != gen) return;
          await _finishStep(run);
        }));
      }
    }));
  }

  // ─── goTo ─────────────────────────────────────────────────────────────

  Future<void> _startGoTo(_Run run) async {
    final params = _params(run.current);
    final map = await _db.getCoverageMap(run.plan.coverageMapId);
    final baseLoc = _mapBase(map);
    final start = _startPin(run);
    final toBase = params['target'] == 'base';
    final target = toBase ? baseLoc : (start ?? baseLoc);
    run.goToTarget = target;
    run.goToSetsBase = baseLoc == null && (toBase || start == null);
    _updateGoTo(run, _env.lastPosition);
    run.subs.add(_env.positions.listen((p) {
      _updateGoTo(run, p);
      _emit(run);
    }));
  }

  void _updateGoTo(_Run run, LatLng? here) {
    final target = run.goToTarget;
    double? dist, bearing;
    if (target != null && here != null) {
      dist = flatDistanceM(here, target);
      bearing = bearingDeg(here, target);
    }
    run.goTo = GoToState(
      target: target,
      distanceM: dist,
      bearingDeg: bearing,
      arrived: dist != null && dist <= arriveWithinM,
      setsBaseLocation: run.goToSetsBase,
    );
  }

  Future<void> _completeGoTo(_Run run) async {
    if (run.goToSetsBase) {
      final here = _env.lastPosition;
      if (here == null) {
        throw const PlanError('Waiting for a GPS fix to mark where the base '
            'stands. Give it a moment, then tap again.');
      }
      await _db.setMapBaseLocation(
          run.plan.coverageMapId, here.latitude, here.longitude);
    }
    await _finishStep(run);
  }

  // ─── walk ─────────────────────────────────────────────────────────────

  Future<void> _startWalk(_Run run, int gen) async {
    final step = run.current;
    final params = _params(step);
    final variant = step.variant;
    final rigs = await _rigsForVariant(run, variant);
    final n = (params['walk'] as num?)?.toInt() ?? 1;
    final total = (params['walks'] as num?)?.toInt() ?? 1;
    final vname = variant == null ? '' : variantName(run.intent, variant);
    final name = [
      run.plan.title,
      '$n of $total',
      if (vname.isNotEmpty) vname,
    ].join(' · ');
    final planned =
        ((params['minutes'] as num?)?.toInt() ?? run.intent.route.minutes) * 60;
    run.ghost = _ghostRoute(run);
    run.matcher = RouteMatcher(run.ghost);
    run.track = TrackBuilder();
    run.walk = WalkState(plannedSec: planned, ghostRoute: run.ghost);
    Session session;
    try {
      session = await _env.startSession(
        coverageMapId: run.plan.coverageMapId,
        name: name,
        mobileRigId: rigs.$1,
        baseRigId: rigs.$2,
      );
    } on SessionStartError catch (e) {
      await _db.updateTestStep(
          step.id, TestStepsCompanion(note: Value(e.message)));
      await _reload(run);
      _emit(run);
      throw PlanError(e.message);
    } catch (e) {
      final msg = userMessage(e);
      await _db.updateTestStep(step.id, TestStepsCompanion(note: Value(msg)));
      await _reload(run);
      _emit(run);
      throw PlanError(msg);
    }
    if (_run != run || run.gen != gen) return;
    await _db.linkSessionToStep(step.id, session.id);
    if (step.note.isNotEmpty && step.note != thinWalkNote) {
      // A start error from a previous try is no longer true.
      if (step.note.startsWith('Radio') ||
          step.note.startsWith('Node') ||
          step.note.startsWith('Your node') ||
          step.note.contains('Location')) {
        await _db.updateTestStep(
            step.id, const TestStepsCompanion(note: Value('')));
      }
    }
    await _reload(run);
    run.session = session;
    run.walkEnded = false;
    run.walkStartedAt = _clock();
    final here = _env.lastPosition;
    if (here != null) _onWalkPosition(run, here);

    run.subs.add(_env.positions.listen((p) {
      _onWalkPosition(run, p);
      _emitWalk(run);
    }));
    run.subs.add(_env.pings.listen((s) {
      run.pingsSent++;
      if (s.status == AckStatus.received || s.status == AckStatus.implicit) {
        run.pingsAnswered++;
      }
      if (s.status == AckStatus.received && s.fromBase) {
        run.baseHeard = true;
        run.baseLastHeard = s.answeredAt;
        if (s.snr != null) run.lastSnr = s.snr;
      }
      _emitWalk(run);
    }));
    run.subs.add(_env.signals.listen((e) {
      final base = _env.baseNodeNum;
      if (base != null && e.sourceNodeId != base) return;
      run.baseHeard = true;
      run.baseLastHeard = e.timestamp;
      if (e.rxSnr != null) run.lastSnr = e.rxSnr;
      _emitWalk(run);
    }));
    run.subs.add(_env.sessionStream.listen((s) {
      if (run.walkEnded || run.session == null) return;
      if (s == null || s.id != run.session!.id) {
        // Ended from outside (out of range, ride-along, the Live tab).
        unawaited(_serial(() async {
          if (_run != run || run.gen != gen || run.walkEnded) return;
          final ok = await _endWalk(run, external: true);
          if (ok) await _finishStep(run);
        }));
      }
    }));
    run.timers.add(Timer.periodic(tick, (_) => _emitWalk(run)));
    _emitWalk(run);
  }

  void _onWalkPosition(_Run run, LatLng p) {
    final track = run.track;
    if (track == null || run.walkEnded) return;
    if (!track.add(p)) return;
    run.matcher?.addPoint(p);
    if (!run.startStored && _startPin(run) == null) {
      // The first walk's first fix is the plan's start pin.
      run.startStored = true;
      // Serialised with the step's other writes; errors are swallowed there.
      unawaited(_mergeParams(run, run.current.id, {
        'start': [p.latitude, p.longitude]
      }));
    }
  }

  void _emitWalk(_Run run) {
    if (_run != run || run.walk == null) return;
    final elapsed = run.walkStartedAt == null
        ? 0
        : _clock().difference(run.walkStartedAt!).inSeconds;
    final planned = run.walk!.plannedSec;
    final match = run.matcher?.pct;
    run.walk = WalkState(
      sessionId: run.session?.id,
      elapsedSec: elapsed,
      plannedSec: planned,
      routeMatchPct: match,
      pingsSent: run.pingsSent,
      pingsAnswered: run.pingsAnswered,
      baseHeard: run.baseHeard,
      baseLastHeardAt: run.baseLastHeard,
      lastSnr: run.lastSnr,
      ghostRoute: run.ghost,
      track: List.unmodifiable(run.track?.points ?? const <LatLng>[]),
      canFinish:
          (match != null && match >= routeMatchDonePct) || elapsed >= planned,
    );
    _emit(run);
  }

  Future<void> _completeWalk(_Run run) async {
    if (run.session == null) {
      // The session never started (radio, GPS): try again.
      await _startWalk(run, run.gen);
      _emit(run);
      return;
    }
    if (!run.walkEnded) {
      final ok = await _endWalk(run);
      if (!ok) return; // thin: the UI offers keep / walk again
    } else if (run.current.note == thinWalkNote) {
      // Kept after all.
      await _db.updateTestStep(
          run.current.id,
          TestStepsCompanion(
              note: Value('kept a short walk: ${_walkSummary(run)}')));
    }
    await _finishStep(run);
  }

  String _walkSummary(_Run run) {
    final secs = run.walkStartedAt == null
        ? 0
        : (run.walkEndedAt ?? _clock())
            .difference(run.walkStartedAt!)
            .inSeconds;
    return '$secs s, ${run.pingsCounted ?? run.pingsSent} pings';
  }

  /// End the walk's session and judge it. False when it is thin: the step
  /// stays active with [thinWalkNote] so the UI can offer "Walk this one
  /// again" ([redoStep]) or keep it ([completeStep]).
  Future<bool> _endWalk(_Run run, {bool external = false}) async {
    final session = run.session!;
    for (final t in run.timers) {
      t.cancel();
    }
    run.timers.clear();
    if (!external) {
      final active = _env.activeSession;
      if (active != null && active.id == session.id) await _env.endSession();
    }
    run.walkEnded = true;
    run.walkEndedAt = _clock();
    final ended = await _db.getSessionById(session.id);
    final secs = ended?.endedAt == null
        ? (run.walkStartedAt == null
            ? 0
            : run.walkEndedAt!.difference(run.walkStartedAt!).inSeconds)
        : ended!.endedAt!.difference(ended.startedAt).inSeconds;
    final pings = (await _db.getPingsForSession(session.id)).length;
    run.pingsCounted = math.max(pings, run.pingsSent);

    final step = run.current;
    final patch = <String, dynamic>{
      'durationSec': secs,
      'pings': run.pingsCounted,
    };
    final match = run.matcher?.pct;
    if (match != null) patch['match'] = (match * 10).round() / 10;
    if (run.ghost.isEmpty) {
      // This walk sets the route the next ones follow.
      final route = resampleRoute(run.track?.points ?? const []);
      if (route.isNotEmpty) patch['ghost'] = routeToJson(route);
    }
    final thin = secs < minWalk.inSeconds || run.pingsCounted! < minWalkPings;
    await _mergeParams(run, step.id, patch);
    if (thin) {
      await _db.updateTestStep(
          step.id, const TestStepsCompanion(note: Value(thinWalkNote)));
    }
    await _reload(run);
    _emitWalk(run);
    return !thin;
  }

  /// The first finished walk's route, resampled (empty on the first walk).
  List<LatLng> _ghostRoute(_Run run) {
    for (final s in run.steps) {
      if (s.kind != StepKind.walk.name || s.id == run.current.id) continue;
      final g = _params(s)['ghost'];
      if (g is List && g.isNotEmpty) return routeFromJson(g);
    }
    return const [];
  }

  /// Where the first walk started, once known.
  LatLng? _startPin(_Run run) {
    for (final s in run.steps) {
      if (s.kind != StepKind.walk.name) continue;
      final p = _params(s)['start'];
      if (p is List && p.length == 2 && p[0] is num && p[1] is num) {
        return LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble());
      }
    }
    return null;
  }

  /// Rig profiles for a walk's variant: antennas and radios get a profile
  /// named after the variant (made if missing, role per side); range and
  /// power tests change no hardware.
  Future<(int?, int?)> _rigsForVariant(_Run run, int? variant) async {
    final intent = run.intent;
    if (variant == null) return (null, null);
    if (intent.template != PlanTemplate.antennas &&
        intent.template != PlanTemplate.radios) {
      return (null, null);
    }
    final name = variantName(intent, variant);
    if (name.isEmpty) return (null, null);
    final side =
        intent.template == PlanTemplate.radios ? PlanSide.mobile : intent.side;
    var rig = await _db.findRigProfileByName(name);
    if (rig == null) {
      final now = _clock();
      final id = await _db.insertRigProfile(RigProfilesCompanion.insert(
        name: name,
        role: Value(side.name),
        antennaName:
            Value(intent.template == PlanTemplate.antennas ? name : ''),
        radioModel: Value(intent.template == PlanTemplate.radios ? name : ''),
        notes: const Value('Made by a guided test'),
        createdAt: now,
        updatedAt: now,
      ));
      rig = await _db.getRigProfile(id);
    }
    final id = rig?.id;
    return side == PlanSide.base ? (null, id) : (id, null);
  }

  // ─── changeRadios (design §6) ─────────────────────────────────────────

  Future<void> _startChange(_Run run) async {
    final step = run.current;
    var params = _params(step);
    final baseChanges = _baseChanges(run.intent, params);
    final remote = run.plan.remoteChanges &&
        params['bluetooth'] != true &&
        baseChanges &&
        _env.protocol != RadioProtocol.meshcore;
    if (params['fromPreset'] == null && params['fromTxPower'] == null) {
      params = {
        ...params,
        if (_env.currentPreset != null) 'fromPreset': _env.currentPreset!.id,
        if (_env.currentTxPowerDbm != null)
          'fromTxPower': _env.currentTxPowerDbm,
      };
      await _db.updateTestStep(
          step.id, TestStepsCompanion(paramsJson: Value(jsonEncode(params))));
      await _reload(run);
    }
    final map = await _db.getCoverageMap(run.plan.coverageMapId);
    final baseLoc = _mapBase(map);
    final here = _env.lastPosition;
    run.changeRows = [];
    run.change = ChangeState(
      phase: ChangePhase.ready,
      remote: remote,
      baseDistanceM:
          baseLoc == null || here == null ? null : flatDistanceM(here, baseLoc),
      targetName: _targetName(run.intent, params),
    );
  }

  static bool _baseChanges(PlanIntent intent, Map<String, dynamic> params) =>
      intent.template == PlanTemplate.rangeSettings ||
      params['side'] == PlanSide.base.name;

  static bool _mobileChanges(PlanIntent intent, Map<String, dynamic> params) =>
      intent.template == PlanTemplate.rangeSettings ||
      params['side'] != PlanSide.base.name;

  String _targetName(PlanIntent intent, Map<String, dynamic> params) {
    final preset = params['preset'];
    if (preset is String && preset.isNotEmpty) return presetDisplayName(preset);
    final tx = params['txPower'];
    if (tx is num) return '${tx.toInt()} dBm';
    return params['restore'] == true ? 'the setting from before' : '';
  }

  void _setPhase(_Run run, ChangePhase phase,
      {String? failure, bool? baseChanged}) {
    final c = run.change!;
    run.change = ChangeState(
      phase: phase,
      rows: List.unmodifiable(run.changeRows),
      remote: c.remote,
      baseDistanceM: c.baseDistanceM,
      targetName: c.targetName,
      failure: failure ?? (phase == ChangePhase.failed ? c.failure : null),
      baseChanged:
          baseChanged ?? (phase == ChangePhase.failed ? c.baseChanged : null),
    );
    _emit(run);
  }

  void _row(_Run run, String label, String detail, CheckStatus status) {
    final rows = run.changeRows;
    final i = rows.indexWhere((r) => r.label == label);
    final row = CheckRow(label: label, detail: detail, status: status);
    if (i >= 0) {
      rows[i] = row;
    } else {
      rows.add(row);
    }
    run.change = ChangeState(
      phase: run.change!.phase,
      rows: List.unmodifiable(rows),
      remote: run.change!.remote,
      baseDistanceM: run.change!.baseDistanceM,
      targetName: run.change!.targetName,
      failure: run.change!.failure,
      baseChanged: run.change!.baseChanged,
    );
    _emit(run);
  }

  bool _stale(_Run run, int gen) => _run != run || run.gen != gen;

  Future<void> _runChange(_Run run, int gen) async {
    if (run.changeBusy) return;
    run.changeBusy = true;
    try {
      final step = run.current;
      final params = _params(step);
      final intent = run.intent;
      final preset = params['preset'] is String
          ? presetFromId(params['preset'] as String)
          : null;
      final txPower = (params['txPower'] as num?)?.toInt();
      if (preset == null && txPower == null) {
        _row(run, 'Nothing to change', 'The setting is not known',
            CheckStatus.fail);
        _setPhase(run, ChangePhase.failed,
            failure: 'The setting to apply is not known. Skip this step or '
                'stop the test.',
            baseChanged: false);
        await _pausePlan(run);
        return;
      }
      run.changeRows = [];
      final result = await BaseChangeSequence(
        _env,
        clock: _clock,
        settleDuration: settleDuration,
        listenDuration: listenDuration,
        rollbackListenDuration: rollbackListenDuration,
        pingEvery: pingEvery,
        tick: tick,
      ).run(
        BaseChangeRequest(
          preset: preset,
          txPowerDbm: txPower,
          oldPreset: params['fromPreset'] is String
              ? presetFromId(params['fromPreset'] as String)
              : null,
          oldTxPowerDbm: (params['fromTxPower'] as num?)?.toInt(),
          changeBase: _baseChanges(intent, params),
          changeMobile: _mobileChanges(intent, params),
          remote: run.change!.remote,
          targetName: run.change!.targetName,
        ),
        onPhase: (p) => _setPhase(run, p),
        onRow: (label, detail, status) => _row(run, label, detail, status),
        onSettle: (left) => run.settleRemaining = left,
        cancelled: () => _stale(run, gen),
      );
      if (result == null || _stale(run, gen)) return;
      if (result.ok) {
        _setPhase(run, ChangePhase.done);
        _advanceSoon(run, gen);
        return;
      }
      _setPhase(run, ChangePhase.failed,
          failure: result.failure, baseChanged: result.baseChanged);
      await _pausePlan(run);
    } finally {
      run.changeBusy = false;
    }
  }

  /// The plan stops here (status paused) but the step's state stays on
  /// screen; [start] or [useBluetoothPath] picks it up again.
  Future<void> _pausePlan(_Run run) async {
    await _db.updateTestPlan(
        run.planId, TestPlansCompanion(status: Value(PlanStatus.paused.name)));
    await _reload(run);
    _emit(run);
  }

  // ─── settle ───────────────────────────────────────────────────────────

  void _startSettle(_Run run, int gen) {
    final secs = (_params(run.current)['seconds'] as num?)?.toInt() ??
        settleDuration.inSeconds;
    run.settleRemaining = secs;
    run.timers.add(Timer.periodic(tick, (t) {
      if (_stale(run, gen)) {
        t.cancel();
        return;
      }
      run.settleRemaining = math.max(0, (run.settleRemaining ?? 0) - 1);
      _emit(run);
      if (run.settleRemaining == 0) {
        t.cancel();
        unawaited(_serial(() async {
          if (_stale(run, gen)) return;
          await _finishStep(run);
        }));
      }
    }));
  }

  // ─── analyze ──────────────────────────────────────────────────────────

  Future<void> _runAnalyze(_Run run, int gen) async {
    try {
      final result = await analyzePlan(_db,
          plan: planRecordFrom(run.plan),
          steps: [for (final s in run.steps) stepRecordFrom(s)]);
      if (_stale(run, gen)) return;
      await _serial(() async {
        if (_stale(run, gen)) return;
        await _db.updateTestStep(
            run.current.id,
            TestStepsCompanion(
                status: Value(StepStatus.done.name), endedAt: Value(_clock())));
        await _db.storeTestPlanResult(run.planId, encodePlanResult(result));
        run.analyzing = false;
        await _reload(run);
        _cancelStepRuntime(run);
        _emit(run);
        _run = null;
      });
    } catch (e) {
      if (_stale(run, gen)) return;
      await _serial(() async {
        if (_stale(run, gen)) return;
        run.analyzing = false;
        await _db.updateTestStep(
            run.current.id,
            TestStepsCompanion(
                note: Value('Could not analyse: ${userMessage(e)}')));
        await _pausePlan(run);
      });
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────

  /// Merge [patch] into a step's params, one write after another (the
  /// start pin lands from a position callback while the walk's end writes
  /// the ghost route; neither may drop the other's keys).
  Future<void> _mergeParams(_Run run, int stepId, Map<String, dynamic> patch) {
    run.paramWrites = run.paramWrites.then((_) async {
      final rows = await _db.getTestSteps(run.planId);
      final row = rows.where((s) => s.id == stepId).firstOrNull;
      if (row == null) return;
      final params = _params(row)..addAll(patch);
      await _db.updateTestStep(
          stepId, TestStepsCompanion(paramsJson: Value(jsonEncode(params))));
    }, onError: (_) {});
    return run.paramWrites;
  }

  static Map<String, dynamic> _params(TestStep s) {
    try {
      final j = jsonDecode(s.paramsJson);
      return j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static PlanIntent _intentOf(TestPlan p) {
    try {
      return PlanIntent.fromJson(
          Map<String, dynamic>.from(jsonDecode(p.intentJson) as Map));
    } catch (_) {
      return PlanIntent(
          template: PlanTemplate.fromId(p.template) ?? PlanTemplate.antennas,
          variants: const ['A', 'B']);
    }
  }

  static LatLng? _mapBase(CoverageMap? map) =>
      map?.baseLat == null || map?.baseLon == null
          ? null
          : LatLng(map!.baseLat!, map.baseLon!);

  static TestStepsCompanion _companion(int planId, PlanStep s) =>
      TestStepsCompanion.insert(
        planId: planId,
        ordinal: s.ordinal,
        kind: s.kind.name,
        variant: Value(s.variant),
        title: s.title,
        instruction: s.instruction,
        summary: Value(s.summary),
        paramsJson: Value(jsonEncode(s.params)),
      );
}

/// The contract's view of a stored plan.
PlanRecord planRecordFrom(TestPlan p) => PlanRecord(
      id: p.id,
      coverageMapId: p.coverageMapId,
      title: p.title,
      intent: PlanRunner._intentOf(p),
      status: PlanStatus.values.firstWhere((s) => s.name == p.status,
          orElse: () => PlanStatus.draft),
      currentStep: p.currentStep,
      remoteChanges: p.remoteChanges,
      createdAt: p.createdAt,
      finishedAt: p.finishedAt,
    );

/// The contract's view of a stored step.
StepRecord stepRecordFrom(TestStep s) => StepRecord(
      id: s.id,
      step: PlanStep(
        ordinal: s.ordinal,
        kind: StepKind.values.firstWhere((k) => k.name == s.kind,
            orElse: () => StepKind.preflight),
        variant: s.variant,
        title: s.title,
        instruction: s.instruction,
        summary: s.summary,
        params: PlanRunner._params(s),
      ),
      status: StepStatus.values.firstWhere((st) => st.name == s.status,
          orElse: () => StepStatus.todo),
      sessionId: s.sessionId,
      startedAt: s.startedAt,
      endedAt: s.endedAt,
      note: s.note,
    );

/// The running plan's in-memory state.
class _Run {
  _Run(this.planId);

  final int planId;
  late TestPlan plan;
  late List<TestStep> steps;
  late PlanIntent intent;
  int ordinal = 0;

  /// Bumped on every step change; async work checks it before touching
  /// state.
  int gen = 0;
  PlanProgress? latest;

  /// Param writes in order (see `_mergeParams`).
  Future<void> paramWrites = Future.value();

  final subs = <StreamSubscription<dynamic>>[];
  final timers = <Timer>[];

  TestStep get current => steps[ordinal.clamp(0, steps.length - 1)];

  // Step state.
  List<CheckRow>? preflight;
  GoToState? goTo;
  LatLng? goToTarget;
  bool goToSetsBase = false;
  WalkState? walk;
  ChangeState? change;
  List<CheckRow> changeRows = [];
  bool changeBusy = false;
  int? settleRemaining;
  bool analyzing = false;
  int? nodeAtEntry;

  // Walk runtime.
  Session? session;
  bool walkEnded = false;
  DateTime? walkStartedAt;
  DateTime? walkEndedAt;
  TrackBuilder? track;
  RouteMatcher? matcher;
  List<LatLng> ghost = const [];
  int pingsSent = 0;
  int pingsAnswered = 0;
  int? pingsCounted;
  bool baseHeard = false;
  DateTime? baseLastHeard;
  double? lastSnr;
  bool startStored = false;

  void resetStepState() {
    preflight = null;
    goTo = null;
    goToTarget = null;
    goToSetsBase = false;
    walk = null;
    change = null;
    changeRows = [];
    changeBusy = false;
    settleRemaining = null;
    analyzing = false;
    nodeAtEntry = null;
    session = null;
    walkEnded = false;
    walkStartedAt = null;
    walkEndedAt = null;
    track = null;
    matcher = null;
    ghost = const [];
    pingsSent = 0;
    pingsAnswered = 0;
    pingsCounted = null;
    baseHeard = false;
    baseLastHeard = null;
    lastSnr = null;
    startStored = false;
  }
}
