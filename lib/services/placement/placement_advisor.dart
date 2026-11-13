// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

/// Node placement advisor engine (Phase 5, Pro). No UI.
///
/// Method
/// 1. Area: the requested bounding box, or the extent of the measurements
///    plus a margin (the base is always inside).
/// 2. Terrain raster: ONE batch of elevation lookups on a regular grid
///    (default 100 m, coarsened automatically so that
///    `cols * rows <= maxElevationRequests * pointsPerRequest`, i.e. at most
///    120 requests of 100 points). Everything below (candidates, link and
///    coverage profiles) is computed from this raster by bilinear sampling,
///    so there are no further elevation requests. A caching
///    `ElevationSource` makes repeat runs free.
/// 3. Weak / dead cells, per analysis cell: a measurement inside the cell
///    (mean RSSI < threshold or SNR < threshold) is `measured`; a timeout
///    location is `dead`; otherwise the Phase 3 IDW grid inside its trusted
///    radius gives `interpolated`; beyond that, optionally, the terrain
///    model predicts RSSI from the base (`predicted`).
/// 4. Candidates: local elevation maxima and ridge-crest cells (higher than
///    both flanks along some axis), ranked by height and prominence, thinned
///    so neighbours do not crowd, capped at `maxCandidates`. Kept only if the
///    relay-to-base link (terrain profile + path-loss model with the
///    calibration offset) is not obstructed and has at least
///    `minLinkMarginDb` over `linkSensitivityDbm`.
/// 5. Scoring: a weak cell counts as covered when the profile from the
///    candidate (at `relayHeightM`) to the cell (at `mobileHeightM`) is not
///    obstructed and predicted RSSI >= the weak threshold. Greedy selection:
///    each pick maximises the number of still-uncovered weak cells
///    (marginal gain; ties by link margin, then deterministic order), so
///    later picks do not duplicate earlier ones.
///
/// Offline (the source throws) the advisor degrades to a distance-only
/// estimate: candidate sites are an even spread of grid cells, nothing is
/// verified, `elevationM` is null and `meta.degraded` is set.
///
/// Limits: not a guarantee. The raster is coarse (ridges narrower than a
/// cell are missed or smoothed); vegetation, buildings and clutter are
/// ignored; the relay is assumed to use the same radio, antenna and power as
/// the base at `relayHeightM` (default 5 m) above ground; the mobile is
/// assumed at `mobileHeightM`. As noted in Phase 3b, a path with partial
/// Fresnel obstruction (clearance below 60 % of F1 but above zero) is
/// modelled by knife-edge diffraction only and can be optimistic or
/// pessimistic; such sites are flagged. Predicted weak cells depend on the
/// path-loss calibration and are far less trustworthy than measured ones;
/// `meta.predictedShare` reports how much of the weak area is predicted.
/// Scoring runs on a background isolate when `useIsolate` is set, so
/// progress is reported only while fetching elevations and cancellation is
/// checked between phases.
library;

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import '../coverage_interpolation.dart';
import '../terrain/coverage_calibrator.dart';
import '../terrain/elevation_source.dart';
import '../terrain/geo.dart';
import '../terrain/path_loss_model.dart';
import '../terrain/terrain_profile.dart';
import '../terrain/terrain_service.dart';
import 'placement_models.dart';

export 'placement_models.dart';

/// Entry point of the placement engine.
class PlacementAdvisor {
  const PlacementAdvisor._();

