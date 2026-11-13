// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/database/app_database.dart';
import '../../data/radio/radio_types.dart' show BeaconKind, RadioProtocol;
import '../../demo/demo_mode.dart';
import '../protocol_text.dart';
import '../../providers.dart';
import '../../services/base_location.dart';
import '../../services/field_report/field_report_data.dart';
import '../../services/link_asymmetry.dart';
import '../../services/pro_entitlement.dart';
import '../../services/rig_comparison.dart';
import '../../services/rig_math.dart';
import '../../services/track_distance.dart';
import '../../services/coverage_interpolation.dart';
import '../../services/estimate_samples.dart';
import '../../services/terrain/elevation_source.dart';
import '../../services/terrain/terrain_coverage.dart';
import '../../services/terrain/terrain_service.dart';
import '../../services/terrain/terrain_settings.dart';
import '../../services/session_radio_settings.dart';
import '../../utils/constants.dart';
import '../../utils/coverage_raster.dart';
import '../../utils/link_margin.dart';
import '../../utils/signal_color_mapper.dart';
import '../layout/window_class.dart';
import '../theme/app_theme.dart';
import '../widgets/terrain_opt_in_sheet.dart';
import '../widgets/base_map_layers.dart';
import '../widgets/create_map_dialog.dart';
import '../widgets/comparison_actions.dart';
import 'pro_paywall_screen.dart';
import '../widgets/export_dialog.dart';
import '../widgets/field_report/field_report_sheet.dart';
import '../widgets/guided/tests_section.dart';
import '../widgets/terrain_profile_sheet.dart';

final _sessionsForMapProvider =
    StreamProvider.family<List<Session>, int>((ref, mapId) {
  return ref.watch(databaseProvider).watchSessionsForMap(mapId);
});

final _eventsForMapProvider =
    StreamProvider.family<List<PacketEvent>, int>((ref, mapId) {
  return ref.watch(databaseProvider).watchEventsForMap(mapId);
});

final _pingsForMapProvider =
    StreamProvider.family<List<PingResult>, int>((ref, mapId) {
  return ref.watch(databaseProvider).watchPingsForMap(mapId);
});

enum _Layer { signal, pings }

/// Space above the sheet taken by the map credit row (8 pt margin, the
/// one-line chip, a 6 pt gap): the legend sits on top of it.
const double _creditRowPx = 34;

/// Ping outcome colours.
const _pingOk = Color(0xFF27AE60);
const _pingRelayed = Color(0xFFF1C40F);

/// Throttled by the radio's duty-cycle limit: neither delivered nor failed.
const _pingThrottled = Color(0xFFE67E22);
const _pingFailed = Color(0xFFC0392B);
const _pingPending = Color(0xFF95A5A6);

/// Estimated-coverage overlay ready to draw: the raster and where it goes.
class _Estimate {
  final LatLngBounds bounds;
  final ImageProvider image;

  const _Estimate(this.bounds, this.image);
}

/// Terrain-aware estimate ready to draw, with its fit quality.
class _TerrainEstimate {
  final LatLngBounds bounds;
  final ImageProvider image;
  final double? rmseDb;
  final bool terrainUnavailable;
  final String? unavailableReason;

  const _TerrainEstimate(
      this.bounds, this.image, this.rmseDb, this.terrainUnavailable,
      [this.unavailableReason]);
}

/// Overall opacity of the estimated layer, so the map and dots stay readable.
const _estimatedOpacity = 0.45;

/// One coverage map: recorded points on a map plus its sessions, filterable
/// by session and modem preset so presets can be compared.
class CoverageMapDetailScreen extends ConsumerStatefulWidget {
  final CoverageMap map;

  /// Open on the Pings layer instead of Signal.
  final bool showPings;

  /// Open with the Estimated coverage overlay on (demo screenshots).
  final bool showEstimated;

  /// Open the line-of-sight profile sheet for this point once the screen is
  /// up (demo screenshots).
  final LatLng? openProfileAt;

  const CoverageMapDetailScreen({
    super.key,
    required this.map,
    this.showPings = false,
    this.showEstimated = false,
    this.openProfileAt,
    this.showOnlySessions,
  });

  /// When set, only these sessions start ticked (a guided test's walks,
  /// from its result's "Open on map").
  final Set<int>? showOnlySessions;

  @override
  ConsumerState<CoverageMapDetailScreen> createState() =>
      _CoverageMapDetailScreenState();
}

