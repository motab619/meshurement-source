// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/radio/mesh_radio.dart' show RadioConnectionState;
import '../../providers.dart';
import '../../services/units.dart';
import '../../services/appearance.dart';
import '../../services/active_probe_service.dart';
import '../../services/airtime_model.dart';
import '../../services/data_erase_service.dart';
import '../../services/privacy_settings.dart';
import '../../services/pro_entitlement.dart';
import '../../services/screen_wake.dart';
import '../../services/session_manager.dart';
import '../../services/terrain/terrain_settings.dart';
import '../../utils/constants.dart';
import '../protocol_text.dart';
import '../theme/app_theme.dart';
import '../widgets/export_dialog.dart';
import '../widgets/airtime_explainer.dart';
import '../widgets/connection_banner.dart' show showConnectDialog;
import '../widgets/info_button.dart';
import 'about_screen.dart';
import 'node_list_screen.dart';
import 'privacy_screen.dart';
import 'pro_paywall_screen.dart';
import 'radio_backups_screen.dart';
import 'radio_setup_screen.dart';
import 'rig_profiles_screen.dart';
import '../../utils/user_errors.dart';
import '../../utils/app_info.dart';
import '../widgets/pro_tag.dart';
import '../layout/window_class.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late SharedPreferences _prefs;
  bool _keepScreenOn = false;
  bool _countRelayed = false;
  bool _showLegend = false;
  String _signalDirection = 'rx';
  String _colorMetric = 'snr';
  int _pingIntervalSec = AppConstants.defaultPingIntervalSec;

  /// The stored "Faster than recommended" choice; it only applies with Pro
  /// ([_faster]), and is kept for when Pro comes back.
  bool _fasterPref = false;
  bool get _faster =>
      _fasterPref &&
      ref.read(proEntitlementProvider).canCreate(ProFeature.fasterIntervals);
  int _outOfRangeTimeoutSec = AppConstants.defaultOutOfRangeTimeoutSec;
  late TerrainSettings _terrain;

  @override
  void initState() {
    super.initState();
    _prefs = ref.read(sharedPreferencesProvider);
    _loadPrefs();
  }

  String _unitsSubtitle() {
    final units = ref.watch(distanceUnitsProvider);
    final miles = ref.watch(useMilesProvider);
    final which = miles ? 'miles and feet' : 'kilometres and metres';
    return units == DistanceUnits.automatic
        ? 'Following the phone\'s region: $which'
        : 'Distances in $which';
  }

  void _loadPrefs() {
    _keepScreenOn = _prefs.getBool(AppConstants.prefKeepScreenOn) ?? false;
    _countRelayed = AppConstants.countRelayedPackets(_prefs);
    // On by default: the dot colours alone don't work for everyone.
    _showLegend = _prefs.getBool(AppConstants.prefShowSignalLegend) ?? true;
    _signalDirection =
        _prefs.getString(AppConstants.prefSignalDirection) ?? 'rx';
    _colorMetric = _prefs.getString(AppConstants.prefColorMetric) ?? 'snr';
    _pingIntervalSec = AppConstants.pingIntervalSec(_prefs);
    _fasterPref = AppConstants.fasterThanRecommended(_prefs);
    _outOfRangeTimeoutSec = AppConstants.outOfRangeTimeoutSec(_prefs);
    _terrain = TerrainSettings.load(_prefs);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when Pro changes ("Faster than recommended" needs it).
    ref.watch(isProProvider);
    // Rebuild when the radio (and so its preset) changes.
    final linkState = ref.watch(meshLinkStateProvider).valueOrNull;
    final radio = ref.read(meshRadioProvider);
    final connected =
        linkState != null && linkState != RadioConnectionState.disconnected;
    final privacy = ref.watch(privacyProvider);
    final preset = radio.currentPreset;
    final presetName = (preset ?? AirtimeModel.defaultPreset).displayName;
    final protocol = radio.protocol;
    final recommendedPing =
        AirtimeModel.minIntervalSecFor(preset, protocol: protocol);
    final minPing = AirtimeModel.minIntervalSecFor(preset,
        override: _faster, protocol: protocol);
    // Steps from the minimum (1 s when overriding, for fine control; else
    // 5 s); max lands on a step (<= 300).
    final step = _faster ? 1 : 5;
    final pingSteps = (300 - minPing) ~/ step;
    final maxPing = minPing + pingSteps * step;
    final belowMin = _pingIntervalSec < minPing;
    final shownPingSec = _pingIntervalSec.clamp(minPing, maxPing);

    final terrainFrequency = radio.regionFrequencyMHz;
    final probes = probeNoun(protocol, plural: true);
    // The out-of-range window the app actually uses: the setting, but at
    // least three missed probes plus the reply wait.
    final minWindowSec = SessionManager.outOfRangeTimeoutSecFor(
      prefSec: 0,
      intervalSec: shownPingSec,
      replySec: ActiveProbeService.pingTimeoutSecFor(protocol, shownPingSec),
      beaconSec: 0,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: WideColumn(
        child: ListView(
          children: [
            // ─── My nodes ───
            const _SectionHeader(title: 'My nodes'),
            // Connecting and switching live here as well as on the map pill:
            // testers looked for the switch in Settings (2026-11-01).
            ListTile(
              key: const ValueKey('settings-connect-radio'),
              leading:
                  Icon(connected ? Icons.bluetooth_connected : Icons.bluetooth),
              title: Text(connected
                  ? 'Connected: ${radio.displayName}'
                  : 'Connect a node'),
              subtitle: Text(connected
                  ? 'Tap to switch to your other node'
                  : 'Pick the mobile or the base over Bluetooth'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showConnectDialog(context),
            ),
            ListTile(
              leading: const Icon(Icons.router),
              title: const Text('Node Setup'),
              subtitle: const Text(
                'Private test channel and range setting for the mobile and '
                'base nodes',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RadioSetupScreen()),
              ),
            ),
            ListTile(
              key: const ValueKey('settings-radio-backups'),
              leading: const Icon(Icons.history),
              title: const Text('Node backups'),
              subtitle: const Text(
                  'Settings saved before Node Setup changed a node; restore '
                  'or put a node back the way it was'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RadioBackupsScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.device_hub_outlined),
              title: const Text('Heard nodes'),
              subtitle:
                  const Text('Nodes the app has heard; give one a nickname'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NodeListScreen()),
              ),
            ),

            // ─── Hardware ───
            const _SectionHeader(title: 'Hardware'),
            ListTile(
              leading: const Icon(Icons.cell_tower),
              title: const Text('Hardware profiles'),
              subtitle: const Text(
                'Hardware, antenna and cable per setup, with net gain',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RigProfilesScreen()),
              ),
            ),

            // ─── Display ───
            const _SectionHeader(title: 'Display'),

            SwitchListTile(
              title: const Text('Keep screen on'),
              subtitle: const Text(
                'On while a session records; this keeps it on all the time.',
              ),
              value: _keepScreenOn,
              onChanged: (value) async {
                setState(() => _keepScreenOn = value);
                await ref.read(screenWakeProvider).setAlwaysOn(value);
              },
            ),

            SwitchListTile(
              key: const ValueKey('settings-count-relayed'),
              title: const Row(
                children: [
                  Flexible(child: Text('Count relayed packets')),
                  InfoButton(
                    title: 'Count relayed packets',
                    body: 'Off: only packets heard straight from the base node '
                        'count, which is what you want to measure the base ↔ '
                        'mobile link.\n\n'
                        'On: copies relayed by other nodes are recorded too '
                        '(small dots on the map) and keep "hearing the base" '
                        'alive.',
                  ),
                ],
              ),
              subtitle: const Text(
                'Off: only packets straight from the base node count.',
              ),
              value: _countRelayed,
              onChanged: (value) async {
                setState(() => _countRelayed = value);
                await _prefs.setBool(
                    AppConstants.prefCountRelayedPackets, value);
              },
            ),

            _ControlTile(
              title: 'Signal direction',
              subtitle: Text(_directionLabel(_signalDirection)),
              control: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'rx', label: Text('Rx')),
                  ButtonSegment(value: 'tx', label: Text('Tx')),
                  ButtonSegment(value: 'both', label: Text('Both')),
                ],
                selected: {_signalDirection},
                onSelectionChanged: (selected) async {
                  setState(() => _signalDirection = selected.first);
                  await _prefs.setString(
                      AppConstants.prefSignalDirection, selected.first);
                },
              ),
            ),

            _ControlTile(
              title: 'Color metric',
              subtitle: Text(_colorMetric == 'snr'
                  ? "Margin: dB above the range setting's decode limit. "
                      "Strong readings use RSSI above the radio's "
                      'sensitivity, because SNR stops rising close to the base '
                      'node. Strong 20+, Good 10 to 20, Weak 0 to 10, Below limit '
                      'under 0.'
                  : 'RSSI (dBm). Flattens at the noise floor (about -105 dBm) '
                      'near the edge of range, where SNR still shows a '
                      'difference.'),
              control: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'snr', label: Text('SNR')),
                  ButtonSegment(value: 'rssi', label: Text('RSSI')),
                ],
                selected: {_colorMetric},
                onSelectionChanged: (selected) async {
                  setState(() => _colorMetric = selected.first);
                  await _prefs.setString(
                      AppConstants.prefColorMetric, selected.first);
                },
              ),
            ),

            SwitchListTile(
              title: const Text('Show color key on the Live map'),
              subtitle: const Text(
                  'Strong, Good, Weak and Below limit swatches in the corner, '
                  'so the dots read without telling colors apart. On by default.'),
              value: _showLegend,
              onChanged: (value) async {
                setState(() => _showLegend = value);
                await _prefs.setBool(AppConstants.prefShowSignalLegend, value);
                ref.read(showSignalLegendProvider.notifier).state = value;
              },
            ),

            _ControlTile(
              title: 'Units',
              subtitle: Text(_unitsSubtitle()),
              control: SegmentedButton<DistanceUnits>(
                key: const ValueKey('settings-units'),
                showSelectedIcon: false,
                segments: [
                  for (final u in DistanceUnits.values)
                    ButtonSegment(value: u, label: Text(u.label)),
                ],
                selected: {ref.watch(distanceUnitsProvider)},
                onSelectionChanged: (selected) => ref
                    .read(distanceUnitsProvider.notifier)
                    .set(selected.first),
              ),
            ),

            _ControlTile(
              title: 'Appearance',
              subtitle: const Text(
                'Bright for sunlight (lighter terrain shading), Night dims the '
                'map. Automatic follows the phone. Also in the map\'s layers '
                'button.',
              ),
              control: SegmentedButton<Appearance>(
                key: const ValueKey('settings-appearance'),
                showSelectedIcon: false,
                segments: [
                  for (final a in Appearance.values)
                    ButtonSegment(value: a, label: Text(a.label)),
                ],
                selected: {ref.watch(appearanceProvider)},
                onSelectionChanged: (selected) =>
                    ref.read(appearanceProvider.notifier).set(selected.first),
              ),
            ),

            // ─── Terrain ───
            const _SectionHeader(title: 'Terrain'),
            _heightTile(
              title: 'Base antenna height',
              value: _terrain.baseHeightM,
              onChanged: (v) {
                setState(() => _terrain = TerrainSettings(
                    baseHeightM: v, mobileHeightM: _terrain.mobileHeightM));
                TerrainSettings.saveBaseHeight(_prefs, v);
              },
            ),
            _heightTile(
              title: 'Mobile antenna height',
              value: _terrain.mobileHeightM,
              onChanged: (v) {
                setState(() => _terrain = TerrainSettings(
                    baseHeightM: _terrain.baseHeightM, mobileHeightM: v));
                TerrainSettings.saveMobileHeight(_prefs, v);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Elevation lookups are switched in Privacy. Meters above ground. Used by the line-of-sight profile (long-'
                'press a coverage map) and the terrain-aware estimate. '
                'Frequency: ${terrainFrequency.round()} MHz '
                '(from the radio\'s region).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

            // ─── Active Probing ───
            const _SectionHeader(title: 'Active probing'),

            _ControlTile(
              title: '${probeNoun(protocol, capital: true)} interval',
              subtitle: Text(
                '${AppConstants.formatSeconds(shownPingSec)}'
                '${belowMin ? ' (the least for $presetName)' : ''}'
                '${shownPingSec < recommendedPing ? ' · ≈${(AirtimeModel.dutyFor(preset, shownPingSec, protocol: protocol) * 100).toStringAsFixed(0)}% airtime' : ''}',
                style: shownPingSec < recommendedPing
                    ? TextStyle(color: context.status.warning)
                    : null,
              ),
              control: SizedBox(
                width: double.infinity,
                child: Slider(
                  value: shownPingSec.toDouble(),
                  min: minPing.toDouble(),
                  max: maxPing.toDouble(),
                  divisions: pingSteps,
                  label: '${shownPingSec}s',
                  onChanged: (value) async {
                    setState(() => _pingIntervalSec = value.round());
                    await _prefs.setInt(
                        AppConstants.prefPingIntervalSec, value.round());
                  },
                ),
              ),
            ),
            SwitchListTile(
              title: Row(children: [
                const Flexible(child: Text('Faster than recommended')),
                if (!ref
                    .read(proEntitlementProvider)
                    .canCreate(ProFeature.fasterIntervals)) ...[
                  const SizedBox(width: 8),
                  const ProTag(),
                ],
              ]),
              subtitle: Text(
                _faster
                    ? '${probeNoun(protocol, plural: true, capital: true)} (and the base beacon in Node Setup) can go as '
                        'often as every ${AppConstants.formatSeconds(minPing)} '
                        'on $presetName, instead of '
                        '${AppConstants.formatSeconds(recommendedPing)}. This '
                        'uses more of the shared channel than the firmware '
                        'recommends, and the radio may hold some $probes back '
                        '(shown as held back). Best for short tests on your '
                        'private channel.'
                    : 'Allow $probes below the '
                        '${AppConstants.formatSeconds(recommendedPing)} '
                        'airtime limit for $presetName.',
                style:
                    _faster ? TextStyle(color: context.status.warning) : null,
              ),
              value: _faster,
              onChanged: (v) async {
                final entitlement = ref.read(proEntitlementProvider);
                if (v && !entitlement.canCreate(ProFeature.fasterIntervals)) {
                  // Pro feature: the paywall only when the switch is tapped.
                  if (!await showProPaywall(context,
                      feature: ProFeature.fasterIntervals)) {
                    return;
                  }
                  if (!mounted) return;
                }
                setState(() => _fasterPref = v);
                await _prefs.setBool(AppConstants.prefFasterThanRecommended, v);
              },
            ),
            if (!_faster)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AirtimeExplainer.forRadio(preset, protocol: protocol),
              ),

            // ─── Notifications ───
            const _SectionHeader(title: 'Notifications'),

            _ControlTile(
              title: 'Out-of-range alert',
              subtitle: Text(
                'Alert after ${AppConstants.formatSeconds(_outOfRangeTimeoutSec)} '
                'without hearing the base'
                '${minWindowSec > _outOfRangeTimeoutSec ? '. At your ${probeNoun(protocol)} interval the app waits at least ${AppConstants.formatSeconds(minWindowSec)}, so three ${probeNoun(protocol, plural: true)} in a row go unanswered first.' : '.'}',
              ),
              control: SizedBox(
                width: double.infinity,
                child: Slider(
                  value: _outOfRangeTimeoutSec.toDouble(),
                  min: 30,
                  max: 900,
                  divisions: 29, // 30 s steps
                  label: AppConstants.formatSeconds(_outOfRangeTimeoutSec),
                  onChanged: (value) async {
                    setState(() => _outOfRangeTimeoutSec = value.round());
                    await _prefs.setInt(
                        AppConstants.prefOutOfRangeTimeoutSec, value.round());
                  },
                ),
              ),
            ),

            // ─── Data ───
            const _SectionHeader(title: 'Data'),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Export all data'),
              subtitle: const Text(
                  'Every map and session as CSV and GeoJSON in one zip.'),
              onTap: () => showExportAllDialog(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.device_hub_outlined),
              title: const Text('Clear nodes list'),
              subtitle: const Text(
                  'Make your node forget the other nodes it has heard. Your '
                  'base is kept.'),
              onTap: () => _erase(
                title: 'Clear nodes list?',
                body:
                    'Your connected node forgets every other node it has heard '
                    'except your base, then restarts (about 10 seconds; the '
                    'app reconnects by itself). The app also removes nodes no '
                    'saved map uses. Nodes you hear again will reappear.',
                action: 'Clear',
                run: (s) async {
                  final (:radioForgot, :baseKept, :removed, :kept) =
                      await s.clearNodes();
                  String nodes(int n) => '$n node${n == 1 ? '' : 's'}';
                  return [
                    if (radioForgot == null)
                      'No node connected over Bluetooth, so its list wasn\'t '
                          'cleared.'
                    else
                      'Your node forgot ${nodes(radioForgot)} and is '
                          'restarting${baseKept ? '; your base was kept' : ''}.',
                    if (removed > 0) 'Removed ${nodes(removed)} from the app.',
                    if (kept > 0)
                      '${nodes(kept)} kept in the app for your saved maps.',
                  ].join(' ');
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.layers_clear_outlined),
              title: const Text('Delete all sessions and maps'),
              subtitle: const Text(
                  'Every coverage map, session, packet and ping result.'),
              onTap: () => _erase(
                title: 'Delete all sessions and maps?',
                body: 'Permanently deletes every coverage map and session with '
                    'all their packets, pings and saved comparisons. Export '
                    'anything you want to keep as CSV first. This can\'t be '
                    'undone.',
                action: 'Delete',
                run: (s) async {
                  await s.deleteSessionsAndMaps();
                  return 'All sessions and maps deleted';
                },
              ),
            ),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Erase all app data',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: const Text(
                  'Maps, sessions, nodes, hardware profiles, node backups, exports, '
                  'the diagnostics log, saved base locations, cached terrain '
                  'and settings.'),
              onTap: () => _erase(
                title: 'Erase all app data?',
                body: 'Permanently deletes everything this app has stored on '
                    'this phone: maps, sessions, nodes, hardware profiles, exported '
                    'files, the diagnostics log, the base locations saved in '
                    'Node Setup, cached terrain and settings. That includes '
                    'the node backups, so you won\'t be able to restore your '
                    'nodes\' original settings from this app afterwards.\n\n'
                    'Kept: the MeshTest channel key and which node is the base '
                    'and which the mobile (your nodes stay paired with the '
                    'app), and your Pro purchase. Nothing on the nodes is '
                    'changed. This can\'t be undone.',
                action: 'Erase',
                run: (s) async {
                  await s.eraseEverything();
                  // "Keep screen on" is reset (a recording session still
                  // keeps the screen on).
                  await ref.read(screenWakeProvider).refresh();
                  ref.invalidate(privacyProvider);
                  if (mounted) setState(_loadPrefs);
                  return 'All app data erased';
                },
              ),
            ),

            // ─── Privacy ───
            const _SectionHeader(title: 'Privacy'),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy'),
              subtitle: Text(
                'Map tiles ${privacy.mapTiles ? 'on' : 'off'} · '
                'Ground height ${privacy.terrain ? 'on' : 'off'} · '
                'AI analysis ${privacy.aiConsent ? 'on' : 'off'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrivacyScreen()),
              ),
            ),

            // ─── About ───
            const _SectionHeader(title: 'About'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About ${AppInfo.displayName}'),
              subtitle: const Text('Version, source code, licenses'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Confirm, then run an erase job and report how it went.
  Future<void> _erase({
    required String title,
    required String body,
    required String action,
    required Future<String> Function(DataEraseService service) run,
  }) async {
    final service = ref.read(dataEraseServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (!service.canErase) {
      messenger.showSnackBar(
          const SnackBar(content: Text('End the current session first.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ctx.status.danger,
              foregroundColor: ctx.status.onDanger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final done = await run(service);
      messenger.showSnackBar(
          SnackBar(content: Text(done), duration: const Duration(seconds: 8)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(userMessage(e))));
    }
  }

  Widget _heightTile({
    required String title,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    const steps = 99; // 0.5 m steps over 0.5-50 m
    return _ControlTile(
      title: title,
      subtitle: Text('${value.toStringAsFixed(1)} m above ground'),
      control: SizedBox(
        width: double.infinity,
        child: Slider(
          value: value.clamp(
              TerrainSettings.minHeightM, TerrainSettings.maxHeightM),
          min: TerrainSettings.minHeightM,
          max: TerrainSettings.maxHeightM,
          divisions: steps,
          label: '${value.toStringAsFixed(1)} m',
          onChanged: onChanged,
        ),
      ),
    );
  }

  String _directionLabel(String dir) {
    switch (dir) {
      case 'rx':
        return 'Received: the base\'s signal at the mobile';
      case 'tx':
        return 'Sent: whether the base heard the mobile';
      case 'both':
        return 'Both, overlaid';
      default:
        return dir;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) => SectionLabel(title);
}

/// A setting with its control under the text (not squeezed into a
/// trailing slot), so long titles wrap and large Dynamic Type sizes fit.
class _ControlTile extends StatelessWidget {
  final String title;
  final Widget subtitle;
  final Widget control;

  const _ControlTile({
    required this.title,
    required this.subtitle,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 2),
          DefaultTextStyle.merge(
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            child: subtitle,
          ),
          const SizedBox(height: 4),
          control,
        ],
      ),
    );
  }
}
