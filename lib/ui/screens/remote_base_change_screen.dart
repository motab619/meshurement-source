// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/database/app_database.dart' show Session;
import '../../data/radio/mesh_radio.dart';
import '../../data/radio/meshtastic/meshtastic_presets.dart';
import '../../providers.dart';
import '../../services/guided/plan_models.dart';
import '../../services/guided/route_match.dart' show flatDistanceM;
import '../../services/pro_entitlement.dart';
import '../../services/remote_base_change.dart';
import '../../utils/user_errors.dart';
import '../widgets/guided/check_list.dart';
import '../widgets/guided/risk_sheet.dart';
import 'pro_paywall_screen.dart';
import '../layout/window_class.dart';

/// TX powers offered (dBm). The firmware caps a value above the
/// hardware's maximum.
const remoteTxPowerChoices = [5, 10, 14, 17, 20, 22, 27, 30];

/// Change the Radio Setup base's range setting and/or TX power from where
/// you stand, over the mesh (Pro, Meshtastic). The sequence lives in
/// [RemoteBaseChange] and keeps going if this screen is closed.
class RemoteBaseChangeScreen extends ConsumerStatefulWidget {
  const RemoteBaseChangeScreen({super.key});

  @override
  ConsumerState<RemoteBaseChangeScreen> createState() =>
      _RemoteBaseChangeScreenState();
}

