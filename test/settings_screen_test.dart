// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/ui/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_mesh_radio.dart';

void main() {
  testWidgets('sections: Radios first, Privacy just above About',
      (tester) async {
    tester.view.physicalSize = const Size(800, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(FakeMeshRadio(myNodeId: 10)),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    // Radios starts with the connected radio and the switch, above Setup.
    final connectRow = find.textContaining('Connected: ');
    expect(connectRow, findsOneWidget);
    expect(find.text('Tap to switch to your other node'), findsOneWidget);
    expect(tester.getTopLeft(connectRow).dy,
        lessThan(tester.getTopLeft(find.text('Node Setup')).dy));

    // Backups have their own row under Radios.
    expect(find.text('Node backups'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Node Setup')).dy,
        lessThan(tester.getTopLeft(find.text('Node backups')).dy));
    // Keep screen on is automatic while recording; the switch is for always.
    expect(find.text('On while a session records; this keeps it on all the '
        'time.'), findsOneWidget);
    // Count relayed packets: one sentence, the rest behind its ⓘ.
    expect(find.text('Off: only packets straight from the base node count.'),
        findsOneWidget);
    expect(find.textContaining('small dots on the map'), findsNothing);
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('settings-count-relayed')),
        matching: find.byIcon(Icons.info_outline)));
    await tester.pumpAndSettle();
    expect(find.textContaining('small dots on the map'), findsOneWidget);
    expect(prefs.getBool('count_relayed_packets'), isNull,
        reason: 'the ⓘ does not flip the switch');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    double y(String header) => tester.getTopLeft(find.text(header).first).dy;
    const order = [
      'My nodes',
      'Hardware',
      'Display',
      'Terrain',
      'Active probing',
      'Notifications',
      'Data',
      'Privacy',
      'About',
    ];
    for (var i = 1; i < order.length; i++) {
      expect(y(order[i - 1]), lessThan(y(order[i])),
          reason: '${order[i - 1]} should come before ${order[i]}');
    }
  });
}
