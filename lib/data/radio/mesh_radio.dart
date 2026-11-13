// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'radio_preset.dart';
import 'radio_types.dart';

export 'radio_preset.dart';
export 'radio_types.dart';

/// The phone's own radio, whatever protocol it speaks.
///
/// Services and UI use only this interface and the neutral types in
/// `radio_types.dart`. Protocol code (protobufs, frame formats) and the
/// Bluetooth plugin stay inside the implementations (`meshtastic/`, later
/// `meshcore/`) and `ble/`.
abstract class MeshRadio {
  RadioProtocol get protocol;

  // ─── Link ──────────────────────────────────────────────

  RadioConnectionState get state;

  /// Current state, then every change. Survives reconnects.
  Stream<RadioConnectionState> get connectionState;

  /// Step-by-step progress while connecting, pairing, configuring or
  /// reconnecting; null once ready or disconnected.
  ConnectProgress? get connectProgress;

  /// Every progress change (including back to null).
  Stream<ConnectProgress?> get connectProgressStream;
  bool get isReady => state == RadioConnectionState.ready;

  Future<void> connect(RadioDescriptor radio);
  Future<void> disconnect();

  /// The radio we're linked to (or last tried), if any.
  RadioDescriptor? get descriptor;

  /// Name for the UI: the radio's own long name, else its Bluetooth name.
  String get displayName;

  /// Pretend connected radio used by demo mode (nothing goes over the air).
  bool get isDemo;

  // ─── What the radio knows ──────────────────────────────

  /// What the connected radio's firmware can do (empty until configured).
  RadioCapabilities get capabilities;

  Future<RadioInfo> queryDevice();

  /// Our radio's node number, once configured.
  int? get myNodeId;

  /// Node DB as last reported by the radio, keyed by node number.
  Map<int, RadioNode> get nodes;

  /// A node's name, hardware or position changed.
  Stream<RadioNode> get nodeUpdates;

  /// Modulation the radio is on (null until configured).
  RadioPreset? get currentPreset;

  /// Centre frequency for the radio's region, in MHz (for path-loss maths).
  double get regionFrequencyMHz;

  /// Region code name for display, e.g. "US" (empty when unknown).
  String get regionName;

  /// Frequency slot, transmit power, hop limit and region the radio runs
  /// on (null until configured, or when the radio can't say). Recorded on
  /// every session next to the preset.
  RadioSettings? get radioSettings;

  /// Name and key presence of the primary channel, for display.
  String get primaryChannelName;

  /// True when the primary channel is the public/default one. Sessions
  /// refuse to start then: we never test on the public channel.
  bool get onPublicChannel;

  // ─── Traffic ───────────────────────────────────────────

  /// Every packet heard (not our own), with signal.
  Stream<ReceivedPacket> get packets;

  /// Estimated airtime (ms) of each packet we send, for the duty meter.
  Stream<double> get txAirtimeStream;

  /// The radio's own airtime / channel-utilization report. Optional: radios
  /// or protocols that don't report it (MeshCore may never) emit nothing and
  /// [lastChannelStats] stays null.
  Stream<RadioChannelStats> get channelStats;

  /// Most recent report since connecting, if any.
  RadioChannelStats? get lastChannelStats;

  /// Fixes from our own node's GPS, when it has one (docs/design/ipad,
  /// step 5). Bluetooth only: Meshtastic 2.8+ hands its own position to
  /// the phone every 60 s without sending it on air; MeshCore answers a
  /// local telemetry request. A node without GPS emits nothing.
  Stream<NodeFix> get ownFixes;

  /// The latest of [ownFixes] since connecting, if any.
  NodeFix? get lastOwnFix;

  /// Whether anyone needs [ownFixes] now (the phone has no good fix of its
  /// own; set by the app from GpsService). While false the radio does no
  /// extra Bluetooth work for them: no MeshCore polling, no node list
  /// re-read on Meshtastic before 2.8. Fixes the node sends anyway still
  /// come through. True until told otherwise.
  bool get ownFixesWanted;
  set ownFixesWanted(bool wanted);

  /// Get ready to ping [target] (e.g. swap keys so DMs can be decrypted).
  Future<void> prepareToPing(int target);

  /// Ping [target] and wait for the outcome; never throws (a send failure
  /// is a [PingStatus.error] outcome). [beforeSend] gets the ping id and
  /// runs before anything is transmitted, so the caller can record it
  /// first.
  Future<PingOutcome> ping(
    int target, {
    Duration timeout,
    int channel,
    FutureOr<void> Function(int pingId)? beforeSend,
  });

  // ─── Configuration ─────────────────────────────────────

  /// Put the radio on our private channel and preset (and the base's
  /// beacon). May reboot it; the link then reconnects by itself. Returns
  /// the beacon written to a base (kind resolved), null for a mobile.
  Future<BeaconConfig?> applyTestProfile(
    TestProfile profile, {
    void Function(String step)? onStep,
  });

  /// The [radioSettings] the radio will have once [applyTestProfile] has
  /// written [profile] (it reboots, so they can't be read back at once).
  RadioSettings? settingsAfter(TestProfile profile);

  /// Turn the base's periodic beacon on, off or to another kind. A null
  /// [BeaconConfig.kind] lets the radio choose. Returns what was written.
  Future<BeaconConfig> setBeacon(BeaconConfig config);

  // ─── Remote administration (guided test, design §5) ───────────────────

  /// Whether this radio can change another node's settings over the mesh.
  /// Meshtastic: yes once the target lists our public key in
  /// `security.admin_key`. MeshCore companions: never.
  bool get supportsRemoteAdmin => false;

  /// Let the node holding [publicKey] (32 bytes) administer THIS radio
  /// from a distance: adds it to the local `security.admin_key` list over
  /// the phone's link. Radio Setup's base flow calls it with the mobile
  /// radio's key. Throws [UnsupportedError] where [supportsRemoteAdmin]
  /// is false.
  Future<void> grantRemoteAdmin(List<int> publicKey) =>
      throw UnsupportedError('No remote administration on $protocol');

  /// Change the modem preset and/or TX power of node [nodeNum] over the
  /// mesh (session passkey handshake, begin/set/commit; the node reboots
  /// on commit, so a lost ACK on the commit counts as sent). Throws
  /// [UnsupportedError] where [supportsRemoteAdmin] is false, [StateError]
  /// on a NAK (e.g. our key is not an admin key there).
  Future<void> setRemoteLora(
    int nodeNum, {
    RadioPreset? preset,
    int? txPowerDbm,
    void Function(String step)? onStep,
  }) =>
      throw UnsupportedError('No remote administration on $protocol');

  Future<void> dispose();
}