class _CoverageMapDetailScreenState
    extends ConsumerState<CoverageMapDetailScreen> {
  final _mapController = MapController();
  final Set<int> _hiddenSessions = {};

  /// Sessions picked for deletion; null when not in delete mode.
  Set<int>? _deleting;

  /// Margin scale (decode limit, sensitivity) of each session's preset,
  /// for link-margin colours.
  Map<int, MarginScale> _marginScales = const {};

  MarginScale _scaleOf(PacketEvent e) =>
      _marginScales[e.sessionId] ?? MarginScale.fallback;
  String? _presetFilter; // null = all presets
  late Set<int>? _onlyPending = widget.showOnlySessions;
  late _Layer _layer = widget.showPings ? _Layer.pings : _Layer.signal;
  bool _fitted = false;

  // Estimated coverage (interpolated between measurements, with unanswered
  // pings as "no margin" samples: see EstimateSamples).
  late bool _estimated = widget.showEstimated;
  String? _estimateSilentLine; // chip line for the silence samples used
  /// MeshCore when every visible session is MeshCore ("link checks").
  RadioProtocol _probeProtocol = RadioProtocol.meshtastic;

  // Results sheet (sessions, layer controls) over the map.
  static const _sheetInitial = 0.42, _sheetMin = 0.12;

  /// Pixels of map covered by the sheet right now (for camera fits).
  double get _sheetPxNow => _docked
      ? 0
      : _sheet.isAttached
          ? _sheet.pixels
          : _sheetFraction * 500;

  /// Results in a column beside the map instead of the sheet over it
  /// ([WindowClass.sidePanel]: wide iPads, Duo unfolded sideways).
  bool _docked = false;
  static const _dockedResultsWidth = 400.0;

  /// Keeps the map (camera, overlays) when the results move between the
  /// sheet and the column (rotation, Split View resize, fold/unfold).
  final _mapStackKey = GlobalKey(debugLabel: 'coverage-map');
  final _sheet = DraggableScrollableController();
  double _sheetFraction = _sheetInitial;
  Timer? _estimateTimer;
  String? _estimateKey; // selection the overlay should show
  _Estimate? _estimate; // last finished overlay (may lag _estimateKey)
  final Map<String, _Estimate?> _estimateCache = {}; // null = no data

  // Terrain-aware estimate (sub-option of Estimated).
  bool _terrainAware = false;
  Timer? _terrainTimer;
  String? _terrainKey;
  _TerrainEstimate? _terrainEstimate; // last finished (may lag _terrainKey)
  final Map<String, _TerrainEstimate?> _terrainCache = {};
  TerrainCancelToken? _terrainCancel;
  double? _terrainProgress; // non-null while fetching

  // Base location: the map's own (CoverageMaps.baseLat/baseLon, schema v8;
  // older placements in SharedPreferences as a fallback) wins over the
  // base node's last known position (Nodes table).
  LatLng? _userBase;
  bool _placingBase = false;
  List<PacketEvent> _rx = const []; // visible signal events, for readings

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
    final m = widget.map;
    _userBase = m.baseLat != null && m.baseLon != null
        ? LatLng(m.baseLat!, m.baseLon!)
        : TerrainSettings.loadUserBase(
            ref.read(sharedPreferencesProvider), widget.map.id);
    final at = widget.openProfileAt;
    if (at != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) _openProfile(at);
      });
    }
  }

  @override
  void dispose() {
    _sheet.dispose();
    _estimateTimer?.cancel();
    _terrainTimer?.cancel();
    _terrainCancel?.cancel();
    super.dispose();
  }

  /// Local Nodes.id of the base radio: the newest session's own (schema
  /// v8), else the map's (older maps).
  int? get _baseLocalId {
    final sessions =
        ref.read(_sessionsForMapProvider(widget.map.id)).valueOrNull ??
            const <Session>[];
    for (final s in sessions) {
      if (s.baseNodeId != null) return s.baseNodeId;
    }
    return widget.map.baseNodeId;
  }

  LatLng? _nodeBase(List<Node>? nodes) {
    final baseId = _baseLocalId;
    for (final n in nodes ?? const <Node>[]) {
      if (n.id == baseId && n.lastLat != null && n.lastLon != null) {
        return LatLng(n.lastLat!, n.lastLon!);
      }
    }
    return null;
  }

  /// Base location now: the user's placement, else the base node's own
  /// position, else where the phone was when it set the base up.
  Future<LatLng?> _resolveBase() async {
    final user = _userBase;
    if (user != null) return user;
    final nodes = await ref.read(databaseProvider).getAllNodes();
    final fromNode = _nodeBase(nodes);
    if (fromNode != null) return fromNode;
    final baseId = _baseLocalId;
    final baseNum =
        nodes.where((n) => n.id == baseId).map((n) => n.nodeId).firstOrNull;
    if (baseNum == null) return null;
    // The user declined the Radio Setup location for this map.
    if (TerrainSettings.loadBaseOptOut(
        ref.read(sharedPreferencesProvider), widget.map.id)) {
      return null;
    }
    return BaseLocationStore(ref.read(sharedPreferencesProvider))
        .load(baseNum)
        ?.point;
  }

  Future<void> _setUserBase(LatLng? p) async {
    await ref
        .read(databaseProvider)
        .setMapBaseLocation(widget.map.id, p?.latitude, p?.longitude);
    await TerrainSettings.saveUserBase(
        ref.read(sharedPreferencesProvider), widget.map.id, p);
    if (!mounted) return;
    setState(() {
      _userBase = p;
      _placingBase = false;
    });
  }

  /// Long-press: terrain profile from the base to the pressed point.
  Future<void> _onLongPress(LatLng p) async {
    final base = await _resolveBase();
    if (!mounted) return;
    if (base == null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Where is the base?'),
          content: const Text(
              "The base node's position isn't known yet. Place the base "
              'here? You can move it later from the menu (top right).'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Set base here')),
          ],
        ),
      );
      if (ok == true) {
        await _setUserBase(p);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Base set. Long-press elsewhere for a profile.')));
        }
      }
      return;
    }
    _openProfile(p, base: base);
  }

  Future<void> _openProfile(LatLng target, {LatLng? base}) async {
    base ??= await _resolveBase();
    if (!mounted || base == null) return;
    if (!await ensureTerrainOptIn(context, ref)) return;
    if (!mounted) return;
    await showTerrainProfileSheet(
      context,
      base: base,
      target: target,
      readings: [
        for (final e in _rx)
          if (e.rxLat != null && e.rxLon != null)
            ProfileReading(LatLng(e.rxLat!, e.rxLon!),
                rssi: e.rxRssi, snr: e.rxSnr),
      ],
    );
  }

  /// "Sessions · Select…" above the list, or the selection bar with Move
  /// and Delete.
  Widget _deleteBar(List<Session> sessions) {
    final picked = _deleting;
    if (picked == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
        child: Row(
          children: [
            Text('Sessions', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.checklist, size: 18),
              label: const Text('Select…'),
              onPressed: () => setState(() => _deleting = {}),
            ),
          ],
        ),
      );
    }
    final red = Theme.of(context).colorScheme.error;
    final n = picked.isEmpty ? '' : ' ${picked.length}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          const Expanded(child: Text('Pick sessions')),
          TextButton(
            onPressed: () => setState(() => _deleting = null),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('move-sessions'),
            onPressed: picked.isEmpty
                ? null
                : () => _moveSessions(sessions, picked.toList()),
            child: Text('Move$n…'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: red),
            onPressed: picked.isEmpty
                ? null
                : () => _deleteSessions(sessions, picked.toList()),
            child: Text('Delete$n'),
          ),
        ],
      ),
    );
  }

  /// Sessions recorded on the wrong map: file them under another one.
  Future<void> _moveSessions(List<Session> all, List<int> ids) async {
    final recording = ref.read(sessionManagerProvider).activeSession?.id;
    if (ids.contains(recording)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Stop the session first: one of these is recording.')));
      return;
    }
    final db = ref.read(databaseProvider);
    final maps = (await db.getAllCoverageMaps())
        .where((m) => m.id != widget.map.id)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    final n = ids.length;
    final target = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(n == 1 ? 'Move session to…' : 'Move $n sessions to…'),
        children: [
          for (final m in maps)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, m.id),
              child: Text(m.name),
            ),
          SimpleDialogOption(
            onPressed: () async {
              final id = await showCreateMapDialog(context, ref);
              if (context.mounted) Navigator.pop(context, id);
            },
            child: const Row(children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: 8),
              Text('New map…'),
            ]),
          ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    await db.moveSessions(ids, target);
    // A saved comparison mixing maps would compare different base
    // positions; drop the moved sessions from any.
    await SavedComparisonStore(ref.read(sharedPreferencesProvider))
        .removeSessions(ids.toSet());
    if (!mounted) return;
    final name = (await db.getAllCoverageMaps())
            .where((m) => m.id == target)
            .map((m) => m.name)
            .firstOrNull ??
        'the other map';
    if (!mounted) return;
    setState(() {
      _deleting = null;
      _hiddenSessions.removeAll(ids);
      _fitted = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            n == 1 ? 'Session moved to $name' : '$n sessions moved to $name')));
  }

  Future<void> _deleteSessions(List<Session> all, List<int> ids) async {
    final recording = ref.read(sessionManagerProvider).activeSession?.id;
    if (ids.contains(recording)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Stop the session first: one of these is recording.')));
      return;
    }
    final n = ids.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(n == 1 ? 'Delete session?' : 'Delete $n sessions?'),
        content: const Text('Permanently deletes their packets and ping '
            'results, and any saved comparison that uses them. The map '
            'stays. Export first if you want to keep them. This can\'t be '
            'undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await ref.read(databaseProvider).deleteSessions(ids);
    await SavedComparisonStore(ref.read(sharedPreferencesProvider))
        .removeSessions(ids.toSet());
    if (!mounted) return;
    setState(() {
      _deleting = null;
      _hiddenSessions.removeAll(ids);
      _fitted = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n == 1 ? 'Session deleted' : '$n sessions deleted')));
  }

  /// Hides every session but [ids] and refits the map to them (a test's
  /// walks, from the Tests row). TestFlight 2026-11-10: "test should be
  /// selectable to have its points visible".
  void _showOnly(List<Session> sessions, Set<int> ids) {
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing recorded in this test yet.')));
      return;
    }
    setState(() {
      _hiddenSessions
        ..clear()
        ..addAll([
          for (final s in sessions)
            if (!ids.contains(s.id)) s.id,
        ]);
      _presetFilter = null;
      _fitted = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ids.length == 1
            ? 'Showing this test\'s session only. Tick the others to bring them back.'
            : 'Showing this test\'s ${ids.length} sessions only. Tick the others to bring them back.')));
  }

  bool _visible(Session s) =>
      !_hiddenSessions.contains(s.id) &&
      (_presetFilter == null || s.loraPreset == _presetFilter);

  @override
  Widget build(BuildContext context) {
    final mapId = widget.map.id;
    final sessions =
        ref.watch(_sessionsForMapProvider(mapId)).valueOrNull ?? const [];
    final events =
        ref.watch(_eventsForMapProvider(mapId)).valueOrNull ?? const [];
    final pings =
        ref.watch(_pingsForMapProvider(mapId)).valueOrNull ?? const [];

    // First load with showOnlySessions: hide the rest once, before use.
    if (_onlyPending case final only? when sessions.isNotEmpty) {
      _onlyPending = null;
      _hiddenSessions.addAll([
        for (final s in sessions)
          if (!only.contains(s.id)) s.id,
      ]);
    }
    final visibleIds = {
      for (final s in sessions)
        if (_visible(s)) s.id,
    };
    _marginScales = {
      for (final s in sessions) s.id: MarginScale.forPresetId(s.loraPreset),
    };
    final rx = [
      for (final e in events)
        // Ping replies ('ack') are base → you measurements too.
        if (e.direction != PacketDirection.tx &&
            e.rxLat != null &&
            e.rxLon != null &&
            visibleIds.contains(e.sessionId))
          e,
    ];
    // Every visible session is MeshCore: its probes are link checks.
    final visibleSessions = [
      for (final s in sessions)
        if (visibleIds.contains(s.id)) s
    ];
    final probeProtocol = visibleSessions.isNotEmpty &&
            visibleSessions
                .every((s) => sessionProtocol(s) == RadioProtocol.meshcore)
        ? RadioProtocol.meshcore
        : RadioProtocol.meshtastic;
    _probeProtocol = probeProtocol;
    final visiblePings = [
      for (final p in pings)
        if (p.tx.rxLat != null &&
            p.tx.rxLon != null &&
            visibleIds.contains(p.tx.sessionId))
          p,
    ];

    final points = _layer == _Layer.signal
        ? [for (final e in rx) LatLng(e.rxLat!, e.rxLon!)]
        : [for (final p in visiblePings) LatLng(p.tx.rxLat!, p.tx.rxLon!)];
    _fitOnce(points);

    final metric = ref
            .read(sharedPreferencesProvider)
            .getString(AppConstants.prefColorMetric) ??
        'snr';
    _rx = rx;
    final showEstimate = _estimated && _layer == _Layer.signal;
    final base = _userBase ?? _nodeBase(ref.watch(nodesProvider).valueOrNull);
    final terrainOn = showEstimate && _terrainAware && base != null;
    if (showEstimate && !terrainOn) {
      _scheduleEstimate(rx, visiblePings, metric == 'rssi', probeProtocol);
    }
    if (terrainOn) _scheduleTerrain(rx, base);
    final terrainEstimate = terrainOn ? _terrainEstimate : null;

    final presets = {
      for (final s in sessions)
        if (s.loraPreset.isNotEmpty) s.loraPreset,
    }.toList()
      ..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.map.name),
        actions: [
          // Compare is the one action testers look for here, so it carries
          // its name; the rest are text items in the overflow menu (a bare
          // glyph says little and iOS users never see the tooltip).
          ProGate(
            feature: ProFeature.rigComparison,
            onUnlocked: _openComparePicker,
            builder: (context, unlocked, activate) => TextButton.icon(
              key: const ValueKey('map-compare'),
              icon: const Icon(Icons.compare_arrows),
              label: const Text('Compare'),
              // Demo mode behaves as Pro.
              onPressed: DemoMode.enabled ? _openComparePicker : activate,
            ),
          ),
          // Export, saved comparisons, the estimated / terrain-aware layers
          // and the base location live in this menu, so nothing sits
          // between the map and the session list.
          PopupMenuButton<String>(
            key: const ValueKey('map-menu'),
            tooltip: 'More',
            onSelected: (v) async {
              switch (v) {
                case 'export':
                  _export(null);
                case 'saved':
                  _showSavedComparisons();
                case 'estimated':
                  setState(() {
                    _estimated = !_estimated;
                    if (!_estimated) _cancelTerrain();
                  });
                case 'terrain':
                  if (_terrainAware) {
                    _cancelTerrain();
                  } else {
                    if (!await ensureTerrainOptIn(this.context, ref)) return;
                    if (!mounted) return;
                    setState(() => _terrainAware = true);
                    if (base == null) {
                      ScaffoldMessenger.of(this.context)
                          .showSnackBar(const SnackBar(
                              content: Text('Set the base location first: this '
                                  'menu → Set base location')));
                    }
                  }
                case 'place':
                  setState(() => _placingBase = true);
                case 'reset':
                  _setUserBase(null);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text('Export / share…'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (SavedComparisonStore(ref.read(sharedPreferencesProvider))
                  .forMap(widget.map.id)
                  .isNotEmpty)
                const PopupMenuItem(
                  value: 'saved',
                  child: ListTile(
                    leading: Icon(Icons.bookmarks_outlined),
                    title: Text('Saved comparisons…'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(
                value: 'estimated',
                checked: _estimated && _layer == _Layer.signal,
                enabled: _layer == _Layer.signal,
                child: const Text('Estimated coverage'),
              ),
              CheckedPopupMenuItem(
                value: 'terrain',
                checked: _terrainAware,
                enabled: _estimated && _layer == _Layer.signal,
                child: const Text('Terrain-aware estimate'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'place', child: Text('Set base location…')),
              if (_userBase != null)
                const PopupMenuItem(
                    value: 'reset',
                    child: Text("Use the base node's position")),
              const PopupMenuItem(
                enabled: false,
                child: Text('Long-press the map for a\nline-of-sight profile'),
              ),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, box) {
        // Results sheet over a full-height map: drag it down to see more
        // map, up to read the sessions. Map overlays ride on top of it.
        _docked = WindowClass.of(context).hasSidePanel;
        final sheetPx = _docked ? 0.0 : _sheetFraction * box.maxHeight;
        final mapStack = Stack(
          key: _mapStackKey,
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: points.isNotEmpty
                    ? points.first
                    : const LatLng(
                        AppConstants.defaultMapLat,
                        AppConstants.defaultMapLon,
                      ),
                initialZoom: AppConstants.defaultMapZoom,
                onLongPress: (_, p) => _onLongPress(p),
                onTap: (tap, p) {
                  if (_placingBase) {
                    _setUserBase(p);
                  } else if (_layer == _Layer.pings) {
                    _showPingAt(tap.relative, visiblePings, events);
                  }
                },
              ),
              children: [
                const BaseMapLayers(),
                if (terrainEstimate != null)
                  OverlayImageLayer(
                    overlayImages: [
                      OverlayImage(
                        bounds: terrainEstimate.bounds,
                        imageProvider: terrainEstimate.image,
                        opacity: _estimatedOpacity,
                        gaplessPlayback: true,
                      ),
                    ],
                  ),
                if (showEstimate && !terrainOn && _estimate != null)
                  OverlayImageLayer(
                    overlayImages: [
                      OverlayImage(
                        bounds: _estimate!.bounds,
                        imageProvider: _estimate!.image,
                        opacity: _estimatedOpacity,
                        gaplessPlayback: true,
                      ),
                    ],
                  ),
                CircleLayer(
                  circles: _layer == _Layer.signal
                      ? [for (final e in rx) _signalDot(e)]
                      : [for (final p in visiblePings) _pingDot(p)],
                ),
                if (base != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: base,
                      width: 34,
                      height: 34,
                      child: const Icon(Icons.cell_tower,
                          size: 28,
                          color: Color(0xFF3987E5),
                          shadows: [
                            Shadow(color: Colors.white, blurRadius: 4),
                          ]),
                    ),
                  ]),
              ],
            ),
            // Map style, clear of the credit chip below it.
            if (!_placingBase)
              Positioned(
                right: 8,
                bottom: sheetPx + 52,
                child: const MapStyleButton(),
              ),
            // Tile credit above the sheet (the OSM tile policy wants
            // it visible), not inside the map where the sheet hides it.
            // A row of its own, right-aligned: a long credit (Terrain
            // lists three sources) shortens with an ellipsis instead
            // of running under the legend.
            Positioned(
              left: 8,
              right: 8,
              bottom: sheetPx + 8,
              child: const Align(
                alignment: Alignment.centerRight,
                child: MapCreditChip(),
              ),
            ),
            // The legend stacks above the credit row, so neither
            // covers the other at phone width.
            Positioned(
              left: 8,
              bottom: sheetPx + _creditRowPx,
              child: _Legend(
                  layer: _layer,
                  rssiScale: terrainEstimate != null || metric == 'rssi',
                  hasRelayed: rx.any((e) => e.hopCount > 0)),
            ),
            if (showEstimate)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_terrainAware && base == null)
                      const _EstimatedChip(
                          line1: 'Set the base location to use terrain',
                          line2: 'Menu (top right) → Set base location')
                    else if (terrainOn && terrainEstimate != null)
                      _EstimatedChip(
                        line1: terrainEstimate.terrainUnavailable
                            ? (terrainEstimate.unavailableReason ==
                                    ElevationDisabled.userMessage
                                ? '${ElevationDisabled.userMessage} — '
                                    'showing distance-only estimate'
                                : 'Terrain data unavailable — '
                                    'distance-only estimate')
                            : 'Estimated (terrain) — not measured',
                        line2: [
                          if (terrainEstimate.rmseDb != null)
                            '±${terrainEstimate.rmseDb!.toStringAsFixed(1)} dB',
                          'RSSI colors',
                        ].join(' · '),
                      )
                    else if (!terrainOn)
                      _EstimatedChip(line2: _estimateSilentLine),
                    if (_terrainProgress != null)
                      _TerrainProgress(
                        progress: _terrainProgress!,
                        onCancel: _cancelTerrain,
                      ),
                  ],
                ),
              ),
            if (_placingBase)
              Positioned(
                left: 8,
                right: 8,
                bottom: sheetPx + 48,
                child: Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.cell_tower),
                    title: const Text('Tap the map where the base is'),
                    trailing: TextButton(
                      onPressed: () => setState(() => _placingBase = false),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
              ),
            if (points.isEmpty)
              const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No points with GPS yet'),
                  ),
                ),
              ),
          ],
        );
        // The floating sheet clears Android's navigation bar / the home
        // indicator itself; the docked panel sits in a SafeArea.
        final sheetInset = MediaQuery.paddingOf(context).bottom;
        Widget results(ScrollController? scrollController) => ListView(
              controller: scrollController,
              padding: EdgeInsets.only(
                  bottom: 24 + (scrollController == null ? 0 : sheetInset)),
              children: [
                if (!_docked)
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: SegmentedButton<_Layer>(
                    segments: [
                      const ButtonSegment(
                        value: _Layer.signal,
                        icon: Icon(Icons.signal_cellular_alt),
                        // Labels shrink rather than wrap into a
                        // clipped second line (large text, MeshCore's
                        // longer "Link checks").
                        label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Signal (base → you)')),
                      ),
                      ButtonSegment(
                        value: _Layer.pings,
                        // A reply needs both legs: a round trip.
                        icon: const Icon(Icons.sync_alt),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                              '${probeNoun(_probeProtocol, plural: true, capital: true)} (you ⇄ base)'),
                        ),
                      ),
                    ],
                    selected: {_layer},
                    onSelectionChanged: (s) => setState(() {
                      _layer = s.first;
                      _fitted = false;
                    }),
                  ),
                ),
                if (presets.length > 1)
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final p in [null, ...presets])
                          Padding(
                            padding: const EdgeInsets.only(right: 6, top: 6),
                            child: ChoiceChip(
                              label: Text(p == null
                                  ? 'All range settings'
                                  : anyPresetDisplayName(p)),
                              selected: _presetFilter == p,
                              onSelected: (_) => setState(() {
                                _presetFilter = p;
                                _fitted = false;
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                GuidedTestsSection(
                  mapId: widget.map.id,
                  onShowOnly: (ids) => _showOnly(sessions, ids),
                ),
                if (sessions.isNotEmpty) _deleteBar(sessions),
                if (sessions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No sessions recorded yet')),
                  )
                else ...[
                  for (final s in sessions)
                    _SessionTile(
                      session: s,
                      events: [
                        for (final e in events)
                          if (e.sessionId == s.id) e,
                      ],
                      pings: [
                        for (final p in pings)
                          if (p.tx.sessionId == s.id) p,
                      ],
                      shown: _visible(s),
                      dimmed: _presetFilter != null &&
                          s.loraPreset != _presetFilter,
                      deleting: _deleting != null,
                      markedForDelete: _deleting?.contains(s.id) ?? false,
                      onMarkForDelete: (mark) => setState(() {
                        mark ? _deleting?.add(s.id) : _deleting?.remove(s.id);
                      }),
                      onToggle: (show) => setState(() {
                        show
                            ? _hiddenSessions.remove(s.id)
                            : _hiddenSessions.add(s.id);
                        _fitted = false;
                      }),
                      onExport: () => _export(s),
                      onFieldReport: () =>
                          showSessionFieldReport(context, s.id),
                      base: base == null
                          ? null
                          : (lat: base.latitude, lon: base.longitude),
                      miles: ref.watch(useMilesProvider),
                    ),
                ],
              ],
            );
        if (_docked) {
          final colors = Theme.of(context).colorScheme;
          return Row(
            children: [
              Expanded(child: mapStack),
              DecoratedBox(
                key: const ValueKey('coverage-results-docked'),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  border:
                      Border(left: BorderSide(color: colors.outlineVariant)),
                ),
                child: SizedBox(
                  width: _dockedResultsWidth,
                  child: SafeArea(
                    top: false,
                    left: false,
                    child: results(null),
                  ),
                ),
              ),
            ],
          );
        }
        return Stack(
          children: [
            Positioned.fill(child: mapStack),
            DraggableScrollableSheet(
              controller: _sheet,
              initialChildSize: _sheetInitial,
              minChildSize: _sheetMin,
              maxChildSize: 0.92,
              snap: true,
              snapSizes: const [_sheetMin, _sheetInitial, 0.92],
              builder: (context, scrollController) => Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppTheme.radiusSheet)),
                  border: Border(
                      top: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant)),
                ),
                child: results(scrollController),
              ),
            ),
          ],
        );
      }),
    );
  }

  /// Recomputes the estimated overlay for the visible Signal-layer points,
  /// debounced and cached per selection (sessions, preset filter, metric,
  /// points). Interpolation runs on a background isolate.
  void _scheduleEstimate(List<PacketEvent> rx, List<PingResult> pings,
      bool rssi, RadioProtocol protocol) {
    // SNR is interpolated as link margin, so sessions on different presets
    // blend on one scale; silence (unanswered pings) is no margin.
    final samples = EstimateSamples.from(
        rx: rx, pings: pings, rssi: rssi, scaleOf: _scaleOf);
    final key = '${rssi ? 'rssi' : 'snr'}|${protocol.name}|'
        '${Object.hashAll(samples.ids)}|${samples.ids.length}';
    if (key == _estimateKey) return;
    _estimateKey = key;
    final n = samples.silent;
    _estimateSilentLine = n == 0
        ? null
        : '$n ${probeNoun(protocol, plural: n != 1)} with no direct reply '
            '${n == 1 ? 'counts' : 'count'} as '
            '${rssi ? 'no signal' : 'no margin'}';
    _estimateTimer?.cancel();
    if (_estimateCache.containsKey(key)) {
      _estimate = _estimateCache[key];
      return;
    }
    if (samples.isEmpty) {
      _estimate = null;
      return;
    }
    final lats = samples.lats, lons = samples.lons, values = samples.values;
    _estimateTimer = Timer(const Duration(milliseconds: 350), () async {
      Object? failure;
      _Estimate? result;
      try {
        final grid = await interpolateCoverageAsync(lats, lons, values);
        if (grid != null) {
          final image = await coverageGridImage(grid, rssi: rssi);
          result = _Estimate(
            LatLngBounds(
              LatLng(grid.south, grid.west),
              LatLng(grid.north, grid.east),
            ),
            image,
          );
        }
      } catch (e) {
        failure = e;
        print('Estimated coverage failed: $e');
      }
      if (failure == null) {
        if (_estimateCache.length >= 6) {
          _estimateCache.remove(_estimateCache.keys.first);
        }
        _estimateCache[key] = result;
      }
      if (mounted && _estimateKey == key) {
        setState(() => _estimate = result);
      }
    });
  }

  /// Stops a running terrain computation and switches Terrain-aware off.
  void _cancelTerrain() {
    _terrainCancel?.cancel();
    _terrainCancel = null;
    _terrainTimer?.cancel();
    _terrainKey = null;
    if (mounted) {
      setState(() {
        _terrainAware = false;
        _terrainProgress = null;
      });
    } else {
      _terrainAware = false;
      _terrainProgress = null;
    }
  }

  /// Computes (debounced, cached per selection) the terrain-aware overlay
  /// from the visible RSSI readings. Elevation fetches show progress and can
  /// be cancelled; a changed selection cancels the previous run.
  void _scheduleTerrain(List<PacketEvent> rx, LatLng base) {
    final used = [
      for (final e in rx)
        if (e.rxRssi != null) e,
    ];
    final prefs = ref.read(sharedPreferencesProvider);
    final settings = TerrainSettings.load(prefs);
    final freq = ref.read(meshRadioProvider).regionFrequencyMHz;
    final key = 'terrain|$freq|${settings.baseHeightM}|'
        '${settings.mobileHeightM}|${base.latitude},${base.longitude}|'
        '${Object.hashAll([for (final e in used) e.id])}|${used.length}';
    if (key == _terrainKey) return;
    _terrainCancel?.cancel();
    _terrainCancel = null;
    _terrainTimer?.cancel();
    _terrainKey = key;
    if (_terrainCache.containsKey(key)) {
      _terrainEstimate = _terrainCache[key];
      _terrainProgress = null;
      return;
    }
    if (used.isEmpty) {
      _terrainEstimate = null;
      _terrainProgress = null;
      return;
    }
    final lats = [for (final e in used) e.rxLat!];
    final lons = [for (final e in used) e.rxLon!];
    final values = [for (final e in used) e.rxRssi!.toDouble()];
    final service = ref.read(terrainServiceProvider);
    _terrainTimer = Timer(const Duration(milliseconds: 600), () async {
      final token = TerrainCancelToken();
      _terrainCancel = token;
      if (mounted) setState(() => _terrainProgress = 0);
      _TerrainEstimate? result;
      var failed = false;
      try {
        final tc = await terrainCoverage(
          service: service,
          base: base,
          lats: lats,
          lons: lons,
          rssi: values,
          frequencyMHz: freq,
          baseHeightM: settings.baseHeightM,
          mobileHeightM: settings.mobileHeightM,
          cancel: token,
          onProgress: (p) {
            if (mounted && _terrainKey == key) {
              setState(() => _terrainProgress = p);
            }
          },
        );
        if (tc != null) {
          final image = await coverageGridImage(tc.grid, rssi: true);
          result = _TerrainEstimate(
            LatLngBounds(
              LatLng(tc.grid.south, tc.grid.west),
              LatLng(tc.grid.north, tc.grid.east),
            ),
            image,
            tc.rmseDb,
            tc.terrainUnavailable,
            tc.unavailableReason,
          );
        }
      } on TerrainCancelled {
        return;
      } catch (e) {
        failed = true;
        print('Terrain-aware estimate failed: $e');
      }
      if (_terrainKey != key) return;
      // A distance-only fallback is not cached: retry when back online.
      if (!failed && result != null && !result.terrainUnavailable) {
        if (_terrainCache.length >= 4) {
          _terrainCache.remove(_terrainCache.keys.first);
        }
        _terrainCache[key] = result;
      }
      if (mounted) {
        setState(() {
          _terrainEstimate = result;
          _terrainProgress = null;
        });
      }
    });
  }

  /// Camera padding that keeps the fitted route above the results sheet.
  ///
  /// The sheet can cover 92% of the screen; padding the camera by its full
  /// height would leave flutter_map a zero-height viewport, which it fits
  /// at zoom 0 (the whole world). Cap the bottom padding so at least 40% of
  /// the map stays usable.
  EdgeInsets _fitPadding() {
    final mapH = _mapController.camera.nonRotatedSize.height;
    final bottom = math.min(40 + _sheetPxNow, mapH * 0.6);
    return EdgeInsets.fromLTRB(40, 40, 40, bottom);
  }

  /// A fix at exactly 0,0 is a GPS failure, not a place; keep it out of
  /// the camera fit so one bad row cannot zoom the map out to the ocean.
  static List<LatLng> _fitPoints(List<LatLng> points) => [
        for (final p in points)
          if (p.latitude != 0 || p.longitude != 0) p
      ];

  /// Zoom floor for fits: a coverage map is a few km across, never a
  /// continent.
  static const _fitMinZoom = 10.0;

  void _fitOnce(List<LatLng> all) {
    final points = _fitPoints(all);
    if (_fitted || points.isEmpty) return;
    _fitted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(points.first, 16);
      } else {
        _mapController.fitCamera(CameraFit.coordinates(
          coordinates: points,
          padding: _fitPadding(),
          minZoom: _fitMinZoom,
          maxZoom: 17,
        ));
      }
      if (DemoMode.enabled) _demoReloadTiles(points);
    });
  }

  /// Demo mode (screenshots): tiles sometimes never load on this screen in
  /// the simulator; zooming out and back in forces a fresh load.
  Future<void> _demoReloadTiles(List<LatLng> points) async {
    await Future<void>.delayed(const Duration(seconds: 6));
    if (!mounted || points.length < 2) return;
    final camera = _mapController.camera;
    _mapController.move(camera.center, camera.zoom - 1);
    await Future<void>.delayed(const Duration(seconds: 6));
    if (!mounted) return;
    _mapController.fitCamera(CameraFit.coordinates(
      coordinates: points,
      padding: _fitPadding(),
      minZoom: _fitMinZoom,
      maxZoom: 17,
    ));
  }

  CircleMarker _signalDot(PacketEvent e) {
    final metric = ref
            .read(sharedPreferencesProvider)
            .getString(AppConstants.prefColorMetric) ??
        'snr';
    final Color color;
    if (metric == 'rssi' && e.rxRssi != null) {
      color = SignalColorMapper.fromRssi(e.rxRssi!);
    } else if (_scaleOf(e).marginDb(snr: e.rxSnr, rssi: e.rxRssi)
        case final m?) {
      color = SignalColorMapper.fromMargin(m);
    } else {
      color = SignalColorMapper.noData;
    }
    return CircleMarker(
      point: LatLng(e.rxLat!, e.rxLon!),
      radius: e.hopCount == 0 ? 7 : 4, // relayed packets drawn smaller
      color: color.withValues(alpha: 0.85),
      borderColor: Colors.black54,
      borderStrokeWidth: 1,
    );
  }

  CircleMarker _pingDot(PingResult p) {
    return CircleMarker(
      point: LatLng(p.tx.rxLat!, p.tx.rxLon!),
      radius: 7,
      color: _pingColor(p).withValues(alpha: 0.85),
      borderColor: Colors.black54,
      borderStrokeWidth: 1,
    );
  }

  /// Tap on the round-trip layer: the nearest ping dot's outcome and, when
  /// the protocol measures both legs (MeshCore), Up / Down SNR.
  void _showPingAt(
      Offset? at, List<PingResult> pings, List<PacketEvent> events) {
    if (at == null || pings.isEmpty) return;
    final camera = _mapController.camera;
    PingResult? best;
    var bestD = 24.0;
    for (final p in pings) {
      final d =
          (camera.latLngToScreenOffset(LatLng(p.tx.rxLat!, p.tx.rxLon!)) - at)
              .distance;
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    if (best == null) return;
    final ackId = best.correlation.ackEventId;
    final ack =
        ackId == null ? null : events.where((e) => e.id == ackId).firstOrNull;
    final text = _isPending(best)
        ? 'Waiting for the reply'
        : roundTripReadout(
            status: best.correlation.ackStatus,
            downSnr: ack?.rxSnr,
            downRssi: ack?.rxRssi,
            upSnr: ack?.uplinkSnr,
            roundTripMs: best.correlation.roundTripMs,
          );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('ping-readout'),
        content: Text(text),
        duration: const Duration(seconds: 4),
      ));
  }

  void _openComparePicker() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => RigComparisonPickerScreen(map: widget.map),
        ))
        // A comparison saved there shows up in the menu.
        .then((_) => mounted ? setState(() {}) : null);
  }

  /// Saved comparisons of this map (always viewable, Pro or not).
  void _showSavedComparisons() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SavedComparisonsSheet(map: widget.map),
    ).then((_) => mounted ? setState(() {}) : null);
  }

  Future<void> _export(Session? s) => showExportDialog(
        context,
        ref,
        mapId: widget.map.id,
        mapName: widget.map.name,
        sessionId: s?.id,
        sessionTitle: s == null ? null : _sessionTitle(s),
      );
}

