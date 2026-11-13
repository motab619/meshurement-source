// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

// The bench server's commands against scripted radios: no HTTP, no
// Bluetooth. MeshCore is the point (a BLE companion build is silent on USB,
// so the bench verifies it through these commands; docs/design/bench-rig
// §5.1), with one Meshtastic snapshot for the generic path.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/bench/bench_server.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_protocol.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/data/radio/switchable_radio.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/services/radio_backup_service.dart';
import 'package:mesh_analyzer/services/radio_profile_service.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshcore/fake_meshcore_transport.dart';
import '../meshtastic/fake_meshtastic_transport.dart' show FakeMeshtasticTransport;

final mobileKey = keyOf([0x11, 0x22, 0x33, 0x44]);
final baseKey = keyOf([0xB0, 0x5E, 0x00, 0x01]);
const mobileNode = 0x11223344;
const baseNode = 0xB05E0001;
const mtNode = 0x68e178cb;

/// A MeshCore companion that reads back what was written to it (name,
/// radio params, repeat flag), like the firmware does after SET_*.
FakeMeshCoreTransport companion(Uint8List key, String name) {
  final t = FakeMeshCoreTransport(ownKey: key);
  var current = name;
  t.selfInfo = selfInfoFrame(key: key, name: name);
  t.after[MeshCoreCmd.setAdvertName] = (cmd) {
    current = utf8.decode(cmd.sublist(1));
    t.selfInfo = selfInfoFrame(key: key, name: current);
  };
  t.after[MeshCoreCmd.setRadioParams] = (cmd) {
    t.selfInfo = selfInfoFrame(
        key: key,
        name: current,
        freqKHz: u32At(cmd, 1),
        bwHz: u32At(cmd, 5),
        sf: cmd[9],
        cr: cmd[10]);
    t.deviceInfo = deviceInfoFrame(repeat: cmd.length > 11 && cmd[11] == 1);
  };
  return t;
}

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  late FakeMeshCoreTransport mobile;
  late FakeMeshCoreTransport base;
  late FakeMeshtasticTransport mt;
  late SharedPreferences prefs;
  late ProviderContainer container;
  late BenchServer server;
  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('bench_server');
    mobile = companion(mobileKey, 'L1 Mobile');
    base = companion(baseKey, 'T1000 Base');
    mt = FakeMeshtasticTransport(myNodeNum: mtNode, nodes: [
      pb.NodeInfo(
          num: mtNode, user: pb.User(longName: 'Heltec', shortName: 'HLTC')),
    ]);
    MeshCoreRadio mc(FakeMeshCoreTransport t) => MeshCoreRadio(
          transport: t,
          commandTimeout: const Duration(milliseconds: 500),
          contactsIdleTimeout: const Duration(milliseconds: 500),
          statsInterval: const Duration(hours: 1),
          reconnectInitialDelay: const Duration(milliseconds: 10),
        );
    // The phone's radio: whichever protocol it connects to.
    final radio = SwitchableRadio(
      factory: (p) => p == RadioProtocol.meshcore
          ? mc(mobile)
          : MeshtasticRadio(transport: mt),
    );
    // Radio Setup's second, temporary connection goes to the base.
    MeshRadio baseFactory(RadioProtocol p) => mc(base);
    final backups = RadioBackupService(directory: dir);
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      meshRadioProvider.overrideWithValue(radio),
      radioFactoryProvider.overrideWithValue(baseFactory),
      radioBackupServiceProvider.overrideWithValue(backups),
      radioProfileServiceProvider.overrideWith((ref) => RadioProfileService(
          radio, prefs, backups, baseFactory, ref.watch(radioRolesProvider))),
    ]);
    server = BenchServer(container.read);
    addTearDown(() async {
      await radio.dispose();
      container.dispose();
      await db.close();
      dir.deleteSync(recursive: true);
    });
  });

  Future<Map<String, dynamic>> run(String cmd,
          [Map<String, dynamic> args = const {}]) async =>
      (await server.run(cmd, args)) as Map<String, dynamic>;

  group('MeshCore read-back', () {
    test('radio.connect with protocol meshcore switches the radio and '
        'radio.settings returns the companion settings, secrets as hex',
        () async {
      final st = await run('radio.connect',
          {'id': 'mc-mobile', 'name': 'MeshCore-L1', 'protocol': 'meshcore'});
      expect(st['protocol'], 'meshcore');
      expect(st['ready'], isTrue);
      expect(st['nodeId'], mobileNode);
      expect(st['preset'], 'MC_SF7_BW62.5_CR5');

      final s = await run('radio.settings');
      expect(s['name'], 'L1 Mobile');
      expect(s['txPowerDbm'], 22);
      expect(s['frequencyKHz'], 910525);
      expect(s['frequencyMHz'], closeTo(910.525, 1e-6));
      expect(s['modulation'], 'MC_SF7_BW62.5_CR5');
      expect(s['community'], 'MC_USA');
      expect(s['clientRepeat'], isFalse);
      expect(s['firmwareVersion'], 'v1.18.0');
      final channels = s['channels'] as List;
      expect(channels.length, 4);
      final public = channels[0] as Map<String, dynamic>;
      expect(public['name'], 'Public');
      expect(public['secret'], '8b' * 16);
      expect(public['empty'], isFalse);
      expect((channels[1] as Map)['empty'], isTrue);

      final snap = await run('radio.snapshot');
      expect(snap['protocol'], 'meshcore');
      expect(snap['nodeId'], mobileNode);
      expect(snap['nodeIdHex'], '!11223344');
      expect(snap['onPublicChannel'], isTrue);
      expect((snap['meshcore'] as Map)['frequencyKHz'], 910525);
      expect(snap.containsKey('meshtastic'), isFalse);
    });

    test('radio.settings and radio.snapshot refuse before a connection',
        () async {
      expect(() => server.run('radio.settings', {}), throwsStateError);
      expect(() => server.run('radio.snapshot', {}), throwsStateError);
    });
  });

  group('Radio Setup over the bench server, MeshCore pair', () {
    test(
        'base flow: ladder preset, relay base on 918 MHz, the mobile follows '
        'the recorded frequency; snapshots and backups show it', () async {
      await server.run('radio.setupBase', {
        'id': 'mc-base',
        'name': 'MeshCore-T1000',
        'protocol': 'meshcore',
        'preset': 'MC_SF8_BW62.5_CR5',
        'beaconSecs': 10,
        'frequencyMHz': 918.0,
        'txPowerDbm': 20,
      });
      // The base companion got the channel, power and params with repeat on.
      final baseParams = base.writes
          .lastWhere((w) => w[0] == MeshCoreCmd.setRadioParams);
      expect(u32At(baseParams, 1), 918000);
      expect(u32At(baseParams, 5), 62500);
      expect(baseParams[9], 8);
      expect(baseParams[10], 5);
      expect(baseParams[11], 1);
      final baseChannel =
          base.writes.lastWhere((w) => w[0] == MeshCoreCmd.setChannel);
      final psk = base64Decode(prefs.getString('test_channel_psk')!);
      expect(psk.length, 32);
      expect(baseChannel[1], 1, reason: 'never slot 0');
      expect(utf8.decode(baseChannel.sublist(2, 10)), 'MeshTest');
      expect(baseChannel.sublist(34), psk.sublist(0, 16));
      final roles = container.read(radioRolesProvider);
      expect(roles.nodeOf(RadioRole.base), baseNode);
      expect(roles.frequencyOf(RadioRole.base), 918.0);
      expect(roles.presetOf(RadioRole.base), 'MC_SF8_BW62.5_CR5');
      expect(roles.baseBeacon?.kind, BeaconKind.trace);
      expect(roles.baseBeacon?.intervalSec, 10);

      // The mobile: no frequency given, it follows the base's.
      await server.run('radio.switchToAndApplyMobile', {
        'id': 'mc-mobile',
        'name': 'MeshCore-L1',
        'protocol': 'meshcore',
        'preset': 'MC_SF8_BW62.5_CR5',
      });
      final mobileParams = mobile.writes
          .lastWhere((w) => w[0] == MeshCoreCmd.setRadioParams);
      expect(u32At(mobileParams, 1), 918000);
      expect(mobileParams[9], 8);
      expect(mobileParams[11], 0, reason: 'the mobile never relays');
      expect(roles.nodeOf(RadioRole.mobile), mobileNode);

      // What the bench scenario reads back.
      final snap = await run('radio.snapshot');
      expect(snap['protocol'], 'meshcore');
      expect(snap['nodeId'], mobileNode);
      expect(snap['preset'], 'MC_SF8_BW62.5_CR5');
      expect(snap['onPublicChannel'], isFalse);
      final mc = snap['meshcore'] as Map<String, dynamic>;
      expect(mc['name'], 'MeshTest Mobile');
      expect(mc['frequencyKHz'], 918000);
      expect(mc['modulation'], 'MC_SF8_BW62.5_CR5');
      expect(mc['clientRepeat'], isFalse);
      final test = (mc['channels'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((c) => c['name'] == 'MeshTest');
      expect(test['secret'], hex(psk.sublist(0, 16)));

      final state = await run('radio.state');
      expect(state['protocol'], 'meshcore');
      expect(state['frequencyMHz'], 918.0);

      // One original backup per node, both MeshCore.
      final backups = (await server.run('backups.list', {}) as List)
          .cast<Map<String, dynamic>>();
      expect(backups.length, 2);
      expect(backups.every((b) => b['protocol'] == 'meshcore'), isTrue);
      expect(backups.every((b) => b['original'] == true), isTrue);
      expect(backups.map((b) => b['nodeNum']).toSet(), {baseNode, mobileNode});
      final onlyBase = (await server.run('backups.list', {'nodeNum': baseNode})
              as List)
          .cast<Map<String, dynamic>>();
      expect(onlyBase.single['nodeId'], '!b05e0001');
      expect(onlyBase.single['radioName'], 'T1000 Base');
      expect(onlyBase.single['summary'], contains('910.525'));
    });

    test('a community preset id lands on the ladder; an unknown one is '
        'refused before anything is written', () async {
      await server.run('radio.connect',
          {'id': 'mc-mobile', 'protocol': 'meshcore'});
      expect(
          () => server.run('radio.setupConnected',
              {'role': 'mobile', 'preset': 'MEDIUM_SLOW_WRONG'}),
          throwsArgumentError);
      expect(mobile.writtenCodes, isNot(contains(MeshCoreCmd.setRadioParams)));

      await server.run('radio.setupConnected', {
        'role': 'mobile',
        'preset': 'MC_USA',
        'frequencyMHz': 918.0,
      });
      final params = mobile.writes
          .lastWhere((w) => w[0] == MeshCoreCmd.setRadioParams);
      expect(params[9], 7);
      expect(u32At(params, 5), 62500);
      expect(params[10], 5);
      expect(container.read(radioRolesProvider).presetOf(RadioRole.mobile),
          'MC_SF7_BW62.5_CR5');
    });

    test('with no frequency given and no base recorded, the connected '
        'radio\'s band decides (915 band → 918.000)', () async {
      await server.run('radio.connect',
          {'id': 'mc-mobile', 'protocol': 'meshcore'});
      await server.run('radio.setupConnected',
          {'role': 'mobile', 'preset': 'MC_SF7_BW62.5_CR5'});
      final params = mobile.writes
          .lastWhere((w) => w[0] == MeshCoreCmd.setRadioParams);
      expect(u32At(params, 1), 918000);
    });
  });

  group('Meshtastic snapshot (the generic path)', () {
    test('radio.snapshot returns channels, lora and owner; radio.settings '
        'says to use it', () async {
      final st = await run('radio.connect', {'id': 'mt', 'name': 'HLTC_78cb'});
      expect(st['protocol'], 'meshtastic');
      final snap = await run('radio.snapshot');
      expect(snap['protocol'], 'meshtastic');
      expect(snap['nodeId'], mtNode);
      expect(snap['preset'], 'LONG_FAST');
      final m = snap['meshtastic'] as Map<String, dynamic>;
      final channels = (m['channels'] as List).cast<Map<String, dynamic>>();
      expect(channels.length, 8);
      expect(channels[0]['role'], 'PRIMARY');
      expect(channels[0]['name'], 'MeshTest');
      expect(channels[0]['psk'], '07' * 32);
      expect(channels[1]['role'], 'DISABLED');
      final lora = m['lora'] as Map<String, dynamic>;
      expect(lora['modemPreset'], 'LONG_FAST');
      expect(lora['region'], 'US');
      expect(lora['txPower'], 27);
      expect(lora['hopLimit'], 3);
      expect((m['owner'] as Map)['longName'], 'Heltec');
      expect((m['owner'] as Map)['shortName'], 'HLTC');
      expect(snap.containsKey('meshcore'), isFalse);

      expect(
          () => server.run('radio.settings', {}),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('radio.snapshot'))));
    });
  });
}
