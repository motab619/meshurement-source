// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/services/heading_service.dart';
import 'package:mesh_analyzer/ui/screens/map_screen.dart';
import 'package:mesh_analyzer/ui/widgets/base_map_layers.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_location_backend.dart';
import 'fakes/fake_mesh_radio.dart';

class FakeHeadingSource implements HeadingSource {
  final controller = StreamController<double?>.broadcast();
  int listeners = 0;

  @override
  Stream<double?> get headings {
    listeners++;
    return controller.stream;
  }
}

/// The Live map's compass button: a twisted map snaps back to north, and
/// from north the same button turns the map with the phone's compass
/// (tester feedback, 2026-11-01). Heading up goes with following: a twist
/// by the user turns it off and keeps their rotation, a pan pauses it
/// until the map follows the phone again (2026-11-02).
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late FakeHeadingSource heading;
  late FakeLocationBackend location;
  late GpsService gps;
  late SharedPreferences prefs;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  MapController controllerOf(WidgetTester tester) =>
      tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;

  Future<void> pump(WidgetTester tester,
      {Map<String, Object> initialPrefs = const {}}) async {
    // flutter_map's tile cache asks path_provider for a directory.
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathProvider, (call) async => Directory.systemTemp.path);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    heading = FakeHeadingSource();
    location = FakeLocationBackend();
    gps = GpsService(backend: location);
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(initialPrefs);
      prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(
            FakeMeshRadio(currentPreset: MeshtasticPresets.longFast)),
        gpsServiceProvider.overrideWithValue(gps),
        headingSourceProvider.overrideWithValue(heading),
      ]);
    });
    addTearDown(() async {
      container.dispose();
      await db.close();
      await heading.controller.close();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MapScreen()),
    ));
    await settle(tester);
  }

  final compass = find.byKey(const ValueKey('compass'));

  /// A GPS fix, so the map has a phone to follow and the locate button.
  Future<void> fix(WidgetTester tester) async {
    gps.startListening();
    location.positions.add(FakeLocationBackend.at(33.68, -116.24));
    await settle(tester);
  }

  /// A two-finger twist by the user, as flutter_map's gesture code
  /// reports it (the controller's own rotate() has source mapController).
  void twist(WidgetTester tester, double degrees) =>
      (controllerOf(tester) as MapControllerImpl).rotateRaw(degrees,
          hasGesture: true, source: MapEventSource.onMultiFinger);

  testWidgets('a rotated map snaps back to north', (tester) async {
    await pump(tester);
    expect(compass, findsOneWidget);
    expect(find.byTooltip('North up · tap to follow and turn with you'),
        findsOneWidget);

    controllerOf(tester).rotate(35);
    await settle(tester);
    expect(find.byTooltip('Tap for north up'), findsOneWidget);

    await tester.tap(compass);
    await settle(tester);
    expect(controllerOf(tester).camera.rotation, 0);
    expect(find.byTooltip('North up · tap to follow and turn with you'),
        findsOneWidget);
    // Nothing subscribed to the compass for a plain reset.
    expect(heading.listeners, 0);
  });

  testWidgets('from north the button turns the map with the compass',
      (tester) async {
    await pump(tester);
    expect(
        find.descendant(
            of: compass, matching: find.byIcon(Icons.navigation_outlined)),
        findsOneWidget);
    await tester.tap(compass);
    await settle(tester);
    expect(find.byTooltip('Heading up · tap for north up'), findsOneWidget);
    expect(heading.listeners, 1);
    expect(prefs.getBool(AppConstants.prefMapHeadingUp), isTrue);
    // A filled arrow while heading up, and the new mode said once.
    expect(
        find.descendant(of: compass, matching: find.byIcon(Icons.navigation)),
        findsOneWidget);
    expect(find.text('Heading up: the map turns with you'), findsOneWidget);

    heading.controller.add(90); // facing east
    await settle(tester);
    expect(controllerOf(tester).camera.rotation, closeTo(-90, 0.01));

    // The rotate gesture stays on while the compass drives the map, and
    // the gesture race keeps a pinch zoom from counting as a twist.
    final options = tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
    expect(options.interactionOptions.flags, InteractiveFlag.all);
    expect(options.interactionOptions.enableMultiFingerGestureRace, isTrue);

    // Tap again: north up, compass released.
    await tester.tap(compass);
    await settle(tester);
    expect(controllerOf(tester).camera.rotation, 0);
    expect(find.text('North up'), findsOneWidget);
    expect(find.text('Heading up: the map turns with you'), findsNothing);
    expect(prefs.getBool(AppConstants.prefMapHeadingUp), isFalse);
    heading.controller.add(180);
    await settle(tester);
    expect(controllerOf(tester).camera.rotation, 0);
  });

  testWidgets('heading up is remembered between launches', (tester) async {
    await pump(tester, initialPrefs: {AppConstants.prefMapHeadingUp: true});
    expect(find.byTooltip('Heading up · tap for north up'), findsOneWidget);
    expect(heading.listeners, 1);
    // Restoring the mode is not a change: nothing announced.
    expect(find.byKey(const ValueKey('compass-mode')), findsNothing);
  });

  testWidgets('Night dims the Live basemap tiles, not the dots',
      (tester) async {
    await pump(tester, initialPrefs: {AppConstants.prefAppearance: 'night'});
    expect(
        tester.widget<BaseMapLayers>(find.byType(BaseMapLayers)).dim, isTrue);
    expect(
        find.ancestor(
            of: find.byType(TileLayer), matching: find.byType(ColorFiltered)),
        findsWidgets);
    // Only the tiles are filtered: the dot layers are not under it.
    expect(
        find.ancestor(
            of: find.byType(CircleLayer), matching: find.byType(ColorFiltered)),
        findsNothing);
  });

  testWidgets('Bright leaves the Live map plain', (tester) async {
    await pump(tester, initialPrefs: {AppConstants.prefAppearance: 'bright'});
    expect(find.byType(ColorFiltered), findsNothing);
  });

  testWidgets('Automatic in a light app leaves the Live map plain',
      (tester) async {
    await pump(tester);
    expect(find.byType(ColorFiltered), findsNothing);
  });

  testWidgets('the layers button says "Layers" until it has been opened',
      (tester) async {
    await pump(tester);
    expect(find.text('Layers'), findsOneWidget);
    await tester.tap(find.byTooltip('Map style'));
    await settle(tester);
    expect(prefs.getBool(prefMapLayersOpened), isTrue);
    // Close the menu: from now on the plain round icon.
    await tester.tapAt(const Offset(20, 400));
    await settle(tester);
    await settle(tester);
    expect(find.text('Layers'), findsNothing);
    expect(find.byTooltip('Map style'), findsOneWidget);
  });

  testWidgets('once opened, the layers button is icon-only', (tester) async {
    await pump(tester, initialPrefs: {prefMapLayersOpened: true});
    expect(find.text('Layers'), findsNothing);
    expect(find.byTooltip('Map style'), findsOneWidget);
  });

  testWidgets('a twist by the user takes over: heading up off, map as turned',
      (tester) async {
    await pump(tester);
    await tester.tap(compass);
    await settle(tester);
    heading.controller.add(90);
    await settle(tester);
    expect(controllerOf(tester).camera.rotation, closeTo(-90, 0.01));

    twist(tester, -50);
    await settle(tester);
    expect(find.text('Heading up off'), findsOneWidget);
    expect(controllerOf(tester).camera.rotation, closeTo(-50, 0.01));
    expect(find.byTooltip('Tap for north up'), findsOneWidget);
    expect(prefs.getBool(AppConstants.prefMapHeadingUp), isFalse);
    // The compass no longer drives the map.
    heading.controller.add(0);
    await settle(tester);
    expect(controllerOf(tester).camera.rotation, closeTo(-50, 0.01));

    // Tap: north up. Tap again: heading up once more.
    await tester.tap(compass);
    await settle(tester);
    expect(controllerOf(tester).camera.rotation, 0);
    expect(find.byTooltip('North up · tap to follow and turn with you'),
        findsOneWidget);
    await tester.tap(compass);
    await settle(tester);
    expect(find.byTooltip('Heading up · tap for north up'), findsOneWidget);
    expect(heading.listeners, 2);
  });

  testWidgets('a pan pauses heading up until the map follows again',
      (tester) async {
    await pump(tester);
    await fix(tester);
    await tester.tap(compass);
    await settle(tester);
    expect(find.byTooltip('Following you'), findsOneWidget);
    heading.controller.add(90);
    await settle(tester);
    expect(controllerOf(tester).camera.rotation, closeTo(-90, 0.01));

    // Pan: following stops, the compass lets go, the map stays as turned
    // and the preference is kept.
    await tester.drag(find.byType(FlutterMap), const Offset(0, 120));
    await settle(tester);
    // The paused state is visible: its own tooltip and the pause badge.
    expect(find.byTooltip('Center on me and turn with you'), findsOneWidget);
    expect(
        find.byTooltip('Heading up paused · center on me to resume, or tap '
            'for north up'),
        findsOneWidget);
    expect(
        tester
            .widget<Badge>(find.byKey(const ValueKey('compass-paused')))
            .isLabelVisible,
        isTrue);
    expect(prefs.getBool(AppConstants.prefMapHeadingUp), isTrue);
    heading.controller.add(45);
    await settle(tester);
    expect(controllerOf(tester).camera.rotation, closeTo(-90, 0.01));

    // Center on me: following and heading up resume together.
    await tester.tap(find.byTooltip('Center on me and turn with you'));
    await settle(tester);
    expect(find.byTooltip('Heading up · tap for north up'), findsOneWidget);
    expect(
        tester
            .widget<Badge>(find.byKey(const ValueKey('compass-paused')))
            .isLabelVisible,
        isFalse);
    heading.controller.add(45);
    await settle(tester);
    expect(controllerOf(tester).camera.rotation, closeTo(-45, 0.01));
  });

  testWidgets('turning heading up on follows the phone again', (tester) async {
    await pump(tester);
    await fix(tester);
    await tester.drag(find.byType(FlutterMap), const Offset(0, 120));
    await settle(tester);
    expect(find.byTooltip('Center on me'), findsOneWidget);

    await tester.tap(compass);
    await settle(tester);
    expect(find.byTooltip('Following you'), findsOneWidget);
    expect(find.byTooltip('Heading up · tap for north up'), findsOneWidget);
  });
}
