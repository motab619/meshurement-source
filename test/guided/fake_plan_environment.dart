// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:latlong2/latlong.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/models/processed_signal_event.dart';
import 'package:mesh_analyzer/services/active_probe_service.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/services/guided/plan_environment.dart';
import 'package:mesh_analyzer/services/session_manager.dart';
import 'package:mesh_analyzer/utils/constants.dart';

/// A scriptable [PlanEnvironment]: a real in-memory database for sessions,
/// everything else set by the test.
class FakePlanEnvironment implements PlanEnvironment {
  FakePlanEnvironment(this.db);

  @override
  final AppDatabase db;

  // ─── Radio ──────────────────────────────────────────────────────────

  bool ready = true;
  final _readyChanges = StreamController<bool>.broadcast();
  void setReady(bool v) {
    ready = v;
    _readyChanges.add(v);
  }

  @override
  bool get radioReady => ready;
  @override
  Stream<bool> get radioReadyChanges => _readyChanges.stream;
  @override
  RadioProtocol protocol = RadioProtocol.meshtastic;
  @override
  int? myNodeId = 0x1001;
  @override
  String radioDisplayName = 'MeshTest Mobile';
  @override
  RadioPreset? currentPreset = MeshtasticPresets.mediumFast;
  @override
  int? currentTxPowerDbm = 27;
  @override
  bool supportsRemoteAdmin = true;
  @override
  bool onTestChannel = true;

  // ─── Roles ──────────────────────────────────────────────────────────

  @override
  int? baseNodeNum = 0x2002;
  @override
  String baseLabel = 'MeshTest Base · Heltec V3 · !2002';
  @override
  bool connectedIsMobile = true;
  @override
  String? setupMismatch;
  @override
  String? basePresetId = 'MEDIUM_FAST';
  @override
  int? baseTxPowerDbm = 27;
  @override
  ({BeaconKind kind, int intervalSec})? baseBeacon =
      (kind: BeaconKind.telemetry, intervalSec: 60);
  @override
  int? remoteAdminMobileNode;
  @override
  DateTime? baseLastHeardAt = DateTime.now();
  bool originalBackup = true;

  /// Every `recordBaseSetting` call: (presetId, txPower).
  final recordedBase = <(String?, int?)>[];

  @override
  Future<void> recordBaseSetting({String? presetId, int? txPowerDbm}) async =>
      recordedBase.add((presetId, txPowerDbm));

  @override
  Future<bool> hasOriginalBaseBackup() async => originalBackup;

  // ─── GPS ────────────────────────────────────────────────────────────

  @override
  GpsState gpsState = const GpsState(GpsStatus.fix, accuracy: 4);
  final _gpsStates = StreamController<GpsState>.broadcast();
  @override
  Stream<GpsState> get gpsStates => _gpsStates.stream;
  void setGps(GpsState s) {
    gpsState = s;
    _gpsStates.add(s);
  }

  @override
  LatLng? lastPosition;
  @override
  double? lastAccuracyM = 4;
  final _positions = StreamController<LatLng>.broadcast();
  @override
  Stream<LatLng> get positions => _positions.stream;

  /// Move the phone: becomes [lastPosition] and is streamed.
  void moveTo(LatLng p) {
    lastPosition = p;
    _positions.add(p);
  }

  int gpsStarts = 0;
  @override
  Future<void> ensureGps() async => gpsStarts++;

  // ─── Traffic ────────────────────────────────────────────────────────

  final _signals = StreamController<ProcessedSignalEvent>.broadcast();
  final _pings = StreamController<PingSample>.broadcast();
  @override
  Stream<ProcessedSignalEvent> get signals => _signals.stream;
  @override
  Stream<PingSample> get pings => _pings.stream;

  void hearBase({double snr = 7.5}) => _signals.add(ProcessedSignalEvent(
        timestamp: DateTime.now(),
        sourceNodeId: baseNodeNum ?? 0,
        rxSnr: snr,
        rxRssi: -90,
        packetType: PacketType.telemetry,
        direction: PacketDirection.rx,
      ));

  /// A ping outcome; also written to the database as a ping of the active
  /// session when [record] (so the thin-walk count sees it).
  Future<void> pingOutcome(String status,
      {double? snr = 5, bool record = true}) async {
    final now = DateTime.now();
    final s = activeSession;
    if (record && s != null) {
      final p = lastPosition;
      final txId = await db.insertPacketEvent(PacketEventsCompanion.insert(
        sessionId: s.id,
        timestamp: now,
        direction: PacketDirection.tx,
        sourceNodeId: await _nodeRow(myNodeId ?? 1),
        packetType: PacketType.ping,
        rxLat: Value(p?.latitude),
        rxLon: Value(p?.longitude),
        sourceKind: const Value(SourceKind.passive),
      ));
      int? ackId;
      if (status == AckStatus.received) {
        ackId = await db.insertPacketEvent(PacketEventsCompanion.insert(
          sessionId: s.id,
          timestamp: now,
          direction: PacketDirection.ack,
          sourceNodeId: await _nodeRow(baseNodeNum ?? 2),
          packetType: PacketType.ack,
          rxSnr: Value(snr),
          rxRssi: const Value(-95),
          rxLat: Value(p?.latitude),
          rxLon: Value(p?.longitude),
          sourceKind: const Value(SourceKind.ack),
        ));
      }
      await db.insertPingCorrelation(PingCorrelationsCompanion.insert(
        txEventId: txId,
        ackEventId: Value(ackId),
        ackStatus: Value(status),
      ));
    }
    _pings.add(PingSample(
      sentAt: now,
      answeredAt: now,
      status: status,
      snr: snr,
      fromBase: status == AckStatus.received,
      latitude: lastPosition?.latitude,
      longitude: lastPosition?.longitude,
    ));
  }

