// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/radio/mesh_radio.dart';
import '../../data/radio/radio_types.dart';
import '../../providers.dart';
import '../../services/radio_roles.dart';
import '../../services/rig_math.dart';
import '../theme/app_theme.dart';

/// Short node id, `!` and the last 4 hex digits (e.g. `!a385`).
String shortNodeHex(int num) =>
    '!${num.toRadixString(16).padLeft(8, '0').substring(4)}';

/// `name · hardware · !last4` for a radio, so two radios with the
/// same name ("MeshTest Base" after a re-flash) can be told apart. Name is
/// the user's label, else the long name the app or the radio knows.
String radioIdentityLabel(int num, {Node? dbNode, RadioNode? live}) {
  final name = [
    dbNode?.userLabel,
    dbNode?.longName,
    live?.longName,
    dbNode?.shortName,
    live?.shortName,
  ].firstWhere((n) => n != null && n.isNotEmpty, orElse: () => null);
  final hw = radioModelName((live?.hwModel.isNotEmpty ?? false)
      ? live!.hwModel
      : dbNode?.hwModel ?? '');
  return [
    if (name != null) name,
    if (hw.isNotEmpty) hw,
    shortNodeHex(num),
  ].join(' · ');
}

/// Session controls: which two radios the session measures between.
class SessionRadios extends ConsumerWidget {
  /// Mesh node number of the session's base radio; null if none is set up.
  final int? baseNodeNum;

  const SessionRadios({super.key, required this.baseNodeNum});

  /// Mobile (the connected radio) and Base (the session's base radio) by
  /// name, hardware and short id, so it's clear which two radios the
  /// session measures between.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radio = ref.read(meshRadioProvider);
    final linkState = ref.watch(meshLinkStateProvider).valueOrNull;
    final roles = ref.watch(radioRolesProvider);
    final nodes = ref.watch(nodesProvider).valueOrNull ?? const [];
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final myNum = radio.myNodeId;
    final mobileName =
        linkState == RadioConnectionState.ready || radio.descriptor != null
            ? radio.displayName
            : null;

    final baseNum = baseNodeNum;
    final baseLabel = baseNum == null
        ? null
        : radioIdentityLabel(baseNum,
            dbNode: nodes.where((n) => n.nodeId == baseNum).firstOrNull,
            live: radio.nodes[baseNum]);

    // The phone connected to the base (or a radio set up as base)
    // measures nothing useful.
    final onBase = myNum != null &&
        (baseNum == myNum || roles.roleOfNode(myNum) == RadioRole.base);

    Widget row(IconData icon, String role, List<InlineSpan> spans) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 16),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [TextSpan(text: '$role: '), ...spans]),
                  softWrap: true,
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(Icons.directions_walk, 'Mobile', [
          TextSpan(
            text: mobileName ?? 'not connected',
            style: mobileName == null ? muted : null,
          ),
          // Short id, unless the name already ends with it (default
          // names like "Meshtastic ae47").
          if (mobileName != null &&
              myNum != null &&
              !mobileName
                  .toLowerCase()
                  .endsWith(shortNodeHex(myNum).substring(1)))
            TextSpan(text: '  ${shortNodeHex(myNum)}', style: muted),
        ]),
        row(Icons.cell_tower, 'Base node', [
          TextSpan(
            text: baseLabel ?? 'not set up',
            style: baseLabel == null ? muted : null,
          ),
        ]),
        if (onBase)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Your phone is connected to the base node. Connect to the '
              'node you carry before recording.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.status.warning),
            ),
          ),
      ],
    );
  }
}
