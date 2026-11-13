// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/radio/mesh_radio.dart';
import '../../providers.dart';
import '../../utils/constants.dart';
import '../theme/app_theme.dart';

/// Big, colour-coded answer to "am I hearing the base?" for the Live tab
/// while a session records: green with the age of the last packet, red
/// with how long it has been silent, amber when the phone↔radio link is
/// down. Ticks once a second.
class BaseStatusBar extends ConsumerStatefulWidget {
  const BaseStatusBar({super.key});

  @override
  ConsumerState<BaseStatusBar> createState() => _BaseStatusBarState();
}

class _BaseStatusBarState extends ConsumerState<BaseStatusBar> {
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

  static String _ago(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds} s';
    final m = d.inMinutes, s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final inSession = ref.watch(activeSessionProvider).valueOrNull != null;
    if (!inSession) return const SizedBox.shrink();
    final link = ref.watch(meshLinkStateProvider).valueOrNull;
    final range = ref.watch(rangeStateProvider).valueOrNull;
    final monitor = ref.read(outOfRangeMonitorProvider);
    final last = monitor.lastHeardBase;
    final now = DateTime.now();
    final theme = Theme.of(context);
    final status = theme.status;

    final (Color bg, Color fg, IconData icon, String text) = switch (range) {
      _ when link != RadioConnectionState.ready => (
          status.lostContainer,
          status.onLostContainer,
          Icons.bluetooth_disabled,
          'Bluetooth link lost — nothing is being recorded',
        ),
      RangeState.inRange => (
          status.okContainer,
          status.onOkContainer,
          Icons.cell_tower,
          last == null
              ? 'Hearing the base'
              : 'Hearing the base · ${_ago(now.difference(last))} ago',
        ),
      RangeState.outOfRange => (
          status.dangerContainer,
          status.onDangerContainer,
          Icons.cell_tower,
          last == null
              ? 'Base not heard yet'
              : 'Base not heard for ${_ago(now.difference(last))}',
        ),
      RangeState.radioLost => (
          status.lostContainer,
          status.onLostContainer,
          Icons.bluetooth_disabled,
          'Bluetooth link lost — nothing is being recorded',
        ),
      RangeState.unknown || null => (
          status.neutral,
          status.onNeutral,
          Icons.hourglass_top,
          'Waiting to hear the base…',
        ),
    };

    return Semantics(
      liveRegion: true,
      label: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                // The one line read at arm's length on a walk: bigger than
                // the 13 pt label style.
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: fg, fontSize: 17),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
