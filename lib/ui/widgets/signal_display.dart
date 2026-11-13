// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/processed_signal_event.dart';
import '../../providers.dart';
import '../../services/radio_roles.dart';
import '../../services/airtime_model.dart';
import '../../utils/constants.dart';
import '../../utils/link_margin.dart';
import '../../utils/signal_color_mapper.dart';
import '../theme/app_theme.dart';

/// Floating overlay showing live signal metrics
class SignalDisplay extends ConsumerWidget {
  const SignalDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Latest live packet, else the latest recorded sample (e.g. a resumed
    // session) so the readout isn't blank.
    final event = ref.watch(liveSignalProvider).valueOrNull ??
        ref.watch(signalHistoryProvider).latestEvent;
    final scale = MarginScale.of(ref.watch(meshRadioProvider).currentPreset);
    final theme = Theme.of(context);
    final chrome = theme.mapChrome;

    if (event == null) {
      return Semantics(
          label: 'Signal readout. Waiting for signal.',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: chrome.panel,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Waiting for\nsignal…',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: chrome.onOverlayMuted),
                  textAlign: TextAlign.center,
                ),
                AirtimeReadout(color: chrome.onOverlayMuted),
              ],
            ),
          ));
    }

    // Hybrid SNR/RSSI link margin: same colour as the reading's map dot.
    final margin = scale.marginDb(snr: event.rxSnr, rssi: event.rxRssi);
    final marginColor =
        margin == null ? null : SignalColorMapper.fromMargin(margin);
    final baseNodeNum = ref.watch(radioRolesProvider).nodeOf(RadioRole.base);
    final origin = signalOriginLabel(event, baseNodeNum: baseNodeNum);
    final source = signalSourceLine(event, origin, baseNodeNum: baseNodeNum);
    final relayed = event.hopCount > 0;
    // VoiceOver hears the numbers, not just "signal readout".
    final spoken = [
      'Signal readout',
      if (event.rxSnr != null) 'SNR ${event.rxSnr!.toStringAsFixed(1)} dB',
      if (event.rxRssi != null) 'RSSI ${event.rxRssi} dBm',
      if (relayed) 'relayed by another node, ${event.hopCount} hops',
      origin,
      if (source != null) 'from $source',
    ].join(', ');
    return Semantics(
        label: '$spoken.',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: chrome.panel.copyWith(
            border: Border.all(
              color: marginColor ?? chrome.hairline,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // SNR
              if (event.rxSnr != null)
                _MetricRow(
                  label: 'SNR',
                  value: '${event.rxSnr!.toStringAsFixed(1)} dB',
                  color: marginColor!,
                ),
              // RSSI
              if (event.rxRssi != null)
                _MetricRow(
                  label: 'RSSI',
                  value: '${event.rxRssi} dBm',
                  color: SignalColorMapper.fromRssi(event.rxRssi!),
                ),
              // Hops: a Radio Setup test is point to point (both nodes
              // LOCAL_ONLY on the private channel), so a reading is
              // direct and "Hops: 0" was noise (Andy, field test
              // 2026-11-08). Only a relayed reading is worth a line.
              if (relayed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    'Relayed by another node, not a direct reading',
                    key: const ValueKey('signal-relayed'),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.status.warning),
                  ),
                ),
              // What this reading was, in words (not "Direction: Received").
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  origin,
                  key: const ValueKey('signal-origin'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: chrome.onOverlayMuted),
                ),
              ),
              // Source, when it adds something to the line above.
              if (source != null)
                Text(
                  source,
                  key: const ValueKey('signal-source'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: chrome.onOverlayMuted),
                ),
              AirtimeReadout(color: chrome.onOverlayMuted),
            ],
          ),
        ));
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: theme.readout.label
                .copyWith(color: theme.mapChrome.onOverlayMuted),
          ),
          Text(
            value,
            style: theme.readout.value.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// What a reading was, for the signal readout: "Heard from base", "Reply
/// to your ping", "Heard from another node" or "Sent" (new-user
/// walkthrough 2026-11-08: "Direction: Received" was jargon).
String signalOriginLabel(ProcessedSignalEvent e, {int? baseNodeNum}) {
  final d = e.direction.toLowerCase();
  if (d == PacketDirection.tx) return 'Sent';
  // A ping reply: an ACK, or the recorded reply loaded on resume.
  if (d == PacketDirection.ack || e.sourceNodeName == 'ping reply') {
    return 'Reply to your ping';
  }
  if (baseNodeNum != null && e.sourceNodeId == baseNodeNum) {
    return 'Heard from base';
  }
  // A sample from history has no node number: say no more than we know.
  if (e.sourceNodeId == 0) return 'Heard';
  return 'Heard from another node';
}

/// The node name under [origin], or null when it would only repeat it:
/// empty, the "ping reply" placeholder of a reloaded reply (field test
/// 2026-11-08: "Reply to your ping" over "ping reply"), or the base's own
/// name (under "Heard from base", or a reply that came from the base). A
/// reply relayed by another node, or "Heard from another node", keeps the
/// name: it says which node.
String? signalSourceLine(ProcessedSignalEvent e, String origin,
    {int? baseNodeNum}) {
  final name = e.sourceNodeName.trim();
  if (name.isEmpty || name == 'ping reply') return null;
  if (origin == 'Heard from base') return null;
  if (baseNodeNum != null && e.sourceNodeId == baseNodeNum) return null;
  return name;
}

/// "Air 1.2%": our radio's recent duty cycle, shown while a session is
/// recording. Amber with a warning icon above [AirtimeModel.warnDuty].
class AirtimeReadout extends ConsumerWidget {
  /// Text colour when under the warning level; the theme's secondary text
  /// colour when null.
  final Color? color;
  final double fontSize;

  const AirtimeReadout({
    super.key,
    this.color,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recording = ref.watch(activeSessionProvider).valueOrNull != null;
    if (!recording) return const SizedBox.shrink();
    final duty = ref.watch(airtimeDutyProvider).valueOrNull ?? 0;
    final warn = duty > AirtimeModel.warnDuty;
    final theme = Theme.of(context);
    final c = warn
        ? theme.status.warning
        : color ?? theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: 'Airtime of your node\'s radio over the last minute'
          '${warn ? ' (high: pings may be throttled)' : ''}',
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(warn ? Icons.warning_amber_rounded : Icons.podcasts,
                size: fontSize + 2, color: c),
            const SizedBox(width: 3),
            Text(
              'Air ${(duty * 100).toStringAsFixed(1)}%',
              style: theme.readout.value.copyWith(
                color: c,
                fontSize: fontSize,
                fontWeight: warn ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
