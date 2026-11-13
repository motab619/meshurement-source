// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

/// Guided test: the shared vocabulary (design: `docs/design/guided-test/`).
///
/// This file is the contract between the pieces built in parallel:
///
/// * `plan_builder.dart` / `plan_runner.dart` / `plan_analysis.dart` (the
///   engine: intent → steps, running them, the result),
/// * `plan_intent_parser.dart` (chips and the AI helper → [PlanIntent]),
/// * `lib/ui/screens/guided/` (Ask, Plan, Run, Result),
/// * the remote-admin additions on `MeshRadio`.
///
/// Everything here is plain Dart: no drift rows, no Flutter, no Riverpod,
/// so it can be used from tests and from every layer. Keep additions
/// backwards compatible; every side depends on these names.
library;

import 'package:latlong2/latlong.dart';

// ─── What the user wants ───────────────────────────────────────────────

/// The five tests the app knows how to run (design §2).
enum PlanTemplate {
  /// The antenna on one radio changes between walks.
  antennas('Compare antennas'),

  /// Modem preset (Meshtastic) or modulation ladder step (MeshCore) on
  /// both radios changes between walks.
  rangeSettings('Compare range settings'),

  /// The mobile radio itself is swapped between walks.
  radios('Compare two nodes'),

  /// TX power on one radio changes between walks.
  txPower('Compare TX power'),

  /// One walk, no variants: how far does the current setup reach.
  reach('How far does it reach?');

  const PlanTemplate(this.chip);

  /// Chip label on the Ask screen.
  final String chip;

  /// Templates whose variants change a radio's settings (the app does it).
  bool get changesRadios => this == rangeSettings || this == txPower;

  static PlanTemplate? fromId(String id) {
    for (final t in values) {
      if (t.name == id) return t;
    }
    return null;
  }
}

/// Which radio the variable is on.
enum PlanSide { mobile, base }

enum RouteKind { walk, drive }

class PlanRoute {
  final RouteKind kind;

  /// Planned length of one pass, in minutes.
  final int minutes;

  const PlanRoute({this.kind = RouteKind.walk, this.minutes = 12});

  Map<String, dynamic> toJson() => {'kind': kind.name, 'minutes': minutes};

  factory PlanRoute.fromJson(Map<String, dynamic> j) => PlanRoute(
        kind: RouteKind.values.firstWhere((k) => k.name == j['kind'],
            orElse: () => RouteKind.walk),
        minutes: (j['minutes'] as num?)?.toInt() ?? 12,
      );
}

/// Limits every side agrees on.
abstract final class PlanLimits {
  static const minVariants = 2;
  static const maxVariants = 4;

  /// Variants beyond this many need Pro (`ProFeature.guidedTests`).
  static const freeVariants = 2;
  static const minRouteMinutes = 5;
  static const maxRouteMinutes = 60;
}

/// The Ask screen's output: which template, with what filled in. Built by
/// a chip, by the AI helper, or by hand; validated by [validate] before a
/// plan is built from it.
class PlanIntent {
  final PlanTemplate template;
  final PlanSide side;

  /// Names of the things compared, in walk order. What they hold depends
  /// on the template:
  ///
  /// * `antennas`: antenna names ("Stock whip", "5.8 dBi fiberglass"),
  /// * `rangeSettings`: preset ids (`RadioPreset.id`: "MEDIUM_FAST", or a
  ///   MeshCore ladder id like "MC_SF9_BW125_CR5"),
  /// * `radios`: radio display names,
  /// * `txPower`: dBm as text ("20"),
  /// * `reach`: exactly one entry, the current setup's name.
  final List<String> variants;

  /// Second pass in the other order (A, B, B, A).
  final bool repeat;
  final PlanRoute route;

  /// What the user typed, kept for the result's AI card. Never positions.
  final String? question;

  const PlanIntent({
    required this.template,
    this.side = PlanSide.mobile,
    required this.variants,
    this.repeat = false,
    this.route = const PlanRoute(),
    this.question,
  });

