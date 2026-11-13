// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/database/app_database.dart';
import '../../providers.dart';
import '../../services/ai_analysis.dart';
import '../../services/privacy_settings.dart';
import '../../services/pro_entitlement.dart';
import '../../services/rig_comparison.dart';
import '../../utils/constants.dart';
import '../screens/about_screen.dart' show supportUrl;
import '../screens/pro_paywall_screen.dart';
import '../theme/app_theme.dart';

/// "Reading it": an opt-in, Pro-gated plain-English read of a comparison,
/// written by a language model from the digest of numbers (never positions).
/// Hidden when the backend is not configured.
class AiAnalysisCard extends ConsumerStatefulWidget {
  final List<Session> a, b;
  final RouteComparison result;
  final RigExpectation expected;
  final ComparisonCheck check;

  /// Filled by the distance section once it exists (see
  /// [SessionDigest.distanceStats] for the shape).
  final Map<String, dynamic>? distanceStats;

  const AiAnalysisCard({
    super.key,
    required this.a,
    required this.b,
    required this.result,
    required this.expected,
    required this.check,
    this.distanceStats,
  });

  @override
  ConsumerState<AiAnalysisCard> createState() => _AiAnalysisCardState();
}

class _AiAnalysisCardState extends ConsumerState<AiAnalysisCard> {
  AiAnalysisResult? _result;
  String? _error;

  /// A usage limit was reached; shown as a calm note, not an error.
  String? _limit;
  bool _busy = false;

  /// Set once a read has been running long enough that the service is
  /// probably waking up (first call of the day: ~20–30 s).
  bool _slow = false;
  Timer? _slowTimer;
  SessionDigest? _digest;

  @override
  void initState() {
    super.initState();
    if (ref.read(aiAnalysisAvailableProvider)) {
      // Reopening a comparison shows the saved answer without a new request.
      _result = ref.read(aiAnalysisClientProvider).cached(aiAnalysisCacheKey(
          [for (final s in widget.a) s.id], [for (final s in widget.b) s.id]));
      _loadIntent();
    }
  }

  final _question = TextEditingController();
  String? _intentSummary;

  @override
  void dispose() {
    _slowTimer?.cancel();
    _question.dispose();
    super.dispose();
  }

  /// The auto-detected reason for the comparison, shown above the button
  /// so the user can correct or sharpen it.
  Future<void> _loadIntent() async {
    final d = await _buildDigest();
    if (mounted) setState(() => _intentSummary = d.intent.summary);
  }

  Future<SessionDigest> _buildDigest() async =>
      _digest ??= await buildSessionDigest(
        ref.read(databaseProvider),
        sessionsA: widget.a,
        sessionsB: widget.b,
        comparison: widget.result,
        expected: widget.expected,
        check: widget.check,
        distanceStats: widget.distanceStats,
      );

  Future<void> _run({bool refresh = false}) async {
    final client = ref.read(aiAnalysisClientProvider);
    if (!client.hasConsent) {
      final ok = await showAiConsentSheet(context);
      if (!ok || !mounted) return;
      await ref.read(privacyProvider.notifier).setAiConsent(true);
    }
    setState(() {
      _busy = true;
      _slow = false;
      _error = null;
      _limit = null;
    });
    _slowTimer?.cancel();
    _slowTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _busy) setState(() => _slow = true);
    });
    try {
      final digest = (await _buildDigest()).withQuestion(_question.text);
      // A question the user just typed deserves a fresh answer.
      final r = await client.analyze(digest,
          refresh: refresh || _question.text.trim().isNotEmpty);
      if (!mounted) return;
      setState(() => _result = r);
    } on AiAnalysisLimitException catch (e) {
      if (mounted) setState(() => _limit = e.message);
    } on AiAnalysisException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Try again.');
      }
    } finally {
      _slowTimer?.cancel();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _report() async {
    final messenger = ScaffoldMessenger.of(context);
    final digest = await _buildDigest();
    final r = _result;
    final body = 'Describe the problem here:\n\n\n'
        '--- Details (numbers only, no positions) ---\n'
        'Model: ${r?.model ?? ''}\n'
        'Result: ${r == null ? '' : jsonEncode(r.toJson())}\n'
        'Digest: ${jsonEncode(digest.toJson())}\n';
    const email = AppConstants.supportEmail;
    if (email != null) {
      await launchUrl(Uri.parse('mailto:$email'
          '?subject=${Uri.encodeComponent('Problem with AI analysis')}'
          '&body=${Uri.encodeComponent(body)}'));
    } else {
      await Clipboard.setData(ClipboardData(text: body));
      messenger.showSnackBar(const SnackBar(
          content: Text('Details copied. Paste them into the support form.')));
      await launchUrl(Uri.parse(supportUrl),
          mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(aiAnalysisAvailableProvider)) {
      return const SizedBox.shrink();
    }
    final text = Theme.of(context).textTheme;
    final r = _result;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.auto_awesome, size: 18),
                const SizedBox(width: 6),
                Text('Reading it', style: text.titleSmall),
              ]),
              const SizedBox(height: 8),
              if (_busy)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _slow
                          ? 'Still reading… the first read in a while wakes '
                              'the analysis service, which can take up to '
                              '30 seconds.'
                          : 'Reading the numbers… (the first read in a while '
                              'can take up to 30 seconds)',
                      key: const ValueKey('ai-busy'),
                    ),
                  ),
                ])
              else if (r == null) ...[
                Text(
                  'Get a plain-English read of this comparison: what held '
                  'up, what didn\'t, what to try next.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 8),
                _intentAndQuestion(text),
                const SizedBox(height: 8),
                _button('Analyze with AI', _run),
              ] else ...[
                Text(r.headline,
                    style:
                        text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                for (final b in r.bullets)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  '),
                        Expanded(child: Text(b)),
                      ],
                    ),
                  ),
                if (r.caveats.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Caveats', style: text.labelLarge),
                  for (final c in r.caveats)
                    Text('– $c', style: text.bodySmall),
                ],
                if (r.nextStep.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Next step', style: text.labelLarge),
                  Text(r.nextStep, style: text.bodyMedium),
                ],
                const SizedBox(height: 8),
                Text(
                  'Written by Claude Haiku from the numbers above; it can '
                  'be wrong.',
                  style: text.bodySmall?.copyWith(color: context.status.muted),
                ),
                const SizedBox(height: 6),
                _intentAndQuestion(text),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                        onPressed: _report,
                        child: const Text('Report a problem')),
                    _button('Analyze again', () => _run(refresh: true),
                        tonal: false),
                  ],
                ),
              ],
              if (_limit != null) ...[
                const SizedBox(height: 8),
                _limitNote(text, _limit!),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: text.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "Analysis limit reached" plus the server's line: muted, no error red.
  Widget _limitNote(TextTheme text, String message) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_empty, size: 16, color: context.status.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Analysis limit reached', style: text.labelLarge),
                Text(message,
                    style:
                        text.bodySmall?.copyWith(color: context.status.muted)),
              ],
            ),
          ),
        ],
      );

  /// What the app thinks is being tested, plus the user's own question.
  Widget _intentAndQuestion(TextTheme text) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_intentSummary != null)
            Text('Comparing: $_intentSummary',
                style: text.bodySmall?.copyWith(color: context.status.muted)),
          const SizedBox(height: 6),
          TextField(
            controller: _question,
            maxLength: 300,
            maxLines: 2,
            minLines: 1,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              isDense: true,
              counterText: '',
              border: OutlineInputBorder(),
              labelText: 'Your question (optional)',
              hintText: 'e.g. Does the whip buy me range, or just a stronger '
                  'signal up close?',
            ),
          ),
        ],
      );

  Widget _button(String label, VoidCallback run, {bool tonal = true}) =>
      ProGate(
        feature: ProFeature.aiAnalysis,
        onUnlocked: run,
        builder: (context, unlocked, activate) => tonal
            // Full card width, so it doesn't sit alone at the left under
            // the full-width question field.
            ? SizedBox(
                width: double.infinity,
                child:
                    FilledButton.tonal(onPressed: activate, child: Text(label)))
            : TextButton(onPressed: activate, child: Text(label)),
      );
}

