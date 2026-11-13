// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../providers.dart';
import '../../services/pro_entitlement.dart';
import '../../services/radio_roles.dart';
import '../../services/rig_math.dart';
import '../theme/app_theme.dart';
import 'pro_paywall_screen.dart';
import '../layout/window_class.dart';

/// Settings → Hardware → Rig profiles.
class RigProfilesScreen extends ConsumerWidget {
  const RigProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rigs = ref.watch(rigProfilesProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Hardware profiles')),
      // Pro gate: only creating a rig is gated (see ProFeature.rigProfiles).
      floatingActionButton: ProGate(
        feature: ProFeature.rigProfiles,
        onUnlocked: () => showRigEditor(context, ref),
        builder: (context, unlocked, activate) => FloatingActionButton.extended(
          onPressed: activate,
          icon: Icon(unlocked ? Icons.add : Icons.lock_outline),
          label: Text(
              unlocked ? 'New hardware profile' : 'New hardware profile (Pro)'),
        ),
      ),
      body: WideColumn(
        child: rigs.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No hardware profiles yet. A hardware profile describes a '
                    'node, antenna and cable so sessions can be compared by '
                    'hardware.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  for (final rig in rigs)
                    Dismissible(
                      key: ValueKey(rig.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: context.status.danger,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child:
                            Icon(Icons.archive, color: context.status.onDanger),
                      ),
                      confirmDismiss: (_) => _confirmArchive(context, rig),
                      onDismissed: (_) =>
                          ref.read(databaseProvider).archiveRigProfile(rig.id),
                      child: ListTile(
                        title: Text(rig.name),
                        subtitle: Text([
                          if (rig.radioModel.isNotEmpty) rig.radioModel,
                          '${rig.antennaGainDbi.toStringAsFixed(1)} dBi antenna',
                        ].join(' · ')),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatGainDb(netGainDb(rig)),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text('net gain',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                        onTap: () => showRigEditor(context, ref, rig: rig),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<bool> _confirmArchive(BuildContext context, RigProfile rig) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Archive "${rig.name}"?'),
        content: const Text(
            'It disappears from pickers. Sessions that used it keep their '
            'recorded hardware details.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Archive')),
        ],
      ),
    );
    return ok ?? false;
  }
}

/// Opens the add/edit form. Returns the saved rig's id, or null if cancelled.
Future<int?> showRigEditor(
  BuildContext context,
  WidgetRef ref, {
  RigProfile? rig,
  String role = rigRoleEither,
}) {
  return Navigator.push<int>(
    context,
    MaterialPageRoute(builder: (_) => RigEditScreen(rig: rig, role: role)),
  );
}

class RigEditScreen extends ConsumerStatefulWidget {
  final RigProfile? rig;
  final String role;

  const RigEditScreen({super.key, this.rig, this.role = rigRoleEither});

  @override
  ConsumerState<RigEditScreen> createState() => _RigEditScreenState();
}