class _RemoteBaseChangeScreenState
    extends ConsumerState<RemoteBaseChangeScreen> {
  RadioPreset? _preset;
  int? _txPower;

  /// The session this screen ended to make the change (offered again
  /// afterwards).
  Session? _endedSession;
  bool _starting = false;

  RemoteBaseChange get _change => ref.read(remoteBaseChangeProvider);

  @override
  Widget build(BuildContext context) {
    final change = ref.watch(remoteBaseChangeProvider);
    // Rebuild on link changes so the blocker line stays current.
    ref.watch(meshLinkStateProvider);
    final radio = ref.watch(meshRadioProvider);
    final plan = ref.watch(activePlanProvider).valueOrNull;
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final state = change.state;
    final running = change.running;
    final finished = state != null &&
        (state.phase == ChangePhase.done || state.phase == ChangePhase.failed);

    final blocker = plan?.status == PlanStatus.running
        ? 'A guided test is running. Pause or finish it first.'
        : change.blocker;

    final basePreset = change.basePreset;
    final baseTx = change.baseTxPowerDbm;
    final offered = MeshtasticPresets.presetsForRegion(radio.regionName,
        firmwareVersion: radio.capabilities.firmwareVersion);

    return Scaffold(
      appBar: AppBar(title: const Text('Change the base')),
      body: WideColumn(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(change.baseLabel.isEmpty ? 'Base node' : change.baseLabel,
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Set up as ${basePreset?.displayName ?? 'an unknown range setting'}'
                '${baseTx == null ? '' : ' · $baseTx dBm'}',
                key: const ValueKey('rbc-base-now'),
                style: hint,
              ),
              const SizedBox(height: 16),
              if (state == null || finished && !running) ...[
                if (blocker != null)
                  _Notice(key: const ValueKey('rbc-blocker'), text: blocker)
                else ...[
                  Text(
                    'The base changes first, over the mesh, then your node '
                    'matches it. If the base goes quiet, your node goes back '
                    'to its old setting.',
                    style: hint,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<RadioPreset?>(
                    key: const ValueKey('rbc-preset'),
                    initialValue: _preset,
                    decoration: const InputDecoration(
                        labelText: 'Range setting (both nodes)'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Keep as it is')),
                      for (final p in offered)
                        DropdownMenuItem(value: p, child: Text(p.displayName)),
                    ],
                    onChanged: (p) => setState(() => _preset = p),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    key: const ValueKey('rbc-power'),
                    initialValue: _txPower,
                    decoration:
                        const InputDecoration(labelText: 'Base TX power'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Keep as it is')),
                      for (final d in remoteTxPowerChoices)
                        DropdownMenuItem(value: d, child: Text('$d dBm')),
                    ],
                    onChanged: (d) => setState(() => _txPower = d),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'TX power changes the base only; your node keeps its own.',
                    style: hint,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const ValueKey('rbc-apply'),
                    onPressed:
                        _preset == null && _txPower == null ? null : _onApply,
                    icon: const Icon(Icons.cell_tower),
                    label: const Text('Change the base'),
                  ),
                ],
              ],
              if (state != null) ...[
                if (finished) const SizedBox(height: 24),
                Text(
                  _sentence(state),
                  key: const ValueKey('rbc-sentence'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (state.rows.isNotEmpty) CheckList(rows: state.rows),
                const SizedBox(height: 12),
                if (running)
                  Text(
                    'Stay where you are until the base is heard again. You can '
                    'leave this screen; the change keeps going.',
                    style: hint,
                  ),
                if (finished && _endedSession != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('rbc-new-session'),
                    onPressed: _starting ? null : _startNewSession,
                    icon: const Icon(Icons.fiber_manual_record),
                    label: const Text('Start a new session'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _sentence(ChangeState s) {
    final both = s.rows.any((r) => r.label.startsWith('Your node'));
    return switch (s.phase) {
      ChangePhase.done => both
          ? 'Both nodes are on ${s.targetName} and the base answered.'
          : 'The base is on ${s.targetName} and answered.',
      ChangePhase.failed => s.failure ?? 'The change did not take.',
      _ => 'Switching to ${s.targetName}…',
    };
  }

  Future<void> _onApply() async {
    final pro = ref.read(proEntitlementProvider);
    if (!pro.canCreate(ProFeature.remoteBaseChange)) {
      final ok =
          await showProPaywall(context, feature: ProFeature.remoteBaseChange);
      if (!ok || !mounted) return;
    }
    final name =
        RemoteBaseChange.targetName(preset: _preset, txPowerDbm: _txPower);

    // Mid-session: readings from two settings would mix in one session.
    final env = ref.read(planEnvironmentProvider);
    final session = env.activeSession;
    if (session != null) {
      final end = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('A session is recording'),
          content: const Text(
              'Changing the radios now would mix two settings in one '
              'session. End it first; you can start a new one when the '
              'change is done.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('rbc-end-and-change'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('End session and change'),
            ),
          ],
        ),
      );
      if (end != true || !mounted) return;
    }

    // The risk, once ever (shared with the guided test).
    if (!riskSheetSeen(ref)) {
      final distance = await _baseDistanceM();
      if (!mounted) return;
      final choice = await showRiskSheet(context,
          targetName: name, baseDistanceM: distance);
      if (choice != RiskChoice.changeHere || !mounted) return;
    }

    if (session != null) {
      try {
        await env.endSession();
      } catch (e) {
        _say(userMessage(e, doing: 'ending the session'));
        return;
      }
      _endedSession = session;
    }
    try {
      await _change.apply(preset: _preset, txPowerDbm: _txPower);
    } catch (e) {
      _say(userMessage(e));
    }
    if (mounted) setState(() {});
  }

  /// How far the base is, for the risk sheet: the nearest map's base
  /// location within 20 km (a map is a place; the base sits at one).
  Future<double?> _baseDistanceM() async {
    final here = ref.read(planEnvironmentProvider).lastPosition;
    if (here == null) return null;
    double? best;
    for (final m in await ref.read(databaseProvider).getAllCoverageMaps()) {
      final lat = m.baseLat, lon = m.baseLon;
      if (lat == null || lon == null) continue;
      final d = flatDistanceM(here, LatLng(lat, lon));
      if (d <= 20000 && (best == null || d < best)) best = d;
    }
    return best;
  }

  Future<void> _startNewSession() async {
    final old = _endedSession;
    if (old == null) return;
    setState(() => _starting = true);
    try {
      final name = _change.state?.targetName ?? '';
      await ref.read(planEnvironmentProvider).startSession(
            coverageMapId: old.coverageMapId,
            name: [if (old.name.isNotEmpty) old.name, name].join(' · '),
          );
      _endedSession = null;
      _say('Recording on the new setting.');
    } catch (e) {
      _say(userMessage(e, doing: 'starting a session'));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.secondary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