  /// One line describing what is wrong, or null when a plan can be built.
  String? validate() {
    final n = variants.length;
    if (template == PlanTemplate.reach) {
      if (n != 1) return 'A reach test has one setup, not $n.';
    } else {
      if (n < PlanLimits.minVariants) {
        return 'Name at least two things to compare.';
      }
      if (n > PlanLimits.maxVariants) {
        return 'Up to ${PlanLimits.maxVariants} setups in one test.';
      }
    }
    final trimmed = variants.map((v) => v.trim()).toList();
    if (trimmed.any((v) => v.isEmpty)) return 'Every setup needs a name.';
    if (trimmed.map((v) => v.toLowerCase()).toSet().length != n) {
      return 'Two setups have the same name.';
    }
    if (template == PlanTemplate.radios && side == PlanSide.base) {
      return 'Nodes are compared on the mobile side.';
    }
    if (template == PlanTemplate.txPower) {
      for (final v in trimmed) {
        final dbm = int.tryParse(v);
        if (dbm == null || dbm < 0 || dbm > 30) {
          return 'TX power is a number of dBm, 0 to 30.';
        }
      }
    }
    if (route.minutes < PlanLimits.minRouteMinutes ||
        route.minutes > PlanLimits.maxRouteMinutes) {
      return 'A pass is ${PlanLimits.minRouteMinutes} to '
          '${PlanLimits.maxRouteMinutes} minutes.';
    }
    return null;
  }

  /// Whether this intent needs Pro (3+ variants).
  bool get needsPro => variants.length > PlanLimits.freeVariants;

  PlanIntent copyWith({
    PlanTemplate? template,
    PlanSide? side,
    List<String>? variants,
    bool? repeat,
    PlanRoute? route,
    String? question,
  }) =>
      PlanIntent(
        template: template ?? this.template,
        side: side ?? this.side,
        variants: variants ?? this.variants,
        repeat: repeat ?? this.repeat,
        route: route ?? this.route,
        question: question ?? this.question,
      );

  Map<String, dynamic> toJson() => {
        'template': template.name,
        'side': side.name,
        'variants': variants,
        'repeat': repeat,
        'route': route.toJson(),
        if (question != null) 'question': question,
      };

  factory PlanIntent.fromJson(Map<String, dynamic> j) => PlanIntent(
        template: PlanTemplate.fromId(j['template'] as String? ?? '') ??
            PlanTemplate.antennas,
        side: PlanSide.values.firstWhere((s) => s.name == j['side'],
            orElse: () => PlanSide.mobile),
        variants: (j['variants'] as List?)?.map((e) => '$e').toList() ?? [],
        repeat: j['repeat'] == true,
        route: j['route'] is Map
            ? PlanRoute.fromJson(Map<String, dynamic>.from(j['route'] as Map))
            : const PlanRoute(),
        question: j['question'] as String?,
      );
}

// ─── The plan ──────────────────────────────────────────────────────────

/// What a step is (design §3). ⚙ automatic, 🙋 the person, 🚶 a recorded walk.
enum StepKind {
  /// ⚙ Checks the setup; rows with fixes.
  preflight,

  /// 🙋 "Put the X on": the person swaps hardware on one radio.
  swapHardware,

  /// 🙋 Connect the other radio (template `radios`).
  switchRadio,

  /// ⚙ The app changes the radios (base first, then the mobile).
  changeRadios,

  /// 🙋 Walk to the start point / stand near the base.
  goTo,

  /// 🚶 A recorded session.
  walk,

  /// ⚙ A short wait after a change or a reboot.
  settle,

  /// ⚙ Compute the result.
  analyze;

  bool get automatic =>
      this == preflight ||
      this == changeRadios ||
      this == settle ||
      this == analyze;
}

enum StepStatus { todo, active, done, skipped }

/// One stop on the track. Pure data; the runner interprets [params].
///
/// `params` keys by kind:
///
/// * `goTo`: `target` = `'base'` | `'start'`; the runner fills the
///   coordinates at run time.
/// * `changeRadios`: `preset` (preset id) and/or `txPower` (int, dBm);
///   `restore: true` on the final "put them back" step.
/// * `walk`: `minutes` (int), `pass` (1 or 2).
/// * `swapHardware`: `side` = `'mobile'` | `'base'`, `name` (the variant).
/// * `switchRadio`: `name` (the radio to connect).
/// * `settle`: `seconds` (int).
class PlanStep {
  /// 0-based position in the plan.
  final int ordinal;
  final StepKind kind;

  /// Index into [PlanIntent.variants] for steps that belong to one
  /// variant; null for preflight/goTo/analyze.
  final int? variant;

  /// Short title ("Put the 5.8 dBi fiberglass on").
  final String title;

  /// One or two sentences for the Run screen.
  final String instruction;

  /// One line under the title on the Plan screen.
  final String summary;
  final Map<String, dynamic> params;

  const PlanStep({
    required this.ordinal,
    required this.kind,
    this.variant,
    required this.title,
    required this.instruction,
    required this.summary,
    this.params = const {},
  });

  Map<String, dynamic> toJson() => {
        'ordinal': ordinal,
        'kind': kind.name,
        if (variant != null) 'variant': variant,
        'title': title,
        'instruction': instruction,
        'summary': summary,
        'params': params,
      };

