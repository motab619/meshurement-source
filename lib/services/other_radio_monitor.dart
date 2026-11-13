// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/foundation.dart';

import '../utils/constants.dart';
import 'diag_log.dart';

/// What a radio other than the base did.
enum OtherRadioReason {
  /// Sent something on the test channel (telemetry, position, a beacon).
  heard,

  /// Answered one of our pings (an ACK or NAK aimed at our ping).
  answered,
}

/// A radio other than the session's base (and other than our own mobile)
/// seen on the test channel while recording.
class OtherRadioAlert {
  /// Mesh node number.
  final int nodeId;

  /// User label, long name, short name or `!hex` id.
  final String name;

  /// Readable hardware model ("Heltec V3"); empty when unknown.
  final String hwModel;
  final OtherRadioReason reason;

  /// Hops on the packet that gave it away (0 = heard directly).
  final int hops;
  final DateTime at;

  const OtherRadioAlert({
    required this.nodeId,
    required this.name,
    this.hwModel = '',
    required this.reason,
    required this.hops,
    required this.at,
  });

  /// Name plus hardware and short id, e.g. "MeshTest Base (Heltec V3 ·
  /// !a385)": two radios both named "MeshTest Base" must be told apart
  /// (field day 2026-10-27, the old base logged as a stranger).
  String get identity {
    final short = '!${nodeId.toRadixString(16).padLeft(8, '0').substring(4)}';
    final details = [
      if (hwModel.isNotEmpty) hwModel,
      if (!name.startsWith('!')) short,
    ];
    return details.isEmpty ? name : '$name (${details.join(' · ')})';
  }

  /// The banner text. Plain and non-blaming: the usual cause is a second
  /// base left powered on (field day 2026-10-26), and the fix is to turn
  /// it off.
  String get message {
    final what = reason == OtherRadioReason.answered
        ? 'Another node is answering'
        : 'Another node is on the test channel';
    return '$what: $identity. If it is a second base left on, turn it off; '
        'relayed answers do not count.';
  }
}

/// Notices radios that should not be there while a session records: any
/// sender on the test channel that is neither the base nor our own
/// mobile, and any node other than the base answering our pings.
///
/// The Compare screen only shows this afterwards ("Heads up" notes in
/// `range_stats.dart`); this is the live version, so a second base left
/// on is caught during the drive, not after it. Each node is reported
/// once per session: the banner is a heads-up, not a counter.
class OtherRadioMonitor {
  int? _baseNodeId;
  final Set<int> _noticed = {};

  /// The latest alert, until dismissed or the session ends.
  final current = ValueNotifier<OtherRadioAlert?>(null);

  /// Every alert this session, oldest first.
  final alerts = ValueNotifier<List<OtherRadioAlert>>(const []);

  bool get active => _baseNodeId != null;
  int? get baseNodeId => _baseNodeId;

  /// Watch for strangers while a session with [baseNodeId] records.
  void start({required int baseNodeId}) {
    _baseNodeId = baseNodeId;
    _noticed.clear();
    current.value = null;
    alerts.value = const [];
  }

  /// Session ended: hide the banner. The list is kept until the next
  /// session starts.
  void stop() {
    _baseNodeId = null;
    _noticed.clear();
    current.value = null;
  }

  /// Hide the banner; the node is not reported again this session.
  void dismiss() => current.value = null;

  /// Whether a packet is evidence of another radio, and of what. Null when
  /// it is the base's or our own, not on the test channel (another channel
  /// index, or one our radio could not decode), already reported this
  /// session, or no session records.
  ///
  /// Replies to our pings are judged whatever channel the radio puts them
  /// on (direct messages travel PKI-encrypted, outside the channel), since
  /// anything answering our ping is in the test by definition.
  OtherRadioReason? classify({
    required int from,
    required String type,
    int channelIndex = 0,
    bool decoded = true,
    int? myNodeId,
  }) {
    final base = _baseNodeId;
    if (base == null) return null;
    if (from == 0 || from == base || from == myNodeId) return null;
    if (_noticed.contains(from)) return null;
    if (type == PacketType.ack) return OtherRadioReason.answered;
    if (!decoded || channelIndex != 0) return null;
    return OtherRadioReason.heard;
  }

  /// Report [nodeId] (already classified) under [name]. Returns the alert
  /// when it is new this session, null when the node was reported before
  /// or no session records.
  OtherRadioAlert? notice({
    required int nodeId,
    required String name,
    String hwModel = '',
    required OtherRadioReason reason,
    int hops = 0,
    DateTime? now,
  }) {
    if (!active || !_noticed.add(nodeId)) return null;
    final alert = OtherRadioAlert(
      nodeId: nodeId,
      name: name,
      hwModel: hwModel,
      reason: reason,
      hops: hops,
      at: now ?? DateTime.now(),
    );
    final hopText = hops == 0 ? 'direct' : '$hops hop${hops == 1 ? '' : 's'}';
    final hw = hwModel.isEmpty ? '' : ' $hwModel';
    print('OtherRadioMonitor: ${diagNode(nodeId)} "$name"$hw ${reason.name} '
        '($hopText), base ${diagNode(_baseNodeId)}');
    DiagLog.instance.log(
        'radios', '${reason.name} ${diagNode(nodeId)} "$name"$hw ($hopText)');
    alerts.value = [...alerts.value, alert];
    current.value = alert;
    return alert;
  }

  void dispose() {
    current.dispose();
    alerts.dispose();
  }
}
