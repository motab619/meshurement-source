// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/radio/mesh_radio.dart';
import '../../providers.dart';
import '../../services/airtime_model.dart';
import '../../services/gps_service.dart';
import '../../services/link_asymmetry.dart';
import '../../utils/constants.dart';
import '../protocol_text.dart';
import '../theme/app_theme.dart';
import 'beacon_status.dart';
import 'radio_stats_readout.dart' show radioStatsMaxAge;

/// GPS accuracy at or under this is "good" (green); above it amber.
const gpsGoodAccuracyM = 10.0;

/// The colour of a GPS state (new-user walkthrough 2026-11-08): green with
/// a fix of ±10 m or better, amber with a looser fix, red with no fix.
/// Unknown / not asked yet are not a problem: [StatusColors.muted].
Color gpsStateColor(StatusColors status, GpsState gps) {
  switch (gps.status) {
    case GpsStatus.fix:
      final acc = gps.accuracy;
      return gps.approximate || acc == null || acc > gpsGoodAccuracyM
          ? status.warning
          : status.ok;
    case GpsStatus.searching:
    case GpsStatus.denied:
    case GpsStatus.off:
      return status.danger;
    case GpsStatus.unknown:
    case GpsStatus.notAsked:
      return status.muted;
  }
}

/// "12:34" or "1:02:03".
String formatElapsed(Duration d) {
  if (d.isNegative) d = Duration.zero;
  String two(int v) => v.toString().padLeft(2, '0');
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Pings of one session that were on air: answered (by the base or a
/// relay) of sent. Throttled and NAKed pings never left the radio and
/// pending ones have no outcome yet; none of them count.
({int answered, int sent}) pingTally(Iterable<PingResult> pings,
    {DateTime? now, int timeoutSec = AppConstants.defaultAckTimeoutSec}) {
  final t = now ?? DateTime.now();
  var answered = 0, sent = 0;
  for (final p in pings) {
    final st = p.correlation.ackStatus;
    if (st == AckStatus.throttled || AckStatus.isError(st)) continue;
    final pending = p.correlation.ackEventId == null &&
        st == AckStatus.timeout &&
        t.difference(p.tx.timestamp).inSeconds < timeoutSec;
    if (pending) continue;
    sent++;
    if (st == AckStatus.received || st == AckStatus.implicit) answered++;
  }
  return (answered: answered, sent: sent);
}

/// Pings of one session, live. Not autoDispose, like `beaconStatsProvider`
/// (a drift watch cancelled from the widget-test zone hangs `db.close`).
final _sessionPingsProvider =
    StreamProvider.family<List<PingResult>, ({int mapId, int sessionId})>(
        (ref, key) {
  return ref.watch(databaseProvider).watchPingsForMap(key.mapId).map((all) => [
        for (final p in all)
          if (p.tx.sessionId == key.sessionId) p
      ]);
});

/// Uplink vs downlink SNR of one session's replies (MeshCore traces carry
/// both legs); null for Meshtastic or with too few replies.
final _sessionAsymmetryProvider =
    StreamProvider.family<LinkAsymmetry?, ({int mapId, int sessionId})>(
        (ref, key) {
  return ref.watch(databaseProvider).watchEventsForMap(key.mapId).map((all) =>
      linkAsymmetryFromEvents(
          all.where((e) => e.sessionId == key.sessionId)));
});

/// One cell: small caps label, big mono value, small sub-label.
class SessionStatCell extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;
  final Color? subColor;

  const SessionStatCell({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.valueColor,
    this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: '$label: $value${sub == null ? '' : ', $sub'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: theme.readout.label.copyWith(color: muted)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: theme.readout.valueLarge.copyWith(
                    fontSize: 22,
                    color: valueColor ?? theme.colorScheme.onSurface),
              ),
            ),
            if (sub != null)
              Text(
                sub!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: subColor ?? muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// The recording panel's 2×3 stat grid (new-user walkthrough 2026-11-08,
/// #1): Readings · Beacons · Round trips / GPS · Airtime · Elapsed. The
/// numbers that matter during a walk, apart from the setup facts. A ping
/// (or link check) is a round trip: the reply needs both directions. On
/// MeshCore a line under the grid compares the two legs' SNR.
class SessionStatsGrid extends ConsumerStatefulWidget {
  final Session session;
  const SessionStatsGrid({super.key, required this.session});

  @override
  ConsumerState<SessionStatsGrid> createState() => _SessionStatsGridState();
}

class _SessionStatsGridState extends ConsumerState<SessionStatsGrid> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Elapsed time, and pending pings turning into results.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
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
    final session = widget.session;
    final status = context.status;
    final meshCore = sessionProtocol(session) == RadioProtocol.meshcore;

    // Readings.
    final count =
        ref.watch(sessionPacketCountProvider(session.id)).valueOrNull ?? 0;
    final readings = SessionStatCell(
      key: const ValueKey('stat-readings'),
      label: 'Readings',
      value: '$count',
      sub: 'recorded',
    );

    // Beacons heard of expected.
    final kind = BeaconKind.fromDb(session.beaconKind);
    final stats = ref.watch(beaconStatsProvider(session.id)).valueOrNull;
    final pct = stats == null ? null : beaconHeardPct(stats);
    final Widget beacons;
    if (stats == null || pct == null) {
      beacons = SessionStatCell(
        key: const ValueKey('stat-beacons'),
        label: kind == BeaconKind.trace ? 'Link checks' : 'Beacons',
        value: '—',
        sub: 'none expected yet',
      );
    } else {
      final expected = stats.heard + stats.missed;
      final approx = !stats.exact && kind != BeaconKind.trace;
      beacons = SessionStatCell(
        key: const ValueKey('stat-beacons'),
        label: kind == BeaconKind.trace ? 'Link checks' : 'Beacons',
        value: '${stats.heard}/${approx ? '~' : ''}$expected',
        valueColor: heardBandColor(status, pct),
        sub: '$pct % ${kind == BeaconKind.trace ? 'answered' : 'heard'}',
      );
    }

    // Pings answered of sent (on air): round trips, both legs needed.
    final Widget pingsCell;
    const pingLabel = 'Round trips';
    if (session.pingIntervalSec <= 0) {
      pingsCell = SessionStatCell(
        key: const ValueKey('stat-pings'),
        label: pingLabel,
        value: '—',
        sub: meshCore ? 'link checks off' : 'pings off',
      );
    } else {
      final pings = ref
              .watch(_sessionPingsProvider(
                  (mapId: session.coverageMapId, sessionId: session.id)))
              .valueOrNull ??
          const <PingResult>[];
      final tally = pingTally(pings);
      final p =
          tally.sent == 0 ? null : (100 * tally.answered / tally.sent).round();
      pingsCell = SessionStatCell(
        key: const ValueKey('stat-pings'),
        label: pingLabel,
        value: p == null ? '—' : '${tally.answered}/${tally.sent}',
        valueColor: p == null ? null : heardBandColor(status, p),
        sub: p == null
            ? 'every ${AppConstants.formatSeconds(session.pingIntervalSec)}'
            : '$p % came back',
      );
    }

    // MeshCore only: how the base heard us vs how we heard it.
    final asymmetry = meshCore && session.pingIntervalSec > 0
        ? ref
            .watch(_sessionAsymmetryProvider(
                (mapId: session.coverageMapId, sessionId: session.id)))
            .valueOrNull
        : null;

    // GPS.
    final gps = ref.watch(gpsStatusProvider).valueOrNull ??
        ref.read(gpsServiceProvider).state;
    final gpsCell = SessionStatCell(
      key: const ValueKey('stat-gps'),
      label: 'GPS',
      value: gps.status == GpsStatus.fix
          ? '±${(gps.accuracy ?? 0).round()} m'
          : 'No fix',
      valueColor: gpsStateColor(status, gps),
      sub: switch (gps.status) {
        GpsStatus.fix => gps.approximate ? 'approximate' : 'fix',
        GpsStatus.searching => 'searching',
        GpsStatus.denied => 'permission off',
        GpsStatus.off => 'location off',
        GpsStatus.unknown || GpsStatus.notAsked => 'checking',
      },
    );

    // Airtime: our own estimate, the radio's measurement under it.
    final duty = ref.watch(airtimeDutyProvider).valueOrNull ?? 0;
    final warn = duty > AirtimeModel.warnDuty;
    final radioStats = ref.watch(radioChannelStatsProvider).valueOrNull;
    final fresh = radioStats != null &&
        DateTime.now().difference(radioStats.measuredAt) <= radioStatsMaxAge;
    final busy = fresh &&
        radioStats.channelUtilizationPercent >
            AirtimeModel.channelPoliteLimitPercent;
    final airtime = Tooltip(
      message: 'Airtime of your node\'s radio over the last minute (our '
          'estimate)'
          '${fresh ? '. Under it, what the radio measured: how much of the '
              'last hour it transmitted and how busy the channel was' : ''}'
          '${warn ? ' (high: pings may be throttled)' : ''}',
      child: SessionStatCell(
        key: const ValueKey('stat-airtime'),
        label: 'Airtime',
        value: '${(duty * 100).toStringAsFixed(1)} %',
        valueColor: warn ? status.warning : null,
        sub: fresh
            ? 'radio TX ${radioStats.airUtilTxPercent.toStringAsFixed(1)} %/h'
                ' · channel ${radioStats.channelUtilizationPercent.round()} %'
            : 'last minute',
        subColor: busy ? status.warning : null,
      ),
    );

    // Elapsed.
    final elapsed = SessionStatCell(
      key: const ValueKey('stat-elapsed'),
      label: 'Elapsed',
      value: formatElapsed(DateTime.now().difference(session.startedAt)),
      sub: 'recording',
    );

    Widget row(List<Widget> cells) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final c in cells) Expanded(child: c)],
        );
    return Container(
      key: const ValueKey('session-stats-grid'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        children: [
          row([readings, beacons, pingsCell]),
          row([gpsCell, airtime, elapsed]),
          if (asymmetry != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
              child: Text(
                linkAsymmetryText(asymmetry,
                    noun: probeNoun(RadioProtocol.meshcore, plural: true)),
                key: const ValueKey('stat-asymmetry'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