  factory PlanStep.fromJson(Map<String, dynamic> j) => PlanStep(
        ordinal: (j['ordinal'] as num).toInt(),
        kind: StepKind.values.firstWhere((k) => k.name == j['kind']),
        variant: (j['variant'] as num?)?.toInt(),
        title: j['title'] as String? ?? '',
        instruction: j['instruction'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        params: j['params'] is Map
            ? Map<String, dynamic>.from(j['params'] as Map)
            : const {},
      );
}

enum PlanStatus { draft, running, paused, done, abandoned }

/// A stored plan, as the UI sees it (the engine maps its DB row to this).
class PlanRecord {
  final int id;
  final int coverageMapId;
  final String title;
  final PlanIntent intent;
  final PlanStatus status;

  /// Ordinal of the current step while running/paused.
  final int currentStep;

  /// Whether this plan changes the base from a distance (Meshtastic
  /// remote admin) rather than by walking to it.
  final bool remoteChanges;
  final DateTime createdAt;
  final DateTime? finishedAt;

  const PlanRecord({
    required this.id,
    required this.coverageMapId,
    required this.title,
    required this.intent,
    required this.status,
    required this.currentStep,
    required this.remoteChanges,
    required this.createdAt,
    this.finishedAt,
  });
}

/// A stored step: the [PlanStep] plus what happened to it.
class StepRecord {
  final int id;
  final PlanStep step;
  final StepStatus status;

  /// The session recorded by a `walk` step.
  final int? sessionId;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// Free text the person or the runner attached ("walked again: first
  /// try was 90 s").
  final String note;

  const StepRecord({
    required this.id,
    required this.step,
    required this.status,
    this.sessionId,
    this.startedAt,
    this.endedAt,
    this.note = '',
  });
}

// ─── Live state while a step runs ──────────────────────────────────────

enum CheckStatus { ok, busy, warn, fail }

/// What a preflight row's fix button does.
enum PreflightFix {
  none,
  connectRadio,
  openRadioSetup,
  setBaseLocation,

  /// Give the base the mobile's key for remote changes (Bluetooth path).
  enableRemoteAtBase,

  /// Use the Bluetooth path for base changes instead of remote.
  walkToBaseInstead,
}

/// One row of a preflight or a radio-change progress list.
class CheckRow {
  final String label;
  final String detail;
  final CheckStatus status;
  final PreflightFix fix;

  const CheckRow({
    required this.label,
    this.detail = '',
    required this.status,
    this.fix = PreflightFix.none,
  });
}

/// Where the person has to go for a `goTo` step.
class GoToState {
  final LatLng? target;
  final double? distanceM;

  /// Compass bearing from the phone to the target, degrees clockwise
  /// from north; null without a fix.
  final double? bearingDeg;

  /// Within reach (15 m): the key lights up.
  final bool arrived;

  /// The map has no base location yet: this step sets it ("Stand next to
  /// the base, tap Set").
  final bool setsBaseLocation;

  const GoToState({
    this.target,
    this.distanceM,
    this.bearingDeg,
    this.arrived = false,
    this.setsBaseLocation = false,
  });
}

/// A `walk` step while recording.
class WalkState {
  final int? sessionId;
  final int elapsedSec;
  final int plannedSec;

  /// 0 to 100; null on the first pass (nothing to match yet).
  final double? routeMatchPct;
  final int pingsSent;
  final int pingsAnswered;
  final bool baseHeard;
  final DateTime? baseLastHeardAt;
  final double? lastSnr;

  /// The route from the first pass, to follow (empty on the first pass).
  final List<LatLng> ghostRoute;

  /// This walk's track so far.
  final List<LatLng> track;

  /// "Done walking" lights: 80 % route match or the planned time.
  final bool canFinish;

  const WalkState({
    this.sessionId,
    this.elapsedSec = 0,
    required this.plannedSec,
    this.routeMatchPct,
    this.pingsSent = 0,
    this.pingsAnswered = 0,
    this.baseHeard = false,
    this.baseLastHeardAt,
    this.lastSnr,
    this.ghostRoute = const [],
    this.track = const [],
    this.canFinish = false,
  });
}

/// A `changeRadios` step. [phase] follows design §6.
enum ChangePhase {
  /// Waiting for the person's go (and, for the first remote change on
  /// this phone, the risk sheet).
  ready,
  backingUp,
  changingBase,
  settling,
  changingMobile,
  listening,
  done,

  /// Rolled back after a silent base; [rows] hold the story and [failure]
  /// the one-line reason.
  failed,
}

class ChangeState {
  final ChangePhase phase;
  final List<CheckRow> rows;

