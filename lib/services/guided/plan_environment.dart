// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:latlong2/latlong.dart';

import '../../data/database/app_database.dart';
import '../../data/radio/mesh_radio.dart';
import '../../models/processed_signal_event.dart';
import '../active_probe_service.dart' show PingSample;
import '../gps_service.dart' show GpsState;

/// Everything the guided-test runner needs from the rest of the app, as
/// one seam: radio, roles, GPS, sessions and the radio-change flows.
///
/// `AppPlanEnvironment` (Riverpod wiring) implements it from the real
/// services; tests fake it. Keeping the runner behind this interface is
/// what lets its state machine be unit tested without Bluetooth.
abstract class PlanEnvironment {
  AppDatabase get db;

  // ─── The radio in hand ─────────────────────────────────────────────

  bool get radioReady;

  /// Every change of [radioReady].
  Stream<bool> get radioReadyChanges;
  RadioProtocol get protocol;
  int? get myNodeId;
  String get radioDisplayName;
  RadioPreset? get currentPreset;
  int? get currentTxPowerDbm;
  bool get supportsRemoteAdmin;

  /// Connected and on our private test channel (any role).
  bool get onTestChannel;

  // ─── Roles (Radio Setup) ───────────────────────────────────────────

  /// Mesh node number of the base, or null when Radio Setup never ran.
  int? get baseNodeNum;

  /// "MeshTest Base · Heltec V3 · !a3f2" for the preflight row.
  String get baseLabel;

  /// The radio in hand is the mobile (not the base, not unknown).
  bool get connectedIsMobile;

  /// `RadioRoles.setupMismatch`.
  String? get setupMismatch;

  /// Preset id / TX power Radio Setup last wrote to the base.
  String? get basePresetId;
  int? get baseTxPowerDbm;
  ({BeaconKind kind, int intervalSec})? get baseBeacon;

  /// Mobile node number the base's remote-admin grant was made for.
  int? get remoteAdminMobileNode;

  /// When the base was last heard over the air, or null.
  DateTime? get baseLastHeardAt;

  /// Remember what a remote change wrote to the base (so the mismatch check
  /// stays honest).
  Future<void> recordBaseSetting({String? presetId, int? txPowerDbm});

  /// An `original` backup of the base's settings exists.
  Future<bool> hasOriginalBaseBackup();

  // ─── GPS ───────────────────────────────────────────────────────────

  GpsState get gpsState;
  Stream<GpsState> get gpsStates;
  LatLng? get lastPosition;
  double? get lastAccuracyM;
  Stream<LatLng> get positions;

  /// Start GPS if it isn't running (may prompt).
  Future<void> ensureGps();

  // ─── Live traffic ──────────────────────────────────────────────────

  Stream<ProcessedSignalEvent> get signals;
  Stream<PingSample> get pings;

  // ─── Sessions ──────────────────────────────────────────────────────

  Session? get activeSession;
  Stream<Session?> get sessionStream;

  /// `SessionManager.startSession` with the Radio Setup base and the user's
  /// ping interval; throws `SessionStartError`.
  Future<Session> startSession({
    required int coverageMapId,
    required String name,
    int? mobileRigId,
    int? baseRigId,
  });
  Future<void> endSession();

  // ─── Radio changes (design §5, §6) ─────────────────────────────────

  /// Change the base over the mesh (`MeshRadio.setRemoteLora`). True when
  /// the base acknowledged the save; false when the commit went
  /// unanswered: sent, but over the mesh the commit itself may be what got
  /// lost (the base then keeps the old setting).
  Future<bool> changeBaseRemote({
    RadioPreset? preset,
    int? txPowerDbm,
    required void Function(String step) onStep,
  });

  /// Change the base over a second Bluetooth connection
  /// (`RadioProfileService.applyToBase`, which backs it up first).
  Future<void> changeBaseBluetooth({
    required RadioPreset preset,
    int? txPowerDbm,
    required void Function(String step) onStep,
  });

  /// Change the radio in hand (`RadioProfileService.applyToMobile`; it
  /// reboots and reconnects).
  Future<void> changeMobile({
    required RadioPreset preset,
    int? txPowerDbm,
    required void Function(String step) onStep,
  });

  Future<void> prepareToPing(int nodeNum);
  Future<PingOutcome> ping(int nodeNum,
      {Duration timeout = const Duration(seconds: 30)});
}
