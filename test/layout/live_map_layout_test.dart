// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/services/heading_service.dart';
import 'package:mesh_analyzer/ui/screens/map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_location_backend.dart';
import '../fakes/fake_mesh_radio.dart';
import 'window_sizes.dart';

/// The Live map's session panel: a bottom sheet on a phone (and on an
/// unfolded Duo held upright, too narrow for a column), docked beside the
/// map where there is room (iPad), without moving the map.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pump(WidgetTester tester, Size size) async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathProvider, (call) async => Directory.systemTemp.path);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null));
    await setWindow(tester, size);
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(
            FakeMeshRadio(currentPreset: MeshtasticPresets.longFast)),
        gpsServiceProvider
            .overrideWithValue(GpsService(backend: FakeLocationBackend())),
        headingSourceProvider.overrideWithValue(const NoHeadingSource()),
      ]);
    });
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MapScreen()),
    ));
    await settle(tester);
  }

  final sessionButton = find.text('Session');
  final docked = find.byKey(const ValueKey('session-panel-docked'));
  final sheet = find.byType(DraggableScrollableSheet);

  MapController controllerOf(WidgetTester tester) =>
      tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;

  testWidgets('phone: Session opens the bottom sheet', (tester) async {
    await pump(tester, phone);
    await tester.tap(sessionButton);
    await settle(tester);
    expect(sheet, findsOneWidget);
    expect(docked, findsNothing);
    expect(find.text('Session Controls'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (name, size) in [
    ('Duo unfolded upright', duoInner),
    ('iPad mini', iPadMini),
    ('iPad Pro 10.5', iPadPro105),
    ('iPad 11', iPad11),
  ]) {
    testWidgets('$name: Session docks the panel under the map, full width',
        (tester) async {
      await pump(tester, size);
      await tester.tap(sessionButton);
      await settle(tester);
      expect(docked, findsOneWidget);
      expect(sheet, findsNothing, reason: 'no floating sheet');
      expect(find.text('Session Controls'), findsOneWidget);
      final map = tester.getRect(find.byType(FlutterMap));
      final panel = tester.getRect(docked);
      expect(panel.top, greaterThanOrEqualTo(map.bottom - 1));
      expect(panel.width, map.width, reason: 'as wide as the map');
      expect(map.height, greaterThan(size.height * 0.5));
      expect(sessionButton, findsOneWidget, reason: 'still on the map');
      expect(tester.takeException(), isNull);
      await tester.tap(sessionButton);
      await settle(tester);
      expect(docked, findsNothing);
    });
  }

  for (final (name, size) in [
    ('iPad 13 portrait', const Size(1032, 1376)),
    ('iPad 13 landscape', iPad13Landscape),
    ('Duo unfolded sideways', duoInnerLandscape),
  ]) {
    testWidgets('$name: Session docks the panel beside the map',
        (tester) async {
      await pump(tester, size);
      const spot = LatLng(33.68, -116.24);
      controllerOf(tester).move(spot, 14);
      await settle(tester);

      await tester.tap(sessionButton);
      await settle(tester);
      expect(docked, findsOneWidget);
      expect(sheet, findsNothing);
      expect(find.text('Session Controls'), findsOneWidget);
      // The map shrank beside the panel but kept its place and zoom.
      final mapBox = tester.getSize(find.byType(FlutterMap));
      expect(mapBox.width, lessThan(size.width - 300));
      final camera = controllerOf(tester).camera;
      expect(camera.center.latitude, closeTo(spot.latitude, 1e-6));
      expect(camera.zoom, 14);
      expect(tester.takeException(), isNull);

      // Close, then the Session button toggles it back and forth.
      await tester.tap(find.byKey(const ValueKey('session-panel-close')));
      await settle(tester);
      expect(docked, findsNothing);
      await tester.tap(sessionButton);
      await settle(tester);
      expect(docked, findsOneWidget);
      await tester.tap(sessionButton);
      await settle(tester);
      expect(docked, findsNothing);
    });
  }
}
