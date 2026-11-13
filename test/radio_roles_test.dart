// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_contacts.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/services/base_node.dart';
import 'package:mesh_analyzer/services/radio_profile_service.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_mesh_radio.dart';
import 'meshtastic/fake_meshtastic_transport.dart';

void main() {
  // DiagLog wants the services binding for its log file.
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupMismatchTests();
  _remoteAdminTests();
  _baseCheckAndRevokeTests();
  late SharedPreferences prefs;
  late RadioRoles roles;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    roles = RadioRoles(prefs);
  });

  test('clearNode forgets the role, device and recorded setup', () async {
    await roles.assign(RadioRole.base, nodeNum: 10, deviceId: 'A');
    await roles.assign(RadioRole.mobile, nodeNum: 20, deviceId: 'B');
    await roles.recordSetup(RadioRole.base,
        presetId: 'LONG_FAST', region: 'US');
    await roles.clearNode(10);
    expect(roles.roleOfNode(10), isNull);
    expect(roles.roleOfDevice('A'), isNull);
    expect(roles.presetOf(RadioRole.base), isNull);
    expect(roles.roleOfNode(20), RadioRole.mobile);
  });

  test('a radio holds one role; reassigning moves it', () async {
    await roles.assign(RadioRole.base, nodeNum: 10, deviceId: 'A');
    await roles.assign(RadioRole.mobile, nodeNum: 20, deviceId: 'B');
    expect(roles.roleOfNode(10), RadioRole.base);
    expect(roles.roleOfDevice('B'), RadioRole.mobile);
    expect(prefs.getInt(baseNodePrefKey), 10);

    // Swap: radio 20 becomes the base.
    await roles.assign(RadioRole.base, nodeNum: 20, deviceId: 'B');
    expect(roles.roleOfNode(20), RadioRole.base);
    expect(roles.nodeOf(RadioRole.mobile), isNull);
    expect(roles.deviceOf(RadioRole.mobile), isNull);
  });

  test('learn fills in the Bluetooth id from the node number', () async {
    await roles.assign(RadioRole.base, nodeNum: 10);
    final radio = FakeMeshRadio(myNodeId: 10);
    await radio.connect(const RadioDescriptor(id: 'X', name: 'r'));
    await roles.learn(radio);
    expect(roles.roleOfDevice('X'), RadioRole.base);
  });

  group('Radio Setup', () {
    final preset = MeshtasticPresets.testPresets.first;

    test('connected radio as base, then switch to and set up the mobile',
        () async {
      final phoneRadio = FakeMeshRadio(myNodeId: 10);
      await phoneRadio.connect(const RadioDescriptor(id: 'A', name: 'a'));
      final service = RadioProfileService(phoneRadio, prefs, null, null, roles);

      await service.applyToConnected(RadioRole.base,
          preset: preset, beaconSecs: 30, rename: true, onStep: (_) {});
      final baseProfile = phoneRadio.appliedProfiles.single;
      expect(baseProfile.isBase, isTrue);
      expect(baseProfile.beacon?.intervalSec, 30);
      expect(baseProfile.radioShortName, 'BASE');
      expect(roles.roleOfNode(10), RadioRole.base);
      expect(roles.roleOfDevice('A'), RadioRole.base);

      // The phone switches to the other radio (node 20 once connected).
      phoneRadio.myNodeId = 20;
      await service.switchToAndApplyMobile(
          const RadioDescriptor(id: 'B', name: 'b'),
          preset: preset,
          rename: true,
          onStep: (_) {});
      expect(phoneRadio.descriptor?.id, 'B');
      final mobileProfile = phoneRadio.appliedProfiles.last;
      expect(mobileProfile.isBase, isFalse);
      expect(mobileProfile.radioLongName, 'MeshTest Mobile');
      expect(mobileProfile.radioShortName, 'MOBL');
      expect(roles.roleOfNode(20), RadioRole.mobile);
      expect(roles.roleOfDevice('B'), RadioRole.mobile);
      expect(roles.roleOfNode(10), RadioRole.base);
    });

    test('names are left alone when renaming is off', () async {
      final phoneRadio = FakeMeshRadio(myNodeId: 10);
      await phoneRadio.connect(const RadioDescriptor(id: 'A', name: 'a'));
      final service = RadioProfileService(phoneRadio, prefs, null, null, roles);
      await service.applyToMobile(preset: preset, onStep: (_) {});
      expect(phoneRadio.appliedProfiles.single.radioLongName, isNull);
      expect(roles.roleOfNode(10), RadioRole.mobile);
    });
  });
}

