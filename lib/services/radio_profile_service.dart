// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/radio/mesh_radio.dart';
import '../data/radio/meshcore/meshcore_radio.dart';
import '../data/radio/meshtastic/meshtastic_admin_keys.dart'
    show ReplaceAdminKeyPrompt, nodeIdHex;
import '../data/radio/meshtastic/meshtastic_presets.dart';
import '../data/radio/meshtastic/meshtastic_contacts.dart';
import '../data/radio/meshtastic/meshtastic_radio.dart';
import '../data/radio/switchable_radio.dart';
import 'radio_roles.dart';
import 'package:latlong2/latlong.dart';

import 'base_location.dart';
import 'radio_backup_service.dart';
import '../utils/user_errors.dart';

/// Puts the mobile and base radios on the same private test channel and
/// modem preset, and sets up the base beacon (base sends, mobile listens).
///
/// The test channel is the only enabled channel, so the radios never talk
/// on the public mesh. Its key is generated once and kept in
/// SharedPreferences so re-applying (e.g. a new preset) keeps both radios
/// on the same channel.
///
/// The admin sequence itself lives in `MeshtasticRadio.applyTestProfile`
/// (beginEdit → setChannel × 8 → setConfig(lora) → setConfig(device) →
/// setModuleConfig(telemetry, rangeTest) → commitEdit); the commit reboots the radio, which may drop BLE before
/// the ACK; that counts as success.
///
/// MeshCore radios (`MeshCoreRadio.applyTestProfile`, no reboot) take the
/// exact frequency and transmit power from the profile, and the base is
/// set to relay so it can answer trace pings. Their name, power, radio
/// parameters, repeat flag and channel table are backed up first
/// ([MeshCoreBackup]); traces need no key exchange, so that step is
/// skipped. Their base beacon is "pulled" ([BeaconKind.trace]): the
/// mobile's trace pings on a timer, so nothing is ever written to the base
/// for it; the setting lives in [RadioRoles] and the recording session.
class RadioProfileService {
  static const channelName = 'MeshTest'; // firmware limit: 11 chars
  static const prefKey = 'test_channel_psk';

  /// Modem presets offered for testing, fastest/shortest range last.
  static const testPresets = MeshtasticPresets.testPresets;

  final MeshRadio _mobile;
  final SharedPreferences _prefs;
  final RadioBackupService _backups;
  final MeshRadio Function(RadioProtocol) _radioFactory;
  final RadioRoles _roles;

  /// Radio names written when "Name the radios" is on: the long name shows
  /// in apps, the short name (max 4 characters) on the radio's screen.
  static const radioNames = {
    RadioRole.base: ('MeshTest Base', 'BASE'),
    RadioRole.mobile: ('MeshTest Mobile', 'MOBL'),
  };

  /// The phone's current fix (lat, lon, accuracy in m), if any. The phone
  /// sits next to the base during setup, so this becomes the base's
  /// remembered location.
  final (LatLng, double)? Function()? _currentFix;

  RadioProfileService(
    this._mobile,
    this._prefs, [
    RadioBackupService? backups,
    MeshRadio Function(RadioProtocol)? radioFactory,
    RadioRoles? roles,
    (LatLng, double)? Function()? currentFix,
  ])  : _backups = backups ?? RadioBackupService(),
        _radioFactory = radioFactory ?? _defaultFactory,
        _roles = roles ?? RadioRoles(_prefs),
        _currentFix = currentFix;

  static MeshRadio _defaultFactory(RadioProtocol protocol) =>
      protocol == RadioProtocol.meshcore ? MeshCoreRadio() : MeshtasticRadio();

  static const sameProtocolMessage =
      'The base and the mobile must speak the same protocol';

  /// The base beacon as the base's protocol runs it: on MeshCore always the
  /// pulled trace beacon (or off), whatever kind was asked for.
  static BeaconConfig _traceBeacon(BeaconConfig config) =>
      config.intervalSec > 0 && config.kind != BeaconKind.none
          ? BeaconConfig(
              intervalSec: config.intervalSec, kind: BeaconKind.trace)
          : const BeaconConfig.off();

