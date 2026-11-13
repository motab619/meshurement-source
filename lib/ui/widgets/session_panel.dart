// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database/app_database.dart';
import '../../data/radio/mesh_radio.dart';
import '../../providers.dart';
import '../../services/airtime_model.dart';
import '../../services/base_node.dart';
import '../../services/diag_log.dart';
import '../../services/live_activity_service.dart';
import '../../services/gps_service.dart';
import '../../services/pro_entitlement.dart';
import '../../services/radio_profile_service.dart';
import '../../services/radio_roles.dart';
import '../../services/rig_math.dart';
import '../../services/session_manager.dart';
import '../../services/session_radio_settings.dart';
import '../protocol_text.dart';
import '../screens/guided/guided_test_flow.dart';
import '../screens/pro_paywall_screen.dart';
import '../theme/app_theme.dart';
import '../../utils/constants.dart';
import '../../utils/user_errors.dart';
import 'airtime_explainer.dart';
import 'beacon_status.dart';
import 'session_stats_grid.dart';
import 'session_verdict.dart';
import 'session_radios.dart';
import '../screens/radio_setup_screen.dart';
import '../screens/rig_profiles_screen.dart';
import 'create_map_dialog.dart';
import 'field_report/field_report_sheet.dart';
import 'get_started_card.dart' show onLastGetStartedStep;
import '../../utils/app_info.dart';
import '../../utils/platform_text.dart';

/// Sessions of a map, newest first (for the "earlier sessions used another
/// base" note).
final _mapSessionsProvider =
    StreamProvider.autoDispose.family<List<Session>, int>((ref, mapId) {
  return ref.watch(databaseProvider).watchSessionsForMap(mapId);
});

class SessionPanel extends ConsumerStatefulWidget {
  const SessionPanel({super.key, this.onClose});

  /// Set when the panel is docked beside the map (iPad, Duo unfolded:
  /// [WindowClass.sidePanel]) rather than in a bottom sheet: no drag
  /// handle, it fills its column, and the header gets a close button.
  final VoidCallback? onClose;

  bool get docked => onClose != null;

  @override
  ConsumerState<SessionPanel> createState() => _SessionPanelState();
}

class _SessionPanelState extends ConsumerState<SessionPanel> {
  final _nameController = TextEditingController();
  int? _mapId;

  /// Base radio picked by hand when Radio Setup has none (mesh node number).
  int? _pickedBaseNum;
  bool _ping = true;
  int? _mobileRigId;
  int? _baseRigId;
  bool _rigsLoaded = false;
  bool _busy = false;

  /// Why the last Start Session tap failed (shown under the button).
  String? _startError;

  /// The session just ended here: the start form offers its field report
  /// until a new session starts or the offer is closed.
  int? _endedSessionId;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  int get _pingIntervalSec =>
      AppConstants.pingIntervalSec(ref.read(sharedPreferencesProvider));

