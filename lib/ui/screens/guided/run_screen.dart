// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/radio/radio_types.dart';
import '../../../providers.dart';
import '../../../services/guided/plan_builder.dart' show variantName;
import '../../../services/guided/plan_models.dart';
import '../../protocol_text.dart';
import '../../theme/app_theme.dart';
import '../../widgets/connection_banner.dart' show showConnectDialog;
import '../../widgets/guided/check_list.dart';
import '../../widgets/guided/go_to_compass.dart';
import '../../widgets/guided/guided_styles.dart';
import '../../widgets/guided/risk_sheet.dart';
import '../../widgets/guided/step_track.dart';
import '../../widgets/guided/walk_map.dart';
import '../coverage_map_detail_screen.dart';
import '../radio_setup_screen.dart';
import 'guided_test_flow.dart';
import '../../../utils/user_errors.dart';
import '../../layout/window_class.dart';

/// The map's base location, for the walk map's diamond.
final _mapBaseProvider =
    FutureProvider.family<LatLng?, int>((ref, mapId) async {
  final m = await ref.watch(databaseProvider).getCoverageMap(mapId);
  if (m == null || m.baseLat == null || m.baseLon == null) return null;
  return LatLng(m.baseLat!, m.baseLon!);
});

/// A plan's current step had the "thin walk" rescue attached by the runner.
bool isThinWalk(StepRecord r) =>
    r.step.kind == StepKind.walk &&
    r.status == StepStatus.active &&
    r.note.toLowerCase().contains('thin walk');

/// Screen 3: one step at a time. Mono "STEP n OF N", the progress strip,
/// the step's body, one big key, and Pause / I'm stuck underneath.
class RunScreen extends ConsumerStatefulWidget {
  const RunScreen({super.key, required this.planId});

  final int planId;

