// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/app_database.dart';
import '../data/radio/mesh_radio.dart';
import '../demo/demo_mode.dart';
import '../utils/constants.dart';
import 'active_probe_service.dart';
import 'airtime_model.dart';
import 'base_node.dart';
import 'base_ride_along_detector.dart';
import 'battery_hint.dart';
import 'gps_service.dart';
import 'out_of_range_monitor.dart';
import 'diag_log.dart';
import 'packet_processor.dart';
import 'radio_roles.dart';
import 'range_test_detector.dart';
import 'rig_math.dart';
import '../utils/platform_text.dart';

/// Why a session could not start (shown to the user as is).
class SessionStartError implements Exception {
  final String message;
  const SessionStartError(this.message);

  @override
  String toString() => message;
}

/// A MeshCore session with neither the base beacon nor pings on: the
/// mobile would hear nothing on a quiet test frequency. A [StateError] and
/// a [SessionStartError] (shown as is).
class SessionProbeOffError extends StateError implements SessionStartError {
  SessionProbeOffError()
      : super('A MeshCore session needs the base beacon or pings on: the '
            'base sends nothing by itself, so nothing else is ever heard '
            'on the test frequency. Turn pings on, or set a base beacon '
            'interval in Settings → Node Setup.');

  @override
  String toString() => message;
}

/// Manages session lifecycle. Sessions persist across app restarts.
class SessionManager {
  final AppDatabase _db;
  final MeshRadio _radio;
  final GpsService _gps;
  final PacketProcessor _packetProcessor;
  final RangeTestDetector _rangeTestDetector;
  final ActiveProbeService _activeProbeService;
  final OutOfRangeMonitor _outOfRangeMonitor;
  final SharedPreferences _prefs;
  final BaseRideAlongDetector? _rideAlong;

  /// Whether "Faster than recommended" may apply (Pro,
  /// `ProFeature.fasterIntervals`); without it the airtime floor holds.
  final bool Function() _fasterAllowed;

  Session? _activeSession;
  StreamSubscription<RadioChannelStats>? _statsSub;

  /// MeshCore sessions: trace outcomes fed to the beacon tracker and the
  /// out-of-range monitor, and base beacon changes from Radio Setup.
  StreamSubscription<PingSample>? _traceSub;
  StreamSubscription<({BeaconKind kind, int intervalSec})>? _beaconSub;
  int? _oorTimeoutSec;
  double? _maxAirUtilTx;
  double? _maxChannelUtil;
  final StreamController<Session?> _sessionController =
      StreamController<Session?>.broadcast();

  Session? get activeSession => _activeSession;

  /// A one-off note for the user after the last [startSession] succeeded
  /// (Android's battery hint, once ever), or null. The UI shows it, e.g.
  /// as a snack bar, right after the start.
  String? startNotice;

  /// Whether the session recording right now belongs to [coverageMapId]
  /// (such a map must not be deleted).
  bool isRecordingInto(int coverageMapId) =>
      _activeSession?.coverageMapId == coverageMapId;
  Stream<Session?> get sessionStream => _sessionController.stream;

  SessionManager({
    required AppDatabase db,
    required MeshRadio radio,
    required GpsService gps,
    required PacketProcessor packetProcessor,
    required RangeTestDetector rangeTestDetector,
    required ActiveProbeService activeProbeService,
    required OutOfRangeMonitor outOfRangeMonitor,
    required SharedPreferences prefs,
    BaseRideAlongDetector? rideAlong,
    bool Function()? fasterAllowed,
  })  : _fasterAllowed = fasterAllowed ?? (() => true),
        _db = db,
        _radio = radio,
        _gps = gps,
        _packetProcessor = packetProcessor,
        _rangeTestDetector = rangeTestDetector,
        _activeProbeService = activeProbeService,
        _outOfRangeMonitor = outOfRangeMonitor,
        _prefs = prefs,
        _rideAlong = rideAlong;

