// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/app_database.dart';
import '../data/radio/radio_types.dart';

/// SharedPreferences key: the base radio's node number, saved when Radio
/// Setup configures it.
const baseNodePrefKey = 'base_node_num';

/// Our base radio's node number: the one Radio Setup configured, else the
/// base of the newest session (or, before any session had its own base,
/// the newest map's). Null if none is known.
Future<int?> knownBaseNodeNum(SharedPreferences prefs, AppDatabase db) async {
  final saved = prefs.getInt(baseNodePrefKey);
  if (saved != null) return saved;
  return db.latestBaseMeshNodeNum();
}

/// Which part of the base picker a node goes in.
enum BaseNodeGroup { yourBase, direct, other }

/// One entry in the base-node picker.
class BaseNodeOption {
  final int nodeNum;
  final String label;
  final String detail;
  final BaseNodeGroup group;

  /// Epoch seconds, 0 if unknown.
  final int lastHeard;

  const BaseNodeOption({
    required this.nodeNum,
    required this.label,
    required this.detail,
    required this.group,
    required this.lastHeard,
  });
}

String _hex(int num) => '!${num.toRadixString(16).padLeft(8, '0')}';

String _ago(int epochSec, DateTime now) {
  final diff =
      now.difference(DateTime.fromMillisecondsSinceEpoch(epochSec * 1000));
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Base-picker entries: [baseNum] first, then nodes the radio hears
/// directly (0 hops), then everything else, each most recently heard first.
/// [radioNodes] is the connected radio's node list, [dbNodes] the app's;
/// the connected radio itself ([myNum]) and [excludeNums] (our mobile
/// radio, which can never be the base) are left out. Every entry carries
/// its `!hex` id, since several radios may share a name ("MeshTest Base"
/// after a re-flash, or an old node number).
List<BaseNodeOption> buildBaseNodeOptions({
  required Iterable<RadioNode> radioNodes,
  required Iterable<Node> dbNodes,
  required int? myNum,
  required int? baseNum,
  Set<int> excludeNums = const {},
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final labels = {
    for (final n in dbNodes)
      if (n.userLabel?.isNotEmpty == true) n.nodeId: n.userLabel!,
  };
  final byId = <int, BaseNodeOption>{};

  BaseNodeGroup groupFor(int num, int? hops) => num == baseNum
      ? BaseNodeGroup.yourBase
      : hops == 0
          ? BaseNodeGroup.direct
          : BaseNodeGroup.other;

  for (final info in radioNodes) {
    if (info.num == myNum || excludeNums.contains(info.num)) continue;
    final heard = (info.lastHeard?.millisecondsSinceEpoch ?? 0) ~/ 1000;
    final hops = info.hopsAway;
    final parts = <String>[
      if (info.shortName.isNotEmpty) info.shortName,
      _hex(info.num),
      // Only say "direct" when the radio knows it's 0 hops.
      if (hops == 0) 'direct' else if (hops != null) '$hops hops',
      if (heard > 0) _ago(heard, clock),
    ];
    byId[info.num] = BaseNodeOption(
      nodeNum: info.num,
      label: labels[info.num] ??
          (info.longName.isNotEmpty ? info.longName : _hex(info.num)),
      detail: parts.join(' · '),
      group: groupFor(info.num, hops),
      lastHeard: heard,
    );
  }

  for (final node in dbNodes) {
    if (byId.containsKey(node.nodeId) ||
        node.nodeId == myNum ||
        excludeNums.contains(node.nodeId)) {
      continue;
    }
    final heard = node.lastHeardAt.millisecondsSinceEpoch ~/ 1000;
    byId[node.nodeId] = BaseNodeOption(
      nodeNum: node.nodeId,
      label: labels[node.nodeId] ??
          (node.longName.isNotEmpty ? node.longName : _hex(node.nodeId)),
      detail: '${_hex(node.nodeId)} · ${_ago(heard, clock)}',
      group: groupFor(node.nodeId, null),
      lastHeard: heard,
    );
  }

  return byId.values.toList()
    ..sort((a, b) {
      final g = a.group.index.compareTo(b.group.index);
      return g != 0 ? g : b.lastHeard.compareTo(a.lastHeard);
    });
}