  @override
  ConsumerState<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends ConsumerState<RunScreen> {
  Timer? _clock;
  int? _lastOrdinal;
  bool _navigated = false;
  bool _working = false;

  PlanRunnerApi get _runner => ref.read(guidedRunnerProvider);

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String get _hhmm {
    final t = DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  /// Run one runner call with the keys disabled meanwhile; errors as a
  /// snack bar.
  Future<void> _do(Future<void> Function() f) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await f();
    } on PlanError catch (e) {
      _say(e.message);
    } catch (e) {
      _say(userMessage(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _complete() => _do(() => _runner.completeStep(widget.planId));

  Future<void> _pause() async {
    await _do(() => _runner.pause(widget.planId));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _stuck(PlanProgress p) async {
    GuidedHaptics.tap();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.skip_next),
              title: const Text('Skip this step'),
              subtitle: const Text('The result says it was skipped.'),
              onTap: () => Navigator.of(ctx).pop('skip'),
            ),
            if (p.current.step.kind == StepKind.walk)
              ListTile(
                leading: const Icon(Icons.replay),
                title: const Text('Walk this one again'),
                subtitle: const Text('Keeps what was recorded, starts over.'),
                onTap: () => Navigator.of(ctx).pop('redo'),
              ),
            ListTile(
              leading:
                  Icon(Icons.stop_circle_outlined, color: ctx.status.danger),
              title: const Text('Stop the test'),
              onTap: () => Navigator.of(ctx).pop('stop'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'skip':
        await _do(() => _runner.skipStep(widget.planId));
      case 'redo':
        await _do(() => _runner.redoStep(widget.planId));
      case 'stop':
        final sure = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Stop the test?'),
            content: const Text(
                'The walks recorded so far stay on the map as sessions. '
                'The plan is closed without a result.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Keep going')),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: ctx.status.danger,
                    foregroundColor: ctx.status.onDanger),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Stop'),
              ),
            ],
          ),
        );
        if (sure != true || !mounted) return;
        await _do(() => _runner.abandon(widget.planId));
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _fix(PlanProgress p, PreflightFix fix) async {
    switch (fix) {
      case PreflightFix.none:
        return;
      case PreflightFix.connectRadio:
        await showConnectDialog(context);
      case PreflightFix.openRadioSetup:
      case PreflightFix.enableRemoteAtBase:
        await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const RadioSetupScreen()));
      case PreflightFix.setBaseLocation:
        final map = await ref
            .read(databaseProvider)
            .getCoverageMap(p.plan.coverageMapId);
        if (map == null || !mounted) return;
        _say('Use the map menu (top right) → Set base location…');
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => CoverageMapDetailScreen(map: map)));
      case PreflightFix.walkToBaseInstead:
        await _do(() => _runner.useBluetoothPath(widget.planId));
        return;
    }
    if (mounted) await _do(() => _runner.recheck(widget.planId));
  }

  /// A changeRadios key: the risk sheet first, once, for remote changes.
  Future<void> _changeRadios(ChangeState c) async {
    if (c.remote && !riskSheetSeen(ref)) {
      final choice = await showRiskSheet(context,
          targetName: c.targetName, baseDistanceM: c.baseDistanceM);
      if (!mounted) return;
      switch (choice) {
        case RiskChoice.changeHere:
          await _complete();
        case RiskChoice.walkInstead:
          await _do(() => _runner.useBluetoothPath(widget.planId));
        case null:
          return;
      }
      return;
    }
    await _complete();
  }

  void _onProgress(PlanProgress p) {
    final ordinal = p.current.step.ordinal;
    if (_lastOrdinal != null && ordinal > _lastOrdinal!) {
      GuidedHaptics.stepDone();
    }
    _lastOrdinal = ordinal;
    if (_navigated) return;
    if (p.plan.status == PlanStatus.done) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) GuidedTestFlow.openResult(context, p.plan, replace: true);
      });
    } else if (p.plan.status == PlanStatus.abandoned) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(planProgressProvider(widget.planId));
    final p = async.valueOrNull;
    if (p != null) _onProgress(p);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(p?.plan.title ?? 'Guided test'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(_hhmm,
                  key: const ValueKey('run-clock'), style: context.guidedFine),
            ),
          ),
        ],
      ),
      body: WideColumn(
        child: p == null
            ? Center(
                child: async.hasError
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                            userMessage(async.error!,
                                doing: 'reading the test'),
                            textAlign: TextAlign.center),
                      )
                    : const CircularProgressIndicator(),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('STEP ${p.stepNumber} OF ${p.stepCount}',
                            style: context.guidedCaption),
                        const SizedBox(height: 10),
                        StepProgressStrip(
                            count: p.stepCount,
                            current: p.current.step.ordinal),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: _body(p, theme),
                    ),
                  ),
                  GuidedFooter(children: [
                    ..._keys(p),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GuidedTextLink('Pause',
                            onPressed: _working ? null : _pause),
                        if (p.current.step.kind == StepKind.walk &&
                            !isThinWalk(p.current) &&
                            !(p.walk?.canFinish ?? false))
                          GuidedTextLink('Finish anyway',
                              onPressed: _working ? null : _complete),
                        GuidedTextLink("I'm stuck",
                            onPressed: _working ? null : () => _stuck(p)),
                      ],
                    ),
                  ]),
                ],
              ),
      ),
    );
  }

  // ─── Bodies ───────────────────────────────────────────

  /// The current setup's display name ("Long Fast", "20 dBm"), never the
  /// raw variant ("LONG_FAST").
  String _variantName(PlanProgress p) {
    final v = p.current.step.variant;
    return v == null ? '' : variantName(p.plan.intent, v);
  }

  /// [text] with [highlight] in orange and bold.
  Widget _rich(String text, String highlight, TextStyle style) {
    final scheme = Theme.of(context).colorScheme;
    final at = highlight.isEmpty ? -1 : text.indexOf(highlight);
    if (at < 0) return Text(text, style: style);
    return Text.rich(TextSpan(style: style, children: [
      TextSpan(text: text.substring(0, at)),
      TextSpan(
        text: highlight,
        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
      ),
      TextSpan(text: text.substring(at + highlight.length)),
    ]));
  }

  List<Widget> _body(PlanProgress p, ThemeData theme) {
    final step = p.current.step;
    final fine = context.guidedFine;
    switch (step.kind) {
      case StepKind.preflight:
        final rows = p.preflight ?? const <CheckRow>[];
        final problem = rows.any((r) => r.status != CheckStatus.ok);
        final remote =
            rows.any((r) => r.fix == PreflightFix.enableRemoteAtBase);
        return [
          Text('Checking your setup', style: context.guidedTitle),
          const SizedBox(height: 10),
          CheckList(rows: rows, onFix: (fix) => _fix(p, fix)),
          const SizedBox(height: 12),
          Text(
            remote
                ? 'Remote changes need one Bluetooth connection to the base: '
                    "the app gives it your mobile node's key, then it can be "
                    'changed from a distance. Or let the plan walk you to the '
                    'base for each change.'
                : problem
                    ? 'Fix the rows marked Fix, then check again.'
                    : 'Nothing to do here; the next step starts when every '
                        'check passes.',
            style: fine,
          ),
        ];

      case StepKind.swapHardware:
        final v = _variantName(p);
        final n = (step.variant ?? 0) + 1;
        final total = p.plan.intent.variants.length;
        final side = step.params['side'] == 'base' ? 'base' : 'mobile';
        return [
          _rich(step.title, v, context.guidedTitle),
          const SizedBox(height: 8),
          _rich(step.instruction, '$side node', context.guidedBig),
          const SizedBox(height: 14),
          GuidedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('THIS WALK WILL BE SAVED AS',
                    style: context.guidedCaption),
                const SizedBox(height: 6),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${p.plan.title} · $n of $total · '),
                  variantValueSpan(context, v,
                      onTap: step.variant == null
                          ? null
                          : () => _renameVariant(p, step.variant!)),
                ])),
                const SizedBox(height: 4),
                Text('Hardware profile "$v" · $side', style: fine),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
              'Tap the name to rename it or add the gain. The app fills in '
              'what it knows.',
              style: fine),
        ];

      case StepKind.switchRadio:
        final link = ref.watch(meshLinkStateProvider).valueOrNull;
        final radio = ref.read(meshRadioProvider);
        final ready = link == RadioConnectionState.ready;
        return [
          _rich(step.title, _variantName(p), context.guidedTitle),
          const SizedBox(height: 8),
          Text(step.instruction, style: context.guidedBig),
          const SizedBox(height: 14),
          CheckList(rows: [
            CheckRow(
              label: ready
                  ? 'Connected: ${radio.displayName}'
                  : 'No node connected',
              detail: ready
                  ? 'Set up as the mobile on MeshTest'
                  : 'Tap Connect and pick the other node',
              status: ready ? CheckStatus.ok : CheckStatus.warn,
              fix: ready ? PreflightFix.none : PreflightFix.connectRadio,
            ),
          ], onFix: (fix) => _fix(p, fix)),
        ];

      case StepKind.goTo:
        final g = p.goTo ?? const GoToState();
        final toBase = step.params['target'] != 'start';
        return [
          Text(step.title, style: context.guidedTitle),
          const SizedBox(height: 8),
          Text(
            g.setsBaseLocation
                ? 'This map has no base location yet. Stand next to the base '
                    'and set it here; every walk is measured from it.'
                : step.instruction,
            style: context.guidedBig,
          ),
          const SizedBox(height: 14),
          GoToCompass(
              state: g, caption: toBase ? 'TO THE BASE' : 'TO THE START PIN'),
          const SizedBox(height: 12),
          Text(
            g.setsBaseLocation
                ? 'The spot is saved to the map when you tap the key.'
                : "The key lights up within 15 m. Tap it anyway if you know "
                    "you're there.",
            style: fine,
          ),
        ];

      case StepKind.walk:
        final w = p.walk ?? const WalkState(plannedSec: 0);
        final base =
            ref.watch(_mapBaseProvider(p.plan.coverageMapId)).valueOrNull;
        final second = w.ghostRoute.isNotEmpty;
        if (isThinWalk(p.current)) {
          return [
            Text('Keep it or walk this one again?', style: context.guidedTitle),
            const SizedBox(height: 8),
            Text(
              p.current.note,
              style: context.guidedBig,
            ),
            const SizedBox(height: 14),
            WalkHud(
                state: w,
                probeLabel: probeNoun(ref.read(meshRadioProvider).protocol,
                        plural: true)
                    .toUpperCase()),
          ];
        }
        return [
          WalkBand(state: w),
          const SizedBox(height: 10),
          WalkHud(
              state: w,
              probeLabel:
                  probeNoun(ref.read(meshRadioProvider).protocol, plural: true)
                      .toUpperCase()),
          const SizedBox(height: 10),
          WalkMap(state: w, base: base),
          const SizedBox(height: 10),
          Text(
            second
                ? 'Follow the dashed line. "Done walking" lights at 80 % route '
                    'match.'
                : 'Walk where you want coverage checked. The app remembers '
                    'this route for the next walk.',
            style: fine,
          ),
        ];

      case StepKind.changeRadios:
        final c = p.change ??
            ChangeState(
                phase: ChangePhase.ready,
                remote: false,
                targetName: _variantName(p));
        final name = c.targetName.isEmpty ? _variantName(p) : c.targetName;
        final seen = riskSheetSeen(ref);
        final sentence = switch (c.phase) {
          ChangePhase.ready =>
            'The base first, then yours. Stay here until the base is heard '
                'again.',
          ChangePhase.done => 'Both nodes are on $name and the base answered.',
          ChangePhase.failed => c.failure ?? 'The change did not take.',
          _ => 'Working. Stay here until the base is heard again.',
        };
        return [
          _rich('Switch both nodes to $name', name, context.guidedTitle),
          const SizedBox(height: 8),
          _rich(sentence, c.phase == ChangePhase.done ? name : '',
              context.guidedBig),
          const SizedBox(height: 14),
          if (c.rows.isNotEmpty) CheckList(rows: c.rows),
          const SizedBox(height: 12),
          if (c.phase == ChangePhase.failed)
            Text(
              c.baseChanged == true
                  ? 'The base is on the new setting but out of reach from '
                      'here. Walk to it and the app changes your node there.'
                  : 'The base did not take the change; your node is back on '
                      'the old setting.',
              style: fine,
            )
          else if (c.phase == ChangePhase.ready && c.remote)
            seen
                ? RiskReminderLine(
                    onInfo: () => showRiskSheet(context,
                        targetName: name,
                        baseDistanceM: c.baseDistanceM,
                        reminder: true),
                  )
                : Text.rich(TextSpan(style: fine, children: [
                    const TextSpan(
                        text: 'Changing the base from here has a risk. The app '
                            'explains it before it starts. '),
                    TextSpan(
                      text: 'What can go wrong?',
                      style: TextStyle(color: theme.colorScheme.secondary),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => _changeRadios(c),
                    ),
                  ]))
          else if (c.phase == ChangePhase.ready)
            Text(
              'The app connects to the base over Bluetooth, changes it, then '
              'changes your node.',
              style: fine,
            )
          else
            Text(
              'If the base stays silent, your node goes back to its old '
              'setting and the plan pauses with directions to the base.',
              style: fine,
            ),
        ];

      case StepKind.settle:
        final s = p.settleRemainingSec ?? 0;
        return [
          Text('Letting the nodes settle', style: context.guidedTitle),
          const SizedBox(height: 8),
          Text(
              step.instruction.isEmpty
                  ? 'A short wait so both nodes are back on the air.'
                  : step.instruction,
              style: context.guidedBig),
          const SizedBox(height: 24),
          Center(
            child: Text.rich(
              TextSpan(
                text: '$s',
                style: context.readout.valueLarge.copyWith(fontSize: 56),
                children: const [
                  TextSpan(text: ' s', style: TextStyle(fontSize: 20))
                ],
              ),
              key: const ValueKey('settle-countdown'),
            ),
          ),
        ];

      case StepKind.analyze:
        return [
          Text('Comparing', style: context.guidedTitle),
          const SizedBox(height: 8),
          Text(step.instruction, style: context.guidedBig),
          const SizedBox(height: 14),
          CheckList(rows: [
            for (final s in p.steps)
              if (s.step.kind == StepKind.walk && s.status == StepStatus.done)
                CheckRow(label: s.step.title, status: CheckStatus.ok),
            const CheckRow(
                label: 'Working out the result…', status: CheckStatus.busy),
          ]),
        ];
    }
  }

  Future<void> _renameVariant(PlanProgress p, int variant) async {
    final controller =
        TextEditingController(text: p.plan.intent.variants[variant]);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name this setup'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await _do(() => _runner.renameVariant(widget.planId, variant, name.trim()));
  }

  // ─── Keys ─────────────────────────────────────────────

  List<Widget> _keys(PlanProgress p) {
    final step = p.current.step;
    final off = _working;
    switch (step.kind) {
      case StepKind.preflight:
        final rows = p.preflight ?? const <CheckRow>[];
        final allOk =
            rows.isNotEmpty && rows.every((r) => r.status == CheckStatus.ok);
        if (allOk) {
          return [
            GuidedKey('Continue', tall: true, onPressed: off ? null : _complete)
          ];
        }
        if (rows.any((r) => r.fix == PreflightFix.enableRemoteAtBase)) {
          return [
            GuidedKey('Walk to the base for changes instead',
                tall: true,
                onPressed: off
                    ? null
                    : () => _do(() => _runner.useBluetoothPath(widget.planId))),
          ];
        }
        return [
          GuidedKey('Check again',
              tall: true,
              onPressed:
                  off ? null : () => _do(() => _runner.recheck(widget.planId))),
        ];

      case StepKind.swapHardware:
        return [
          GuidedKey("Done, it's on",
              tall: true, onPressed: off ? null : _complete)
        ];

      case StepKind.switchRadio:
        final ready = ref.watch(meshLinkStateProvider).valueOrNull ==
            RadioConnectionState.ready;
        return [
          ready
              ? GuidedKey('Continue',
                  tall: true, onPressed: off ? null : _complete)
              : GuidedKey('Connect the other node',
                  tall: true,
                  onPressed:
                      off ? null : () => _fix(p, PreflightFix.connectRadio)),
        ];

      case StepKind.goTo:
        final g = p.goTo ?? const GoToState();
        final label =
            g.setsBaseLocation ? 'Set base location here' : "I'm here";
        if (g.arrived) {
          return [
            GuidedKey(label, tall: true, onPressed: off ? null : _complete)
          ];
        }
        // Not there yet: unlit but always tappable.
        return [
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            onPressed: off
                ? null
                : () {
                    GuidedHaptics.tap();
                    _complete();
                  },
            child: Text(label),
          ),
        ];

      case StepKind.walk:
        if (isThinWalk(p.current)) {
          return [
            GuidedKey('Keep it', tall: true, onPressed: off ? null : _complete),
            GuidedGhostKey('Walk this one again',
                onPressed: off
                    ? null
                    : () => _do(() => _runner.redoStep(widget.planId))),
          ];
        }
        final can = p.walk?.canFinish ?? false;
        return [
          GuidedKey('Done walking',
              tall: true, onPressed: can && !off ? _complete : null)
        ];

      case StepKind.changeRadios:
        final c = p.change;
        switch (c?.phase ?? ChangePhase.ready) {
          case ChangePhase.ready:
            return [
              GuidedKey('Change both nodes',
                  tall: true,
                  onPressed: off
                      ? null
                      : () => _changeRadios(c ??
                          ChangeState(
                              phase: ChangePhase.ready,
                              remote: false,
                              targetName: _variantName(p)))),
            ];
          case ChangePhase.done:
            return [
              GuidedKey('Continue',
                  tall: true, onPressed: off ? null : _complete)
            ];
          case ChangePhase.failed:
            return [
              GuidedKey('Try again',
                  tall: true, onPressed: off ? null : _complete),
              Row(children: [
                Expanded(
                  child: GuidedGhostKey('Walk to it instead',
                      onPressed: off
                          ? null
                          : () => _do(
                              () => _runner.useBluetoothPath(widget.planId))),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child:
                        GuidedGhostKey('Stop', onPressed: off ? null : _pause)),
              ]),
            ];
          default:
            return [const GuidedKey('Working…', tall: true, onPressed: null)];
        }

      case StepKind.settle:
        return [const GuidedKey('Waiting…', tall: true, onPressed: null)];

      case StepKind.analyze:
        return [const GuidedKey('Comparing…', tall: true, onPressed: null)];
    }
  }
}