void _remoteAdminTests() {
  final mobileKey = List<int>.generate(32, (i) => 0xA0 + i);
  final preset = MeshtasticPresets.testPresets.first;

  group('RadioRoles remote admin', () {
    late SharedPreferences prefs;
    late RadioRoles roles;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      roles = RadioRoles(prefs);
    });

    test('recorded, read back, cleared with the base', () async {
      expect(roles.remoteAdminMobileNode, isNull);
      await roles.assign(RadioRole.base, nodeNum: 10, deviceId: 'A');
      await roles.recordRemoteAdmin(20);
      expect(roles.remoteAdminMobileNode, 20);
      expect(prefs.getInt(RadioRoles.remoteAdminNodeKey), 20);
      // The mobile role landing on the same radio keeps it.
      await roles.assign(RadioRole.mobile, nodeNum: 20, deviceId: 'B');
      expect(roles.remoteAdminMobileNode, 20);
      await roles.clearNode(10);
      expect(roles.remoteAdminMobileNode, isNull);
      expect(prefs.containsKey(RadioRoles.remoteAdminNodeKey), isFalse);
    });

    test('a grant is for one mobile radio: another mobile needs its own',
        () async {
      await roles.assign(RadioRole.base, nodeNum: 10);
      await roles.assign(RadioRole.mobile, nodeNum: 20);
      await roles.recordRemoteAdmin(20);
      await roles.assign(RadioRole.mobile, nodeNum: 21);
      expect(roles.remoteAdminMobileNode, isNull);
      await roles.assign(RadioRole.mobile, nodeNum: 20);
      expect(roles.remoteAdminMobileNode, 20);
    });

    test('a different radio becoming the base holds no grant', () async {
      await roles.assign(RadioRole.base, nodeNum: 10);
      await roles.recordRemoteAdmin(20);
      await roles.assign(RadioRole.base, nodeNum: 10); // same base: kept
      expect(roles.remoteAdminMobileNode, 20);
      await roles.assign(RadioRole.base, nodeNum: 11);
      expect(roles.remoteAdminMobileNode, isNull);
    });

    test('clearRemoteAdmin and prefKeys', () async {
      await roles.recordRemoteAdmin(20);
      await roles.clearRemoteAdmin();
      expect(roles.remoteAdminMobileNode, isNull);
      expect(RadioRoles.prefKeys, contains(RadioRoles.remoteAdminNodeKey));
    });
  });

  group('Radio Setup grants remote changes', () {
    late SharedPreferences prefs;
    late RadioRoles roles;
    late FakeMeshRadio base;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      roles = RadioRoles(prefs);
      base = FakeMeshRadio(myNodeId: 10)..remoteAdmin = true;
    });

    RadioProfileService service(FakeMeshRadio phoneRadio) =>
        RadioProfileService(phoneRadio, prefs, null, (_) => base, roles);

    Future<void> saveKey(int node) => MeshtasticContacts(prefs)
        .save(node, pb.User(longName: 'Mobile', publicKey: mobileKey));

    test('mobile flow: the base over a second link gets the mobile\'s key',
        () async {
      final mobile = FakeMeshRadio(myNodeId: 20);
      await mobile.connect(const RadioDescriptor(id: 'B', name: 'b'));
      await saveKey(20);
      final steps = <String>[];
      await service(mobile).applyToBase(
          const RadioDescriptor(id: 'A', name: 'a'),
          preset: preset,
          beaconSecs: 30,
          onStep: steps.add);
      expect(base.grantedKeys, [mobileKey]);
      expect(base.appliedProfiles.single.isBase, isTrue);
      expect(base.disposed, isTrue);
      expect(roles.remoteAdminMobileNode, 20);
      expect(steps, contains(contains('Remote changes allowed')));
      // Step 2 makes that radio the mobile: the grant still matches.
      await service(mobile).applyToMobile(preset: preset, onStep: (_) {});
      expect(roles.remoteAdminMobileNode, 20);
    });

    test('the switch off: no grant, nothing remembered', () async {
      final mobile = FakeMeshRadio(myNodeId: 20);
      await mobile.connect(const RadioDescriptor(id: 'B', name: 'b'));
      await saveKey(20);
      await roles.recordRemoteAdmin(20); // from an earlier setup
      final steps = <String>[];
      await service(mobile).applyToBase(
          const RadioDescriptor(id: 'A', name: 'a'),
          preset: preset,
          beaconSecs: 30,
          onStep: steps.add,
          allowRemoteChanges: false);
      expect(base.grantedKeys, isEmpty);
      expect(roles.remoteAdminMobileNode, isNull);
      expect(steps, contains('Remote changes: not allowed'));
    });

    test('base flow: the connected base gets the remembered mobile\'s key',
        () async {
      final phoneRadio = FakeMeshRadio(myNodeId: 10)..remoteAdmin = true;
      await phoneRadio.connect(const RadioDescriptor(id: 'A', name: 'a'));
      await roles.assign(RadioRole.mobile, nodeNum: 20, deviceId: 'B');
      await saveKey(20);
      await service(phoneRadio).applyToConnected(RadioRole.base,
          preset: preset, beaconSecs: 30, onStep: (_) {});
      expect(phoneRadio.grantedKeys, [mobileKey]);
      expect(roles.remoteAdminMobileNode, 20);
    });

    test('base flow, brand-new pair: no key yet, nothing granted', () async {
      final phoneRadio = FakeMeshRadio(myNodeId: 10)..remoteAdmin = true;
      await phoneRadio.connect(const RadioDescriptor(id: 'A', name: 'a'));
      final steps = <String>[];
      await service(phoneRadio).applyToConnected(RadioRole.base,
          preset: preset, beaconSecs: 30, onStep: steps.add);
      expect(phoneRadio.grantedKeys, isEmpty);
      expect(roles.remoteAdminMobileNode, isNull);
      expect(steps, contains(contains('isn\'t known yet')));
    });

    test('the mobile role never grants; MeshCore never grants or throws',
        () async {
      final phoneRadio = FakeMeshRadio(myNodeId: 20)..remoteAdmin = true;
      await phoneRadio.connect(const RadioDescriptor(id: 'B', name: 'b'));
      await saveKey(20);
      await service(phoneRadio).applyToMobile(preset: preset, onStep: (_) {});
      expect(phoneRadio.grantedKeys, isEmpty);

      final mc = FakeMeshRadio(myNodeId: 20, protocol: RadioProtocol.meshcore);
      await mc.connect(const RadioDescriptor(
          id: 'B', name: 'b', protocol: RadioProtocol.meshcore));
      base = FakeMeshRadio(myNodeId: 10, protocol: RadioProtocol.meshcore);
      final steps = <String>[];
      await service(mc).applyToBase(
          const RadioDescriptor(
              id: 'A', name: 'a', protocol: RadioProtocol.meshcore),
          preset: preset,
          beaconSecs: 30,
          onStep: steps.add);
      expect(base.grantedKeys, isEmpty);
      expect(roles.remoteAdminMobileNode, isNull);
      expect(steps.where((s) => s.startsWith('Remote changes')), isEmpty);
      await service(mc).grantRemoteAdminAtBase(
          const RadioDescriptor(
              id: 'A', name: 'a', protocol: RadioProtocol.meshcore),
          onStep: steps.add);
      expect(steps.last, contains('MeshCore'));
    });

    test('grantRemoteAdminAtBase: connects, grants, remembers, disconnects',
        () async {
      final mobile = FakeMeshRadio(myNodeId: 20);
      await mobile.connect(const RadioDescriptor(id: 'B', name: 'b'));
      await saveKey(20);
      await roles.assign(RadioRole.base, nodeNum: 10);
      final steps = <String>[];
      await service(mobile).grantRemoteAdminAtBase(
          const RadioDescriptor(id: 'A', name: 'a'),
          onStep: steps.add);
      expect(base.grantedKeys, [mobileKey]);
      expect(base.appliedProfiles, isEmpty, reason: 'only the grant');
      expect(base.disposed, isTrue);
      expect(roles.remoteAdminMobileNode, 20);
      expect(roles.deviceOf(RadioRole.base), 'A', reason: 'learned');
      expect(steps.first, 'Connecting to the base node…');
      expect(steps.last, contains('Remote changes allowed'));
    });

    test('grantRemoteAdminAtBase needs the connected mobile and its key',
        () async {
      final mobile = FakeMeshRadio(
          myNodeId: 20, state: RadioConnectionState.disconnected);
      await expectLater(
          service(mobile).grantRemoteAdminAtBase(
              const RadioDescriptor(id: 'A', name: 'a'),
              onStep: (_) {}),
          throwsStateError);
      await mobile.connect(const RadioDescriptor(id: 'B', name: 'b'));
      await expectLater(
          service(mobile).grantRemoteAdminAtBase(
              const RadioDescriptor(id: 'A', name: 'a'),
              onStep: (_) {}),
          throwsStateError,
          reason: 'no key saved for the mobile');
      expect(base.grantedKeys, isEmpty);
    });
  });
}

