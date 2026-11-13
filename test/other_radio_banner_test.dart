// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/ui/widgets/other_radio_banner.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_location_backend.dart';
import 'fakes/fake_mesh_radio.dart';

/// The live-map banner for a radio other than the base, driven by a real
/// session (SessionManager → PacketProcessor → OtherRadioMonitor) on a
/// fake radio.
void main() {
  const stranger = 0x0a1b2c3d;
  late AppDatabase db;
  late FakeMeshRadio radio;
  late ProviderContainer container;
  late int mapId;

  Future<void> setUpWorld(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      radio = FakeMeshRadio(currentPreset: MeshtasticPresets.longFast);
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(radio),
        gpsServiceProvider
            .overrideWithValue(GpsService(backend: FakeLocationBackend())),
      ]);
      final base = await db.upsertNode(nodeId: 2);
      mapId = await db.createCoverageMap(name: 'Polo', baseNodeId: base);
      container.read(packetProcessorProvider).start();
    });
  }

  Future<void> tearDownWorld(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await container.read(sessionManagerProvider).endSession();
      container.dispose();
      await db.close();
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  Widget app() => UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            // As on the map: in the left column, narrower than the screen.
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 300, child: OtherRadioBanner()),
            ),
          ),
        ),
      );

  testWidgets("a stranger's packet mid-session shows the banner; "
      'dismiss hides it', (tester) async {
    await setUpWorld(tester);
    await tester.pumpWidget(app());
    await settle(tester);
    expect(find.byKey(const ValueKey('other-radio-banner')), findsNothing);

    // Before the session starts the same packet is nobody's business.
    radio.nodes[stranger] = const RadioNode(
        num: stranger, longName: 'Spare Base', hwModel: 'HELTEC_V3');
    radio.pushPacket(ReceivedPacket(
        from: stranger, type: PacketType.telemetry, snr: 2, rssi: -100));
    await settle(tester);
    expect(find.byKey(const ValueKey('other-radio-banner')), findsNothing);

    await tester.runAsync(() => container
        .read(sessionManagerProvider)
        .startSession(coverageMapId: mapId, baseMeshNodeId: 2));
    await settle(tester);
    expect(find.byKey(const ValueKey('other-radio-banner')), findsNothing);

    radio.pushPacket(ReceivedPacket(
        from: stranger, type: PacketType.telemetry, snr: 2, rssi: -100));
    await settle(tester);
    expect(find.byKey(const ValueKey('other-radio-banner')), findsOneWidget);
    expect(
        find.text('Another node is on the test channel: Spare Base (Heltec '
            'V3 · !2c3d). If it is a second base left on, turn it off; relayed answers do not '
            'count.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('other-radio-dismiss')));
    await settle(tester);
    expect(find.byKey(const ValueKey('other-radio-banner')), findsNothing);

    // Once per node per session: more of the same stays quiet.
    radio.pushPacket(ReceivedPacket(
        from: stranger, type: PacketType.telemetry, snr: 2, rssi: -100));
    await settle(tester);
    expect(find.byKey(const ValueKey('other-radio-banner')), findsNothing);
    await tearDownWorld(tester);
  });

  testWidgets('an answer from a node that is not the base says so',
      (tester) async {
    await setUpWorld(tester);
    await tester.runAsync(() => container
        .read(sessionManagerProvider)
        .startSession(coverageMapId: mapId, baseMeshNodeId: 2));
    await tester.pumpWidget(app());
    await settle(tester);

    radio.pushPacket(ReceivedPacket(
        from: stranger, type: PacketType.ack, hops: 1, snr: 1, rssi: -110));
    await settle(tester);
    expect(
        find.text('Another node is answering: !0a1b2c3d. If it is a second '
            'base left on, turn it off; relayed answers do not count.'),
        findsOneWidget);

    // Ending the session takes the banner down.
    await tester.runAsync(
        () => container.read(sessionManagerProvider).endSession());
    await settle(tester);
    expect(find.byKey(const ValueKey('other-radio-banner')), findsNothing);
    await tearDownWorld(tester);
  });
}
