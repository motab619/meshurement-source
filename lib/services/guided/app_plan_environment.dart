// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database/app_database.dart';
import '../../data/radio/mesh_radio.dart';
import '../../models/processed_signal_event.dart';
import '../../utils/constants.dart';
import '../active_probe_service.dart';
import '../gps_service.dart';
import '../packet_processor.dart';
import '../radio_backup_service.dart';
import '../radio_profile_service.dart';
import '../radio_roles.dart';
import '../session_manager.dart';
import 'plan_environment.dart';
import 'remote_admin_flag.dart' as flag;

/// [PlanEnvironment] over the real services (wired in `providers.dart`).
class AppPlanEnvironment implements PlanEnvironment {
  AppPlanEnvironment({
    required AppDatabase db,
    required MeshRadio radio,
    required RadioRoles roles,
    required SharedPreferences prefs,
    required RadioProfileService profiles,
    required RadioBackupService backups,
    required GpsService gps,
    required SessionManager sessions,
    required PacketProcessor packets,
    required ActiveProbeService probe,
  })  : _db = db,
        _radio = radio,
        _roles = roles,
        _prefs = prefs,
        _profiles = profiles,
        _backups = backups,
        _gps = gps,
        _sessions = sessions,
        _packets = packets,
        _probe = probe {
    // Remember when the base was last heard, whatever the radio's node
    // list says (it may be stale after a reconnect).
    _signalSub = _packets.signalStream.listen((e) {
      if (e.sourceNodeId == baseNodeNum) _baseHeard = e.timestamp;
    });
    _pingSub = _probe.outcomes.listen((s) {
      if (s.fromBase && s.status == AckStatus.received) {
        _baseHeard = s.answeredAt;
      }
    });
  }

  final AppDatabase _db;
  final MeshRadio _radio;
  final RadioRoles _roles;
  final SharedPreferences _prefs;
  final RadioProfileService _profiles;
  final RadioBackupService _backups;
  final GpsService _gps;
  final SessionManager _sessions;
  final PacketProcessor _packets;
  final ActiveProbeService _probe;
  StreamSubscription<ProcessedSignalEvent>? _signalSub;
  StreamSubscription<PingSample>? _pingSub;
  DateTime? _baseHeard;

  @override
  AppDatabase get db => _db;

  // ─── Radio ──────────────────────────────────────────────────────────

  @override
  bool get radioReady => _radio.isReady;

  @override
  Stream<bool> get radioReadyChanges => _radio.connectionState
      .map((s) => s == RadioConnectionState.ready)
      .distinct();

  @override
  RadioProtocol get protocol => _radio.protocol;

  @override
  int? get myNodeId => _radio.myNodeId;

  @override
  String get radioDisplayName => _radio.displayName;

  @override
  RadioPreset? get currentPreset => _radio.currentPreset;

  @override
  int? get currentTxPowerDbm => _radio.radioSettings?.txPowerDbm;

  @override
  bool get supportsRemoteAdmin => _radio.supportsRemoteAdmin;

  @override
  bool get onTestChannel => _profiles.isOnTestChannel(_radio);

  // ─── Roles ──────────────────────────────────────────────────────────

  @override
  int? get baseNodeNum => _roles.nodeOf(RadioRole.base);

  @override
  String get baseLabel {
    final num = baseNodeNum;
    if (num == null) return '';
    final node = _radio.nodes[num];
    final hex = '!${num.toRadixString(16).padLeft(8, '0').substring(4)}';
    return [
      if (node != null && node.longName.isNotEmpty) node.longName,
      if (node != null && node.hwModel.isNotEmpty) _hardware(node.hwModel),
      hex,
    ].join(' · ');
  }

  static String _hardware(String hw) => hw
      .toLowerCase()
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w.length <= 2
          ? w.toUpperCase()
          : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  @override
  bool get connectedIsMobile => _roles.roleOf(_radio) == RadioRole.mobile;

  @override
  String? get setupMismatch => _roles.setupMismatch();

  @override
  String? get basePresetId => _roles.presetOf(RadioRole.base);

  @override
  int? get baseTxPowerDbm => _roles.txPowerOf(RadioRole.base);

  @override
  ({BeaconKind kind, int intervalSec})? get baseBeacon {
    final b = _roles.baseBeacon;
    return b == null ? null : (kind: b.kind, intervalSec: b.intervalSec);
  }

  @override
  int? get remoteAdminMobileNode => flag.remoteAdminMobileNode(_prefs);