  /// Computes ranked relay sites for [request]. Throws [TerrainCancelled]
  /// when the request's cancel token fires.
  static Future<PlacementResult> suggest(PlacementRequest request) async {
    void check() {
      if (request.cancel?.isCancelled ?? false) throw const TerrainCancelled();
    }

    check();
    final geom = _planGeometry(request);

    // Terrain raster: row-major cell centres, fetched in request-sized chunks.
    final centers = [
      for (var i = 0; i < geom.cols * geom.rows; i++) geom.center(i),
    ];
    final elev = <double?>[];
    var requests = 0;
    String? degradedReason;
    try {
      for (var i = 0; i < centers.length; i += request.pointsPerRequest) {
        check();
        final end = math.min(i + request.pointsPerRequest, centers.length);
        elev.addAll(await request.source.elevations(centers.sublist(i, end)));
        requests++;
        request.onProgress?.call(0.3 * end / centers.length);
      }
      if (elev.length != centers.length) {
        degradedReason = 'elevation source returned a short answer';
      }
    } on TerrainCancelled {
      rethrow;
    } on Exception catch (e) {
      degradedReason = e is ElevationUnavailable ? e.message : e.toString();
    }
    check();

    Float64List? raster;
    if (degradedReason == null) {
      final known = [
        for (final e in elev)
          if (e != null) e,
      ];
      if (known.isEmpty) {
        degradedReason = 'no elevation data for this area';
      } else {
        final mean = known.reduce((a, b) => a + b) / known.length;
        raster = Float64List.fromList([for (final e in elev) e ?? mean]);
      }
    }
    final fetchedPoints = degradedReason == null ? centers.length : 0;

    final job = _Job(
      geom: geom,
      elev: raster,
      baseLat: request.base.latitude,
      baseLon: request.base.longitude,
      baseH: request.baseHeightM,
      mobileH: request.mobileHeightM,
      relayH: request.relayHeightM,
      freq: request.frequencyMHz,
      inModel: request.model,
      weakRssi: request.weakRssiDbm,
      weakSnr: request.weakSnrDb,
      includePredicted: request.includePredicted,
      maxPredictRangeM: request.maxPredictRangeM,
      sLat: Float64List.fromList([for (final s in request.samples) s.lat]),
      sLon: Float64List.fromList([for (final s in request.samples) s.lon]),
      sRssi: Float64List.fromList([for (final s in request.samples) s.rssiDbm]),
      sSnr: Float64List.fromList(
          [for (final s in request.samples) s.snrDb ?? double.nan]),
      dLat: Float64List.fromList(
          [for (final p in request.deadPoints) p.latitude]),
      dLon: Float64List.fromList(
          [for (final p in request.deadPoints) p.longitude]),
      grid: request.grid,
      maxSuggestions: request.maxSuggestions,
      maxCandidates: request.maxCandidates,
      maxScoreCells: request.maxScoreCells,
      maxRelayRangeM: request.maxRelayRangeM,
      sensitivity: request.linkSensitivityDbm,
      minMargin: request.minLinkMarginDb,
      minGain: request.minGainFraction,
      minSepM: request.minSeparationM ?? 2 * geom.cellM,
    );
    final out = request.useIsolate ? await _runAsync(job) : _run(job);
    check();
    request.onProgress?.call(1);

    final nW = out.weakCells.length;
    final predicted =
        out.weakCells.where((w) => w.kind == WeakKind.predicted).length;
    return PlacementResult(
      suggestions: out.suggestions,
      weakCells: out.weakCells,
      cumulativeCoveredPercent: out.cumulativePercent,
      emptyReason: out.suggestions.isEmpty ? out.emptyReason : null,
      meta: PlacementMeta(
        cellM: geom.cellM,
        elevationRequests: requests,
        elevationPoints: fetchedPoints,
        requestBudget: request.maxElevationRequests,
        degraded: raster == null,
        degradedReason: degradedReason,
        weakCellCount: nW,
        scoredCellCount: out.scoredCells,
        measuredShare: nW == 0 ? 0 : (nW - predicted) / nW,
        predictedShare: nW == 0 ? 0 : predicted / nW,
        candidateCount: out.candidates,
        linkedCandidateCount: out.linkedCandidates,
        calibrated: out.calibrated,
        calibrationRmseDb: out.calibrationRmse,
        modelOffsetDb: out.modelOffset,
        modelExponent: out.modelExponent,
      ),
    );
  }