  /// The preset (and channel) are set on the radios in Radio Setup. The
  /// panel rebuilds on return to show the radio's new preset.
  Future<void> _openRadioSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RadioSetupScreen()),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(activeSessionProvider).valueOrNull;
    final theme = Theme.of(context);

    Widget content(ScrollController? scrollController) {
      final list = ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.docked)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Session Controls',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  key: const ValueKey('session-panel-close'),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ],
            )
          else ...[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Session Controls',
              style: theme.textTheme.titleLarge,
            ),
          ],
          const SizedBox(height: 16),
          if (session != null)
            ..._activeSession(context, session)
          else
            ..._startForm(context),
        ],
      );
      if (session == null) return list;
      // While recording, End session is pinned to the sheet's bottom
      // edge, visible at any sheet height and scroll position (new-user
      // walkthrough 2026-11-08: it was below the fold at half height).
      return Column(
        children: [
          Expanded(child: list),
          _endSessionBar(context),
        ],
      );
    }

    if (widget.docked) return content(null);
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => content(scrollController),
    );
  }

  Widget _endSessionBar(BuildContext context) {
    final theme = Theme.of(context);
    final status = theme.status;
    return DecoratedBox(
      decoration: BoxDecoration(
        border:
            Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('end-session'),
              style: FilledButton.styleFrom(
                backgroundColor: status.danger,
                foregroundColor: status.onDanger,
              ),
              onPressed: _busy ? null : _confirmEndSession,
              icon: const Icon(Icons.stop),
              label: const Text('End session'),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Status lines ────────────────────────────────────

  Widget _statusLine(String text,
      {bool problem = false, Key? key, Color? color}) {
    final theme = Theme.of(context);
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: color ??
              (problem
                  ? theme.status.warning
                  : theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  GpsState get _gps =>
      ref.watch(gpsStatusProvider).valueOrNull ??
      ref.read(gpsServiceProvider).state;

  /// "GPS: fix ±5 m" green within 10 m, amber looser, red without a fix.
  Widget _gpsLine() {
    final gps = _gps;
    final line = gpsStatusLine(gps);
    return _statusLine(line.text,
        problem: line.problem,
        color: gpsStateColor(context.status, gps),
        key: const ValueKey('gps-status'));
  }

  /// What the out-of-range monitor did this session, e.g.
  /// "Range: out 12:32 → back 12:37", so a missed alert still shows.
  Widget? _rangeEventsLine() {
    final events = ref.watch(rangeEventsProvider).valueOrNull ?? const [];
    final shown = events
        .where((e) =>
            e.state == RangeState.outOfRange ||
            e.state == RangeState.radioLost ||
            e.state == RangeState.inRange)
        .toList();
    // Skip the initial "in range" — only transitions worth knowing about.
    if (shown.isEmpty || shown.every((e) => e.state == RangeState.inRange)) {
      return null;
    }
    String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    final parts = <String>[];
    for (final e in shown) {
      final word = switch (e.state) {
        RangeState.outOfRange => 'out',
        RangeState.radioLost => 'Bluetooth lost',
        RangeState.inRange => parts.isEmpty ? null : 'back',
        RangeState.unknown => null,
      };
      if (word != null) parts.add('$word ${hm(e.at.toLocal())}');
    }
    final tail = parts.length > 6 ? parts.sublist(parts.length - 6) : parts;
    final last = shown.last.state;
    return _statusLine('Range: ${tail.join(' → ')}',
        problem: last != RangeState.inRange);
  }

  /// Live Activity state, iOS only ([problem] from LiveActivityService).
  Widget? _liveActivityLine() {
    if (!LiveActivityService.deviceSupported) return null;
    final problem = ref.watch(liveActivityProblemProvider).valueOrNull;
    if (problem == null) {
      return _statusLine('Live Activity: shows on the lock screen and '
          'Dynamic Island once you leave the app.');
    }
    if (problem == 'pro') {
      // No paywall unasked: a line saying what Pro adds, and a link.
      return Row(
        key: const ValueKey('live-activity-pro'),
        children: [
          Expanded(
            child: _statusLine('Live Activity (the recording on the lock '
                'screen and Dynamic Island) comes with ${AppInfo.proName}.'),
          ),
          TextButton(
            onPressed: () =>
                showProPaywall(context, feature: ProFeature.liveActivity),
            child: const Text('See Pro'),
          ),
        ],
      );
    }
    final text = switch (problem) {
      'disabled' =>
        'Live Activity is off for ${AppInfo.displayName}. Turn it on in '
            'iOS Settings → ${AppInfo.displayName} → Live Activities, then start a new '
            'session.',
      'unsupported' =>
        'Live Activity could not start (needs iOS 16.2 or later).',
      'background' => 'Live Activity starts next time the app is in front.',
      _ => 'Live Activity could not start '
          '(${problem.startsWith('error: ') ? problem.substring(7) : problem}).',
    };
    return _statusLine(text, problem: true);
  }

  // ─── Recording ───────────────────────────────────────

  List<Widget> _activeSession(BuildContext context, Session session) {
    final maps = ref.watch(coverageMapsProvider).valueOrNull ?? const [];
    final mapName = maps
            .where((m) => m.id == session.coverageMapId)
            .map((m) => m.name)
            .firstOrNull ??
        '';
    final linkState = ref.watch(meshLinkStateProvider).valueOrNull;
    final reconnectNotice = ref.watch(autoReconnectNoticeProvider);
    final started = session.startedAt.toLocal();
    final theme = Theme.of(context);
    final status = theme.status;
    // MeshCore: the ping is a trace, and it is also the base beacon.
    final meshCore = sessionProtocol(session) == RadioProtocol.meshcore;
    final gps = _gps;
    final liveActivityProblem = LiveActivityService.deviceSupported &&
        ref.watch(liveActivityProblemProvider).valueOrNull != null;

    // Setup facts: known before the walk, so folded away (new-user
    // walkthrough 2026-11-08: thirteen lines in one block).
    final setup = <Widget>[
      SessionRadios(baseNodeNum: _sessionBaseNum(session)),
      const SizedBox(height: 6),
      Text('Map: $mapName'),
      if (RigSpec.decode(session.mobileRigJson) case final r?)
        Text('Mobile hardware: ${r.name} (${formatGainDb(r.netGainDb)})'),
      if (RigSpec.decode(session.baseRigJson) case final r?)
        Text('Base hardware: ${r.name} (${formatGainDb(r.netGainDb)})'),
      Text('Started: ${started.hour.toString().padLeft(2, '0')}:'
          '${started.minute.toString().padLeft(2, '0')}'),
      if (session.loraPreset.isNotEmpty)
        Text('Range setting: ${anyPresetDisplayName(session.loraPreset)}'),
      if (session.radioSettingsLine case final line when line.isNotEmpty)
        Text(line),
      Text(session.pingIntervalSec > 0
          ? '${meshCore ? 'Checking the link to the base every ' : 'Pinging the base node every '}'
              '${AppConstants.formatSeconds(session.pingIntervalSec)}'
              '${session.pingIntervalSec < AirtimeModel.minIntervalSecFor(ref.read(meshRadioProvider).currentPreset, protocol: ref.read(meshRadioProvider).protocol) ? ' (faster than recommended)' : ''}'
          : meshCore
              ? 'Passive (no link checks)'
              : 'Passive (no pings)'),
      if (session.pingIntervalSec > 0 && session.packetAirtimeMs > 0)
        Text('≈${session.packetAirtimeMs.round()} ms of airtime per '
            '${meshCore ? 'check' : 'ping'}'),
      if (!liveActivityProblem)
        if (_liveActivityLine() case final line?) line,
    ];

    return [
      Row(
        children: [
          Icon(Icons.fiber_manual_record, color: status.danger, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              session.name.isNotEmpty ? session.name : 'Recording',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SessionStatsGrid(session: session),
      // Problems stay in view, under the numbers.
      if (linkState != RadioConnectionState.ready)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Node not connected over Bluetooth — nothing is being '
            'recorded until it reconnects.',
            style: TextStyle(color: status.warning),
          ),
        ),
      if (linkState != RadioConnectionState.ready && reconnectNotice != null)
        _statusLine(reconnectNotice, problem: true),
      if (session.pingIntervalSec > 0 &&
          ref.watch(pingBlockedReasonProvider).valueOrNull != null)
        _statusLine(
            meshCore
                ? 'Link checks paused: your node is on the public mesh '
                    'settings. Run Node Setup to put it back on the private '
                    'test frequency.'
                : 'Pings paused: your node is on the public channel. Run '
                    'Node Setup to put it back on the private test channel.',
            problem: true),
      // The GPS cell says "No fix"; the line says why.
      if (gps.status != GpsStatus.fix || gps.approximate) _gpsLine(),
      BeaconAbsentNotice(sessionBeaconKind: session.beaconKind),
      const BaseBeaconAgeNotice(),
      if (_rangeEventsLine() case final line?) line,
      if (liveActivityProblem)
        if (_liveActivityLine() case final line?) line,
      if (ref.watch(notificationsAllowedProvider).valueOrNull == false)
        _statusLine('Notifications are off, so out-of-range alerts won\'t '
            'reach the lock screen (${PlatformText.appNotifications}).'),
      const SizedBox(height: 4),
      _disclosure(
        key: const ValueKey('session-setup'),
        title: 'Setup',
        subtitle: [
          if (mapName.isNotEmpty) mapName,
          if (session.loraPreset.isNotEmpty)
            anyPresetDisplayName(session.loraPreset),
        ].join(' · '),
        children: setup,
      ),
    ];
  }

  /// A collapsed-by-default section (Setup, Hardware profiles).
  Widget _disclosure({
    required Key key,
    required String title,
    String subtitle = '',
    bool initiallyExpanded = false,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Theme(
      // No divider lines above and below the expanded tile.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: key,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        expandedAlignment: Alignment.centerLeft,
        initiallyExpanded: initiallyExpanded,
        title: Text(title, style: theme.textTheme.titleSmall),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        children: children,
      ),
    );
  }

  Future<void> _confirmEndSession() async {
    final status = context.status;
    final end = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End session?'),
        content: const Text('The session ends; its data is kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continue session'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: status.danger,
              foregroundColor: status.onDanger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End'),
          ),
        ],
      ),
    );
    if (end == true && mounted) await _endSession();
  }

  Future<void> _endSession() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final service = ref.read(radioProfileServiceProvider);
    final beaconOn = ref.read(radioRolesProvider).baseBeacon;
    final meshCore =
        ref.read(meshRadioProvider).protocol == RadioProtocol.meshcore;
    final endingId = ref.read(activeSessionProvider).valueOrNull?.id;
    try {
      await ref.read(sessionManagerProvider).endSession();
      if (mounted) setState(() => _endedSessionId = endingId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // The base keeps sending (airtime, battery) until told to stop. A
    // pulled beacon (MeshCore) stops with the session.
    if (!meshCore &&
        beaconOn != null &&
        beaconOn.kind != BeaconKind.none &&
        beaconOn.kind != BeaconKind.trace &&
        beaconOn.intervalSec > 0) {
      _showTimed(
        messenger,
        SnackBar(
          duration: const Duration(seconds: 12),
          showCloseIcon: true,
          content: const Text('The base is still sending its beacon.'),
          action: SnackBarAction(
            label: 'Stop beacon…',
            onPressed: () => _confirmStopBaseBeacon(messenger, service),
          ),
        ),
      );
    }
  }

  /// Show [bar] and make sure it goes away after its duration. With an
  /// action, Flutter keeps a snackbar up for ever when iOS accessibility
  /// navigation is on (VoiceOver, Switch Control, Full Keyboard Access),
  /// and a stuck "Stop it" bar covers the Settings rows.
  void _showTimed(ScaffoldMessengerState? messenger, SnackBar bar) {
    final shown = messenger?.showSnackBar(bar);
    if (shown == null) return;
    Future<void>.delayed(bar.duration, shown.close);
  }

  /// "Stop it" on a passing snackbar read like "dismiss this" and switched
  /// the base's beacon off with one tap (bench, 2026-10-26: the next
  /// sessions then ran with no beacon and nothing said so). Ask first.
  Future<void> _confirmStopBaseBeacon(
      ScaffoldMessengerState? messenger, RadioProfileService service) async {
    final ctx = messenger?.context;
    if (ctx == null || !ctx.mounted) return;
    final stop = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop the base beacon?'),
        content: const Text(
            'The base keeps sending its beacon until told to stop. Stopping '
            'saves its battery and airtime, but the next session records '
            'nothing from the base until the beacon is started again '
            '(Node Setup, or the beacon card when connected to the base).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it on')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Stop beacon')),
        ],
      ),
    );
    if (stop == true) await _stopBaseBeacon(messenger, service);
  }

  /// Stop the base's beacon over a temporary connection to it. The error,
  /// if any, stays up long enough to read and offers a retry (the usual
  /// cause is the base being out of Bluetooth range).
  Future<void> _stopBaseBeacon(
      ScaffoldMessengerState? messenger, RadioProfileService service) async {
    try {
      await service.stopBaseBeacon();
      messenger
          ?.showSnackBar(const SnackBar(content: Text('Base beacon stopped.')));
    } catch (e) {
      DiagLog.instance.log('beacon', 'stop base beacon failed: $e');
      _showTimed(
        messenger,
        SnackBar(
          duration: const Duration(seconds: 15),
          showCloseIcon: true,
          content: Text('Couldn\'t stop the base beacon: ${userMessage(e)} '
              'The phone needs to be within Bluetooth range of the base.'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _stopBaseBeacon(messenger, service),
          ),
        ),
      );
    }
  }

  /// Mesh node number of a recording session's base radio: its own, else
  /// (sessions from before schema v8) its map's.
  int? _sessionBaseNum(Session session) {
    final maps = ref.watch(coverageMapsProvider).valueOrNull ?? const [];
    final nodes = ref.watch(nodesProvider).valueOrNull ?? const [];
    final localId = session.baseNodeId ??
        maps
            .where((m) => m.id == session.coverageMapId)
            .map((m) => m.baseNodeId)
            .firstOrNull;
    return nodes.where((n) => n.id == localId).map((n) => n.nodeId).firstOrNull;
  }

  /// The base radio the next session will use: the Radio Setup base, else
  /// the one picked by hand.
  int? get _chosenBaseNum =>
      ref.read(radioRolesProvider).nodeOf(RadioRole.base) ?? _pickedBaseNum;

  /// Base radio row for the start form: the Radio Setup base read-only, or
  /// (none set up) a warning and a picker of known radios.
  Widget _baseRadioSection(MeshRadio radio) {
    final roles = ref.watch(radioRolesProvider);
    final setupBase = roles.nodeOf(RadioRole.base);
    final status = context.status;
    if (setupBase != null) return SessionRadios(baseNodeNum: setupBase);

    final nodes = ref.watch(nodesProvider).valueOrNull ?? const [];
    final mobileNum = roles.nodeOf(RadioRole.mobile);
    final options = buildBaseNodeOptions(
      radioNodes: radio.nodes.values,
      dbNodes: nodes,
      myNum: radio.myNodeId,
      baseNum: null,
      excludeNums: {if (mobileNum != null) mobileNum},
    );
    if (!options.any((o) => o.nodeNum == _pickedBaseNum)) _pickedBaseNum = null;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SessionRadios(baseNodeNum: _pickedBaseNum),
        // Only until a base is picked (A16 first run: the warning stayed
        // under a picked base and sat on the field's floating label).
        if (_pickedBaseNum == null) ...[
          const SizedBox(height: 4),
          Text(
            'No base node set up — run Settings → Node Setup',
            key: const ValueKey('no-setup-base'),
            style: TextStyle(color: status.warning),
          ),
        ],
        if (options.isNotEmpty) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            key: ValueKey('base-pick-${options.length}'),
            initialValue: _pickedBaseNum,
            isExpanded: true,
            itemHeight: null,
            decoration: const InputDecoration(
              labelText: 'Or pick the base node (the one that stays put)',
            ),
            // The closed field shows the name only: the menu entries' second
            // line (id, last heard) spilled below the field's border.
            selectedItemBuilder: (context) => [
              for (final (i, o) in options.indexed) ...[
                if (i == 0 || options[i - 1].group != o.group)
                  const SizedBox.shrink(),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(o.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
            items: [
              for (final (i, o) in options.indexed) ...[
                if (i == 0 || options[i - 1].group != o.group)
                  DropdownMenuItem<int>(
                    enabled: false,
                    child: Text(
                      switch (o.group) {
                        BaseNodeGroup.yourBase => 'YOUR BASE',
                        BaseNodeGroup.direct => 'HEARD DIRECTLY',
                        BaseNodeGroup.other => 'OTHER NODES ON THE MESH',
                      },
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                // Two lines, not one wrapped one: on a phone every entry
                // ("Name  (SHRT · !id · direct · 22d ago)") broke mid-detail
                // and the menu read as a wall of text (first run on the A16).
                DropdownMenuItem(
                  value: o.nodeNum,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.label,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (o.detail.isNotEmpty)
                          Text(
                            o.detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
            onChanged: (v) => setState(() => _pickedBaseNum = v),
          ),
        ],
      ],
    );
  }

  /// One-line amber note when the map's newest session used a different
  /// base radio than this one will. Not a block: moving to a new base is
  /// legitimate, but comparisons assume the same base position.
  Widget? _baseMismatchNote(int? mapId, int? baseNum) {
    if (mapId == null || baseNum == null) return null;
    final sessions =
        ref.watch(_mapSessionsProvider(mapId)).valueOrNull ?? const [];
    if (sessions.isEmpty) return null;
    final maps = ref.watch(coverageMapsProvider).valueOrNull ?? const [];
    final mapBase =
        maps.where((m) => m.id == mapId).map((m) => m.baseNodeId).firstOrNull;
    final localId = sessions
            .map((s) => s.baseNodeId)
            .firstWhere((id) => id != null, orElse: () => null) ??
        mapBase;
    if (localId == null) return null;
    final nodes = ref.watch(nodesProvider).valueOrNull ?? const [];
    final prev = nodes.where((n) => n.id == localId).firstOrNull;
    if (prev == null || prev.nodeId == baseNum) return null;
    final label = radioIdentityLabel(prev.nodeId,
        dbNode: prev, live: ref.read(meshRadioProvider).nodes[prev.nodeId]);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Earlier sessions on this map used $label. Comparisons across '
        'sessions assume the same base position.',
        key: const ValueKey('base-mismatch'),
        style: TextStyle(color: context.status.warning),
      ),
    );
  }

  // ─── Start form ──────────────────────────────────────

  List<Widget> _startForm(BuildContext context) {
    final radio = ref.read(meshRadioProvider);
    final guidedRow = ListTile(
      key: const ValueKey('guided-test-row'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.route),
      title: const Text('Guided test'),
      subtitle: const Text('Say what you want to find out; the app plans the '
          'walks and talks you through them.'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => GuidedTestFlow.open(context, mapId: _mapId),
    );
    final connected = ref.watch(meshLinkStateProvider).valueOrNull ==
        RadioConnectionState.ready;
    final public = connected && radio.onPublicChannel;
    final ready = connected && !public;
    final maps = ref.watch(coverageMapsProvider).valueOrNull ?? const [];
    if (_mapId != null && !maps.any((m) => m.id == _mapId)) _mapId = null;
    _mapId ??= maps.isNotEmpty ? maps.last.id : null;

    final effectiveSec = ref
        .read(sessionManagerProvider)
        .effectivePingIntervalSec(_pingIntervalSec);
    final recommendedSec = AirtimeModel.minIntervalSecFor(radio.currentPreset,
        protocol: radio.protocol);
    final status = context.status;
    // MeshCore: the ping is a trace, and it is also the base beacon.
    final meshCore = radio.protocol == RadioProtocol.meshcore;

    // Built first: it loads the remembered choices the summary reads.
    final rigPickers = _rigPickers();
    final rigs = ref.watch(rigProfilesProvider).valueOrNull ?? const [];
    String rigName(int? id) =>
        rigs.where((r) => r.id == id).map((r) => r.name).firstOrNull ?? 'None';
    final rigSummary = _mobileRigId == null && _baseRigId == null
        ? 'Antennas and cables, for comparing setups'
        : 'Mobile: ${rigName(_mobileRigId)} · Base: ${rigName(_baseRigId)}';

    final endedId = _endedSessionId;
    // First run, last step of the Get started card: say so here, where the
    // card's "Go to Live" lands (first run 2026-11-07: "leaves you hanging").
    final lastStep = onLastGetStartedStep(ref);
    return [
      if (lastStep)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.flag_outlined, size: 18, color: status.ok),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Last step: pick the map, leave the base behind, then tap '
                  'Start session.',
                  key: const ValueKey('start-last-step'),
                  style: TextStyle(color: status.ok),
                ),
              ),
            ],
          ),
        ),
      if (endedId != null) ...[
        Card(
          key: const ValueKey('ended-session-report'),
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.summarize_outlined),
            // The verdict in the Compare screen's voice: "Base heard 41 %
            // · farthest 2.2 mi · median +7 dB".
            title: SessionVerdictText(sessionId: endedId),
            subtitle: const Text('Session saved. Share a field report: a '
                'picture of how far the base reached, with your home area '
                'hidden.'),
            trailing: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _endedSessionId = null),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('share-field-report'),
            onPressed: () => showSessionFieldReport(context, endedId),
            icon: const Icon(Icons.ios_share),
            label: const Text('Share field report'),
          ),
        ),
        const SizedBox(height: 8),
      ],
      // Blockers first, then the form (new-user walkthrough 2026-11-08).
      if (!connected)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Connect to your node first (tap Connect a node at the top of the map).',
            style: TextStyle(color: status.warning),
          ),
        )
      else if (public)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                meshCore
                    ? 'Your node is on the public mesh settings. Run Node '
                        'Setup to put both nodes on a private test '
                        'frequency first.'
                    : 'Your node is on the public channel. Run Node Setup '
                        'to put both nodes on the private test channel '
                        'first.',
                style: TextStyle(color: status.warning),
              ),
              TextButton(
                onPressed: _openRadioSetup,
                child: const Text('Open Node Setup'),
              ),
            ],
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _baseRadioSection(radio),
              if (_baseMismatchNote(_mapId, _chosenBaseNum) case final note?)
                note,
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text('Range setting: '
                        '${radio.currentPreset?.displayName ?? 'not known yet'}'),
                  ),
                  TextButton(
                    onPressed: _openRadioSetup,
                    child: const Text('Change'),
                  ),
                ],
              ),
            ],
          ),
        ),
      Row(
        children: [
          Expanded(
            child: maps.isEmpty
                ? const Text('No coverage maps yet. Make one to start.')
                : DropdownButtonFormField<int>(
                    initialValue: _mapId,
                    isExpanded: true,
                    itemHeight: null,
                    decoration:
                        const InputDecoration(labelText: 'Coverage map'),
                    items: [
                      for (final m in maps)
                        DropdownMenuItem(
                            value: m.id, child: Text(m.name, softWrap: true)),
                    ],
                    onChanged: (v) => setState(() => _mapId = v),
                  ),
          ),
          TextButton.icon(
            onPressed: !ready
                ? null
                : () async {
                    final id = await showCreateMapDialog(context, ref);
                    if (id != null && mounted) setState(() => _mapId = id);
                  },
            icon: const Icon(Icons.add),
            label: const Text('New map'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _nameController,
        decoration: const InputDecoration(
          labelText: 'Session name (optional)',
          hintText: 'e.g., Walk to the park',
        ),
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(meshCore ? 'Check the link to the base' : 'Ping the base'),
        subtitle: Text(
          '${meshCore ? 'Sends the base a link check every ${AppConstants.formatSeconds(effectiveSec)} and records '
              'whether it came back and how well each node heard the other; '
              'on MeshCore this is also the base beacon (interval is in '
              'Settings).' : 'Sends a small test message to the base every ${AppConstants.formatSeconds(effectiveSec)} and '
              'records whether its reply came back, which needs the link to '
              'work both ways (interval is in Settings).'}'
          '${meshCore && !_ping ? ' Off: nothing from the base is recorded.' : ''}'
          '${effectiveSec > _pingIntervalSec ? ' Raised from '
              '${AppConstants.formatSeconds(_pingIntervalSec)}, the minimum '
              'for your radio\'s range setting.' : ''}'
          '${_ping && effectiveSec < recommendedSec ? ' Faster than '
              'recommended (≈${(AirtimeModel.dutyFor(radio.currentPreset, effectiveSec, protocol: radio.protocol) * 100).toStringAsFixed(0)}% '
              'airtime; Settings → Active probing).' : ''}',
          style:
              (_ping && effectiveSec < recommendedSec) || (meshCore && !_ping)
                  ? TextStyle(color: status.warning)
                  : null,
        ),
        value: _ping,
        onChanged: (v) => setState(() => _ping = v),
      ),
      if (_ping && connected) AirtimeExplainer.forRadio(radio.currentPreset),
      _disclosure(
        key: const ValueKey('hardware-profiles'),
        title: 'Hardware profiles (optional)',
        subtitle: rigSummary,
        // Open when one is picked, so the choice isn't hidden.
        initiallyExpanded: _mobileRigId != null || _baseRigId != null,
        children: rigPickers,
      ),
      _gpsLine(),
      const BaseBeaconAgeNotice(),
      if (ref.watch(notificationsAllowedProvider).valueOrNull != true)
        _statusLine('Out-of-range alerts need notifications.'),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: (!ready || _mapId == null || _busy) ? null : _startSession,
        icon: const Icon(Icons.fiber_manual_record),
        label: const Text('Start session'),
      ),
      if (_startError case final error?)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            error,
            key: const ValueKey('start-error'),
            style: TextStyle(color: status.warning),
          ),
        ),
      Divider(height: 24, color: Theme.of(context).colorScheme.outlineVariant),
      guidedRow,
    ];
  }

  Future<void> _saveRigChoice(SharedPreferences prefs, String key, int? id) =>
      id == null ? prefs.remove(key) : prefs.setInt(key, id);

  List<Widget> _rigPickers() {
    final rigs = ref.watch(rigProfilesProvider).valueOrNull ?? const [];
    final prefs = ref.read(sharedPreferencesProvider);
    if (!_rigsLoaded) {
      _rigsLoaded = true;
      _mobileRigId = prefs.getInt(AppConstants.prefLastMobileRig);
      _baseRigId = prefs.getInt(AppConstants.prefLastBaseRig);
    }
    // Forget choices whose rig was archived.
    if (rigs.isNotEmpty || ref.read(rigProfilesProvider).hasValue) {
      if (!rigs.any((r) => r.id == _mobileRigId)) _mobileRigId = null;
      if (!rigs.any((r) => r.id == _baseRigId)) _baseRigId = null;
    }

    Widget picker(
        String label, String role, int? value, ValueChanged<int?> onChanged) {
      return Expanded(
        child: DropdownButtonFormField<int?>(
          key: ValueKey('$role-$value-${rigs.length}'),
          initialValue: value,
          isExpanded: true,
          itemHeight: null,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
          ),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('None')),
            for (final r in rigs)
              if (r.role == role || r.role == rigRoleEither || r.id == value)
                DropdownMenuItem<int?>(
                  value: r.id,
                  child: Text(
                    '${r.name} (${formatGainDb(netGainDb(r))})',
                    softWrap: true,
                  ),
                ),
          ],
          onChanged: onChanged,
        ),
      );
    }

    return [
      Row(
        children: [
          picker('Mobile hardware profile', rigRoleMobile, _mobileRigId,
              (v) => setState(() => _mobileRigId = v)),
          const SizedBox(width: 8),
          picker('Base hardware profile', rigRoleBase, _baseRigId,
              (v) => setState(() => _baseRigId = v)),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        // Pro gate: creating a rig is Pro; picking existing rigs stays free.
        child: ProGate(
          feature: ProFeature.rigProfiles,
          onUnlocked: _newRig,
          builder: (context, unlocked, activate) => TextButton.icon(
            onPressed: activate,
            icon: Icon(unlocked ? Icons.add : Icons.lock_outline),
            label: Text(unlocked
                ? 'New hardware profile'
                : 'New hardware profile (Pro)'),
          ),
        ),
      ),
    ];
  }

  Future<void> _newRig() async {
    final id = await showRigEditor(context, ref);
    if (id == null || !mounted) return;
    // Assign to the role it fits; mobile first if both are empty.
    final rig = await ref.read(databaseProvider).getRigProfile(id);
    setState(() {
      if (rig?.role == rigRoleBase ||
          (rig?.role == rigRoleEither && _mobileRigId != null)) {
        _baseRigId = id;
      } else {
        _mobileRigId = id;
      }
    });
  }

  /// The base's beacon is recorded as switched off (Stop after a session,
  /// or set up without one). A session would still run on pings alone, so
  /// ask rather than refuse. True = go ahead.
  Future<bool> _confirmBeaconOff() async {
    // MeshCore: the beacon is the link check itself (the switch above).
    if (ref.read(meshRadioProvider).protocol == RadioProtocol.meshcore) {
      return true;
    }
    final roles = ref.read(radioRolesProvider);
    final beacon = roles.baseBeacon;
    final off = roles.nodeOf(RadioRole.base) != null &&
        beacon != null &&
        (beacon.kind == BeaconKind.none || beacon.intervalSec <= 0);
    if (!off) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Base beacon is off'),
        content: const Text(
            'Your base is not sending its beacon (it was stopped after a '
            'session, or set up without one). Pings still measure the link, '
            'but nothing from the base itself will be recorded and gaps '
            'will not count as dead zones. Start it with Node Setup, or '
            'from the beacon card while connected to the base.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Start anyway')),
        ],
      ),
    );
    return go == true && mounted;
  }

  Future<void> _startSession() async {
    if (!await _confirmBeaconOff()) return;
    setState(() {
      _busy = true;
      _startError = null;
    });
    try {
      await ref.read(sessionManagerProvider).startSession(
            coverageMapId: _mapId!,
            baseMeshNodeId: _chosenBaseNum,
            name: _nameController.text.trim(),
            pingIntervalSec: _ping ? _pingIntervalSec : 0,
            mobileRigId: _mobileRigId,
            baseRigId: _baseRigId,
          );
      _endedSessionId = null;
      final prefs = ref.read(sharedPreferencesProvider);
      await _saveRigChoice(prefs, AppConstants.prefLastMobileRig, _mobileRigId);
      await _saveRigChoice(prefs, AppConstants.prefLastBaseRig, _baseRigId);
      // Started, but positions only come once GPS has a fix: say so.
      final gps = ref.read(gpsServiceProvider).state;
      if (gps.status != GpsStatus.fix && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Recording, but GPS has no fix yet. Packets get a '
              'position once it does; move to open sky if it takes long.'),
        ));
      }
      // A one-off platform note (Android: battery settings), queued
      // after the GPS one so neither hides the other.
      final notice = ref.read(sessionManagerProvider).startNotice;
      if (notice != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(notice),
          duration: const Duration(seconds: 12),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _startError = switch (e) {
              SessionStartError() => e.message,
              // Refusals worded for the user (e.g. a MeshCore session with
              // neither beacon nor link checks) pass through userMessage.
              _ => userMessage(e, doing: 'starting the session'),
            });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
