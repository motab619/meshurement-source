// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/services/guided/base_change_sequence.dart';
import 'package:mesh_analyzer/services/guided/plan_models.dart';
import 'package:mesh_analyzer/services/remote_base_change.dart';

import 'guided/fake_plan_environment.dart';

void main() {
  late AppDatabase db;
  late FakePlanEnvironment env;
  late RemoteBaseChange change;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    env = FakePlanEnvironment(db)..remoteAdminMobileNode = 0x1001;
    change = RemoteBaseChange(env,
        sequence: BaseChangeSequence(
          env,
          settleDuration: const Duration(milliseconds: 10),
          listenDuration: const Duration(milliseconds: 60),
          rollbackListenDuration: const Duration(milliseconds: 40),
          pingEvery: const Duration(milliseconds: 5),
          tick: const Duration(milliseconds: 5),
        ));
  });

  tearDown(() async {
    change.dispose();
    await env.dispose();
    await db.close();
  });

  group('blocker', () {
    test('none when the mobile holds the base\'s grant', () {
      expect(change.blocker, isNull);
    });

    test('MeshCore has no remote admin', () {
      env.protocol = RadioProtocol.meshcore;
      expect(change.blocker, contains('MeshCore'));
    });

    test('no base yet', () {
      env.baseNodeNum = null;
      expect(change.blocker, contains('no base'));
    });

    test('the connected radio is not the mobile', () {
      env.connectedIsMobile = false;
      expect(change.blocker, contains('isn\'t the mobile'));
    });

    test('the base never granted this radio', () {
      env.remoteAdminMobileNode = null;
      expect(change.blocker, contains('Let the mobile node'));
      env.remoteAdminMobileNode = 0x9999;
      expect(change.blocker, contains('Let the mobile node'));
    });

    test('not on the test channel', () {
      env.onTestChannel = false;
      expect(change.blocker, contains('test channel'));
    });

    test('apply refuses while blocked', () async {
      env.connectedIsMobile = false;
      await expectLater(
          change.apply(preset: MeshtasticPresets.longFast), throwsStateError);
      expect(env.remoteChanges, isEmpty);
    });
  });

  test('a range setting changes the base, then the mobile, and listens',
      () async {
    env.pingScript.add(PingStatus.received);
    final ok = await change.apply(preset: MeshtasticPresets.longFast);
    expect(ok, isTrue);
    expect(env.remoteChanges, [('LONG_FAST', null)]);
    expect(env.mobileChanges, [('LONG_FAST', null)]);
    expect(env.recordedBase, [('LONG_FAST', null)]);
    expect(change.state!.phase, ChangePhase.done);
    expect(change.state!.targetName, 'Long Fast');
    expect(change.running, isFalse);
  });

  test('TX power alone changes only the base', () async {
    env.pingScript.add(PingStatus.received);
    final ok = await change.apply(txPowerDbm: 20);
    expect(ok, isTrue);
    expect(env.remoteChanges, [(null, 20)]);
    expect(env.mobileChanges, isEmpty);
    expect(env.currentTxPowerDbm, 27, reason: 'the mobile keeps its own');
    expect(change.state!.targetName, '20 dBm');
  });

  test('a silent base puts the mobile back and reports which side moved',
      () async {
    // Silent on the new setting and on the old one: the base moved.
    final ok = await change.apply(preset: MeshtasticPresets.longFast);
    expect(ok, isFalse);
    expect(env.mobileChanges, [('LONG_FAST', null), ('MEDIUM_FAST', 27)]);
    expect(env.currentPreset, MeshtasticPresets.mediumFast);
    final s = change.state!;
    expect(s.phase, ChangePhase.failed);
    expect(s.baseChanged, isTrue);
    expect(s.failure, contains('out of reach'));
  });

  test('a base that refuses leaves both radios alone', () async {
    env.remoteError = StateError('NAK: ADMIN_PUBLIC_KEY_UNAUTHORIZED');
    final ok = await change.apply(preset: MeshtasticPresets.longFast);
    expect(ok, isFalse);
    expect(env.mobileChanges, isEmpty);
    expect(change.state!.baseChanged, isFalse);
    expect(change.state!.failure, startsWith("The base didn't take"));
  });

  test('no original backup: refused before anything is sent', () async {
    env.originalBackup = false;
    final ok = await change.apply(preset: MeshtasticPresets.longFast);
    expect(ok, isFalse);
    expect(env.remoteChanges, isEmpty);
    expect(change.state!.failure, contains("aren't saved"));
  });

  test('targetName joins a range setting and a power', () {
    expect(
        RemoteBaseChange.targetName(
            preset: MeshtasticPresets.longFast, txPowerDbm: 20),
        'Long Fast at 20 dBm');
  });
}
