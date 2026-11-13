// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../demo/demo_mode.dart';
import '../../providers.dart';
import '../theme/app_theme.dart';
import '../widgets/create_map_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/get_started_card.dart';
import 'coverage_map_detail_screen.dart';
import 'guided/guided_test_flow.dart';
import '../../utils/user_errors.dart';
import '../layout/window_class.dart';

class CoverageMapListScreen extends ConsumerWidget {
  const CoverageMapListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapsAsync = ref.watch(coverageMapsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Coverage maps')),
      body: WideColumn(
        child: mapsAsync.when(
          data: (maps) {
            if (maps.isEmpty) {
              return ListView(
                children: const [
                  GetStartedCard(),
                  PlanATestKey(),
                  EmptyState(
                    icon: Icons.layers_outlined,
                    tile: false,
                    title: 'No maps yet',
                    message: 'A map is a place with a base node.',
                  ),
                ],
              );
            }

            // The Get started checklist sits above the maps until dismissed.
            return ListView.builder(
              itemCount: maps.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) return const GetStartedCard();
                if (index == 1) return const PlanATestKey();
                final map = maps[index - 2];
                return ListTile(
                  leading: const Icon(Icons.map),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CoverageMapDetailScreen(map: map),
                    ),
                  ),
                  title: Text(map.name),
                  subtitle: Text(map.description.isEmpty
                      ? 'Created ${map.createdAt.toLocal().toString().substring(0, 16)}'
                      : map.description),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'More',
                    onSelected: (action) {
                      if (action == 'delete') _deleteMap(context, ref, map);
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(userMessage(e, doing: 'loading the maps'),
                      textAlign: TextAlign.center))),
        ),
      ),
      // While the Get started card shows and no map exists, its "New map"
      // is the way in; a + next to it would be a second button for the
      // same thing.
      floatingActionButton: _showFab(ref)
          ? FloatingActionButton(
              tooltip: 'New coverage map',
              onPressed: () => _showCreateDialog(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  /// The + shows once a map exists, or when the checklist doesn't show
  /// (hidden, or demo mode).
  bool _showFab(WidgetRef ref) {
    if (DemoMode.enabled || ref.watch(checklistHiddenProvider)) return true;
    return (ref.watch(coverageMapsProvider).valueOrNull?.length ?? 0) > 0;
  }

  /// Delete [map] after confirming; never the map being recorded into.
  Future<void> _deleteMap(
      BuildContext context, WidgetRef ref, CoverageMap map) async {
    final messenger = ScaffoldMessenger.of(context);
    void stopFirst() => messenger.showSnackBar(const SnackBar(
          content: Text('Stop the session first: this map is recording.'),
        ));
    final sessions = ref.read(sessionManagerProvider);
    if (sessions.isRecordingInto(map.id)) return stopFirst();

    final db = ref.read(databaseProvider);
    final counts = await db.coverageMapCounts(map.id);
    if (!context.mounted) return;
    String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete map?'),
        content: Text(
          'Delete "${map.name}" with its '
          '${plural(counts.sessions, 'session')} '
          '(${plural(counts.packets, 'recorded packet')})? '
          'This can\'t be undone; export CSV first to keep a copy.',
        ),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    // A session may have started on this map while the dialog was open.
    if (sessions.isRecordingInto(map.id)) return stopFirst();
    await db.deleteCoverageMap(map.id);
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showCreateMapDialog(context, ref);
  }
}

/// "Plan a test": the guided test's front door, at the top of the
/// Coverage tab under the Get started card. Outlined while the checklist
/// still has a radio to connect or Radio Setup to run (a guided test needs
/// both nodes set up, and the brightest button on a 1/4 checklist pulled
/// new users in too early); the filled orange key once that is done or
/// the checklist is hidden.
class PlanATestKey extends ConsumerWidget {
  const PlanATestKey({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open() => GuidedTestFlow.open(context);
    const icon = Icon(Icons.route);
    const label = Text('Plan a test');
    const size = Size(double.infinity, 44);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: radioSetupDone(ref)
          ? FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: size),
              onPressed: open,
              icon: icon,
              label: label,
            )
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: size),
              onPressed: open,
              icon: icon,
              label: label,
            ),
    );
  }
}
