// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/services/base_node.dart';
import 'package:mesh_analyzer/services/radio_profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_mesh_radio.dart';

void main() {
  final now = DateTime(2026, 10, 15, 12);
  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));

  group('buildBaseNodeOptions', () {
    final radioNodes = [
      RadioNode(num: 1, longName: 'Me', lastHeard: ago(0)),
      RadioNode(num: 2, longName: 'Base', hopsAway: 0, lastHeard: ago(30)),
      RadioNode(num: 3, longName: 'Near', hopsAway: 0, lastHeard: ago(5)),
      RadioNode(num: 4, longName: 'Far', hopsAway: 3, lastHeard: ago(1)),
      RadioNode(num: 5, longName: 'Unknown hops', lastHeard: ago(2)),
    ];

    test('base first, then direct, then the rest; self left out', () {
      final opts = buildBaseNodeOptions(
        radioNodes: radioNodes,
        dbNodes: const [],
        myNum: 1,
        baseNum: 2,
        now: now,
      );
      expect([for (final o in opts) o.nodeNum], [2, 3, 4, 5]);
      expect([
        for (final o in opts) o.group
      ], [
        BaseNodeGroup.yourBase,
        BaseNodeGroup.direct,
        BaseNodeGroup.other,
        BaseNodeGroup.other,
      ]);
    });

    test('excluded radios (our mobile) are never offered; ids shown', () {
      final opts = buildBaseNodeOptions(
        radioNodes: radioNodes,
        dbNodes: const [],
        myNum: 1,
        baseNum: 2,
        excludeNums: const {3},
        now: now,
      );
      expect([for (final o in opts) o.nodeNum], [2, 4, 5]);
      expect(opts.first.detail, contains('!00000002'));
    });

    test('"direct" only when the hop count is known to be 0', () {
      final opts = buildBaseNodeOptions(
        radioNodes: radioNodes,
        dbNodes: const [],
        myNum: 1,
        baseNum: null,
        now: now,
      );
      String detail(int n) => opts.firstWhere((o) => o.nodeNum == n).detail;
      expect(detail(3), contains('direct'));
      expect(detail(4), contains('3 hops'));
      expect(detail(5), isNot(contains('direct')));
      expect(detail(5), isNot(contains('hops')));
    });
  });

  group('knownBaseNodeNum', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('prefers the Radio Setup base, else the newest map', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(await knownBaseNodeNum(prefs, db), isNull);

      final local = await db.upsertNode(nodeId: 0xbeef);
      await db.createCoverageMap(name: 'm', baseNodeId: local);
      expect(await knownBaseNodeNum(prefs, db), 0xbeef);

      await prefs.setInt(baseNodePrefKey, 0xcafe);
      expect(await knownBaseNodeNum(prefs, db), 0xcafe);
    });
  });

  test('Radio Setup remembers the base radio', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = RadioProfileService(
      FakeMeshRadio(),
      prefs,
      null,
      (_) => FakeMeshRadio(myNodeId: 0xba5e),
    );
    await service.applyToBase(
      const RadioDescriptor(id: 'b', name: 'Base'),
      preset: MeshtasticPresets.testPresets.first,
      beaconSecs: 15,
      onStep: (_) {},
    );
    expect(prefs.getInt(baseNodePrefKey), 0xba5e);
  });
}
