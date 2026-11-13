// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

// The bench server's `radio.setRemoteLora` command (scenario
// remote-base-change, tool/bench): the connected mobile changes the base
// over the mesh through a scripted transport, no socket, no Bluetooth.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/bench/bench_server.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/proto/meshtastic/admin.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/services/base_node.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../meshtastic/fake_meshtastic_transport.dart';

const mobileNum = 0x10;
const baseNum = 0x20;
final mobileKey = keyOf([0xA1]);
final mobilePrivate = keyOf([0xA2]);
final baseKey = keyOf([0xB1]);
final passkey = [1, 2, 3, 4, 5, 6, 7, 8];

final baseLora = pb.Config_LoRaConfig(
  usePreset: true,
  modemPreset: pb.Config_LoRaConfig_ModemPreset.MEDIUM_FAST,
  region: pb.Config_LoRaConfig_RegionCode.US,
  txPower: 27,
  hopLimit: 3,
);

/// The mobile radio with the base in its node list (keys on both sides).
FakeMeshtasticTransport fakeMobile() => FakeMeshtasticTransport(
      myNodeNum: mobileNum,
      nodes: [
        pb.NodeInfo(
            num: mobileNum,
            user: pb.User(longName: 'MeshTest Mobile', publicKey: mobileKey)),
        pb.NodeInfo(
            num: baseNum,
            user: pb.User(longName: 'MeshTest Base', publicKey: baseKey)),
      ],
      security:
          pb.Config_SecurityConfig(publicKey: mobileKey, privateKey: mobilePrivate),
    );

/// A base that answers like the firmware: LoRa settings plus a session
/// passkey for the get, an ACK for everything else; [silent] leaves one
/// message kind unanswered.
List<pb.FromRadio>? Function(pb.MeshPacket) baseAnswers(
        {bool Function(pb.AdminMessage)? silent}) =>
    (p) {
      if (p.to != baseNum) return null;
      final admin = adminOf(p);
      if (silent != null && silent(admin)) return const [];
      final ack = routingFrame(p, from: baseNum);
      if (admin.hasGetConfigRequest()) {
        return [
          ack,
          adminFrame(p,
              from: baseNum,
              message: pb.AdminMessage(
                  getConfigResponse: pb.Config(lora: baseLora),
                  sessionPasskey: passkey)),
        ];
      }
      return [ack];
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMeshtasticTransport transport;
  late MeshtasticRadio radio;
  late RadioRoles roles;

  /// The server reads providers through this; only the two it needs here.
  T read<T>(ProviderListenable<T> provider) {
    if (identical(provider, meshRadioProvider)) return radio as T;
    if (identical(provider, radioRolesProvider)) return roles as T;
    throw UnimplementedError('bench test reader: $provider');
  }

  Future<BenchServer> serverWithBase({int? baseNode = baseNum}) async {
    SharedPreferences.setMockInitialValues(
        {if (baseNode != null) baseNodePrefKey: baseNode});
    roles = RadioRoles(await SharedPreferences.getInstance());
    radio = MeshtasticRadio(
        transport: transport,
        remoteExchangeTimeout: const Duration(milliseconds: 300));
    await radio.connect(const RadioDescriptor(id: 'mob', name: 'Mobile'));
    expect(radio.isReady, isTrue);
    return BenchServer(read);
  }

  setUp(() => transport = fakeMobile()..onPacket = baseAnswers());
  tearDown(() => radio.dispose());

  test('changes the Radio Setup base: get → begin → set → commit, confirmed',
      () async {
    final server = await serverWithBase();
    final value = await server.run('radio.setRemoteLora',
        {'preset': 'MEDIUM_SLOW', 'txPower': 20}) as Map;

    expect(value['nodeNum'], baseNum);
    expect(value['confirmed'], isTrue);
    final steps = value['steps'] as List;
    expect(steps.first, 'Asking MeshTest Base for its settings…');
    expect(steps.last, 'Done');

    final msgs = transport.adminPacketsTo(baseNum).map(adminOf).toList();
    expect(msgs.map((m) => m.whichPayloadVariant()), [
      pb.AdminMessage_PayloadVariant.getConfigRequest,
      pb.AdminMessage_PayloadVariant.beginEditSettings,
      pb.AdminMessage_PayloadVariant.setConfig,
      pb.AdminMessage_PayloadVariant.commitEditSettings,
    ]);
    final lora = msgs[2].setConfig.lora;
    expect(lora.modemPreset, pb.Config_LoRaConfig_ModemPreset.MEDIUM_SLOW);
    expect(lora.txPower, 20);
    expect(lora.region, pb.Config_LoRaConfig_RegionCode.US,
        reason: 'the rest as read from the base');
    for (final m in msgs.skip(1)) {
      expect(m.sessionPasskey, passkey);
    }
    // Every step also went out as a `remote` event for the Mac's log.
    final remote = server.events.where((e) => e['type'] == 'remote').toList();
    expect(remote.map((e) => e['step']), steps);
    expect(remote.first['nodeNum'], baseNum);
    // The app's picture of the base follows (roles.basePreset in /state).
    expect(roles.presetOf(RadioRole.base), 'MEDIUM_SLOW');
    expect(roles.txPowerOf(RadioRole.base), 20);
  });

  test('a commit the base never acknowledges is sent but not confirmed',
      () async {
    transport.onPacket = baseAnswers(silent: (m) => m.hasCommitEditSettings());
    final server = await serverWithBase();
    final value = await server
        .run('radio.setRemoteLora', {'preset': 'LONG_FAST'}) as Map;
    expect(value['confirmed'], isFalse);
    expect((value['steps'] as List).join('\n'),
        contains(BenchServer.unconfirmedSaveStep));
    expect(
        transport
            .adminPacketsTo(baseNum)
            .map(adminOf)
            .where((m) => m.hasCommitEditSettings()),
        hasLength(1));
  });

  test('an explicit nodeNum wins over the roles; tx power alone is fine',
      () async {
    final server = await serverWithBase(baseNode: 0x99);
    final value = await server
        .run('radio.setRemoteLora', {'nodeNum': baseNum, 'txPower': 0}) as Map;
    expect(value['nodeNum'], baseNum);
    final lora = transport
        .adminPacketsTo(baseNum)
        .map(adminOf)
        .firstWhere((m) => m.hasSetConfig())
        .setConfig
        .lora;
    expect(lora.txPower, 0);
    expect(lora.modemPreset, pb.Config_LoRaConfig_ModemPreset.MEDIUM_FAST);
    expect(roles.presetOf(RadioRole.base), isNull,
        reason: 'another node: the Radio Setup base is not touched');
  });

  test('refused without a base node, with an unknown preset, or nothing to '
      'change: nothing goes out', () async {
    final server = await serverWithBase(baseNode: null);
    await expectLater(
        server.run('radio.setRemoteLora', {'preset': 'MEDIUM_SLOW'}),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('Radio Setup'))));
    await expectLater(
        server.run('radio.setRemoteLora',
            {'nodeNum': baseNum, 'preset': 'NOT_A_PRESET'}),
        throwsArgumentError);
    await expectLater(
        server.run('radio.setRemoteLora', {'nodeNum': baseNum}),
        throwsArgumentError);
    expect(transport.adminPacketsTo(baseNum), isEmpty);
  });

  test('unknown commands are an ArgumentError', () async {
    final server = await serverWithBase();
    await expectLater(server.run('radio.nope', {}), throwsArgumentError);
  });
}
