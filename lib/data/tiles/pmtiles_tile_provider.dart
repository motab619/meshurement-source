// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import 'pmtiles_archive.dart';

/// One PMTiles file a [PmTilesTileProvider] may read a tile from: its URL
/// and which tiles it may have (the box it was built for).
class PmTilesRegionFile {
  const PmTilesRegionFile({required this.url, required this.covers});

  /// file://, a path, or http(s):// URL of the .pmtiles file.
  final String url;

  /// Whether tile z/x/y lies inside the region the file was built for.
  final bool Function(int z, int x, int y) covers;
}

/// flutter_map [TileProvider] for raster PMTiles files (local or on
/// CloudFront), one per hosted region.
///
/// Per tile: the files whose region covers it are tried in [files] order
/// (zooms past an archive's max zoom are cut from the ancestor tile, so the
/// map can zoom in further than the file goes); the first that has the tile
/// wins. When none covers it, none has it, or none can be read, the tile
/// comes from [fallback] (OSM for streets), or is left transparent
/// (overlays).
class PmTilesTileProvider extends TileProvider {
  PmTilesTileProvider({
    required this.files,
    this.fallback,
    this.maxOverzoom = 6,
    http.Client? httpClient,
    PmTilesSource Function(String url)? openSource,
    this.retryAfter = const Duration(minutes: 5),
    DateTime Function()? clock,
    super.headers,
  })  : _httpClient = httpClient,
        _openSource = openSource,
        _clock = clock ?? DateTime.now;

  /// The region files, in lookup order.
  final List<PmTilesRegionFile> files;

  /// Tiles outside every region (e.g. a [NetworkTileProvider] with the
  /// TileLayer's OSM `urlTemplate`); null leaves them transparent.
  final TileProvider? fallback;

  /// How many zooms past the archive's max zoom are upscaled.
  final int maxOverzoom;
  final http.Client? _httpClient;

  /// Opens a file's bytes (tests inject an in-memory source).
  final PmTilesSource Function(String url)? _openSource;

  /// A file that failed to open (missing on the server, offline) is not
  /// asked for again until this long has passed, so a missing region file
  /// costs one request, not one per tile.
  final Duration retryAfter;
  final DateTime Function() _clock;

  /// One per URL, opened lazily, shared by every tile, retried after a
  /// failure once [retryAfter] has passed.
  final _archives = <String, Future<PmTilesArchive>>{};
  final _failedAt = <String, DateTime>{};
  bool _disposed = false;

  Future<PmTilesArchive> archive(String url) {
    if (_disposed) return Future.error(StateError('provider disposed'));
    final failed = _failedAt[url];
    if (failed != null && _clock().difference(failed) < retryAfter) {
      return Future.error(PmTilesException('$url failed recently'));
    }
    return _archives[url] ??= PmTilesArchive.open(
      _openSource?.call(url) ??
          PmTilesSource.fromUrl(url, client: _httpClient, headers: headers),
    ).then((a) {
      _failedAt.remove(url);
      return a;
    }, onError: (Object e, StackTrace st) {
      _archives.remove(url);
      _failedAt[url] = _clock();
      Error.throwWithStackTrace(e, st);
    });
  }

  // Forwarded to the fallback (NetworkTileProvider aborts obsolete requests).
  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      getImageWithCancelLoadingSupport(
          coordinates, options, Completer<void>().future);

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    final z = coordinates.z, x = coordinates.x, y = coordinates.y;
    final urls = [
      for (final f in files)
        if (f.covers(z, x, y)) f.url
    ];
    if (urls.isNotEmpty) {
      return PmTilesImageProvider(
        provider: this,
        urls: urls,
        z: z,
        x: x,
        y: y,
        fallback: _fallbackImage(coordinates, options, cancelLoading),
      );
    }
    return _fallbackImage(coordinates, options, cancelLoading) ??
        MemoryImage(TileProvider.transparentImage);
  }

  ImageProvider? _fallbackImage(TileCoordinates coordinates, TileLayer options,
      Future<void> cancelLoading) {
    final fb = fallback;
    if (fb == null) return null;
    return fb.supportsCancelLoading
        ? fb.getImageWithCancelLoadingSupport(
            coordinates, options, cancelLoading)
        : fb.getImage(coordinates, options);
  }

  @override
  void dispose() {
    _disposed = true;
    fallback?.dispose();
    final open = _archives.values.toList();
    _archives.clear();
    for (final a in open) {
      a.then((x) => x.close(), onError: (_) {});
    }
    super.dispose();
  }
}

/// One tile from a [PmTilesTileProvider].
@immutable
class PmTilesImageProvider extends ImageProvider<PmTilesImageProvider> {
  const PmTilesImageProvider({
    required this.provider,
    required this.urls,
    required this.z,
    required this.x,
    required this.y,
    this.fallback,
  });

  final PmTilesTileProvider provider;

  /// The candidate files, tried in order.
  final List<String> urls;
  final int z, x, y;

  /// Used when no archive can be opened or has this tile.
  final ImageProvider? fallback;

  @override
  Future<PmTilesImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
      PmTilesImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_load(decode));
  }

  Future<ImageInfo> _load(ImageDecoderCallback decode) async {
    for (final url in urls) {
      try {
        final archive = await provider.archive(url);
        final h = archive.header;
        if (z < h.minZoom) continue;
        if (z <= h.maxZoom) {
          final bytes = await archive.getTile(z, x, y);
          if (bytes != null) {
            return ImageInfo(image: await _decode(bytes, decode));
          }
        } else if (z - h.maxZoom <= provider.maxOverzoom) {
          final dz = z - h.maxZoom;
          final bytes = await archive.getTile(h.maxZoom, x >> dz, y >> dz);
          if (bytes != null) {
            final parent = await _decode(bytes, decode);
            return ImageInfo(image: await _crop(parent, dz));
          }
        }
      } catch (e) {
        if (kDebugMode) print('PMTiles $url $z/$x/$y: $e');
      }
    }
    return _fallbackOrTransparent(decode);
  }

  /// The part of [parent] (dz zooms up) covering this tile, at the parent's
  /// pixel size.
  Future<ui.Image> _crop(ui.Image parent, int dz) async {
    final scale = 1 << dz;
    final w = parent.width.toDouble(), h = parent.height.toDouble();
    final sw = w / scale, sh = h / scale;
    final sx = (x - ((x >> dz) << dz)) * sw;
    final sy = (y - ((y >> dz) << dz)) * sh;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      parent,
      Rect.fromLTWH(sx, sy, sw, sh),
      Rect.fromLTWH(0, 0, w, h),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(parent.width, parent.height);
    } finally {
      picture.dispose();
      parent.dispose();
    }
  }

  Future<ImageInfo> _fallbackOrTransparent(ImageDecoderCallback decode) async {
    final fb = fallback;
    if (fb != null) {
      final completer = Completer<ImageInfo>();
      final stream = fb.resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        stream.removeListener(listener);
        completer.complete(info.clone());
      }, onError: (e, st) {
        stream.removeListener(listener);
        completer.completeError(e, st);
      });
      stream.addListener(listener);
      return completer.future;
    }
    return ImageInfo(
        image: await _decode(TileProvider.transparentImage, decode));
  }

  static Future<ui.Image> _decode(
      Uint8List bytes, ImageDecoderCallback decode) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PmTilesImageProvider &&
      listEquals(other.urls, urls) &&
      other.z == z &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(Object.hashAll(urls), z, x, y);
}