  /// The connected radio is already on our private test channel (set up
  /// before, as either role).
  bool isOnTestChannel(MeshRadio radio) {
    final meshtastic = radioAs<MeshtasticRadio>(radio);
    if (meshtastic != null) return _onTestChannel(meshtastic);
    // MeshCore: our channel is in a slot and the radio parameters are off
    // every community preset (the test traffic rides the frequency, not
    // the channel; design §5).
    return radio.protocol == RadioProtocol.meshcore &&
        radio.isReady &&
        radio.primaryChannelName == channelName &&
        !radio.onPublicChannel;
  }

  /// [radio] is already on our test channel (nothing worth backing up).
  bool _onTestChannel(MeshtasticRadio radio) {
    final primary = radio.channels[0];
    return primary != null &&
        primary.settings.name == channelName &&
        _sameBytes(primary.settings.psk, channelKey);
  }

  /// Save [radio]'s current settings before Radio Setup replaces them.
  Future<void> _backUp(
    MeshRadio radio,
    void Function(String) onStep, {
    RadioRole? renameTo,
  }) async {
    if (!RadioBackupService.supports(radio)) {
      // A radio of a protocol without backups (tests' fakes): nothing to
      // save, and the step list says so rather than claiming a backup.
      onStep('No backup for this node');
      return;
    }
    // Already set up as base or mobile: the backup from its first setup
    // holds the original settings; re-applying or swapping roles adds
    // nothing worth keeping.
    if (isOnTestChannel(radio)) return;
    onStep('Backing up current settings…');
    final b = await _backups.save(radio, reason: backupReasonBeforeSetup);
    onStep('Saved backup (${b.summary}) — restore it from Node Setup');
  }

  /// 32-byte AES-256 key for the test channel, created on first use.
  List<int> get channelKey {
    final saved = _prefs.getString(prefKey);
    if (saved != null) return base64Decode(saved);
    final rng = Random.secure();
    final key = List<int>.generate(32, (_) => rng.nextInt(256));
    _prefs.setString(prefKey, base64Encode(key));
    return key;
  }

  /// Region to use: the mobile radio's, or US if it has none.
  String get regionName {
    final r = _mobile.regionName;
    return (r.isEmpty || r == 'UNSET') ? 'US' : r;
  }

  /// The mobile radio is on the test channel with [preset].
  bool mobileMatches(RadioPreset preset) {
    final mobile = radioAs<MeshtasticRadio>(_mobile);
    if (mobile == null) {
      return isOnTestChannel(_mobile) && _mobile.currentPreset?.id == preset.id;
    }
    final lora = mobile.loraConfig;
    final primary = mobile.channels[0];
    if (lora == null || primary == null) return false;
    return lora.usePreset &&
        mobile.currentPreset == preset &&
        primary.settings.name == channelName &&
        _sameBytes(primary.settings.psk, channelKey);
  }

  TestProfile _profile(
    RadioPreset preset, {
    required RadioRole role,
    required bool rename,
    BeaconConfig? beacon,
    double? frequencyMHz,
    int? txPowerDbm,
  }) =>
      TestProfile(
        channelName: channelName,
        // 32 bytes; MeshCore takes the first 16 (`channelKey16`).
        channelKey: Uint8List.fromList(channelKey),
        preset: preset,
        isBase: role == RadioRole.base,
        beacon: beacon,
        regionName: regionName,
        radioLongName: rename ? radioNames[role]!.$1 : null,
        radioShortName: rename ? radioNames[role]!.$2 : null,
        frequencyMHz: frequencyMHz,
        txPowerDbm: txPowerDbm,
        baseRelays: true,
      );

