// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/radio/mesh_radio.dart';
import '../demo/demo_mode.dart';
import '../utils/constants.dart';
import 'diag_log.dart';

/// Tracks whether the base node is reachable during a session.
///
/// The clock starts when monitoring starts, so a base that is never heard
/// still goes out of range. While the phone's Bluetooth link to the mobile
/// radio is down the state is [RangeState.radioLost] instead, so a dropped
/// phone↔radio link isn't reported as the base being out of range.
/// Notifications are only sent while the app is in the background.
class OutOfRangeMonitor {
  static const _radioLostGrace = Duration(seconds: 30);

  /// The same alert is not *sounded* again within this long: at the edge
  /// of coverage the base comes and goes, and one buzz per state change
  /// every minute helps nobody. A repeat inside the window is still posted
  /// to the lock screen, silently, so a second real outage is not invisible
  /// (bench, 2026-10-26: a second "Out of range" 95 s after the first went
  /// unnoticed when it was dropped outright).
  static const _minRepeat = Duration(minutes: 2);
  final _lastSent = <String, DateTime>{};

  /// Out of range is left only after this many answers from the base in
  /// one timeout window: at the edge of coverage half the probes fail, and
  /// a single lucky answer followed by two misses would ring the alarm
  /// again a minute later (session 33, 2026-10-29: 33 flips in 3.5 h).
  static const reentryAnswers = 2;
  int _heardWhileOut = 0;

  /// Going out of range again this soon after coming back is the edge of
  /// coverage, not a new outage: the state still changes (pill, panel,
  /// lock screen list) but neither alert sounds. A new episode after a
  /// quiet spell sounds as before.
  static const flapQuiet = Duration(minutes: 5);
  DateTime? _lastBackInRange;

  /// Alerts posted this session, oldest first, with whether each was
  /// silent (a quick repeat or a flap).
  @visibleForTesting
  final sentAlerts = <({String title, bool quiet})>[];

  final FlutterLocalNotificationsPlugin _notifications;
  final MeshRadio _radio;
  StreamSubscription<RadioConnectionState>? _linkSub;

  RangeState _state = RangeState.unknown;
  Timer? _timeoutTimer;
  Timer? _radioLostTimer;
  int _timeoutSec = AppConstants.defaultOutOfRangeTimeoutSec;
  int? _baseNodeId;
  DateTime? _lastHeardBase;
  bool _radioLostNotified = false;

  final StreamController<RangeState> _stateController =
      StreamController<RangeState>.broadcast();

  RangeState get state => _state;
  Stream<RangeState> get stateStream => _stateController.stream;

  /// State changes this session, oldest first (shown in the session panel
  /// so a missed alert can still be seen afterwards).
  final events = ValueNotifier<List<RangeEvent>>(const []);
  bool get isMonitoring => _baseNodeId != null;

  /// Mesh node number of the base being watched; null when not monitoring.
  int? get baseNodeId => _baseNodeId;

  /// When a packet from the base was last received (this session).
  DateTime? get lastHeardBase => _lastHeardBase;

  /// Whether the app is in foreground (suppress push notifications).
  /// Set from the app lifecycle in app.dart.
  bool isAppInForeground = true;

  /// Whether alerts can reach the locked phone: true/false once known,
  /// null before the first check (or where it can't be checked).
  final notificationsAllowed = ValueNotifier<bool?>(null);

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Android notification channel for the out-of-range and radio-lost
  /// alerts (high importance: heads-up with sound).
  static const alertChannel = AndroidNotificationChannel(
    'session_alerts',
    'Session alerts',
    description: 'Base out of range or radio lost while recording.',
    importance: Importance.high,
  );

