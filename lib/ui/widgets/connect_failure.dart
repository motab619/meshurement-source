// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/radio/radio_types.dart';
import '../../utils/platform_text.dart';
import '../../utils/user_errors.dart';
import '../protocol_text.dart';
import '../theme/app_theme.dart';

/// A failed connect, in parts: what happened, why (when the error says),
/// what to try, and the raw text for a problem report. First run
/// 2026-11-07: the dialog showed one red paragraph, generic tips and
/// "FlutterBluePlusException | discoverServices | fbp-code: 6 | Device is
/// disconnected" in it, for a radio that was simply too far away
/// (−106 dBm on the scan).
class ConnectFailure {
  const ConnectFailure({
    required this.headline,
    required this.cause,
    required this.tips,
    required this.detail,
  });

  /// "Couldn't connect to MeshCore-MeshTest Base".
  final String headline;

  /// Plain words for the recognised cause; empty when nothing is known.
  final String cause;

  /// Things to try, in order; empty when the cause already says what to do.
  final List<String> tips;

  /// The raw error, for the Details expander.
  final String detail;
}

/// Below this scan RSSI (dBm) a dropped link is most likely distance.
const weakScanRssiDbm = -85;

/// Classify [error] from connecting to [device].
ConnectFailure connectFailure(Object error, RadioDescriptor device) {
  final name = device.name.isEmpty ? 'the node' : device.name;
  final headline = 'Couldn\'t connect to $name';
  final raw = error.toString();
  final detail =
      raw.replaceFirst(RegExp(r'^(Bad state|Exception|Error): '), '');
  final lower = raw.toLowerCase();
  final app = protocolLabel(device.protocol);
  final otherApp = 'Close the $app app and any other app using this node.';
  final pin = 'If ${PlatformText.isAndroid ? 'the phone' : 'iOS'} asks for '
      'a PIN, use the one on the node\'s screen (no screen: 123456).';
  final forget = 'If the node was reset or re-flashed, forget it in '
      '${PlatformText.bluetoothDevices}, then try again.';
  final rssi = device.scanRssi;
  final weak = rssi != null && rssi < weakScanRssiDbm;
  final weakNote = weak
      ? ' The signal was weak ($rssi dBm on the scan); move closer and try '
          'again.'
      : '';

  if (isLostBondError(raw) ||
      (error is PlatformException &&
          '${error.code} ${error.message ?? ''}'
              .toLowerCase()
              .contains(RegExp('permission|unauthorized|powered|adapter')))) {
    // userMessage already says what to do.
    return ConnectFailure(
        headline: headline,
        cause: userMessage(error),
        tips: const [],
        detail: detail);
  }
  if (error is TimeoutException ||
      lower.contains('timeout') ||
      lower.contains('timed out')) {
    return ConnectFailure(
      headline: headline,
      cause: 'It didn\'t answer in time.$weakNote',
      tips: [
        if (!weak) 'Make sure the node is on and nearby.',
        otherApp,
        pin,
      ],
      detail: detail,
    );
  }
  if (lower.contains('pairing') ||
      lower.contains('authentication') ||
      lower.contains('encryption')) {
    return ConnectFailure(
      headline: headline,
      cause: 'Pairing didn\'t complete.',
      tips: [pin, forget],
      detail: detail,
    );
  }
  if (lower.contains('disconnected') ||
      lower.contains('connection') ||
      lower.contains('fbp-code: 6')) {
    return ConnectFailure(
      headline: headline,
      cause: 'It dropped the connection before answering.$weakNote',
      tips: [
        if (!weak) 'Move the node closer to the phone.',
        otherApp,
        forget,
      ],
      detail: detail,
    );
  }
  // A worded refusal from the radio layer, else the three generic tips.
  final worded = userMessage(error);
  final generic = worded.startsWith('Something went wrong') ||
      worded.startsWith('Bluetooth problem');
  return ConnectFailure(
    headline: headline,
    cause: generic ? '' : worded,
    tips: [otherApp, pin, forget],
    detail: detail,
  );
}

/// The failure laid out: headline in the error colour, the cause, a
/// numbered "Things to try" in normal ink, and the raw error behind a
/// Details toggle in monospace.
class ConnectFailureView extends StatefulWidget {
  const ConnectFailureView(this.failure, {super.key});
  final ConnectFailure failure;

  @override
  State<ConnectFailureView> createState() => _ConnectFailureViewState();
}

class _ConnectFailureViewState extends State<ConnectFailureView> {
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = widget.failure;
    final small = theme.textTheme.bodySmall;
    final muted = small?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          f.headline,
          key: const ValueKey('connect-failure-headline'),
          style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error, fontWeight: FontWeight.w600),
        ),
        if (f.cause.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(f.cause, style: theme.textTheme.bodyMedium),
        ],
        if (f.tips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Things to try', style: theme.textTheme.labelLarge),
          for (var i = 0; i < f.tips.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 18, child: Text('${i + 1}.', style: small)),
                  Expanded(child: Text(f.tips[i], style: small)),
                ],
              ),
            ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('connect-failure-details'),
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: () => setState(() => _details = !_details),
            child: Text(_details ? 'Hide details' : 'Details'),
          ),
        ),
        if (_details)
          SelectableText(
            f.detail,
            style: muted?.copyWith(
                fontFamily: ReadoutStyles.monoFamily, fontSize: 11),
          ),
      ],
    );
  }
}