/// The "what is sent" sheet; true when the user agrees. Shared by the first
/// analysis and the Settings → Privacy switch (same consent pref).
Future<bool> showAiConsentSheet(BuildContext context,
        {String confirmLabel = 'Send & analyze'}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ConsentSheet(confirmLabel: confirmLabel),
    ) ??
    false;

/// One-time "what is sent" sheet. Pops true on the confirm button.
class _ConsentSheet extends StatelessWidget {
  const _ConsentSheet({required this.confirmLabel});

  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget item(IconData icon, String s) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(s, style: text.bodyMedium)),
            ],
          ),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Use the AI helpers?', style: text.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                        'Two things use them: Analyze on a comparison or a '
                        'test result, and a test request you type when '
                        'planning a test.',
                        style: text.bodyMedium),
                    const SizedBox(height: 12),
                    Text('What is sent', style: text.titleSmall),
                    item(
                        Icons.check,
                        'Each side\'s modem preset, hardware profile '
                        'names and net antenna gain, and how long you recorded.'),
                    item(
                        Icons.check,
                        'How many packets were heard, and their signal '
                        'strength: lowest, median and highest SNR, median RSSI.'),
                    item(
                        Icons.check,
                        'How many pings were answered, and how the '
                        'others failed (timeout, refused).'),
                    item(
                        Icons.check,
                        'Airtime and channel-busy percentages, and how '
                        'much the two routes overlap and differ (counts of map '
                        'squares).'),
                    item(
                        Icons.check,
                        'If shown, how each side did at different '
                        'distances from the base (distances only).'),
                    item(
                        Icons.check,
                        'The question or context you type in the box, '
                        'if any.'),
                    item(
                        Icons.check,
                        'When you plan a test: the sentence you type, the '
                        'names of your saved antennas and hardware profiles, and '
                        'the range setting names.'),
                    item(
                        Icons.check,
                        'The app version, and a random install id that '
                        'is used only for the daily and monthly limits.'),
                    const SizedBox(height: 10),
                    Text('What is not sent', style: text.titleSmall),
                    item(Icons.block,
                        'Your route, GPS positions or the base location.'),
                    item(
                        Icons.block,
                        'Node ids or names, keys or the channel '
                        'key.'),
                    const SizedBox(height: 10),
                    Text(
                      'This goes to our server and on to Anthropic, which '
                      'writes the reply. You are asked to agree once. Nothing '
                      'is sent until you tap Analyze, or type a test request '
                      'and tap Next; picking a test from the list never sends '
                      'anything. Withdraw any time in Settings → Privacy.',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Text('What to expect', style: text.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      'The reply is written by an AI model from those '
                      'numbers. It can misread them or state something that '
                      'is not so; your measurements are the record, the text '
                      'is a reading of them. It is not engineering, legal or '
                      'safety advice.',
                      style: text.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