  /// Configure [radio] (already connected) for [role] and remember it.
  Future<void> _apply(
    MeshRadio radio,
    RadioRole role, {
    required RadioPreset preset,
    required int beaconSecs,
    required bool rename,
    required void Function(String step) onStep,
    double? frequencyMHz,
    int? txPowerDbm,
    bool allowRemoteChanges = true,
    ReplaceAdminKeyPrompt? confirmReplaceAdminKey,
  }) async {
    final nodeNum = radio.myNodeId;
    final deviceId = radio.descriptor?.id;
    final meshcore = radio.protocol == RadioProtocol.meshcore;
    await _backUp(radio, onStep, renameTo: rename ? role : null);
    if (meshcore) {
      onStep('Key exchange not needed: link checks work without keys');
    } else {
      await _introduce(radio, role, onStep);
    }
    // Remote changes (guided test, design §5): the base gets the mobile
    // radio's key as an admin key, when that key is known. A Meshtastic
    // radio takes it inside applyTestProfile's edit transaction (one
    // reboot); any other radio that supports it gets a separate grant.
    final remoteBase = role == RadioRole.base && !meshcore;
    final grant =
        remoteBase && allowRemoteChanges ? _mobileKeyFor(radio) : null;
    final meshtastic = radioAs<MeshtasticRadio>(radio);
    var granted = false;
    if (grant != null && meshtastic == null && radio.supportsRemoteAdmin) {
      onStep('Allowing the mobile node to change this base from a distance…');
      await radio.grantRemoteAdmin(grant.key);
      granted = true;
    }
    final askedBeacon = role == RadioRole.base
        ? (meshcore
            ? _traceBeacon(BeaconConfig(intervalSec: beaconSecs))
            : BeaconConfig(intervalSec: beaconSecs))
        : null;
    final profile = _profile(
      preset,
      role: role,
      rename: rename,
      beacon: askedBeacon,
      frequencyMHz: frequencyMHz,
      txPowerDbm: txPowerDbm,
    );
    // Read before writing: the radio reboots and reconnects afterwards.
    final settings = radio.settingsAfter(profile);
    var beacon = meshtastic != null
        ? await meshtastic.applyTestProfile(
            profile,
            onStep: onStep,
            remoteAdminKey: grant?.key,
            onRemoteAdmin: (ok) => granted = ok,
            confirmReplaceAdminKey: confirmReplaceAdminKey,
          )
        : await radio.applyTestProfile(profile, onStep: onStep);
    // A MeshCore base runs no beacon of its own: whatever it returns, the
    // trace schedule is ours.
    if (meshcore && role == RadioRole.base) beacon = askedBeacon;
    if (role == RadioRole.base && beacon != null) {
      await _roles.recordBeacon(beacon);
      onStep(beaconSummary(beacon));
    }
    // The map picker lists the base first, clearing the mobile's node list
    // keeps it, and the connect list tags both.
    await _roles.assign(role, nodeNum: nodeNum, deviceId: deviceId);
    if (remoteBase) {
      if (granted && grant != null) {
        await _roles.recordRemoteAdmin(grant.node);
        onStep('Remote changes allowed for the mobile node '
            '(${nodeIdHex(grant.node)})');
      } else {
        await _roles.clearRemoteAdmin();
        onStep(!allowRemoteChanges
            ? 'Remote changes: not allowed'
            : grant == null
                ? 'Remote changes: the mobile node\'s key isn\'t known yet. '
                    'A guided test can enable them at the base later.'
                : 'Remote changes: not set up on this node');
      }
    }
    await _roles.recordSetup(role,
        presetId: preset.id,
        // MeshCore has no regions: the radio's own label for its settings
        // (a matching community preset's title, else empty).
        region: meshcore ? (settings?.region ?? radio.regionName) : regionName,
        frequencySlot: settings?.frequencySlot,
        txPowerDbm: settings?.txPowerDbm ?? txPowerDbm,
        frequencyMHz: meshcore
            ? (settings?.frequencyMHz ?? frequencyMHz)
            : settings?.frequencyMHz);
    // Most bases have no GPS; the phone is beside it right now.
    final fix = role == RadioRole.base ? _currentFix?.call() : null;
    if (fix != null && nodeNum != null) {
      final saved = await BaseLocationStore(_prefs)
          .record(nodeNum, fix.$1, accuracyM: fix.$2);
      if (saved) {
        onStep('Base location saved from the phone\'s GPS '
            '(±${fix.$2.round()} m)');
      }
    }
  }

