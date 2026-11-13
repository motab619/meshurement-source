// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/radio/meshcore/meshcore_presets.dart';
import '../data/radio/mesh_radio.dart';
import 'base_node.dart';

/// What a radio is for: the base stays put and sends the beacon; the
/// mobile is carried and connected to the phone while mapping.
enum RadioRole {
  base('Base'),
  mobile('Mobile');

  final String label;
  const RadioRole(this.label);

  RadioRole get other => this == base ? mobile : base;
}

/// Which radio is the base and which the mobile, remembered by node
/// number (known once connected) and Bluetooth id (known from a scan, so
/// the connect list can tag radios before connecting).
///
/// Radio Setup assigns roles; connecting to a radio with a known node
/// number fills in its Bluetooth id.
class RadioRoles extends ChangeNotifier {
  static const mobileNodeKey = 'mobile_node_num';
  static const baseDeviceKey = 'base_ble_id';
  static const mobileDeviceKey = 'mobile_ble_id';
  static const basePresetKey = 'base_preset_id';
  static const mobilePresetKey = 'mobile_preset_id';
  static const baseRegionKey = 'base_region';
  static const mobileRegionKey = 'mobile_region';

  /// Frequency slot and transmit power the radio in each role was left on
  /// by Radio Setup (from the radio's own settings; absent when unknown).
  static const baseSlotKey = 'base_frequency_slot';
  static const mobileSlotKey = 'mobile_frequency_slot';
  static const baseTxPowerKey = 'base_tx_power_dbm';
  static const mobileTxPowerKey = 'mobile_tx_power_dbm';

  /// Centre frequency (MHz) each radio was left on, where the protocol
  /// sets an exact one (MeshCore); absent when unknown.
  static const baseFrequencyKey = 'base_frequency_mhz';
  static const mobileFrequencyKey = 'mobile_frequency_mhz';

  /// The beacon Radio Setup last wrote to the base (kind name, interval in
  /// seconds, when it was switched on in ms since epoch).
  static const baseBeaconKindKey = 'base_beacon_kind';
  static const baseBeaconIntervalKey = 'base_beacon_interval_sec';
  static const baseBeaconSinceKey = 'base_beacon_since_ms';

  /// When Radio Setup last wrote the base (each write restarts it, which
  /// restarts Range Test's 8-hour clock), ms since epoch.
  static const baseRestartedKey = 'base_restarted_ms';

  /// The mobile node number whose public key Radio Setup put in the base's
  /// `security.admin_key` (guided test, design §5): that mobile may change
  /// the base over the mesh. Absent when no grant was made.
  static const remoteAdminNodeKey = 'base_remote_admin_node';

  /// Everything this class stores (kept by "Erase all app data": the roles
  /// describe how the radios are configured, not recorded data).
  static const prefKeys = {
    remoteAdminNodeKey,
    baseNodePrefKey,
    mobileNodeKey,
    baseDeviceKey,
    mobileDeviceKey,
    basePresetKey,
    mobilePresetKey,
    baseRegionKey,
    mobileRegionKey,
    baseSlotKey,
    mobileSlotKey,
    baseTxPowerKey,
    mobileTxPowerKey,
    baseFrequencyKey,
    mobileFrequencyKey,
    baseBeaconKindKey,
    baseBeaconIntervalKey,
    baseBeaconSinceKey,
    baseRestartedKey,
  };

