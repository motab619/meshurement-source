// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/tiles/pmtiles_tile_provider.dart';
import '../../../providers.dart';
import '../../../services/field_report/field_report_data.dart';
import '../../../utils/map_tiles.dart';
import 'report_painters.dart';
import 'report_style.dart';

/// What sits under the route on a Field Report card. Anything but [plain]
/// draws the route north-up at its real place (no rotation), so the card
/// shows where it was recorded; Hide base area still applies.
enum ReportBackground {
  plain('Plain'),
  streets('Streets'),
  terrain('Terrain');

  const ReportBackground(this.label);
  final String label;

  bool get isMap => this != plain;

  /// The app map style whose tiles and credits this uses.
  MapStyle get mapStyle =>
      this == terrain ? MapStyle.terrain : MapStyle.standard;

  static ReportBackground fromName(String? name) => values
      .firstWhere((b) => b.name == name, orElse: () => ReportBackground.plain);
}

/// Makes the report sheet's tile loader (tests swap in fake tile sources).
final reportTileLoaderFactoryProvider = Provider<ReportTileLoader Function()>(
    (ref) => () => ReportTileLoader(ref.read(mapTileConfigProvider)));

/// SharedPreferences key: the last background picked in the report sheet.
const reportBackgroundPref = 'field_report_background';

/// The map behind a card's route: where the route's origin is, which
/// background, and the loader that fetches the tiles.
class ReportBasemap {
  const ReportBasemap({
    required this.origin,
    required this.background,
    required this.loader,
  });

  final GeoPoint origin;
  final ReportBackground background;
  final ReportTileLoader loader;
}

/// The map for a card of [data], or null for the plain grid ([background]
/// plain, no [tiles] loader, or no known position).
ReportBasemap? reportBasemapFor(FieldReportData data,
    ReportBackground background, ReportTileLoader? tiles) {
  final origin = data.geoOrigin;
  if (!background.isMap || tiles == null || origin == null) return null;
  return ReportBasemap(origin: origin, background: background, loader: tiles);
}

/// One tile image and where it lands in the route box.
class ReportTile {
  ReportTile(this.image, this.rect);
  final ui.Image image;
  final Rect rect;
}

/// The tiles for one route box: streets, then the hillshade on top.
class ReportTiles {
  ReportTiles(this.layers);
  final List<List<ReportTile>> layers;
  bool get isEmpty => layers.every((l) => l.isEmpty);
}

const _earthCircumferenceM = 40075016.686;
const _metresPerDegree = 111320.0; // the same as the report's projection
const _tilePx = 256.0;

/// Where tiles for a [RouteView] come from, in Web Mercator. Pure maths, so
/// it is tested on its own.
class ReportTileGrid {
  ReportTileGrid._(this.zoom, this.f, this.gx, this.gy, this.size);

  /// Tiles for [view] around [origin] (the report's (0, 0)): the lowest
  /// zoom whose tiles are at least as sharp as the box, at most [maxZoom],
  /// stepping out while more than [maxTiles] would be needed.
  factory ReportTileGrid.of(RouteView view, GeoPoint origin,
      {int maxZoom = 18, int maxTiles = 80}) {
    final lat = origin.lat + view.cy / _metresPerDegree;
    final lon = origin.lon +
        view.cx / (_metresPerDegree * math.cos(origin.lat * math.pi / 180));
    final cosLat = math.cos(lat * math.pi / 180);
    var z = (math.log(view.scale * _earthCircumferenceM * cosLat / _tilePx) /
            math.ln2)
        .ceil()
        .clamp(0, maxZoom);
    while (true) {
      final grid = ReportTileGrid._at(z, view, lat, lon, cosLat);
      if (grid.tiles.length <= maxTiles || z == 0) return grid;
      z--;
    }
  }