class _RigEditScreenState extends ConsumerState<RigEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _antenna;
  late final TextEditingController _gain;
  late final TextEditingController _length;
  late final TextEditingController _connLoss;
  late final TextEditingController _notes;
  late String _radio;
  late String _role;
  late String _cable;
  late int _connectors;

  @override
  void initState() {
    super.initState();
    final r = widget.rig;
    _name = TextEditingController(text: r?.name ?? '');
    _radio = r?.radioModel ?? '';
    _antenna = TextEditingController(text: r?.antennaName ?? '');
    _gain = TextEditingController(text: _num(r?.antennaGainDbi ?? 0));
    _length = TextEditingController(text: _num(r?.cableLengthM ?? 0));
    _connLoss = TextEditingController(text: _num(r?.connectorLossDb ?? 0.1));
    _notes = TextEditingController(text: r?.notes ?? '');
    _role = r?.role ?? widget.role;
    _cable = r?.cableType ?? 'none';
    _connectors = r?.connectorCount ?? 0;
    // New rig: fill in the model the radio reports.
    if (r == null && _radio.isEmpty) {
      _radio = _detectedModel();
      _autoFilled = _radio.isNotEmpty;
    }
  }

  /// Field controller of the radio model Autocomplete.
  TextEditingController? _radioField;

  /// The model field holds the detected model (so a role change updates it).
  bool _autoFilled = false;

  /// Model reported by the radio this rig is for: the base (when the role
  /// is Base and we know which radio that is), else the connected radio.
  /// Empty if unknown.
  String _detectedModel() {
    final radio = ref.read(meshRadioProvider);
    final num = _role == rigRoleBase
        ? ref.read(radioRolesProvider).nodeOf(RadioRole.base)
        : radio.myNodeId;
    if (num == null) return '';
    return radioModelName(radio.nodes[num]?.hwModel ?? '');
  }

  void _setRadio(String model, {required bool auto}) {
    _radio = model;
    _autoFilled = auto;
    _radioField?.text = model;
  }

  @override
  void dispose() {
    for (final c in [_name, _antenna, _gain, _length, _connLoss, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  static double _parse(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  RigSpec get _spec => RigSpec(
        name: _name.text.trim(),
        antennaGainDbi: _parse(_gain),
        cableType: _cable,
        cableLengthM: _parse(_length),
        connectorCount: _connectors,
        connectorLossDb: _parse(_connLoss),
      );

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Give the profile a name')));
      return;
    }
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    int id;
    if (widget.rig == null) {
      id = await db.insertRigProfile(RigProfilesCompanion.insert(
        name: name,
        role: Value(_role),
        radioModel: Value(_radio.trim()),
        antennaName: Value(_antenna.text.trim()),
        antennaGainDbi: Value(_parse(_gain)),
        cableType: Value(_cable),
        cableLengthM: Value(_parse(_length)),
        connectorCount: Value(_connectors),
        connectorLossDb: Value(_parse(_connLoss)),
        notes: Value(_notes.text.trim()),
        createdAt: now,
        updatedAt: now,
      ));
    } else {
      id = widget.rig!.id;
      await db.updateRigProfile(
        id,
        RigProfilesCompanion(
          name: Value(name),
          role: Value(_role),
          radioModel: Value(_radio.trim()),
          antennaName: Value(_antenna.text.trim()),
          antennaGainDbi: Value(_parse(_gain)),
          cableType: Value(_cable),
          cableLengthM: Value(_parse(_length)),
          connectorCount: Value(_connectors),
          connectorLossDb: Value(_parse(_connLoss)),
          notes: Value(_notes.text.trim()),
        ),
      );
    }
    if (mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    final net = spec.netGainDb;
    const decimal =
        TextInputType.numberWithOptions(decimal: true, signed: true);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rig == null
            ? 'New hardware profile'
            : 'Edit hardware profile'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: WideColumn(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Net gain'),
                    Text(
                      formatGainDb(net),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: rigRoleMobile, label: Text('Mobile')),
                ButtonSegment(value: rigRoleBase, label: Text('Base')),
                ButtonSegment(value: rigRoleEither, label: Text('Either')),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() {
                _role = s.first;
                if (_autoFilled) _setRadio(_detectedModel(), auto: true);
              }),
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _radio),
              optionsBuilder: (v) => supportedRadioModels.where(
                  (m) => m.toLowerCase().contains(v.text.trim().toLowerCase())),
              onSelected: (v) => _radio = v,
              fieldViewBuilder: (context, controller, focus, onSubmit) {
                _radioField = controller;
                final detected = _detectedModel();
                // Free text: any typed value is kept, suggestions are optional.
                return TextField(
                  controller: controller,
                  focusNode: focus,
                  onChanged: (v) {
                    _radio = v;
                    _autoFilled = false;
                  },
                  decoration: InputDecoration(
                    labelText: 'Hardware model',
                    helperText: detected.isEmpty
                        ? null
                        : 'Reported by the '
                            '${_role == rigRoleBase ? 'base' : 'connected'} '
                            'node: $detected',
                    suffixIcon: detected.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.sensors),
                            tooltip: 'Use $detected',
                            onPressed: () =>
                                setState(() => _setRadio(detected, auto: true)),
                          ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _antenna,
                    decoration: const InputDecoration(labelText: 'Antenna'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _gain,
                    keyboardType: decimal,
                    decoration: const InputDecoration(labelText: 'Gain (dBi)'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: _cable,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Cable'),
                    items: [
                      for (final c in cableTypes)
                        DropdownMenuItem(
                          value: c.key,
                          child: Text(c.lossDbPerM == 0
                              ? c.label
                              : '${c.label} (${c.lossDbPerM} dB/m)'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _cable = v ?? 'none'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _length,
                    keyboardType: decimal,
                    decoration: const InputDecoration(labelText: 'Length (m)'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Text('Connectors'),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _connectors > 0
                            ? () => setState(() => _connectors--)
                            : null,
                      ),
                      Text('$_connectors'),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => setState(() => _connectors++),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _connLoss,
                    keyboardType: decimal,
                    decoration: const InputDecoration(labelText: 'dB each'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
      ),
    );
  }
}