  static _Geom _planGeometry(PlacementRequest r) {
    double? minLat, maxLat, minLon, maxLon;
    void add(double lat, double lon) {
      minLat = minLat == null ? lat : math.min(minLat!, lat);
      maxLat = maxLat == null ? lat : math.max(maxLat!, lat);
      minLon = minLon == null ? lon : math.min(minLon!, lon);
      maxLon = maxLon == null ? lon : math.max(maxLon!, lon);
    }

    var marginM = 0.0;
    final a = r.area;
    if (a != null) {
      add(a.south, a.west);
      add(a.north, a.east);
    } else {
      for (final s in r.samples) {
        add(s.lat, s.lon);
      }
      for (final p in r.deadPoints) {
        add(p.latitude, p.longitude);
      }
      final g = r.grid;
      if (g != null) {
        add(g.south, g.west);
        add(g.north, g.east);
      }
      marginM = minLat == null ? 4 * r.areaMarginM : r.areaMarginM;
    }
    add(r.base.latitude, r.base.longitude);
    final (mLat, mLon) = metersPerDegree((minLat! + maxLat!) / 2);
    final south = minLat! - marginM / mLat, north = maxLat! + marginM / mLat;
    final west = minLon! - marginM / mLon, east = maxLon! + marginM / mLon;
    final widthM = math.max((east - west) * mLon, 1.0);
    final heightM = math.max((north - south) * mLat, 1.0);
    final maxPoints = math.max(4, r.maxElevationRequests * r.pointsPerRequest);
    var cell = math.max(r.cellM, 10.0);
    while ((widthM / cell).ceil().clamp(1, 1 << 30) *
            (heightM / cell).ceil().clamp(1, 1 << 30) >
        maxPoints) {
      cell *= 1.25;
    }
    final cols = math.max(1, (widthM / cell).ceil());
    final rows = math.max(1, (heightM / cell).ceil());
    return _Geom(
      south: south,
      west: west,
      dLat: (north - south) / rows,
      dLon: (east - west) / cols,
      cols: cols,
      rows: rows,
      cellM: cell,
    );
  }
}

// ---------------------------------------------------------------------------
// Pure computation (runs on an isolate or synchronously).
// ---------------------------------------------------------------------------

class _Geom {
  const _Geom({
    required this.south,
    required this.west,
    required this.dLat,
    required this.dLon,
    required this.cols,
    required this.rows,
    required this.cellM,
  });
  final double south, west, dLat, dLon, cellM;
  final int cols, rows;

  double latOf(int r) => south + (r + 0.5) * dLat;
  double lonOf(int c) => west + (c + 0.5) * dLon;
  LatLng center(int i) => LatLng(latOf(i ~/ cols), lonOf(i % cols));

  /// Cell index containing the point, or -1.
  int cellAt(double lat, double lon) {
    final r = ((lat - south) / dLat).floor();
    final c = ((lon - west) / dLon).floor();
    if (r < 0 || r >= rows || c < 0 || c >= cols) return -1;
    return r * cols + c;
  }
}

class _Job {
  const _Job({
    required this.geom,
    required this.elev,
    required this.baseLat,
    required this.baseLon,
    required this.baseH,
    required this.mobileH,
    required this.relayH,
    required this.freq,
    required this.inModel,
    required this.weakRssi,
    required this.weakSnr,
    required this.includePredicted,
    required this.maxPredictRangeM,
    required this.sLat,
    required this.sLon,
    required this.sRssi,
    required this.sSnr,
    required this.dLat,
    required this.dLon,
    required this.grid,
    required this.maxSuggestions,
    required this.maxCandidates,
    required this.maxScoreCells,
    required this.maxRelayRangeM,
    required this.sensitivity,
    required this.minMargin,
    required this.minGain,
    required this.minSepM,
  });
  final _Geom geom;
  final Float64List? elev;
  final double baseLat, baseLon, baseH, mobileH, relayH, freq;
  final PathLossModel? inModel;
  final double weakRssi, weakSnr, maxPredictRangeM;
  final bool includePredicted;
  final Float64List sLat, sLon, sRssi, sSnr, dLat, dLon;
  final CoverageGrid? grid;
  final int maxSuggestions, maxCandidates, maxScoreCells;
  final double maxRelayRangeM, sensitivity, minMargin, minGain, minSepM;
}

