// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/radio/mesh_radio.dart';
import '../../../data/radio/meshcore/meshcore_presets.dart';
import '../../../data/radio/meshtastic/meshtastic_presets.dart';
import '../../../providers.dart';
import '../../../services/guided/plan_intent_parser.dart'
    show AiPlanIntentParser;
import '../../../services/guided/plan_models.dart';
import '../../../services/privacy_settings.dart';
import '../../../services/pro_entitlement.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ai_analysis_card.dart' show showAiConsentSheet;
import '../../widgets/guided/guided_styles.dart';
import '../pro_paywall_screen.dart';
import 'guided_test_flow.dart';
import '../../../utils/user_errors.dart';
import '../../layout/window_class.dart';

/// The sentence a chip puts in the field.
String chipSentence(PlanTemplate t) => switch (t) {
      PlanTemplate.antennas => 'I want to compare antennas',
      PlanTemplate.rangeSettings => 'I want to compare range settings',
      PlanTemplate.radios => 'I want to compare two nodes',
      PlanTemplate.txPower => 'I want to compare TX power',
      PlanTemplate.reach => 'How far does my setup reach?',
    };

/// The chip's small cyan glyph (from the mock).
String chipGlyph(PlanTemplate t) => switch (t) {
      PlanTemplate.antennas => '⟟',
      PlanTemplate.rangeSettings => '≋',
      PlanTemplate.radios => '▣',
      PlanTemplate.txPower => '▲',
      PlanTemplate.reach => '◎',
    };

/// The template whose chip sentence [text] is, if any (case and
/// punctuation insensitive).
PlanTemplate? templateForSentence(String text) {
  String norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();
  final n = norm(text);
  for (final t in PlanTemplate.values) {
    if (norm(chipSentence(t)) == n || norm(t.chip) == n) return t;
  }
  return null;
}

/// Presets (or MeshCore ladder steps) the connected radio can use, in
/// ladder order, id → display name.
Map<String, String> presetLadder(MeshRadio radio) {
  if (radio.protocol == RadioProtocol.meshcore) {
    return {for (final m in MeshCoreModulations.all) m.id: m.name};
  }
  return {
    for (final p in MeshtasticPresets.presetsForRegion(radio.regionName,
        firmwareVersion: radio.capabilities.firmwareVersion))
      if (!p.deprecated) p.id: p.displayName,
  };
}

/// Default variants for a chip: antennas and radios get placeholder
/// names (renamed on the Plan screen); range settings the current preset
/// plus its neighbour on the ladder; TX power the current power and a
/// lower one; reach the one current setup.
List<String> defaultVariants(PlanTemplate t, ParserContext ctx,
    {String? currentPresetId, int? currentTxPower}) {
  switch (t) {
    case PlanTemplate.antennas:
      return const ['Antenna A', 'Antenna B'];
    case PlanTemplate.radios:
      return const ['Node A', 'Node B'];
    case PlanTemplate.reach:
      return const ['Current setup'];
    case PlanTemplate.txPower:
      final now = currentTxPower ?? 20;
      final other = now >= 10 ? now - 10 : now + 10;
      return ['$now', '$other'];
    case PlanTemplate.rangeSettings:
      final ids = ctx.presetNames.keys.toList();
      if (ids.isEmpty) return const ['LONG_FAST', 'MEDIUM_FAST'];
      final at = currentPresetId == null ? -1 : ids.indexOf(currentPresetId);
      if (at < 0) return ids.take(2).toList();
      final next = at + 1 < ids.length ? at + 1 : at - 1;
      if (next < 0) return [ids[at]];
      return [ids[at], ids[next]];
  }
}

