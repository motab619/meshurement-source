// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../services/airtime_model.dart';
import '../theme/app_theme.dart';

/// Reports older than this are not shown (the radio normally reports every
/// minute, so this means the link or the radio's reporting stopped).
const radioStatsMaxAge = Duration(minutes: 30);

/// "2 min ago" style age for [at] relative to [now].
String formatStatsAge(DateTime at, DateTime now) {
  final s = now.difference(at).inSeconds;
  if (s < 90) return 'just now';
  final m = (s / 60).round();
  if (m < 60) return '$m min ago';
  return '${(m / 60).round()} h ago';
}

/// "Radio: TX 1.2%/h · channel 8% · 2 min ago": what the radio itself
/// measured, next to our own "Air" estimate. Nothing while unknown or
/// stale. The channel figure is amber above
/// [AirtimeModel.channelPoliteLimitPercent].
class RadioStatsReadout extends ConsumerStatefulWidget {
  /// Text colour; the theme's secondary text colour when null.
  final Color? color;
  final double fontSize;

  const RadioStatsReadout({
    super.key,
    this.color,
    this.fontSize = 12,
  });

  @override
  ConsumerState<RadioStatsReadout> createState() => _RadioStatsReadoutState();
}

class _RadioStatsReadoutState extends ConsumerState<RadioStatsReadout> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Keep the "x min ago" text fresh between reports.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(radioChannelStatsProvider).valueOrNull;
    if (stats == null) return const SizedBox.shrink();
    final now = DateTime.now();
    if (now.difference(stats.measuredAt) > radioStatsMaxAge) {
      return const SizedBox.shrink();
    }
    final busy = stats.channelUtilizationPercent >
        AirtimeModel.channelPoliteLimitPercent;
    final theme = Theme.of(context);
    final style = theme.readout.value.copyWith(
      color: widget.color ?? theme.colorScheme.onSurfaceVariant,
      fontSize: widget.fontSize,
      fontWeight: FontWeight.w400,
    );
    return Tooltip(
      message: 'Measured by your node\'s radio: how much of the last hour it '
          'transmitted (everything it sends, not just pings) and how busy '
          'the channel was over the last minute'
          '${busy ? ' (high: your node holds back optional traffic)' : ''}',
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text.rich(
          TextSpan(style: style, children: [
            TextSpan(
                text: 'Radio: TX '
                    '${stats.airUtilTxPercent.toStringAsFixed(1)}%/h · channel '),
            TextSpan(
              text: '${stats.channelUtilizationPercent.round()}%',
              style: busy
                  ? TextStyle(
                      color: theme.status.warning, fontWeight: FontWeight.bold)
                  : null,
            ),
            TextSpan(text: ' · ${formatStatsAge(stats.measuredAt, now)}'),
          ]),
        ),
      ),
    );
  }
}