bool _isPending(PingResult p) =>
    p.correlation.ackEventId == null &&
    p.correlation.ackStatus == AckStatus.timeout &&
    DateTime.now().difference(p.tx.timestamp).inSeconds <
        AppConstants.defaultAckTimeoutSec;

Color _pingColor(PingResult p) {
  if (_isPending(p)) return _pingPending;
  switch (p.correlation.ackStatus) {
    case AckStatus.received:
      return _pingOk;
    case AckStatus.implicit:
      return _pingRelayed;
    case AckStatus.throttled:
      return _pingThrottled;
    default:
      return _pingFailed;
  }
}

String _sessionTitle(Session s) {
  if (s.name.isNotEmpty) return s.name;
  final t = s.startedAt.toLocal();
  return 'Session ${t.month}/${t.day} '
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

/// "Base heard" as the Field Report counts it: beacons heard plus pings
/// answered (received or relayed) over beacons expected plus pings that went
/// on air (NAKs and throttled pings never did). A pulled MeshCore beacon
/// (`BeaconKind.trace`) is those pings, so pass no [beacons] for it.
({int heard, int expected}) sessionBaseHeard(
    {BeaconStats? beacons, required Iterable<PingCorrelation> pings}) {
  var heard = beacons?.heard ?? 0;
  var expected = (beacons?.heard ?? 0) + (beacons?.missed ?? 0);
  for (final p in pings) {
    final st = p.ackStatus;
    if (st == AckStatus.throttled || AckStatus.isError(st)) continue;
    expected++;
    if (st == AckStatus.received || st == AckStatus.implicit) heard++;
  }
  return (heard: heard, expected: expected);
}

/// A distance from the base: "2.2 mi" / "3.5 km", short ones in feet or
/// metres.
String _farText(double m, {required bool miles}) =>
    formatTrackDistance(m, miles: miles) ??
    (miles ? '${(m * 3.28084).round()} ft' : '${m.round()} m');

/// One session on the map: a dimmed setup line (range setting, radio
/// settings, hardware), a stats line with the two numbers a tester scans
/// for in bold (base heard, farthest from the base) and the details.
class _SessionTile extends ConsumerStatefulWidget {
  final Session session;
  final List<PacketEvent> events;
  final List<PingResult> pings;
  final bool shown;
  final bool dimmed;
  final ValueChanged<bool> onToggle;
  final VoidCallback onExport;
  final VoidCallback onFieldReport;

  /// The map's base location, for "farthest" (none without it).
  final GeoPoint? base;

  /// Distances in miles (Settings → Units).
  final bool miles;

  /// Delete mode: the checkbox picks the session for deletion instead of
  /// showing or hiding it. A recording session can't be picked.
  final bool deleting;
  final bool markedForDelete;
  final ValueChanged<bool> onMarkForDelete;

  const _SessionTile({
    required this.session,
    required this.events,
    required this.pings,
    required this.shown,
    required this.dimmed,
    required this.onToggle,
    required this.onExport,
    required this.onFieldReport,
    required this.base,
    required this.miles,
    required this.deleting,
    required this.markedForDelete,
    required this.onMarkForDelete,
  });

  @override
  ConsumerState<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends ConsumerState<_SessionTile> {
  Object? _farKey;
  double? _farthestM;

  /// Farthest reading from the base with a second one near it, as the
  /// Field Report has it. Rebuilt only when the rows or the base change
  /// (the tile rebuilds on every sheet drag).
  double? get _farthest {
    final w = widget;
    final key = (
      w.events.length,
      w.events.isEmpty ? null : w.events.last.id,
      w.base,
    );
    if (key != _farKey) {
      _farKey = key;
      _farthestM = w.events.isEmpty || w.base == null
          ? null
          : FieldReportData.build(
              [SessionReportInput(session: w.session, events: w.events)],
              base: w.base,
            ).farthestM;
    }
    return _farthestM;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final events = widget.events;
    final pings = widget.pings;
    final miles = widget.miles;

    final rx = events.where((e) => e.direction != PacketDirection.tx);
    // Link margin on the legend's scale (SNR near the limit, RSSI over
    // sensitivity once SNR saturates), not raw SNR.
    final scale = MarginScale.forPresetId(session.loraPreset);
    final margins = [
      for (final e in rx)
        if (scale.marginDb(snr: e.rxSnr, rssi: e.rxRssi) case final m?) m,
    ]..sort();
    final allDone = pings.where((p) => !_isPending(p)).toList();
    final throttled = allDone
        .where((p) => p.correlation.ackStatus == AckStatus.throttled)
        .length;
    // Throttled pings were never sent: not delivered, not failed.
    final done = allDone
        .where((p) => p.correlation.ackStatus != AckStatus.throttled)
        .toList();
    final ok =
        done.where((p) => p.correlation.ackStatus == AckStatus.received).length;
    final relayed =
        done.where((p) => p.correlation.ackStatus == AckStatus.implicit).length;
    // Failure reasons: "no reply" for timeouts, else the radio's NAK reason.
    final failures = <String, int>{};
    for (final p in done) {
      final status = p.correlation.ackStatus;
      if (status == AckStatus.timeout) {
        failures['no reply'] = (failures['no reply'] ?? 0) + 1;
      } else if (AckStatus.isError(status)) {
        final reason = status.contains(':') ? status.split(':').last : 'error';
        failures[reason] = (failures[reason] ?? 0) + 1;
      }
    }

    final t = session.startedAt.toLocal();
    final end = session.endedAt?.toLocal();
    final duration = (end ?? DateTime.now()).difference(t);

    final mobileRig = RigSpec.decode(session.mobileRigJson);
    final baseRig = RigSpec.decode(session.baseRigJson);
    String rigLine(String role, RigSpec r) =>
        '$role: ${r.name} (${formatGainDb(r.netGainDb)})';
    final mobileModel = radioModelName(session.hwNodeModel);

    // Distance driven while recording, for a mileage log.
    final distance = formatTrackDistance(trackDistanceM(events), miles: miles);

    final trace = session.beaconKind == BeaconKind.trace.dbValue;
    final beacons =
        trace ? null : ref.watch(beaconStatsProvider(session.id)).valueOrNull;
    final heard = sessionBaseHeard(
        beacons: beacons,
        // A ping still waiting for its reply isn't counted yet.
        pings: [for (final p in allDone) p.correlation]);
    final heardPct = heard.expected == 0
        ? null
        : (100 * heard.heard / heard.expected).round();
    final far = _farthest;

    final setup = <String>[
      if (session.loraPreset.isNotEmpty)
        anyPresetDisplayName(session.loraPreset),
      if (session.radioSettingsLine case final line when line.isNotEmpty) line,
      if (mobileRig != null)
        rigLine('Mobile', mobileRig)
      else if (mobileModel.isNotEmpty)
        'Mobile: $mobileModel',
      if (baseRig != null) rigLine('Base', baseRig),
    ];
    final details = <String>[
      if (distance != null) '$distance driven',
      if (margins.isNotEmpty)
        'Margin ${_signedDb(margins.first)}…${_signedDb(margins.last)} dB '
            '(median ${_signedDb(margins[margins.length ~/ 2])})',
      // Round trips: a reply needs both directions.
      if (done.isNotEmpty)
        '${probeNounFor(session.protocol, plural: true)} $ok/${done.length} came back'
            '${relayed > 0 ? ', $relayed relayed' : ''}'
            '${failures.isEmpty ? '' : ' (${failures.entries.map((e) => '${e.value} ${e.key}').join(', ')})'}',
      if (throttled > 0) '$throttled throttled',
      // MeshCore traces carry both legs; Meshtastic shows nothing here.
      if (linkAsymmetryFromEvents(events) case final a?)
        linkAsymmetryText(a,
            noun: probeNounFor(session.protocol, plural: true)),
    ];

    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    final strong = body?.copyWith(fontWeight: FontWeight.w700);
    final dim = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final minor = '${duration.inMinutes} min'
        '${session.isActive ? ' (recording)' : ''} · ${rx.length} readings';
    final subtitle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (setup.isNotEmpty)
          Text(setup.join(' · '),
              key: ValueKey('session-setup-${session.id}'), style: dim),
        Text.rich(
          key: ValueKey('session-stats-${session.id}'),
          TextSpan(style: body, children: [
            if (heardPct != null) ...[
              const TextSpan(text: 'Base heard '),
              TextSpan(text: '$heardPct %', style: strong),
              const TextSpan(text: ' · '),
            ],
            if (far != null) ...[
              const TextSpan(text: 'Farthest '),
              TextSpan(text: _farText(far, miles: miles), style: strong),
              const TextSpan(text: ' · '),
            ],
            TextSpan(text: minor, style: dim),
          ]),
        ),
        if (details.isNotEmpty) Text(details.join(' · '), style: dim),
      ],
    );

    if (widget.deleting) {
      return CheckboxListTile(
        value: widget.markedForDelete,
        onChanged:
            session.isActive ? null : (v) => widget.onMarkForDelete(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: theme.colorScheme.error,
        title: Text(_sessionTitle(session)),
        subtitle: subtitle,
      );
    }
    return Opacity(
      opacity: widget.dimmed ? 0.4 : 1,
      child: CheckboxListTile(
        value: widget.shown,
        onChanged: widget.dimmed ? null : (v) => widget.onToggle(v ?? true),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(_sessionTitle(session)),
        subtitle: subtitle,
        secondary: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: ValueKey('field-report-${session.id}'),
              icon: const Icon(Icons.summarize_outlined),
              tooltip: 'Share field report',
              onPressed: session.isActive ? null : widget.onFieldReport,
            ),
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Export…',
              onPressed: widget.onExport,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown while the estimated layer is on: it is modelled, not measured.
class _EstimatedChip extends StatelessWidget {
  final String line1;
  final String? line2;

  const _EstimatedChip({
    this.line1 = 'Estimated — not measured',
    this.line2,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chrome = theme.mapChrome;
    final small = theme.textTheme.bodySmall;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: chrome.panel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.blur_on, size: 14, color: chrome.onOverlayMuted),
          const SizedBox(width: 4),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line1, style: small?.copyWith(color: chrome.onOverlay)),
                if (line2 != null)
                  Text(line2!,
                      style: small?.copyWith(color: chrome.onOverlayMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Progress of the terrain download / prediction, with a cancel button.
class _TerrainProgress extends StatelessWidget {
  final double progress;
  final VoidCallback onCancel;

  const _TerrainProgress({required this.progress, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chrome = theme.mapChrome;
    final small = theme.textTheme.bodySmall;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: chrome.panel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 90,
            child:
                LinearProgressIndicator(value: progress <= 0 ? null : progress),
          ),
          const SizedBox(width: 8),
          Text('Terrain ${(progress * 100).round()}%',
              style: small?.copyWith(color: chrome.onOverlay)),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: chrome.onOverlay,
                textStyle: small),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final _Layer layer;

  /// Show the RSSI colour scale instead of SNR (terrain estimate / RSSI
  /// metric).
  final bool rssiScale;

  /// Some visible signal dots are relayed (drawn small), so the dot-size
  /// note is worth showing.
  final bool hasRelayed;

  const _Legend(
      {required this.layer, this.rssiScale = false, this.hasRelayed = false});

  /// A ping the radio held back for its duty cycle (never sent).
  static const _heldBack = 'Held back by radio';

  @override
  Widget build(BuildContext context) {
    final items = layer == _Layer.signal
        ? (rssiScale
            ? [
                (SignalColorMapper.fromRssi(-60), 'Strong (-70 dBm or more)'),
                (SignalColorMapper.fromRssi(-95), 'OK (about -95 dBm)'),
                (SignalColorMapper.fromRssi(-130), 'None (-120 dBm or less)'),
              ]
            : [
                for (final b in MarginBand.values)
                  (b.colour, '${b.label} (${b.range} margin)'),
              ])
        : [
            (_pingOk, 'Base replied'),
            (_pingRelayed, 'Relayed only'),
            (_pingFailed, 'No reply or refused'),
            (_pingThrottled, _heldBack),
          ];
    final theme = Theme.of(context);
    final chrome = theme.mapChrome;
    final small = theme.textTheme.bodySmall;
    final note = small?.copyWith(color: chrome.onOverlayMuted);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: chrome.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (color, label) in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(label == _heldBack ? Icons.hourglass_bottom : Icons.circle,
                    size: 10, color: color),
                const SizedBox(width: 6),
                Text(label, style: small?.copyWith(color: chrome.onOverlay)),
              ],
            ),
          if (layer == _Layer.signal && !rssiScale)
            Text("Margin: dB above the range setting's limit", style: note),
          if (layer == _Layer.signal && hasRelayed)
            Text('Small dot: relayed', style: note),
          if (layer == _Layer.pings)
            Text('A reply needs both directions', style: note),
        ],
      ),
    );
  }
}

/// A margin in whole dB with its sign: "+7", "−3", "0".
String _signedDb(double db) {
  final r = db.round();
  return r > 0 ? '+$r' : (r < 0 ? '−${-r}' : '0');
}