  @override
  DateTime? get baseLastHeardAt {
    final num = baseNodeNum;
    final fromNodes = num == null ? null : _radio.nodes[num]?.lastHeard;
    final a = _baseHeard, b = fromNodes;
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  @override
  Future<void> recordBaseSetting({String? presetId, int? txPowerDbm}) =>
      _roles.recordSetup(
        RadioRole.base,
        presetId: presetId ?? _roles.presetOf(RadioRole.base) ?? '',
        region: _roles.regionOf(RadioRole.base) ?? '',
        frequencySlot: _roles.slotOf(RadioRole.base),
        txPowerDbm: txPowerDbm ?? _roles.txPowerOf(RadioRole.base),
        frequencyMHz: _roles.frequencyOf(RadioRole.base),
      );

  @override
  Future<bool> hasOriginalBaseBackup() async {
    final num = baseNodeNum;
    if (num == null) return false;
    final mine = (await _backups.list()).where((b) => b.nodeNum == num);
    return RadioBackup.originalOf(mine) != null;
  }

  // ─── GPS ────────────────────────────────────────────────────────────

  @override
  GpsState get gpsState => _gps.state;

  @override
  Stream<GpsState> get gpsStates => _gps.stateStream;

  @override
  LatLng? get lastPosition {
    final p = _gps.lastPosition;
    return p == null ? null : LatLng(p.latitude, p.longitude);
  }

  @override
  double? get lastAccuracyM => _gps.lastPosition?.accuracy;

  @override
  Stream<LatLng> get positions =>
      _gps.positionStream.map((p) => LatLng(p.latitude, p.longitude));

  @override
  Future<void> ensureGps() => _gps.ensureStarted();

  // ─── Traffic ────────────────────────────────────────────────────────

  @override
  Stream<ProcessedSignalEvent> get signals => _packets.signalStream;

  @override
  Stream<PingSample> get pings => _probe.outcomes;

  // ─── Sessions ───────────────────────────────────────────────────────

  @override
  Session? get activeSession => _sessions.activeSession;

  @override
  Stream<Session?> get sessionStream => _sessions.sessionStream;

  @override
  Future<Session> startSession({
    required int coverageMapId,
    required String name,
    int? mobileRigId,
    int? baseRigId,
  }) =>
      _sessions.startSession(
        coverageMapId: coverageMapId,
        baseMeshNodeId: baseNodeNum,
        name: name,
        pingIntervalSec: AppConstants.pingIntervalSec(_prefs),
        mobileRigId: mobileRigId,
        baseRigId: baseRigId,
      );

  @override
  Future<void> endSession() => _sessions.endSession();

  // ─── Radio changes ──────────────────────────────────────────────────

  /// The step `MeshtasticRadio.setRemoteLora` reports when the commit got
  /// no ACK (it counts that as sent: the reboot often eats the ACK).
  static const _unconfirmedSave = 'did not confirm the save';

  @override
  Future<bool> changeBaseRemote({
    RadioPreset? preset,
    int? txPowerDbm,
    required void Function(String step) onStep,
  }) async {
    final num = baseNodeNum;
    if (num == null) throw StateError('The base node is not known');
    var confirmed = true;
    await _radio.setRemoteLora(num, preset: preset, txPowerDbm: txPowerDbm,
        onStep: (s) {
      if (s.contains(_unconfirmedSave)) confirmed = false;
      onStep(s);
    });
    return confirmed;
  }

  @override
  Future<void> changeBaseBluetooth({
    required RadioPreset preset,
    int? txPowerDbm,
    required void Function(String step) onStep,
  }) {
    final id = _roles.deviceOf(RadioRole.base);
    if (id == null) {
      throw StateError('The base node\'s Bluetooth id is not known. Set it '
          'up in Node Setup first.');
    }
    final beacon = _roles.baseBeacon;
    return _profiles.applyToBase(
      RadioDescriptor(id: id, name: 'Base node', protocol: _radio.protocol),
      preset: preset,
      beaconSecs: beacon == null || beacon.kind == BeaconKind.none
          ? 0
          : beacon.intervalSec,
      onStep: onStep,
      frequencyMHz: _roles.frequencyOf(RadioRole.base),
      txPowerDbm: txPowerDbm,
      expectNodeNum: baseNodeNum,
    );
  }

  @override
  Future<void> changeMobile({
    required RadioPreset preset,
    int? txPowerDbm,
    required void Function(String step) onStep,
  }) =>
      _profiles.applyToMobile(
        preset: preset,
        onStep: onStep,
        frequencyMHz: _roles.frequencyOf(RadioRole.mobile),
        txPowerDbm: txPowerDbm,
      );

  @override
  Future<void> prepareToPing(int nodeNum) => _radio.prepareToPing(nodeNum);

  /// The guided listen loop pings here, not through [ActiveProbeService],
  /// so the public-channel rule is applied here too (the radios refuse as
  /// well).
  @override
  Future<PingOutcome> ping(int nodeNum,
      {Duration timeout = const Duration(seconds: 30)}) async {
    if (_radio.onPublicChannel) {
      return const PingOutcome(
          pingId: 0,
          status: PingStatus.error,
          errorReason: 'PUBLIC_CHANNEL',
          roundTrip: Duration.zero);
    }
    return _radio.ping(nodeNum, timeout: timeout);
  }

  void dispose() {
    _signalSub?.cancel();
    _pingSub?.cancel();
  }
}