  /// When Radio Setup last restarted the base, or null.
  DateTime? get baseRestartedAt {
    final ms = _prefs.getInt(baseRestartedKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  final SharedPreferences _prefs;

  RadioRoles(this._prefs);

  static String _nodeKey(RadioRole r) =>
      r == RadioRole.base ? baseNodePrefKey : mobileNodeKey;
  static String _deviceKey(RadioRole r) =>
      r == RadioRole.base ? baseDeviceKey : mobileDeviceKey;

  static String _presetKey(RadioRole r) =>
      r == RadioRole.base ? basePresetKey : mobilePresetKey;
  static String _regionKey(RadioRole r) =>
      r == RadioRole.base ? baseRegionKey : mobileRegionKey;
  static String _slotKey(RadioRole r) =>
      r == RadioRole.base ? baseSlotKey : mobileSlotKey;
  static String _txPowerKey(RadioRole r) =>
      r == RadioRole.base ? baseTxPowerKey : mobileTxPowerKey;
  static String _frequencyKey(RadioRole r) =>
      r == RadioRole.base ? baseFrequencyKey : mobileFrequencyKey;

  int? nodeOf(RadioRole role) => _prefs.getInt(_nodeKey(role));

  /// Preset id / region Radio Setup last wrote to the radio in [role]
  /// (the base can't be read back once the phone is on the mobile).
  String? presetOf(RadioRole role) => _prefs.getString(_presetKey(role));
  String? regionOf(RadioRole role) => _prefs.getString(_regionKey(role));

  /// Frequency slot (1-based) / transmit power (dBm) the radio in [role]
  /// was left on by Radio Setup; null when unknown.
  int? slotOf(RadioRole role) => _prefs.getInt(_slotKey(role));
  int? txPowerOf(RadioRole role) => _prefs.getInt(_txPowerKey(role));

  /// Centre frequency (MHz) the radio in [role] was left on by Radio
  /// Setup; null when unknown.
  double? frequencyOf(RadioRole role) => _prefs.getDouble(_frequencyKey(role));

  /// Remember what Radio Setup just wrote to the radio in [role]. A null
  /// slot, power or frequency forgets the old one (it is no longer known).
  Future<void> recordSetup(
    RadioRole role, {
    required String presetId,
    required String region,
    int? frequencySlot,
    int? txPowerDbm,
    double? frequencyMHz,
  }) async {
    await _prefs.setString(_presetKey(role), presetId);
    await _prefs.setString(_regionKey(role), region);
    Future<void> setOrRemove(String key, int? v) =>
        v == null ? _prefs.remove(key) : _prefs.setInt(key, v);
    await setOrRemove(_slotKey(role), frequencySlot);
    await setOrRemove(_txPowerKey(role), txPowerDbm);
    if (frequencyMHz == null) {
      await _prefs.remove(_frequencyKey(role));
    } else {
      await _prefs.setDouble(_frequencyKey(role), frequencyMHz);
    }
    notifyListeners();
  }

  /// The beacon the base was last set up with, or null when unknown (set up
  /// before beacon kinds, or never).
  static ({BeaconKind kind, int intervalSec, DateTime? since})? beaconIn(
      SharedPreferences prefs) {
    final kind = prefs.getString(baseBeaconKindKey);
    if (kind == null) return null;
    // The beacon starts over whenever Radio Setup writes the base (it
    // reboots), so the later of its start and the last restart is shown.
    var since = prefs.getInt(baseBeaconSinceKey);
    final restarted = prefs.getInt(baseRestartedKey);
    if (since != null && restarted != null && restarted > since) {
      since = restarted;
    }
    return (
      kind: BeaconKind.fromDb(kind),
      intervalSec: prefs.getInt(baseBeaconIntervalKey) ?? 0,
      since: since == null ? null : DateTime.fromMillisecondsSinceEpoch(since),
    );
  }

  ({BeaconKind kind, int intervalSec, DateTime? since})? get baseBeacon =>
      beaconIn(_prefs);

  /// The mobile node the base accepts remote changes from, or null when no
  /// grant was made, or it was made for a radio that is no longer the
  /// mobile (the key is per radio, so a new mobile needs a new grant).
  int? get remoteAdminMobileNode {
    final granted = _prefs.getInt(remoteAdminNodeKey);
    if (granted == null) return null;
    final mobile = nodeOf(RadioRole.mobile);
    return mobile != null && mobile != granted ? null : granted;
  }

  /// The mobile node whose key the base holds, as recorded, even when the
  /// mobile has changed since (what a revoke or a put-back must remove).
  int? get remoteAdminGrantedNode => _prefs.getInt(remoteAdminNodeKey);

  /// Radio Setup just put [mobileNode]'s key in the base's admin list.
  Future<void> recordRemoteAdmin(int mobileNode) async {
    await _prefs.setInt(remoteAdminNodeKey, mobileNode);
    notifyListeners();
  }

  /// Forget the grant (the base was set up again without one, or put back
  /// the way it was).
  Future<void> clearRemoteAdmin() async {
    if (!_prefs.containsKey(remoteAdminNodeKey)) return;
    await _prefs.remove(remoteAdminNodeKey);
    notifyListeners();
  }

  /// The base was just restarted (Range Test's 8-hour clock starts over).
  Future<void> recordBaseRestart() async {
    await _prefs.setInt(
        baseRestartedKey, DateTime.now().millisecondsSinceEpoch);
    notifyListeners();
  }

  static final StreamController<({BeaconKind kind, int intervalSec})>
      _beaconChanges = StreamController.broadcast(sync: true);

  /// Every beacon [recordBeacon] remembers, from any instance (Radio Setup
  /// makes its own). A recording MeshCore session listens, so a new trace
  /// beacon interval takes effect at once.
  static Stream<({BeaconKind kind, int intervalSec})> get beaconChanges =>
      _beaconChanges.stream;

  /// Remember the beacon just written to the base. Writing restarts the
  /// radio (and the base may be a different radio than last time), so the
  /// beacon's start date is now (field, 2026-10-27: a new base showed the
  /// old base's date).
  Future<void> recordBeacon(BeaconConfig beacon) async {
    final kind = beacon.activeKind;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(baseBeaconKindKey, kind.dbValue);
    await _prefs.setInt(baseBeaconIntervalKey,
        kind == BeaconKind.none ? 0 : beacon.intervalSec);
    await _prefs.setInt(baseRestartedKey, now);
    if (kind == BeaconKind.none) {
      await _prefs.remove(baseBeaconSinceKey);
    } else {
      await _prefs.setInt(baseBeaconSinceKey, now);
    }
    notifyListeners();
    _beaconChanges.add((
      kind: kind,
      intervalSec: kind == BeaconKind.none ? 0 : beacon.intervalSec,
    ));
  }

  /// Why the two radios can't hear each other, judging from what Radio
  /// Setup wrote to each, or null when they match (or aren't both set up).
  /// Different presets or regions mean different modulation / frequency:
  /// the radios decode nothing from each other, which looks exactly like
  /// being out of range.
  String? setupMismatch() {
    final bp = presetOf(RadioRole.base), mp = presetOf(RadioRole.mobile);
    final br = regionOf(RadioRole.base), mr = regionOf(RadioRole.mobile);
    if (bp != null &&
        mp != null &&
        MeshCoreModulations.ladderId(bp) != MeshCoreModulations.ladderId(mp)) {
      return 'preset: base $bp, mobile $mp';
    }
    // MeshCore has no regions (the stored one is a community title, empty
    // on the test frequency): the modulation and frequency decide below.
    final meshcore = (bp ?? mp ?? '').startsWith('MC_');
    if (!meshcore && br != null && mr != null && br != mr) {
      return 'region: base $br, mobile $mr';
    }
    // Same preset and region normally means the same slot (both hash the
    // shared channel name); a different one is a radio set by hand.
    final bs = slotOf(RadioRole.base), ms = slotOf(RadioRole.mobile);
    if (bs != null && ms != null && bs != ms) {
      return 'frequency slot: base $bs, mobile $ms';
    }
    // Exact frequencies (MeshCore), compared to the kHz.
    final bf = frequencyOf(RadioRole.base), mf = frequencyOf(RadioRole.mobile);
    if (bf != null && mf != null && (bf * 1000).round() != (mf * 1000).round()) {
      return 'frequency: base ${formatFrequencyMHz(bf)} MHz, '
          'mobile ${formatFrequencyMHz(mf)} MHz';
    }
    return null;
  }

  String? deviceOf(RadioRole role) => _prefs.getString(_deviceKey(role));

  RadioRole? roleOfNode(int? nodeNum) {
    if (nodeNum == null) return null;
    for (final r in RadioRole.values) {
      if (nodeOf(r) == nodeNum) return r;
    }
    return null;
  }

  RadioRole? roleOfDevice(String? deviceId) {
    if (deviceId == null || deviceId.isEmpty) return null;
    for (final r in RadioRole.values) {
      if (deviceOf(r) == deviceId) return r;
    }
    return null;
  }

  /// Role of a connected (or last connected) radio.
  RadioRole? roleOf(MeshRadio radio) =>
      roleOfNode(radio.myNodeId) ?? roleOfDevice(radio.descriptor?.id);

  /// Record that this radio has [role]. If it held the other role, that is
  /// cleared (a radio can't be both).
  Future<void> assign(RadioRole role, {int? nodeNum, String? deviceId}) async {
    final other = role.other;
    if (nodeNum != null) {
      if (nodeOf(other) == nodeNum) await _prefs.remove(_nodeKey(other));
      // A different radio becoming the base holds no grant yet.
      final before = nodeOf(role);
      if (role == RadioRole.base && before != null && before != nodeNum) {
        await _prefs.remove(remoteAdminNodeKey);
      }
      await _prefs.setInt(_nodeKey(role), nodeNum);
    }
    if (deviceId != null && deviceId.isNotEmpty) {
      if (deviceOf(other) == deviceId) await _prefs.remove(_deviceKey(other));
      await _prefs.setString(_deviceKey(role), deviceId);
    }
    notifyListeners();
  }

  /// Forget that [nodeNum] is the base or mobile (its settings were put
  /// back the way they were), so the connect list and mismatch banner stop
  /// naming it.
  Future<void> clearNode(int nodeNum) async {
    for (final r in RadioRole.values) {
      if (nodeOf(r) != nodeNum) continue;
      await _prefs.remove(_nodeKey(r));
      await _prefs.remove(_deviceKey(r));
      await _prefs.remove(_presetKey(r));
      await _prefs.remove(_regionKey(r));
      await _prefs.remove(_slotKey(r));
      await _prefs.remove(_txPowerKey(r));
      await _prefs.remove(_frequencyKey(r));
      if (r == RadioRole.base) {
        await _prefs.remove(baseBeaconKindKey);
        await _prefs.remove(baseBeaconIntervalKey);
        await _prefs.remove(baseBeaconSinceKey);
        await _prefs.remove(remoteAdminNodeKey);
      }
    }
    notifyListeners();
  }

  /// After connecting: if the radio's node number has a role, remember its
  /// Bluetooth id too (radios set up before ids were stored, or iOS handing
  /// out a new id).
  Future<void> learn(MeshRadio radio) async {
    final role = roleOfNode(radio.myNodeId);
    final id = radio.descriptor?.id;
    if (role == null || id == null || deviceOf(role) == id) return;
    await assign(role, deviceId: id);
  }
}
