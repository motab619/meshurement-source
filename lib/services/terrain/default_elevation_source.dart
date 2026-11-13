// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'elevation_cache.dart';
import 'elevation_source.dart';
import 'open_topo_data_source.dart';

/// The app's real elevation source: Open Topo Data behind a disk cache in
/// the application support directory (`elevation_cache/`). The directory is
/// resolved lazily on first use, so the provider can stay synchronous.
class DefaultElevationSource implements ElevationSource {
  /// [enabled] is the user's "Online terrain data" opt-in; it is checked on
  /// every call (before the cache too), and when false nothing is read or
  /// sent and [ElevationDisabled] is thrown.
  DefaultElevationSource({
    required bool Function() enabled,
    ElevationSource? inner,
    Future<Directory>? cacheDir,
  })  : _enabled = enabled,
        _inner = inner ?? OpenTopoDataSource(),
        _dir = cacheDir;

  final bool Function() _enabled;

  final ElevationSource _inner;
  final Future<Directory>? _dir;
  Future<ElevationSource>? _source;

  Future<ElevationSource> _resolve() => _source ??= () async {
        final dir = await (_dir ??
            getApplicationSupportDirectory()
                .then((d) => Directory(p.join(d.path, 'elevation_cache'))));
        return CachedElevationSource(_inner, dir);
      }();

  @override
  String get name => 'Open Topo Data (cached)';

  @override
  Future<List<double?>> elevations(List<LatLng> points) async {
    if (!_enabled()) throw const ElevationDisabled();
    final Future<ElevationSource> source;
    try {
      source = _resolve();
    } catch (e) {
      throw ElevationUnavailable('cache unavailable: $e');
    }
    return (await source).elevations(points);
  }
}
