// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/database/app_database.dart';
import '../../data/radio/mesh_radio.dart';
import '../../demo/demo_mode.dart';
import '../../models/processed_signal_event.dart';
import '../../providers.dart';
import '../../services/range_test_detector.dart';
import '../../services/active_probe_service.dart';
import '../../utils/constants.dart';
import '../../utils/link_margin.dart';
import '../../utils/signal_color_mapper.dart';
import '../layout/window_class.dart';
import '../widgets/base_map_layers.dart';
import '../widgets/connection_banner.dart';
import '../widgets/get_started_card.dart';
import '../widgets/other_radio_banner.dart';
import '../widgets/beacon_status.dart';
import '../widgets/range_test_dialog.dart';
import '../widgets/ride_along_banner.dart';
import '../widgets/session_panel.dart';
import '../widgets/signal_charts_panel.dart';
import '../widgets/signal_display.dart';
import '../widgets/base_status_bar.dart';
import '../widgets/setup_mismatch_banner.dart';
import '../widgets/signal_legend.dart';
import 'radio_setup_screen.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  static const _maxDots = 5000;
  final List<CircleMarker> _signalDots = [];

  /// A relayed (hop count > 0) dot has been drawn: the legend explains the
  /// small dots only then.
  bool _hasRelayedDot = false;
  bool _centeredOnGps = false;
  bool _chartsOpen = DemoMode.enabled && DemoMode.screen == 'charts';

  /// The session panel docked beside the map ([WindowClass.sidePanel]
  /// windows only; a phone gets the bottom sheet).
  bool _panelDocked = false;

  /// Keeps the map (camera, dots, timers) when the panel docks or undocks
  /// and the map moves into or out of the row beside it.
  final _mapKey = GlobalKey(debugLabel: 'live-map');
  int? _dotsSessionId;
  bool _demoPanelShown = false;

  /// Where the phone is (blue dot) and whether the map follows it.
  Position? _myPos;
  bool _follow = true;
  StreamSubscription<Position>? _posSub;

  /// While recording, following resumes this long after the last touch: in
  /// a moving car a brushed or bumped screen shouldn't lose the map.
  static const _resumeFollowAfter = Duration(seconds: 15);
  Timer? _resumeFollow;

  /// Map orientation. North up by default; a two-finger twist rotates the
  /// map freely and the compass button puts north back. "Heading up" turns
  /// the map with the phone's compass instead (tester feedback, 2026-11-01)
  /// and goes with following: it is wanted (remembered) while the user has
  /// it on, and active only while the map also follows the phone. A pan
  /// suspends it with follow and it comes back with follow; a twist turns it
  /// off, since the user took the rotation over (Apple Maps behaviour).
  bool _headingWanted = false;
  bool get _headingActive => _headingSub != null;
  double _rotation = 0; // the camera's current rotation, degrees
  StreamSubscription<double?>? _headingSub;
  StreamSubscription<MapEvent>? _mapEvents;

  @override
  void initState() {
    super.initState();
    // Centre on the first GPS fix (or the last known one).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSessionDots(ref.read(sessionManagerProvider).activeSession);
      _mapEvents = _mapController.mapEventStream.listen((e) {
        final r = e.camera.rotation;
        if ((r - _rotation).abs() > 0.5 && mounted) {
          setState(() => _rotation = r);
        }
        // A twist by the user (not our own compass rotate) takes the
        // rotation over: heading up goes off and the map stays as turned.
        if (e is MapEventRotate &&
            _headingWanted &&
            e.source != MapEventSource.mapController &&
            e.source != MapEventSource.fitCamera) {
          _setHeadingWanted(false, keepRotation: true);
          _announce('Heading up off');
        }
      });
      if (DemoMode.enabled) return; // demo frames the recorded walk instead
      if (ref
              .read(sharedPreferencesProvider)
              .getBool(AppConstants.prefMapHeadingUp) ==
          true) {
        _setHeadingWanted(true);
      }
      final gps = ref.read(gpsServiceProvider);
      final pos = gps.lastPosition;
      if (pos != null) {
        _myPos = pos;
        _centerOn(pos.latitude, pos.longitude);
      }
      _posSub = gps.positionStream.listen((p) {
        if (!mounted) return;
        setState(() => _myPos = p);
        _centerOn(p.latitude, p.longitude);
        // Keep the phone in view while recording, unless the user panned.
        if (_follow && _centeredOnGps) {
          _mapController.move(
              LatLng(p.latitude, p.longitude), _mapController.camera.zoom);
        }
      }, onError: (_) {});
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _resumeFollow?.cancel();
    _headingSub?.cancel();
    _mapEvents?.cancel();
    super.dispose();
  }

  /// Turn heading-up on or off. On: the map follows the phone again and
  /// turns with the compass. Off: north goes back up, unless the user just
  /// twisted the map themselves ([keepRotation]).
  void _setHeadingWanted(bool on, {bool keepRotation = false}) {
    if (mounted) setState(() => _headingWanted = on);
    ref
        .read(sharedPreferencesProvider)
        .setBool(AppConstants.prefMapHeadingUp, on);
    if (on) {
      _recenter(); // following is part of heading up
    } else {
      _syncHeading();
      if (!keepRotation) _mapController.rotate(0);
    }
  }

  /// Following the phone on or off; heading up is active only while both
  /// it and following are on.
  void _setFollow(bool on) {
    if (mounted && _follow != on) setState(() => _follow = on);
    _syncHeading();
  }

  /// Subscribe to the compass while heading up is wanted and the map
  /// follows the phone; let go otherwise (the map stays as it is turned).
  void _syncHeading() {
    final want = _headingWanted && _follow && mounted;
    if (want == _headingActive) return;
    if (!want) {
      _headingSub?.cancel();
      _headingSub = null;
      if (mounted) setState(() {});
      return;
    }
    _headingSub = ref.read(headingSourceProvider).headings.listen((h) {
      if (h == null || !mounted || !_headingActive) return;
      // Map rotation is counter-clockwise degrees; facing east (90) means
      // turning the map -90 so east is up. Skip sub-degree jitter.
      final target = -h;
      var delta = (target - _mapController.camera.rotation) % 360;
      if (delta > 180) delta -= 360;
      if (delta.abs() < 1) return;
      _mapController.rotate(target);
    }, onError: (_) {});
    if (mounted) setState(() {});
  }

  /// The compass button: heading up → north up; rotated → north up;
  /// north up → heading up (and following). Each change of mode says so
  /// once: the same button means two things, and only trying it shows
  /// which (new-user walkthrough 2026-11-08).
  void _onCompassTap() {
    if (_headingActive) {
      _setHeadingWanted(false);
      _announce('North up');
    } else if (_rotation.abs() > 0.5) {
      if (_headingWanted) {
        _setHeadingWanted(false);
      } else {
        _mapController.rotate(0);
      }
      _announce('North up');
    } else {
      // Also a paused heading up at north (after a pan): it resumes.
      _setHeadingWanted(true);
      _announce('Heading up: the map turns with you');
    }
  }

  /// A short floating note for an orientation change, replacing any
  /// earlier one so quick taps never queue up.
  void _announce(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('compass-mode'),
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1500),
      ));
  }

  /// Heading up is on but the map stopped turning with the compass (the
  /// user panned): it comes back with following.
  bool get _headingPaused => _headingWanted && !_headingActive;

  String get _compassTooltip => _headingActive
      ? 'Heading up · tap for north up'
      : _headingPaused
          ? (_rotation.abs() > 0.5
              ? 'Heading up paused · center on me to resume, or tap for '
                  'north up'
              : 'Heading up paused · tap to resume')
          : _rotation.abs() > 0.5
              ? 'Tap for north up'
              : 'North up · tap to follow and turn with you';

  /// The Live colour key: on by default (never set = on), off only when
  /// the user turned it off in Settings → Display.
  bool get _legendOn =>
      ref.watch(showSignalLegendProvider) ||
      ref
              .read(sharedPreferencesProvider)
              .getBool(AppConstants.prefShowSignalLegend) ==
          null;

  /// "You are here" dot (the theme's cyan) with its accuracy ring.
  List<CircleMarker> get _myLocation {
    final p = _myPos;
    if (p == null) return const [];
    final here = LatLng(p.latitude, p.longitude);
    final hereColor = Theme.of(context).colorScheme.secondary;
    return [
      if (p.accuracy > 0)
        CircleMarker(
          point: here,
          radius: p.accuracy,
          useRadiusInMeter: true,
          color: hereColor.withValues(alpha: 0.15),
          borderColor: hereColor.withValues(alpha: 0.4),
          borderStrokeWidth: 1,
        ),
      CircleMarker(
        point: here,
        radius: 7,
        color: hereColor,
        borderColor: Colors.white,
        borderStrokeWidth: 2.5,
      ),
    ];
  }

  void _recenter() {
    _resumeFollow?.cancel();
    final p = _myPos;
    _setFollow(true);
    if (p != null) {
      _mapController.move(LatLng(p.latitude, p.longitude),
          math.max(_mapController.camera.zoom, AppConstants.defaultMapZoom));
    }
  }

  void _centerOn(double lat, double lon) {
    if (_centeredOnGps || !mounted) return;
    _centeredOnGps = true;
    _mapController.move(LatLng(lat, lon), AppConstants.defaultMapZoom);
  }

  /// A dot for a received packet, coloured by the chosen metric.
  CircleMarker _dot(double lat, double lon, double? snr, int? rssi, int hops) {
    if (hops > 0) _hasRelayedDot = true;
    final metric = ref
            .read(sharedPreferencesProvider)
            .getString(AppConstants.prefColorMetric) ??
        'snr';
    final Color color;
    if (metric == 'rssi' && rssi != null) {
      color = SignalColorMapper.fromRssi(rssi);
    } else if (MarginScale.of(ref.read(meshRadioProvider).currentPreset)
            .marginDb(snr: snr, rssi: rssi)
        case final m?) {
      color = SignalColorMapper.fromMargin(m);
    } else {
      color = SignalColorMapper.noData;
    }
    return CircleMarker(
      point: LatLng(lat, lon),
      radius: hops == 0 ? 7 : 4, // relayed packets drawn smaller
      color: color.withValues(alpha: 0.85),
      borderColor: Colors.black54,
      borderStrokeWidth: 1,
    );
  }

  void _addPingDot(PingSample s) {
    if (!s.hasGps) return;
    if (s.status != AckStatus.received && s.status != AckStatus.implicit) {
      return;
    }
    if (s.snr == null && s.rssi == null) return;
    setState(() {
      _signalDots.add(_dot(s.latitude!, s.longitude!, s.snr, s.rssi, s.hops));
      if (_signalDots.length > _maxDots) _signalDots.removeAt(0);
    });
  }

  void _addDot(ProcessedSignalEvent event) {
    if (!event.hasGps) return;
    setState(() {
      _signalDots.add(_dot(event.latitude!, event.longitude!, event.rxSnr,
          event.rxRssi, event.hopCount));
      if (_signalDots.length > _maxDots) _signalDots.removeAt(0);
    });
  }

  /// Show what the active session has already recorded (e.g. after the
  /// app was restarted mid-session).
  Future<void> _loadSessionDots(Session? session) async {
    if (session == null || session.id == _dotsSessionId) return;
    final hadDots = _dotsSessionId != null || _signalDots.isNotEmpty;
    _dotsSessionId = session.id;
    // A new session starts with a clean map: the last drive's dots live on
    // its coverage map, not here (feedback 2026-10-28).
    if (hadDots) {
      setState(() {
        _signalDots.clear();
        _hasRelayedDot = false;
      });
    }
    final events =
        await ref.read(databaseProvider).getEventsForSession(session.id);
    if (!mounted) return;
    final dots = [
      for (final e in events)
        if (e.direction != PacketDirection.tx &&
            e.rxLat != null &&
            e.rxLon != null &&
            (e.rxSnr != null || e.rxRssi != null))
          _dot(e.rxLat!, e.rxLon!, e.rxSnr, e.rxRssi, e.hopCount),
    ];
    if (dots.isEmpty) return;
    setState(() => _signalDots.insertAll(0, dots));

    if (DemoMode.enabled) {
      _centeredOnGps = true;
      _mapController.fitCamera(CameraFit.coordinates(
        coordinates: [for (final d in dots) d.point],
        padding: const EdgeInsets.fromLTRB(40, 260, 40, 140),
      ));
      if (DemoMode.screen == 'session' && !_demoPanelShown) {
        _demoPanelShown = true;
        _showSessionPanel(context);
      }
    }
  }

  /// Redraw [sessionId]'s dots from the database (after a trim).
  Future<void> _reloadDots(int sessionId) async {
    final session = await ref.read(databaseProvider).getSessionById(sessionId);
    if (!mounted || session == null) return;
    // Forget the session so it loads again (clearing the old dots).
    _dotsSessionId = null;
    await _loadSessionDots(session);
  }

  Future<void> _promptRangeTest(RangeTestPrompt prompt) async {
    final detector = ref.read(rangeTestDetectorProvider);
    final node = ref.read(meshRadioProvider).nodes[prompt.meshNodeId]?.longName;
    await showDialog<void>(
      context: context,
      builder: (context) => RangeTestDialog(
        prompt: RangeTestPrompt(meshNodeId: prompt.meshNodeId, nodeName: node),
        onResult: (ok) => detector.setConfirmation(prompt.meshNodeId, ok),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final linkState = ref.watch(meshLinkStateProvider).valueOrNull ??
        RadioConnectionState.disconnected;
    final linkReady = linkState == RadioConnectionState.ready;
    final onBase = baseBeaconBannerShows(
        ref.watch(radioRolesProvider), ref.watch(meshRadioProvider), linkReady);
    ref.listen(liveSignalProvider, (_, next) {
      final event = next.valueOrNull;
      if (event != null) _addDot(event);
    });
    // A ping reply is a signal sample too (base → you), and on a walk it
    // is most of them: beacons come once a minute, pings every few
    // seconds (feedback 2026-10-28: "base responding but no dots").
    ref.listen(pingSampleProvider, (_, next) {
      final s = next.valueOrNull;
      if (s != null) _addPingDot(s);
    });
    ref.listen(activeSessionProvider, (_, next) {
      _loadSessionDots(next.valueOrNull);
    });
    ref.listen(rangeTestPromptProvider, (_, next) {
      final prompt = next.valueOrNull;
      if (prompt != null) _promptRangeTest(prompt);
    });
    // The Get started card's last step: open the start form with the tab.
    ref.listen(openStartFormProvider, (_, open) {
      if (!open) return;
      ref.read(openStartFormProvider.notifier).state = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showSessionPanel(context);
      });
    });

    final scaffold = Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(
                AppConstants.defaultMapLat,
                AppConstants.defaultMapLon,
              ),
              initialZoom: AppConstants.defaultMapZoom,
              // Every gesture, twist included, even while heading up: a
              // twist then takes the rotation over (see _mapEvents). The
              // gesture race makes a two-finger gesture either a zoom or a
              // twist (20° before it counts), so a pinch zoom never turns
              // the map a few degrees and never counts as a twist.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
                enableMultiFingerGestureRace: true,
              ),
              // A pan or pinch by the user stops the map following them
              // (and pauses heading up) until they tap the locate button,
              // or (while recording) until they leave the map alone for a
              // while.
              onPositionChanged: (_, hasGesture) {
                if (!hasGesture) return;
                _setFollow(false);
                _resumeFollow?.cancel();
                if (ref.read(sessionManagerProvider).activeSession != null) {
                  _resumeFollow = Timer(_resumeFollowAfter, () {
                    if (!mounted || _follow) return;
                    _setFollow(true);
                    final p = _myPos;
                    if (p != null) {
                      _mapController.move(LatLng(p.latitude, p.longitude),
                          _mapController.camera.zoom);
                    }
                  });
                }
              },
            ),
            children: [
              // Dimmed (tiles only): the dots and the blue dot stay bright.
              const BaseMapLayers(dim: true),
              CircleLayer(circles: _signalDots),
              CircleLayer(circles: _myLocation),
            ],
          ),
          // Soft fade behind the status bar so the clock stays readable
          // over bright map tiles.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).padding.top + 24,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left column: pill, then the base status right
                        // under it (not under the tall readout), then any
                        // setup warning. Shrinks (name ellipsized) to leave
                        // room for the signal readout.
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const ConnectionBanner(),
                              // Whether the base is being heard, large and
                              // colour-coded.
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: BaseStatusBar(),
                              ),
                              // Base and mobile set up differently: flag it
                              // here, where it would otherwise just look
                              // like no signal.
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: SetupMismatchBanner(
                                  onFix: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const RadioSetupScreen())),
                                ),
                              ),
                              // A radio other than the base heard on the
                              // test channel mid-session (a second base
                              // left on): caught here, not in Compare.
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: OtherRadioBanner(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Connected to the base itself: there is no signal
                        // to read out (the base is the sender), so its
                        // beacon controls take the readout's place.
                        if (linkReady && onBase)
                          ConstrainedBox(
                            // Narrow enough that the pill and base status
                            // on the left keep their one-line layout.
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * 0.46),
                            child: const BaseBeaconBanner(),
                          )
                        else if (linkReady && !_chartsOpen)
                          // The readout's own label carries the numbers;
                          // this adds the button and what a tap does.
                          MergeSemantics(
                              child: Semantics(
                            button: true,
                            hint: 'Opens live charts',
                            child: GestureDetector(
                              onTap: () => setState(() => _chartsOpen = true),
                              // Capped and shrunk at large text sizes, so
                              // the base status on the left keeps whole
                              // words ("Hearin/g" at 1.3x).
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                    minHeight: 44,
                                    maxWidth: MediaQuery.sizeOf(context).width *
                                        0.48),
                                child: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.topRight,
                                  child: SignalDisplay(),
                                ),
                              ),
                            ),
                          )),
                      ],
                    ),
                    // The base travelling with the phone (left in the car,
                    // then driven off): offer to stop and trim. Full width
                    // so its three buttons fit.
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: RideAlongBanner(onTrimmed: _reloadDots),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // The Get started pointer, above the Session button and left of
          // the locate / compass / map style column (16 FAB margin + a
          // 56 button + a gap), so it never runs under them.
          Positioned(
            left: 12,
            right: 84,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 104),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // One checklist in the app (the Coverage tab's Get
                    // started card); Live only points at its current step.
                    GetStartedPill(
                      onStartSession: () => _showSessionPanel(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bottom-left cluster: colour key sitting on the tile credit (the
          // OSM tile policy wants the credit visible), level with the
          // Session button on the right.
          Positioned(
            left: 8,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width - 200),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_signalDots.isNotEmpty && _legendOn) ...[
                        SignalLegend(showRelayedNote: _hasRelayedDot),
                        const SizedBox(height: 4),
                      ],
                      const MapCreditChip(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Tapping the readout expands it into live charts over the top
          // half of the screen, growing from the top-right corner.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => ScaleTransition(
                  alignment: Alignment.topRight,
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: _chartsOpen
                    ? Padding(
                        key: const ValueKey('charts'),
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.5,
                          child: SignalChartsPanel(
                            onClose: () => setState(() => _chartsOpen = false),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('none')),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Recentre on the phone and follow it again.
          if (_myPos != null)
            FloatingActionButton.small(
              heroTag: 'locate',
              tooltip: _follow
                  ? 'Following you'
                  : _headingWanted
                      ? 'Center on me and turn with you'
                      : 'Center on me',
              backgroundColor: _follow
                  ? null
                  : Theme.of(context).colorScheme.surfaceContainerHigh,
              foregroundColor:
                  _follow ? null : Theme.of(context).colorScheme.onSurface,
              onPressed: _recenter,
              child:
                  Icon(_follow ? Icons.my_location : Icons.location_searching),
            ),
          const SizedBox(height: 8),
          // Compass: the needle points north however the map is turned.
          // Paused heading up (after a pan) shows an orange ring and a
          // pause badge, so the map turning again later is no surprise.
          Semantics(
            toggled: _headingActive,
            child: FloatingActionButton.small(
              key: const ValueKey('compass'),
              heroTag: 'compass',
              tooltip: _compassTooltip,
              backgroundColor: _headingActive
                  ? null
                  : Theme.of(context).colorScheme.surfaceContainerHigh,
              foregroundColor: _headingActive
                  ? null
                  : Theme.of(context).colorScheme.onSurface,
              shape: _headingPaused
                  ? CircleBorder(
                      side: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2))
                  : null,
              onPressed: _onCompassTap,
              child: Badge(
                key: const ValueKey('compass-paused'),
                isLabelVisible: _headingPaused,
                backgroundColor: Theme.of(context).colorScheme.primary,
                offset: const Offset(6, -6),
                label: Icon(Icons.pause,
                    size: 10, color: Theme.of(context).colorScheme.onPrimary),
                child: Transform.rotate(
                  angle: _rotation * math.pi / 180,
                  child: Icon(_headingActive
                      ? Icons.navigation
                      : Icons.navigation_outlined),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Map style (only when terrain tiles are hosted), labelled
          // "Layers" until first opened.
          const MapStyleButton(labelUntilOpened: true),
          const SizedBox(height: 8),
          // The pill at the top is the connect control, so only Session
          // lives here and the bottom-left stays free for the credit.
          FloatingActionButton.extended(
            heroTag: 'session',
            onPressed: () => _showSessionPanel(context, toggle: true),
            icon: const Icon(Icons.radio_button_checked),
            label: const Text('Session'),
            tooltip: 'Start or end a recording session',
          ),
        ],
      ),
    ); // No app bar here, so nothing else picks the status bar icons: keep
    // them light over the dark fade at the top (Android otherwise draws
    // dark icons on it in light mode). Status bar only; the navigation bar
    // keeps the theme's.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: _withDockedPanel(context, scaffold),
    );
  }

  /// [map] alone (phones, and wide windows without room for a side
  /// column), or with the session panel docked to its right.
  Widget _withDockedPanel(BuildContext context, Widget map) {
    final keyed = KeyedSubtree(key: _mapKey, child: map);
    final cls = WindowClass.of(context);
    if (!_panelDocked || !cls.isWide) return keyed;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final beside = cls.hasSidePanel;

    // The map's overlays size themselves from MediaQuery (the readout is
    // at most ~half the width): give them the map's own size, and leave
    // the edge the panel covers to the panel.
    final sizedMap = LayoutBuilder(
      builder: (context, box) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: box.biggest,
          padding: beside
              ? MediaQuery.paddingOf(context).copyWith(right: 0)
              : MediaQuery.paddingOf(context).copyWith(bottom: 0),
          viewPadding: beside
              ? MediaQuery.viewPaddingOf(context).copyWith(right: 0)
              : MediaQuery.viewPaddingOf(context).copyWith(bottom: 0),
        ),
        child: keyed,
      ),
    );
    final panel = Material(
      type: MaterialType.transparency,
      child: SessionPanel(
        onClose: () => setState(() => _panelDocked = false),
      ),
    );

    if (!beside) {
      // An iPad held upright (or the Duo unfolded upright): too narrow for
      // a column beside the map, so the panel docks under it, full width,
      // and the map keeps its controls (2026-11-10, the floating sheet on
      // Andy's iPad Pro 10.5).
      final height = (MediaQuery.sizeOf(context).height * 0.42)
          .clamp(320.0, 520.0)
          .toDouble();
      return Column(
        children: [
          Expanded(child: sizedMap),
          DecoratedBox(
            key: const ValueKey('session-panel-docked'),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: SafeArea(top: false, child: panel),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: sizedMap),
        DecoratedBox(
          key: const ValueKey('session-panel-docked'),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border(left: BorderSide(color: colors.outlineVariant)),
          ),
          child: SizedBox(
            width: _dockedPanelWidth,
            child: Stack(
              children: [
                SafeArea(left: false, child: panel),
                // The status bar's icons are light (for the map's dark
                // fade) and run across the panel too: the same fade here
                // keeps the battery and Wi-Fi readable over a light panel.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.paddingOf(context).top + 12,
                  child: const IgnorePointer(child: _StatusBarFade()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const _dockedPanelWidth = 380.0;

  void _showSessionPanel(BuildContext context, {bool toggle = false}) {
    // Room beside the map (iPad, Duo unfolded): dock it there instead of
    // covering the map with a sheet; the Session button toggles it.
    if (WindowClass.of(context).isWide) {
      setState(() => _panelDocked = toggle ? !_panelDocked : true);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // Lift the sheet above the keyboard so the session-name field stays
      // visible while typing (modal sheets ignore the keyboard inset), and
      // above the system bar at the bottom: Android's three-button bar is
      // 48 dp of opaque edge-to-edge overlay, and the Start session button
      // sat under it on the Galaxy A16 (2026-11-08).
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: math.max(
            MediaQuery.viewInsetsOf(context).bottom,
            MediaQuery.viewPaddingOf(context).bottom,
          ),
        ),
        child: const SessionPanel(),
      ),
    );
  }
}

/// The dark fade behind the status bar, so its light icons stay readable.
class _StatusBarFade extends StatelessWidget {
  const _StatusBarFade();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x99000000), Color(0x00000000)],
          ),
        ),
      );
}
