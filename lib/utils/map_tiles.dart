// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Base map look, picked per user with the layers button on the maps.
enum MapStyle {
  /// Streets (self-hosted raster PMTiles inside the covered region, OSM
  /// tiles elsewhere).
  standard('Standard'),

  /// Streets plus hillshade (and contours when built): line of sight
  /// matters for LoRa.
  terrain('Terrain');

  const MapStyle(this.label);
  final String label;

  static MapStyle fromName(String? name) => MapStyle.values
      .firstWhere((s) => s.name == name, orElse: () => MapStyle.standard);
}

/// One credit line under the map ("© OpenStreetMap contributors"...).
class MapCredit {
  const MapCredit(this.text, [this.url]);
  final String text;
  final String? url;

  @override
  bool operator ==(Object other) =>
      other is MapCredit && other.text == text && other.url == url;

  @override
  int get hashCode => Object.hash(text, url);

  @override
  String toString() => text;
}

/// The three kinds of hosted tile file.
enum HostedTileKind { streets, terrain, contours }

/// One hosted region: its own streets, hillshade and contour PMTiles files
/// and the box they were built for.
///
/// The box is generous (regions overlap at state lines); the files only have
/// tiles inside the region's state outlines, so a tile the box covers may
/// still be missing from the file, and the next region (or the fallback) is
/// tried.
class HostedRegion {
  const HostedRegion({
    required this.name,
    this.streetsUrl,
    this.terrainUrl,
    this.contoursUrl,
    this.boundsSWNE,
    this.minZoom = 0,
  });

  /// Short id, e.g. 'west' (file names are `<name>-streets.pmtiles`...).
  final String name;

  /// PMTiles URLs (https://, http://localhost or file://); null = not built.
  final String? streetsUrl;
  final String? terrainUrl;
  final String? contoursUrl;

  /// [south, west, north, east], or null for unbounded (a local test file).
  final List<double>? boundsSWNE;

  /// Tiles below this zoom are never looked up here.
  final int minZoom;

  String? urlFor(HostedTileKind kind) => switch (kind) {
        HostedTileKind.streets => streetsUrl,
        HostedTileKind.terrain => terrainUrl,
        HostedTileKind.contours => contoursUrl,
      };

  Iterable<String> get urls =>
      [streetsUrl, terrainUrl, contoursUrl].whereType<String>();

  LatLngBounds? get bounds {
    final b = boundsSWNE;
    if (b == null || b.length != 4) return null;
    return LatLngBounds(LatLng(b[0], b[1]), LatLng(b[2], b[3]));
  }

  /// Whether [point] is inside the box (always, when unbounded).
  bool contains(LatLng point) {
    final b = boundsSWNE;
    if (b == null || b.length != 4) return true;
    return point.latitude >= b[0] &&
        point.latitude <= b[2] &&
        point.longitude >= b[1] &&
        point.longitude <= b[3];
  }

  /// Whether tile [z]/[x]/[y] lies entirely inside the box, i.e. may be in
  /// this region's files.
  bool covers(int z, int x, int y) {
    if (z < minZoom) return false;
    final b = boundsSWNE;
    if (b == null || b.length != 4) return true;
    final t = MapTileConfig.tileBounds(z, x, y);
    return t.south >= b[0] &&
        t.north <= b[2] &&
        t.west >= b[1] &&
        t.east <= b[3];
  }
}

/// Where map tiles come from. Built by `tool/tiles/` (see its README) and
/// hosted on S3 + CloudFront, one set of files per region in
/// [hostedRegions]. For local testing the list can be replaced by a single
/// region with `--dart-define=TILES_STREETS_URL=file:///path/to/x.pmtiles`
/// etc.
class MapTileConfig {
  const MapTileConfig({
    this.regions = const [],
    this.regionName,
    this.osmFallbackUrl = osmTileUrl,
  });

  // ─── The hosted files (tool/tiles/README.md) ───

  static const _v2 = 'https://d13u6w4g5rrbl6.cloudfront.net/v2';