  /// Check for and resume an active session on app startup
  Future<void> initialize() async {
    final activeSessionId = _prefs.getInt(AppConstants.prefActiveSessionId);
    if (activeSessionId != null) {
      _activeSession = await _db.getSessionById(activeSessionId);
      if (_activeSession != null && _activeSession!.isActive) {
        _packetProcessor.activeSessionId = _activeSession!.id;
        await _startMonitoring(_activeSession!);
        _sessionController.add(_activeSession);
        // Don't prompt here (no context); just learn whether alerts work.
        unawaited(_outOfRangeMonitor.checkNotificationPermission());
      } else {
        // Session was ended or deleted externally
        await _prefs.remove(AppConstants.prefActiveSessionId);
        _activeSession = null;
        _sessionController.add(null);
      }
    }
  }

  /// Demo mode: make [session] the active one without touching the saved
  /// "active session" setting (so a real session is never disturbed).
  Future<void> attachDemo(Session session) async {
    _activeSession = session;
    _packetProcessor.activeSessionId = session.id;
    await _startMonitoring(session, trackBeacons: false);
    _sessionController.add(session);
  }

  /// The ping interval that will actually be used for [requested] seconds
  /// with the connected radio's LoRa settings (never below the airtime
  /// minimum). Safe to call from the UI to preview.
  ///
  /// MeshCore: the floor is a trace exchange's airtime, not a DM ping's.
  int effectivePingIntervalSec(int requested) =>
      _effectiveIntervalSec(requested, _radio.protocol);

  int _effectiveIntervalSec(int requested, RadioProtocol protocol) => max(
      requested,
      AirtimeModel.minIntervalSecFor(_radio.currentPreset,
          override: AppConstants.fasterThanRecommended(_prefs) &&
              _fasterAllowed(),
          protocol: protocol));

  /// The trace probe interval of a MeshCore session: the base beacon (the
  /// mobile's trace schedule) and pings are one mechanism, so it runs at
  /// the smaller of the two intervals that are on; 0 when both are off.
  /// Both arguments are already floored ([effectivePingIntervalSec]).
  static int meshCoreProbeIntervalSec(
      {required int pingIntervalSec, required int beaconIntervalSec}) {
    final on = [pingIntervalSec, beaconIntervalSec].where((s) => s > 0);
    return on.isEmpty ? 0 : on.reduce(min);
  }

  /// Trace beacon interval Radio Setup recorded for the base (0 when off
  /// or not a trace beacon), floored for the connected radio.
  int _recordedTraceBeaconSec(RadioProtocol protocol) {
    final b = RadioRoles.beaconIn(_prefs);
    if (b == null || b.kind != BeaconKind.trace || b.intervalSec <= 0) {
      return 0;
    }
    return _effectiveIntervalSec(b.intervalSec, protocol);
  }

