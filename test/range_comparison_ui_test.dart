// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/ui/protocol_text.dart';
import 'package:mesh_analyzer/ui/screens/rig_comparison_screen.dart';
import 'package:mesh_analyzer/ui/widgets/range_polar_plot.dart';
import 'package:mesh_analyzer/utils/constants.dart';

const _baseLat = 33.68, _baseLon = -116.24;
const _degPerM = 1 / 111320;

class _Env {
  final AppDatabase db;
  final CoverageMap map;
  final List<int> ids;
  final SharedPreferences prefs;

  _Env(this.db, this.map, this.ids, this.prefs);
}

/// Two sessions: A walks [aDir] (+1 east / -1 west) and B walks [bDir];
/// with opposite directions the routes never overlap.
Future<_Env> _env(WidgetTester tester,
    {required int aDir,
    required int bDir,
    List<RadioSettings?> settings = const [null, null],
    List<(String, String)> presets = const [
      ('MEDIUM_FAST', 'meshtastic'),
      ('SHORT_FAST', 'meshtastic'),
    ]}) async {
  SharedPreferences.setMockInitialValues({});
  final env = await tester.runAsync(() async {
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final node = await db.upsertNode(nodeId: 1, longName: 'Base');
    final mapId = await db.createCoverageMap(name: 'Map', baseNodeId: node);
    await prefs.setString(
        AppConstants.prefTerrainBaseLocation(mapId), '$_baseLat,$_baseLon');
    final map =
        (await db.getAllCoverageMaps()).firstWhere((m) => m.id == mapId);
    final ids = <int>[];
    var t = DateTime(2026, 10, 1, 12);
    for (final (dir, (preset, protocol), rs) in [
      (aDir, presets[0], settings[0]),
      (bDir, presets[1], settings[1]),
    ]) {
      final sid = await db.createSession(
          coverageMapId: mapId,
          loraPreset: preset,
          protocol: protocol,
          packetAirtimeMs: 300,
          radioSettings: rs);
      ids.add(sid);
      // Pings every 100 m from 200 to 1400 m; answered out to 700 m.
      for (var m = 200; m <= 1400; m += 100) {
        final lon = _baseLon + dir * m * _degPerM * 1.2;
        t = t.add(const Duration(seconds: 30));
        final tx = await db.insertPacketEvent(PacketEventsCompanion.insert(
          sessionId: sid,
          timestamp: t,
          direction: PacketDirection.tx,
          sourceNodeId: node,
          packetType: PacketType.ping,
          rxLat: const Value(_baseLat),
          rxLon: Value(lon),
        ));
        final ok = m <= 700;
        int? ack;
        if (ok) {
          ack = await db.insertPacketEvent(PacketEventsCompanion.insert(
            sessionId: sid,
            timestamp: t.add(const Duration(seconds: 2)),
            direction: PacketDirection.ack,
            sourceNodeId: node,
            packetType: PacketType.ack,
            rxSnr: const Value(3.5),
            rxRssi: const Value(-100),
            rxLat: const Value(_baseLat),
            rxLon: Value(lon),
          ));
        }
        await db.insertPingCorrelation(PingCorrelationsCompanion.insert(
          txEventId: tx,
          ackEventId: Value(ack),
          roundTripMs: Value(ok ? 2000 : null),
          ackStatus: Value(ok ? AckStatus.received : AckStatus.timeout),
        ));
      }
    }
    return _Env(db, map, ids, prefs);
  });
  addTearDown(() => tester.runAsync(env!.db.close));
  return env!;
}

