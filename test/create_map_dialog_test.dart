// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/base_location.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/services/terrain/terrain_settings.dart';
import 'package:mesh_analyzer/services/base_node.dart';
import 'package:mesh_analyzer/ui/widgets/create_map_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_location_backend.dart';
import 'fakes/fake_mesh_radio.dart';

void main() {
  testWidgets('no base radio picker: a map is a place', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // No radios known at all: a map can still be made.
    final radio = FakeMeshRadio(myNodeId: 1);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(radio),
        gpsServiceProvider.overrideWithValue(_FixedGps(null)),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => showCreateMapDialog(context, ref),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(find.textContaining('Base node'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Park');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    final map = (await tester.runAsync(db.getAllCoverageMaps))!.single;
    expect(map.name, 'Park');
    expect(map.baseNodeId, isNull);
    expect(map.baseLat, isNull);
  });

  group('base location default', () {
    Future<(SharedPreferences, AppDatabase)> open(
      WidgetTester tester, {
      required bool savedLocation,
      Position? fix,
    }) async {
      SharedPreferences.setMockInitialValues({baseNodePrefKey: 2});
      final prefs = await SharedPreferences.getInstance();
      if (savedLocation) {
        await BaseLocationStore(prefs)
            .record(2, const LatLng(33.0, -116.0), accuracyM: 10);
      }
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final radio = FakeMeshRadio(myNodeId: 1);
      radio.nodes[2] = const RadioNode(num: 2, longName: 'Base', hopsAway: 0);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          meshRadioProvider.overrideWithValue(radio),
          gpsServiceProvider.overrideWithValue(_FixedGps(fix)),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showCreateMapDialog(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      return (prefs, db);
    }

    final tiles = find.byWidgetPredicate((w) => w is RadioListTile);

    String? chosen(WidgetTester tester) {
      final group = tester
          .widget(find.byWidgetPredicate((w) => w is RadioGroup)) as dynamic;
      for (final t in tester.widgetList(tiles)) {
        final tile = t as dynamic;
        if (tile.value == group.groupValue) return (tile.title as Text).data;
      }
      return null;
    }

    bool enabled(WidgetTester tester, String title) =>
        (tester.widget(find.ancestor(of: find.text(title), matching: tiles))
                as dynamic)
            .enabled !=
        false;

    // Near the saved location (33.0, -116.0) unless told otherwise.
    Position pos(double acc, {double lat = 33.001, double lon = -116.0}) =>
        Position(
            latitude: lat,
            longitude: lon,
            timestamp: DateTime(2026),
            accuracy: acc,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0);

    testWidgets('Radio Setup location exists: "where it was set up" is chosen',
        (tester) async {
      await open(tester, savedLocation: true, fix: pos(5));
      expect(find.text('Where it was set up'), findsOneWidget);
      expect(find.text('My position now'), findsOneWidget);
      expect(find.text('Set it by hand'), findsOneWidget);
      expect(chosen(tester), 'Where it was set up');
      expect(enabled(tester, 'My position now'), isTrue);
    });

    testWidgets('the chosen location is stored on the map', (tester) async {
      final (_, db) = await open(tester, savedLocation: true);
      await tester.enterText(find.byType(TextField).first, 'Test map');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      final map = (await tester.runAsync(db.getAllCoverageMaps))!.single;
      expect((map.baseLat, map.baseLon), (33.0, -116.0));
      expect(map.baseNodeId, isNull);
    });

    testWidgets(
        'saved location far from the phone: "my position now" is chosen',
        (tester) async {
      await open(tester, savedLocation: true, fix: pos(5, lat: 33.5));
      expect(chosen(tester), 'My position now');
      expect(enabled(tester, 'Where it was set up'), isTrue);
      expect(find.textContaining('from where you are now'), findsOneWidget);
    });

    testWidgets('saved location far, no fix: still the saved one',
        (tester) async {
      await open(tester, savedLocation: true);
      expect(chosen(tester), 'Where it was set up');
      expect(find.textContaining('from where you are now'), findsNothing);
    });

    testWidgets('no saved location but a GPS fix: "my position now" is chosen',
        (tester) async {
      await open(tester, savedLocation: false, fix: pos(5));
      expect(enabled(tester, 'Where it was set up'), isFalse);
      expect(find.textContaining('standing at the base'), findsOneWidget);
      expect(chosen(tester), 'My position now');
    });

    testWidgets('no location and no fix: "set it by hand", others disabled',
        (tester) async {
      await open(tester, savedLocation: false);
      expect(chosen(tester), 'Set it by hand');
      expect(enabled(tester, 'Where it was set up'), isFalse);
      expect(enabled(tester, 'My position now'), isFalse);
      expect(find.textContaining('Set base location'), findsOneWidget);
      // Location never asked for: say so and offer to ask.
      expect(find.text('Location not allowed yet.'), findsOneWidget);
      expect(find.byKey(const ValueKey('map-allow-location')), findsOneWidget);
    });

    testWidgets('Allow location asks, then a fix enables "my position now"',
        (tester) async {
      SharedPreferences.setMockInitialValues({baseNodePrefKey: 2});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final backend = FakeLocationBackend(
          permission: LocationPermission.denied,
          afterRequest: LocationPermission.whileInUse);
      final gps = GpsService(backend: backend);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          meshRadioProvider.overrideWithValue(FakeMeshRadio(myNodeId: 1)),
          gpsServiceProvider.overrideWithValue(gps),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => showCreateMapDialog(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(enabled(tester, 'My position now'), isFalse);

      await tester.tap(find.byKey(const ValueKey('map-allow-location')));
      await tester.pumpAndSettle();
      expect(backend.requests, 1);
      expect(find.text('Getting a fix…'), findsOneWidget);
      expect(find.byKey(const ValueKey('map-allow-location')), findsNothing);

      backend.positions.add(pos(8));
      await tester.pumpAndSettle();
      expect(enabled(tester, 'My position now'), isTrue);
      expect(chosen(tester), 'My position now');
    });

    testWidgets(
        'choosing another option over Node Setup is remembered per map',
        (tester) async {
      final (prefs, _) = await open(tester, savedLocation: true);
      // The Allow-location row above it can push it below the fold.
      await tester.ensureVisible(find.text('Set it by hand'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set it by hand'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Test map');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(prefs.getKeys().where((k) => k.startsWith('terrain_base_optout_')),
          hasLength(1));
      expect(
          prefs.getKeys().where((k) => k.startsWith('terrain_base_location_')),
          isEmpty);
      final id = int.parse(prefs
          .getKeys()
          .firstWhere((k) => k.startsWith('terrain_base_optout_'))
          .split('_')
          .last);
      expect(TerrainSettings.loadBaseOptOut(prefs, id), isTrue);
    });
  });
}

class _FixedGps extends GpsService {
  _FixedGps(this._fix);
  final Position? _fix;
  @override
  Position? get lastPosition => _fix;
}
