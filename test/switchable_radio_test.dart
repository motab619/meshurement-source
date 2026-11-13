// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/ble/radio_services.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/data/radio/switchable_radio.dart';
import 'package:mesh_analyzer/providers.dart';

import 'fakes/fake_mesh_radio.dart';

void main() {
  group('SwitchableRadio', () {
    late List<FakeMeshRadio> made;
    late SwitchableRadio radio;

    FakeMeshRadio make(RadioProtocol p) {
      final r = FakeMeshRadio(
        protocol: p,
        myNodeId: p == RadioProtocol.meshtastic ? 1 : 2,
        state: RadioConnectionState.disconnected,
      );
      made.add(r);
      return r;
    }

    setUp(() {
      made = [];
      radio = SwitchableRadio(factory: make);
    });

    tearDown(() => radio.dispose());

    const meshCoreRadio = RadioDescriptor(
        id: 'mc-1', name: 'MeshCore-1', protocol: RadioProtocol.meshcore);
    const meshtasticRadio = RadioDescriptor(id: 'mt-1', name: 'T1000-E');

    test('starts with a Meshtastic radio and delegates to it', () async {
      final inner = made.single;
      expect(radio.protocol, RadioProtocol.meshtastic);
      expect(radio.inner, same(inner));
      expect(radio.myNodeId, 1);
      inner
        ..displayName = 'inner'
        ..regionName = 'EU_868'
        ..onPublicChannel = true;
      expect(radio.displayName, 'inner');
      expect(radio.regionName, 'EU_868');
      expect(radio.onPublicChannel, isTrue);

      await radio.connect(meshtasticRadio);
      expect(inner.descriptor, meshtasticRadio);
      expect(radio.descriptor, meshtasticRadio);
      expect(radio.isReady, isTrue);

      final outcome = await radio.ping(7);
      expect(inner.pingTargets, [7]);
      expect(outcome.status, PingStatus.timeout);
      await radio.prepareToPing(7);
      expect(inner.preparedTargets, [7]);

      await radio.setBeacon(const BeaconConfig.off());
      expect(inner.beacons, hasLength(1));
      await radio.applyTestProfile(TestProfile(
        channelName: 'MeshTest',
        channelKey: Uint8List(32),
        preset: const RadioPreset(
            id: 'x', displayName: 'X', sf: 9, bwKHz: 250, cr: 5),
        isBase: false,
      ));
      expect(inner.appliedProfiles, hasLength(1));
      expect(made, hasLength(1), reason: 'same protocol: no switch');
    });

    test('streams survive a protocol switch', () async {
      final packets = <int>[];
      final nodes = <int>[];
      final states = <RadioConnectionState>[];
      final airtime = <double>[];
      final stats = <double>[];
      radio.packets.listen((p) => packets.add(p.from));
      radio.nodeUpdates.listen((n) => nodes.add(n.num));
      radio.connectionState.listen(states.add);
      radio.txAirtimeStream.listen(airtime.add);
      radio.channelStats.listen((s) => stats.add(s.airUtilTxPercent));
      await pumpEventQueue();

      final first = made.single;
      first.pushPacket(ReceivedPacket(from: 10, type: 'text'));

      await radio.connect(meshCoreRadio);
      final second = made.last;
      expect(made, hasLength(2));
      expect(radio.inner, same(second));
      expect(radio.protocol, RadioProtocol.meshcore);
      expect(first.disposed, isTrue);
      expect(second.descriptor, meshCoreRadio);

      second.pushPacket(ReceivedPacket(from: 20, type: 'text'));
      second.pushNode(const RadioNode(num: 21));
      second.pushTxAirtime(12.5);
      second.pushChannelStats(RadioChannelStats(
          airUtilTxPercent: 3,
          channelUtilizationPercent: 9,
          measuredAt: DateTime(2026)));
      await pumpEventQueue();

      expect(packets, [10, 20]);
      expect(nodes, [21]);
      expect(airtime, [12.5]);
      expect(stats, [3]);
      // Disconnected (start), ready on the new radio; the switch between
      // two disconnected radios adds nothing.
      expect(states,
          [RadioConnectionState.disconnected, RadioConnectionState.ready]);
      expect(radio.myNodeId, 2);
    });

    test('connect disconnects the old radio before switching', () async {
      await radio.connect(meshtasticRadio);
      final first = made.single;
      expect(first.isReady, isTrue);
      await radio.connect(meshCoreRadio);
      expect(first.state, RadioConnectionState.disconnected);
      expect(first.disposed, isTrue);
      expect(radio.isReady, isTrue);
    });

    test('switchTo refuses while connected', () async {
      await radio.connect(meshtasticRadio);
      expect(() => radio.switchTo(RadioProtocol.meshcore),
          throwsA(isA<StateError>()));
      expect(made, hasLength(1));
      await radio.disconnect();
      await radio.switchTo(RadioProtocol.meshcore);
      expect(radio.protocol, RadioProtocol.meshcore);
    });

    test('refuses to switch while a session records on another protocol',
        () async {
      String? recording = RadioProtocol.meshtastic.name;
      radio.switchBlockedReason = (to) =>
          recording == null || recording == to.name ? null : 'recording';

      expect(radio.whyCantSwitchTo(RadioProtocol.meshcore), 'recording');
      expect(radio.whyCantSwitchTo(RadioProtocol.meshtastic), isNull);
      await expectLater(
          radio.connect(meshCoreRadio), throwsA(isA<StateError>()));
      await expectLater(
          radio.switchTo(RadioProtocol.meshcore), throwsA(isA<StateError>()));
      expect(made, hasLength(1));
      expect(radio.protocol, RadioProtocol.meshtastic);

      // A session resumed after relaunch on MeshCore: switching to it is
      // allowed.
      recording = RadioProtocol.meshcore.name;
      await radio.connect(meshCoreRadio);
      expect(radio.protocol, RadioProtocol.meshcore);

      recording = null;
      await radio.connect(meshtasticRadio);
      expect(radio.protocol, RadioProtocol.meshtastic);
    });

    test('innerChanged reports each new radio', () async {
      final changes = <MeshRadio>[];
      radio.innerChanged.listen(changes.add);
      await radio.switchTo(RadioProtocol.meshcore);
      await pumpEventQueue();
      expect(changes, [same(made.last)]);
    });

    test('radioAs looks through the wrapper', () async {
      expect(radioAs<FakeMeshRadio>(radio), same(made.single));
      expect(radioAs<SwitchableRadio>(radio), same(radio));
      expect(radioAs<MeshtasticRadio>(radio), isNull);
      final plain = FakeMeshRadio();
      expect(radioAs<FakeMeshRadio>(plain), same(plain));
      expect(radioAs<MeshtasticRadio>(plain), isNull);
      expect(radioAs<FakeMeshRadio>(null), isNull);
      await plain.dispose();
    });
  });

  group('providers', () {
    test('factory builds a MeshCoreRadio for MeshCore', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final factory = container.read(radioFactoryProvider);
      final mc = factory(RadioProtocol.meshcore);
      expect(mc, isA<MeshCoreRadio>());
      expect(mc.protocol, RadioProtocol.meshcore);
      expect(mc.state, RadioConnectionState.disconnected);
      await mc.dispose();
      final mt = factory(RadioProtocol.meshtastic);
      expect(mt, isA<MeshtasticRadio>());
      await mt.dispose();
    });

    test('the phone radio is switchable and starts as Meshtastic', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final radio = container.read(meshRadioProvider);
      expect(radio, isA<SwitchableRadio>());
      expect(radioAs<MeshtasticRadio>(radio), isNotNull);
      expect(radio.protocol, RadioProtocol.meshtastic);
    });
  });

  group('scan tagging', () {
    test('tags radios by advertised service', () {
      expect(RadioServices.protocolFor([RadioServices.meshtastic]),
          RadioProtocol.meshtastic);
      expect(
          RadioServices.protocolFor(['6E400001-B5A3-F393-E0A9-E50E24DCCA9E']),
          RadioProtocol.meshcore);
      expect(
          RadioServices.protocolFor(
              ['0000180a-0000-1000-8000-00805f9b34fb', RadioServices.meshCore]),
          RadioProtocol.meshcore);
      expect(RadioServices.protocolFor(const []), isNull);
      expect(RadioServices.all,
          containsAll([RadioServices.meshtastic, RadioServices.meshCore]));
      expect(MeshtasticRadio.serviceUuid, RadioServices.meshtastic);
      expect(MeshCoreRadio.serviceUuid, RadioServices.meshCore);
      expect(RadioServices.serviceFor(RadioProtocol.meshcore),
          RadioServices.meshCore);
    });
  });

  group('MeshCoreRadio before connecting', () {
    test('ping reports an error instead of throwing', () async {
      final r = MeshCoreRadio();
      final outcome = await r.ping(5);
      expect(outcome.status, PingStatus.error);
      expect(r.onPublicChannel, isTrue,
          reason: 'sessions must refuse until the node params are known');
      expect(
          (await r.setBeacon(const BeaconConfig.off())).kind, BeaconKind.none);
      await r.dispose();
    });
  });
}