  /// Save [radio]'s own key and give it the other radio's (base ↔ mobile),
  /// so direct-message pings work even if one has never heard the other.
  Future<void> _introduce(
    MeshRadio target,
    RadioRole role,
    void Function(String) onStep,
  ) async {
    final radio = radioAs<MeshtasticRadio>(target);
    if (radio == null) return;
    final mobile = radioAs<MeshtasticRadio>(_mobile);
    final contacts = MeshtasticContacts(_prefs);
    for (final r in {radio, if (mobile != null) mobile}) {
      final num = r.myNodeId;
      final me = num == null ? null : r.nodeInfos[num];
      if (r.isReady && me != null && me.hasUser()) {
        // Straight from the radio over Bluetooth: may replace a saved key.
        await contacts.save(num!, me.user, replaceKey: true);
      }
    }
    final other = {
      _roles.nodeOf(role.other),
      if (!identical(target, _mobile) && _mobile.isReady) _mobile.myNodeId,
    }..removeWhere((n) => n == null || n == radio.myNodeId);
    for (final num in other) {
      final user = contacts.get(num!);
      if (user == null) continue;
      onStep(
          'Giving it the ${role.other.label.toLowerCase()} node\'s public key…');
      try {
        await radio.addContact(num, user);
      } catch (e) {
        // Older firmware without add_contact: the radios swap keys over
        // the air before the first ping instead.
        onStep('(Skipped: ${userMessage(e)})');
      }
    }
  }

  /// The mobile radio's node number and public key, for the base's admin
  /// list: the connected radio when [base] is a second connection (mobile
  /// flow), else the remembered mobile (base flow, set up earlier). Null
  /// when the key isn't known yet (a brand-new pair set up base first).
  ({int node, List<int> key})? _mobileKeyFor(MeshRadio base) {
    final secondLink = !identical(base, _mobile) &&
        _mobile.isReady &&
        _mobile.protocol == RadioProtocol.meshtastic;
    final node =
        secondLink ? _mobile.myNodeId : _roles.nodeOf(RadioRole.mobile);
    if (node == null || node == base.myNodeId) return null;
    final key = _publicKeyOf(node, [_mobile, base]);
    return key == null ? null : (node: node, key: key);
  }

  /// [node]'s 32-byte public key: the copy saved on the phone, else what
  /// one of [radios] has in its node list.
  List<int>? _publicKeyOf(int node, Iterable<MeshRadio> radios) {
    final saved = MeshtasticContacts(_prefs).get(node)?.publicKey;
    if (saved != null && saved.length == 32) return saved;
    for (final r in radios) {
      final info = radioAs<MeshtasticRadio>(r)?.nodeInfos[node];
      if (info != null && info.hasUser() && info.user.publicKey.length == 32) {
        return info.user.publicKey;
      }
    }
    return null;
  }

  /// Give the base [base] (over a second, temporary Bluetooth connection;
  /// the phone stays on the mobile) the connected mobile radio's key as an
  /// admin key, so guided tests can change the base from a distance, and
  /// remember it. The base restarts. For setups made before the grant
  /// existed, or made base first. MeshCore: nothing to do (no remote
  /// administration), never throws.
  ///
  /// The radio reached must be the remembered base (when one is
  /// remembered); a full admin list is only changed when
  /// [confirmReplaceAdminKey] agrees.
  Future<void> grantRemoteAdminAtBase(
    RadioDescriptor base, {
    required void Function(String step) onStep,
    ReplaceAdminKeyPrompt? confirmReplaceAdminKey,
  }) async {
    if (base.protocol == RadioProtocol.meshcore ||
        _mobile.protocol == RadioProtocol.meshcore) {
      onStep('MeshCore: the base is changed over Bluetooth, nothing to allow');
      return;
    }
    if (!_mobile.isReady) {
      throw StateError('Connect to the mobile node first: the base needs '
          'its key');
    }
    final mobileNode = _mobile.myNodeId;
    final key = mobileNode == null ? null : _publicKeyOf(mobileNode, [_mobile]);
    if (mobileNode == null || key == null) {
      throw StateError('The mobile node\'s public key isn\'t known yet; '
          'connect to it and try again');
    }
    final radio = _radioFactory(RadioProtocol.meshtastic);
    radioAs<MeshtasticRadio>(radio)?.contacts = MeshtasticContacts(_prefs);
    try {
      onStep('Connecting to the base node…');
      await radio.connect(base);
      if (radio.myNodeId == mobileNode) {
        throw StateError('That is the mobile node itself, not the base');
      }
      verifyIsBase(radio);
      if (!radio.supportsRemoteAdmin) {
        onStep('This node can\'t be changed from a distance');
        return;
      }
      await _roles.learn(radio);
      final meshtastic = radioAs<MeshtasticRadio>(radio);
      if (meshtastic != null) {
        await meshtastic.grantRemoteAdmin(key,
            onStep: onStep, confirmReplace: confirmReplaceAdminKey);
      } else {
        await radio.grantRemoteAdmin(key);
      }
      await _roles.recordRemoteAdmin(mobileNode);
      onStep('Remote changes allowed for the mobile node '
          '(${nodeIdHex(mobileNode)}); the base restarts');
    } finally {
      await radio.dispose();
    }
  }