class _Out {
  const _Out({
    required this.suggestions,
    required this.weakCells,
    required this.cumulativePercent,
    required this.emptyReason,
    required this.scoredCells,
    required this.candidates,
    required this.linkedCandidates,
    required this.calibrated,
    required this.calibrationRmse,
    required this.modelOffset,
    required this.modelExponent,
  });
  final List<PlacementSuggestion> suggestions;
  final List<WeakCell> weakCells;
  final double cumulativePercent;
  final String? emptyReason;
  final int scoredCells, candidates, linkedCandidates;
  final bool calibrated;
  final double? calibrationRmse;
  final double modelOffset, modelExponent;
}

Future<_Out> _runAsync(_Job job) => Isolate.run(() => _run(job));

class _Cand {
  _Cand(this.idx, this.score, this.ridge);
  final int idx;
  final double score;
  final bool ridge;
}

_Out _run(_Job j) {
  final g = j.geom;
  final nCells = g.cols * g.rows;
  final terrain = j.elev != null;
  final elev = j.elev;

  double elevAt(double lat, double lon) {
    final fr = ((lat - g.south) / g.dLat - 0.5).clamp(0.0, g.rows - 1.0);
    final fc = ((lon - g.west) / g.dLon - 0.5).clamp(0.0, g.cols - 1.0);
    final r0 = fr.floor(), c0 = fc.floor();
    final r1 = math.min(r0 + 1, g.rows - 1), c1 = math.min(c0 + 1, g.cols - 1);
    final tr = fr - r0, tc = fc - c0;
    final a = elev![r0 * g.cols + c0], b = elev[r0 * g.cols + c1];
    final c = elev[r1 * g.cols + c0], d = elev[r1 * g.cols + c1];
    return (a * (1 - tc) + b * tc) * (1 - tr) + (c * (1 - tc) + d * tc) * tr;
  }

  TerrainProfile? profile(LatLng a, LatLng b, double hA, double hB) {
    if (!terrain) return null;
    final d = greatCircleDistanceM(a, b);
    final n = (d / g.cellM).ceil().clamp(1, 120);
    final pts = [
      for (var i = 0; i <= n; i++) greatCircleInterpolate(a, b, i / n)
    ];
    return TerrainProfile.fromElevations(
      points: pts,
      elevations: [for (final p in pts) elevAt(p.latitude, p.longitude)],
      frequencyMHz: j.freq,
      baseHeightM: hA,
      mobileHeightM: hB,
    );
  }

  final base = LatLng(j.baseLat, j.baseLon);

  // Measurements binned per analysis cell.
  final cnt = Int32List(nCells), snrCnt = Int32List(nCells);
  final sumR = Float64List(nCells), sumS = Float64List(nCells);
  for (var i = 0; i < j.sLat.length; i++) {
    final c = g.cellAt(j.sLat[i], j.sLon[i]);
    if (c < 0) continue;
    cnt[c]++;
    sumR[c] += j.sRssi[i];
    if (!j.sSnr[i].isNaN) {
      snrCnt[c]++;
      sumS[c] += j.sSnr[i];
    }
  }
  final deadCell = Uint8List(nCells);
  for (var i = 0; i < j.dLat.length; i++) {
    final c = g.cellAt(j.dLat[i], j.dLon[i]);
    if (c >= 0) deadCell[c] = 1;
  }

  // Model: caller's calibrated one, else fit on our raster.
  var model = j.inModel ?? PathLossModel(frequencyMHz: j.freq);
  var calibrated = j.inModel != null;
  double? rmse;
  if (j.inModel == null && terrain) {
    final measuredCells = [
      for (var c = 0; c < nCells; c++)
        if (cnt[c] > 0 && greatCircleDistanceM(base, g.center(c)) > 50) c,
    ];
    if (measuredCells.length >= 3) {
      final step = math.max(1, (measuredCells.length / 50).ceil());
      final m0 = PathLossModel(frequencyMHz: j.freq);
      final samples = <CalibrationSample>[];
      for (var k = 0; k < measuredCells.length; k += step) {
        final c = measuredCells[k];
        final p = g.center(c);
        final prof = profile(base, p, j.baseH, j.mobileH);
        samples.add(CalibrationSample(
          greatCircleDistanceM(base, p),
          prof == null ? 0 : m0.diffractionLossDb(prof),
          sumR[c] / cnt[c],
        ));
      }
      final fit = CoverageCalibrator.fit(m0, samples);
      model = fit.model;
      rmse = fit.rmseDb;
      calibrated = true;
    }
  }

  // Interpolated grids (trusted radius = IDW alpha > 0). A tight fade of
  // its own: the estimated-coverage display fade reaches 1.5 km, too far
  // to call a cell measured-weak.
  const fadeStart = 50.0, fadeEnd = 300.0;
  CoverageGrid? rssiGrid = j.grid;
  CoverageGrid? snrGrid;
  if (rssiGrid == null && j.sLat.isNotEmpty) {
    rssiGrid = interpolateCoverage(
        j.sLat.toList(), j.sLon.toList(), j.sRssi.toList(),
        fadeStart: fadeStart, fadeEnd: fadeEnd);
    final si = [
      for (var i = 0; i < j.sSnr.length; i++)
        if (!j.sSnr[i].isNaN) i,
    ];
    if (si.isNotEmpty) {
      snrGrid = interpolateCoverage([
        for (final i in si) j.sLat[i]
      ], [
        for (final i in si) j.sLon[i]
      ], [
        for (final i in si) j.sSnr[i]
      ], fadeStart: fadeStart, fadeEnd: fadeEnd);
    }
  }

  // Weak / dead cells.
  final weakIdx = <int>[];
  final weak = <WeakCell>[];
  for (var c = 0; c < nCells; c++) {
    final lat = g.latOf(c ~/ g.cols), lon = g.lonOf(c % g.cols);
    WeakKind? kind;
    double? value;
    var trusted = false;
    if (deadCell[c] == 1) {
      kind = WeakKind.dead;
      trusted = true;
    } else if (cnt[c] > 0) {
      trusted = true;
      value = sumR[c] / cnt[c];
      final snr = snrCnt[c] > 0 ? sumS[c] / snrCnt[c] : null;
      if (value < j.weakRssi || (snr != null && snr < j.weakSnr)) {
        kind = WeakKind.measured;
      }
    } else if (rssiGrid != null) {
      final gi = rssiGrid.cellAt(lat, lon);
      if (gi >= 0 && rssiGrid.alpha[gi] > 0) {
        trusted = true;
        value = rssiGrid.values[gi];
        var w = value < j.weakRssi;
        final sg = snrGrid;
        if (sg != null) {
          final si = sg.cellAt(lat, lon);
          if (si >= 0 && sg.alpha[si] > 0 && sg.values[si] < j.weakSnr) {
            w = true;
          }
        }
        if (w) kind = WeakKind.interpolated;
      }
    }
    if (!trusted && j.includePredicted) {
      final p = LatLng(lat, lon);
      final d = greatCircleDistanceM(base, p);
      if (d > g.cellM && d <= j.maxPredictRangeM) {
        final pr = model.predict(
            distanceM: d, profile: profile(base, p, j.baseH, j.mobileH));
        if (pr.rssiDbm < j.weakRssi) {
          kind = WeakKind.predicted;
          value = pr.rssiDbm;
        }
      }
    }
    if (kind != null) {
      weakIdx.add(c);
      weak.add(WeakCell(lat, lon, kind, kind == WeakKind.dead ? null : value));
    }
  }

  _Out empty(String reason, {int cands = 0, int linked = 0, int scored = 0}) =>
      _Out(
        suggestions: const [],
        weakCells: weak,
        cumulativePercent: 0,
        emptyReason: reason,
        scoredCells: scored,
        candidates: cands,
        linkedCandidates: linked,
        calibrated: calibrated,
        calibrationRmse: rmse,
        modelOffset: model.offsetDb,
        modelExponent: model.exponent,
      );

  if (weak.isEmpty) {
    return empty('No weak or dead cells found: coverage in the area meets '
        'the threshold, so no extra node is needed.');
  }

  // Sub-sample weak cells for scoring.
  final scoredPos = <int>[]; // positions into weak/weakIdx
  if (weak.length <= j.maxScoreCells) {
    for (var i = 0; i < weak.length; i++) {
      scoredPos.add(i);
    }
  } else {
    for (var k = 0; k < j.maxScoreCells; k++) {
      scoredPos.add(k * weak.length ~/ j.maxScoreCells);
    }
  }
  final nS = scoredPos.length;

  // Candidate sites.
  final cands = <_Cand>[];
  if (terrain) {
    const axes = [(0, 1), (1, 0), (1, 1), (1, -1)];
    const ridgeMinM = 5.0;
    for (var r = 0; r < g.rows; r++) {
      for (var c = 0; c < g.cols; c++) {
        final i = r * g.cols + c;
        final e = elev![i];
        var peak = true, nbCount = 0;
        var nbSum = 0.0;
        for (var dr = -1; dr <= 1; dr++) {
          for (var dc = -1; dc <= 1; dc++) {
            if (dr == 0 && dc == 0) continue;
            final rr = r + dr, cc = c + dc;
            if (rr < 0 || rr >= g.rows || cc < 0 || cc >= g.cols) continue;
            final v = elev[rr * g.cols + cc];
            nbCount++;
            nbSum += v;
            // Plateaus: only the first cell in scan order is a peak.
            final earlier = rr * g.cols + cc < i;
            if (earlier ? e <= v : e < v) peak = false;
          }
        }
        if (nbCount == 0) continue;
        var ridge = false;
        for (final (dr, dc) in axes) {
          final r1 = r + dr, c1 = c + dc, r2 = r - dr, c2 = c - dc;
          if (r1 < 0 || r1 >= g.rows || c1 < 0 || c1 >= g.cols) continue;
          if (r2 < 0 || r2 >= g.rows || c2 < 0 || c2 >= g.cols) continue;
          if (e - elev[r1 * g.cols + c1] >= ridgeMinM &&
              e - elev[r2 * g.cols + c2] >= ridgeMinM) {
            ridge = true;
            break;
          }
        }
        if (!peak && !ridge) continue;
        final prom = e - nbSum / nbCount;
        cands.add(_Cand(i, e + 2 * prom, !peak));
      }
    }
    cands.sort((a, b) {
      final s = b.score.compareTo(a.score);
      return s != 0 ? s : a.idx.compareTo(b.idx);
    });
    // Thin out: no two candidates within 2 cells (Chebyshev).
    final kept = <_Cand>[];
    for (final cd in cands) {
      if (kept.length >= j.maxCandidates) break;
      final r = cd.idx ~/ g.cols, c = cd.idx % g.cols;
      var near = false;
      for (final k in kept) {
        if ((k.idx ~/ g.cols - r).abs() <= 2 &&
            (k.idx % g.cols - c).abs() <= 2) {
          near = true;
          break;
        }
      }
      if (!near) kept.add(cd);
    }
    cands
      ..clear()
      ..addAll(kept);
  } else {
    // No terrain: an even spread of cells, nothing about them is verified.
    final n = math.min(j.maxCandidates, nCells);
    for (var k = 0; k < n; k++) {
      cands.add(_Cand(k * nCells ~/ n, 0, false));
    }
  }
  if (cands.isEmpty) {
    return empty('No candidate high points or ridges found in the area.',
        scored: nS);
  }

  // Link filter + coverage per candidate.
  final linked = <_Linked>[];
  final dBaseMin = g.cellM;
  for (final cd in cands) {
    final p = g.center(cd.idx);
    final d = greatCircleDistanceM(base, p);
    if (d < dBaseMin) continue;
    final prof = profile(base, p, j.baseH, j.relayH);
    final pr = model.predict(distanceM: d, profile: prof);
    final margin = pr.rssiDbm - j.sensitivity;
    if (pr.classification == PathClass.obstructed || margin < j.minMargin) {
      continue;
    }
    final covThr = j.weakRssi;
    final covered = <int>[];
    for (var k = 0; k < nS; k++) {
      final wp = weakIdx[scoredPos[k]];
      final q = g.center(wp);
      final dc = greatCircleDistanceM(p, q);
      if (dc > j.maxRelayRangeM) continue;
      if (wp == cd.idx || dc < g.cellM * 0.75) {
        covered.add(k);
        continue;
      }
      if (model.offsetDb - model.logDistanceLossDb(dc) < covThr) continue;
      final cp = model.predict(
          distanceM: dc, profile: profile(p, q, j.relayH, j.mobileH));
      if (cp.classification != PathClass.obstructed && cp.rssiDbm >= covThr) {
        covered.add(k);
      }
    }
    linked.add(_Linked(cd, p, d, margin, pr.classification, covered));
  }
  if (linked.isEmpty) {
    return empty(
        'No candidate site has a usable link to the base '
        '(line of sight with at least ${j.minMargin.toStringAsFixed(0)} dB '
        'margin).',
        cands: cands.length,
        scored: nS);
  }

  // Greedy marginal-gain selection.
  final coveredNow = Uint8List(nS);
  final picks = <PlacementSuggestion>[];
  final chosen = <_Linked>[];
  final minGainCells = math.max(1, (j.minGain * nS).ceil());
  var totalCovered = 0;
  while (picks.length < j.maxSuggestions) {
    _Linked? best;
    var bestGain = 0;
    for (final l in linked) {
      if (chosen.contains(l)) continue;
      if (greatCircleDistanceM(l.point, base) < j.minSepM) continue;
      if (chosen
          .any((c) => greatCircleDistanceM(c.point, l.point) < j.minSepM)) {
        continue;
      }
      var gain = 0;
      for (final k in l.covered) {
        if (coveredNow[k] == 0) gain++;
      }
      if (gain > bestGain ||
          (gain == bestGain && gain > 0 && l.margin > best!.margin)) {
        best = l;
        bestGain = gain;
      }
    }
    if (best == null || bestGain < minGainCells) break;
    var dead = 0, predicted = 0;
    for (final k in best.covered) {
      if (coveredNow[k] == 0) {
        coveredNow[k] = 1;
        final kind = weak[scoredPos[k]].kind;
        if (kind == WeakKind.dead) dead++;
        if (kind == WeakKind.predicted) predicted++;
      }
    }
    totalCovered += bestGain;
    chosen.add(best);
    final notes = <String>[
      if (!terrain)
        'No terrain data: distance-only estimate, site not verified.'
      else
        '${best.cand.ridge ? 'Ridge crest' : 'Local high point'}, '
            '${elev![best.cand.idx].toStringAsFixed(0)} m elevation.',
      if (terrain && best.cls == PathClass.clear)
        'Clear line of sight to the base.'
      else if (terrain)
        'Line of sight to the base but the first Fresnel zone is partly '
            'blocked; the link margin is less certain.',
      if (dead > 0) 'Covers $dead dead (no-reply) cells.',
      if (predicted * 2 > bestGain)
        'Most of this gain is in terrain-predicted cells with no '
            'measurements; verify on site.',
      'Assumes a ${j.relayH.toStringAsFixed(0)} m antenna at the site and '
          'the same hardware as the base.',
    ];
    picks.add(PlacementSuggestion(
      rank: picks.length + 1,
      lat: best.point.latitude,
      lon: best.point.longitude,
      elevationM: terrain ? elev![best.cand.idx] : null,
      coveredCells: bestGain,
      coveredPercent: 100 * bestGain / nS,
      standaloneCoveredCells: best.covered.length,
      linkMarginToBaseDb: best.margin,
      losToBase: terrain && best.cls == PathClass.clear,
      distanceToBaseM: best.distance,
      notes: notes,
    ));
  }
  if (picks.isEmpty) {
    return empty(
        'No candidate site would cover enough of the weak area '
        '(at least ${(j.minGain * 100).toStringAsFixed(0)} %).',
        cands: cands.length,
        linked: linked.length,
        scored: nS);
  }
  return _Out(
    suggestions: picks,
    weakCells: weak,
    cumulativePercent: 100 * totalCovered / nS,
    emptyReason: null,
    scoredCells: nS,
    candidates: cands.length,
    linkedCandidates: linked.length,
    calibrated: calibrated,
    calibrationRmse: rmse,
    modelOffset: model.offsetDb,
    modelExponent: model.exponent,
  );
}

class _Linked {
  _Linked(this.cand, this.point, this.distance, this.margin, this.cls,
      this.covered);
  final _Cand cand;
  final LatLng point;
  final double distance, margin;
  final PathClass cls;
  final List<int> covered;
}
