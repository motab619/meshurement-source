// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

// Remote administration (guided test, design §5): the admin-key grant over
// the phone's link and the session-passkey exchange with the base over
// the mesh, frames in and frames out through a scripted transport.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_admin_keys.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_contacts.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/proto/meshtastic/admin.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/channel.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/portnums.pbenum.dart' as pb;
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_meshtastic_transport.dart';

const mobileNum = 0x10;
const baseNum = 0x20;
const relayNum = 0x30;
final mobileKey = keyOf([0xA1]);
final mobilePrivate = keyOf([0xA2]);
final baseKey = keyOf([0xB1]);
final passkey = [1, 2, 3, 4, 5, 6, 7, 8];

final baseLora = pb.Config_LoRaConfig(
  usePreset: true,
  modemPreset: pb.Config_LoRaConfig_ModemPreset.LONG_FAST,
  region: pb.Config_LoRaConfig_RegionCode.US,
  txPower: 27,
  hopLimit: 3,
  sx126xRxBoostedGain: true,
);

FakeMeshtasticTransport fakeMobile({
  pb.Config_SecurityConfig? security,
  bool baseKeyKnown = true,
}) =>
    FakeMeshtasticTransport(
      myNodeNum: mobileNum,
      nodes: [
        pb.NodeInfo(
            num: mobileNum,
            user: pb.User(longName: 'MeshTest Mobile', publicKey: mobileKey)),
        pb.NodeInfo(
            num: baseNum,
            user: pb.User(
                longName: 'MeshTest Base',
                publicKey: baseKeyKnown ? baseKey : const [])),
      ],
      security: security ??
          pb.Config_SecurityConfig(
              publicKey: mobileKey, privateKey: mobilePrivate),
    );

Future<MeshtasticRadio> connectTo(FakeMeshtasticTransport t) async {
  final radio = MeshtasticRadio(
      transport: t, remoteExchangeTimeout: const Duration(milliseconds: 300));
  await radio.connect(const RadioDescriptor(id: 'mob', name: 'Mobile'));
  expect(radio.isReady, isTrue);
  expect(radio.myNodeId, mobileNum);
  return radio;
}

/// A base that answers like the firmware: the LoRa settings with a session
/// passkey for the get, an ACK for everything else. [nak] turns one message
/// kind into a NAK from [nakFrom]; [silent] leaves one kind unanswered.
List<pb.FromRadio>? Function(pb.MeshPacket) baseAnswers({
  bool Function(pb.AdminMessage)? nak,
  int nakFrom = baseNum,
  pb.Routing_Error error = pb.Routing_Error.ADMIN_PUBLIC_KEY_UNAUTHORIZED,
  bool Function(pb.AdminMessage)? silent,
  List<int> ackFrom = const [baseNum],
}) =>
    (p) {
      if (p.to != baseNum) return null;
      final admin = adminOf(p);
      if (silent != null && silent(admin)) return const [];
      if (nak != null && nak(admin)) {
        return [routingFrame(p, from: nakFrom, error: error)];
      }
      final acks = [for (final f in ackFrom) routingFrame(p, from: f)];
      if (admin.hasGetConfigRequest()) {
        return [
          ...acks,
          adminFrame(p,
              from: baseNum,
              message: pb.AdminMessage(
                  getConfigResponse: pb.Config(lora: baseLora),
                  sessionPasskey: passkey)),
        ];
      }
      return acks;
    };

