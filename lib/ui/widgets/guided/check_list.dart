// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../../../services/guided/plan_models.dart';
import '../../theme/app_theme.dart';
import 'guided_styles.dart';

/// Label on a preflight row's fix key.
String preflightFixLabel(PreflightFix fix) => switch (fix) {
      PreflightFix.none => '',
      PreflightFix.connectRadio => 'Connect',
      PreflightFix.openRadioSetup => 'Open Node Setup',
      PreflightFix.setBaseLocation => 'Set base location',
      PreflightFix.enableRemoteAtBase => 'Enable at the base',
      PreflightFix.walkToBaseInstead => 'Walk to it instead',
    };

/// A card with one row per [CheckRow]: a 12 px square dot (green ok, cyan
/// blinking busy, amber warn, red fail) with its state in words beside it
/// ("OK", "Waiting", "Check", "Fix"), so no row relies on colour alone;
/// label, detail, and a fix key when the row has one. Used by the preflight step and the radio-change
/// progress list.
class CheckList extends StatelessWidget {
  const CheckList({super.key, required this.rows, this.onFix});

  final List<CheckRow> rows;
  final void Function(PreflightFix fix)? onFix;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant;
    return GuidedCard(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: line)),
              ),
              child: _Row(row: rows[i], onFix: onFix),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, this.onFix});

  final CheckRow row;
  final void Function(PreflightFix fix)? onFix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        CheckDot(status: row.status),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.label, style: theme.textTheme.bodyMedium),
              if (row.detail.isNotEmpty)
                Text(row.detail,
                    style: context.guidedFine.copyWith(fontSize: 13)),
            ],
          ),
        ),
        if (row.fix != PreflightFix.none && onFix != null) ...[
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: const TextStyle(fontSize: 13),
            ),
            onPressed: () {
              GuidedHaptics.tap();
              onFix!(row.fix);
            },
            child: Text(preflightFixLabel(row.fix)),
          ),
        ],
      ],
    );
  }
}

/// The state of a check in words, shown beside its dot.
String checkStatusText(CheckStatus s) => switch (s) {
      CheckStatus.ok => 'OK',
      CheckStatus.busy => 'Waiting',
      CheckStatus.warn => 'Check',
      CheckStatus.fail => 'Fix',
    };

/// The 12 px status square with its state in words. Busy blinks, unless
/// the system asks for reduced motion.
class CheckDot extends StatefulWidget {
  const CheckDot({super.key, required this.status});

  final CheckStatus status;

  @override
  State<CheckDot> createState() => _CheckDotState();
}

class _CheckDotState extends State<CheckDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didUpdateWidget(CheckDot old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  bool get _reduceMotion =>
      mounted && (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _sync() {
    if (widget.status == CheckStatus.busy && !_reduceMotion) {
      _blink.repeat();
    } else {
      _blink.stop();
      _blink.value = 0;
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = context.status;
    final color = switch (widget.status) {
      CheckStatus.ok => status.ok,
      CheckStatus.busy => status.info,
      CheckStatus.warn => status.warning,
      CheckStatus.fail => status.danger,
    };
    final word = checkStatusText(widget.status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _blink,
          builder: (context, _) => Opacity(
            opacity: widget.status == CheckStatus.busy && _blink.value >= 0.5
                ? 0.25
                : 1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 52,
          child: Text(word,
              style: context.guidedFine
                  .copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
