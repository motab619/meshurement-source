// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

/// Estimated-coverage grid: inverse-distance-weighted values on a regular
/// grid, with a per-cell alpha that fades with distance from the nearest
/// measurement. Rows run south → north, columns west → east. Cells beyond
/// the fade distance have alpha 0 (omitted).
class CoverageGrid {
  final double south, west, north, east;
  final int cols, rows;
  final double cellMeters;

  /// Interpolated value per cell (`rows * cols`, index `row * cols + col`).
  final Float32List values;

  /// 0..1 per cell; 0 = no estimate.
  final Float32List alpha;

  const CoverageGrid({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.cols,
    required this.rows,
    required this.cellMeters,
    required this.values,
    required this.alpha,
  });

  /// Cell index containing [lat]/[lon], or -1 if outside the grid.
  int cellAt(double lat, double lon) {
    if (lat < south || lat >= north || lon < west || lon >= east) return -1;
    final col =
        ((lon - west) / (east - west) * cols).floor().clamp(0, cols - 1);
    final row =
        ((lat - south) / (north - south) * rows).floor().clamp(0, rows - 1);
    return row * cols + col;
  }
}

/// Tunables (metres).
class InterpolationParams {
  InterpolationParams._();

  static const cellMeters = 50.0;

  /// Neighbours are looked for this far out; must exceed [fadeEnd].
  static const searchRadius = 2500.0;
  static const maxNeighbours = 12;

  /// Full opacity out to here, then linear fade to transparent at [fadeEnd].
  /// Testers found 50/300 m inferred too little; a drive's estimate now
  /// reaches about 1.5 km either side of the route.
  static const fadeStart = 250.0;
  static const fadeEnd = 1500.0;

  /// Keeps image size and compute bounded for very large sessions.
  static const maxCells = 250000;
}

/// Metres per degree of (latitude, longitude) at [latDeg] (WGS84 series).
(double, double) metersPerDegree(double latDeg) {
  final p = latDeg * math.pi / 180;
  final lat = 111132.92 - 559.82 * math.cos(2 * p) + 1.175 * math.cos(4 * p);
  final lon = 111412.84 * math.cos(p) - 93.5 * math.cos(3 * p);
  return (lat, lon);
}

/// Runs [interpolateCoverage] on a background isolate.
Future<CoverageGrid?> interpolateCoverageAsync(
  List<double> lats,
  List<double> lons,
  List<double> values,
) =>
    Isolate.run(() => interpolateCoverage(lats, lons, values));

/// Where a [CoverageGrid] sits and how fine it is, without values. Lets two
/// datasets (e.g. the two sides of a rig comparison) share one grid.
class CoverageGridSpec {
  final double south, west, north, east;
  final int cols, rows;
  final double cellMeters;
  final double metersPerDegLat, metersPerDegLon;

  const CoverageGridSpec({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.cols,
    required this.rows,
    required this.cellMeters,
    required this.metersPerDegLat,
    required this.metersPerDegLon,
  });
}

/// The grid [interpolateCoverage] would use for these points (null for no
/// points): their bounding box plus the fade margin, on whole cells.
CoverageGridSpec? coverageGridSpecFor(List<double> lats, List<double> lons,
    {double fadeEnd = InterpolationParams.fadeEnd}) {
  final n = lats.length;
  if (n == 0) return null;
  var minLat = lats[0], maxLat = lats[0], minLon = lons[0], maxLon = lons[0];
  for (var i = 1; i < n; i++) {
    minLat = math.min(minLat, lats[i]);
    maxLat = math.max(maxLat, lats[i]);
    minLon = math.min(minLon, lons[i]);
    maxLon = math.max(maxLon, lons[i]);
  }
  final (mLat, mLon) = metersPerDegree((minLat + maxLat) / 2);
  // Not a whole number of cells, so points never sit exactly on a cell edge.
  final margin = fadeEnd + 17;

  final west = minLon - margin / mLon;
  final south = minLat - margin / mLat;
  final widthM = (maxLon - minLon) * mLon + 2 * margin;
  final heightM = (maxLat - minLat) * mLat + 2 * margin;

  var cell = InterpolationParams.cellMeters;
  while ((widthM / cell).ceil() * (heightM / cell).ceil() >
      InterpolationParams.maxCells) {
    cell *= 1.25;
  }
  final cols = math.max(1, (widthM / cell).ceil());
  final rows = math.max(1, (heightM / cell).ceil());
  // Grid edges are whole cells, so cell maths and lat/lon maths agree.
  return CoverageGridSpec(
    south: south,
    west: west,
    north: south + rows * cell / mLat,
    east: west + cols * cell / mLon,
    cols: cols,
    rows: rows,
    cellMeters: cell,
    metersPerDegLat: mLat,
    metersPerDegLon: mLon,
  );
}

