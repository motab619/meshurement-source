// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import '../services/terrain/elevation_source.dart';

/// Demo-mode elevation from a small bundled grid (real terrain, no
/// network). Values are metres x 4 as little-endian int16, row 0 at
/// [north], bilinear in between; outside the grid the nearest edge value.
class GridElevationSource implements ElevationSource {
  GridElevationSource({
    required this.north,
    required this.west,
    required this.stepDeg,
    required this.rows,
    required this.cols,
    required String base64Data,
    this.label = 'bundled terrain (demo)',
  }) : _data = _decode(base64Data, rows * cols);

  final double north;
  final double west;
  final double stepDeg;
  final int rows;
  final int cols;
  final String label;
  final Int16List _data;

  static Int16List _decode(String b64, int count) {
    final bytes = base64.decode(b64);
    final view = ByteData.sublistView(bytes);
    return Int16List.fromList([
      for (var i = 0; i < count; i++) view.getInt16(i * 2, Endian.little),
    ]);
  }

  @override
  String get name => label;

  double _at(int r, int c) => _data[r * cols + c] / 4.0;

  double elevationAt(LatLng p) {
    final y = ((north - p.latitude) / stepDeg).clamp(0.0, rows - 1.001);
    final x = ((p.longitude - west) / stepDeg).clamp(0.0, cols - 1.001);
    final r = y.floor();
    final c = x.floor();
    final fy = y - r;
    final fx = x - c;
    final top = _at(r, c) * (1 - fx) + _at(r, c + 1) * fx;
    final bottom = _at(r + 1, c) * (1 - fx) + _at(r + 1, c + 1) * fx;
    return top * (1 - fy) + bottom * fy;
  }

  @override
  Future<List<double?>> elevations(List<LatLng> points) async =>
      [for (final p in points) elevationAt(p)];
}
