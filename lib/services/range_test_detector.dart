// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

/// Decides whether Range Test beacons are recorded, asking the user about
/// nodes it doesn't know.
///
/// Beacons from our base (the base of the map being recorded, or the radio
/// Radio Setup made the base) are always recorded without asking. For any
/// other node the first beacon emits a prompt; beacons are recorded while
/// the question is open (nothing is lost if the phone is in a pocket), and
/// stop being recorded only once the user says no. Answers are kept across
/// sessions, except "no", which lasts until the session ends.
class RangeTestDetector {
  /// node mesh ID → true (confirmed), false (declined), null (pending)
  final Map<int, bool?> _confirmationState = {};

  /// Nodes recorded without asking (our base radios).
  final Set<int> _trusted = {};

  final StreamController<RangeTestPrompt> _promptController =
      StreamController<RangeTestPrompt>.broadcast();

  /// Emits when user confirmation is needed (once per node).
  Stream<RangeTestPrompt> get promptStream => _promptController.stream;

  /// Record beacons from [meshNodeIds] without asking.
  void trust(Iterable<int?> meshNodeIds) {
    for (final id in meshNodeIds) {
      if (id == null) continue;
      _trusted.add(id);
      _confirmationState[id] = true;
    }
  }

  /// The answer given for [meshNodeId] (null: not asked or not answered).
  bool? confirmationFor(int meshNodeId) => _confirmationState[meshNodeId];

  /// Called by PacketProcessor for each Range Test packet received while a
  /// session records. Returns true if the packet should be logged.
  bool shouldLogRangeTest(int meshNodeId) {
    if (_trusted.contains(meshNodeId)) return true;
    if (!_confirmationState.containsKey(meshNodeId)) {
      _confirmationState[meshNodeId] = null; // pending
      if (!_promptController.isClosed) {
        _promptController.add(RangeTestPrompt(meshNodeId: meshNodeId));
      }
    }
    // Confirmed or still pending: record. Only a "no" drops it.
    return _confirmationState[meshNodeId] != false;
  }

  /// Called when the user responds to the confirmation prompt
  void setConfirmation(int meshNodeId, bool confirmed) {
    if (_trusted.contains(meshNodeId)) return;
    _confirmationState[meshNodeId] = confirmed;
  }

  /// Session ended: forget "no" answers and the session's trusted bases
  /// (they are set again when the next session starts). "Yes" answers and
  /// open questions are kept, so nobody is asked twice.
  void endSession() {
    _confirmationState.removeWhere(
        (id, v) => v == false || (_trusted.contains(id) && v == true));
    _trusted.clear();
  }

  /// Forget everything.
  void reset() {
    _confirmationState.clear();
    _trusted.clear();
  }

  void dispose() {
    _promptController.close();
  }
}

class RangeTestPrompt {
  final int meshNodeId;
  final String? nodeName;

  RangeTestPrompt({required this.meshNodeId, this.nodeName});
}
