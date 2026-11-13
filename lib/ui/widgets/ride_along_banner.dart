// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../services/base_ride_along_detector.dart';
import '../../services/diag_log.dart';
import '../theme/app_theme.dart';

/// Amber card on the Live map when the base seems to be travelling with
/// the phone (left in the car, then driven off with the session still
/// recording): offers to stop the session and drop what was recorded since
/// the drive began. Never blocks; "Keep going" hides it for the session.
class RideAlongBanner extends ConsumerWidget {
  /// Called after "Stop & trim" removed points from [sessionId] (the map
  /// redraws that session's dots).
  final void Function(int sessionId)? onTrimmed;

  const RideAlongBanner({super.key, this.onTrimmed});

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _points(int n) => n == 1 ? '1 point' : '$n points';

  Future<void> _stop(BuildContext context, WidgetRef ref, RideAlongEvent event,
      {required bool trim}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final sessions = ref.read(sessionManagerProvider);
    final db = ref.read(databaseProvider);
    final sessionId = sessions.activeSession?.id;
    DiagLog.instance.log('rideAlong', trim ? 'stop & trim' : 'stop only');
    await sessions.endSession();
    if (!trim || sessionId == null) {
      messenger?.showSnackBar(const SnackBar(content: Text('Session stopped')));
      return;
    }
    final r = await db.trimSessionAfter(sessionId, event.startedAt);
    DiagLog.instance.log(
        'rideAlong', 'trimmed ${r.deleted} events (${r.received} received)');
    onTrimmed?.call(sessionId);
    messenger?.showSnackBar(SnackBar(
        content: Text('Session stopped; ${_points(r.received)} dropped')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(rideAlongPendingProvider).valueOrNull;
    if (event == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final status = theme.status;
    final fg = status.onWarningContainer;
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: fg,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(44, 36),
    );
    return Container(
      key: const ValueKey('ride-along-banner'),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 2),
      decoration: BoxDecoration(
        color: status.warningContainer.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.directions_car, size: 18, color: fg),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    'Looks like the base is riding with you since '
                    '${_hhmm(event.startedAt)}. Stop the session and drop '
                    'the ${_points(event.samplesSince)} since then?',
                    style: theme.textTheme.bodySmall?.copyWith(color: fg),
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 2,
            children: [
              TextButton(
                key: const ValueKey('ride-along-trim'),
                style: buttonStyle,
                onPressed: () => _stop(context, ref, event, trim: true),
                child: const Text('Stop & trim'),
              ),
              TextButton(
                key: const ValueKey('ride-along-stop'),
                style: buttonStyle,
                onPressed: () => _stop(context, ref, event, trim: false),
                child: const Text('Stop only'),
              ),
              TextButton(
                key: const ValueKey('ride-along-keep'),
                style: buttonStyle,
                onPressed: () =>
                    ref.read(baseRideAlongDetectorProvider).dismiss(),
                child: const Text('Keep going'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
