// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/database/app_database.dart';
import '../protocol_text.dart';
import '../../providers.dart';
import '../../services/ai_analysis.dart';
import '../../services/base_location.dart';
import '../../services/guided/plan_models.dart';
import '../../services/range_stats.dart';
import '../../services/rig_comparison.dart';
import '../../services/rig_math.dart';
import '../../utils/constants.dart';
import '../../utils/coverage_raster.dart';
import '../../services/terrain/terrain_settings.dart';
import '../../utils/signal_color_mapper.dart';
import '../theme/app_theme.dart';
import '../widgets/field_report/field_report_sheet.dart';
import '../widgets/ai_analysis_card.dart';
import '../widgets/base_map_layers.dart';
import '../widgets/range_comparison_section.dart';
import 'guided/guided_test_flow.dart';
import '../widgets/signal_legend.dart' show signalLevels;
import '../layout/window_class.dart';

/// Colour scale limits (dB) for the delta overlay.
const _rssiClampDb = 10.0;
const _snrClampDb = 5.0;
const _overlayOpacity = 0.75;

/// Preference: which view of the comparison the map shows.
const prefCompareView = 'compare_view';

/// What the comparison map paints in each cell.
enum CompareView {
  /// Orange / blue / grey: who is better by [comparisonClearDeltaDb].
  winner('Winner'),

  /// Continuous B-minus-A colour ramp.
  gradient('Gradient'),

  /// Side A's own signal, every cell A measured.
  aOnly('A only'),

  /// Side B's own signal, every cell B measured.
  bOnly('B only');

  final String label;
  const CompareView(this.label);
}

/// Faint outline for route cells that are not painted in the current view.
const _outlineColor = Color(0xCC616161);
const _outlineFill = Color(0x1F757575);

/// "Mobile: X · Base: Y" style description of a group of sessions.
String describeSide(List<Session> sessions) {
  final presets = {
    for (final s in sessions)
      if (s.loraPreset.isNotEmpty) anyPresetDisplayName(s.loraPreset),
  };
  final mobile = groupRig(sessions, mobile: true);
  final base = groupRig(sessions, mobile: false);
  return [
    if (presets.isNotEmpty) presets.join('/'),
    'Mobile: ${mobile.label}',
    'Base: ${base.label}',
  ].join(' · ');
}

/// B-minus-A delta view for two groups of sessions of one coverage map:
/// diverging overlay on the map plus a summary card. Opening a saved
/// comparison is free; creating one is Pro (gated by the caller).
class RigComparisonScreen extends ConsumerStatefulWidget {
  final CoverageMap map;
  final List<int> sessionIdsA;
  final List<int> sessionIdsB;

  const RigComparisonScreen({
    super.key,
    required this.map,
    required this.sessionIdsA,
    required this.sessionIdsB,
  });

  @override
  ConsumerState<RigComparisonScreen> createState() =>
      _RigComparisonScreenState();
}

class _Loaded {
  final List<Session> a, b;
  final ComparisonCheck check;
  final RouteComparison? result;
  final RigExpectation expected;

  /// Distance-from-base comparison; null when no base position is known.
  final RangeComparison? range;

  const _Loaded(this.a, this.b, this.check, this.result, this.expected,
      [this.range]);
}

/// Names for the two sides in the distance section: the modem presets when
/// they tell the sides apart, else the rigs, else "A" / "B".
(String, String) rangeSideNames(List<Session> a, List<Session> b) {
  String presets(List<Session> g) => {
        for (final s in g)
          if (s.loraPreset.isNotEmpty) anyPresetDisplayName(s.loraPreset),
      }.join('/');
  final pa = presets(a), pb = presets(b);
  if (pa.isNotEmpty && pb.isNotEmpty && pa != pb) return (pa, pb);
  final (ra, rb) = _sideNames(a, b);
  if (ra != null && rb != null) return (ra, rb);
  return ('A', 'B');
}

