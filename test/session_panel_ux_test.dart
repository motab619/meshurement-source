// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/models/processed_signal_event.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/field_report/field_report_data.dart';
import 'package:mesh_analyzer/services/field_report/field_report_loader.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/ui/theme/app_theme.dart';
import 'package:mesh_analyzer/ui/widgets/beacon_status.dart';
import 'package:mesh_analyzer/ui/widgets/session_stats_grid.dart';
import 'package:mesh_analyzer/ui/widgets/session_verdict.dart';
import 'package:mesh_analyzer/ui/widgets/signal_display.dart';

import 'field_report/fixtures.dart';

void main() {
  const status = StatusColors.dark;

  group('beacon label', () {
    test('heard of expected with a percent', () {
      expect(beaconStatsText(const BeaconStats(15, 19)),
          'Beacons 15 of ~34 (44 %)');
      expect(beaconStatsText(const BeaconStats(15, 19, exact: true)),
          'Beacons 15 of 34 (44 %)');
      expect(beaconStatsText(const BeaconStats(15, 19), kind: BeaconKind.trace),
          'Link checks 15 of 34 answered (44 %)');
      expect(beaconStatsText(BeaconStats.none), isNull);
      expect(beaconHeardPct(BeaconStats.none), isNull);
    });

    test('bands: 80 % and up ok, 50 to 80 amber, below red', () {
      expect(heardBandColor(status, 100), status.ok);
      expect(heardBandColor(status, 80), status.ok);
      expect(heardBandColor(status, 79), status.warning);
      expect(heardBandColor(status, 50), status.warning);
      expect(heardBandColor(status, 49), status.danger);
      expect(heardBandColor(status, 0), status.danger);
    });

    Future<Text> pumpLine(WidgetTester tester, BeaconStats stats) async {
      // A fresh scope per figure.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          beaconStatsProvider.overrideWith((ref, id) => Stream.value(stats)),
        ],
        child: const MaterialApp(
            home: Scaffold(body: BeaconStatsLine(sessionId: 1))),
      ));
      await tester.pump();
      return tester.widget<Text>(find.byKey(const ValueKey('beacon-stats')));
    }

    testWidgets('the line is coloured by band', (tester) async {
      final theme = ThemeData(brightness: Brightness.light).status;
      var t = await pumpLine(tester, const BeaconStats(15, 19));
      expect(t.data, 'Beacons 15 of ~34 (44 %)');
      expect(t.style?.color, theme.danger);
      t = await pumpLine(tester, const BeaconStats(30, 4, exact: true));
      expect(t.data, 'Beacons 30 of 34 (88 %)');
      expect(t.style?.color, theme.ok);
      t = await pumpLine(tester, const BeaconStats(20, 14, exact: true));
      expect(t.style?.color, theme.warning);
      t = await pumpLine(tester, BeaconStats.none);
      expect(t.data, 'Beacons: none expected yet');
    });
  });

  group('GPS colour', () {
    test('green within 10 m, amber looser, red without a fix', () {
      expect(gpsStateColor(status, const GpsState(GpsStatus.fix, accuracy: 5)),
          status.ok);
      expect(gpsStateColor(status, const GpsState(GpsStatus.fix, accuracy: 10)),
          status.ok);
      expect(gpsStateColor(status, const GpsState(GpsStatus.fix, accuracy: 25)),
          status.warning);
      expect(gpsStateColor(status, const GpsState(GpsStatus.searching)),
          status.danger);
      expect(gpsStateColor(status, const GpsState(GpsStatus.denied)),
          status.danger);
    });
  });

  test('elapsed reads as a clock', () {
    expect(formatElapsed(const Duration(seconds: 75)), '01:15');
    expect(formatElapsed(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03');
  });

  group('verdict after End session', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('base heard, farthest and median, in the Compare voice', () async {
      final s = await seedSession32(db);
      final d = (await FieldReportLoader(db).session(s.sessionId))!;
      final session = (await db.getSessionById(s.sessionId))!;
      expect(sessionVerdict(d, session, miles: false),
          'Base heard 49 % · farthest 400 m · median +6 dB');
      expect(sessionVerdict(d, session, miles: true),
          'Base heard 49 % · farthest 0.2 mi · median +6 dB');
    });

    test('never empty: a base never heard says so with the count', () {
      final session = testSession(1).copyWith(beaconKind: 'telemetry');
      final misses = [
        for (var i = 0; i < 12; i++)
          testEvent(1, i, 0, 100.0 * i)
              .copyWith(sourceKind: 'telemetry_miss', rxSnr: const Value(null)),
      ];
      final d = FieldReportData.build(
          [SessionReportInput(session: session, events: misses)],
          base: (lat: baseLat, lon: baseLon));
      expect(sessionVerdict(d, session, miles: false),
          'Base node not heard · 0 of 12 beacons');
    });

    test('nothing due at all', () {
      final session = testSession(1);
      final d = FieldReportData.build(
          [SessionReportInput(session: session, events: const [])],
          base: (lat: baseLat, lon: baseLon));
      expect(sessionVerdict(d, session, miles: false),
          'Base node not heard · nothing from it was due in this session');
    });
  });

  test('the signal readout names where a reading came from', () {
    ProcessedSignalEvent e(int from, {String dir = 'rx', String name = 'x'}) =>
        ProcessedSignalEvent(
            timestamp: DateTime(2026),
            sourceNodeId: from,
            sourceNodeName: name,
            packetType: '',
            direction: dir);
    expect(signalOriginLabel(e(7), baseNodeNum: 7), 'Heard from base');
    expect(signalOriginLabel(e(8), baseNodeNum: 7), 'Heard from another node');
    expect(signalOriginLabel(e(7, dir: 'ack'), baseNodeNum: 7),
        'Reply to your ping');
    expect(signalOriginLabel(e(0, name: 'ping reply')), 'Reply to your ping');
    expect(signalOriginLabel(e(0)), 'Heard');
  });
}