  /// Throw unless [radio] (just connected by a remembered Bluetooth id) is
  /// the base Radio Setup remembers by node number. iOS ids are stable, but
  /// a factory reset or a new key (on firmware 2.8 the node number follows
  /// the key) or a re-flash makes it a different radio, which must not be
  /// set up as the base by accident. No base remembered: nothing to check.
  void verifyIsBase(MeshRadio radio, {int? expected}) {
    final want = expected ?? _roles.nodeOf(RadioRole.base);
    final got = radio.myNodeId;
    if (want == null || got == want) return;
    throw StateError('This is not the base node: it answers as '
        '${got == null ? 'an unknown node' : nodeIdHex(got)}, the base is '
        '${nodeIdHex(want)}. It may have been reset or re-flashed. Nothing '
        'was changed; run Node Setup to set it up as the base again.');
  }

  /// The mobile node whose key the base holds as an admin key, as recorded
  /// (also when the mobile has changed since).
  int? get remoteAdminGrantedNode => _roles.remoteAdminGrantedNode;

  /// Take the mobile radio's key back out of the base's admin list, so it
  /// can no longer change the base from a distance, and forget the grant.
  /// Uses the connected radio when that is the base, else a second
  /// Bluetooth connection to the remembered base (it must be in range).
  /// The base restarts. Meshtastic only (MeshCore has no remote admin).
  Future<void> revokeRemoteAdminAtBase({
    required void Function(String step) onStep,
  }) async {
    final mobileNode = _roles.remoteAdminGrantedNode;
    if (mobileNode == null) {
      onStep('The base node holds no key from this app');
      return;
    }
    final key = _publicKeyOf(mobileNode, [_mobile]);
    if (key == null) {
      throw StateError('The mobile node\'s public key isn\'t known on this '
          'phone, so it can\'t be picked out of the base\'s admin list. '
          'Restore the base\'s original settings instead.');
    }
    final connected = radioAs<MeshtasticRadio>(_mobile);
    if (connected != null &&
        _mobile.isReady &&
        _roles.roleOf(_mobile) == RadioRole.base) {
      verifyIsBase(_mobile);
      await connected.revokeRemoteAdmin(key, onStep: onStep);
      await _roles.clearRemoteAdmin();
      onStep('The mobile node can no longer change this base');
      return;
    }
    if (_mobile.protocol == RadioProtocol.meshcore) {
      await _roles.clearRemoteAdmin();
      return;
    }
    final id = _roles.deviceOf(RadioRole.base);
    if (id == null) {
      throw StateError('The base node is not known yet. Connect to it '
          'and try again.');
    }
    final radio = _radioFactory(RadioProtocol.meshtastic);
    radioAs<MeshtasticRadio>(radio)?.contacts = MeshtasticContacts(_prefs);
    try {
      onStep('Connecting to the base node…');
      await radio.connect(RadioDescriptor(id: id, name: 'Base node'));
      verifyIsBase(radio);
      final meshtastic = radioAs<MeshtasticRadio>(radio);
      if (meshtastic == null) {
        throw StateError('Removing admin access needs a Meshtastic base');
      }
      await meshtastic.revokeRemoteAdmin(key, onStep: onStep);
      await _roles.clearRemoteAdmin();
      onStep('The mobile node can no longer change the base; the base '
          'restarts');
    } finally {
      await radio.dispose();
    }
  }

