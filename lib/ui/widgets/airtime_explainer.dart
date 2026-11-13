// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../../data/radio/radio_preset.dart';
import '../../data/radio/radio_types.dart';
import '../../services/airtime_model.dart';
import '../../utils/constants.dart';
import '../protocol_text.dart';

/// Above this minimum interval the explainer is shown.
const _explainFromSec = 15;

/// "Long Slow takes about 3 seconds of air per ping, so pings are limited
/// to one every 61 s…" plus a plain-English primer. Shows nothing when the
/// preset's minimum interval is 15 s or less.
class AirtimeExplainer extends StatelessWidget {
  final String label;
  final double airtimeMs;
  final int minIntervalSec;

  /// Says "ping" on Meshtastic, "link check" on MeshCore.
  final RadioProtocol protocol;

  /// Inside an ⓘ sheet: always shown, and the primer is open (no "Learn
  /// more").
  final bool inline;

  const AirtimeExplainer({
    super.key,
    required this.label,
    required this.airtimeMs,
    required this.minIntervalSec,
    this.protocol = RadioProtocol.meshtastic,
    this.inline = false,
  });

  /// For a modem preset.
  factory AirtimeExplainer.forPreset(RadioPreset preset,
          {RadioProtocol protocol = RadioProtocol.meshtastic,
          bool inline = false}) =>
      AirtimeExplainer(
        label: preset.displayName,
        airtimeMs: AirtimeModel.probeAirtimeMsFor(preset, protocol: protocol),
        minIntervalSec:
            AirtimeModel.minIntervalSecFor(preset, protocol: protocol),
        protocol: protocol,
        inline: inline,
      );

  /// For a radio's current modulation (null = LONG_FAST numbers).
  factory AirtimeExplainer.forRadio(RadioPreset? preset,
          {RadioProtocol protocol = RadioProtocol.meshtastic}) =>
      AirtimeExplainer(
        label: (preset ?? AirtimeModel.defaultPreset).displayName,
        airtimeMs: protocol == RadioProtocol.meshtastic
            ? AirtimeModel.pingAirtimeMsFor(preset)
            : AirtimeModel.probeAirtimeMsFor(
                preset ?? AirtimeModel.defaultPreset,
                protocol: protocol),
        minIntervalSec:
            AirtimeModel.minIntervalSecFor(preset, protocol: protocol),
        protocol: protocol,
      );

  /// "0.4 s" under a second, else whole seconds ("3 s").
  static String formatAirtime(double ms) => ms < 1000
      ? '${(ms / 1000).toStringAsFixed(1)} s'
      : '${(ms / 1000).round()} s';

  @override
  Widget build(BuildContext context) {
    if (!inline && minIntervalSec <= _explainFromSec) {
      return const SizedBox.shrink();
    }
    final seconds = (airtimeMs / 1000).round();
    final air = airtimeMs < 1000
        ? '${(airtimeMs / 1000).toStringAsFixed(1)} seconds'
        : '$seconds ${seconds == 1 ? 'second' : 'seconds'}';
    final small = inline
        ? Theme.of(context).textTheme.bodyMedium
        : Theme.of(context).textTheme.bodySmall;
    final primer = Text(
      'Airtime is how long your node\'s radio occupies the '
      'channel while a packet is being sent. Slower range settings '
      'reach farther, but each packet takes much longer to '
      'transmit. Everyone nearby shares the same channel, and in '
      'some regions regulations limit how much of the time a '
      'radio may transmit, so we cap our own share (the duty '
      'cycle) at '
      '${(AirtimeModel.targetDuty * 100).round()}%. Staying '
      'under it also saves battery. The base node\'s '
      'beacon uses airtime too, which is why Node Setup limits '
      'its interval as well.\n\n'
      'During a session "Air" is our estimate: the airtime of '
      'the ${probeNoun(protocol, plural: true)} this app sent over the last minute. It is a '
      'lower bound, because your node also sends its own '
      'NodeInfo, position and telemetry. The "Radio" line is '
      'what your node\'s radio itself measured, reported about once a '
      'minute: "TX" is how much of the last hour it transmitted '
      '(everything, so it moves slowly), and "channel" is how '
      'busy the air was over the last minute with everyone\'s '
      'traffic. Above 25% channel use your node skips optional '
      'sends (telemetry, NodeInfo and the base beacon), '
      'so the figure turns amber then.',
      style: small,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1, right: 6),
                child: Icon(Icons.timer_outlined, size: 14),
              ),
              Expanded(
                child: Text(
                  '$label takes about $air of air per '
                  '${probeNoun(protocol)}, so ${probeNoun(protocol, plural: true)} are '
                  'limited to one every '
                  '${AppConstants.formatSeconds(minIntervalSec)} to keep your '
                  'node\'s radio under a ${(AirtimeModel.targetDuty * 100).round()}% '
                  'duty cycle.',
                  style: small,
                ),
              ),
            ],
          ),
          if (inline) ...[
            const SizedBox(height: 8),
            primer,
          ] else
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text('Learn more', style: small),
              children: [primer, const SizedBox(height: 8)],
            ),
        ],
      ),
    );
  }
}
