// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_commander.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_frames.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_protocol.dart';

MeshCoreFrame frame(List<int> b) => MeshCoreFrame.parse(Uint8List.fromList(b));

void main() {
  late List<Uint8List> written;
  late MeshCoreCommander cmd;
  late DateTime now;

  void setUpCommander() {
    written = [];
    now = DateTime(2026, 11, 4, 12);
    cmd = MeshCoreCommander(
      write: (f, _) async => written.add(f),
      defaultTimeout: const Duration(seconds: 5),
      now: () => now,
    );
  }

  test('a timeout is MeshCoreNoReply, still a TimeoutException', () {
    fakeAsync((async) {
      setUpCommander();
      Object? error;
      cmd
          .send(Uint8List.fromList([MeshCoreCmd.getStats, 1]))
          .catchError((Object e) {
        error = e;
        return frame([0]);
      });
      async.elapse(const Duration(seconds: 6));
      expect(error, isA<MeshCoreNoReply>());
      expect(error, isA<TimeoutException>());
    });
  });

  test('a late reply to a timed-out command is not the next one\'s answer', () {
    fakeAsync((async) {
      setUpCommander();
      cmd
          .send(Uint8List.fromList([MeshCoreCmd.getStats, 1]))
          .catchError((Object _) => frame([0]));
      async.elapse(const Duration(seconds: 6));

      MeshCoreFrame? got;
      cmd
          .send(Uint8List.fromList([MeshCoreCmd.sendTracePath, 1, 2, 3, 4]))
          .then((f) => got = f);
      async.flushMicrotasks();
      expect(written.last[0], MeshCoreCmd.sendTracePath);

      // The stats reply turns up late: dropped, the trace keeps waiting.
      cmd.onResponse(frame([MeshCoreResp.stats, 1, 0, 0, 0, 0]));
      async.flushMicrotasks();
      expect(got, isNull);
      expect(cmd.busy, isTrue);

      cmd.onResponse(frame([MeshCoreResp.sent, 0, 1, 2, 3, 4, 0, 0, 0, 0]));
      async.flushMicrotasks();
      expect(got!.code, MeshCoreResp.sent);
    });
  });

  test('without a timeout before it, any reply answers the command', () {
    fakeAsync((async) {
      setUpCommander();
      MeshCoreFrame? got;
      cmd
          .send(Uint8List.fromList([MeshCoreCmd.sendTracePath, 1, 2, 3, 4]))
          .then((f) => got = f);
      async.flushMicrotasks();
      cmd.onResponse(frame([MeshCoreResp.stats, 1]));
      async.flushMicrotasks();
      expect(got!.code, MeshCoreResp.stats,
          reason: 'the caller checks the frame type itself');
    });
  });

  test('errors always answer, even with a late reply owed', () {
    fakeAsync((async) {
      setUpCommander();
      cmd
          .send(Uint8List.fromList([MeshCoreCmd.getStats, 1]))
          .catchError((Object _) => frame([0]));
      async.elapse(const Duration(seconds: 6));
      MeshCoreFrame? got;
      cmd
          .send(Uint8List.fromList([MeshCoreCmd.sendTracePath, 1, 2, 3, 4]))
          .then((f) => got = f);
      async.flushMicrotasks();
      cmd.onResponse(frame([MeshCoreResp.err, MeshCoreErr.tableFull]));
      async.flushMicrotasks();
      expect(got!.code, MeshCoreResp.err);
    });
  });

  test('a late reply is only expected for a while', () {
    fakeAsync((async) {
      setUpCommander();
      cmd
          .send(Uint8List.fromList([MeshCoreCmd.getStats, 1]))
          .catchError((Object _) => frame([0]));
      async.elapse(const Duration(seconds: 6));
      now = now.add(MeshCoreCommander.lateReplyWindow * 2);
      MeshCoreFrame? got;
      cmd
          .send(Uint8List.fromList([MeshCoreCmd.sendTracePath, 1, 2, 3, 4]))
          .then((f) => got = f);
      async.flushMicrotasks();
      cmd.onResponse(frame([MeshCoreResp.stats, 1]));
      async.flushMicrotasks();
      expect(got!.code, MeshCoreResp.stats);
    });
  });

  test('a write failure fails the command with the write error', () {
    fakeAsync((async) {
      setUpCommander();
      final c = MeshCoreCommander(
          write: (_, __) => Future.error(StateError('ble write failed')));
      Object? error;
      c
          .send(Uint8List.fromList([MeshCoreCmd.getStats, 1]))
          .catchError((Object e) {
        error = e;
        return frame([0]);
      });
      async.flushMicrotasks();
      expect(error, isA<StateError>());
      expect(error, isNot(isA<MeshCoreNoReply>()));
    });
  });
}
