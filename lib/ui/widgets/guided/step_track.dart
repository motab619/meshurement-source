// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../../../services/guided/plan_models.dart';
import '../../theme/app_theme.dart';
import 'guided_styles.dart';

/// Who does a step, for the mono line under each card.
enum StepWho { you, automatic, walk }

StepWho whoDoes(StepKind kind) => switch (kind) {
      StepKind.walk => StepWho.walk,
      StepKind.preflight ||
      StepKind.changeRadios ||
      StepKind.settle ||
      StepKind.analyze =>
        StepWho.automatic,
      StepKind.swapHardware || StepKind.switchRadio || StepKind.goTo => StepWho.you,
    };

/// The plan as the arcade level-select: numbered boxy stops on a hairline,
/// the current one lit orange, done ones green. Each stop is a card with
/// the title (variant names as dashed-underline tappable values), a
/// one-line summary and the mono "● YOU / ● AUTOMATIC / ● WALK · RECORDED".
class StepTrack extends StatelessWidget {
  const StepTrack({
    super.key,
    required this.steps,
    required this.variants,
    this.onVariantTap,
    this.onMinutesTap,
  });

  final List<StepRecord> steps;
  final List<String> variants;

  /// Tapping a variant name in a title or summary (rename).
  final void Function(int variant)? onVariantTap;

  /// Tapping the "12 min" value of a walk step (change the route length).
  final VoidCallback? onMinutesTap;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant;
    return Stack(
      children: [
        Positioned(
          left: 13,
          top: 10,
          bottom: 10,
          child: Container(width: 2, color: line),
        ),
        Column(
          children: [
            for (final s in steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _Stop(
                  record: s,
                  variants: variants,
                  onVariantTap: onVariantTap,
                  onMinutesTap: onMinutesTap,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({
    required this.record,
    required this.variants,
    this.onVariantTap,
    this.onMinutesTap,
  });

  final StepRecord record;
  final List<String> variants;
  final void Function(int variant)? onVariantTap;
  final VoidCallback? onMinutesTap;

  /// [text] with every variant name (and, on walk steps, the minutes) as a
  /// tappable value.
  TextSpan _withValues(BuildContext context, String text, TextStyle? style) {
    final spans = <TextSpan>[];
    var rest = text;
    while (rest.isNotEmpty) {
      var bestAt = -1;
      var bestLen = 0;
      int? bestVariant;
      for (var i = 0; i < variants.length; i++) {
        final v = variants[i];
        if (v.isEmpty) continue;
        final at = rest.indexOf(v);
        if (at >= 0 && (bestAt < 0 || at < bestAt || (at == bestAt && v.length > bestLen))) {
          bestAt = at;
          bestLen = v.length;
          bestVariant = i;
        }
      }
      if (record.step.kind == StepKind.walk) {
        final m = RegExp(r'\d+ min').firstMatch(rest);
        if (m != null && (bestAt < 0 || m.start < bestAt)) {
          spans.add(TextSpan(text: rest.substring(0, m.start)));
          spans.add(variantValueSpan(context, m.group(0)!, onTap: onMinutesTap));
          rest = rest.substring(m.end);
          continue;
        }
      }
      if (bestAt < 0) {
        spans.add(TextSpan(text: rest));
        break;
      }
      spans.add(TextSpan(text: rest.substring(0, bestAt)));
      final v = bestVariant!;
      spans.add(variantValueSpan(context, variants[v],
          onTap: onVariantTap == null ? null : () => onVariantTap!(v)));
      rest = rest.substring(bestAt + bestLen);
    }
    return TextSpan(style: style, children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.status;
    final lit = record.status == StepStatus.active;
    final done = record.status == StepStatus.done || record.status == StepStatus.skipped;
    final who = whoDoes(record.step.kind);
    final whoColor = switch (who) {
      StepWho.you => status.warning,
      StepWho.automatic => scheme.secondary,
      StepWho.walk => status.ok,
    };
    final whoText = switch (who) {
      StepWho.you => '● YOU',
      StepWho.automatic => '● AUTOMATIC',
      StepWho.walk => '● WALK · RECORDED',
    };
    final body = theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(left: 36),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GuidedCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  _withValues(context, record.step.title,
                      body?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  _withValues(context, record.step.summary,
                      body?.copyWith(color: scheme.onSurfaceVariant, fontSize: 14)),
                ),
                const SizedBox(height: 6),
                Text(
                  whoText,
                  style: context.guidedMonoLabel.copyWith(color: whoColor),
                ),
              ],
            ),
          ),
          Positioned(
            left: -36,
            top: 10,
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: lit
                    ? scheme.primary
                    : done
                        ? status.okContainer
                        : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppTheme.radius),
                border: Border.all(
                  color: lit
                      ? scheme.primary
                      : done
                          ? status.ok
                          : scheme.outlineVariant,
                ),
              ),
              child: Text(
                '${record.step.ordinal + 1}',
                style: context.readout.value.copyWith(
                  fontSize: 12,
                  color: lit
                      ? scheme.onPrimary
                      : done
                          ? status.onOkContainer
                          : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The segmented progress strip at the top of the Run screen: done steps
/// green, the current one orange, the rest hairline.
class StepProgressStrip extends StatelessWidget {
  const StepProgressStrip({
    super.key,
    required this.count,
    required this.current,
  });

  final int count;

  /// 0-based ordinal of the current step.
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: i < current
                    ? theme.status.ok
                    : i == current
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