/// Short name for each side: the rig that differs between them (mobile
/// first, then base), or null when the rigs do not tell them apart.
(String?, String?) _sideNames(List<Session> a, List<Session> b) {
  for (final mobile in [true, false]) {
    final ga = groupRig(a, mobile: mobile), gb = groupRig(b, mobile: mobile);
    if (ga.label != gb.label && (ga.hasProfile || gb.hasProfile)) {
      return (ga.label, gb.label);
    }
  }
  return (null, null);
}

class _RigComparisonScreenState extends ConsumerState<RigComparisonScreen> {
  late final Future<_Loaded> _future = _load();
  bool _rssi = true;
  CompareView _view = CompareView.winner;
  final _polygons = <(CompareView, bool), List<Polygon>>{};
  late SavedComparison _saved;
  bool _isSaved = false;

  // Results sheet over the map; its height places the tile credit just
  // above it (as on map detail), clear of the view toggle and the route.
  static const _sheetInitial = 0.5;
  final _sheet = DraggableScrollableController();
  double _sheetFraction = _sheetInitial;

  @override
  void initState() {
    super.initState();
    _sheet.addListener(() {
      if (!_sheet.isAttached) return;
      final f = _sheet.size;
      if ((f - _sheetFraction).abs() > 0.002) {
        setState(() => _sheetFraction = f);
      }
    });
    _saved = SavedComparison(
      mapId: widget.map.id,
      sessionIdsA: widget.sessionIdsA,
      sessionIdsB: widget.sessionIdsB,
      createdAt: DateTime.now(),
    );
    _isSaved = SavedComparisonStore(ref.read(sharedPreferencesProvider))
        .contains(_saved);
    final saved =
        ref.read(sharedPreferencesProvider).getString(prefCompareView);
    _view = CompareView.values.asNameMap()[saved] ?? CompareView.winner;
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  void _setView(CompareView v) {
    setState(() => _view = v);
    try {
      ref.read(sharedPreferencesProvider).setString(prefCompareView, v.name);
    } catch (_) {}
  }

  Future<_Loaded> _load() async {
    final db = ref.read(databaseProvider);
    final sessions = await db.watchSessionsForMap(widget.map.id).first;
    final events = await db.watchEventsForMap(widget.map.id).first;
    final a = [
      for (final s in sessions)
        if (widget.sessionIdsA.contains(s.id)) s,
    ];
    final b = [
      for (final s in sessions)
        if (widget.sessionIdsB.contains(s.id)) s,
    ];
    final expected = expectedRigDelta(a, b);
    final check = checkComparable(a, b);
    if (!check.ok) {
      return _Loaded(a, b, check, null, expected);
    }

    SidePoints side(List<Session> group) {
      final ids = {for (final s in group) s.id};
      final lats = <double>[], lons = <double>[];
      final rssi = <double?>[], snr = <double?>[];
      for (final e in events) {
        if (e.direction == PacketDirection.tx ||
            e.rxLat == null ||
            e.rxLon == null ||
            !ids.contains(e.sessionId)) {
          continue;
        }
        lats.add(e.rxLat!);
        lons.add(e.rxLon!);
        rssi.add(e.rxRssi?.toDouble());
        snr.add(e.rxSnr);
      }
      return SidePoints(lats, lons, rssi, snr);
    }

    final result = await compareRoutesAsync(side(a), side(b));
    final range = await _loadRange(db, a, b, events, result);
    return _Loaded(a, b, check, result, expected, range);
  }

  Future<RangeComparison?> _loadRange(
      AppDatabase db,
      List<Session> a,
      List<Session> b,
      List<PacketEvent> events,
      RouteComparison? result) async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final pings = await db.watchPingsForMap(widget.map.id).first;
      final nodes = await db.getAllNodes();
      // The base radio of the newest session (sessions own their base
      // since schema v8; the map's is the fallback for older ones).
      final baseLocalId = await db.latestBaseNodeIdForMap(widget.map.id);
      final baseNode = nodes.where((n) => n.id == baseLocalId).firstOrNull;
      final map = await db.getCoverageMap(widget.map.id) ?? widget.map;
      final (nameA, nameB) = rangeSideNames(a, b);
      return compareRange(
        sessionsA: a,
        sessionsB: b,
        events: events,
        correlations: [for (final p in pings) p.correlation],
        nameA: nameA,
        nameB: nameB,
        userBase: map.baseLat != null && map.baseLon != null
            ? LatLng(map.baseLat!, map.baseLon!)
            : TerrainSettings.loadUserBase(prefs, widget.map.id),
        nodeBase: baseNode?.lastLat != null && baseNode?.lastLon != null
            ? LatLng(baseNode!.lastLat!, baseNode.lastLon!)
            : null,
        radioSetupBase: baseNode == null
            ? null
            : BaseLocationStore(prefs).load(baseNode.nodeId)?.point,
        baseNodeDbId: widget.map.baseNodeId,
        nodeNames: {
          for (final n in nodes)
            n.id: (n.userLabel?.isNotEmpty ?? false)
                ? n.userLabel!
                : n.longName.isNotEmpty
                    ? n.longName
                    : n.shortName.isNotEmpty
                        ? n.shortName
                        : '!${n.nodeId.toRadixString(16)}',
        },
        matchedCells: result == null
            ? 0
            : (result.rssi.cells > result.snr.cells
                ? result.rssi.cells
                : result.snr.cells),
      );
    } catch (e) {
      print('Distance comparison failed: $e');
      return null;
    }
  }

  /// One square per cell that either side measured, in its exact grid
  /// bounds: painted per [view], or a faint outline when the view has
  /// nothing for it. Sorted by colour so flutter_map batches equal styles
  /// into one path.
  List<Polygon> _cellPolygons(RouteComparison r, CompareView view, bool rssi) {
    final g = r.grid;
    final delta = rssi ? r.rssiDelta : r.snrDelta;
    final va = rssi ? r.rssiA : r.snrA;
    final vb = rssi ? r.rssiB : r.snrB;
    final clamp = rssi ? _rssiClampDb : _snrClampDb;
    final latStep = (g.north - g.south) / g.rows;
    final lonStep = (g.east - g.west) / g.cols;

    Color signal(double v) => rssi
        ? SignalColorMapper.fromRssi(v.round())
        : SignalColorMapper.fromSnr((v * 2).round() / 2);

    List<LatLng> square(int i) {
      final s = g.south + (i ~/ g.cols) * latStep;
      final w = g.west + (i % g.cols) * lonStep;
      return [
        LatLng(s, w),
        LatLng(s + latStep, w),
        LatLng(s + latStep, w + lonStep),
        LatLng(s, w + lonStep),
      ];
    }

    final outlines = <Polygon>[];
    final filled = <(int, int)>[]; // (argb, cell)
    for (var i = 0; i < delta.length; i++) {
      final a = va[i], b = vb[i], d = delta[i];
      if (a.isNaN && b.isNaN) continue;
      final Color? fill = switch (view) {
        CompareView.winner =>
          d.isNaN ? null : comparisonWinnerColor(d, comparisonClearDeltaDb),
        CompareView.gradient =>
          d.isNaN ? null : comparisonDeltaColor((d * 2).round() / 2, clamp),
        CompareView.aOnly => a.isNaN ? null : signal(a),
        CompareView.bOnly => b.isNaN ? null : signal(b),
      };
      if (fill == null) {
        outlines.add(Polygon(
          points: square(i),
          color: _outlineFill,
          borderColor: _outlineColor,
          borderStrokeWidth: 1,
        ));
      } else {
        filled.add((fill.withValues(alpha: _overlayOpacity).toARGB32(), i));
      }
    }
    filled.sort((x, y) => x.$1.compareTo(y.$1));
    return [
      ...outlines,
      for (final (argb, i) in filled)
        Polygon(points: square(i), color: Color(argb)),
    ];
  }

  /// Cell under [p], or -1 off the grid.
  int _cellAt(RouteComparison r, LatLng p) {
    final g = r.grid;
    if (p.latitude < g.south ||
        p.latitude >= g.north ||
        p.longitude < g.west ||
        p.longitude >= g.east) {
      return -1;
    }
    final col = ((p.longitude - g.west) / (g.east - g.west) * g.cols)
        .floor()
        .clamp(0, g.cols - 1);
    final row = ((p.latitude - g.south) / (g.north - g.south) * g.rows)
        .floor()
        .clamp(0, g.rows - 1);
    return row * g.cols + col;
  }

  void _onMapTap(RouteComparison r, LatLng p) {
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final i = _cellAt(r, p);
    if (i < 0) return;
    final a = (_rssi ? r.rssiA : r.snrA)[i];
    final b = (_rssi ? r.rssiB : r.snrB)[i];
    if (a.isNaN && b.isNaN) return;
    String value(double v) => v.isNaN
        ? 'no reading'
        : _rssi
            ? '${v.round()} dBm'
            : '${v.toStringAsFixed(1)} dB';
    final parts = ['A ${value(a)}', 'B ${value(b)}'];
    if (!a.isNaN && !b.isNaN) {
      final d = b - a;
      final mag = _rssi ? '${d.abs().round()}' : d.abs().toStringAsFixed(1);
      parts.add(d.abs() < comparisonClearDeltaDb
          ? 'tie ($mag dB)'
          : '${d > 0 ? 'B' : 'A'} +$mag dB');
    }
    messenger.showSnackBar(SnackBar(
      content: Text(parts.join(' · ')),
      duration: const Duration(seconds: 3),
    ));
  }

  /// Bounds of the cells that were compared (what the camera should fit).
  LatLngBounds _matchedBounds(RouteComparison r) {
    final g = r.grid;
    final d = _rssi ? r.rssiDelta : r.snrDelta;
    var minC = g.cols, maxC = -1, minR = g.rows, maxR = -1;
    for (var i = 0; i < d.length; i++) {
      if (d[i].isNaN) continue;
      final c = i % g.cols, row = i ~/ g.cols;
      if (c < minC) minC = c;
      if (c > maxC) maxC = c;
      if (row < minR) minR = row;
      if (row > maxR) maxR = row;
    }
    if (maxC < 0) {
      return LatLngBounds(LatLng(g.south, g.west), LatLng(g.north, g.east));
    }
    final latStep = (g.north - g.south) / g.rows;
    final lonStep = (g.east - g.west) / g.cols;
    return LatLngBounds(
      LatLng(g.south + minR * latStep, g.west + minC * lonStep),
      LatLng(g.south + (maxR + 1) * latStep, g.west + (maxC + 1) * lonStep),
    );
  }

  /// Open the guided test's Ask screen with the two rigs as the antennas
  /// to compare (A then B), so the same question is asked properly next
  /// time: same route, same start, base untouched.
  Future<void> _makeGuidedTest() async {
    final data = await _future;
    if (!mounted) return;
    var (a, b) = rangeSideNames(data.a, data.b);
    // Nothing tells the sides apart: placeholders, renamed on the Plan screen.
    if (a == b || (a == 'A' && b == 'B')) (a, b) = ('Antenna A', 'Antenna B');
    await GuidedTestFlow.open(
      context,
      mapId: widget.map.id,
      prefill: PlanIntent(
        template: PlanTemplate.antennas,
        variants: [a, b],
      ),
    );
  }

  Future<void> _toggleSaved() async {
    final store = SavedComparisonStore(ref.read(sharedPreferencesProvider));
    if (_isSaved) {
      await store.remove(_saved);
    } else {
      await store.add(_saved);
    }
    if (mounted) setState(() => _isSaved = !_isSaved);
  }

  /// The comparison card, sides named as in the distance section.
  Future<void> _fieldReport() async {
    final data = await _future;
    if (!mounted) return;
    final (nameA, nameB) = rangeSideNames(data.a, data.b);
    await showComparisonFieldReport(
      context,
      coverageMapId: widget.map.id,
      sides: [(nameA, widget.sessionIdsA), (nameB, widget.sessionIdsB)],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare'),
        actions: [
          IconButton(
            key: const ValueKey('compare-field-report'),
            tooltip: 'Share field report',
            icon: const Icon(Icons.summarize_outlined),
            onPressed: _fieldReport,
          ),
          IconButton(
            tooltip: 'Make this a guided test',
            icon: const Icon(Icons.route),
            onPressed: _makeGuidedTest,
          ),
          IconButton(
            tooltip: _isSaved ? 'Remove from saved' : 'Save comparison',
            icon: Icon(_isSaved ? Icons.bookmark : Icons.bookmark_border),
            onPressed: _toggleSaved,
          ),
        ],
      ),
      body: WideColumn(
        maxWidth: 900,
        child: FutureBuilder<_Loaded>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return const _Message('Could not compare these sessions.');
            }
            final data = snap.data;
            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (data.a.isEmpty || data.b.isEmpty) {
              return const _Message(
                  'Some of the sessions in this comparison were deleted.');
            }
            if (!data.check.ok) return _Message(data.check.refusal!);
            final result = data.result;
            if (result == null) {
              return const _Message(
                  'These sessions have no overlapping route (within 75 m), '
                  'so there is nothing to compare.');
            }
            return _body(data, result);
          },
        ),
      ),
    );
  }

  Widget _body(_Loaded data, RouteComparison result) {
    final stats = _rssi ? result.rssi : result.snr;
    final g = result.grid;
    final clamp = _rssi ? _rssiClampDb : _snrClampDb;
    final polygons = _polygons
        .putIfAbsent((_view, _rssi), () => _cellPolygons(result, _view, _rssi));
    final (nameA, nameB) = _sideNames(data.a, data.b);
    // The map fills the screen; the results are a draggable sheet over it,
    // so scrolling the results shrinks the map instead of fighting it.
    return LayoutBuilder(builder: (context, box) {
      final sheetPx = _sheetFraction * box.maxHeight;
      return Stack(
        children: [
          Positioned.fill(
            child: Stack(
              children: [
                FlutterMap(
                  key: ValueKey(_matchedBounds(result)),
                  options: MapOptions(
                    initialCenter: const LatLng(
                        AppConstants.defaultMapLat, AppConstants.defaultMapLon),
                    initialZoom: AppConstants.defaultMapZoom,
                    initialCameraFit: CameraFit.bounds(
                      bounds: _matchedBounds(result),
                      // The results sheet covers the lower half at first.
                      padding: EdgeInsets.fromLTRB(32, 32, 32,
                          MediaQuery.of(context).size.height * 0.5 + 24),
                      maxZoom: 17,
                    ),
                    onTap: (_, p) => _onMapTap(result, p),
                  ),
                  children: [
                    const BaseMapLayers(),
                    PolygonLayer(
                      polygons: polygons,
                      polygonLabels: false,
                      simplificationTolerance: 0,
                    ),
                  ],
                ),
                // Tile credit always visible and above the shading (OSM tile
                // policy): at the map's bottom edge, riding just above the
                // results sheet as on map detail, not on the route under the
                // view toggle.
                Positioned(
                  right: 8,
                  bottom: sheetPx + 8,
                  child: const MapCreditChip(),
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  right: 12,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: _ViewToggle(view: _view, onChanged: _setView),
                  ),
                ),
              ],
            ),
          ),
          DraggableScrollableSheet(
            controller: _sheet,
            initialChildSize: _sheetInitial,
            minChildSize: 0.22,
            maxChildSize: 0.94,
            snap: true,
            snapSizes: const [0.22, 0.5, 0.94],
            builder: (context, scrollController) => Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppTheme.radiusSheet)),
                border: Border(
                    top: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant)),
              ),
              child: ListView(
                controller: scrollController,
                // Clear Android's navigation bar / the home indicator.
                padding: EdgeInsets.fromLTRB(
                    12, 0, 12, 24 + MediaQuery.paddingOf(context).bottom),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Colour key for the map above, at the top of the sheet so
                  // it stays next to the map at every sheet height.
                  _ViewLegend(
                    view: _view,
                    rssi: _rssi,
                    clampDb: clamp,
                    nameA: nameA,
                    nameB: nameB,
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('RSSI')),
                      ButtonSegment(value: false, label: Text('SNR')),
                    ],
                    selected: {_rssi},
                    onSelectionChanged: (v) => setState(() => _rssi = v.first),
                  ),
                  const SizedBox(height: 8),
                  _SummaryCard(
                    data: data,
                    stats: stats,
                    cellMeters: g.cellMeters,
                    metricLabel: _rssi ? 'RSSI' : 'SNR',
                  ),
                  const SizedBox(height: 12),
                  if (data.range != null)
                    RangeComparisonSection(
                      range: data.range!,
                      comparabilityNote: comparabilityNote(data.a, data.b),
                    )
                  else
                    const Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text(
                            'By distance from base is unavailable: the base '
                            'position is unknown. Place the base on the '
                            "coverage map, or run Node Setup near it."),
                      ),
                    ),
                  const SizedBox(height: 8),
                  AiAnalysisCard(
                      a: data.a,
                      b: data.b,
                      result: result,
                      expected: data.expected,
                      check: data.check,
                      distanceStats: data.range == null
                          ? null
                          : digestDistanceStats(data.range!)),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _Message extends StatelessWidget {
  final String text;

  const _Message(this.text);

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}

