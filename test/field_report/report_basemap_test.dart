// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/field_report/field_report_data.dart';
import 'package:mesh_analyzer/services/field_report/field_report_loader.dart';
import 'package:mesh_analyzer/services/pro_entitlement.dart';
import 'package:mesh_analyzer/services/privacy_settings.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/field_report_card.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/field_report_sheet.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/report_basemap.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/report_painters.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/report_style.dart';
import 'package:mesh_analyzer/utils/map_tiles.dart';

import '../pro_entitlement_test.dart' show FakeStore;
import 'fixtures.dart';

/// Stands in for a tile source; the loader's fetch hook does the work.
class _FakeTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      throw StateError('the fetch hook should be used');
}

void main() {
  group('ReportTileGrid', () {
    const origin = (lat: 33.70, lon: -116.23);
    const frame = RouteFrame(-1000, -600, 1500, 900);
    final view = RouteView(frame, const Size(980, 510));
    final grid = ReportTileGrid.of(view, origin);

    test('tiles are at least as sharp as the card, and not wastefully more',
        () {
      expect(grid.f, lessThanOrEqualTo(1));
      expect(grid.f, greaterThan(0.5));
    });

    test('a recorded point lands where the route painter draws it', () {
      for (final (x, y) in [(0.0, 0.0), (800.0, -200.0), (-900.0, 850.0)]) {
        // The report's own projection, undone to a lat/lon...
        final lat = origin.lat + y / 111320;
        final lon =
            origin.lon + x / (111320 * math.cos(origin.lat * math.pi / 180));
        // ...then Web Mercator at the grid's zoom.
        final world = 256 * math.pow(2, grid.zoom);
        final gx = (lon + 180) / 360 * world;
        final r = lat * math.pi / 180;
        final gy =
            (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * world;
        final onTiles = Offset(view.size.width / 2 + (gx - grid.gx) * grid.f,
            view.size.height / 2 + (gy - grid.gy) * grid.f);
        final painted = view.at(x, y);
        expect((onTiles - painted).distance, lessThan(1.5),
            reason: 'point ($x, $y)');
      }
    });

    test('the tiles cover the whole box', () {
      final rects = [for (final (x, y) in grid.tiles) grid.rectOf(x, y)];
      final box = Offset.zero & view.size;
      for (final p in [
        box.topLeft,
        box.topRight - const Offset(0.1, 0),
        box.bottomLeft - const Offset(0, 0.1),
        box.bottomRight - const Offset(0.1, 0.1),
        box.center,
      ]) {
        expect(rects.any((r) => r.contains(p)), isTrue, reason: '$p');
      }
    });

    test('a huge area steps out a zoom instead of asking for 100s of tiles',
        () {
      final big = RouteView(frame, const Size(4000, 4000));
      final g = ReportTileGrid.of(big, origin, maxTiles: 20);
      expect(g.tiles.length, lessThanOrEqualTo(20));
    });
  });

  group('cards and sheet', () {
    late AppDatabase db;
    late _FakeTiles streets;
    var requests = 0;
    ui.Image? tile;

    setUp(() {
      SharedPreferences.setMockInitialValues({'distance_units': 'miles'});
      db = AppDatabase.forTesting(NativeDatabase.memory());
      streets = _FakeTiles();
      requests = 0;
    });
    tearDown(() => db.close());

    /// One decoded tile image, shared (each request gets a clone).
    Future<void> makeTile(WidgetTester tester) async {
      tile ??=
          await tester.runAsync(() => createTestImage(width: 256, height: 256));
    }

    ReportTileLoader loader() =>
        ReportTileLoader(MapTileConfig.fromValues(), streets: streets,
            fetchOverride: (p, c) async {
          requests++;
          return tile!.clone();
        });

    Future<FieldReportData> session32(WidgetTester tester) async =>
        (await tester.runAsync(() async {
          final s = await seedSession32(db);
          return FieldReportLoader(db).session(s.sessionId);
        }))!;

    testWidgets('a streets card loads tiles and credits OpenStreetMap',
        (tester) async {
      await makeTile(tester);
      final d = await session32(tester);
      expect(d.geoOrigin, isNotNull);
      final tiles = loader();
      addTearDown(tiles.dispose);
      const size = Size(1080, 1350);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(SizedBox.fromSize(
          size: size,
          child: FieldReportCard(
            data: d,
            title: 'x',
            format: ReportFormat.feed,
            miles: true,
            background: ReportBackground.streets,
            tiles: tiles,
          )));
      await tester.pump();
      await tiles.idle;
      await tester.pump();
      expect(requests, greaterThan(0));
      expect(find.textContaining('OpenStreetMap'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a plain card asks for no tiles and has no map credit',
        (tester) async {
      final d = await session32(tester);
      final tiles = loader();
      addTearDown(tiles.dispose);
      tester.view.physicalSize = const Size(1080, 1350);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(SizedBox.fromSize(
          size: const Size(1080, 1350),
          child: FieldReportCard(
              data: d,
              title: 'x',
              format: ReportFormat.feed,
              miles: true,
              tiles: tiles)));
      await tester.pump();
      expect(requests, 0);
      expect(
          find.byKey(const ValueKey('field-report-map-credit')), findsNothing);
    });

    Future<Widget> sheet(FieldReportData d, {bool tilesOn = true}) async {
      final prefs = await SharedPreferences.getInstance();
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
          proEntitlementProvider.overrideWithValue(
              ProEntitlement(prefs: prefs, store: FakeStore())),
          mapTilesEnabledProvider.overrideWithValue(tilesOn),
          reportTileLoaderFactoryProvider.overrideWithValue(loader),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: FieldReportSheet(load: (_) async => SingleReport(d)))),
      );
    }

    void bigScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('the background choice is remembered for the next report',
        (tester) async {
      bigScreen(tester);
      await makeTile(tester);
      final d = await session32(tester);
      await tester.pumpWidget(await sheet(d));
      await tester.pumpAndSettle();
      expect(find.text('A plain grid with no streets.'), findsOneWidget);

      await tester.tap(find.text('Streets'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The map shows where the route is'),
          findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(reportBackgroundPref), 'streets');

      // A new sheet starts on Streets.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(await sheet(d));
      await tester.pumpAndSettle();
      expect(find.textContaining('The map shows where the route is'),
          findsOneWidget);
    });

    testWidgets('with map tiles off in Privacy the card stays plain',
        (tester) async {
      bigScreen(tester);
      SharedPreferences.setMockInitialValues(
          {'distance_units': 'miles', reportBackgroundPref: 'streets'});
      final d = await session32(tester);
      await tester.pumpWidget(await sheet(d, tilesOn: false));
      await tester.pumpAndSettle();
      expect(find.textContaining('Map tiles are off'), findsOneWidget);
      expect(requests, 0);
    });
  });
}