  /// Start a new recording session.
  ///
  /// Throws [SessionStartError] when the radio isn't usable or the app may
  /// not use location (a session without positions maps nothing). Starts
  /// GPS if it isn't running yet; a missing fix is not an error (check
  /// [GpsService.state] afterwards to warn).
  ///
  /// [baseMeshNodeId] is the base radio's mesh node number: the Radio Setup
  /// base, or the user's pick when there is none. The session stores it
  /// (the map is only the place), so pings, beacons and the out-of-range
  /// monitor follow the radio actually standing at the base. Null refuses.
  Future<Session> startSession({
    required int coverageMapId,
    required int? baseMeshNodeId,
    String name = '',
    int? remoteNodeId,
    String hwAntenna = '',
    String hwNodeModel = '',
    String hwNotes = '',
    int pingIntervalSec = 0,
    int? mobileRigId,
    int? baseRigId,
  }) async {
    // Never test on the public mesh.
    if (!_radio.isReady) {
      throw const SessionStartError('Node not connected over Bluetooth');
    }
    if (_radio.onPublicChannel) {
      throw const SessionStartError('Your node is on the public channel — run '
          'Settings → Node Setup first');
    }
    if (baseMeshNodeId == null) {
      throw const SessionStartError('No base node set up. Run Settings → '
          'Node Setup, or pick the base node (the one that stays put).');
    }
    // A base that is the radio in hand would ping itself (the radio
    // answers locally, so every ping looks delivered) and never hear "the
    // base". Seen on the bench 2026-10-26.
    if (baseMeshNodeId == _radio.myNodeId) {
      throw const SessionStartError('The base node is the node you are '
          'connected to, so it would ping itself. Connect to the node you '
          'carry, or run Settings → Node Setup to choose the base.');
    }

    // MeshCore: the base beacon is our own trace schedule, and with it and
    // pings both off nothing would be heard at all.
    final meshcore = _radio.protocol == RadioProtocol.meshcore;
    final pingSec =
        pingIntervalSec > 0 ? effectivePingIntervalSec(pingIntervalSec) : 0;
    final traceBeaconSec =
        meshcore ? _recordedTraceBeaconSec(_radio.protocol) : 0;
    if (meshcore &&
        meshCoreProbeIntervalSec(
                pingIntervalSec: pingSec, beaconIntervalSec: traceBeaconSec) ==
            0) {
      throw SessionProbeOffError();
    }

    // Location may have been allowed in Settings since launch: retry.
    final gps = await _gps.ensureStarted();
    switch (gps.status) {
      case GpsStatus.denied:
        throw SessionStartError('Location permission is off, so '
            'nothing could be placed on the map. Allow it in '
            '${PlatformText.appPermission('Location')} '
            '("While Using the App"${PlatformText.isAndroid ? ', precise' : ''}), '
            'then try again.');
      case GpsStatus.off:
        throw SessionStartError(PlatformText.locationServicesOff);
      default:
        break;
    }

    // Snapshot the rigs now so later profile edits don't change this session.
    final mobileRig = await _rigById(mobileRigId);
    final baseRig = await _rigById(baseRigId);

    // End any existing active session first
    if (_activeSession != null) {
      await endSession();
    }

    // The base's beacon, as Radio Setup left it (unknown: the first beacon
    // heard decides).
    final beacon = RadioRoles.beaconIn(_prefs);

    final baseNodeId = await _baseNodeRow(baseMeshNodeId);

    final sessionId = await _db.createSession(
      coverageMapId: coverageMapId,
      name: name,
      remoteNodeId: remoteNodeId,
      baseNodeId: baseNodeId,
      // Legacy hw* fields (kept for CSV/back-compat): fall back to the
      // mobile rig's details when not given explicitly.
      hwAntenna: hwAntenna.isNotEmpty
          ? hwAntenna
          : (mobileRig == null
              ? ''
              : [
                  mobileRig.antennaName,
                  if (mobileRig.antennaGainDbi != 0)
                    '${mobileRig.antennaGainDbi} dBi',
                ].where((e) => e.isNotEmpty).join(' ')),
      hwNodeModel:
          hwNodeModel.isNotEmpty ? hwNodeModel : (mobileRig?.radioModel ?? ''),
      hwNotes: hwNotes.isNotEmpty ? hwNotes : (mobileRig?.notes ?? ''),
      mobileRigId: mobileRig?.id,
      baseRigId: baseRig?.id,
      mobileRigJson: mobileRig?.encode(),
      baseRigJson: baseRig?.encode(),
      pingIntervalSec: pingSec,
      loraPreset: _radio.currentPreset?.id ?? '',
      radioSettings: _radio.radioSettings,
      protocol: _radio.protocol.name,
      packetAirtimeMs: AirtimeModel.probeAirtimeMsFor(_radio.currentPreset,
          protocol: _radio.protocol),
      // MeshCore: always the trace beacon (every trace answer is a beacon
      // sample), at the base beacon interval (0 = only pings drive it).
      beaconKind:
          meshcore ? BeaconKind.trace.dbValue : (beacon?.kind.dbValue ?? ''),
      beaconIntervalSec: meshcore ? traceBeaconSec : (beacon?.intervalSec ?? 0),
    );

    _activeSession = await _db.getSessionById(sessionId);
    _packetProcessor.activeSessionId = sessionId;
    await _startMonitoring(_activeSession!);

    await _prefs.setInt(AppConstants.prefActiveSessionId, sessionId);
    _sessionController.add(_activeSession);

    // Out-of-range alerts need notifications: ask now (the first time),
    // with the user looking at the app, instead of cold at launch.
    unawaited(_outOfRangeMonitor.requestNotificationPermission());
    startNotice =
        DemoMode.enabled ? null : AndroidBatteryHint.takeOnce(_prefs);

    return _activeSession!;
  }

