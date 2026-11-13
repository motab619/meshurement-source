// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/radio/mesh_radio.dart';
import '../../providers.dart';

/// Short status for the map pill, e.g. "Nodes 62%" or "Pairing… 14s".
String connectProgressLabel(ConnectProgress? p, DateTime now) {
  if (p == null) return 'Connecting…';
  final secs = now.difference(p.stepStartedAt).inSeconds;
  final elapsed = secs >= 5 ? ' ${secs}s' : '';
  return switch (p.state) {
    RadioConnectionState.configuring when p.fraction != null =>
      'Nodes ${(p.fraction! * 100).round()}%',
    RadioConnectionState.configuring
        when p.detail != null && p.step == 'Downloading node list' =>
      'Nodes ${p.detail!.split(' ').first}',
    RadioConnectionState.configuring => 'Reading settings…$elapsed',
    RadioConnectionState.pairing => 'Pairing…$elapsed',
    RadioConnectionState.reconnecting => 'Reconnecting…',
    _ => 'Connecting…$elapsed',
  };
}

/// Advice for a step that's taking a while; null when there's nothing to add.
String? _hint(ConnectProgress p, int secs) {
  switch (p.state) {
    case RadioConnectionState.connecting:
      return secs >= 8
          ? 'Make sure the node is on and nearby, and close any other app '
              'using it (such as the Meshtastic or MeshCore app).'
          : null;
    case RadioConnectionState.pairing:
      return 'If the phone asks for a PIN, type the one shown on the radio\'s '
          'screen (no screen: 123456).';
    case RadioConnectionState.configuring:
      if (p.step == 'Downloading node list' && secs >= 10) {
        return 'Nodes that have heard many other nodes take longer. This happens '
            'once per connection.';
      }
      return null;
    case RadioConnectionState.reconnecting:
      return 'The app keeps trying until you disconnect.';
    default:
      return null;
  }
}

/// Live connect progress: step, counts, a bar, elapsed time and a hint.
/// Ticks once a second so the elapsed time and retry countdown move.
class ConnectProgressView extends ConsumerStatefulWidget {
  const ConnectProgressView({super.key});

  @override
  ConsumerState<ConnectProgressView> createState() =>
      _ConnectProgressViewState();
}

class _ConnectProgressViewState extends ConsumerState<ConnectProgressView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(connectProgressProvider).valueOrNull;
    final theme = Theme.of(context);
    final now = DateTime.now();
    if (p == null) {
      return const Row(children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 8),
        Text('Connecting…'),
      ]);
    }
    final secs = now.difference(p.stepStartedAt).inSeconds;
    final String status;
    if (p.state == RadioConnectionState.reconnecting && p.retryAt != null) {
      final wait = p.retryAt!.difference(now).inSeconds;
      status = wait > 0
          ? 'Lost the Bluetooth link to your node. Retry ${p.attempt} in '
              '${wait}s'
          : 'Lost the Bluetooth link to your node. Retry ${p.attempt}…';
    } else {
      status = '${p.step}…';
    }
    final hint = _hint(p, secs);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(status, style: theme.textTheme.bodyMedium)),
            if (p.state != RadioConnectionState.reconnecting)
              Text('${secs}s',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: p.fraction),
        if (p.detail != null) ...[
          const SizedBox(height: 4),
          Text(p.detail!, style: theme.textTheme.bodySmall),
        ],
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(hint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}
