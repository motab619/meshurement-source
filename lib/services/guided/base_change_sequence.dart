// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import '../../data/radio/mesh_radio.dart';
import '../../utils/user_errors.dart';
import 'plan_analysis.dart' show presetFromId;
import 'plan_environment.dart';
import 'plan_models.dart';

/// What to change, and what it was before (for the rollback).
class BaseChangeRequest {
  const BaseChangeRequest({
    this.preset,
    this.txPowerDbm,
    this.oldPreset,
    this.oldTxPowerDbm,
    required this.changeBase,
    required this.changeMobile,
    required this.remote,
    required this.targetName,
    this.outOfReachAdvice =
        'Walk to it: the plan continues over Bluetooth from there.',
  });

  final RadioPreset? preset;
  final int? txPowerDbm;
  final RadioPreset? oldPreset;
  final int? oldTxPowerDbm;

  /// Which radios change. A range setting changes both (they must match);
  /// TX power can change one side only.
  final bool changeBase;
  final bool changeMobile;

  /// True: the base is changed over the mesh. False: over a second
  /// Bluetooth connection (the person is at the base).
  final bool remote;

  /// "Long Fast", "20 dBm".
  final String targetName;

  /// What to do when the base took the change and went out of reach.
  final String outOfReachAdvice;
}

/// How a change ended. [ok] means the base answered on the new setting.
class BaseChangeResult {
  const BaseChangeResult.ok()
      : ok = true,
        failure = null,
        baseChanged = null;
  const BaseChangeResult.failed(this.failure, {required this.baseChanged})
      : ok = false;

  final bool ok;

  /// One-line reason, shown under the rows.
  final String? failure;

  /// After a failure: whether the base is believed to be on the new
  /// setting (out of reach) or still on the old one.
  final bool? baseChanged;
}

/// The safe radio-change sequence (guided-test design §6), shared by the
/// guided test's changeRadios step and the standalone "Change the base"
/// screen:
///
/// 1. the base's settings are saved (an original backup must exist for a
///    remote change);
/// 2. the base changes first, over the mesh (one resend when the commit
///    went unanswered) or over Bluetooth;
/// 3. a settle countdown while the base restarts;
/// 4. then the radio in hand;
/// 5. ping the base for up to [listenDuration];
/// 6. silent: the radio in hand goes back to its old setting and the base
///    is pinged for [rollbackListenDuration] to tell which side moved.
///
/// Progress goes out through the callbacks; [run] returns null when
/// `cancelled()` turned true on the way (the caller has moved on).
class BaseChangeSequence {
  BaseChangeSequence(
    this._env, {
    DateTime Function()? clock,
    this.settleDuration = const Duration(seconds: 20),
    this.listenDuration = const Duration(seconds: 120),
    this.rollbackListenDuration = const Duration(seconds: 60),
    this.pingEvery = const Duration(seconds: 10),
    this.tick = const Duration(seconds: 1),
  }) : _clock = clock ?? DateTime.now;

  final PlanEnvironment _env;
  final DateTime Function() _clock;
  final Duration settleDuration;
  final Duration listenDuration;
  final Duration rollbackListenDuration;
  final Duration pingEvery;
  final Duration tick;