  /// True when the base is changed over the mesh; false for the
  /// Bluetooth path (the person walked to the base).
  final bool remote;

  /// Distance to the base now, for the risk sheet.
  final double? baseDistanceM;

  /// Human name of the setting being applied ("Long Fast", "20 dBm").
  final String targetName;
  final String? failure;

  /// After a failure: whether the base is believed to be on the new
  /// setting (out of reach) or still on the old one (change didn't take).
  final bool? baseChanged;

  const ChangeState({
    required this.phase,
    this.rows = const [],
    required this.remote,
    this.baseDistanceM,
    required this.targetName,
    this.failure,
    this.baseChanged,
  });
}

/// Everything the Run screen needs for the current step. Exactly one of
/// the typed states is set, by [StepRecord.step.kind].
class PlanProgress {
  final PlanRecord plan;
  final List<StepRecord> steps;
  final StepRecord current;
  final List<CheckRow>? preflight;
  final GoToState? goTo;
  final WalkState? walk;
  final ChangeState? change;

  /// Seconds left on a `settle` step.
  final int? settleRemainingSec;

  /// Set while `analyze` runs; the result is then at [PlanAnalysisResult].
  final bool analyzing;

  const PlanProgress({
    required this.plan,
    required this.steps,
    required this.current,
    this.preflight,
    this.goTo,
    this.walk,
    this.change,
    this.settleRemainingSec,
    this.analyzing = false,
  });

  int get stepCount => steps.length;
  int get stepNumber => current.step.ordinal + 1;
}

// ─── The result ────────────────────────────────────────────────────────

/// One measure on the result table: a number with its unit and a caption
/// ("800 m", "farthest ping").
class Measure {
  final String value;
  final String caption;

  const Measure(this.value, this.caption);

  Map<String, dynamic> toJson() => {'value': value, 'caption': caption};
  factory Measure.fromJson(Map<String, dynamic> j) =>
      Measure(j['value'] as String? ?? '', j['caption'] as String? ?? '');
}

/// One row per variant on the result screen.
class VariantResult {
  final int variant;
  final String name;

  /// Session ids this variant's walks produced.
  final List<int> sessionIds;
  final Measure reach;
  final Measure margin;

  /// Third column: pings answered, or airtime per ping for range settings.
  final Measure third;

  /// Share of shared cells where this variant led, 0 to 100.
  final double leadPct;

  const VariantResult({
    required this.variant,
    required this.name,
    required this.sessionIds,
    required this.reach,
    required this.margin,
    required this.third,
    required this.leadPct,
  });

  Map<String, dynamic> toJson() => {
        'variant': variant,
        'name': name,
        'sessionIds': sessionIds,
        'reach': reach.toJson(),
        'margin': margin.toJson(),
        'third': third.toJson(),
        'leadPct': leadPct,
      };