  /// The hosted regions, in lookup order: a tile is taken from the first
  /// region whose box contains it and whose file has it.
  static const List<HostedRegion> hostedRegions = [
    HostedRegion(
      name: 'west',
      streetsUrl: '$_v2/west-streets.pmtiles',
      terrainUrl: '$_v2/west-terrain.pmtiles',
      contoursUrl: '$_v2/west-contours.pmtiles',
      boundsSWNE: [31.20, -124.90, 49.10, -102.00],
      minZoom: 8,
    ),
    HostedRegion(
      name: 'midwest',
      streetsUrl: '$_v2/midwest-streets.pmtiles',
      terrainUrl: '$_v2/midwest-terrain.pmtiles',
      contoursUrl: '$_v2/midwest-contours.pmtiles',
      boundsSWNE: [35.90, -104.10, 49.45, -80.40],
      minZoom: 8,
    ),
    HostedRegion(
      name: 'south',
      streetsUrl: '$_v2/south-streets.pmtiles',
      terrainUrl: '$_v2/south-terrain.pmtiles',
      contoursUrl: '$_v2/south-contours.pmtiles',
      boundsSWNE: [24.40, -106.70, 40.70, -75.00],
      minZoom: 8,
    ),
    HostedRegion(
      name: 'northeast',
      streetsUrl: '$_v2/northeast-streets.pmtiles',
      terrainUrl: '$_v2/northeast-terrain.pmtiles',
      contoursUrl: '$_v2/northeast-contours.pmtiles',
      boundsSWNE: [38.80, -80.60, 47.50, -66.90],
      minZoom: 8,
    ),
    HostedRegion(
      name: 'hawaii',
      streetsUrl: '$_v2/hawaii-streets.pmtiles',
      terrainUrl: '$_v2/hawaii-terrain.pmtiles',
      contoursUrl: '$_v2/hawaii-contours.pmtiles',
      boundsSWNE: [18.85, -160.30, 22.30, -154.75],
      minZoom: 8,
    ),
    // 100-mile circles around Anchorage, Fairbanks and Juneau; the files
    // only have tiles inside the circles.
    HostedRegion(
      name: 'alaska',
      streetsUrl: '$_v2/alaska-streets.pmtiles',
      terrainUrl: '$_v2/alaska-terrain.pmtiles',
      contoursUrl: '$_v2/alaska-contours.pmtiles',
      boundsSWNE: [56.80, -153.00, 66.30, -131.60],
      minZoom: 8,
    ),
  ];

  /// Shown in the About screen ("…inside the United States").
  static const String hostedRegionName = 'the United States';

  // ─────────────────────────────────────────────────────────────────────

  static const osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const osmCopyrightUrl = 'https://www.openstreetmap.org/copyright';
  static const userAgentPackageName = 'com.andybrunker.meshAnalyzer';

  static const osmCredit =
      MapCredit('© OpenStreetMap contributors', osmCopyrightUrl);
  static const openMapTilesCredit =
      MapCredit('© OpenMapTiles', 'https://openmaptiles.org/');
  static const hillshadeCredit = MapCredit('Hillshade: USGS 3DEP / NASA SRTM',
      'https://www.usgs.gov/3d-elevation-program');

  /// The hosted regions, in lookup order (empty: OSM tiles everywhere).
  final List<HostedRegion> regions;

  /// Where the hosted tiles are, for the privacy wording.
  final String? regionName;
  final String osmFallbackUrl;

  /// The app's configuration: [hostedRegions], or a single region from
  /// `--dart-define` (TILES_STREETS_URL, TILES_TERRAIN_URL,
  /// TILES_CONTOURS_URL, TILES_BOUNDS="s,w,n,e", TILES_REGION) when any of
  /// the URLs is given.
  static final MapTileConfig current = _fromDefines(
        streets: _define(const String.fromEnvironment('TILES_STREETS_URL')),
        terrain: _define(const String.fromEnvironment('TILES_TERRAIN_URL')),
        contours: _define(const String.fromEnvironment('TILES_CONTOURS_URL')),
        boundsSWNE: _parseBounds(const String.fromEnvironment('TILES_BOUNDS')),
        region: _define(const String.fromEnvironment('TILES_REGION')),
      ) ??
      const MapTileConfig(regions: hostedRegions, regionName: hostedRegionName);

  static MapTileConfig? _fromDefines({
    String? streets,
    String? terrain,
    String? contours,
    List<double>? boundsSWNE,
    String? region,
  }) =>
      streets == null && terrain == null && contours == null
          ? null
          : fromValues(
              streets: streets,
              terrain: terrain,
              contours: contours,
              boundsSWNE: boundsSWNE,
              region: region);