Future<void> _open(WidgetTester tester, _Env env) async {
  // flutter_map's tile cache asks path_provider for a directory.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path);
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null));
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(env.db),
      sharedPreferencesProvider.overrideWithValue(env.prefs),
    ],
    child: MaterialApp(
      home: RigComparisonScreen(
        map: env.map,
        sessionIdsA: [env.ids[0]],
        sessionIdsB: [env.ids[1]],
      ),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  for (final overlap in [false, true]) {
    testWidgets(
        overlap
            ? 'distance section renders when the routes overlap'
            : 'distance section replaces the no-overlap message',
        (tester) async {
      final env = await _env(tester, aDir: 1, bDir: overlap ? 1 : -1);
      await _open(tester, env);
      expect(find.textContaining('no overlapping route'), findsNothing);
      final list = find.byType(Scrollable).last;
      Future<void> see(Finder f) =>
          tester.scrollUntilVisible(f, 300, scrollable: list);
      await see(find.text('Ping success by distance from base'));
      expect(find.text('By distance from base'), findsOneWidget);
      await see(find.text('Side by side'));
      expect(find.text('Medium Fast'), findsWidgets);
      expect(find.text('Short Fast'), findsWidgets);
      expect(find.text('Pings ACKed'), findsOneWidget);
      await see(find.text('What the numbers say'));
      expect(find.byType(RangePolarPlot), findsNWidgets(2));
      expect(
          find.textContaining('Base position placed by you'), findsOneWidget);
      // No coordinates anywhere in the footnote.
      expect(find.textContaining('33.68'), findsNothing);
      if (!overlap) {
        expect(find.textContaining('rerun both on the same route'),
            findsOneWidget);
      }
      await _dispose(tester);
    });
  }

  testWidgets('side by side lists radio settings; different power is noted',
      (tester) async {
    final env = await _env(tester, aDir: 1, bDir: 1, settings: const [
      RadioSettings(
          region: 'US',
          frequencySlot: 45,
          frequencyMHz: 913.125,
          txPowerDbm: 27,
          hopLimit: 3),
      RadioSettings(
          region: 'US',
          frequencySlot: 45,
          frequencyMHz: 913.125,
          txPowerDbm: 22,
          hopLimit: 3),
    ]);
    await _open(tester, env);
    final list = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(find.text('Hop limit'), 300,
        scrollable: list);
    expect(find.text('Frequency'), findsOneWidget);
    expect(find.text('Slot 45 · 913.125 MHz'), findsNWidgets(2));
    expect(find.text('Transmit power'), findsOneWidget);
    expect(find.text('27 dBm'), findsOneWidget);
    expect(find.text('22 dBm'), findsOneWidget);
    final note = find.textContaining(
        'Sides ran at different transmit power (27 vs 22 dBm): antenna '
        'differences are confounded');
    await tester.scrollUntilVisible(note, 300, scrollable: list);
    expect(note, findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('sessions without radio settings show no settings rows',
      (tester) async {
    final env = await _env(tester, aDir: 1, bDir: 1);
    await _open(tester, env);
    final list = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(find.text('Channel utilisation'), 300,
        scrollable: list);
    expect(find.text('Transmit power'), findsNothing);
    expect(find.text('Hop limit'), findsNothing);
    expect(find.textContaining('Sides ran at different'), findsNothing);
    await _dispose(tester);
  });

  testWidgets('sides on different bandwidths get a note', (tester) async {
    final env = await _env(tester, aDir: 1, bDir: 1, presets: const [
      ('MC_USA', 'meshcore'),
      ('MC_AUSTRALIA', 'meshcore'),
    ]);
    await _open(tester, env);
    final list = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('comparability-note')), 300,
        scrollable: list);
    final note = tester
        .widget<Text>(find.byKey(const ValueKey('comparability-note')))
        .data!;
    expect(note, contains('62.5 kHz vs 250 kHz'));
    expect(note, contains('link margin'));
    await _dispose(tester);
  });

  test('protocol and bandwidth differences are named', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final mapId = await db.createCoverageMap(name: 'Map');
    Future<Session> make(String preset, String protocol) async =>
        (await db.getSessionById(await db.createSession(
            coverageMapId: mapId, loraPreset: preset, protocol: protocol)))!;
    final lf = await make('LONG_FAST', 'meshtastic');
    final lf2 = await make('LONG_FAST', 'meshtastic');
    final usa = await make('MC_USA', 'meshcore');
    final custom = await make('CUSTOM', 'meshcore');
    expect(comparabilityNote([lf], [lf2]), isNull);
    expect(
        comparabilityNote([lf], [usa]),
        allOf(contains('Meshtastic vs MeshCore'),
            contains('250 kHz vs 62.5 kHz')));
    // Unknown bandwidth (custom): only the protocol is named.
    final note = comparabilityNote([lf], [custom])!;
    expect(note, contains('Meshtastic vs MeshCore'));
    expect(note, isNot(contains('kHz')));
  });

  testWidgets('like-for-like sides get no comparability note', (tester) async {
    final env = await _env(tester, aDir: 1, bDir: 1);
    await _open(tester, env);
    final list = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(find.text('By distance from base'), 300,
        scrollable: list);
    expect(find.byKey(const ValueKey('comparability-note')), findsNothing);
    await _dispose(tester);
  });
}
