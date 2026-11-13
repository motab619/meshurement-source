// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/models/processed_signal_event.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/base_node.dart';
import 'package:mesh_analyzer/ui/theme/app_theme.dart';
import 'package:mesh_analyzer/ui/widgets/signal_display.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_mesh_radio.dart';

// Field test 2026-11-08 (Andy): "why do i want hops?" and "Reply to your
// ping" over "ping reply". A direct reading has no hops line; a relayed one
// gets a warning; the node name shows only when it adds something.
ProcessedSignalEvent _e(int from,
        {String dir = 'rx', String name = 'x', int hops = 0}) =>
    ProcessedSignalEvent(
        timestamp: DateTime(2026),
        sourceNodeId: from,
        sourceNodeName: name,
        rxSnr: 8,
        rxRssi: -90,
        hopCount: hops,
        packetType: '',
        direction: dir);

void main() {
  test('the node name is hidden when it repeats the origin line', () {
    String? line(ProcessedSignalEvent e) =>
        signalSourceLine(e, signalOriginLabel(e, baseNodeNum: 7),
            baseNodeNum: 7);
    expect(line(_e(7, name: 'MeshTest Base')), isNull);
    expect(line(_e(0, name: 'ping reply')), isNull);
    expect(line(_e(7, dir: 'ack', name: 'MeshTest Base')), isNull);
    // A reply relayed by another node, or another node heard: which one.
    expect(line(_e(9, dir: 'ack', name: 'Hilltop')), 'Hilltop');
    expect(line(_e(8, name: 'Stranger')), 'Stranger');
    expect(line(_e(8, name: '')), isNull);
  });

  Future<void> pump(WidgetTester tester, ProcessedSignalEvent e) async {
    SharedPreferences.setMockInitialValues({baseNodePrefKey: 7});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(FakeMeshRadio()),
        liveSignalProvider.overrideWith((ref) => Stream.value(e)),
        activeSessionProvider.overrideWith((ref) => Stream.value(null)),
        airtimeDutyProvider.overrideWith((ref) => Stream.value(0)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: Center(child: SignalDisplay())),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a direct reading from the base: no hops, no repeated name',
      (tester) async {
    await pump(tester, _e(7, name: 'MeshTest Base'));
    expect(find.textContaining('Hops'), findsNothing);
    expect(find.byKey(const ValueKey('signal-relayed')), findsNothing);
    expect(find.text('Heard from base'), findsOneWidget);
    expect(find.byKey(const ValueKey('signal-source')), findsNothing);
  });

  testWidgets('a ping reply placeholder is not shown under the origin',
      (tester) async {
    await pump(tester, _e(0, name: 'ping reply'));
    expect(find.text('Reply to your ping'), findsOneWidget);
    expect(find.text('ping reply'), findsNothing);
  });

  testWidgets('a relayed reading carries a warning line', (tester) async {
    await pump(tester, _e(7, name: 'MeshTest Base', hops: 2));
    final warning =
        tester.widget<Text>(find.byKey(const ValueKey('signal-relayed')));
    expect(warning.data, 'Relayed by another node, not a direct reading');
    final ctx = tester.element(find.byKey(const ValueKey('signal-relayed')));
    expect(warning.style?.color, Theme.of(ctx).status.warning);
    expect(tester.getSemantics(find.byType(SignalDisplay)).label,
        contains('relayed by another node'));
  });
}