void main() {
  // DiagLog wants the services binding for its log file.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('adminKeysWith', () {
    final a = keyOf([1]), b = keyOf([2]), c = keyOf([3]), d = keyOf([4]);

    test('adds a missing key, leaves the list alone when present', () {
      expect(adminKeysWith([a], b), [a, b]);
      expect(adminKeysWith([a, b], b), isNull);
      expect(adminKeysWith([], a), [a]);
    });

    test('a full list drops nothing unless told to replace the oldest', () {
      expect(
          () => adminKeysWith([a, b, c], d, ownKey: a),
          throwsA(isA<AdminKeyListFull>()
              .having((e) => e.oldest, 'oldest', b)
              .having((e) => e.oldestHex, 'oldestHex', '02000102…')));
      // Already there: nothing to write, full or not.
      expect(adminKeysWith([a, b, c], b), isNull);
    });

    test('replaceOldest: the oldest key that is not the radio\'s own goes',
        () {
      List<int>? replaced;
      expect(
          adminKeysWith([a, b, c], d,
              ownKey: a, replaceOldest: true, onReplace: (k) => replaced = k),
          [a, c, d]);
      expect(replaced, b);
      expect(adminKeysWith([a, b, c], d, replaceOldest: true), [b, c, d]);
    });

    test('adminKeysWithout removes only that key', () {
      expect(adminKeysWithout([a, b, c], b), [a, c]);
      expect(adminKeysWithout([a, c], b), isNull);
      expect(adminKeysWithout([b], b), isEmpty);
    });

    test('refuses a key that is not 32 bytes', () {
      expect(() => adminKeysWith([], [1, 2, 3]), throwsArgumentError);
    });

    test('nodeIdHex', () => expect(nodeIdHex(0x1a2b), '!00001a2b'));
  });

  group('grantRemoteAdmin (local, no passkey)', () {
    late MeshtasticRadio radio;
    tearDown(() => radio.dispose());

    test('reads the security settings and writes them back with the key',
        () async {
      final t = fakeMobile();
      radio = await connectTo(t);
      final steps = <String>[];
      await radio.grantRemoteAdmin(baseKey, onStep: steps.add);

      final sent = t.localAdmin;
      expect(sent.map((m) => m.whichPayloadVariant()), [
        pb.AdminMessage_PayloadVariant.getConfigRequest,
        pb.AdminMessage_PayloadVariant.beginEditSettings,
        pb.AdminMessage_PayloadVariant.setConfig,
        pb.AdminMessage_PayloadVariant.commitEditSettings,
      ]);
      expect(sent.first.getConfigRequest,
          pb.AdminMessage_ConfigType.SECURITY_CONFIG);
      final get = t.adminPacketsTo(mobileNum).first;
      expect(get.decoded.wantResponse, isTrue);
      final written = sent[2].setConfig.security;
      expect(written.adminKey, [baseKey]);
      expect(written.publicKey, mobileKey, reason: 'identity kept');
      expect(written.privateKey, mobilePrivate, reason: 'identity kept');
      // Local admin: everything to our own node, no session passkey.
      for (final p in t.adminPacketsTo(mobileNum)) {
        expect(p.to, mobileNum);
        expect(adminOf(p).sessionPasskey, isEmpty);
      }
      expect(steps, contains('Saving — the node restarts…'));
    });

    test('is idempotent: a key already in the list writes nothing', () async {
      final t = fakeMobile(
          security: pb.Config_SecurityConfig(
              publicKey: mobileKey,
              privateKey: mobilePrivate,
              adminKey: [keyOf([0x55]), baseKey]));
      radio = await connectTo(t);
      final steps = <String>[];
      await radio.grantRemoteAdmin(baseKey, onStep: steps.add);
      expect(t.localAdmin.map((m) => m.whichPayloadVariant()),
          [pb.AdminMessage_PayloadVariant.getConfigRequest]);
      expect(steps.single, contains('already'));
    });

    test('a full list: nothing is dropped without the user\'s yes',
        () async {
      final other1 = keyOf([0x61]), other2 = keyOf([0x62]);
      final t = fakeMobile(
          security: pb.Config_SecurityConfig(
              publicKey: mobileKey,
              privateKey: mobilePrivate,
              adminKey: [mobileKey, other1, other2]));
      radio = await connectTo(t);
      await expectLater(
          radio.grantRemoteAdmin(baseKey), throwsA(isA<AdminKeyListFull>()));
      String? asked;
      await expectLater(
          radio.grantRemoteAdmin(baseKey, confirmReplace: (k) async {
            asked = k;
            return false; // Skip
          }),
          throwsA(isA<AdminKeyListFull>()));
      expect(asked, '61000102…', reason: 'the oldest foreign key, not ours');
      expect(t.localAdmin.where((m) => m.hasSetConfig()), isEmpty);
    });

    test('a full list: replace oldest on a yes, never the radio\'s own key',
        () async {
      final other1 = keyOf([0x61]), other2 = keyOf([0x62]);
      final t = fakeMobile(
          security: pb.Config_SecurityConfig(
              publicKey: mobileKey,
              privateKey: mobilePrivate,
              adminKey: [mobileKey, other1, other2]));
      radio = await connectTo(t);
      await radio.grantRemoteAdmin(baseKey, confirmReplace: (_) async => true);
      final written = t.localAdmin
          .firstWhere((m) => m.hasSetConfig())
          .setConfig
          .security
          .adminKey;
      expect(written, [mobileKey, other2, baseKey]);
    });

    test('refuses to write back a record without the private key', () async {
      // Older firmware would generate a new keypair (and 2.8 a new node
      // number) from such a write.
      final t = fakeMobile(
          security: pb.Config_SecurityConfig(publicKey: mobileKey));
      radio = await connectTo(t);
      await expectLater(radio.grantRemoteAdmin(baseKey), throwsStateError);
      expect(t.localAdmin.where((m) => m.hasSetConfig()), isEmpty);
    });

    test('falls back to the settings from connect when the request is '
        'unanswered', () async {
      final t = fakeMobile();
      final downloaded = t.security;
      t.onPacket = (p) {
        if (p.to == mobileNum && adminOf(p).hasGetConfigRequest()) {
          return const []; // no reply at all
        }
        return null;
      };
      radio = await connectTo(t);
      // The local get waits 10 s; the fallback then uses the handshake copy.
      final done = radio.grantRemoteAdmin(baseKey);
      await expectLater(done.timeout(const Duration(seconds: 12)), completes);
      final written =
          t.localAdmin.firstWhere((m) => m.hasSetConfig()).setConfig.security;
      expect(written.adminKey, [baseKey]);
      expect(written.privateKey, downloaded!.privateKey);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('a wrong-sized key or the radio\'s own key is refused', () async {
      radio = await connectTo(fakeMobile());
      await expectLater(radio.grantRemoteAdmin([1, 2, 3]), throwsArgumentError);
      await expectLater(radio.grantRemoteAdmin(mobileKey), throwsArgumentError);
    });
  });

  group('applyTestProfile with remoteAdminKey', () {
    late MeshtasticRadio radio;
    tearDown(() => radio.dispose());

    TestProfile base() => TestProfile(
          channelName: 'MeshTest',
          channelKey: Uint8List.fromList(List.filled(32, 7)),
          preset: MeshtasticPresets.longFast,
          isBase: true,
          beacon: const BeaconConfig(intervalSec: 30, kind: BeaconKind.telemetry),
        );

    test('the security write rides in the one edit transaction', () async {
      final t = fakeMobile();
      radio = await connectTo(t);
      bool? granted;
      final steps = <String>[];
      await radio.applyTestProfile(base(),
          onStep: steps.add,
          remoteAdminKey: baseKey,
          onRemoteAdmin: (ok) => granted = ok);
      expect(granted, isTrue);
      final kinds = t.localAdmin.map((m) => m.whichPayloadVariant()).toList();
      // The read comes before the transaction opens.
      expect(kinds.first, pb.AdminMessage_PayloadVariant.getConfigRequest);
      expect(kinds[1], pb.AdminMessage_PayloadVariant.beginEditSettings);
      expect(kinds.last, pb.AdminMessage_PayloadVariant.commitEditSettings);
      expect(kinds.where((k) => k == pb.AdminMessage_PayloadVariant.commitEditSettings),
          hasLength(1), reason: 'one reboot');
      final security = t.localAdmin
          .where((m) => m.hasSetConfig() && m.setConfig.hasSecurity())
          .single
          .setConfig
          .security;
      expect(security.adminKey, [baseKey]);
      expect(steps, contains(startsWith('Allowing the mobile node')));
    });

    test('already granted: nothing extra is written, still reported granted',
        () async {
      final t = fakeMobile(
          security: pb.Config_SecurityConfig(
              publicKey: mobileKey, privateKey: mobilePrivate, adminKey: [baseKey]));
      radio = await connectTo(t);
      bool? granted;
      await radio.applyTestProfile(base(),
          remoteAdminKey: baseKey, onRemoteAdmin: (ok) => granted = ok);
      expect(granted, isTrue);
      expect(t.localAdmin.where((m) => m.hasSetConfig() && m.setConfig.hasSecurity()),
          isEmpty);
    });

    test('a full admin list is left alone: no security write, not granted',
        () async {
      final t = fakeMobile(
          security: pb.Config_SecurityConfig(
              publicKey: mobileKey,
              privateKey: mobilePrivate,
              adminKey: [keyOf([0x61]), keyOf([0x62]), keyOf([0x63])]));
      radio = await connectTo(t);
      bool? granted;
      final steps = <String>[];
      await radio.applyTestProfile(base(),
          onStep: steps.add,
          remoteAdminKey: baseKey,
          onRemoteAdmin: (ok) => granted = ok);
      expect(granted, isFalse);
      expect(
          t.localAdmin
              .where((m) => m.hasSetConfig() && m.setConfig.hasSecurity()),
          isEmpty);
      expect(steps, contains(contains('already has 3 admin keys')));
      // The rest of the setup still happened.
      expect(t.localAdmin.last.hasCommitEditSettings(), isTrue);
    });

    test('a mobile profile ignores the key', () async {
      final t = fakeMobile();
      radio = await connectTo(t);
      await radio.applyTestProfile(
          TestProfile(
              channelName: 'MeshTest',
              channelKey: Uint8List.fromList(List.filled(32, 7)),
              preset: MeshtasticPresets.longFast,
              isBase: false),
          remoteAdminKey: baseKey);
      expect(t.localAdmin.where((m) => m.hasGetConfigRequest()), isEmpty);
    });
  });

  group('NodeInfo over the air', () {
    late MeshtasticRadio radio;
    tearDown(() => radio.dispose());

    pb.FromRadio nodeInfoFrom(int from, pb.User user) => pb.FromRadio(
          packet: pb.MeshPacket(
            from: from,
            to: 0xffffffff,
            id: 777,
            decoded: pb.Data(
                portnum: pb.PortNum.NODEINFO_APP,
                payload: user.writeToBuffer()),
          ),
        );

    test('a different key for a known node is ignored, never saved',
        () async {
      SharedPreferences.setMockInitialValues({});
      final contacts = MeshtasticContacts(await SharedPreferences.getInstance());
      await contacts.save(
          baseNum, pb.User(longName: 'MeshTest Base', publicKey: baseKey));
      final t = fakeMobile();
      radio = await connectTo(t);
      radio.contacts = contacts;
      final impostor = keyOf([0xEE]);
      t.push(nodeInfoFrom(
          baseNum, pb.User(longName: 'Renamed Base', publicKey: impostor)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final user = radio.nodeInfos[baseNum]!.user;
      expect(user.longName, 'Renamed Base');
      expect(user.publicKey, baseKey, reason: 'first key wins');
      await radio.prepareToPing(baseNum);
      expect(contacts.get(baseNum)!.publicKey, baseKey);
    });

    test('the same key updates the node as before', () async {
      final t = fakeMobile();
      radio = await connectTo(t);
      t.push(nodeInfoFrom(
          baseNum, pb.User(longName: 'Base 2', publicKey: baseKey)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(radio.nodeInfos[baseNum]!.user.longName, 'Base 2');
      expect(radio.nodeInfos[baseNum]!.user.publicKey, baseKey);
    });

    test('a node we have no key for takes the one it sends', () async {
      final t = fakeMobile(baseKeyKnown: false);
      radio = await connectTo(t);
      t.push(nodeInfoFrom(
          baseNum, pb.User(longName: 'MeshTest Base', publicKey: baseKey)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(radio.nodeInfos[baseNum]!.user.publicKey, baseKey);
    });
  });

  group('revokeRemoteAdmin (local)', () {
    late MeshtasticRadio radio;
    tearDown(() => radio.dispose());

    test('writes the record back without that key, identity kept', () async {
      final other = keyOf([0x55]);
      final t = fakeMobile(
          security: pb.Config_SecurityConfig(
              publicKey: mobileKey,
              privateKey: mobilePrivate,
              adminKey: [other, baseKey]));
      radio = await connectTo(t);
      expect(await radio.revokeRemoteAdmin(baseKey), isTrue);
      expect(t.localAdmin.map((m) => m.whichPayloadVariant()), [
        pb.AdminMessage_PayloadVariant.getConfigRequest,
        pb.AdminMessage_PayloadVariant.beginEditSettings,
        pb.AdminMessage_PayloadVariant.setConfig,
        pb.AdminMessage_PayloadVariant.commitEditSettings,
      ]);
      final written =
          t.localAdmin.firstWhere((m) => m.hasSetConfig()).setConfig.security;
      expect(written.adminKey, [other]);
      expect(written.privateKey, mobilePrivate);
      expect(written.publicKey, mobileKey);
    });

    test('a key not in the list writes nothing', () async {
      final t = fakeMobile();
      radio = await connectTo(t);
      expect(await radio.revokeRemoteAdmin(baseKey), isFalse);
      expect(t.localAdmin.where((m) => m.hasSetConfig()), isEmpty);
    });
  });

  group('setRemoteLora (over the mesh, session passkey)', () {
    late MeshtasticRadio radio;
    tearDown(() => radio.dispose());

    test('refused on the public channel: nothing goes out', () async {
      final t = FakeMeshtasticTransport(
        myNodeNum: mobileNum,
        nodes: fakeMobile().nodes,
        security: pb.Config_SecurityConfig(
            publicKey: mobileKey, privateKey: mobilePrivate),
        channels: [
          pb.Channel(
              index: 0,
              role: pb.Channel_Role.PRIMARY,
              settings: pb.ChannelSettings(name: '', psk: [1])),
        ],
      )..onPacket = baseAnswers();
      radio = await connectTo(t);
      expect(radio.onPublicChannel, isTrue);
      await expectLater(
          radio.setRemoteLora(baseNum, preset: MeshtasticPresets.longFast),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('public channel'))));
      expect(t.adminPacketsTo(baseNum), isEmpty);
    });

    test('get → begin → set → commit, each to the base with the passkey',
        () async {
      final t = fakeMobile()..onPacket = baseAnswers();
      radio = await connectTo(t);
      final steps = <String>[];
      await radio.setRemoteLora(baseNum,
          preset: MeshtasticPresets.fromId('MEDIUM_SLOW'), onStep: steps.add);

      final sent = t.adminPacketsTo(baseNum);
      final msgs = sent.map(adminOf).toList();
      expect(msgs.map((m) => m.whichPayloadVariant()), [
        pb.AdminMessage_PayloadVariant.getConfigRequest,
        pb.AdminMessage_PayloadVariant.beginEditSettings,
        pb.AdminMessage_PayloadVariant.setConfig,
        pb.AdminMessage_PayloadVariant.commitEditSettings,
      ]);
      for (final p in sent) {
        expect(p.to, baseNum);
        expect(p.wantAck, isTrue);
        expect(p.pkiEncrypted, isTrue, reason: 'never channel-encoded');
      }
      expect(msgs[0].getConfigRequest, pb.AdminMessage_ConfigType.LORA_CONFIG);
      expect(sent[0].decoded.wantResponse, isTrue);
      expect(msgs[0].sessionPasskey, isEmpty, reason: 'requests need none');
      for (final m in msgs.skip(1)) {
        expect(m.sessionPasskey, passkey, reason: 'echoed on every set');
      }
      final lora = msgs[2].setConfig.lora;
      expect(lora.modemPreset, pb.Config_LoRaConfig_ModemPreset.MEDIUM_SLOW);
      expect(lora.usePreset, isTrue);
      expect(lora.txPower, 27, reason: 'everything else as read from the base');
      expect(lora.region, pb.Config_LoRaConfig_RegionCode.US);
      expect(lora.sx126xRxBoostedGain, isTrue);
      expect(steps.first, 'Asking MeshTest Base for its settings…');
      expect(steps, contains('MeshTest Base: switching to Medium Slow…'));
      expect(steps.last, 'Done');
      // Nothing was sent to our own radio (the base's key was known).
      expect(t.localAdmin, isEmpty);
    });

    test('tx power alone keeps the preset; 0 (firmware max) passes through',
        () async {
      final t = fakeMobile()..onPacket = baseAnswers();
      radio = await connectTo(t);
      final steps = <String>[];
      await radio.setRemoteLora(baseNum, txPowerDbm: 0, onStep: steps.add);
      final lora = t
          .adminPacketsTo(baseNum)
          .map(adminOf)
          .firstWhere((m) => m.hasSetConfig())
          .setConfig
          .lora;
      expect(lora.txPower, 0);
      expect(lora.modemPreset, pb.Config_LoRaConfig_ModemPreset.LONG_FAST);
      expect(steps, contains('MeshTest Base: full power…'));
    });

    test('nothing to change, a non-Meshtastic preset or ourselves: refused',
        () async {
      final t = fakeMobile();
      radio = await connectTo(t);
      await expectLater(radio.setRemoteLora(baseNum), throwsArgumentError);
      await expectLater(
          radio.setRemoteLora(baseNum,
              preset: const RadioPreset(
                  id: 'MC_SF7_BW62.5_CR5',
                  displayName: 'x',
                  sf: 7,
                  bwKHz: 62.5,
                  cr: 5)),
          throwsArgumentError);
      await expectLater(radio.setRemoteLora(mobileNum, txPowerDbm: 20),
          throwsArgumentError);
      expect(t.adminPacketsTo(baseNum), isEmpty);
    });

    test('a NAK from the base is a StateError naming the reason, and stops',
        () async {
      final t = fakeMobile()
        ..onPacket = baseAnswers(nak: (m) => m.hasGetConfigRequest());
      radio = await connectTo(t);
      await expectLater(
          radio.setRemoteLora(baseNum, preset: MeshtasticPresets.longFast),
          throwsA(isA<RemoteAdminNak>()
              .having((e) => e.errorName, 'errorName',
                  'ADMIN_PUBLIC_KEY_UNAUTHORIZED')
              .having((e) => e.message, 'message',
                  contains('not an admin key'))));
      expect(t.adminPacketsTo(baseNum), hasLength(1));
    });

    test('a bad session key NAK on a set is not retried', () async {
      final t = fakeMobile()
        ..onPacket = baseAnswers(
            nak: (m) => m.hasSetConfig(),
            error: pb.Routing_Error.ADMIN_BAD_SESSION_KEY);
      radio = await connectTo(t);
      await expectLater(
          radio.setRemoteLora(baseNum, preset: MeshtasticPresets.longFast),
          throwsA(isA<RemoteAdminNak>()
              .having((e) => e.errorName, 'errorName', 'ADMIN_BAD_SESSION_KEY')));
      expect(t.adminPacketsTo(baseNum), hasLength(3), reason: 'get, begin, set');
    });

    test('a local PKI NAK gives our radio the saved key and retries once',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final contacts = MeshtasticContacts(prefs);
      await contacts.save(
          baseNum, pb.User(longName: 'MeshTest Base', publicKey: baseKey));

      var gets = 0;
      final t = fakeMobile(baseKeyKnown: false);
      t.onPacket = (p) {
        if (p.to != baseNum) return null;
        final admin = adminOf(p);
        if (admin.hasGetConfigRequest() && ++gets == 1) {
          // Our own radio refuses: it has no key for the base.
          return [
            routingFrame(p,
                from: mobileNum,
                error: pb.Routing_Error.PKI_SEND_FAIL_PUBLIC_KEY)
          ];
        }
        return baseAnswers()(p);
      };
      radio = await connectTo(t);
      radio.contacts = contacts;
      final steps = <String>[];
      await radio.setRemoteLora(baseNum,
          preset: MeshtasticPresets.longFast, onStep: steps.add);

      expect(gets, 2);
      // add_contact before the first try (node list had no key) and again,
      // forced, after the local NAK.
      final adds = t.localAdmin.where((m) => m.hasAddContact()).toList();
      expect(adds, hasLength(2));
      expect(adds.first.addContact.nodeNum, baseNum);
      expect(adds.first.addContact.user.publicKey, baseKey);
      expect(steps, contains(startsWith('A key is missing on one side')));
      expect(steps.last, 'Done');
    });

    test('a second key NAK gives up', () async {
      final t = fakeMobile()
        ..onPacket = baseAnswers(
            nak: (m) => m.hasGetConfigRequest(),
            error: pb.Routing_Error.PKI_UNKNOWN_PUBKEY);
      radio = await connectTo(t);
      await expectLater(
          radio.setRemoteLora(baseNum, preset: MeshtasticPresets.longFast),
          throwsA(isA<RemoteAdminNak>()
              .having((e) => e.errorName, 'errorName', 'PKI_UNKNOWN_PUBKEY')
              .having((e) => e.isKeyProblem, 'isKeyProblem', isTrue)));
      expect(t.adminPacketsTo(baseNum).where((p) => adminOf(p).hasGetConfigRequest()),
          hasLength(2), reason: 'one retry');
    });

    test('a lost commit ACK counts as sent (the base reboots)', () async {
      final t = fakeMobile()
        ..onPacket = baseAnswers(silent: (m) => m.hasCommitEditSettings());
      radio = await connectTo(t);
      final steps = <String>[];
      await radio.setRemoteLora(baseNum,
          preset: MeshtasticPresets.longFast, onStep: steps.add);
      expect(steps, contains(contains('did not confirm the save')));
      expect(steps.last, 'Done');
    });

    test('silence on anything before the commit is a timeout', () async {
      final t = fakeMobile()
        ..onPacket = baseAnswers(silent: (m) => m.hasBeginEditSettings());
      radio = await connectTo(t);
      await expectLater(
          radio.setRemoteLora(baseNum, preset: MeshtasticPresets.longFast),
          throwsA(isA<TimeoutException>()));
      expect(t.adminPacketsTo(baseNum), hasLength(2), reason: 'get, begin');
    });

    test('a relay\'s implicit ACK is not the base\'s; the base\'s is awaited',
        () async {
      final t = fakeMobile()
        ..onPacket = baseAnswers(ackFrom: const [relayNum, baseNum]);
      radio = await connectTo(t);
      await radio.setRemoteLora(baseNum, preset: MeshtasticPresets.longFast);
      expect(t.adminPacketsTo(baseNum), hasLength(4));

      // Only the relay answers: that is silence.
      final t2 = fakeMobile()
        ..onPacket = baseAnswers(ackFrom: const [relayNum]);
      final radio2 = await connectTo(t2);
      try {
        await expectLater(
            radio2.setRemoteLora(baseNum, preset: MeshtasticPresets.longFast),
            throwsA(isA<TimeoutException>()));
      } finally {
        await radio2.dispose();
      }
    });

    test('the base\'s replies also reach the packet stream and adminStream',
        () async {
      final t = fakeMobile()..onPacket = baseAnswers();
      radio = await connectTo(t);
      final admin = <AdminReply>[];
      final sub = radio.adminStream.listen(admin.add);
      await radio.setRemoteLora(baseNum, preset: MeshtasticPresets.longFast);
      await sub.cancel();
      expect(admin.single.from, baseNum);
      expect(admin.single.message.getConfigResponse.hasLora(), isTrue);
    });
  });
}