  Future<int> _nodeRow(int meshId) async {
    final n = await db.getNodeByMeshId(meshId);
    if (n != null) return n.id;
    return db.upsertNode(nodeId: meshId, longName: 'node $meshId');
  }

  // ─── Sessions ───────────────────────────────────────────────────────

  @override
  Session? activeSession;
  final _sessions = StreamController<Session?>.broadcast();
  @override
  Stream<Session?> get sessionStream => _sessions.stream;

  /// Set to refuse the next start.
  String? startRefusal;
  final startedNames = <String>[];
  final startedRigs = <(int?, int?)>[];

  @override
  Future<Session> startSession({
    required int coverageMapId,
    required String name,
    int? mobileRigId,
    int? baseRigId,
  }) async {
    if (startRefusal != null) throw SessionStartError(startRefusal!);
    if (activeSession != null) await endSession();
    final baseRow = baseNodeNum == null ? null : await _nodeRow(baseNodeNum!);
    final id = await db.createSession(
      coverageMapId: coverageMapId,
      name: name,
      baseNodeId: baseRow,
      loraPreset: currentPreset?.id ?? '',
      protocol: protocol.name,
      pingIntervalSec: 15,
      mobileRigId: mobileRigId,
      baseRigId: baseRigId,
    );
    startedNames.add(name);
    startedRigs.add((mobileRigId, baseRigId));
    activeSession = await db.getSessionById(id);
    _sessions.add(activeSession);
    return activeSession!;
  }

  @override
  Future<void> endSession() async {
    final s = activeSession;
    if (s == null) return;
    await db.endSession(s.id);
    activeSession = null;
    _sessions.add(null);
  }

  /// The session ended from outside the plan (out of range, Live tab).
  Future<void> endSessionExternally() => endSession();

  // ─── Radio changes ──────────────────────────────────────────────────

  final remoteChanges = <(String?, int?)>[];
  final bluetoothBaseChanges = <(String, int?)>[];
  final mobileChanges = <(String, int?)>[];
  Object? remoteError;
  Object? mobileError;

  /// The radio in hand says it applied a change but reports the old
  /// setting afterwards.
  bool mobileIgnoresChanges = false;

  /// What each changeBaseRemote reports in turn (true = the base confirmed
  /// the save); confirmed once the list runs out.
  final List<bool> remoteConfirms = [];

  @override
  Future<bool> changeBaseRemote({
    RadioPreset? preset,
    int? txPowerDbm,
    required void Function(String step) onStep,
  }) async {
    if (remoteError != null) throw remoteError!;
    onStep('begin edit');
    onStep('commit');
    remoteChanges.add((preset?.id, txPowerDbm));
    return remoteConfirms.isEmpty ? true : remoteConfirms.removeAt(0);
  }

  @override
  Future<void> changeBaseBluetooth({
    required RadioPreset preset,
    int? txPowerDbm,
    required void Function(String step) onStep,
  }) async {
    onStep('Connecting to the base node…');
    bluetoothBaseChanges.add((preset.id, txPowerDbm));
  }

  @override
  Future<void> changeMobile({
    required RadioPreset preset,
    int? txPowerDbm,
    required void Function(String step) onStep,
  }) async {
    if (mobileError != null) throw mobileError!;
    onStep('Applying…');
    mobileChanges.add((preset.id, txPowerDbm));
    if (mobileIgnoresChanges) return;
    currentPreset = preset;
    if (txPowerDbm != null) currentTxPowerDbm = txPowerDbm;
  }

  final prepared = <int>[];
  @override
  Future<void> prepareToPing(int nodeNum) async => prepared.add(nodeNum);

  /// Outcomes for the change step's pings, in order; empty → timeout.
  final List<PingStatus> pingScript = [];
  int pingsAsked = 0;

  @override
  Future<PingOutcome> ping(int nodeNum,
      {Duration timeout = const Duration(seconds: 30)}) async {
    pingsAsked++;
    final status =
        pingScript.isEmpty ? PingStatus.timeout : pingScript.removeAt(0);
    return PingOutcome(
        pingId: pingsAsked,
        status: status,
        roundTrip: const Duration(milliseconds: 400),
        responder: status == PingStatus.received ? nodeNum : null,
        snr: 6);
  }

  Future<void> dispose() async {
    await _readyChanges.close();
    await _gpsStates.close();
    await _positions.close();
    await _signals.close();
    await _pings.close();
    await _sessions.close();
  }
}
