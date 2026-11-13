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
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/portnums.pbenum.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/telemetry.pb.dart' as pb;
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/ui/widgets/radio_stats_readout.dart';
import 'package:mesh_analyzer/ui/theme/app_theme.dart';

import 'fakes/fake_mesh_radio.dart';

pb.MeshPacket telemetryPacket(int from, pb.Telemetry t) => pb.MeshPacket(
      from: from,
      decoded: pb.Data(
        portnum: pb.PortNum.TELEMETRY_APP,
        payload: t.writeToBuffer(),
      ),
    );

String? readoutText(WidgetTester tester) {
  final f = find.descendant(
      of: find.byType(RadioStatsReadout), matching: find.byType(RichText));
  return f.evaluate().isEmpty
      ? null
      : tester.widget<RichText>(f.first).text.toPlainText();
}

void main() {
  const me = 100;
  final metrics = pb.Telemetry(
    deviceMetrics: pb.DeviceMetrics(airUtilTx: 1.25, channelUtilization: 8.5),
  );

  group('channelStatsFromTelemetry', () {
    test('own DeviceMetrics become stats', () {
      final at = DateTime(2026, 1, 1);
      final s = channelStatsFromTelemetry(telemetryPacket(me, metrics),
          myNodeNum: me, now: at)!;
      expect(s.airUtilTxPercent, closeTo(1.25, 1e-6));
      expect(s.channelUtilizationPercent, closeTo(8.5, 1e-6));
      expect(s.measuredAt, at);
    });

    test('own LocalStats become stats', () {
      final t = pb.Telemetry(
          localStats: pb.LocalStats(airUtilTx: 2, channelUtilization: 30));
      final s =
          channelStatsFromTelemetry(telemetryPacket(me, t), myNodeNum: me)!;
      expect(s.airUtilTxPercent, 2);
      expect(s.channelUtilizationPercent, 30);
    });

    test("other nodes' telemetry is ignored", () {
      expect(
          channelStatsFromTelemetry(telemetryPacket(7, metrics), myNodeNum: me),
          isNull);
      expect(
          channelStatsFromTelemetry(telemetryPacket(me, metrics),
              myNodeNum: null),
          isNull);
    });

    test('other ports, battery-only metrics and junk are ignored', () {
      final text = pb.MeshPacket(
          from: me, decoded: pb.Data(portnum: pb.PortNum.TEXT_MESSAGE_APP));
      expect(channelStatsFromTelemetry(text, myNodeNum: me), isNull);
      final battery =
          pb.Telemetry(deviceMetrics: pb.DeviceMetrics(batteryLevel: 80));
      expect(
          channelStatsFromTelemetry(telemetryPacket(me, battery),
              myNodeNum: me),
          isNull);
      final junk = pb.MeshPacket(
          from: me,
          decoded: pb.Data(
              portnum: pb.PortNum.TELEMETRY_APP, payload: [0xff, 0xff]));
      expect(channelStatsFromTelemetry(junk, myNodeNum: me), isNull);
    });
  });

  test('NodeInfo.deviceMetrics counts only for our own node', () {
    final info = pb.NodeInfo(
        num: me,
        deviceMetrics: pb.DeviceMetrics(airUtilTx: 0.5, channelUtilization: 3));
    expect(
        channelStatsFromNodeInfo(info, myNodeNum: me)!.airUtilTxPercent, 0.5);
    expect(channelStatsFromNodeInfo(info, myNodeNum: 5), isNull);
    expect(
        channelStatsFromNodeInfo(pb.NodeInfo(num: me), myNodeNum: me), isNull);
  });

  group('RadioStatsReadout', () {
    Future<FakeMeshRadio> pump(WidgetTester tester) async {
      final radio = FakeMeshRadio();
      await tester.pumpWidget(ProviderScope(
        overrides: [meshRadioProvider.overrideWithValue(radio)],
        child: const MaterialApp(
          home: Scaffold(body: RadioStatsReadout()),
        ),
      ));
      await tester.pump();
      await tester.pump();
      return radio;
    }

    testWidgets('shows nothing until the radio reports', (tester) async {
      await pump(tester);
      expect(readoutText(tester), isNull);
    });

    testWidgets('shows TX, channel and age; amber above 25%', (tester) async {
      final radio = await pump(tester);
      radio.pushChannelStats(RadioChannelStats(
        airUtilTxPercent: 1.2,
        channelUtilizationPercent: 8,
        measuredAt: DateTime.now().subtract(const Duration(minutes: 2)),
      ));
      await tester.pump();
      await tester.pump();
      expect(readoutText(tester),
          'Radio: TX 1.2%/h \u00b7 channel 8% \u00b7 2 min ago');

      radio.pushChannelStats(RadioChannelStats(
        airUtilTxPercent: 1.2,
        channelUtilizationPercent: 31,
        measuredAt: DateTime.now(),
      ));
      await tester.pump();
      await tester.pump();
      final rich = tester.widget<RichText>(find
          .descendant(
              of: find.byType(RadioStatsReadout),
              matching: find.byType(RichText))
          .first);
      final spans = <TextSpan>[];
      rich.text.visitChildren((s) {
        if (s is TextSpan) spans.add(s);
        return true;
      });
      final chan = spans.firstWhere((s) => s.text == '31%');
      // The test pumps a default (light) MaterialApp.
      expect(chan.style?.color, StatusColors.of(Brightness.light).warning);
    });

    testWidgets('hides a stale report', (tester) async {
      final radio = await pump(tester);
      radio.pushChannelStats(RadioChannelStats(
        airUtilTxPercent: 1,
        channelUtilizationPercent: 1,
        measuredAt: DateTime.now().subtract(const Duration(hours: 2)),
      ));
      await tester.pump();
      await tester.pump();
      expect(readoutText(tester), isNull);
    });
  });

  group('schema v6', () {
    test('new sessions have null radio stats; they can be stored', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      expect(db.schemaVersion, 11);
      final baseId = await db.upsertNode(nodeId: 2);
      final mapId = await db.createCoverageMap(name: 'm', baseNodeId: baseId);
      final id = await db.createSession(coverageMapId: mapId);
      var s = (await db.getSessionById(id))!;
      expect(s.radioAirUtilTx, isNull);
      expect(s.radioChannelUtil, isNull);
      await db.updateSessionRadioStats(id, airUtilTx: 1.5, channelUtil: 12);
      s = (await db.getSessionById(id))!;
      expect(s.radioAirUtilTx, 1.5);
      expect(s.radioChannelUtil, 12);
    });
  });
}
