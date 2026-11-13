// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import 'elevation_source.dart';

/// Disk cache in front of another [ElevationSource].
///
/// Grid: points are quantized to a lat/lon lattice of 1/3600 degree
/// (1 arc-second: 30.9 m in latitude, 30.9 m * cos(lat) in longitude, i.e.
/// ~24 m at 40 deg N), which matches the 30 m SRTM / 10-30 m NED resolution.
/// The inner source is queried at the lattice point of the cell, so all
/// lookups in a cell share one value.
///
/// Storage: one sparse binary file per 0.1 degree tile
/// (`t_<row>_<col>.bin` in [cacheDir]; 360 x 360 cells per tile). A file is a
/// sequence of 8-byte little-endian records: uint32 cell index within the
/// tile, float32 elevation. Only known elevations are stored (~8 bytes per
/// distinct 30 m cell crossed by a path), so a county of radial profiles is
/// a few MB. Unknown (null) results are not cached so they are retried.
class CachedElevationSource implements ElevationSource {
  CachedElevationSource(this.inner, this.cacheDir);

  final ElevationSource inner;
  final Directory cacheDir;

  /// Cells per degree.
  static const int cellsPerDegree = 3600;

  /// Cells per tile edge (0.1 degree).
  static const int tileCells = 360;

  final Map<String, Map<int, double>> _tiles = {};

  @override
  String get name => '${inner.name} (cached)';

  static int _floorDiv(int a, int b) => (a / b).floor();

  /// Cell (row, col) for a point.
  static (int, int) cellOf(LatLng p) => (
        (p.latitude * cellsPerDegree).round(),
        (p.longitude * cellsPerDegree).round(),
      );

  static String _tileName(int tr, int tc) => 't_${tr}_$tc.bin';

  Future<Map<int, double>> _loadTile(int tr, int tc) async {
    final name = _tileName(tr, tc);
    final cached = _tiles[name];
    if (cached != null) return cached;
    final map = <int, double>{};
    final f = File('${cacheDir.path}/$name');
    if (await f.exists()) {
      final bytes = await f.readAsBytes();
      final bd = ByteData.sublistView(bytes);
      for (var o = 0; o + 8 <= bytes.length; o += 8) {
        map[bd.getUint32(o, Endian.little)] =
            bd.getFloat32(o + 4, Endian.little);
      }
    }
    return _tiles[name] = map;
  }

  Future<void> _saveTile(int tr, int tc) async {
    final map = _tiles[_tileName(tr, tc)]!;
    final bd = ByteData(map.length * 8);
    var o = 0;
    map.forEach((idx, v) {
      bd.setUint32(o, idx, Endian.little);
      bd.setFloat32(o + 4, v, Endian.little);
      o += 8;
    });
    await cacheDir.create(recursive: true);
    final f = File('${cacheDir.path}/${_tileName(tr, tc)}');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bd.buffer.asUint8List(), flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<List<double?>> elevations(List<LatLng> points) async {
    final result = List<double?>.filled(points.length, null);
    // Distinct missing cells -> indices waiting on them.
    final missing = <(int, int), List<int>>{};
    for (var i = 0; i < points.length; i++) {
      final (r, c) = cellOf(points[i]);
      final tr = _floorDiv(r, tileCells), tc = _floorDiv(c, tileCells);
      final tile = await _loadTile(tr, tc);
      final idx = (r - tr * tileCells) * tileCells + (c - tc * tileCells);
      final v = tile[idx];
      if (v != null) {
        result[i] = v;
      } else {
        missing.putIfAbsent((r, c), () => []).add(i);
      }
    }
    if (missing.isEmpty) return result;

    final cells = missing.keys.toList();
    final fetched = await inner.elevations([
      for (final (r, c) in cells)
        LatLng(r / cellsPerDegree, c / cellsPerDegree),
    ]);
    final dirty = <(int, int)>{};
    for (var k = 0; k < cells.length; k++) {
      final v = fetched[k];
      if (v == null) continue;
      final (r, c) = cells[k];
      final tr = _floorDiv(r, tileCells), tc = _floorDiv(c, tileCells);
      _tiles[_tileName(tr, tc)]![
          (r - tr * tileCells) * tileCells + (c - tc * tileCells)] = v;
      dirty.add((tr, tc));
      for (final i in missing[cells[k]]!) {
        result[i] = v;
      }
    }
    for (final (tr, tc) in dirty) {
      await _saveTile(tr, tc);
    }
    return result;
  }
}