void _setupMismatchTests() {
  group('setup mismatch', () {
    late SharedPreferences prefs;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('nothing recorded: no mismatch', () {
      expect(RadioRoles(prefs).setupMismatch(), isNull);
    });

    test('same preset and region: no mismatch', () async {
      final roles = RadioRoles(prefs);
      await roles.recordSetup(RadioRole.base,
          presetId: 'LONG_FAST', region: 'US');
      await roles.recordSetup(RadioRole.mobile,
          presetId: 'LONG_FAST', region: 'US');
      expect(roles.setupMismatch(), isNull);
    });

    test('MeshCore: a base recorded under a community id matches a mobile '
        'on the same modulation at the test frequency (field, 2026-10-29)',
        () async {
      final roles = RadioRoles(prefs);
      // Before the ladder, Radio Setup stored the community preset it
      // took the modulation from, and the base's old community title.
      await roles.recordSetup(RadioRole.base,
          presetId: 'MC_USA_SOUTHERN_CALIFORNIA',
          region: 'USA - Southern California',
          frequencyMHz: 918.0);
      await roles.recordSetup(RadioRole.mobile,
          presetId: 'MC_SF7_BW62.5_CR5', region: '', frequencyMHz: 918.0);
      expect(roles.setupMismatch(), isNull);
      // A different modulation or frequency still shows.
      await roles.recordSetup(RadioRole.mobile,
          presetId: 'MC_SF8_BW62.5_CR8', region: '', frequencyMHz: 918.0);
      expect(roles.setupMismatch(), contains('preset'));
      await roles.recordSetup(RadioRole.mobile,
          presetId: 'MC_SF7_BW62.5_CR5', region: '', frequencyMHz: 910.525);
      expect(roles.setupMismatch(), contains('frequency'));
    });

    test('different presets are flagged, preset first', () async {
      final roles = RadioRoles(prefs);
      await roles.recordSetup(RadioRole.base,
          presetId: 'LONG_FAST', region: 'US');
      await roles.recordSetup(RadioRole.mobile,
          presetId: 'MEDIUM_FAST', region: 'EU_868');
      expect(roles.setupMismatch(), contains('preset'));
    });

    test('different regions are flagged', () async {
      final roles = RadioRoles(prefs);
      await roles.recordSetup(RadioRole.base,
          presetId: 'LONG_FAST', region: 'US');
      await roles.recordSetup(RadioRole.mobile,
          presetId: 'LONG_FAST', region: 'EU_868');
      expect(roles.setupMismatch(), contains('region'));
    });

    test('different frequency slots are flagged after preset and region',
        () async {
      final roles = RadioRoles(prefs);
      await roles.recordSetup(RadioRole.base,
          presetId: 'LONG_FAST',
          region: 'US',
          frequencySlot: 20,
          txPowerDbm: 27);
      await roles.recordSetup(RadioRole.mobile,
          presetId: 'LONG_FAST',
          region: 'US',
          frequencySlot: 7,
          txPowerDbm: 22);
      expect(roles.slotOf(RadioRole.base), 20);
      expect(roles.txPowerOf(RadioRole.mobile), 22);
      expect(roles.setupMismatch(), 'frequency slot: base 20, mobile 7');
      // Power alone doesn't stop the radios hearing each other.
      await roles.recordSetup(RadioRole.mobile,
          presetId: 'LONG_FAST',
          region: 'US',
          frequencySlot: 20,
          txPowerDbm: 22);
      expect(roles.setupMismatch(), isNull);
      // An unknown slot forgets the old one.
      await roles.recordSetup(RadioRole.mobile,
          presetId: 'LONG_FAST', region: 'US');
      expect(roles.slotOf(RadioRole.mobile), isNull);
      expect(roles.setupMismatch(), isNull);
    });

    test('recorded setup survives in prefKeys (kept by Erase all)', () {
      expect(
          RadioRoles.prefKeys,
          containsAll([
            RadioRoles.basePresetKey,
            RadioRoles.mobilePresetKey,
            RadioRoles.baseRegionKey,
            RadioRoles.mobileRegionKey,
            RadioRoles.baseSlotKey,
            RadioRoles.mobileSlotKey,
            RadioRoles.baseTxPowerKey,
            RadioRoles.mobileTxPowerKey,
          ]));
    });
  });
}