  /// A single region (or nothing hosted, when every URL is null).
  static MapTileConfig fromValues({
    String? streets,
    String? terrain,
    String? contours,
    List<double>? boundsSWNE,
    String? region,
  }) {
    final b = boundsSWNE;
    return MapTileConfig(
      regions: streets == null && terrain == null && contours == null
          ? const []
          : [
              HostedRegion(
                name: region ?? 'local',
                streetsUrl: streets,
                terrainUrl: terrain,
                contoursUrl: contours,
                boundsSWNE: b == null || b.length != 4 ? null : b,
              ),
            ],
      regionName: region,
    );
  }

  static String? _define(String v) => v.trim().isEmpty ? null : v.trim();

  static List<double>? _parseBounds(String v) {
    final parts = v.split(',').map((s) => double.tryParse(s.trim())).toList();
    if (parts.length != 4 || parts.contains(null)) return null;
    return parts.cast<double>();
  }

  /// Shown over a Terrain map whose centre is outside every region with
  /// hillshade: there the hillshade and contours are simply absent and the
  /// map looks like Standard, so say why.
  static const terrainGapHint =
      'No hillshade here (outside the hosted map area)';

  /// One phrase for the privacy switches: who serves tiles and where.
  String get tileServersPhrase => anyRemoteHosted
      ? 'OpenStreetMap, or our map server in ${regionName ?? 'the covered region'}'
      : 'OpenStreetMap';

  /// Regions that have a [kind] file, in lookup order.
  List<HostedRegion> regionsWith(HostedTileKind kind) => [
        for (final r in regions)
          if (r.urlFor(kind) != null) r
      ];

  /// Whether a Terrain map centred on [center] shows the hillshade at all:
  /// some region with hillshade contains it (an unbounded one always does).
  bool terrainCovers(LatLng center) =>
      regionsWith(HostedTileKind.terrain).any((r) => r.contains(center));

  /// Any self-hosted tiles at all (the About copy changes with this).
  bool get anyHosted => regions.any((r) => r.urls.isNotEmpty);

  /// Hosted URLs other than local test files (for the privacy wording).
  bool get anyRemoteHosted =>
      regions.expand((r) => r.urls).any((u) => !u.startsWith('file:'));

  /// Terrain has something to show (otherwise the style switcher hides).
  bool get terrainAvailable => regionsWith(HostedTileKind.terrain).isNotEmpty;

  /// The style actually drawn: Terrain falls back to Standard when there is
  /// no hillshade to show.
  MapStyle effectiveStyle(MapStyle chosen) =>
      chosen == MapStyle.terrain && !terrainAvailable
          ? MapStyle.standard
          : chosen;

  /// Credits for [style], in display order.
  List<MapCredit> creditsFor(MapStyle style) => [
        osmCredit,
        if (regionsWith(HostedTileKind.streets).isNotEmpty) openMapTilesCredit,
        if (effectiveStyle(style) == MapStyle.terrain) hillshadeCredit,
      ];

  /// The regions whose [kind] file may have tile [z]/[x]/[y] (the tile lies
  /// entirely inside their box), in lookup order. Empty: the fallback.
  List<HostedRegion> candidatesFor(HostedTileKind kind, int z, int x, int y) =>
      [
        for (final r in regionsWith(kind))
          if (r.covers(z, x, y)) r
      ];

  /// Whether any region's box covers tile [z]/[x]/[y] (any kind).
  bool covers(int z, int x, int y) => regions.any((r) => r.covers(z, x, y));

  /// Lat/lon bounds of a Web Mercator (XYZ) tile.
  static LatLngBounds tileBounds(int z, int x, int y) {
    final n = math.pow(2, z).toDouble();
    double lon(int tx) => tx / n * 360.0 - 180.0;
    double lat(int ty) {
      final r = math.pi * (1 - 2 * ty / n);
      return math.atan((math.exp(r) - math.exp(-r)) / 2) * 180.0 / math.pi;
    }

    return LatLngBounds(LatLng(lat(y + 1), lon(x)), LatLng(lat(y), lon(x + 1)));
  }
}