/// Winner / Gradient / A only / B only, overlaid on the map.
class _ViewToggle extends StatelessWidget {
  final CompareView view;
  final ValueChanged<CompareView> onChanged;

  const _ViewToggle({required this.view, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final chrome = Theme.of(context).mapChrome;
    return Material(
      color: chrome.overlay,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(chrome.radius),
        side: BorderSide(color: chrome.hairline),
      ),
      child: SegmentedButton<CompareView>(
        segments: [
          for (final v in CompareView.values)
            ButtonSegment(value: v, label: Text(v.label)),
        ],
        selected: {view},
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
        ),
        onSelectionChanged: (v) => onChanged(v.first),
      ),
    );
  }
}

/// Key for the current [CompareView].
class _ViewLegend extends StatelessWidget {
  final CompareView view;
  final bool rssi;
  final double clampDb;
  final String? nameA, nameB;

  const _ViewLegend({
    required this.view,
    required this.rssi,
    required this.clampDb,
    required this.nameA,
    required this.nameB,
  });

  static Widget _swatch(Color color, Color edge, {bool outline = false}) =>
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: outline ? _outlineFill : color,
          border: Border.all(color: outline ? _outlineColor : edge, width: 1),
        ),
      );

  static Widget _item(Widget swatch, String text, TextStyle? style) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          swatch,
          const SizedBox(width: 5),
          Flexible(child: Text(text, style: style)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelMedium;
    final small = Theme.of(context).textTheme.labelSmall;
    final edge = scheme.outlineVariant;
    String side(String letter, String? name) =>
        name == null ? letter : '$letter — $name';
    final oneSide = _item(_swatch(_outlineColor, edge, outline: true),
        'Only one side measured', small);
    final threshold = comparisonClearDeltaDb.round();

    final Widget content = switch (view) {
      CompareView.winner => Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _item(_swatch(comparisonBetterAColor, edge),
                '${side('A', nameA)} wins', style),
            _item(_swatch(comparisonBetterBColor, edge),
                '${side('B', nameB)} wins', style),
            _item(_swatch(comparisonNeutralColor, edge), 'Tie (<$threshold dB)',
                style),
            oneSide,
          ],
        ),
      CompareView.gradient => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: const LinearGradient(colors: [
                  comparisonBetterAColor,
                  comparisonNeutralColor,
                  comparisonBetterBColor,
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('A better  -${clampDb.round()} dB', style: small),
                Text('equal', style: small),
                Text('+${clampDb.round()} dB  B better', style: small),
              ],
            ),
            const SizedBox(height: 4),
            oneSide,
          ],
        ),
      CompareView.aOnly || CompareView.bOnly => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${view == CompareView.aOnly ? side('A', nameA) : side('B', nameB)}'
              ' · Signal (${rssi ? 'RSSI' : 'SNR'})',
              style: small,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final (label, margin, dbm) in signalLevels)
                  _item(
                      _swatch(
                          rssi
                              ? SignalColorMapper.fromRssi(dbm)
                              : SignalColorMapper.fromMargin(margin),
                          edge),
                      label,
                      style),
                _item(_swatch(_outlineColor, edge, outline: true),
                    'Other side only', small),
              ],
            ),
          ],
        ),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: content,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final _Loaded data;
  final MetricStats stats;
  final double cellMeters;
  final String metricLabel;

  const _SummaryCard({
    required this.data,
    required this.stats,
    required this.cellMeters,
    required this.metricLabel,
  });

  String _pct(double v) => '${v.round()} %';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = data.expected;
    final areaKm2 = stats.cells * cellMeters * cellMeters / 1e6;
    final threshold = comparisonClearDeltaDb.round();

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label)),
              const SizedBox(width: 12),
              Flexible(
                child: Text(value,
                    textAlign: TextAlign.end, style: text.labelLarge),
              ),
            ],
          ),
        );

    final String expectedText;
    if (e.noProfiles) {
      expectedText = 'No hardware profile';
    } else if (e.deltaDb == null) {
      expectedText = 'Unknown (one side untagged)';
    } else {
      expectedText = '${formatGainDb(e.deltaDb!)} '
          '(mobile ${formatGainDb(e.mobileDeltaDb)}, '
          'base ${formatGainDb(e.baseDeltaDb)})';
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stats.cells == 0
                  ? 'No overlapping $metricLabel readings to compare.'
                  : comparisonVerdict(
                      measuredMedianDb: stats.medianDelta,
                      expected: e,
                      cells: stats.cells),
              style: text.titleSmall,
            ),
            if (data.check.warning != null) ...[
              const SizedBox(height: 6),
              Text(data.check.warning!,
                  style: text.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error)),
            ],
            const Divider(height: 20),
            row('Median B - A ($metricLabel)',
                stats.cells == 0 ? '-' : formatGainDb(stats.medianDelta)),
            row('Compared cells',
                '${stats.cells} (~${areaKm2.toStringAsFixed(2)} km²)'),
            row('B better by $threshold dB or more',
                stats.cells == 0 ? '-' : _pct(stats.pctBBetter)),
            row('A better by $threshold dB or more',
                stats.cells == 0 ? '-' : _pct(stats.pctABetter)),
            row('Expected from specs', expectedText),
            const Divider(height: 20),
            Text('A  ${describeSide(data.a)}', style: text.bodySmall),
            const SizedBox(height: 2),
            Text('B  ${describeSide(data.b)}', style: text.bodySmall),
            const SizedBox(height: 6),
            Text(
              'Cells are compared where both sides have readings within '
              '${comparisonMatchRadiusM.round()} m; outlined cells were '
              'covered by only one side. Tap a cell for its readings.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
