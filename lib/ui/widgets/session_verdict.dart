// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/radio/radio_types.dart';
import '../../providers.dart';
import '../../services/field_report/field_report_data.dart';
import '../../services/field_report/field_report_loader.dart';
import '../../services/units.dart';
import '../theme/app_theme.dart';
import 'beacon_status.dart' show heardBandColor;

/// What a session expected from the base, for "0 of 12 beacons".
String _expectedNoun(Session s) {
  final kind = BeaconKind.fromDb(s.beaconKind);
  if (kind == BeaconKind.trace) return 'link checks';
  final pings = s.pingIntervalSec > 0;
  final beacon = kind != BeaconKind.none;
  if (beacon && pings) return 'beacons and pings';
  if (pings) return 'pings';
  return 'beacons';
}

/// "+7 dB" / "-3 dB".
String _db(double v) {
  final r = v.round();
  return '${r >= 0 ? '+' : '-'}${r.abs()} dB';
}

/// One sentence for a just-ended session, in the Compare screen's voice
/// (new-user walkthrough 2026-11-08, #10): "Base heard 41 % · farthest
/// 2.2 mi · median +7 dB". Never empty: a session that never heard the
/// base says so ("Base node not heard · 0 of 12 beacons").
String sessionVerdict(FieldReportData d, Session session,
    {required bool miles}) {
  final pct = d.baseHeardPct;
  if (pct == null) {
    return 'Base node not heard · nothing from it was due in this session';
  }
  if (d.baseHeard == 0) {
    return 'Base node not heard · 0 of ${d.baseExpected} '
        '${_expectedNoun(session)}';
  }
  return [
    'Base heard $pct %',
    if (d.farthestM case final m?) 'farthest ${formatDistance(m, miles: miles)}',
    if (d.medianMarginDb case final m?) 'median ${_db(m)}',
  ].join(' · ');
}

/// A session's report data and row, read once (the session has ended).
final _endedSessionProvider = FutureProvider.autoDispose
    .family<(FieldReportData, Session)?, int>((ref, sessionId) async {
  final db = ref.watch(databaseProvider);
  final session = await db.getSessionById(sessionId);
  if (session == null) return null;
  final data = await FieldReportLoader(db).session(sessionId);
  return data == null ? null : (data, session);
});

/// [sessionVerdict] for [sessionId], coloured by how much of the base was
/// heard; "Session saved" while it loads or if it can't be read.
class SessionVerdictText extends ConsumerWidget {
  final int sessionId;
  const SessionVerdictText({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(_endedSessionProvider(sessionId)).valueOrNull;
    final theme = Theme.of(context);
    final style = theme.textTheme.titleSmall;
    if (loaded == null) return Text('Session saved', style: style);
    final (data, session) = loaded;
    final pct = data.baseHeardPct;
    return Text(
      sessionVerdict(data, session, miles: ref.watch(useMilesProvider)),
      key: const ValueKey('ended-session-verdict'),
      style: style?.copyWith(
          color: pct == null
              ? theme.colorScheme.onSurfaceVariant
              : heardBandColor(theme.status, pct)),
    );
  }
}
