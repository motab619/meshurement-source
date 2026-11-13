// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../providers.dart';
import '../../services/rig_math.dart';
import '../../utils/user_errors.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../layout/window_class.dart';

class NodeListScreen extends ConsumerWidget {
  const NodeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodesAsync = ref.watch(nodesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nodes')),
      body: WideColumn(
        child: nodesAsync.when(
          data: (nodes) {
            if (nodes.isEmpty) {
              return const EmptyState(
                icon: Icons.device_hub_outlined,
                title: 'No nodes heard yet',
                message:
                    'Connect to your node and the nodes it hears will appear here.',
              );
            }

            return ListView.builder(
              itemCount: nodes.length,
              itemBuilder: (context, index) {
                final node = nodes[index];
                return _NodeTile(node: node);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(userMessage(e, doing: 'loading the node list')),
          ),
        ),
      ),
    );
  }
}

class _NodeTile extends ConsumerWidget {
  final Node node;

  const _NodeTile({required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = node.userLabel?.isNotEmpty == true
        ? node.userLabel!
        : node.longName.isNotEmpty
            ? node.longName
            : shortNodeId(node.nodeId);

    final lastHeard = DateTime.now().difference(node.lastHeardAt);
    final lastHeardStr = lastHeard.inMinutes < 60
        ? '${lastHeard.inMinutes}m ago'
        : lastHeard.inHours < 24
            ? '${lastHeard.inHours}h ago'
            : '${lastHeard.inDays}d ago';

    final theme = Theme.of(context);
    final status = theme.status;
    final (badgeBg, badgeFg) = lastHeard.inMinutes < 30
        ? (status.okContainer, status.onOkContainer)
        : lastHeard.inHours < 2
            ? (status.warningContainer, status.onWarningContainer)
            : (status.neutral, status.onNeutral);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: badgeBg,
        child: Text(
          node.shortName.isNotEmpty
              ? node.shortName.substring(
                  0, node.shortName.length > 2 ? 2 : node.shortName.length)
              : '#',
          style: theme.textTheme.labelMedium?.copyWith(color: badgeFg),
        ),
      ),
      title: Text(displayName),
      subtitle: Text(
        '${radioModelName(node.hwModel).isNotEmpty ? radioModelName(node.hwModel) : "Unknown"} · $lastHeardStr',
      ),
      trailing: IconButton(
        tooltip: 'Edit name',
        icon: const Icon(Icons.edit, size: 20),
        onPressed: () => _showLabelDialog(context, ref, node),
      ),
      onTap: () => _showLabelDialog(context, ref, node),
    );
  }

  void _showLabelDialog(BuildContext context, WidgetRef ref, Node node) {
    final controller = TextEditingController(text: node.userLabel ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set node label'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Label',
            hintText: node.longName.isNotEmpty
                ? node.longName
                : shortNodeId(node.nodeId),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await ref
                  .read(databaseProvider)
                  .updateNodeLabel(node.id, controller.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
