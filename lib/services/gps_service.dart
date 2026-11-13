// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../data/radio/radio_types.dart' show NodeFix;
import '../utils/app_info.dart';
import '../utils/platform_text.dart';
import 'diag_log.dart';

/// Where GPS stands, for the session panel and [GpsService.ensureStarted].
enum GpsStatus {
  /// Not checked yet (app just launched).
  unknown,

  /// Location Services are switched off for the whole phone.
  off,

  /// Not asked yet: the prompt is shown when the first session starts.
  notAsked,

  /// The app may not use location.
  denied,

  /// Allowed and listening, but no position yet.
  searching,

  /// A position has arrived.
  fix,
}

/// Where a position comes from.
enum GpsSource {
  /// The phone's (or iPad's) own location.
  phone,

  /// The connected node's GPS over Bluetooth ([NodeFix]): used when the
  /// phone has no good fix (a Wi-Fi iPad has no GPS).
  node,
}

class GpsState {
  final GpsStatus status;

  /// Where the fix comes from (only meaningful for [GpsStatus.fix]).
  final GpsSource source;

  /// Horizontal accuracy of the last fix in metres (only for [GpsStatus.fix]).
  final double? accuracy;

  /// iOS "Precise Location" is off: positions are only approximate.
  final bool approximate;

  const GpsState(this.status,
      {this.accuracy, this.approximate = false, this.source = GpsSource.phone});

  static const unknown = GpsState(GpsStatus.unknown);

  bool get usable => status == GpsStatus.searching || status == GpsStatus.fix;

  @override
  bool operator ==(Object other) =>
      other is GpsState &&
      other.status == status &&
      other.accuracy == accuracy &&
      other.approximate == approximate &&
      other.source == source;

  @override
  int get hashCode => Object.hash(status, accuracy, approximate, source);
}

/// One line for the session panel, and whether it is a problem (amber).
({String text, bool problem}) gpsStatusLine(GpsState s) {
  final base = switch (s.status) {
    GpsStatus.unknown => (text: 'GPS: checking…', problem: false),
    GpsStatus.off => (
        text: PlatformText.isAndroid
            ? 'GPS: Location is off — turn it on in the quick settings'
            : 'GPS: Location Services are off — turn them on in Settings',
        problem: true
      ),
    GpsStatus.notAsked => (
        text: 'GPS: you\'ll be asked for location when you start a session',
        problem: false
      ),
    GpsStatus.denied => (
        text: 'GPS: permission denied — enable in Settings',
        problem: true
      ),
    GpsStatus.searching => (text: 'GPS: waiting for fix…', problem: true),
    GpsStatus.fix => (
        text: s.source == GpsSource.node
            ? 'GPS: from your node ±${(s.accuracy ?? 0).round()} m'
            : 'GPS: fix ±${(s.accuracy ?? 0).round()} m',
        problem: false
      ),
  };
  if (s.source == GpsSource.node) return base;
  if (s.approximate && s.usable) {
    return (
      text: '${base.text} (approximate — turn on '
          '${PlatformText.preciseLocation})',
      problem: true,
    );
  }
  return base;
}

/// The platform location calls [GpsService] uses (a seam for tests).
class LocationBackend {
  const LocationBackend();

  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();
  Future<LocationAccuracyStatus> getLocationAccuracy() =>
      Geolocator.getLocationAccuracy();
  Stream<Position> getPositionStream(LocationSettings settings) =>
      Geolocator.getPositionStream(locationSettings: settings);
  Future<Position> getCurrentPosition(LocationSettings settings) =>
      Geolocator.getCurrentPosition(locationSettings: settings);
}

/// Wraps the geolocator package to provide GPS position, with the
/// connected node's GPS ([addNodeFix]) standing in when the phone has no
/// good fix of its own (docs/design/ipad, step 5).
class GpsService {
  GpsService({
    LocationBackend backend = const LocationBackend(),
    DateTime Function()? clock,
  })  : _backend = backend,
        _now = clock ?? DateTime.now;

  /// A phone fix this good (metres) always wins over the node's. The
  /// phone's stream only reports after 5 m of movement, so its age says
  /// nothing; its accuracy does (a Wi-Fi iPad reports 65 m and worse).
  static const phoneGoodAccuracyM = 30.0;

  /// A node fix older than this is not used (Meshtastic sends one a
  /// minute, MeshCore is asked every 5 s).
  static const nodeFixMaxAge = Duration(minutes: 2);

  final LocationBackend _backend;
  final DateTime Function() _now;
  StreamSubscription<Position>? _subscription;

  /// The phone's own last position and state.
  Position? _lastPosition;
  GpsState _phoneState = GpsState.unknown;

  /// The node's last fix, and whether it is the one in use.
  NodeFix? _nodeFix;
  bool _usingNode = false;
  Timer? _nodeExpiry;
  final StreamController<Position> _positionController =
      StreamController<Position>.broadcast();
  final StreamController<GpsState> _stateController =
      StreamController<GpsState>.broadcast();
  GpsState _state = GpsState.unknown;
  bool _approximate = false;
  Future<GpsState>? _starting;