  factory VariantResult.fromJson(Map<String, dynamic> j) => VariantResult(
        variant: (j['variant'] as num).toInt(),
        name: j['name'] as String? ?? '',
        sessionIds: (j['sessionIds'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            [],
        reach: Measure.fromJson(Map<String, dynamic>.from(j['reach'] as Map)),
        margin: Measure.fromJson(Map<String, dynamic>.from(j['margin'] as Map)),
        third: Measure.fromJson(Map<String, dynamic>.from(j['third'] as Map)),
        leadPct: (j['leadPct'] as num?)?.toDouble() ?? 0,
      );
}

/// "What you found out", written to the never-null rule: what was proved,
/// one number with margin per side, one next step; data problems as
/// rescues.
class PlanAnalysisResult {
  final String headline;

  /// "Same route both times (match 91 %), base untouched."
  final String fairness;
  final List<VariantResult> variants;

  /// Index into [variants] of the winner, or null for a tie (equivalence
  /// is itself a finding).
  final int? winner;
  final String nextStep;
  final List<String> dataNotes;

  /// Third-column header: "PINGS" or "AIRTIME".
  final String thirdLabel;

  /// Numbers-only digest for the AI card (the existing
  /// `AiAnalysisClient`), already free of positions.
  final Map<String, dynamic> digest;

  const PlanAnalysisResult({
    required this.headline,
    required this.fairness,
    required this.variants,
    this.winner,
    required this.nextStep,
    this.dataNotes = const [],
    required this.thirdLabel,
    this.digest = const {},
  });

  Map<String, dynamic> toJson() => {
        'headline': headline,
        'fairness': fairness,
        'variants': variants.map((v) => v.toJson()).toList(),
        if (winner != null) 'winner': winner,
        'nextStep': nextStep,
        'dataNotes': dataNotes,
        'thirdLabel': thirdLabel,
        'digest': digest,
      };

  factory PlanAnalysisResult.fromJson(Map<String, dynamic> j) =>
      PlanAnalysisResult(
        headline: j['headline'] as String? ?? '',
        fairness: j['fairness'] as String? ?? '',
        variants: (j['variants'] as List?)
                ?.map((e) =>
                    VariantResult.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
        winner: (j['winner'] as num?)?.toInt(),
        nextStep: j['nextStep'] as String? ?? '',
        dataNotes:
            (j['dataNotes'] as List?)?.map((e) => '$e').toList() ?? const [],
        thirdLabel: j['thirdLabel'] as String? ?? 'PINGS',
        digest: j['digest'] is Map
            ? Map<String, dynamic>.from(j['digest'] as Map)
            : const {},
      );
}

// ─── The engine's API (implemented by PlanRunner, faked in UI tests) ───

/// Thrown by [PlanRunnerApi] with a sentence for the person.
class PlanError implements Exception {
  final String message;
  const PlanError(this.message);
  @override
  String toString() => message;
}

abstract class PlanRunnerApi {
  /// Build and store a plan from a valid intent. Throws [PlanError] with
  /// [PlanIntent.validate]'s line when invalid. The plan starts as
  /// [PlanStatus.draft]; [start] makes it running.
  Future<PlanRecord> createPlan(PlanIntent intent,
      {required int coverageMapId});

  /// The plan's steps, as built.
  Future<List<StepRecord>> steps(int planId);

  /// Plans of a map, newest first (map detail's Tests section).
  Stream<List<PlanRecord>> watchPlans(int coverageMapId);

  /// The one plan that is running or paused, if any (for resume on
  /// launch and the Live tab row).
  Stream<PlanRecord?> watchActivePlan();

  /// Start (from draft) or resume (from paused) at the current step.
  Future<void> start(int planId);

  /// Live state of the current step; emits on every change.
  Stream<PlanProgress> watch(int planId);

  /// The person tapped the step's key ("Done, it's on", "I'm here",
  /// "Done walking", "Continue"). Automatic steps ignore it unless they
  /// are waiting for a go ([ChangePhase.ready]).
  Future<void> completeStep(int planId);

  /// "Walk this one again" after a thin walk: the session is kept but
  /// unlinked, the step restarts.
  Future<void> redoStep(int planId);

  /// Skip the current step (the result notes it).
  Future<void> skipStep(int planId);

  /// Switch the current `changeRadios` step to the Bluetooth path
  /// ("I'll walk to it instead").
  Future<void> useBluetoothPath(int planId);

  /// A preflight row's fix was handled outside (Radio Setup, the map);
  /// re-run the checks.
  Future<void> recheck(int planId);

  Future<void> pause(int planId);
  Future<void> abandon(int planId);

  /// The stored result of a finished plan, or null.
  Future<PlanAnalysisResult?> result(int planId);

  /// Rename a variant before its first walk (the Plan screen's tappable
  /// values); the step titles are rebuilt.
  Future<void> renameVariant(int planId, int variant, String name);

  /// Change the planned minutes per pass or the repeat flag on a draft.
  Future<void> updateDraft(int planId, PlanIntent intent);
}

// ─── Understanding the request (implemented in plan_intent_parser.dart) ─

/// What the parser knows about the setup, so names can be resolved.
class ParserContext {
  /// Rig profile names on this phone (antenna names come from them).
  final List<String> rigNames;

  /// Presets or ladder ids the connected radio can use, with display names.
  final Map<String, String> presetNames;

  /// 'meshtastic' or 'meshcore'.
  final String protocol;

  const ParserContext({
    this.rigNames = const [],
    this.presetNames = const {},
    this.protocol = 'meshtastic',
  });
}

/// The parser's answer: an intent, how sure it is, and what to say when
/// something is missing ("Which two antennas? Tap to name them.").
class PlanIntentGuess {
  final PlanIntent intent;

  /// 0 to 1; below 0.5 the Ask screen pre-selects the chip and asks.
  final double confidence;
  final String? clarification;

  /// Whether the AI helper was used (false: local keywords only).
  final bool fromAi;

  const PlanIntentGuess({
    required this.intent,
    required this.confidence,
    this.clarification,
    this.fromAi = false,
  });
}

abstract class PlanIntentParser {
  /// Never throws: offline, no consent or a limit yields a local guess
  /// with [PlanIntentGuess.fromAi] false.
  Future<PlanIntentGuess> parse(String text, {required ParserContext ctx});
}