  /// Local Nodes.id for the base [meshNodeId], adding the row (with what
  /// the radio knows of it) when the app has never recorded that node.
  Future<int> _baseNodeRow(int meshNodeId) async {
    final existing = await _db.getNodeByMeshId(meshNodeId);
    if (existing != null) return existing.id;
    final user = _radio.nodes[meshNodeId];
    await _db.upsertNode(
      nodeId: meshNodeId,
      longName: user?.longName ?? '',
      shortName: user?.shortName ?? '',
      hwModel: user?.hwModel ?? '',
    );
    return (await _db.getNodeByMeshId(meshNodeId))!.id;
  }

  Future<RigSpec?> _rigById(int? id) async {
    if (id == null) return null;
    final rig = await _db.getRigProfile(id);
    return rig == null ? null : RigSpec.fromProfile(rig);
  }

  /// End the current session
  Future<void> endSession() async {
    if (_activeSession == null) return;
    _endingSessionId = _activeSession!.id;
    try {
      await _endActiveSession();
    } finally {
      _endingSessionId = null;
    }
  }

  /// The session being ended by [endSession], while it runs.
  int? _endingSessionId;

  /// Whether session [id] is recording and not being ended.
  bool _recording(int id) => _activeSession?.id == id && _endingSessionId != id;

  Future<void> _endActiveSession() async {
    _activeProbeService.stop();
    await _traceSub?.cancel();
    _traceSub = null;
    await _beaconSub?.cancel();
    _beaconSub = null;
    DiagLog.instance.log('session', 'ended');
    _outOfRangeMonitor.stop();
    _rideAlong?.stop();
    _gps.setBackgroundMode(false);
    await _statsSub?.cancel();
    _statsSub = null;
    await _db.endSession(_activeSession!.id);
    _packetProcessor.stopBeaconTracking();
    _packetProcessor.otherRadios.stop();
    _packetProcessor.activeSessionId = null;
    await _packetProcessor.flushLastHeard();
    _rangeTestDetector.endSession();

    await _prefs.remove(AppConstants.prefActiveSessionId);
    _activeSession = null;
    _sessionController.add(null);
  }

  /// Keep the highest radio-reported airtime figures on the session row.
  void _trackRadioStats(Session session) {
    _statsSub?.cancel();
    _maxAirUtilTx = session.radioAirUtilTx;
    _maxChannelUtil = session.radioChannelUtil;
    void take(RadioChannelStats s) {
      final air = max(_maxAirUtilTx ?? 0, s.airUtilTxPercent);
      final chan = max(_maxChannelUtil ?? 0, s.channelUtilizationPercent);
      if (air == _maxAirUtilTx && chan == _maxChannelUtil) return;
      _maxAirUtilTx = air;
      _maxChannelUtil = chan;
      unawaited(_db
          .updateSessionRadioStats(session.id,
              airUtilTx: air, channelUtil: chan)
          .catchError((Object e) {
        print('SessionManager: radio stats not saved: $e');
      }));
    }

    final last = _radio.lastChannelStats;
    if (last != null &&
        DateTime.now().difference(last.measuredAt).inMinutes < 5) {
      take(last);
    }
    _statsSub = _radio.channelStats.listen(take);
  }

