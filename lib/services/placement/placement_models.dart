// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:latlong2/latlong.dart';

import '../coverage_interpolation.dart';
import '../terrain/elevation_source.dart';
import '../terrain/path_loss_model.dart';
import '../terrain/terrain_service.dart';

/// One measured packet: location, RSSI (dBm) and optionally SNR (dB).
class PlacementSample {
  const PlacementSample(this.lat, this.lon, this.rssiDbm, {this.snrDb});
  final double lat;
  final double lon;
  final double rssiDbm;
  final double? snrDb;
}

/// Rectangular area of interest (degrees).
class PlacementBounds {
  const PlacementBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });
  final double south, west, north, east;
}

/// How a weak cell was determined.
enum WeakKind {
  /// A measurement fell inside the cell.
  measured,

  /// Estimated from nearby measurements (IDW, inside the trusted radius).
  interpolated,

  /// Beyond the measurements: terrain-predicted from the base.
  predicted,

  /// Packets were sent here but never answered (timeouts).
  dead,
}

/// A weak or dead analysis cell.
class WeakCell {
  const WeakCell(this.lat, this.lon, this.kind, this.rssiDbm);
  final double lat;
  final double lon;
  final WeakKind kind;

  /// Measured / interpolated / predicted RSSI; null for dead cells.
  final double? rssiDbm;
}

/// Everything [PlacementAdvisor.suggest] needs.
class PlacementRequest {
  const PlacementRequest({
    required this.base,
    required this.source,
    this.samples = const [],
    this.deadPoints = const [],
    this.grid,
    this.area,
    this.areaMarginM = 500,
    this.baseHeightM = 2.0,
    this.mobileHeightM = 1.5,
    this.relayHeightM = 5.0,
    this.frequencyMHz = 915,
    this.model,
    this.weakRssiDbm = -115,
    this.weakSnrDb = -10,
    this.includePredicted = true,
    this.maxPredictRangeM = 6000,
    this.cellM = 100,
    this.maxSuggestions = 5,
    this.maxCandidates = 60,
    this.maxScoreCells = 1500,
    this.maxRelayRangeM = 5000,
    this.linkSensitivityDbm = -120,
    this.minLinkMarginDb = 3,
    this.minGainFraction = 0.01,
    this.minSeparationM,
    this.maxElevationRequests = 120,
    this.pointsPerRequest = 100,
    this.useIsolate = true,
    this.cancel,
    this.onProgress,
  });

  final LatLng base;
  final ElevationSource source;

  /// Measured events (lat/lon/RSSI/SNR) of the coverage map.
  final List<PlacementSample> samples;

  /// Locations where packets were sent but never answered (timeouts).
  final List<LatLng> deadPoints;

  /// Optional pre-computed RSSI grid (Phase 3 IDW). When null and
  /// [samples] is not empty, one is interpolated from [samples].
  final CoverageGrid? grid;

  /// Area of interest; default is the extent of the samples / dead points /
  /// grid plus [areaMarginM]. The base is always included.
  final PlacementBounds? area;
  final double areaMarginM;

  final double baseHeightM;

  /// Height of the person/vehicle whose coverage is predicted.
  final double mobileHeightM;

  /// Assumed antenna height of the relay above ground at the new site.
  final double relayHeightM;
  final double frequencyMHz;

  /// Calibrated model (e.g. from `CoverageCalibrator`). When null and enough
  /// samples exist, the advisor calibrates one on its own terrain raster.
  final PathLossModel? model;

  /// A cell is weak when RSSI < [weakRssiDbm] or SNR < [weakSnrDb].
  final double weakRssiDbm;
  final double weakSnrDb;

  /// Also treat cells beyond the measurements as weak when the terrain
  /// model predicts RSSI below the threshold (labelled predicted).
  final bool includePredicted;
  final double maxPredictRangeM;

  /// Analysis cell size (metres); coarsened automatically to fit the
  /// elevation request budget.
  final double cellM;

  final int maxSuggestions;
  final int maxCandidates;

  /// Weak cells beyond this count are sub-sampled (evenly) for scoring.
  final int maxScoreCells;
  final double maxRelayRangeM;

  /// Receiver sensitivity used for the relay-to-base link margin.
  final double linkSensitivityDbm;
  final double minLinkMarginDb;

  /// A pick must add at least this fraction of the weak area.
  final double minGainFraction;

  /// Minimum spacing between picks (default 2 cells).
  final double? minSeparationM;

  /// Elevation request budget ([pointsPerRequest] points each).
  final int maxElevationRequests;
  final int pointsPerRequest;

  /// Run the scoring on a background isolate.
  final bool useIsolate;
  final TerrainCancelToken? cancel;
  final void Function(double progress)? onProgress;
}

/// One suggested relay site.
class PlacementSuggestion {
  const PlacementSuggestion({
    required this.rank,
    required this.lat,
    required this.lon,
    required this.elevationM,
    required this.coveredCells,
    required this.coveredPercent,
    required this.standaloneCoveredCells,
    required this.linkMarginToBaseDb,
    required this.losToBase,
    required this.distanceToBaseM,
    required this.notes,
  });

  final int rank;
  final double lat;
  final double lon;

  /// Ground elevation (m); null when no terrain data was available.
  final double? elevationM;

  /// Weak cells this site adds beyond the earlier picks (marginal gain).
  final int coveredCells;

  /// [coveredCells] as a percentage of the weak area.
  final double coveredPercent;

  /// Weak cells this site would cover on its own.
  final int standaloneCoveredCells;

  /// Predicted RSSI at the base from this site minus the link sensitivity.
  final double linkMarginToBaseDb;

  /// True when the first Fresnel zone to the base is mostly clear; false
  /// means line of sight but partial Fresnel obstruction (or unknown).
  final bool losToBase;
  final double distanceToBaseM;
  final List<String> notes;
}

/// Facts about how the result was produced.
class PlacementMeta {
  const PlacementMeta({
    required this.cellM,
    required this.elevationRequests,
    required this.elevationPoints,
    required this.requestBudget,
    required this.degraded,
    required this.degradedReason,
    required this.weakCellCount,
    required this.scoredCellCount,
    required this.measuredShare,
    required this.predictedShare,
    required this.candidateCount,
    required this.linkedCandidateCount,
    required this.calibrated,
    required this.calibrationRmseDb,
    required this.modelOffsetDb,
    required this.modelExponent,
  });

  final double cellM;
  final int elevationRequests;
  final int elevationPoints;
  final int requestBudget;

  /// No usable terrain: distance-only estimate, sites are unverified.
  final bool degraded;
  final String? degradedReason;
  final int weakCellCount;
  final int scoredCellCount;

  /// Share of weak cells backed by measurements (measured, interpolated,
  /// dead) versus terrain-predicted.
  final double measuredShare;
  final double predictedShare;
  final int candidateCount;
  final int linkedCandidateCount;
  final bool calibrated;
  final double? calibrationRmseDb;
  final double modelOffsetDb;
  final double modelExponent;
}

/// Output of [PlacementAdvisor.suggest].
class PlacementResult {
  const PlacementResult({
    required this.suggestions,
    required this.weakCells,
    required this.cumulativeCoveredPercent,
    required this.emptyReason,
    required this.meta,
  });

  /// Ranked best first; later picks add only what earlier ones miss.
  final List<PlacementSuggestion> suggestions;
  final List<WeakCell> weakCells;

  /// Share of the weak area covered by all suggestions together.
  final double cumulativeCoveredPercent;

  /// Why [suggestions] is empty (null when it is not).
  final String? emptyReason;
  final PlacementMeta meta;
}
