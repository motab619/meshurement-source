// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/ble/radio_scanner.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:mesh_analyzer/ui/widgets/connection_banner.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_mesh_radio.dart';
import 'fakes/fake_radio_scanner.dart';

void main() {
  Future<void> pump(WidgetTester tester,
      {required String name, bool connected = true}) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final radio = FakeMeshRadio(
        myNodeId: 10,
        state: connected
            ? RadioConnectionState.ready
            : RadioConnectionState.disconnected)
      ..displayName = name;
    if (connected) {
      await radio.connect(const RadioDescriptor(id: 'A', name: 'a'));
    }
    await RadioRoles(prefs).assign(RadioRole.mobile, nodeNum: 10);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(radio),
        radioScannerProvider.overrideWithValue(FakeRadioScanner(const [])),
        bleAdapterStateProvider
            .overrideWith((ref) => Stream.value(RadioAdapterState.on)),
        activeSessionProvider.overrideWith((ref) => Stream.value(null)),
        rangeStateProvider
            .overrideWith((ref) => Stream.value(RangeState.inRange)),
      ],
      // As on the map: the pill beside a fixed-width readout.
      child: const MaterialApp(
        home: Scaffold(
          body: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: ConnectionBanner()),
              SizedBox(width: 8),
              SizedBox(width: 150, height: 40),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a long name is shortened instead of overflowing',
      (tester) async {
    await pump(tester,
        name: 'A very long node name that would never fit on the pill');
    expect(tester.takeException(), isNull);
    expect(find.text(' · Mobile'), findsOneWidget);
  });

  testWidgets('the radio sheet offers Switch radio, which opens the scan list',
      (tester) async {
    await pump(tester, name: 'MeshTest Mobile');
    await tester.tap(find.byType(ConnectionBanner));
    await tester.pumpAndSettle();
    final switchKey = find.byKey(const ValueKey('sheet-switch-radio'));
    expect(switchKey, findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    await tester.tap(switchKey);
    // The scan dialog shows a spinner while scanning, so settle by hand.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Connect to a node'), findsOneWidget);
    expect(find.byKey(const ValueKey('sheet-switch-radio')), findsNothing);
  });

  testWidgets('no "· Mobile" when the name already says it', (tester) async {
    await pump(tester, name: 'MeshTest Mobile');
    expect(tester.takeException(), isNull);
    expect(find.text('MeshTest Mobile'), findsOneWidget);
    expect(find.text(' · Mobile'), findsNothing);
  });

  testWidgets('with no radio it is a "Connect a radio" button',
      (tester) async {
    await pump(tester, name: 'x', connected: false);
    final button = find.byKey(const ValueKey('connect-radio-button'));
    expect(button, findsOneWidget);
    expect(find.text('Connect a node'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(button);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Connect to a node'), findsOneWidget);
  });

  testWidgets('connected, it keeps the pill look', (tester) async {
    await pump(tester, name: 'MeshTest Mobile');
    expect(find.byKey(const ValueKey('connect-radio-button')), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });
}