/// IDW (power 2) interpolation of [values] measured at [lats]/[lons].
/// Returns null for no points. Cells containing measurements show exactly
/// the mean of those measurements. With [spec] the result lies on that grid
/// (all points must be inside it, see [coverageGridSpecFor]).
/// [fadeStart]/[fadeEnd] override the display fade (rig comparison uses
/// a tight one).
CoverageGrid? interpolateCoverage(
  List<double> lats,
  List<double> lons,
  List<double> values, {
  CoverageGridSpec? spec,
  double fadeStart = InterpolationParams.fadeStart,
  double fadeEnd = InterpolationParams.fadeEnd,
}) {
  final n = lats.length;
  if (n == 0) return null;
  final g = spec ?? coverageGridSpecFor(lats, lons)!;
  final south = g.south, west = g.west, north = g.north, east = g.east;
  final cols = g.cols, rows = g.rows, cell = g.cellMeters;
  final mLat = g.metersPerDegLat, mLon = g.metersPerDegLon;

  // Points in local metres, bucketed by search radius for neighbour lookup.
  final px = Float64List(n), py = Float64List(n);
  for (var i = 0; i < n; i++) {
    px[i] = (lons[i] - west) * mLon;
    py[i] = (lats[i] - south) * mLat;
  }
  const bs = InterpolationParams.searchRadius;
  final bCols = (cols * cell / bs).ceil() + 1;
  final bRows = (rows * cell / bs).ceil() + 1;
  final buckets = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    final key = (py[i] / bs).floor() * bCols + (px[i] / bs).floor();
    (buckets[key] ??= <int>[]).add(i);
  }

  const k = InterpolationParams.maxNeighbours;
  const r2Max =
      InterpolationParams.searchRadius * InterpolationParams.searchRadius;
  final out = Float32List(cols * rows);
  final alpha = Float32List(cols * rows);
  final nd = Float64List(k); // squared distances, ascending
  final ni = Int32List(k);

  for (var r = 0; r < rows; r++) {
    final cy = (r + 0.5) * cell;
    final by = (cy / bs).floor();
    for (var c = 0; c < cols; c++) {
      final cx = (c + 0.5) * cell;
      final bx = (cx / bs).floor();
      var count = 0;
      for (var yy = by - 1; yy <= by + 1; yy++) {
        if (yy < 0 || yy >= bRows) continue;
        for (var xx = bx - 1; xx <= bx + 1; xx++) {
          if (xx < 0 || xx >= bCols) continue;
          final list = buckets[yy * bCols + xx];
          if (list == null) continue;
          for (final i in list) {
            final dx = px[i] - cx, dy = py[i] - cy;
            final d2 = dx * dx + dy * dy;
            if (d2 > r2Max) continue;
            if (count == k && d2 >= nd[k - 1]) continue;
            var j = count < k ? count++ : k - 1;
            while (j > 0 && nd[j - 1] > d2) {
              nd[j] = nd[j - 1];
              ni[j] = ni[j - 1];
              j--;
            }
            nd[j] = d2;
            ni[j] = i;
          }
        }
      }
      if (count == 0) continue;
      final d0 = math.sqrt(nd[0]);
      if (d0 >= fadeEnd) continue;
      var wSum = 0.0, vSum = 0.0;
      for (var j = 0; j < count; j++) {
        final w = 1 / math.max(nd[j], 1.0);
        wSum += w;
        vSum += w * values[ni[j]];
      }
      final idx = r * cols + c;
      out[idx] = vSum / wSum;
      alpha[idx] = d0 <= fadeStart ? 1 : (fadeEnd - d0) / (fadeEnd - fadeStart);
    }
  }

  // Cells that contain measurements show exactly their mean.
  final sums = <int, double>{}, counts = <int, int>{};
  for (var i = 0; i < n; i++) {
    final col = (px[i] / cell).floor().clamp(0, cols - 1);
    final row = (py[i] / cell).floor().clamp(0, rows - 1);
    final idx = row * cols + col;
    sums[idx] = (sums[idx] ?? 0) + values[i];
    counts[idx] = (counts[idx] ?? 0) + 1;
  }
  sums.forEach((idx, s) {
    out[idx] = s / counts[idx]!;
    alpha[idx] = 1;
  });

  return CoverageGrid(
    south: south,
    west: west,
    north: north,
    east: east,
    cols: cols,
    rows: rows,
    cellMeters: cell,
    values: out,
    alpha: alpha,
  );
}
