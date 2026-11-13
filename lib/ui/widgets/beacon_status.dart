// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/radio/mesh_radio.dart';
import '../../providers.dart';
import '../../services/radio_profile_service.dart';
import '../../services/radio_roles.dart';
import '../../utils/user_errors.dart';
import '../theme/app_theme.dart';

/// Share of the expected beacons that were heard, as a whole percent;
/// null while nothing has been expected yet.
int? beaconHeardPct(BeaconStats stats) {
  final expected = stats.heard + stats.missed;
  return expected == 0 ? null : (100 * stats.heard / expected).round();
}

/// The band colour for a heard share (beacons, pings): at least 80 % ok,
/// 50 to 80 % amber, below 50 % red (new-user walkthrough 2026-11-08: a
/// bare "~19 missed" read as failure with nothing to measure it against).
Color heardBandColor(StatusColors status, int pct) => pct >= 80
    ? status.ok
    : pct >= 50
        ? status.warning
        : status.danger;

/// "Beacons 41 of 44 (93 %)" (sequence numbers, exact) or "Beacons 41 of
/// ~44 (93 %)" (misses from timing, approximate). For the pulled beacon
/// ([BeaconKind.trace]) every check is known: "Link checks 41 of 44
/// answered (93 %)". Nothing until a beacon has been heard or missed.
String? beaconStatsText(BeaconStats stats,
    {BeaconKind kind = BeaconKind.none}) {
  final pct = beaconHeardPct(stats);
  if (pct == null) return null;
  final expected = stats.heard + stats.missed;
  if (kind == BeaconKind.trace) {
    return 'Link checks ${stats.heard} of $expected answered ($pct %)';
  }
  final of = stats.exact ? '$expected' : '~$expected';
  return 'Beacons ${stats.heard} of $of ($pct %)';
}

/// [beaconStatsText] coloured by [heardBandColor]; "Beacons: none
/// expected yet" before the first one is due.
class BeaconStatsLine extends ConsumerWidget {
  final int sessionId;

  /// The session's beacon (`BeaconKind.dbValue`), for the wording.
  final String? sessionBeaconKind;
  const BeaconStatsLine(
      {super.key, required this.sessionId, this.sessionBeaconKind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(beaconStatsProvider(sessionId)).valueOrNull;
    if (stats == null) return const SizedBox.shrink();
    final kind = BeaconKind.fromDb(sessionBeaconKind);
    final text = beaconStatsText(stats, kind: kind);
    final pct = beaconHeardPct(stats);
    final theme = Theme.of(context);
    if (text == null || pct == null) {
      return Text(
        kind == BeaconKind.trace
            ? 'Link checks: none expected yet'
            : 'Beacons: none expected yet',
        key: const ValueKey('beacon-stats'),
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    return Text(text,
        key: const ValueKey('beacon-stats'),
        style: TextStyle(color: heardBandColor(theme.status, pct)));
  }
}

/// Shown when the base answers pings but its beacon stopped arriving (an
/// older radio that lacks the beacon, or one that switched it off): the
/// silence is not a dead zone. Offers to switch the base to the telemetry
/// beacon, which needs Bluetooth range of the base.
class BeaconAbsentNotice extends ConsumerStatefulWidget {
  /// The beacon the session was set up with (`BeaconKind.dbValue`).
  final String sessionBeaconKind;
  const BeaconAbsentNotice({super.key, required this.sessionBeaconKind});

  @override
  ConsumerState<BeaconAbsentNotice> createState() => _BeaconAbsentNoticeState();
}

class _BeaconAbsentNoticeState extends ConsumerState<BeaconAbsentNotice> {
  bool _busy = false;
  String? _result;

  Future<void> _switch() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      await ref.read(radioProfileServiceProvider).switchBaseToTelemetry();
      _result = 'Done. The base restarts and the beacon returns shortly.';
    } catch (e) {
      _result = '${userMessage(e)} Try again when you are back at the base.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final absent = ref.watch(beaconAbsentProvider).valueOrNull ?? false;
    if (!absent && _result == null) return const SizedBox.shrink();
    final kind = BeaconKind.fromDb(widget.sessionBeaconKind);
    // The pulled beacon is the mobile's own link check: nothing on the
    // base to switch.
    final trace = kind == BeaconKind.trace;
    final canSwitch = !trace && kind != BeaconKind.telemetry;
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('beacon-absent'),
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (absent)
            Text(
              trace
                  ? 'Base is heard but isn\'t answering link checks. Its '
                      'relaying may be off or it is on another frequency: '
                      'run Node Setup on the base. Gaps are not counted as '
                      'dead zones.'
                  : 'Base is reachable but its beacon is off. Pings still '
                      'measure the link; gaps are not counted as dead zones.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.status.warning),
            ),
          if (absent && canSwitch)
            TextButton(
              onPressed: _busy ? null : _switch,
              child: Text(
                  _busy ? 'Switching…' : 'Switch base to telemetry beacon'),
            ),
          if (_result != null)
            Text(_result!, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Range Test switches itself off 8 hours after the base starts (firmware
/// 2.7 `RangeTestModule`); after that the base sends nothing and a drive
/// maps an empty map. Text for the warning, or null when it doesn't apply.
/// [restartedAt] is when Radio Setup last wrote (and so restarted) the
/// base.
String? baseBeaconAgeWarning(
    ({BeaconKind kind, int intervalSec, DateTime? since})? beacon,
    DateTime? restartedAt,
    DateTime now) {
  if (beacon == null ||
      beacon.kind != BeaconKind.rangeTest ||
      beacon.intervalSec <= 0) {
    return null;
  }
  // Set up before restarts were recorded: the beacon's start will do.
  final started = restartedAt ?? beacon.since;
  if (started == null) return null;
  final age = now.difference(started);
  if (age < rangeTestAutoOff) return null;
  return "Your base probably isn't broadcasting any more. Its test signal "
      'switches itself off 8 hours after the base starts, and it was set '
      'up ${age.inHours} h ago. Unless the base has been restarted since, '
      'power-cycle it, or run Node Setup on it to switch to the telemetry '
      'beacon, which never switches off.';
}

/// The firmware's Range Test sender cut-off (2.7: 28800000 ms after boot).
const rangeTestAutoOff = Duration(hours: 8);

/// [baseBeaconAgeWarning] as an amber line (Session panel, before and
/// during a session).
class BaseBeaconAgeNotice extends ConsumerWidget {
  const BaseBeaconAgeNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(radioRolesProvider);
    final text = baseBeaconAgeWarning(
        roles.baseBeacon, roles.baseRestartedAt, DateTime.now());
    if (text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('base-beacon-age'),
      padding: const EdgeInsets.only(top: 4),
      child: Text(text,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.status.warning)),
    );
  }
}

/// Whether [BaseBeaconBanner] has anything to show: the phone is connected
/// to the base itself and Radio Setup recorded its beacon (running, or
/// switched off since). The map uses this to put the banner where the
/// signal readout would be.
bool baseBeaconBannerShows(RadioRoles roles, MeshRadio radio, bool ready) {
  final beacon = roles.baseBeacon;
  // A pulled beacon (MeshCore) runs on the mobile: the base sends nothing
  // to stop or restart.
  return ready &&
      beacon != null &&
      beacon.kind != BeaconKind.trace &&
      radio.protocol != RadioProtocol.meshcore &&
      roles.roleOf(radio) == RadioRole.base;
}

/// The recorded beacon is switched off (Stop after a session).
bool baseBeaconIsOff(
        ({BeaconKind kind, int intervalSec, DateTime? since})? beacon) =>
    beacon != null &&
    (beacon.kind == BeaconKind.none || beacon.intervalSec <= 0);

/// "Base beacon on since Oct 20" with a Stop button, shown while the phone
/// is connected to the base radio itself (so the beacon isn't left running
/// after testing).
class BaseBeaconBanner extends ConsumerStatefulWidget {
  const BaseBeaconBanner({super.key});

  @override
  ConsumerState<BaseBeaconBanner> createState() => _BaseBeaconBannerState();
}

class _BaseBeaconBannerState extends ConsumerState<BaseBeaconBanner> {
  bool _busy = false;
  String? _error;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Which button is working ('stop' or 'restart'), while [_busy].
  String? _action;

  Future<void> _run(String action, Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _action = action;
      _error = null;
    });
    try {
      await work();
    } catch (e) {
      _error = userMessage(e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _action = null;
        });
      }
    }
  }

