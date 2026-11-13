// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../demo/demo_mode.dart';
import '../../providers.dart';
import '../../services/pro_entitlement.dart';
import '../../services/rig_comparison.dart';
import '../screens/pro_paywall_screen.dart';
import '../screens/rig_comparison_screen.dart';
import '../protocol_text.dart';

String _sessionTitle(Session s) {
  if (s.name.isNotEmpty) return s.name;
  final t = s.startedAt.toLocal();
  return 'Session ${t.month}/${t.day} '
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

/// App-bar buttons of a coverage map: "Compare" (new comparison, Pro) and,
/// when the map has any, "Saved comparisons" (always viewable).
class ComparisonActions extends ConsumerStatefulWidget {
  final CoverageMap map;

  const ComparisonActions({super.key, required this.map});

  @override
  ConsumerState<ComparisonActions> createState() => _ComparisonActionsState();
}

class _ComparisonActionsState extends ConsumerState<ComparisonActions> {
  CoverageMap get map => widget.map;

  @override
  Widget build(BuildContext context) {
    // Rebuilt after returning from a screen, so new saves show up.
    final saved = SavedComparisonStore(ref.watch(sharedPreferencesProvider))
        .forMap(map.id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (saved.isNotEmpty)
          IconButton(
            tooltip: 'Saved comparisons',
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: _showSaved,
          ),
        ProGate(
          feature: ProFeature.rigComparison,
          onUnlocked: () => _openPicker(context),
          builder: (context, unlocked, activate) => IconButton(
            tooltip: unlocked || DemoMode.enabled ? 'Compare' : 'Compare (Pro)',
            icon: const Icon(Icons.compare),
            // Demo mode behaves as Pro.
            onPressed: DemoMode.enabled ? () => _openPicker(context) : activate,
          ),
        ),
      ],
    );
  }

  void _openPicker(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => RigComparisonPickerScreen(map: map),
        ))
        .then((_) => mounted ? setState(() {}) : null);
  }

  void _showSaved() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SavedComparisonsSheet(map: map),
    ).then((_) => mounted ? setState(() {}) : null);
  }
}

/// This map's saved comparisons: open one, or remove it. Viewable without
/// Pro (only a new comparison needs it). Shown from [ComparisonActions] and
/// the map detail's More menu.
class SavedComparisonsSheet extends ConsumerStatefulWidget {
  final CoverageMap map;

  const SavedComparisonsSheet({super.key, required this.map});

  @override
  ConsumerState<SavedComparisonsSheet> createState() =>
      _SavedComparisonsSheetState();
}

class _SavedComparisonsSheetState extends ConsumerState<SavedComparisonsSheet> {
  @override
  Widget build(BuildContext context) {
    final store = SavedComparisonStore(ref.watch(sharedPreferencesProvider));
    final saved = store.forMap(widget.map.id);
    final sessions =
        ref.watch(_mapSessionsProvider(widget.map.id)).valueOrNull ?? const [];
    String side(List<int> ids) => [
          for (final s in sessions)
            if (ids.contains(s.id)) _sessionTitle(s),
        ].join(', ');
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final c in saved)
            ListTile(
              leading: const Icon(Icons.compare),
              title: Text('${side(c.sessionIdsA)}\nvs ${side(c.sessionIdsB)}',
                  maxLines: 3, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  'Saved ${c.createdAt.toLocal().toString().substring(0, 16)}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove',
                onPressed: () async {
                  await store.remove(c);
                  if (mounted) setState(() {});
                },
              ),
              onTap: () {
                final nav = Navigator.of(context)..pop();
                nav.push(MaterialPageRoute<void>(
                  builder: (_) => RigComparisonScreen(
                    map: widget.map,
                    sessionIdsA: c.sessionIdsA,
                    sessionIdsB: c.sessionIdsB,
                  ),
                ));
              },
            ),
        ],
      ),
    );
  }
}

final _mapSessionsProvider =
    StreamProvider.family<List<Session>, int>((ref, mapId) {
  return ref.watch(databaseProvider).watchSessionsForMap(mapId);
});

/// Pick the sessions for side A and side B of a new comparison.
class RigComparisonPickerScreen extends ConsumerStatefulWidget {
  final CoverageMap map;

  const RigComparisonPickerScreen({super.key, required this.map});

  @override
  ConsumerState<RigComparisonPickerScreen> createState() =>
      _RigComparisonPickerScreenState();
}

class _RigComparisonPickerScreenState
    extends ConsumerState<RigComparisonPickerScreen> {
  final Set<int> _a = {}, _b = {};

  @override
  Widget build(BuildContext context) {
    final sessions =
        ref.watch(_mapSessionsProvider(widget.map.id)).valueOrNull ?? const [];
    final chosenA = [
      for (final s in sessions)
        if (_a.contains(s.id)) s
    ];
    final chosenB = [
      for (final s in sessions)
        if (_b.contains(s.id)) s
    ];
    final both = chosenA.isNotEmpty && chosenB.isNotEmpty;
    final check = both ? checkComparable(chosenA, chosenB) : null;

    void toggle(Set<int> mine, Set<int> other, int id) => setState(() {
          other.remove(id);
          if (!mine.remove(id)) mine.add(id);
        });

    return Scaffold(
      appBar: AppBar(title: const Text('Compare sessions')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Put the sessions to compare on side A and side B. Several '
              'sessions on one side are pooled. Best when the same route '
              'was walked with different hardware.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final s in sessions)
                  ListTile(
                    title: Text(_sessionTitle(s)),
                    subtitle: Text([
                      if (s.loraPreset.isNotEmpty)
                        anyPresetDisplayName(s.loraPreset),
                      'Mobile: ${groupRig([s], mobile: true).label}',
                      'Base: ${groupRig([s], mobile: false).label}',
                    ].join(' · ')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ChoiceChip(
                          label: const Text('A'),
                          selected: _a.contains(s.id),
                          onSelected: (_) => toggle(_a, _b, s.id),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('B'),
                          selected: _b.contains(s.id),
                          onSelected: (_) => toggle(_b, _a, s.id),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (check?.refusal != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(check!.refusal!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (check?.warning != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(check!.warning!,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: check != null && check.ok
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => RigComparisonScreen(
                                map: widget.map,
                                sessionIdsA: _a.toList()..sort(),
                                sessionIdsB: _b.toList()..sort(),
                              ),
                            ),
                          )
                      : null,
                  child: const Text('Compare'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