  factory ReportTileGrid._at(
      int z, RouteView view, double lat, double lon, double cosLat) {
    final world = _tilePx * math.pow(2, z);
    final mpp = _earthCircumferenceM * cosLat / world; // metres per tile px
    final f = view.scale * mpp; // box px per tile px
    final gx = (lon + 180) / 360 * world;
    final r = lat * math.pi / 180;
    final gy =
        (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * world;
    return ReportTileGrid._(z, f, gx, gy, view.size);
  }

  final int zoom;

  /// Box pixels per tile pixel.
  final double f;

  /// The box centre in global Mercator pixels at [zoom].
  final double gx, gy;
  final Size size;

  /// Every tile the box needs, as (x, y) at [zoom] (x not wrapped).
  List<(int, int)> get tiles {
    final halfW = size.width / 2 / f, halfH = size.height / 2 / f;
    final x0 = ((gx - halfW) / _tilePx).floor(),
        x1 = ((gx + halfW) / _tilePx).floor();
    final n = 1 << zoom;
    final y0 = math.max(0, ((gy - halfH) / _tilePx).floor()),
        y1 = math.min(n - 1, ((gy + halfH) / _tilePx).floor());
    return [
      for (var y = y0; y <= y1; y++)
        for (var x = x0; x <= x1; x++) (x, y),
    ];
  }

  /// Where tile ([x], [y]) lands in the box.
  Rect rectOf(int x, int y) => Rect.fromLTWH(
        size.width / 2 + (x * _tilePx - gx) * f,
        size.height / 2 + (y * _tilePx - gy) * f,
        _tilePx * f,
        _tilePx * f,
      );
}

/// Fetches and caches the tiles for report cards from the app's own tile
/// sources (hosted regions first, then OpenStreetMap; hillshade only where
/// hosted). Owned by the report sheet: [idle] lets Share wait until every
/// tile is in, and [dispose] frees the images.
class ReportTileLoader {
  /// [streets] and [terrain] replace the app's tile sources (tests).
  ReportTileLoader(
    this.config, {
    this.tileTimeout = const Duration(seconds: 15),
    TileProvider? streets,
    TileProvider? terrain,
    @visibleForTesting this.fetchOverride,
  })  : _streets = streets,
        _terrain = terrain,
        _options = TileLayer(
          urlTemplate: config.osmFallbackUrl,
          userAgentPackageName: MapTileConfig.userAgentPackageName,
        );

  final MapTileConfig config;
  final Duration tileTimeout;

  /// Tests: returns a ready image instead of decoding one from [TileProvider].
  final Future<ui.Image?> Function(TileProvider p, TileCoordinates c)?
      fetchOverride;
  final TileLayer _options;
  final _cache = <String, Future<ReportTiles>>{};
  final _inFlight = <Future<ReportTiles>>{};
  final _images = <ui.Image>[];
  TileProvider? _streets, _terrain;
  bool _disposed = false;

  TileProvider get _streetsProvider => _streets ??= () {
        final fallback = NetworkTileProvider(headers: {
          'User-Agent': 'flutter_map (${MapTileConfig.userAgentPackageName})',
        });
        final regions = config.regionsWith(HostedTileKind.streets);
        if (regions.isEmpty) return fallback;
        return PmTilesTileProvider(files: [
          for (final r in regions)
            PmTilesRegionFile(
                url: r.urlFor(HostedTileKind.streets)!, covers: r.covers),
        ], fallback: fallback);
      }();

  TileProvider? get _terrainProvider {
    if (_terrain != null) return _terrain;
    final regions = config.regionsWith(HostedTileKind.terrain);
    if (regions.isEmpty) return null;
    return _terrain ??= PmTilesTileProvider(files: [
      for (final r in regions)
        PmTilesRegionFile(
            url: r.urlFor(HostedTileKind.terrain)!, covers: r.covers),
    ]);
  }

  /// Completes when every tile asked for so far has loaded (or failed).
  Future<void> get idle => Future.wait(_inFlight.toList()).then((_) {});

  /// Tiles for a box of [view] around [origin].
  Future<ReportTiles> load(
      RouteView view, GeoPoint origin, ReportBackground background) {
    final grid = ReportTileGrid.of(view, origin);
    final key = '${background.name}|${grid.zoom}|'
        '${grid.gx.toStringAsFixed(1)}|${grid.gy.toStringAsFixed(1)}|'
        '${grid.f.toStringAsFixed(4)}|${view.size.width}x${view.size.height}';
    return _cache[key] ??= () {
      final f = _load(grid, background);
      _inFlight.add(f);
      f.whenComplete(() => _inFlight.remove(f));
      return f;
    }();
  }

  Future<ReportTiles> _load(ReportTileGrid grid, ReportBackground b) async {
    final terrain = b == ReportBackground.terrain ? _terrainProvider : null;
    final layers = await Future.wait([
      _layer(grid, _streetsProvider),
      if (terrain != null) _layer(grid, terrain),
    ]);
    return ReportTiles(layers);
  }