  /// "Base beacon: telemetry every 30 s" for the settings summary. Never
  /// names the firmware module behind a test signal.
  static String beaconSummary(BeaconConfig beacon) {
    if (!beacon.enabled) return 'Base beacon: off';
    final every = 'every ${beacon.intervalSec} s';
    return switch (beacon.kind) {
      BeaconKind.telemetry => 'Base beacon: telemetry $every',
      BeaconKind.rangeTest => 'Base beacon: test signal $every',
      BeaconKind.trace => 'Link check from the mobile $every',
      _ => 'Base beacon: off',
    };
  }

  /// Change the base's beacon without redoing the whole setup. Uses the
  /// connected radio when that is the base, else a second Bluetooth
  /// connection to the base (it must be in range of the phone). Remembers
  /// what was written.
  ///
  /// MeshCore: nothing is written to the base (its beacon is the mobile's
  /// trace pings); the interval is remembered and a recording session
  /// picks it up at once ([RadioRoles.beaconChanges]).
  Future<BeaconConfig> setBaseBeacon(BeaconConfig config) async {
    if (_mobile.protocol == RadioProtocol.meshcore) {
      final applied = _traceBeacon(config);
      await _roles.recordBeacon(applied);
      return applied;
    }
    if (_mobile.isReady && _roles.roleOf(_mobile) == RadioRole.base) {
      final applied = await _mobile.setBeacon(config);
      await _roles.recordBeacon(applied);
      return applied;
    }
    final id = _roles.deviceOf(RadioRole.base);
    if (id == null) {
      throw StateError('The base node is not known yet. Set it up in '
          'Node Setup first.');
    }
    final radio = _radioFactory(RadioProtocol.meshtastic);
    radioAs<MeshtasticRadio>(radio)?.contacts = MeshtasticContacts(_prefs);
    try {
      await radio.connect(RadioDescriptor(id: id, name: 'Base node'));
      verifyIsBase(radio);
      final applied = await radio.setBeacon(config);
      await _roles.recordBeacon(applied);
      return applied;
    } finally {
      await radio.dispose();
    }
  }

  /// Switch the base to the telemetry beacon (for a base whose test signal
  /// is missing), keeping the interval it had. On MeshCore (no telemetry
  /// beacon) this turns the trace beacon on at that interval instead.
  Future<BeaconConfig> switchBaseToTelemetry() {
    final before = _roles.baseBeacon;
    final secs = (before?.intervalSec ?? 0) > 0 ? before!.intervalSec : 30;
    return setBaseBeacon(BeaconConfig(
        intervalSec: secs,
        kind: _mobile.protocol == RadioProtocol.meshcore
            ? BeaconKind.trace
            : BeaconKind.telemetry));
  }

  /// Turn the base's beacon off (at the end of testing, so it stops using
  /// airtime and battery).
  Future<BeaconConfig> stopBaseBeacon() =>
      setBaseBeacon(const BeaconConfig.off());

  /// Restart the base: [radio] must be the phone's connection to the base
  /// itself. A restart re-arms a Range Test beacon's 8-hour clock, so the
  /// base-silence warning resets.
  Future<void> restartBase(MeshRadio radio) async {
    if (radio is! MeshtasticRadio) {
      throw StateError('Restart needs a Meshtastic node');
    }
    if (_roles.roleOf(radio) != RadioRole.base) {
      throw StateError('Connect to the base node to restart it');
    }
    await radio.reboot();
    await _roles.recordBaseRestart();
  }