  Future<void> _stop() => _run(
      'stop', () => ref.read(radioProfileServiceProvider).stopBaseBeacon());

  /// Switch the beacon back on at the default interval; the kind follows
  /// the base's firmware (telemetry on 2.8+, Range Test on 2.7).
  Future<void> _start() => _run(
      'start',
      () => ref
          .read(radioProfileServiceProvider)
          .setBaseBeacon(const BeaconConfig(intervalSec: 60)));

  /// Reboot the base: for a Range Test beacon this starts its 8-hour clock
  /// over. The banner disappears while the base is down and comes back
  /// when the app reconnects.
  Future<void> _restart() => _run(
      'restart',
      () => ref
          .read(radioProfileServiceProvider)
          .restartBase(ref.read(meshRadioProvider)));

  @override
  Widget build(BuildContext context) {
    final roles = ref.watch(radioRolesProvider);
    final radio = ref.watch(meshRadioProvider);
    final ready = ref.watch(meshLinkStateProvider).valueOrNull ==
        RadioConnectionState.ready;
    final beacon = roles.baseBeacon;
    if (!baseBeaconBannerShows(roles, radio, ready) || beacon == null) {
      return const SizedBox.shrink();
    }
    final since = beacon.since?.toLocal();
    final when =
        since == null ? '' : ' since ${_months[since.month - 1]} ${since.day}';
    final theme = Theme.of(context);
    final status = theme.status;
    if (baseBeaconIsOff(beacon)) {
      return Container(
        key: const ValueKey('base-beacon-off'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: status.warningContainer.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _error ?? 'Base beacon is off · sessions record pings only',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: status.onWarningContainer),
            ),
            TextButton(
              onPressed: _busy ? null : _start,
              child: Text(_action == 'start' ? 'Starting…' : 'Start beacon'),
            ),
          ],
        ),
      );
    }
    return Container(
      key: const ValueKey('base-beacon-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.neutral.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _error ??
                'Base beacon on$when · '
                    '${RadioProfileService.beaconSummary(BeaconConfig(intervalSec: beacon.intervalSec, kind: beacon.kind)).replaceFirst('Base beacon: ', '')}',
            style: theme.textTheme.bodySmall?.copyWith(color: status.onNeutral),
          ),
          // Wraps (Stop under Restart) at large text sizes rather than
          // overflowing the narrow banner; keeps full-size touch targets.
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: _busy ? null : _restart,
                child: Text(_action == 'restart' ? 'Restarting…' : 'Restart'),
              ),
              TextButton(
                onPressed: _busy ? null : _stop,
                child: Text(_action == 'stop' ? 'Stopping…' : 'Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