  /// Android only: a quick repeat or a flap goes here, without sound.
  static const quietChannel = AndroidNotificationChannel(
    'session_alerts_quiet',
    'Session alerts (repeats)',
    description: 'Repeats of a recent alert, without sound.',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  /// Ask for notification permission (iOS prompts only the first time;
  /// later calls just report the current answer; Android 13+ asks for
  /// POST_NOTIFICATIONS the same way). Called when a session starts, not
  /// at launch.
  Future<bool?> requestNotificationPermission() async {
    if (DemoMode.enabled) return null; // never prompt in demo
    try {
      final android = _android;
      if (android != null) {
        await android.createNotificationChannel(alertChannel);
        await android.createNotificationChannel(quietChannel);
        final ok = await android.requestNotificationsPermission();
        DiagLog.instance.log('notify', 'permission request -> $ok');
        notificationsAllowed.value = ok;
        return ok;
      }
      final ios = _ios;
      if (ios == null) return null;
      final ok = await ios.requestPermissions(alert: true, sound: true);
      DiagLog.instance.log('notify', 'permission request -> $ok');
      notificationsAllowed.value = ok;
      return ok;
    } catch (e) {
      print('OutOfRangeMonitor: permission request failed: $e');
      return null;
    }
  }

  /// Refresh [notificationsAllowed] without prompting (resume, relaunch).
  Future<void> checkNotificationPermission() async {
    if (DemoMode.enabled) return;
    try {
      final android = _android;
      if (android != null) {
        final ok = await android.areNotificationsEnabled();
        if (ok != null) notificationsAllowed.value = ok;
        return;
      }
      final options = await _ios?.checkPermissions();
      if (options != null) notificationsAllowed.value = options.isEnabled;
    } catch (e) {
      print('OutOfRangeMonitor: permission check failed: $e');
    }
  }

  OutOfRangeMonitor({
    required FlutterLocalNotificationsPlugin notifications,
    required MeshRadio radio,
  })  : _notifications = notifications,
        _radio = radio {
    _linkSub = _radio.connectionState.listen(_onLinkState);
  }

  /// Start monitoring [baseNodeId] (mesh node number).
  void configure({
    required int baseNodeId,
    int timeoutSec = AppConstants.defaultOutOfRangeTimeoutSec,
  }) {
    _baseNodeId = baseNodeId;
    _timeoutSec = timeoutSec;
    _lastHeardBase = null;
    _lastSent.clear();
    _heardWhileOut = 0;
    _lastBackInRange = null;
    sentAlerts.clear();
    events.value = const [];
    DiagLog.instance.log(
        'range',
        'monitoring ${diagNode(baseNodeId)}, timeout ${timeoutSec}s, '
            'radio ${_radio.isReady ? 'ready' : 'not ready'}');
    _setState(_radio.isReady ? RangeState.unknown : RangeState.radioLost);
    if (_radio.isReady) {
      _resetTimeout();
    } else {
      // E.g. a session resumed after relaunch before the radio reconnects.
      _armRadioLostTimer();
    }
  }

  /// Called when any packet is received. Checks if it's from the base node.
  void onPacketReceived(int fromMeshNodeId) {
    if (_baseNodeId == null || fromMeshNodeId != _baseNodeId) return;
    _lastHeardBase = clock.now();
    _resetTimeout();

    if (_state == RangeState.inRange) return;
    if (_state == RangeState.outOfRange) {
      _heardWhileOut++;
      if (_heardWhileOut < reentryAnswers) {
        DiagLog.instance.log('range',
            'heard once while outOfRange ($_heardWhileOut/$reentryAnswers)');
        return;
      }
      _heardWhileOut = 0;
      _setState(RangeState.inRange);
      _sendNotification(
        title: 'Back in range',
        body: 'Hearing the base node again.',
        quiet: _isFlap(),
      );
      _lastBackInRange = clock.now();
      return;
    }
    _setState(RangeState.inRange);
  }

  /// Within [flapQuiet] of the last return to range.
  bool _isFlap() {
    final back = _lastBackInRange;
    return back != null && clock.now().difference(back) < flapQuiet;
  }

  void _onLinkState(RadioConnectionState link) {
    if (_baseNodeId == null) return;
    DiagLog.instance.log('range', 'link ${link.name} while ${_state.name}');
    if (link == RadioConnectionState.ready) {
      _radioLostTimer?.cancel();
      if (_state == RangeState.radioLost) {
        if (_radioLostNotified) {
          _sendNotification(
            title: 'Bluetooth link restored',
            body: 'Recording again.',
          );
        }
        _radioLostNotified = false;
        _setState(RangeState.unknown);
        _resetTimeout();
      }
    } else if (_state != RangeState.radioLost) {
      // Can't judge the base without the radio; pause the clock.
      _timeoutTimer?.cancel();
      _setState(RangeState.radioLost);
      _armRadioLostTimer();
    }
  }

  /// Radio reboots reconnect within seconds; only notify if it lasts.
  void _armRadioLostTimer() {
    _radioLostTimer?.cancel();
    _radioLostTimer = Timer(_radioLostGrace, () {
      if (_state != RangeState.radioLost) return;
      _radioLostNotified = true;
      _sendNotification(
        title: 'Bluetooth link lost',
        body: "Your phone lost its Bluetooth link to your node. "
            'Nothing is being recorded.',
      );
    });
  }

  void _resetTimeout() {
    _timeoutTimer?.cancel();
    if (DemoMode.enabled) return; // screenshots: base stays "in range"
    _timeoutTimer = Timer(Duration(seconds: _timeoutSec), _onTimeout);
  }

  void _onTimeout() {
    DiagLog.instance.log('range', 'timeout fired while ${_state.name}');
    // A lone answer while out of range no longer counts once the window
    // it restarted has run out.
    _heardWhileOut = 0;
    if (_state == RangeState.outOfRange || _state == RangeState.radioLost) {
      return;
    }
    _setState(RangeState.outOfRange);
    _sendNotification(
      title: 'Out of range',
      body: "Haven't heard the base node for "
          '${AppConstants.formatSeconds(_timeoutSec)}.',
      quiet: _isFlap(),
    );
  }

  void _setState(RangeState s) {
    if (_state == s || _stateController.isClosed) return;
    DiagLog.instance.log('range', '${_state.name} -> ${s.name}');
    _state = s;
    _stateController.add(s);
    if (_baseNodeId != null) {
      events.value = [...events.value, RangeEvent(clock.now(), s)];
    }
  }

  /// Post an alert through the same path as the range alerts (banner with
  /// sound, quiet repeat within two minutes), under its own id so it
  /// doesn't replace a range alert. Used by the ride-along detector.
  Future<void> notify({required String title, required String body}) =>
      _sendNotification(title: title, body: body, id: 1);

  /// [quiet] posts silently whatever the repeat window says (a flap).
  Future<void> _sendNotification({
    required String title,
    required String body,
    int id = 0,
    bool quiet = false,
  }) async {
    if (DemoMode.enabled) return; // never prompt for permission in demo
    DiagLog.instance.log(
        'notify',
        '"$title" (foreground: $isAppInForeground, '
            'allowed: ${notificationsAllowed.value})');
    final now = clock.now();
    final last = _lastSent[title];
    if (quiet) {
      DiagLog.instance.log(
          'notify',
          'quiet flap (back in range '
              '${now.difference(_lastBackInRange ?? now).inSeconds}s ago)');
    } else if (last != null && now.difference(last) < _minRepeat) {
      quiet = true;
      DiagLog.instance.log('notify',
          'quiet repeat (sounded ${now.difference(last).inSeconds}s ago)');
    } else {
      _lastSent[title] = now;
    }
    sentAlerts.add((title: title, quiet: quiet));

    // Shown as a banner with sound even while the app is open (the pill
    // alone is easy to miss on a walk), and on the lock screen otherwise.
    // A quick repeat is listed without sound or vibration.
    final channel = quiet ? quietChannel : alertChannel;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: channel.importance,
        priority: quiet ? Priority.low : Priority.high,
        playSound: !quiet,
        enableVibration: !quiet,
        // Nothing private in it: full text on the lock screen, as on iOS
        // (Android's default hides it when the user hides sensitive
        // content). The channel's high importance gives the heads-up
        // banner, in the foreground too.
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.status,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: !quiet,
        interruptionLevel:
            quiet ? InterruptionLevel.passive : InterruptionLevel.active,
      ),
    );

    try {
      await _notifications.show(id, title, body, details);
      DiagLog.instance.log('notify', 'shown');
    } catch (e) {
      DiagLog.instance.log('notify', 'FAILED: $e');
    }
  }

  /// Stop monitoring (session ended).
  void stop() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _radioLostTimer?.cancel();
    _radioLostTimer = null;
    _baseNodeId = null;
    _lastHeardBase = null;
    _lastSent.clear();
    _radioLostNotified = false;
    _setState(RangeState.unknown);
  }

  void dispose() {
    stop();
    notificationsAllowed.dispose();
    events.dispose();
    _linkSub?.cancel();
    _stateController.close();
  }
}

/// One state change of the monitor, for the session panel.
class RangeEvent {
  final DateTime at;
  final RangeState state;
  const RangeEvent(this.at, this.state);
}