  /// Point the out-of-range monitor (and pings, if enabled) at the
  /// session's base radio (its map's, for sessions from before schema v8).
  Future<void> _startMonitoring(Session session,
      {bool trackBeacons = true}) async {
    DiagLog.instance.log(
        'session',
        'start #${session.id} map ${session.coverageMapId} '
            'ping ${session.pingIntervalSec}s');
    final baseMeshNodeId = await _db.baseMeshNodeIdForSession(session);
    DiagLog.instance.log('session', 'base ${diagNode(baseMeshNodeId)}');
    _gps.setBackgroundMode(true);
    _trackRadioStats(session);
    // Our base's beacons are recorded without asking.
    _rangeTestDetector.trust([_prefs.getInt(baseNodePrefKey)]);
    if (baseMeshNodeId == null) return;
    _rangeTestDetector.trust([baseMeshNodeId]);
    // Any other radio on the test channel gets a live banner.
    _packetProcessor.otherRadios.start(baseNodeId: baseMeshNodeId);
    // The base put in the car and driven off with the phone: offer to trim.
    unawaited(_rideAlong?.start(session, baseMeshNodeId));

    // Pings may be slower than the saved setting (airtime floor), and the
    // monitor must tolerate at least 3 missed pings. The session's own
    // protocol decides the floor (on resume the radio may not be back yet).
    final protocol = session.protocol == RadioProtocol.meshcore.name
        ? RadioProtocol.meshcore
        : RadioProtocol.meshtastic;
    final trace = protocol == RadioProtocol.meshcore;
    final pingSec = session.pingIntervalSec > 0
        ? _effectiveIntervalSec(session.pingIntervalSec, protocol)
        : 0;
    // MeshCore: one trace schedule serves as both beacon and ping.
    final intervalSec = trace
        ? meshCoreProbeIntervalSec(
            pingIntervalSec: pingSec,
            beaconIntervalSec: session.beaconIntervalSec > 0
                ? _effectiveIntervalSec(session.beaconIntervalSec, protocol)
                : 0)
        : pingSec;
    if (trackBeacons) {
      // Kind none: unknown, decided by the first beacon heard.
      _packetProcessor.startBeaconTracking(
        baseNodeId: baseMeshNodeId,
        kind: trace ? BeaconKind.trace : BeaconKind.fromDb(session.beaconKind),
        intervalSec: trace ? intervalSec : session.beaconIntervalSec,
      );
    }
    if (trace) {
      _followTraces(session, baseMeshNodeId, trackBeacons: trackBeacons);
    }
    _configureOutOfRange(baseMeshNodeId,
        protocol: protocol,
        intervalSec: intervalSec,
        beaconSec: trace ? 0 : session.beaconIntervalSec);

    if (intervalSec > 0) {
      _activeProbeService.start(
        sessionId: session.id,
        baseMeshNodeId: baseMeshNodeId,
        intervalSec: intervalSec,
      );
    }
  }

  void _configureOutOfRange(int baseMeshNodeId,
      {required RadioProtocol protocol,
      required int intervalSec,
      required int beaconSec}) {
    final timeoutSec = outOfRangeTimeoutSecFor(
      prefSec: AppConstants.outOfRangeTimeoutSec(_prefs),
      intervalSec: intervalSec,
      replySec: ActiveProbeService.pingTimeoutSecFor(protocol, intervalSec),
      beaconSec: beaconSec,
    );
    _oorTimeoutSec = timeoutSec;
    _outOfRangeMonitor.configure(
        baseNodeId: baseMeshNodeId, timeoutSec: timeoutSec);
  }

  /// The out-of-range window: the user's setting, but at least three
  /// missed probes. Three probes after the last answer go out at 1, 2 and
  /// 3 intervals, and the third can only be answered within its reply
  /// timeout after that, so the window is 3 × interval + the reply time
  /// (3 × interval alone fired before the third reply could land: two
  /// misses, not three). With pings off the base is only heard when it
  /// beacons, so the window spans two beacon intervals plus the
  /// firmware's jitter, or every telemetry gap would read as out of range.
  static int outOfRangeTimeoutSecFor({
    required int prefSec,
    required int intervalSec,
    required int replySec,
    required int beaconSec,
  }) =>
      [
        prefSec,
        if (intervalSec > 0) 3 * intervalSec + replySec,
        if (intervalSec == 0 && beaconSec > 0) 2 * beaconSec + 30,
      ].reduce(max);