  /// Configure the base radio over a second, temporary connection; the
  /// phone stays connected to the mobile. [frequencyMHz] / [txPowerDbm]
  /// go into the [TestProfile] (MeshCore needs the exact frequency; null
  /// keeps the protocol's or radio's own). Refuses a base of another
  /// protocol than the connected mobile's. [allowRemoteChanges] gives the
  /// base the mobile's key as an admin key (Meshtastic; see
  /// [grantRemoteAdminAtBase]; a full admin list is only changed when
  /// [confirmReplaceAdminKey] agrees). [expectNodeNum]: the radio must
  /// answer as this node (a connection by a remembered Bluetooth id, such
  /// as a guided test's base change), else nothing is written.
  Future<void> applyToBase(
    RadioDescriptor device, {
    required RadioPreset preset,
    required int beaconSecs,
    bool rename = false,
    required void Function(String step) onStep,
    double? frequencyMHz,
    int? txPowerDbm,
    bool allowRemoteChanges = true,
    ReplaceAdminKeyPrompt? confirmReplaceAdminKey,
    int? expectNodeNum,
  }) async {
    if (_mobile.isReady && device.protocol != _mobile.protocol) {
      throw StateError(sameProtocolMessage);
    }
    final radio = _radioFactory(device.protocol);
    radioAs<MeshtasticRadio>(radio)?.contacts = MeshtasticContacts(_prefs);
    try {
      onStep('Connecting to the base node…');
      await radio.connect(device);
      if (radio.protocol != device.protocol) {
        throw StateError(sameProtocolMessage);
      }
      if (expectNodeNum != null) verifyIsBase(radio, expected: expectNodeNum);
      await _apply(radio, RadioRole.base,
          preset: preset,
          beaconSecs: beaconSecs,
          rename: rename,
          onStep: onStep,
          frequencyMHz: frequencyMHz,
          txPowerDbm: txPowerDbm,
          allowRemoteChanges: allowRemoteChanges,
          confirmReplaceAdminKey: confirmReplaceAdminKey);
    } finally {
      await radio.dispose();
    }
  }

  /// Configure the radio the phone is connected to, as [role]. It reboots
  /// and the app reconnects to it automatically. [allowRemoteChanges]
  /// matters for a base only (see [applyToBase]).
  Future<void> applyToConnected(
    RadioRole role, {
    required RadioPreset preset,
    int beaconSecs = 0,
    bool rename = false,
    required void Function(String step) onStep,
    double? frequencyMHz,
    int? txPowerDbm,
    bool allowRemoteChanges = true,
    ReplaceAdminKeyPrompt? confirmReplaceAdminKey,
  }) async {
    if (!_mobile.isReady) throw StateError('Connect to your node first');
    await _apply(_mobile, role,
        preset: preset,
        beaconSecs: beaconSecs,
        rename: rename,
        onStep: onStep,
        frequencyMHz: frequencyMHz,
        txPowerDbm: txPowerDbm,
        allowRemoteChanges: allowRemoteChanges,
        confirmReplaceAdminKey: confirmReplaceAdminKey);
  }

  /// Configure the connected (mobile) radio.
  Future<void> applyToMobile({
    required RadioPreset preset,
    bool rename = false,
    required void Function(String step) onStep,
    double? frequencyMHz,
    int? txPowerDbm,
  }) =>
      applyToConnected(RadioRole.mobile,
          preset: preset,
          rename: rename,
          onStep: onStep,
          frequencyMHz: frequencyMHz,
          txPowerDbm: txPowerDbm);

  /// Switch the phone's connection to [device] and configure it as the
  /// mobile (used after setting up the connected radio as the base, so
  /// [device] must speak the same protocol as the radio connected now).
  Future<void> switchToAndApplyMobile(
    RadioDescriptor device, {
    required RadioPreset preset,
    bool rename = false,
    required void Function(String step) onStep,
    double? frequencyMHz,
    int? txPowerDbm,
  }) async {
    if (_mobile.isReady && device.protocol != _mobile.protocol) {
      throw StateError(sameProtocolMessage);
    }
    onStep(
        'Connecting to ${device.name.isEmpty ? 'the mobile node' : device.name}…');
    await _mobile.connect(device);
    await applyToMobile(
        preset: preset,
        rename: rename,
        onStep: onStep,
        frequencyMHz: frequencyMHz,
        txPowerDbm: txPowerDbm);
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
