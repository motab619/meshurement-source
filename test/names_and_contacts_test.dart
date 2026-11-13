// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_contacts.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/csv_export_service.dart';
import 'package:mesh_analyzer/services/rig_math.dart';
import 'package:mesh_analyzer/ui/screens/rig_profiles_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_mesh_radio.dart';

void main() {
  group('csvFileName', () {
    final t = DateTime(2026, 10, 15, 22, 4);

    test('map, session, start time and preset', () {
      expect(
        csvFileName(
            mapName: 'Polo Fields',
            sessionName: 'Walk to the store!',
            startedAt: t,
            preset: 'MEDIUM_FAST'),
        'Polo-Fields_Walk-to-the-store_2026-10-15_2204_MediumFast',
      );
    });

    test('skips empty parts and caps long ones', () {
      expect(
        csvFileName(
            mapName: 'A' * 50, sessionName: '', startedAt: t, preset: ''),
        '${'A' * 30}_2026-10-15_2204',
      );
    });
  });

  test('radioModelName', () {
    expect(radioModelName('TRACKER_T1000_E'), 'Seeed T1000-E');
    expect(radioModelName('HELTEC_V3'), 'Heltec V3');
    expect(radioModelName('SOME_NEW_BOARD'), 'Some New Board');
    expect(radioModelName('UNSET'), '');
    expect(radioModelName(''), '');
  });

  test('saved contacts keep only users with a key', () async {
    SharedPreferences.setMockInitialValues({});
    final contacts = MeshtasticContacts(await SharedPreferences.getInstance());
    await contacts.save(1, pb.User(longName: 'no key'));
    expect(contacts.get(1), isNull);
    final base = pb.User(longName: 'Base', publicKey: List.filled(32, 7));
    await contacts.save(2, base);
    expect(contacts.get(2), base);
  });

  test('a saved key is only replaced from the radio itself', () async {
    SharedPreferences.setMockInitialValues({});
    final contacts = MeshtasticContacts(await SharedPreferences.getInstance());
    final base = pb.User(longName: 'Base', publicKey: List.filled(32, 7));
    await contacts.save(2, base);
    // Heard over the air with another key: kept the saved one.
    final other = pb.User(longName: 'Base?', publicKey: List.filled(32, 9));
    expect(await contacts.save(2, other), isFalse);
    expect(contacts.get(2), base);
    // Same key, new name: fine.
    final renamed = pb.User(longName: 'Base 2', publicKey: List.filled(32, 7));
    expect(await contacts.save(2, renamed), isTrue);
    expect(contacts.get(2), renamed);
    // Straight from that radio over Bluetooth (a reset radio): replaced.
    expect(await contacts.save(2, other, replaceKey: true), isTrue);
    expect(contacts.get(2), other);
  });

  test('mapBaseNodeNums lists every map base', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final a = await db.upsertNode(nodeId: 0xa);
    final b = await db.upsertNode(nodeId: 0xb);
    await db.upsertNode(nodeId: 0xc);
    await db.createCoverageMap(name: '1', baseNodeId: a);
    await db.createCoverageMap(name: '2', baseNodeId: b);
    await db.createCoverageMap(name: '3', baseNodeId: b);
    expect(await db.mapBaseNodeNums(), {0xa, 0xb});
  });

  testWidgets('new rig is filled with the radio\'s reported model',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final radio = FakeMeshRadio(myNodeId: 10);
    radio.nodes[10] = const RadioNode(num: 10, hwModel: 'TRACKER_T1000_E');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(radio),
      ],
      child: const MaterialApp(home: RigEditScreen(role: rigRoleMobile)),
    ));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(TextField),
            matching: find.text('Seeed T1000-E')),
        findsOneWidget);
    expect(find.textContaining('Reported by the connected node'),
        findsOneWidget);
  });
}