/// Security audit 2026-11-04: a second Bluetooth link to "the base" must
/// reach the base (node number), and the grant can be taken back.
void _baseCheckAndRevokeTests() {
  final mobileKey = keyOf([0xA1]);
  final otherKey = keyOf([0x55]);
  final baseKey = keyOf([0xB1]);
  final basePrivate = keyOf([0xB2]);
  final preset = MeshtasticPresets.testPresets.first;

  group('second link to the base checks the node number', () {
    late SharedPreferences prefs;
    late RadioRoles roles;
    late FakeMeshRadio mobile;
    late FakeMeshRadio reached;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      roles = RadioRoles(prefs);
      await roles.assign(RadioRole.base, nodeNum: 10, deviceId: 'A');
      mobile = FakeMeshRadio(myNodeId: 20);
      await mobile.connect(const RadioDescriptor(id: 'B', name: 'b'));
      // The remembered Bluetooth id now answers as another node.
      reached = FakeMeshRadio(myNodeId: 11)..remoteAdmin = true;
    });

    RadioProfileService service() =>
        RadioProfileService(mobile, prefs, null, (_) => reached, roles);

    test('setBaseBeacon writes nothing to another radio', () async {
      await expectLater(
          service().setBaseBeacon(const BeaconConfig(intervalSec: 60)),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('not the base'))));
      expect(reached.beacons, isEmpty);
      expect(reached.disposed, isTrue);
    });

    test('applyToBase with expectNodeNum refuses another radio', () async {
      await expectLater(
          service().applyToBase(const RadioDescriptor(id: 'A', name: 'Base'),
              preset: preset,
              beaconSecs: 30,
              onStep: (_) {},
              expectNodeNum: 10),
          throwsStateError);
      expect(reached.appliedProfiles, isEmpty);
    });

    test('grantRemoteAdminAtBase refuses another radio', () async {
      await MeshtasticContacts(prefs)
          .save(20, pb.User(longName: 'Mobile', publicKey: mobileKey));
      await expectLater(
          service().grantRemoteAdminAtBase(
              const RadioDescriptor(id: 'A', name: 'Base'),
              onStep: (_) {}),
          throwsStateError);
      expect(reached.grantedKeys, isEmpty);
    });

    test('the right node passes', () async {
      reached.myNodeId = 10;
      await service().setBaseBeacon(const BeaconConfig(intervalSec: 60));
      expect(reached.beacons, hasLength(1));
    });
  });

  group('revokeRemoteAdminAtBase', () {
    late SharedPreferences prefs;
    late RadioRoles roles;
    late FakeMeshtasticTransport baseLink;
    late FakeMeshRadio mobile;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      roles = RadioRoles(prefs);
      await roles.assign(RadioRole.base, nodeNum: 10, deviceId: 'A');
      await roles.assign(RadioRole.mobile, nodeNum: 20, deviceId: 'B');
      await roles.recordRemoteAdmin(20);
      await MeshtasticContacts(prefs)
          .save(20, pb.User(longName: 'Mobile', publicKey: mobileKey));
      mobile = FakeMeshRadio(myNodeId: 20);
      await mobile.connect(const RadioDescriptor(id: 'B', name: 'b'));
      baseLink = FakeMeshtasticTransport(
        myNodeNum: 10,
        nodes: [
          pb.NodeInfo(num: 10, user: pb.User(longName: 'Base', publicKey: baseKey))
        ],
        security: pb.Config_SecurityConfig(
            publicKey: baseKey,
            privateKey: basePrivate,
            adminKey: [otherKey, mobileKey]),
      );
    });

    RadioProfileService service() => RadioProfileService(mobile, prefs, null,
        (_) => MeshtasticRadio(transport: baseLink), roles);

    test('takes only the mobile\'s key out and forgets the grant', () async {
      final steps = <String>[];
      await service().revokeRemoteAdminAtBase(onStep: steps.add);
      final security = baseLink.localAdmin
          .singleWhere((m) => m.hasSetConfig())
          .setConfig
          .security;
      expect(security.adminKey, [otherKey]);
      expect(security.privateKey, basePrivate);
      expect(roles.remoteAdminGrantedNode, isNull);
      expect(steps.last, contains('can no longer change'));
    });

    test('another radio at the base\'s Bluetooth id: nothing written',
        () async {
      await roles.assign(RadioRole.base, nodeNum: 12, deviceId: 'A');
      await roles.recordRemoteAdmin(20);
      await expectLater(service().revokeRemoteAdminAtBase(onStep: (_) {}),
          throwsStateError);
      expect(baseLink.localAdmin.where((m) => m.hasSetConfig()), isEmpty);
      expect(roles.remoteAdminGrantedNode, 20);
    });

    test('no grant recorded: nothing to do', () async {
      await roles.clearRemoteAdmin();
      final steps = <String>[];
      await service().revokeRemoteAdminAtBase(onStep: steps.add);
      expect(baseLink.written, isEmpty);
      expect(steps.single, contains('holds no key'));
    });
  });
}