  /// MeshCore: the radio consumes trace replies itself (they never reach
  /// the packet stream), so each trace outcome is fed here to the
  /// out-of-range monitor and the beacon tracker: an answer from the base
  /// is the base heard and a beacon sample, a timeout one beacon miss.
  /// Also follows base beacon changes made in Radio Setup mid-session.
  void _followTraces(Session session, int baseMeshNodeId,
      {required bool trackBeacons}) {
    _traceSub?.cancel();
    _traceSub = _activeProbeService.outcomes.listen((sample) {
      if (_activeSession?.id != session.id) return;
      final beacons = _packetProcessor.beacons;
      if (sample.status == AckStatus.received && sample.fromBase) {
        _outOfRangeMonitor.onPacketReceived(baseMeshNodeId);
        if (trackBeacons && beacons.active) {
          beacons.onBeacon(BeaconKind.trace, sample.answeredAt,
              lat: sample.latitude, lon: sample.longitude);
        }
      } else if (sample.status == AckStatus.timeout &&
          trackBeacons &&
          beacons.active) {
        beacons.onTraceTimeout(sample.answeredAt);
      }
    });
    _beaconSub?.cancel();
    _beaconSub = RadioRoles.beaconChanges.listen((b) {
      unawaited(_retuneTrace(session.id, baseMeshNodeId, b));
    });
  }

  /// The base beacon changed while a MeshCore session records: store the
  /// new interval on the session and move the trace probe to the new rule
  /// interval (stopping it when both beacon and pings are now off).
  Future<void> _retuneTrace(int sessionId, int baseMeshNodeId,
      ({BeaconKind kind, int intervalSec}) beacon) async {
    final session = _activeSession;
    if (session == null || !_recording(sessionId)) return;
    final beaconSec = beacon.kind == BeaconKind.trace && beacon.intervalSec > 0
        ? _effectiveIntervalSec(beacon.intervalSec, RadioProtocol.meshcore)
        : 0;
    await _db.updateSessionBeacon(sessionId,
        kind: BeaconKind.trace.dbValue, intervalSec: beaconSec);
    // The session may have ended meanwhile: leave the probe, tracker and
    // monitor as endSession left them.
    if (!_recording(sessionId)) return;
    final pingSec = session.pingIntervalSec > 0
        ? _effectiveIntervalSec(session.pingIntervalSec, RadioProtocol.meshcore)
        : 0;
    final probeSec = meshCoreProbeIntervalSec(
        pingIntervalSec: pingSec, beaconIntervalSec: beaconSec);
    DiagLog.instance.log('session',
        'trace beacon ${beaconSec}s, ping ${pingSec}s -> probe ${probeSec}s');
    if (probeSec == 0) {
      _activeProbeService.stop();
    } else if (_activeProbeService.isActive) {
      _activeProbeService.retune(probeSec);
    } else {
      _activeProbeService.start(
          sessionId: sessionId,
          baseMeshNodeId: baseMeshNodeId,
          intervalSec: probeSec);
    }
    _packetProcessor.beacons.retune(probeSec);
    final timeout = outOfRangeTimeoutSecFor(
      prefSec: AppConstants.outOfRangeTimeoutSec(_prefs),
      intervalSec: probeSec,
      replySec: ActiveProbeService.pingTimeoutSecFor(
          RadioProtocol.meshcore, probeSec),
      beaconSec: 0,
    );
    if (timeout != _oorTimeoutSec) {
      _configureOutOfRange(baseMeshNodeId,
          protocol: RadioProtocol.meshcore,
          intervalSec: probeSec,
          beaconSec: 0);
    }
    final updated = await _db.getSessionById(sessionId);
    // Never put an ended session back as the active one.
    if (updated == null || !_recording(sessionId)) return;
    _activeSession = updated;
    _sessionController.add(updated);
  }

  void dispose() {
    _traceSub?.cancel();
    _beaconSub?.cancel();
    _statsSub?.cancel();
    _sessionController.close();
  }
}
