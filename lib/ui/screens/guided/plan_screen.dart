// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers.dart';
import '../../../services/guided/plan_builder.dart' show variantName;
import '../../../services/guided/plan_models.dart';
import '../../../services/pro_entitlement.dart' show ProFeature;
import '../pro_paywall_screen.dart' show ProGate;
import '../../theme/app_theme.dart';
import '../../widgets/guided/guided_styles.dart';
import '../../widgets/guided/step_track.dart';
import 'ask_screen.dart' show presetLadder;
import 'guided_test_flow.dart';
import 'plan_copy.dart';
import '../../../utils/user_errors.dart';
import '../../layout/window_class.dart';

/// Screen 2: the plan as a track of numbered stops, with minutes / steps /
/// walks readouts, the one-paragraph why, the "Second pass, other order"
/// switch and Start.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key, required this.plan});

  final PlanRecord plan;

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  late PlanRecord _plan = widget.plan;
  List<StepRecord>? _steps;
  String? _error;
  bool _busy = false;

  PlanRunnerApi get _runner => ref.read(guidedRunnerProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final steps = await _runner.steps(_plan.id);
      if (mounted) setState(() => _steps = steps);
    } catch (e) {
      if (mounted) {
        setState(() => _error = userMessage(e, doing: 'reading the plan'));
      }
    }
  }

  PlanRecord _withIntent(PlanIntent intent) => PlanRecord(
        id: _plan.id,
        coverageMapId: _plan.coverageMapId,
        title: _plan.title,
        intent: intent,
        status: _plan.status,
        currentStep: _plan.currentStep,
        remoteChanges: _plan.remoteChanges,
        createdAt: _plan.createdAt,
        finishedAt: _plan.finishedAt,
      );

  /// Ask for one setup's value the way its template needs it: a range
  /// setting from the radio's list, TX power as a number of dBm, a name
  /// for antennas and radios. Null when cancelled.
  Future<String?> _askVariant({required String title, String initial = ''}) {
    final intent = _plan.intent;
    switch (intent.template) {
      case PlanTemplate.rangeSettings:
        final ladder = presetLadder(ref.read(meshRadioProvider));
        final taken = {...intent.variants}..remove(initial);
        return showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(title),
            children: [
              for (final e in ladder.entries)
                if (!taken.contains(e.key))
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(ctx).pop(e.key),
                    child: Text(e.value,
                        style: e.key == initial
                            ? const TextStyle(fontWeight: FontWeight.w700)
                            : null),
                  ),
            ],
          ),
        );
      case PlanTemplate.txPower:
        return _askText(context,
            title: title,
            initial: initial,
            hint: 'dBm, 0 to 30',
            numeric: true);
      case PlanTemplate.radios:
        return _askText(context,
            title: title, initial: initial, hint: 'For example T1000-E');
      case PlanTemplate.antennas:
      case PlanTemplate.reach:
        return _askText(context,
            title: title,
            initial: initial,
            hint: 'For example 5.8 dBi fiberglass');
    }
  }

  String get _renameTitle => switch (_plan.intent.template) {
        PlanTemplate.rangeSettings => 'Pick a range setting',
        PlanTemplate.txPower => 'TX power for this setup',
        _ => 'Name this setup',
      };

  /// Whether another setup can be added: a draft, not a reach test, fewer
  /// than [PlanLimits.maxVariants] setups.
  bool get _canAddSetup =>
      _plan.status == PlanStatus.draft &&
      _plan.intent.template != PlanTemplate.reach &&
      _plan.intent.variants.length < PlanLimits.maxVariants;

  /// Add a setup to the comparison (the third and fourth need Pro; the
  /// button goes through [ProGate] first).
  Future<void> _addSetup() async {
    final value = await _askVariant(title: 'Add a setup');
    if (value == null || value.trim().isEmpty) return;
    final intent = _plan.intent;
    await _update(
        intent.copyWith(variants: [...intent.variants, value.trim()]));
  }

  Future<void> _rename(int variant) async {
    final current = _plan.intent.variants[variant];
    final name = await _askVariant(title: _renameTitle, initial: current);
    if (name == null || name.trim().isEmpty || name.trim() == current) return;
    final variants = [..._plan.intent.variants]..[variant] = name.trim();
    final problem = _plan.intent.copyWith(variants: variants).validate();
    if (problem != null) {
      _say(problem);
      return;
    }
    try {
      await _runner.renameVariant(_plan.id, variant, name.trim());
      if (!mounted) return;
      setState(
          () => _plan = _withIntent(_plan.intent.copyWith(variants: variants)));
      await _load();
    } on PlanError catch (e) {
      _say(e.message);
    }
  }

  Future<void> _changeMinutes() async {
    final text = await _askText(
      context,
      title: 'Minutes per walk',
      initial: '${_plan.intent.route.minutes}',
      hint: '${PlanLimits.minRouteMinutes} to ${PlanLimits.maxRouteMinutes}',
      numeric: true,
    );
    final minutes = int.tryParse(text?.trim() ?? '');
    if (minutes == null) return;
    final route = PlanRoute(kind: _plan.intent.route.kind, minutes: minutes);
    await _update(_plan.intent.copyWith(route: route));
  }

  Future<void> _update(PlanIntent intent) async {
    final problem = intent.validate();
    if (problem != null) {
      _say(problem);
      return;
    }
    try {
      await _runner.updateDraft(_plan.id, intent);
      if (!mounted) return;
      setState(() => _plan = _withIntent(intent));
      await _load();
    } on PlanError catch (e) {
      _say(e.message);
    }
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await _runner.start(_plan.id);
      if (!mounted) return;
      await GuidedTestFlow.openRun(context, _plan.id, replace: true);
    } on PlanError catch (e) {
      _say(e.message);
    } catch (e) {
      _say(userMessage(e, doing: 'starting the test'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = _steps;
    final intent = _plan.intent;
    final draft = _plan.status == PlanStatus.draft;
    return Scaffold(
      appBar:
          AppBar(title: Text(_plan.title.isEmpty ? 'Your plan' : _plan.title)),
      body: WideColumn(
        child: Column(
          children: [
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : steps == null
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Row(
                              children: [
                                _Readout(
                                    value:
                                        '${PlanCopy.totalMinutes(steps, intent)}',
                                    label: 'MINUTES'),
                                const SizedBox(width: 18),
                                _Readout(
                                    value: '${steps.length}', label: 'STEPS'),
                                const SizedBox(width: 18),
                                _Readout(
                                    value: '${PlanCopy.walkCount(steps)}',
                                    label: 'WALKS'),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(PlanCopy.why(_plan),
                                style: context.guidedSoft),
                            const SizedBox(height: 10),
                            StepTrack(
                              steps: steps,
                              // Step text uses display names ("Long Fast",
                              // "20 dBm"), so match on those.
                              variants: [
                                for (var i = 0; i < intent.variants.length; i++)
                                  variantName(intent, i)
                              ],
                              onVariantTap: draft ? _rename : null,
                              onMinutesTap: draft ? _changeMinutes : null,
                            ),
                            if (_canAddSetup)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: ProGate(
                                  feature: ProFeature.guidedTests,
                                  onUnlocked: _addSetup,
                                  builder: (context, unlocked, activate) {
                                    // Setups beyond the free two need Pro.
                                    final needsPro = intent.variants.length >=
                                        PlanLimits.freeVariants;
                                    final locked = needsPro && !unlocked;
                                    return TextButton.icon(
                                      key: const ValueKey('add-setup'),
                                      onPressed:
                                          needsPro ? activate : _addSetup,
                                      icon: Icon(locked
                                          ? Icons.lock_outline
                                          : Icons.add),
                                      label: Text(locked
                                          ? 'Add a setup (Pro)'
                                          : 'Add a setup'),
                                    );
                                  },
                                ),
                              ),
                            if (intent.template != PlanTemplate.reach) ...[
                              const SizedBox(height: 6),
                              GuidedCard(
                                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Second pass, other order',
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700)),
                                          Text(
                                            '+${PlanCopy.secondPassMinutes(intent)} '
                                            'min · cancels out changes over time '
                                            '(battery, people, weather)',
                                            style: context.guidedFine,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      key: const ValueKey('repeat-switch'),
                                      value: intent.repeat,
                                      onChanged: draft
                                          ? (v) {
                                              GuidedHaptics.tap();
                                              _update(
                                                  intent.copyWith(repeat: v));
                                            }
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Text(PlanCopy.note(_plan),
                                style: context.guidedFine),
                          ],
                        ),
            ),
            GuidedFooter(children: [
              GuidedKey(
                draft ? 'Start' : 'Continue',
                onPressed: steps == null || _busy ? null : _start,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.value, required this.label});

  final String value, label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: context.readout.valueLarge),
          Text(label, style: context.guidedMonoLabel),
        ],
      );
}

/// One-field dialog; null when cancelled.
Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String initial,
  required String hint,
  bool numeric = false,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
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
}