  /// The best position now: the phone's, or the node's fix while that is
  /// the one in use.
  Position? get lastPosition =>
      _usingNode ? _positionOf(_nodeFix!) : _lastPosition;

  /// Whether the node's GPS fixes are needed: the phone has no fix within
  /// [phoneGoodAccuracyM]. The radio only polls / re-reads for them while
  /// this is true ([nodeFixWantedChanges] → MeshRadio.ownFixesWanted).
  bool get nodeFixWanted => !_phoneGood;
  Stream<bool> get nodeFixWantedChanges => _wantedController.stream;
  final _wantedController = StreamController<bool>.broadcast();
  bool? _lastWanted;

  /// Whether positions currently come from the node's GPS.
  GpsSource get source => _usingNode ? GpsSource.node : GpsSource.phone;
  Stream<Position> get positionStream => _positionController.stream;

  /// Current GPS status, and its changes.
  GpsState get state => _state;
  Stream<GpsState> get stateStream => _stateController.stream;

  bool get isListening => _subscription != null;

  /// The phone's own state changed: publish it, unless the node's fix is
  /// in use (then the phone may have just become good enough to take over).
  void _setState(GpsState s) {
    _phoneState = s;
    _reevaluate();
  }

  void _publish(GpsState s) {
    if (s == _state || _stateController.isClosed) return;
    if (s.status != _state.status) {
      DiagLog.instance.log('gps', '${_state.status.name} -> ${s.status.name}');
    }
    _state = s;
    _stateController.add(s);
  }

  /// Check permission and Location Services and start listening if
  /// allowed. Safe to call repeatedly (app resume, Start Session): it does
  /// nothing more when already listening. [request] shows the iOS
  /// permission prompt if it hasn't been answered yet.
  Future<GpsState> ensureStarted({bool request = true}) =>
      _starting ??= _ensureStarted(request).whenComplete(() {
        _starting = null;
      });

  Future<GpsState> _ensureStarted(bool request) async {
    try {
      var permission = await _backend.checkPermission();
      if (permission == LocationPermission.denied && request) {
        permission = await _backend.requestPermission();
      }
      if (permission == LocationPermission.denied && !request) {
        // iOS "not determined": no prompt until a session starts.
        stopListening();
        _setState(const GpsState(GpsStatus.notAsked));
        return _state;
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        stopListening();
        _setState(const GpsState(GpsStatus.denied));
        return _state;
      }
      if (!await _backend.isLocationServiceEnabled()) {
        stopListening();
        _setState(const GpsState(GpsStatus.off));
        return _state;
      }
      try {
        _approximate = await _backend.getLocationAccuracy() ==
            LocationAccuracyStatus.reduced;
      } catch (_) {
        _approximate = false;
      }
      if (!isListening) startListening();
      _setState(_listeningState());
    } catch (e) {
      print('GPS start failed: $e');
    }
    return _state;
  }

  GpsState _listeningState() {
    final p = _lastPosition;
    return p == null
        ? GpsState(GpsStatus.searching, approximate: _approximate)
        : GpsState(GpsStatus.fix,
            accuracy: p.accuracy, approximate: _approximate);
  }

  bool _background = false;

  /// Demo mode: a fixed position instead of real GPS (no permission prompt).
  void useDemoPosition(double lat, double lon, {double altitude = 0}) {
    final p = Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: altitude,
      altitudeAccuracy: 5,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    _lastPosition = p;
    _positionController.add(p);
    _setState(const GpsState(GpsStatus.fix, accuracy: 5));
  }

  /// While a session records, keep GPS running with the phone locked
  /// (iOS shows the blue location indicator; Android runs the stream in a
  /// foreground service with an ongoing notification). This also keeps the
  /// app alive in the background, so ping and out-of-range timers keep
  /// firing and packets get the current position instead of a stale one.
  void setBackgroundMode(bool enabled) {
    if (enabled == _background) return;
    _background = enabled;
    _fgsDeferred = enabled && !_appInForeground;
    if (_fgsDeferred) {
      DiagLog.instance.log('gps', 'background mode deferred: app not resumed');
    }
    if (_subscription != null) {
      stopListening();
      startListening();
    }
  }

  bool _appInForeground = true;
  bool _fgsDeferred = false;

  /// Whether the app is resumed (from the app lifecycle in `app.dart`).
  ///
  /// Android only lets an app start a location foreground service while it
  /// is in the foreground (Android 12+, `ForegroundServiceStartNotAllowed`:
  /// "Foreground service started from background can not have location
  /// access"), and the refusal never reaches the Dart stream: the stream
  /// just stays silent. So the recording settings are applied only while
  /// resumed; a session that starts, or is picked up again at launch, with
  /// the app in the background runs the plain stream until the next resume.
  /// Galaxy A16, 2026-11-08: a session resumed from a background launch had
  /// no position for 90 s and the map sat on the default centre.
  set appInForeground(bool resumed) {
    if (resumed == _appInForeground) return;
    _appInForeground = resumed;
    if (resumed && _fgsDeferred && _background && isListening) {
      _fgsDeferred = false;
      DiagLog.instance.log('gps', 'background mode applied on resume');
      stopListening();
      startListening();
    }
  }

