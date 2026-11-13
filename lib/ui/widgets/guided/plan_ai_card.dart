// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers.dart';
import '../../../services/ai_analysis.dart';
import '../../../services/privacy_settings.dart';
import '../../../services/pro_entitlement.dart';
import '../../screens/pro_paywall_screen.dart';
import '../../theme/app_theme.dart';
import '../ai_analysis_card.dart' show showAiConsentSheet;
import 'guided_styles.dart';

/// "READING IT · AI": the result's plain-English read, written from the
/// plan's numbers-only [digest] and the question the person typed. Same
/// consent sheet, Pro gate and backend as [AiAnalysisCard]; the answer is
/// cached per plan so reopening does not re-bill. Hidden when the backend
/// is not configured.
class PlanAiCard extends ConsumerStatefulWidget {
  const PlanAiCard({
    super.key,
    required this.planId,
    required this.digest,
    this.question,
  });

  final int planId;
  final Map<String, dynamic> digest;
  final String? question;

  static String cacheKey(int planId) => 'ai_plan_result_$planId';

  @override
  ConsumerState<PlanAiCard> createState() => _PlanAiCardState();
}

class _PlanAiCardState extends ConsumerState<PlanAiCard> {
  AiAnalysisResult? _result;
  String? _error;
  String? _limit;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _result = ref
        .read(aiAnalysisClientProvider)
        .cached(PlanAiCard.cacheKey(widget.planId));
  }

  /// The engine's digest (`kind: guidedTest`, numbers only) with the
  /// question the person typed on top (the backend caps it at 300).
  Map<String, dynamic> get _payload {
    final q = widget.question?.trim();
    return {
      ...widget.digest,
      if (q != null && q.isNotEmpty)
        'question': q.length > 300 ? q.substring(0, 300) : q,
    };
  }

  Future<void> _run() async {
    final client = ref.read(aiAnalysisClientProvider);
    if (!client.hasConsent) {
      final ok = await showAiConsentSheet(context);
      if (!ok || !mounted) return;
      await ref.read(privacyProvider.notifier).setAiConsent(true);
    }
    setState(() {
      _busy = true;
      _error = null;
      _limit = null;
    });
    try {
      final json = _payload;
      assertNoLocationData(json);
      final r = await ref
          .read(aiAnalysisGatewayProvider)
          .analyze(json,
              deviceId: client.deviceId, appVersion: await client.appVersion())
          .timeout(AiAnalysisClient.timeout);
      await ref
          .read(sharedPreferencesProvider)
          .setString(PlanAiCard.cacheKey(widget.planId), jsonEncode(r.toJson()));
      if (mounted) setState(() => _result = r);
    } on AiAnalysisLimitException catch (e) {
      if (mounted) setState(() => _limit = e.message);
    } on AiAnalysisException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(aiAnalysisAvailableProvider)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final r = _result;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('READING IT · AI',
              style: context.guidedCaption.copyWith(color: scheme.secondary)),
          const SizedBox(height: 4),
          if (_busy)
            Row(children: [
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    'Reading the numbers… (the first read in a while can '
                    'take up to 30 seconds)',
                    style: context.guidedSoft),
              ),
            ])
          else if (r == null) ...[
            Text(
              'A plain-English read of this result, written by Claude from '
              'the numbers above (never positions).',
              style: context.guidedSoft,
            ),
            ProGate(
              feature: ProFeature.aiAnalysis,
              onUnlocked: _run,
              builder: (context, unlocked, activate) => GuidedTextLink(
                unlocked ? 'Send summary & read it' : 'Send summary & read it (Pro)',
                onPressed: activate,
              ),
            ),
          ] else ...[
            Text(r.headline,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final b in r.bullets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(b, style: context.guidedSoft)),
                  ],
                ),
              ),
            if (r.caveats.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final c in r.caveats)
                Text('– $c', style: context.guidedFine),
            ],
            if (r.nextStep.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(r.nextStep, style: text.bodyMedium),
            ],
            const SizedBox(height: 6),
            Text(
              'Written by Claude Haiku from the numbers above; it can be '
              'wrong.',
              style: context.guidedFine,
            ),
            ProGate(
              feature: ProFeature.aiAnalysis,
              onUnlocked: _run,
              builder: (context, unlocked, activate) =>
                  GuidedTextLink('Read it again', onPressed: activate),
            ),
          ],
          if (_limit != null) ...[
            const SizedBox(height: 6),
            Text('Analysis limit reached: $_limit', style: context.guidedFine),
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!,
                style: text.bodySmall?.copyWith(color: scheme.error)),
          ],
        ],
      ),
    );
  }
}