  Future<List<ReportTile>> _layer(ReportTileGrid grid, TileProvider p) async {
    final n = 1 << grid.zoom;
    final tiles = await Future.wait([
      for (final (x, y) in grid.tiles)
        _image(p, TileCoordinates(x % n, y, grid.zoom)).then(
            (img) => img == null ? null : ReportTile(img, grid.rectOf(x, y))),
    ]);
    return [
      for (final t in tiles)
        if (t != null) t
    ];
  }

  Future<ui.Image?> _image(TileProvider p, TileCoordinates c) async {
    if (_disposed) return null;
    final override = fetchOverride;
    if (override != null) {
      final img = await override(p, c);
      if (img != null) _images.add(img);
      return img;
    }
    final done = Completer<ui.Image?>();
    final stream = p.getImage(c, _options).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (!done.isCompleted) done.complete(info.image.clone());
      info.dispose();
    }, onError: (_, __) {
      if (!done.isCompleted) done.complete(null);
    });
    stream.addListener(listener);
    final img = await done.future
        .timeout(tileTimeout, onTimeout: () => null)
        .whenComplete(() => stream.removeListener(listener));
    if (img != null) {
      if (_disposed) {
        img.dispose();
        return null;
      }
      _images.add(img);
    }
    return img;
  }

  void dispose() {
    _disposed = true;
    _streets?.dispose();
    _terrain?.dispose();
    for (final i in _images) {
      i.dispose();
    }
    _images.clear();
    _cache.clear();
  }
}

/// Paints [tiles] and a dark veil, so the coloured dots stay the loudest
/// thing on the card.
class ReportTilesPainter extends CustomPainter {
  ReportTilesPainter(this.tiles);
  final ReportTiles? tiles;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
        rect, const Radius.circular(ReportStyle.radius)));
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (final layer in tiles?.layers ?? const <List<ReportTile>>[]) {
      for (final t in layer) {
        canvas.drawImageRect(
            t.image,
            Rect.fromLTWH(
                0, 0, t.image.width.toDouble(), t.image.height.toDouble()),
            // A hair larger, so no seam shows between tiles.
            t.rect.inflate(0.5),
            paint);
      }
    }
    canvas.drawRect(
        rect, Paint()..color = ReportStyle.panel.withValues(alpha: 0.55));
    canvas.restore();
  }

  @override
  bool shouldRepaint(ReportTilesPainter old) => old.tiles != tiles;
}

/// The map under a route box: loads the tiles for its size and paints them
/// with the map credit in the corner.
class ReportBasemapLayer extends StatelessWidget {
  const ReportBasemapLayer({
    super.key,
    required this.basemap,
    required this.frame,
    this.scale = 1,
  });

  final ReportBasemap basemap;
  final RouteFrame frame;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final credits = basemap.loader.config
        .creditsFor(basemap.background.mapStyle)
        .map((c) => c.text)
        .join(' · ');
    return LayoutBuilder(builder: (context, box) {
      final view = RouteView(frame, box.biggest);
      return Stack(children: [
        Positioned.fill(
          child: FutureBuilder<ReportTiles>(
            future:
                basemap.loader.load(view, basemap.origin, basemap.background),
            builder: (context, snap) =>
                CustomPaint(painter: ReportTilesPainter(snap.data)),
          ),
        ),
        Positioned(
          left: 14 * scale,
          bottom: 10 * scale,
          right: 220 * scale, // clear of the scale bar
          child: Align(
            alignment: Alignment.bottomLeft,
            child: ReportMapLabel(
              scale: scale,
              child: Text(credits,
                  key: const ValueKey('field-report-map-credit'),
                  maxLines: 2,
                  style: ReportStyle.sans(15 * scale, color: ReportStyle.soft)),
            ),
          ),
        ),
      ]);
    });
  }
}

/// Dark backing for text over map tiles (note, credit), so it reads on a
/// light street map.
class ReportMapLabel extends StatelessWidget {
  const ReportMapLabel({super.key, required this.child, this.scale = 1});
  final Widget child;
  final double scale;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: ReportStyle.panel.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6 * scale),
        ),
        child: Padding(
          padding:
              EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
          child: child,
        ),
      );
}
