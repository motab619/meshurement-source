// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/data/tiles/pmtiles_archive.dart';
import 'package:mesh_analyzer/data/tiles/pmtiles_tile_provider.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/ui/screens/about_screen.dart';
import 'package:mesh_analyzer/ui/widgets/base_map_layers.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:mesh_analyzer/utils/map_tiles.dart';

// Coachella Valley, roughly.
final _hosted = MapTileConfig.fromValues(
  streets: 'https://example.cloudfront.net/v1/socal-streets.pmtiles',
  terrain: 'https://example.cloudfront.net/v1/socal-terrain.pmtiles',
  boundsSWNE: [33.4, -116.6, 34.0, -115.9],
  region: 'the Coachella Valley',
);

/// Tile z/x/y containing [lat],[lon].
(int, int) _tileAt(int z, double lat, double lon) {
  final n = 1 << z;
  final x = ((lon + 180) / 360 * n).floor();
  final r = lat * math.pi / 180;
  final y =
      ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n).floor();
  return (x, y);
}

/// Writes a PMTiles v3 file with [tiles] (tileId → bytes), uncompressed
/// directories, root directory only.
Uint8List _pmtiles(Map<int, List<int>> tiles,
    {int minZoom = 0, int maxZoom = 14}) {
  final ids = tiles.keys.toList()..sort();
  final data = BytesBuilder();
  final offsets = <int>[];
  for (final id in ids) {
    offsets.add(data.length);
    data.add(tiles[id]!);
  }
  final dir = BytesBuilder();
  void varint(int v) {
    while (v >= 0x80) {
      dir.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    dir.addByte(v);
  }

  varint(ids.length);
  var last = 0;
  for (final id in ids) {
    varint(id - last);
    last = id;
  }
  for (final _ in ids) {
    varint(1);
  }
  for (final id in ids) {
    varint(tiles[id]!.length);
  }
  for (var i = 0; i < ids.length; i++) {
    varint(offsets[i] + 1);
  }
  final root = dir.toBytes();
  final h = ByteData(127);
  'PMTiles'.codeUnits.asMap().forEach((i, c) => h.setUint8(i, c));
  h.setUint8(7, 3);
  h.setUint64(8, 127, Endian.little);
  h.setUint64(16, root.length, Endian.little);
  h.setUint64(24, 127 + root.length, Endian.little);
  h.setUint64(32, 0, Endian.little);
  h.setUint64(40, 127 + root.length, Endian.little);
  h.setUint64(48, 0, Endian.little);
  h.setUint64(56, 127 + root.length, Endian.little);
  h.setUint64(64, data.length, Endian.little);
  h.setUint8(97, PmTilesHeader.compressionNone);
  h.setUint8(98, PmTilesHeader.compressionNone);
  h.setUint8(99, 2); // png
  h.setUint8(100, minZoom);
  h.setUint8(101, maxZoom);
  return (BytesBuilder()
        ..add(h.buffer.asUint8List())
        ..add(root)
        ..add(data.toBytes()))
      .toBytes();
}

/// The root directory bytes of a file written by [_pmtiles].
Uint8List _directoryOf(Uint8List file) {
  final h = ByteData.sublistView(file);
  final off = h.getUint64(8, Endian.little);
  final len = h.getUint64(16, Endian.little);
  return Uint8List.fromList(file.sublist(off, off + len));
}

/// Tile id 5 is z2/0/0.
Future<Uint8List?> _tile5(PmTilesArchive a) => a.getTile(2, 0, 0);

class _MemorySource implements PmTilesSource {
  _MemorySource(this.bytes);
  final Uint8List bytes;

  @override
  Future<Uint8List> read(int offset, int length) async {
    final end = (offset + length).clamp(0, bytes.length);
    return Uint8List.sublistView(bytes, offset.clamp(0, end), end);
  }

  @override
  Future<void> close() async {}
}

class _FailingSource implements PmTilesSource {
  @override
  Future<Uint8List> read(int offset, int length) async =>
      throw PmTilesException('HTTP 403');

  @override
  Future<void> close() async {}
}

void main() {
  group('PMTiles reader', () {
    test('Hilbert tile ids match the v3 spec', () {
      expect(PmTilesArchive.zxyToTileId(0, 0, 0), 0);
      expect(PmTilesArchive.zxyToTileId(1, 0, 0), 1);
      expect(PmTilesArchive.zxyToTileId(1, 0, 1), 2);
      expect(PmTilesArchive.zxyToTileId(1, 1, 1), 3);
      expect(PmTilesArchive.zxyToTileId(1, 1, 0), 4);
      expect(PmTilesArchive.zxyToTileId(2, 0, 0), 5);
      // From the reference implementation's tests.
      expect(PmTilesArchive.zxyToTileId(12, 3423, 1763), 19078479);
    });

    test('reads tiles back from a file, misses return null', () async {
      final a = PmTilesArchive.zxyToTileId(10, 180, 409);
      final b = PmTilesArchive.zxyToTileId(10, 181, 409);
      final dir = await Directory.systemTemp.createTemp('pmtiles_test');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/t.pmtiles')
        ..writeAsBytesSync(_pmtiles({
          a: [1, 2, 3],
          b: [9, 8]
        }));
      final archive =
          await PmTilesArchive.open(PmTilesSource.fromUrl(f.uri.toString()));
      addTearDown(archive.close);
      expect(archive.header.tileType, PmTileType.png);
      expect(archive.header.maxZoom, 14);
      expect(await archive.getTile(10, 180, 409), [1, 2, 3]);
      expect(await archive.getTile(10, 181, 409), [9, 8]);
      expect(await archive.getTile(10, 182, 409), isNull);
      expect(await archive.getTile(3, 1, 3), isNull);
    });

    test('rejects a file that is not PMTiles', () {
      expect(() => PmTilesHeader.parse(Uint8List(200)),
          throwsA(isA<PmTilesException>()));
    });

    group('malformed directories throw PmTilesException, never RangeError', () {
      final throwsPm = throwsA(isA<PmTilesException>());

      test('a truncated directory', () {
        final full = _directoryOf(_pmtiles({
          5: [1, 2, 3],
          9: [4, 5],
        }));
        expect(PmTilesArchive.parseDirectory(full), hasLength(2));
        for (var cut = 0; cut < full.length; cut++) {
          expect(() => PmTilesArchive.parseDirectory(full.sublist(0, cut)),
              throwsPm,
              reason: 'cut at $cut of ${full.length}');
        }
      });

      test('an entry count the bytes cannot hold', () {
        // n = 2^40 in five varint bytes, then nothing.
        expect(
            () => PmTilesArchive.parseDirectory(
                Uint8List.fromList([0x80, 0x80, 0x80, 0x80, 0x80, 0x20])),
            throwsPm);
      });

      test('an overlong varint', () {
        expect(
            () => PmTilesArchive.parseDirectory(
                Uint8List.fromList(List.filled(12, 0xff))),
            throwsPm);
      });

      test('a first offset of zero', () {
        // one entry: id 0, run 1, length 1, offset varint 0
        expect(
            () => PmTilesArchive.parseDirectory(
                Uint8List.fromList([1, 0, 1, 1, 0])),
            throwsPm);
      });

      test('a truncated archive and a tile outside its section', () async {
        final bytes = _pmtiles({
          5: [1, 2, 3],
        });
        final dir = await Directory.systemTemp.createTemp('pmtiles_bad');
        addTearDown(() => dir.delete(recursive: true));

        // Root length larger than the file: the root read comes back short.
        final longRoot = Uint8List.fromList(bytes);
        ByteData.sublistView(longRoot).setUint64(16, 20000, Endian.little);
        final f1 = File('${dir.path}/a.pmtiles')..writeAsBytesSync(longRoot);
        await expectLater(
            PmTilesArchive.open(PmTilesSource.fromUrl(f1.path)), throwsPm);

        // A negative (over 2^63) section length in the header.
        final neg = Uint8List.fromList(bytes);
        ByteData.sublistView(neg).setInt64(64, -1, Endian.little);
        expect(() => PmTilesHeader.parse(neg), throwsPm);

        // Tile data section shorter than the entry claims.
        final short = Uint8List.fromList(bytes);
        ByteData.sublistView(short).setUint64(64, 2, Endian.little);
        final f2 = File('${dir.path}/b.pmtiles')..writeAsBytesSync(short);
        final a = await PmTilesArchive.open(PmTilesSource.fromUrl(f2.path));
        addTearDown(a.close);
        expect(await a.getTile(1, 0, 0), isNull, reason: 'a miss');
        await expectLater(_tile5(a), throwsPm);
      });

      test('a gzip directory that is corrupt', () {
        final h = ByteData(127);
        'PMTiles'.codeUnits.asMap().forEach((i, c) => h.setUint8(i, c));
        h.setUint8(7, 3);
        h.setUint64(8, 127, Endian.little);
        h.setUint64(16, 4, Endian.little);
        h.setUint8(97, PmTilesHeader.compressionGzip);
        final file = (BytesBuilder()
              ..add(h.buffer.asUint8List())
              ..add([0x1f, 0x8b, 0x08, 0x00]))
            .toBytes();
        expect(PmTilesArchive.open(_MemorySource(file)), throwsPm);
      });
    });
  });

  group('MapTileConfig', () {
    test('nothing hosted: OSM only, standard style, OSM credit', () {
      final c = MapTileConfig.fromValues();
      expect(c.anyHosted, isFalse);
      expect(c.terrainAvailable, isFalse);
      expect(
          c.osmFallbackUrl, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
      expect(c.effectiveStyle(MapStyle.terrain), MapStyle.standard);
      expect(c.creditsFor(MapStyle.terrain), [MapTileConfig.osmCredit]);
    });

    test('the shipped regions cover the United States', () {
      final c = MapTileConfig.current;
      expect(c.anyHosted, isTrue);
      expect(c.anyRemoteHosted, isTrue);
      expect(c.terrainAvailable, isTrue);
      expect(c.regionName, 'the United States');
      expect(c.regions.map((r) => r.name), [
        'west',
        'midwest',
        'south',
        'northeast',
        'hawaii',
        'alaska'
      ]);
      for (final r in c.regions) {
        for (final kind in HostedTileKind.values) {
          expect(r.urlFor(kind),
              'https://d13u6w4g5rrbl6.cloudfront.net/v2/${r.name}-${kind.name}.pmtiles');
        }
      }
      List<String> at(double lat, double lon, {int z = 14}) {
        final (x, y) = _tileAt(z, lat, lon);
        return c
            .candidatesFor(HostedTileKind.streets, z, x, y)
            .map((r) => r.name)
            .toList();
      }

      expect(at(41.88, -87.63), ['midwest']); // Chicago
      expect(at(21.31, -157.86), ['hawaii']); // Honolulu
      expect(at(61.22, -149.90), ['alaska']); // Anchorage
      expect(at(39.74, -104.99), ['west', 'south']); // Denver: west first
      expect(at(37.0, -94.0), ['midwest', 'south']); // overlap: list order
      expect(at(34.05, -118.25), ['west']); // Los Angeles
      expect(at(22.0, -90.0), isEmpty); // Gulf of Mexico, south of the box
      expect(at(41.88, -87.63, z: 7), isEmpty); // below z8: OSM
      expect(c.terrainCovers(const LatLng(41.88, -87.63)), isTrue);
      expect(c.terrainCovers(const LatLng(51.5, -0.12)), isFalse); // London
      expect(c.tileServersPhrase,
          'OpenStreetMap, or our map server in the United States');
      expect(mapTilesPrivacyText(c),
          contains('(CloudFront) inside the United States'));
    });

    test('tiles inside the covered bounds come from PMTiles, others not', () {
      final (ix, iy) = _tileAt(14, 33.7, -116.2); // Indio
      expect(_hosted.covers(14, ix, iy), isTrue);
      final (ox, oy) = _tileAt(14, 34.05, -118.25); // Los Angeles
      expect(_hosted.covers(14, ox, oy), isFalse);
      // A z4 tile is far bigger than the region: fallback.
      final (lx, ly) = _tileAt(4, 33.7, -116.2);
      expect(_hosted.covers(4, lx, ly), isFalse);
    });

    test('privacy wording follows the config', () {
      expect(mapTilesPrivacyText(MapTileConfig.fromValues()),
          'two hosts: tile.openstreetmap.org for map tiles');
      expect(mapTilesPrivacyText(_hosted),
          contains('CloudFront) inside the Coachella Valley'));
      expect(MapTileConfig.fromValues().tileServersPhrase, 'OpenStreetMap');
      expect(_hosted.tileServersPhrase,
          'OpenStreetMap, or our map server in the Coachella Valley');
      // A local test file is not a server.
      expect(
          mapTilesPrivacyText(
              MapTileConfig.fromValues(terrain: 'file:///tmp/t.pmtiles')),
          startsWith('two hosts'));
    });

    test('terrain covers the hosted region only', () {
      expect(_hosted.terrainCovers(const LatLng(33.7, -116.2)), isTrue);
      expect(_hosted.terrainCovers(const LatLng(37.77, -122.42)), isFalse);
      // Unbounded (a local file): everywhere; no terrain: nowhere.
      expect(
          MapTileConfig.fromValues(terrain: 'file:///t.pmtiles')
              .terrainCovers(const LatLng(0, 0)),
          isTrue);
      expect(
          MapTileConfig.fromValues().terrainCovers(const LatLng(33.7, -116.2)),
          isFalse);
    });

    test('tile bounds are the Web Mercator tile', () {
      final b = MapTileConfig.tileBounds(1, 0, 0);
      expect(b.west, -180);
      expect(b.east, 0);
      expect(b.south, closeTo(0, 1e-9));
      expect(b.north, closeTo(85.0511, 1e-4));
    });

    test('credits per style', () {
      expect(_hosted.creditsFor(MapStyle.standard),
          [MapTileConfig.osmCredit, MapTileConfig.openMapTilesCredit]);
      expect(_hosted.creditsFor(MapStyle.terrain), [
        MapTileConfig.osmCredit,
        MapTileConfig.openMapTilesCredit,
        MapTileConfig.hillshadeCredit,
      ]);
      expect(MapTileConfig.hillshadeCredit.text,
          'Hillshade: USGS 3DEP / NASA SRTM');
    });

    test('tile provider: archive inside, fallback outside', () {
      final fallback = NetworkTileProvider();
      final p = PmTilesTileProvider(files: [
        for (final r in _hosted.regionsWith(HostedTileKind.streets))
          PmTilesRegionFile(url: r.streetsUrl!, covers: r.covers),
      ], fallback: fallback);
      addTearDown(p.dispose);
      final layer = TileLayer(urlTemplate: _hosted.osmFallbackUrl);
      final (ix, iy) = _tileAt(14, 33.7, -116.2);
      expect(p.getImage(TileCoordinates(ix, iy, 14), layer),
          isA<PmTilesImageProvider>());
      final (ox, oy) = _tileAt(14, 34.05, -118.25);
      expect(p.getImage(TileCoordinates(ox, oy, 14), layer),
          isNot(isA<PmTilesImageProvider>()));
    });

    testWidgets(
        'tile provider: the second region serves a tile the first lacks',
        (tester) async {
      await tester.runAsync(() async {
        // A 2x2 PNG, told apart from the 1x1 transparent tile.
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 2, 2),
            Paint()..color = const Color(0xff00ff00));
        final img = await recorder.endRecording().toImage(2, 2);
        final png = (await img.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        final (x, y) = _tileAt(10, 37.0, -94.0);
        final id = PmTilesArchive.zxyToTileId(10, x, y);
        final files = {
          'mem://first': _pmtiles({
            PmTilesArchive.zxyToTileId(10, x + 1, y): png,
          }),
          'mem://second': _pmtiles({id: png}),
        };
        final opened = <String>[];
        bool everywhere(int z, int x, int y) => true;
        final p = PmTilesTileProvider(
          files: [
            PmTilesRegionFile(url: 'mem://first', covers: everywhere),
            PmTilesRegionFile(url: 'mem://second', covers: everywhere),
          ],
          openSource: (url) {
            opened.add(url);
            return _MemorySource(files[url]!);
          },
        );
        addTearDown(p.dispose);

        Future<ui.Image> load(int z, int x, int y) {
          final completer = Completer<ui.Image>();
          final image =
              p.getImage(TileCoordinates(x, y, z), TileLayer(urlTemplate: 'x'));
          expect(image, isA<PmTilesImageProvider>());
          final stream = image.resolve(ImageConfiguration.empty);
          stream.addListener(ImageStreamListener(
              (info, _) => completer.complete(info.image),
              onError: completer.completeError));
          return completer.future;
        }

        expect((await load(10, x, y)).width, 2);
        expect(opened, ['mem://first', 'mem://second']);
        // In neither file: transparent (no fallback for overlays).
        expect((await load(10, x, y + 1)).width, 1);
      });
    });

    testWidgets('tile provider: a missing file is asked for once, not per tile',
        (tester) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 2, 2),
            Paint()..color = const Color(0xff00ff00));
        final img = await recorder.endRecording().toImage(2, 2);
        final png = (await img.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        final (x, y) = _tileAt(10, 34.0, -117.0);
        final good = _pmtiles({
          PmTilesArchive.zxyToTileId(10, x, y): png,
          PmTilesArchive.zxyToTileId(10, x + 1, y): png,
          PmTilesArchive.zxyToTileId(10, x + 2, y): png,
        });
        var now = DateTime(2026, 11, 9, 12);
        final opened = <String>[];
        bool everywhere(int z, int x, int y) => true;
        final p = PmTilesTileProvider(
          files: [
            // Like v2/west before its upload: the server refuses it.
            PmTilesRegionFile(url: 'mem://missing', covers: everywhere),
            PmTilesRegionFile(url: 'mem://socal', covers: everywhere),
          ],
          clock: () => now,
          openSource: (url) {
            opened.add(url);
            return url == 'mem://missing'
                ? _FailingSource()
                : _MemorySource(good);
          },
        );
        addTearDown(p.dispose);

        Future<int> width(int x, int y) {
          final completer = Completer<int>();
          p
              .getImage(TileCoordinates(x, y, 10), TileLayer(urlTemplate: 'x'))
              .resolve(ImageConfiguration.empty)
              .addListener(ImageStreamListener(
                  (info, _) => completer.complete(info.image.width),
                  onError: completer.completeError));
          return completer.future;
        }

        expect(await width(x, y), 2);
        expect(await width(x + 1, y), 2);
        expect(opened.where((u) => u == 'mem://missing'), hasLength(1));
        // Once the wait is over it is tried again (it may be uploaded now).
        now = now.add(const Duration(minutes: 6));
        // A tile not loaded before (the image cache would answer that one).
        expect(await width(x + 2, y), 2);
        expect(opened.where((u) => u == 'mem://missing'), hasLength(2));
      });
    });
  });

  group('map style pref', () {
    test('round-trips through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      expect(c.read(mapStyleProvider), MapStyle.standard);
      c.read(mapStyleProvider.notifier).set(MapStyle.terrain);
      expect(c.read(mapStyleProvider), MapStyle.terrain);
      expect(prefs.getString(AppConstants.prefMapStyle), 'terrain');

      final c2 = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(c2.dispose);
      expect(c2.read(mapStyleProvider), MapStyle.terrain);
    });

    test('unknown stored value falls back to standard', () {
      expect(MapStyle.fromName('satellite'), MapStyle.standard);
      expect(MapStyle.fromName(null), MapStyle.standard);
    });
  });

  group('BaseMapLayers', () {
    Future<void> pump(WidgetTester tester, MapTileConfig config,
        {MapStyle style = MapStyle.standard,
        LatLng center = const LatLng(33.7, -116.2)}) async {
      SharedPreferences.setMockInitialValues(
          {AppConstants.prefMapStyle: style.name});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mapTileConfigProvider.overrideWithValue(config),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Stack(children: [
              FlutterMap(
                // A new map per centre: a re-pumped map keeps its camera.
                key: ValueKey('${style.name}@$center'),
                options: MapOptions(initialCenter: center, initialZoom: 12),
                children: const [BaseMapLayers(), BaseMapAttribution()],
              ),
              const Positioned(right: 0, bottom: 60, child: MapStyleButton()),
            ]),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('with no hosted URLs it is the plain OSM TileLayer',
        (tester) async {
      await pump(tester, MapTileConfig.fromValues(), style: MapStyle.terrain);
      final layers = tester.widgetList<TileLayer>(find.byType(TileLayer));
      expect(layers, hasLength(1));
      expect(layers.single.urlTemplate,
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
      expect(layers.single.tileProvider, isA<NetworkTileProvider>());
      // No style to switch, but the appearance is still there.
      await tester.tap(find.byIcon(Icons.layers));
      await tester.pumpAndSettle();
      expect(find.text('Terrain'), findsNothing);
      expect(find.text('Night'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.byType(RichAttributionWidget), findsOneWidget);
    });

    testWidgets('hosted terrain adds the hillshade overlay and the switcher',
        (tester) async {
      await pump(tester, _hosted, style: MapStyle.terrain);
      final layers =
          tester.widgetList<TileLayer>(find.byType(TileLayer)).toList();
      expect(layers, hasLength(2));
      expect(layers[0].tileProvider, isA<PmTilesTileProvider>());
      expect(layers[1].tileProvider, isA<PmTilesTileProvider>());
      expect(find.byIcon(Icons.layers), findsOneWidget);

      await tester.tap(find.byIcon(Icons.layers));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standard'));
      await tester.pumpAndSettle();
      expect(find.byType(TileLayer), findsOneWidget);
    });

    testWidgets('Bright softens the hillshade, Night dims the base map',
        (tester) async {
      await pump(tester, _hosted, style: MapStyle.terrain);
      Opacity shade() => tester.widget<Opacity>(find.ancestor(
          of: find.byKey(const ValueKey('base-hillshade')),
          matching: find.byType(Opacity)));
      expect(shade().opacity, 1.0);
      expect(find.byType(ColorFiltered), findsNothing);

      await tester.tap(find.byIcon(Icons.layers));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('appearance-bright')));
      await tester.pumpAndSettle();
      expect(shade().opacity, lessThan(1.0));
      expect(find.byType(ColorFiltered), findsNothing);

      await tester.tap(find.byIcon(Icons.layers));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('appearance-night')));
      await tester.pumpAndSettle();
      expect(shade().opacity, 1.0);
      expect(find.byType(ColorFiltered), findsWidgets);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppConstants.prefAppearance), 'night');
    });

    testWidgets('Terrain outside the hosted region says there is no hillshade',
        (tester) async {
      await pump(tester, _hosted,
          style: MapStyle.terrain, center: const LatLng(37.77, -122.42));
      expect(find.text(MapTileConfig.terrainGapHint), findsOneWidget);
      // Inside the region, or on Standard, nothing to explain.
      await pump(tester, _hosted, style: MapStyle.terrain);
      expect(find.text(MapTileConfig.terrainGapHint), findsNothing);
      await pump(tester, _hosted,
          style: MapStyle.standard, center: const LatLng(37.77, -122.42));
      expect(find.text(MapTileConfig.terrainGapHint), findsNothing);
    });

    testWidgets('credit chip lists the credits for the style', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          mapTileConfigProvider.overrideWithValue(MapTileConfig.fromValues()),
        ],
        child: const MaterialApp(home: Scaffold(body: MapCreditChip())),
      ));
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    });
  });
}