  Future<BaseChangeResult?> run(
    BaseChangeRequest r, {
    required void Function(ChangePhase phase) onPhase,
    required void Function(String label, String detail, CheckStatus status)
        onRow,
    void Function(int? secondsLeft)? onSettle,
    required bool Function() cancelled,
  }) async {
    final preset = r.preset;
    final txPower = r.txPowerDbm;
    final target = r.targetName;
    final remote = r.remote;

    // 1. Backup.
    onPhase(ChangePhase.backingUp);
    if (r.changeBase) {
      if (remote) {
        final saved = await _env.hasOriginalBaseBackup();
        if (cancelled()) return null;
        if (!saved) {
          onRow("Saving the base's settings", 'No backup of the base',
              CheckStatus.fail);
          return const BaseChangeResult.failed(
              "The base's settings aren't saved, so it can't be changed from "
              'here. Walk to it instead: Node Setup saves them first.',
              baseChanged: false);
        }
        onRow("Saving the base's settings", 'original backup kept',
            CheckStatus.ok);
      } else {
        onRow("Saving the base's settings", 'Node Setup keeps the original',
            CheckStatus.ok);
      }
    }

    // 2. The base first.
    if (r.changeBase) {
      onPhase(ChangePhase.changingBase);
      final label = 'Base: switching to $target';
      onRow(label, remote ? 'from here, over the mesh' : 'over Bluetooth',
          CheckStatus.busy);
      var saveUnconfirmed = false;
      try {
        if (remote) {
          var confirmed = await _env.changeBaseRemote(
              preset: preset,
              txPowerDbm: txPower,
              onStep: (s) => onRow(label, s, CheckStatus.busy));
          if (cancelled()) return null;
          if (!confirmed) {
            // Over the mesh the commit itself is often what got lost, and
            // the base then keeps its old setting. Once more: a second
            // commit after a reboot is harmless, and a base that already
            // restarted on the new setting can't hear it (not an error).
            onRow(label, "the base didn't confirm; sending again",
                CheckStatus.busy);
            try {
              confirmed = await _env.changeBaseRemote(
                  preset: preset,
                  txPowerDbm: txPower,
                  onStep: (s) => onRow(label, s, CheckStatus.busy));
            } catch (_) {
              confirmed = false;
            }
            if (cancelled()) return null;
            saveUnconfirmed = !confirmed;
          }
          await _env.recordBaseSetting(
              presetId: preset?.id, txPowerDbm: txPower);
        } else {
          final basePreset = preset ??
              presetFromId(_env.basePresetId ?? '') ??
              _env.currentPreset;
          if (basePreset == null) {
            throw StateError('The base\'s range setting is not known');
          }
          await _env.changeBaseBluetooth(
              preset: basePreset,
              txPowerDbm: txPower,
              onStep: (s) => onRow(label, s, CheckStatus.busy));
        }
      } catch (e) {
        if (cancelled()) return null;
        onRow(label, userMessage(e), CheckStatus.fail);
        return BaseChangeResult.failed(
            "The base didn't take the change: ${userMessage(e)}",
            baseChanged: false);
      }
      if (cancelled()) return null;
      if (saveUnconfirmed) {
        onRow(label, 'sent, but the base may not have saved it',
            CheckStatus.warn);
      } else {
        onRow(label, remote ? 'sent' : 'done', CheckStatus.ok);
      }

      // 3. Settle while the base restarts.
      onPhase(ChangePhase.settling);
      await _countdown(onRow, onSettle, cancelled);
      if (cancelled()) return null;
    }

    // 4. Then the mobile.
    if (r.changeMobile) {
      onPhase(ChangePhase.changingMobile);
      const label = 'Your node: switching';
      onRow(label, 'over Bluetooth, restarts', CheckStatus.busy);
      try {
        final mobilePreset = preset ?? _env.currentPreset;
        if (mobilePreset == null) {
          throw StateError('Your node\'s range setting is not known');
        }
        await _env.changeMobile(
            preset: mobilePreset,
            txPowerDbm: txPower,
            onStep: (s) => onRow(label, s, CheckStatus.busy));
      } catch (e) {
        if (cancelled()) return null;
        onRow(label, userMessage(e), CheckStatus.fail);
        return BaseChangeResult.failed(
            "Your node didn't take the change: ${userMessage(e)}",
            baseChanged: r.changeBase);
      }
      if (cancelled()) return null;
      onRow(label, 'done', CheckStatus.ok);
    }

    // 5. Listen for the base on the new setting.
    onPhase(ChangePhase.listening);
    const listenLabel = 'Listening for the base';
    onRow(listenLabel, 'up to ${listenDuration.inSeconds ~/ 60} min',
        CheckStatus.busy);
    final t0 = _clock();
    final heard = await _pingUntilHeard(listenDuration, cancelled);
    if (cancelled()) return null;
    if (heard) {
      onRow(listenLabel, 'answered in ${_clock().difference(t0).inSeconds} s',
          CheckStatus.ok);
      return const BaseChangeResult.ok();
    }
    onRow(listenLabel, 'silent for ${listenDuration.inSeconds} s',
        CheckStatus.fail);

    // 6. Silent: put the mobile back and find out which side moved.
    if (r.changeMobile) {
      await _restoreMobile(r, onRow, cancelled);
      if (cancelled()) return null;
    }
    const checkLabel = 'Checking the old setting';
    onRow(checkLabel, 'pinging for ${rollbackListenDuration.inSeconds} s',
        CheckStatus.busy);
    final answered = await _pingUntilHeard(rollbackListenDuration, cancelled);
    if (cancelled()) return null;
    if (answered) {
      onRow(checkLabel, 'the base answered', CheckStatus.ok);
      return const BaseChangeResult.failed(
          "The base didn't take the change. Your node is back on its old "
          'setting.',
          baseChanged: false);
    }
    onRow(checkLabel, 'still silent', CheckStatus.fail);
    return BaseChangeResult.failed(
        r.changeBase
            ? 'The base is on the new setting but out of reach from here. '
                '${r.outOfReachAdvice}'
            : 'The base is not answering on either setting. Walk to it '
                'and check it in Node Setup.',
        baseChanged: r.changeBase);
  }