/// Screen 1: "What do you want to find out?" A text field, five chips and
/// Next. A chip alone is the whole input for most people; typed text goes
/// to the parser (AI helper when allowed, local keywords otherwise).
class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key, this.mapId, this.prefill});

  /// The map the plan belongs to; picked (or created) when null.
  final int? mapId;

  /// A template and variants to start from (Compare → "Make this a guided
  /// test").
  final PlanIntent? prefill;

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  final _text = TextEditingController();
  PlanTemplate? _selected;
  String? _clarification;
  PlanIntentGuess? _guess;
  String? _guessedText;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    if (p != null) {
      _selected = p.template;
      _text.text = chipSentence(p.template);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _pick(PlanTemplate t) {
    GuidedHaptics.tap();
    setState(() {
      _selected = t;
      _text.text = chipSentence(t);
      _clarification = null;
      _guess = null;
    });
  }

  ParserContext _context(MeshRadio radio) {
    final rigs = ref.read(rigProfilesProvider).valueOrNull ?? const [];
    return ParserContext(
      rigNames: [for (final r in rigs) r.name],
      presetNames: presetLadder(radio),
      protocol: radio.protocol.name,
    );
  }

  PlanIntent _local(PlanTemplate t, ParserContext ctx, MeshRadio radio) {
    final p = widget.prefill;
    if (p != null && p.template == t) return p;
    return PlanIntent(
      template: t,
      variants: defaultVariants(t, ctx,
          currentPresetId: radio.currentPreset?.id,
          currentTxPower: radio.radioSettings?.txPowerDbm),
    );
  }

  Future<void> _next() async {
    final text = _text.text.trim();
    final radio = ref.read(meshRadioProvider);
    final ctx = _context(radio);
    PlanIntent? intent;

    final chip = text.isEmpty ? _selected : templateForSentence(text);
    if (chip != null) {
      intent = _local(chip, ctx, radio);
    } else if (text.isEmpty) {
      setState(() => _clarification =
          'Pick one of the tests below, or say what you want to find out.');
      return;
    } else if (_guess != null && _guessedText == text && _selected != null) {
      // Second Next after a clarification: the pre-selected (or changed)
      // chip decides.
      final g = _guess!;
      intent = g.intent.template == _selected && g.intent.validate() == null
          ? g.intent
          : _local(_selected!, ctx, radio);
    } else {
      final parser = ref.read(planIntentParserProvider);
      if (parser is AiPlanIntentParser && parser.shouldOfferConsent) {
        // Offered once; declined = the phone reads the text itself.
        await parser.markConsentOffered();
        if (!mounted) return;
        if (await showAiConsentSheet(context, confirmLabel: 'Allow')) {
          await ref.read(privacyProvider.notifier).setAiConsent(true);
        }
        if (!mounted) return;
      }
      setState(() {
        _busy = true;
        _clarification = null;
      });
      final guess = await parser.parse(text, ctx: ctx);
      if (!mounted) return;
      _guess = guess;
      _guessedText = text;
      if (guess.confidence < 0.5 || guess.intent.validate() != null) {
        setState(() {
          _busy = false;
          _selected = guess.intent.template;
          _clarification = guess.clarification ??
              'Is it "${guess.intent.template.chip}"? Tap Next to go on, '
                  'or pick another.';
        });
        return;
      }
      setState(() => _busy = false);
      intent = guess.intent;
    }

    intent = intent.copyWith(question: text.isEmpty ? null : text);
    final problem = intent.validate();
    if (problem != null) {
      setState(() => _clarification = problem);
      return;
    }
    if (intent.needsPro &&
        !ref.read(proEntitlementProvider).canCreate(ProFeature.guidedTests)) {
      final ok = await showProPaywall(context, feature: ProFeature.guidedTests);
      if (!ok || !mounted) return;
    }
    final mapId = await pickMapForPlan(context, ref, mapId: widget.mapId);
    if (mapId == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final plan = await ref
          .read(guidedRunnerProvider)
          .createPlan(intent, coverageMapId: mapId);
      if (!mounted) return;
      await GuidedTestFlow.openPlan(context, plan, replace: true);
    } on PlanError catch (e) {
      if (mounted) setState(() => _clarification = e.message);
    } catch (e) {
      if (mounted) {
        setState(
            () => _clarification = userMessage(e, doing: 'making the plan'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Guided test')),
      body: WideColumn(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('WHAT DO YOU WANT TO FIND OUT?',
                      style: context.guidedCaption),
                  const SizedBox(height: 6),
                  Text('Say it in your own words, or pick one.',
                      style: context.guidedTitle.copyWith(fontSize: 21)),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('ask-field'),
                    controller: _text,
                    minLines: 3,
                    maxLines: 5,
                    autofocus: widget.prefill == null,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(fontSize: 17),
                    onChanged: (_) {
                      if (_clarification != null) {
                        setState(() => _clarification = null);
                      }
                    },
                    onSubmitted: (_) => _next(),
                    decoration: const InputDecoration(
                      hintText:
                          'e.g. which of my two antennas gets further up the hill',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_clarification != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _clarification!,
                        key: const ValueKey('ask-clarification'),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.status.warning),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in PlanTemplate.values)
                        _Chip(
                          template: t,
                          selected: _selected == t,
                          onTap: () => _pick(t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    ref.watch(privacyProvider).aiConsent
                        ? 'The app builds the plan itself. When AI help is on, '
                            'what you type is sent to an AI helper to work out '
                            'which test you mean. No positions, node ids or '
                            'keys are ever sent.'
                        : 'The app builds the plan itself. AI help is off, so '
                            'what you type is read on this phone only. You can '
                            'turn AI help on in Settings → Privacy.',
                    style: context.guidedFine,
                  ),
                ],
              ),
            ),
            GuidedFooter(children: [
              GuidedKey(
                _busy ? 'Working…' : 'Next',
                onPressed: _busy ? null : _next,
              ),
            ]),
          ],
        ),
      ),
      backgroundColor: scheme.surface,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final PlanTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // VoiceOver hears the chip's words and whether it is selected, not the
    // decorative glyph.
    return Semantics(
        button: true,
        selected: selected,
        label: template.chip,
        excludeSemantics: true,
        child: Material(
          color:
              selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            side: BorderSide(
                color: selected ? scheme.primary : scheme.outlineVariant),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '${chipGlyph(template)} ',
                    style: TextStyle(color: scheme.secondary),
                  ),
                  TextSpan(text: template.chip),
                ]),
                style: TextStyle(fontSize: 14, color: scheme.onSurface),
              ),
            ),
          ),
        ));
  }
}
