// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../services/guided/plan_models.dart';
import '../../../utils/constants.dart';
import '../../theme/app_theme.dart';
import '../base_map_layers.dart';
import 'guided_styles.dart';

String _mmss(int sec) {
  final m = sec ~/ 60, s = sec % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// "4 s ago" / "2 min ago" for the band.
String _ago(DateTime? at, DateTime now) {
  if (at == null) return '';
  final d = now.difference(at);
  if (d.inSeconds < 60) return '${d.inSeconds} s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  return '${d.inHours} h ago';
}

/// "● Base heard · 4 s ago · SNR +7.5" in the ok colours, or an amber
/// "● Base not heard" band.
class WalkBand extends StatelessWidget {
  const WalkBand({super.key, required this.state, this.now});

  final WalkState state;

  /// Injected by tests; defaults to the clock.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final status = context.status;
    final heard = state.baseHeard;
    final bg = heard ? status.okContainer : status.warningContainer;
    final fg = heard ? status.onOkContainer : status.onWarningContainer;
    final ago = _ago(state.baseLastHeardAt, now ?? DateTime.now());
    final snr = state.lastSnr;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              heard
                  ? '● Base heard${ago.isEmpty ? '' : ' · $ago'}'
                  : '● Base not heard${ago.isEmpty ? '' : ' · last $ago'}',
              style: TextStyle(color: fg, fontSize: 14),
            ),
          ),
          if (snr != null)
            Text(
              'SNR ${snr >= 0 ? '+' : ''}${snr.toStringAsFixed(1)}',
              style: context.guidedMono.copyWith(color: fg),
            ),
        ],
      ),
    );
  }
}

/// Four cells: ELAPSED / PLANNED / ROUTE MATCH / PINGS, mono values.
class WalkHud extends StatelessWidget {
  const WalkHud({super.key, required this.state, this.probeLabel = 'PINGS'});

  final WalkState state;

  /// "PINGS" on Meshtastic, "LINK CHECKS" on MeshCore.
  final String probeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = theme.colorScheme.outlineVariant;
    Widget cell(String label, String value,
            {Color? color, bool last = false}) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: last ? null : Border(right: BorderSide(color: line)),
            ),
            // Large text or a narrow phone: shrink a cell rather than
            // break "07:40" or "ELAPSED" mid-word. One word per line keeps
            // "ROUTE MATCH" on two lines as before.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(label.replaceAll(' ', '\n'),
                      style: context.guidedMonoLabel.copyWith(fontSize: 10)),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      maxLines: 1,
                      style: context.readout.value
                          .copyWith(fontSize: 18, color: color)),
                ),
              ],
            ),
          ),
        );
    final match = state.routeMatchPct;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          cell('ELAPSED', _mmss(state.elapsedSec)),
          cell('PLANNED', _mmss(state.plannedSec)),
          cell('ROUTE MATCH', match == null ? '—' : '${match.round()} %',
              color: theme.colorScheme.secondary),
          cell(probeLabel, '${state.pingsAnswered}/${state.pingsSent}',
              color: theme.status.ok, last: true),
        ],
      ),
    );
  }
}

/// The walk's map: this walk's track as a 3 px ink line, the ghost route
/// (first pass) as a dashed cyan line, the base as an orange diamond with
/// "BASE", my position cyan, and a small legend. Follows the walker; a pan
/// or zoom pauses that for [resumeFollowAfter] (or until the locate button),
/// like the Live map. TestFlight 2026-11-10: following stopped for good
/// after any touch, e.g. a page scroll that started on the map.
class WalkMap extends StatefulWidget {
  const WalkMap({
    super.key,
    required this.state,
    this.base,
    this.height = 300,
  });

  /// How long a pan or zoom keeps the map where the walker put it.
  static const resumeFollowAfter = Duration(seconds: 15);

  final WalkState state;

  /// Where the base stands (the map's base location), if known.
  final LatLng? base;
  final double height;

  @override
  State<WalkMap> createState() => _WalkMapState();
}

class _WalkMapState extends State<WalkMap> {
  final _controller = MapController();
  bool _follow = true;
  Timer? _resume;

  List<LatLng> get _all => [
        ...widget.state.ghostRoute,
        ...widget.state.track,
        if (widget.base != null) widget.base!,
      ];

  LatLng? get _me =>
      widget.state.track.isNotEmpty ? widget.state.track.last : null;

