// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/foundation.dart';

import '../data/radio/mesh_radio.dart';
import 'guided/base_change_sequence.dart';
import 'guided/plan_analysis.dart' show presetFromId;
import 'guided/plan_environment.dart';
import 'guided/plan_models.dart';

/// "Change the base from here" outside a guided test (Pro,
/// `ProFeature.remoteBaseChange`): the range setting and/or TX power of
/// the Node Setup base, over the mesh, with the guided test's safe
/// sequence ([BaseChangeSequence]): base first, then the radio in hand,
/// listen for the base, roll the radio in hand back when it stays silent.
///
/// A range setting changes both radios (they must match to hear each
/// other); a TX power change alone changes only the base.
///
/// Meshtastic only: MeshCore companions have no remote administration.
class RemoteBaseChange extends ChangeNotifier {
  RemoteBaseChange(this._env, {BaseChangeSequence? sequence})
      : _sequence = sequence ?? BaseChangeSequence(_env);

  final PlanEnvironment _env;
  final BaseChangeSequence _sequence;

  ChangeState? _state;
  final _rows = <CheckRow>[];
  bool _disposed = false;
  int _gen = 0;

  /// Progress of the change underway or just finished; null before.
  ChangeState? get state => _state;

  bool get running {
    final p = _state?.phase;
    return p != null && p != ChangePhase.done && p != ChangePhase.failed;
  }

  /// What the base was last set to by Node Setup or a remote change.
  RadioPreset? get basePreset => presetFromId(_env.basePresetId ?? '');
  int? get baseTxPowerDbm => _env.baseTxPowerDbm;
  String get baseLabel => _env.baseLabel;

  /// The radio in hand's own setting now.
  RadioPreset? get currentPreset => _env.currentPreset;
  int? get currentTxPowerDbm => _env.currentTxPowerDbm;

  /// Why a change can't start right now, as one sentence; null when it can.
  String? get blocker {
    if (_env.protocol == RadioProtocol.meshcore || !_env.supportsRemoteAdmin) {
      return 'MeshCore nodes can\'t be changed from a distance. Walk to the '
          'base and change it in Node Setup.';
    }
    if (_env.baseNodeNum == null) {
      return 'There is no base yet. Set one up in Node Setup first.';
    }
    if (!_env.radioReady) return 'Connect the node you carry first.';
    if (!_env.connectedIsMobile) {
      return 'The connected node isn\'t the mobile. Connect the node you '
          'carry.';
    }
    if (_env.remoteAdminMobileNode == null ||
        _env.remoteAdminMobileNode != _env.myNodeId) {
      return 'The base doesn\'t let this node change it yet. In Node '
          'Setup, turn on "Let the mobile node change this base from a distance" and '
          'set up the base again.';
    }
    if (!_env.onTestChannel) {
      return 'This node isn\'t on the test channel. Run Node Setup first.';
    }
    return null;
  }

  /// Human name of a change ("Long Fast", "20 dBm", "Long Fast at 20 dBm").
  static String targetName({RadioPreset? preset, int? txPowerDbm}) => [
        if (preset != null) preset.displayName,
        if (txPowerDbm != null) '$txPowerDbm dBm',
      ].join(' at ');

  /// Run the change. Returns true when the base answered on the new
  /// setting. Throws [StateError] when [blocker] is set or nothing would
  /// change.
  Future<bool> apply({RadioPreset? preset, int? txPowerDbm}) async {
    if (running) throw StateError('A change is already running');
    final why = blocker;
    if (why != null) throw StateError(why);
    if (preset == null && txPowerDbm == null) {
      throw StateError('Pick a range setting or a TX power');
    }
    final gen = ++_gen;
    _rows.clear();
    final name = targetName(preset: preset, txPowerDbm: txPowerDbm);
    _set(ChangePhase.ready, name);
    final result = await _sequence.run(
      BaseChangeRequest(
        preset: preset,
        txPowerDbm: txPowerDbm,
        oldPreset: _env.currentPreset,
        oldTxPowerDbm: _env.currentTxPowerDbm,
        changeBase: true,
        // A range setting must match on both; power is per radio.
        changeMobile: preset != null,
        remote: true,
        targetName: name,
        outOfReachAdvice: 'Walk to it and set both nodes to the same '
            'setting in Node Setup.',
      ),
      onPhase: (p) => _set(p, name),
      onRow: _row,
      cancelled: () => _disposed || gen != _gen,
    );
    if (result == null || _disposed) return false;
    _set(result.ok ? ChangePhase.done : ChangePhase.failed, name,
        failure: result.failure, baseChanged: result.baseChanged);
    return result.ok;
  }

  void _set(ChangePhase phase, String name,
      {String? failure, bool? baseChanged}) {
    _state = ChangeState(
      phase: phase,
      rows: List.unmodifiable(_rows),
      remote: true,
      targetName: name,
      failure: failure,
      baseChanged: baseChanged,
    );
    if (!_disposed) notifyListeners();
  }

  void _row(String label, String detail, CheckStatus status) {
    final row = CheckRow(label: label, detail: detail, status: status);
    final i = _rows.indexWhere((r) => r.label == label);
    if (i >= 0) {
      _rows[i] = row;
    } else {
      _rows.add(row);
    }
    final s = _state;
    if (s != null) _set(s.phase, s.targetName);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