  /// The position stream's settings for [platform]; [background] while a
  /// session records.
  @visibleForTesting
  static LocationSettings streamSettingsFor(
    TargetPlatform platform, {
    required bool background,
  }) {
    if (platform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // minimum 5m movement before update
        intervalDuration: const Duration(seconds: 1),
        // The foreground service (geolocator's own, declared in its plugin
        // manifest) keeps GPS and the app's timers running when the screen
        // is off. Stopping the stream stops the service and its notice.
        foregroundNotificationConfig: background
            ? const ForegroundNotificationConfig(
                notificationTitle: '${AppInfo.displayName} is recording',
                notificationText:
                    'GPS and the radio link stay on until you end the session.',
                notificationChannelName: 'Recording',
                notificationIcon: AndroidResource(
                  name: 'ic_stat_notify',
                  defType: 'drawable',
                ),
                setOngoing: true,
                enableWakeLock: true,
              )
            : null,
      );
    }
    return AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // minimum 5m movement before update
      activityType: ActivityType.fitness,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: background,
      showBackgroundLocationIndicator: background,
    );
  }

  void startListening() {
    _subscription = _backend
        .getPositionStream(streamSettingsFor(defaultTargetPlatform,
            background: _background && !_fgsDeferred))
        .listen(
      (position) {
        _lastPosition = position;
        _setState(GpsState(GpsStatus.fix,
            accuracy: position.accuracy, approximate: _approximate));
        // While the node's GPS stands in, a poor phone fix isn't passed on.
        if (!_usingNode) _positionController.add(position);
      },
      onError: (error) {
        // GPS errors are non-fatal; we just won't have position data.
        // Permission revoked or Location Services switched off: re-check
        // so the status shows it (and the next resume restarts).
        print('GPS error: $error');
        if (error is PermissionDeniedException ||
            error is LocationServiceDisabledException) {
          stopListening();
          _setState(GpsState(error is PermissionDeniedException
              ? GpsStatus.denied
              : GpsStatus.off));
        }
      },
    );
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Get current position on demand (with timeout)
  Future<Position?> getCurrentPosition({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // The node's GPS stands in for a phone without a good fix.
    if (_usingNode) return lastPosition;
    try {
      return await _backend
          .getCurrentPosition(const LocationSettings(
            accuracy: LocationAccuracy.high,
          ))
          .timeout(timeout);
    } catch (e) {
      return lastPosition;
    }
  }

  /// A fix from the connected node's GPS (MeshRadio.ownFixes). Used while
  /// the phone has no fix within [phoneGoodAccuracyM] and the fix is under
  /// [nodeFixMaxAge] old.
  void addNodeFix(NodeFix fix) {
    if (!fix.isValid || _stateController.isClosed) return;
    if (_now().difference(fix.time) > nodeFixMaxAge) return;
    _nodeFix = fix;
    _reevaluate();
    if (_usingNode) _positionController.add(_positionOf(fix));
  }

  bool get _phoneGood {
    final p = _lastPosition;
    return _phoneState.status == GpsStatus.fix &&
        p != null &&
        p.accuracy <= phoneGoodAccuracyM;
  }

  /// Pick the source and publish the state that goes with it.
  void _reevaluate() {
    final wanted = nodeFixWanted;
    if (wanted != _lastWanted && !_wantedController.isClosed) {
      _lastWanted = wanted;
      _wantedController.add(wanted);
    }
    final node = _nodeFix;
    final age = node == null ? null : _now().difference(node.time);
    final nodeFresh = age != null && age <= nodeFixMaxAge;
    final useNode = nodeFresh && !_phoneGood;
    if (useNode != _usingNode) {
      DiagLog.instance
          .log('gps', useNode ? 'using the node GPS' : 'using the phone GPS');
    }
    _usingNode = useNode;
    _nodeExpiry?.cancel();
    _nodeExpiry = null;
    if (useNode && node != null) {
      // Drop back to the phone when this fix gets too old.
      _nodeExpiry =
          Timer(nodeFixMaxAge - age + const Duration(seconds: 1), _reevaluate);
      _publish(GpsState(GpsStatus.fix,
          accuracy: node.accuracyM, source: GpsSource.node));
    } else {
      _publish(_phoneState);
    }
  }

  static Position _positionOf(NodeFix f) => Position(
        latitude: f.latitude,
        longitude: f.longitude,
        timestamp: f.time,
        accuracy: f.accuracyM,
        altitude: f.altitudeM ?? 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  void dispose() {
    _nodeExpiry?.cancel();
    _wantedController.close();
    stopListening();
    _positionController.close();
    _stateController.close();
  }
}
