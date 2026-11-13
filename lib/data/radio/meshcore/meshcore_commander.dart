// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:typed_data';

import 'meshcore_frames.dart';
import 'meshcore_protocol.dart';

/// The radio never answered a command (its idle timeout ran out). The
/// command may or may not have reached the radio; a Bluetooth write that
/// fails or times out is reported as its own error instead.
class MeshCoreNoReply extends TimeoutException {
  MeshCoreNoReply(super.message, super.duration);
}

/// One-command-at-a-time request/response over a MeshCore companion link.
///
/// Responses carry no request id (docs/design/meshcore.md §2), so only one
/// command is outstanding: its response is the next non-push frame. Pushes
/// (code >= 0x80) never reach here; the radio dispatches them itself.
/// Every command has an idle timeout that restarts on each frame it
/// receives, so a long reply (the contact list) only fails when the radio
/// goes quiet.
///
/// A command that times out may still be answered later. Until that late
/// reply is used up, a frame whose code can't answer the running command
/// ([expectedReplies]) is taken as the late one and dropped, so it doesn't
/// fail the next command.
class MeshCoreCommander {
  MeshCoreCommander({
    required Future<void> Function(Uint8List frame, Duration timeout) write,
    this.defaultTimeout = const Duration(seconds: 5),
    DateTime Function()? now,
  })  : _write = write,
        _now = now ?? DateTime.now;

  final Future<void> Function(Uint8List frame, Duration timeout) _write;
  final Duration defaultTimeout;
  final DateTime Function() _now;

  final _queue = <_Job>[];
  _Job? _active;

  /// Replies still owed to commands that timed out, and when the last one
  /// timed out (late replies are only expected for [lateReplyWindow]).
  int _lateReplies = 0;
  DateTime? _lateSince;

  /// How long after a timeout a late reply is still expected.
  static const lateReplyWindow = Duration(seconds: 30);

  /// Error codes any command may get back.
  static const _anyCommand = {MeshCoreResp.err, MeshCoreResp.disabled};
  static const _okOrErr = {MeshCoreResp.ok, ..._anyCommand};

  /// The reply codes that can answer command [cmd], or null when not
  /// listed (then any frame is taken as its reply). docs/design/meshcore.md
  /// §4.
  static Set<int>? expectedReplies(int cmd) => switch (cmd) {
        MeshCoreCmd.deviceQuery => {MeshCoreResp.deviceInfo, ..._anyCommand},
        MeshCoreCmd.appStart => {MeshCoreResp.selfInfo, ..._anyCommand},
        MeshCoreCmd.getContacts => {
            MeshCoreResp.contactsStart,
            MeshCoreResp.contact,
            MeshCoreResp.endOfContacts,
            ..._anyCommand,
          },
        MeshCoreCmd.getDeviceTime => {MeshCoreResp.currTime, ..._anyCommand},
        MeshCoreCmd.getChannel => {MeshCoreResp.channelInfo, ..._anyCommand},
        MeshCoreCmd.syncNextMessage => {
            MeshCoreResp.contactMsgRecv,
            MeshCoreResp.channelMsgRecv,
            MeshCoreResp.contactMsgRecvV3,
            MeshCoreResp.channelMsgRecvV3,
            MeshCoreResp.channelDataRecv,
            MeshCoreResp.noMoreMessages,
            ..._anyCommand,
          },
        MeshCoreCmd.getStats => {MeshCoreResp.stats, ..._anyCommand},
        MeshCoreCmd.getCustomVars => {MeshCoreResp.customVars, ..._anyCommand},
        MeshCoreCmd.getBattAndStorage => {
            MeshCoreResp.battAndStorage,
            ..._anyCommand,
          },
        MeshCoreCmd.sendTracePath => {MeshCoreResp.sent, ..._anyCommand},
        MeshCoreCmd.setDeviceTime ||
        MeshCoreCmd.setAdvertName ||
        MeshCoreCmd.setRadioParams ||
        MeshCoreCmd.setRadioTxPower ||
        MeshCoreCmd.setChannel ||
        MeshCoreCmd.setOtherParams ||
        MeshCoreCmd.setCustomVar ||
        MeshCoreCmd.removeContact ||
        MeshCoreCmd.resetPath =>
          _okOrErr,
        _ => null,
      };