  @override
  void didUpdateWidget(WalkMap old) {
    super.didUpdateWidget(old);
    final me = _me;
    final was = old.state.track.isNotEmpty ? old.state.track.last : null;
    if (_follow && me != null && me != was) _centre(me);
  }

  void _centre(LatLng p) {
    try {
      _controller.move(p, _controller.camera.zoom);
    } catch (_) {
      // Not laid out yet.
    }
  }

  /// The person moved the map: stop following for a while.
  void _pause() {
    _resume?.cancel();
    _resume = Timer(WalkMap.resumeFollowAfter, _followAgain);
    if (_follow) setState(() => _follow = false);
  }

  void _followAgain() {
    _resume?.cancel();
    if (!mounted) return;
    setState(() => _follow = true);
    if (_me case final me?) _centre(me);
  }

  @override
  void dispose() {
    _resume?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chrome = theme.mapChrome;
    final points = _all;
    final me = widget.state.track.isNotEmpty ? widget.state.track.last : null;
    final distinct = points.toSet();
    final ink = scheme.onSurface;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: me ??
                    widget.base ??
                    const LatLng(
                        AppConstants.defaultMapLat, AppConstants.defaultMapLon),
                initialZoom: 16,
                initialCameraFit: distinct.length >= 2
                    ? CameraFit.coordinates(
                        coordinates: points,
                        padding: const EdgeInsets.all(28),
                        maxZoom: 18,
                      )
                    : null,
                onPositionChanged: (_, hasGesture) {
                  if (hasGesture) _pause();
                },
              ),
              children: [
                const BaseMapLayers(),
                if (widget.state.ghostRoute.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: widget.state.ghostRoute,
                        color: scheme.secondary.withValues(alpha: 0.75),
                        strokeWidth: 4,
                        pattern: StrokePattern.dashed(segments: const [8, 7]),
                      ),
                    ],
                  ),
                if (widget.state.track.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: widget.state.track,
                        color: ink,
                        strokeWidth: 3,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (widget.base != null)
                      Marker(
                        point: widget.base!,
                        width: 72,
                        height: 24,
                        alignment: Alignment.centerRight,
                        child: _BaseDiamond(
                            color: scheme.primary,
                            label: ink,
                            bg: scheme.surface),
                      ),
                    if (me != null)
                      Marker(
                        point: me,
                        width: 22,
                        height: 22,
                        child: _MyDot(color: scheme.secondary),
                      ),
                  ],
                ),
              ],
            ),
            if (!_follow && me != null)
              Positioned(
                right: 8,
                bottom: 8,
                child: Material(
                  color: chrome.overlay,
                  shape: const CircleBorder(),
                  child: IconButton(
                    key: const ValueKey('walk-map-follow'),
                    tooltip: 'Follow me',
                    icon: Icon(Icons.my_location, color: scheme.secondary),
                    onPressed: _followAgain,
                  ),
                ),
              ),
            // Tile credit always visible (OSM tile policy), not behind the
            // attribution button's tap.
            const Positioned(
              right: 8,
              top: 8,
              child: MapCreditChip(),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: chrome.overlay,
                  border: Border.all(color: chrome.hairline),
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LegendLine(
                        color: ink,
                        label: 'this walk',
                        fg: chrome.onOverlayMuted),
                    if (widget.state.ghostRoute.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      _LegendLine(
                          color: scheme.secondary,
                          label: 'walk 1 (follow it)',
                          fg: chrome.onOverlayMuted),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendLine extends StatelessWidget {
  const _LegendLine(
      {required this.color, required this.label, required this.fg});

  final Color color, fg;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 3, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, color: fg)),
        ],
      );
}

/// Orange diamond with "BASE" to its right.
class _BaseDiamond extends StatelessWidget {
  const _BaseDiamond(
      {required this.color, required this.label, required this.bg});

  final Color color, label, bg;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.rotate(
            angle: math.pi / 4,
            child: Container(width: 12, height: 12, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            'BASE',
            style: TextStyle(
              fontFamily: ReadoutStyles.monoFamily,
              fontSize: 11,
              color: label,
              shadows: [Shadow(color: bg, blurRadius: 3)],
            ),
          ),
        ],
      );
}

/// My position: a cyan dot with a soft halo.
class _MyDot extends StatelessWidget {
  const _MyDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.25), shape: BoxShape.circle),
          ),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ],
      );
}