  /// Put the radio in hand back on the setting it had before the change
  /// and read it back. A row is only `ok` when the radio reports the old
  /// setting (or can't report it); when the old setting isn't known there
  /// is nothing to restore, and the row says so instead of "done".
  Future<void> _restoreMobile(
    BaseChangeRequest r,
    void Function(String, String, CheckStatus) onRow,
    bool Function() cancelled,
  ) async {
    final preset = r.preset;
    final oldPreset = r.oldPreset;
    final oldTxPower = r.oldTxPowerDbm;
    final label = 'Your node: back to '
        '${oldPreset?.displayName ?? (oldTxPower != null ? '$oldTxPower dBm' : 'the old setting')}';
    // A range-setting change needs the old preset; a TX power change the
    // old power (the preset stayed as it was).
    final back = preset != null ? oldPreset : oldPreset ?? _env.currentPreset;
    final missing = preset != null
        ? (back == null ? 'range setting' : null)
        : (oldTxPower == null || back == null ? 'TX power' : null);
    if (missing != null) {
      final what = preset != null
          ? 'its old range setting'
          : (oldTxPower != null ? '$oldTxPower dBm' : 'its old TX power');
      onRow(
          label,
          "The old $missing isn't known, so nothing was changed. Set "
          '$what in Node Setup.',
          CheckStatus.fail);
      return;
    }
    onRow(label, 'over Bluetooth, restarts', CheckStatus.busy);
    try {
      await _env.changeMobile(
          preset: back!,
          txPowerDbm: oldTxPower,
          onStep: (s) => onRow(label, s, CheckStatus.busy));
    } catch (e) {
      if (cancelled()) return;
      onRow(label, userMessage(e), CheckStatus.fail);
      return;
    }
    if (cancelled()) return;
    // Read back what the radio reports now.
    final nowPreset = _env.currentPreset;
    final nowTx = _env.currentTxPowerDbm;
    final wrong = [
      if (nowPreset != null && nowPreset.id != back.id)
        'it is on ${nowPreset.displayName}',
      if (oldTxPower != null && nowTx != null && nowTx != oldTxPower)
        'it is at $nowTx dBm',
    ];
    if (wrong.isNotEmpty) {
      onRow(
          label,
          "Your node didn't go back: ${wrong.join(' and ')}. Set it in "
          'Node Setup.',
          CheckStatus.fail);
    } else if (nowPreset == null || (oldTxPower != null && nowTx == null)) {
      onRow(label, 'sent; the radio did not report its setting',
          CheckStatus.warn);
    } else {
      onRow(label, 'done', CheckStatus.ok);
    }
  }

  Future<void> _countdown(
    void Function(String, String, CheckStatus) onRow,
    void Function(int?)? onSettle,
    bool Function() cancelled,
  ) async {
    const label = 'Letting the base restart';
    var left = settleDuration.inSeconds;
    onRow(label, '$left s', CheckStatus.busy);
    onSettle?.call(left);
    while (left > 0) {
      await Future<void>.delayed(tick);
      if (cancelled()) return;
      left--;
      onSettle?.call(left);
      onRow(label, '$left s', CheckStatus.busy);
    }
    onSettle?.call(null);
    onRow(label, 'done', CheckStatus.ok);
  }

  /// Ping the base every [pingEvery] until it answers or [budget] runs
  /// out; waits for the radio to come back first.
  Future<bool> _pingUntilHeard(
      Duration budget, bool Function() cancelled) async {
    final base = _env.baseNodeNum;
    if (base == null) return false;
    final deadline = _clock().add(budget);
    // The mobile reboots after a change: wait for the link.
    while (!_env.radioReady) {
      if (_clock().isAfter(deadline) || cancelled()) return false;
      await Future<void>.delayed(tick);
    }
    try {
      await _env.prepareToPing(base);
    } catch (_) {
      // Keys sort themselves out on the first ping.
    }
    while (!cancelled()) {
      final left = deadline.difference(_clock());
      if (left <= Duration.zero) return false;
      final timeout = left < pingEvery ? left : pingEvery;
      final outcome =
          await _env.ping(base, timeout: timeout < tick ? tick : timeout);
      if (cancelled()) return false;
      if (outcome.status == PingStatus.received) return true;
      final wait = deadline.difference(_clock());
      if (wait <= Duration.zero) return false;
      await Future<void>.delayed(wait < pingEvery ? wait : pingEvery);
    }
    return false;
  }
}