  /// Whether a command is waiting for its reply.
  bool get busy => _active != null;

  /// Send [frame] and complete with its single reply frame.
  Future<MeshCoreFrame> send(
    Uint8List frame, {
    Duration? timeout,
    Duration writeTimeout = const Duration(seconds: 15),
  }) async {
    final frames = await sendMulti(frame,
        isLast: (_) => true, timeout: timeout, writeTimeout: writeTimeout);
    return frames.single;
  }

  /// Send [frame], a command the firmware answers with a push or not at
  /// all (the self telemetry request): done once it is written, in turn
  /// with the other commands.
  Future<void> post(
    Uint8List frame, {
    Duration writeTimeout = const Duration(seconds: 15),
  }) {
    final job = _Job(frame, (_) => true, null, Duration.zero, writeTimeout,
        noReply: true);
    _queue.add(job);
    _pump();
    return job.completer.future;
  }

  /// Send [frame] and collect reply frames until [isLast] says one ends
  /// the reply (it is included). [onFrame] sees each as it arrives.
  Future<List<MeshCoreFrame>> sendMulti(
    Uint8List frame, {
    required bool Function(MeshCoreFrame f) isLast,
    void Function(MeshCoreFrame f)? onFrame,
    Duration? timeout,
    Duration writeTimeout = const Duration(seconds: 15),
  }) {
    final job =
        _Job(frame, isLast, onFrame, timeout ?? defaultTimeout, writeTimeout);
    _queue.add(job);
    _pump();
    return job.completer.future;
  }

  /// A non-push frame from the radio.
  void onResponse(MeshCoreFrame f) {
    final job = _active;
    if (_lateReplies > 0 && _now().difference(_lateSince!) > lateReplyWindow) {
      _lateReplies = 0;
    }
    if (job == null) {
      if (_lateReplies > 0) _lateReplies--;
      print('MeshCore: reply with no command waiting: $f');
      return;
    }
    if (_lateReplies > 0 && job.frames.isEmpty) {
      final expected = expectedReplies(job.frame[0]);
      if (expected != null && !expected.contains(f.code)) {
        _lateReplies--;
        print('MeshCore: dropped a late reply (code ${f.code}) while '
            'command ${job.frame[0]} waits');
        return;
      }
    }
    job.frames.add(f);
    job.onFrame?.call(f);
    if (job.isLast(f)) {
      _finish(job, null);
    } else {
      _arm(job);
    }
  }

  /// Fail the running and every queued command (link lost).
  void failAll(Object error) {
    final jobs = [if (_active != null) _active!, ..._queue];
    _queue.clear();
    _active?.timer?.cancel();
    _active = null;
    _lateReplies = 0;
    for (final j in jobs) {
      if (!j.completer.isCompleted) j.completer.completeError(error);
    }
  }

  void _pump() {
    if (_active != null || _queue.isEmpty) return;
    final job = _queue.removeAt(0);
    _active = job;
    if (!job.noReply) _arm(job);
    _write(job.frame, job.writeTimeout).then((_) {
      if (job.noReply && identical(_active, job)) _finish(job, null);
    }, onError: (Object e) {
      if (identical(_active, job)) _finish(job, e);
    });
  }

  void _arm(_Job job) {
    job.timer?.cancel();
    job.timer = Timer(job.timeout, () {
      if (identical(_active, job)) {
        _lateReplies++;
        _lateSince = _now();
        _finish(
            job,
            MeshCoreNoReply('No reply from the node to command ${job.frame[0]}',
                job.timeout));
      }
    });
  }

  void _finish(_Job job, Object? error) {
    job.timer?.cancel();
    if (identical(_active, job)) _active = null;
    if (!job.completer.isCompleted) {
      if (error != null) {
        job.completer.completeError(error);
      } else {
        job.completer.complete(job.frames);
      }
    }
    _pump();
  }
}

class _Job {
  _Job(this.frame, this.isLast, this.onFrame, this.timeout, this.writeTimeout,
      {this.noReply = false});

  final Uint8List frame;
  final bool Function(MeshCoreFrame) isLast;
  final void Function(MeshCoreFrame)? onFrame;
  final Duration timeout;
  final Duration writeTimeout;
  final bool noReply;
  final frames = <MeshCoreFrame>[];
  final completer = Completer<List<MeshCoreFrame>>();
  Timer? timer;
}
