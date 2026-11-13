// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../data/radio/ble/radio_scanner.dart';
import '../../data/radio/ble/radio_services.dart';
import '../../data/radio/mesh_radio.dart';
import '../../data/radio/meshcore/meshcore_presets.dart';
import '../../data/radio/meshtastic/meshtastic_presets.dart';
import '../../data/radio/meshtastic/meshtastic_radio.dart';
import '../../data/radio/switchable_radio.dart';
import '../../data/radio/meshtastic/meshtastic_regions.dart';
import '../../providers.dart';
import '../../services/airtime_model.dart';
import '../../services/pro_entitlement.dart';
import '../../services/diag_log.dart';
import '../../services/radio_profile_service.dart';
import '../../services/gps_service.dart';
import '../../services/radio_roles.dart';
import '../../utils/constants.dart';
import '../../utils/user_errors.dart';
import '../protocol_text.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_banner.dart';
import '../widgets/airtime_explainer.dart';
import '../widgets/info_button.dart';
import '../widgets/radio_backups_section.dart';
import '../widgets/protocol_tag.dart';
import '../widgets/radio_firmware_line.dart';
import '../widgets/region_dialog.dart';
import '../widgets/role_chip.dart';
import '../widgets/setup_mismatch_banner.dart';
import 'radio_backups_screen.dart';
import '../widgets/pro_tag.dart';
import 'remote_base_change_screen.dart';
import '../layout/window_class.dart';

/// Puts the mobile and base radios on the private test channel with a
/// chosen modem preset (Meshtastic), or on a private test frequency with a
/// chosen modulation and power (MeshCore).
/// Title and subtitle of the remote-changes switch, the same in both
/// flows: it says plainly what the grant gives away.
const remoteAdminSwitchTitle =
    'Let the mobile node change this base from a distance';
const remoteAdminSwitchSubtitle = 'This gives the mobile node admin access '
    'to the base (settings and channel keys) until you restore the base. '
    'Needed for guided tests that change range settings.';

class RadioSetupScreen extends ConsumerStatefulWidget {
  /// How long after an apply the page waits for the radio to come back
  /// before offering to connect one by hand.
  static const settleFor = Duration(seconds: 60);

  /// Preselect what the connected radio is (e.g. from "Change role").
  final RadioRole? initialRole;

  const RadioSetupScreen({super.key, this.initialRole});

  @override
  ConsumerState<RadioSetupScreen> createState() => _RadioSetupScreenState();
}

class _RadioSetupScreenState extends ConsumerState<RadioSetupScreen> {
  static const _normalIntervals = [0, 30, 60, 120, 300];

  /// "Faster than recommended" (Settings) adds shorter beacon intervals.
  /// Pro only (`ProFeature.fasterIntervals`).
  bool get _faster =>
      AppConstants.fasterThanRecommended(ref.read(sharedPreferencesProvider)) &&
      ref.read(proEntitlementProvider).canCreate(ProFeature.fasterIntervals);

  List<int> get _intervals =>
      _faster ? const [0, 5, 10, 15, 30, 60, 120, 300] : _normalIntervals;

  RadioPreset? _preset;
  int _beaconSecs = 30;

  /// The protocol [_preset] was picked for; a radio of the other protocol
  /// picks again.
  RadioProtocol? _presetProtocol;

  // ─── MeshCore: range setting (modulation), test frequency and power ───
  MeshCoreModulation? _mcMod;
  final _freqController = TextEditingController();
  final _powerController = TextEditingController();

  /// The test frequency field is open (the band's relay frequency is the
  /// one right answer; this is for experiments off it).
  bool _freqOther = false;

  /// What the user says the connected radio is; null follows the stored
  /// role (mobile if unknown).
  RadioRole? _roleChoice;
  bool _rename = true;

  /// Both flows (Meshtastic): put the mobile radio's key in the base's
  /// admin list, so guided tests can change the base from a distance.
  bool _allowRemote = true;

  final _scroll = ScrollController();

  /// Open the radio backups (their own screen since the new-user
  /// walkthrough of 2026-11-08; also Settings → Radios → Radio backups).
  Future<void> _showBackups() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const RadioBackupsScreen()));
    _putBackKey.currentState?.reload(); // a backup may have been restored
  }

  /// Read once: `ref` can't be used in [dispose].
  late final RadioScanner _scanner;

  @override
  void initState() {
    super.initState();
    _roleChoice = widget.initialRole;
    _scanner = ref.read(radioScannerProvider);
  }

  /// The connected radio was already set up in [role] (on our channel).
  bool _alreadySetUp(MeshRadio radio, RadioRole role) =>
      radio.isReady &&
      _service.isOnTestChannel(radio) &&
      ref.read(radioRolesProvider).roleOf(radio) == role;

  RadioRole _connectedRole(MeshRadio radio) =>
      _roleChoice ??
      ref.read(radioRolesProvider).roleOf(radio) ??
      RadioRole.mobile;

  List<RadioDescriptor> _results = [];
  StreamSubscription<List<RadioDescriptor>>? _scanSub;
  bool _scanning = false;
  bool _working = false;
  final List<String> _log = [];
  final _putBackKey = GlobalKey<RestoreOriginalButtonState>();
  String? _error;

  /// The raw error behind [_error] (type, message, the step it failed in,
  /// the top of the stack), behind a Details toggle and in the diag log.
  String? _errorDetail;
  bool _showErrorDetail = false;

  /// The apply failed after it had started changing settings.
  bool _failedMidway = false;
  String? _success;

  /// When settings were last written to the radio. A Meshtastic radio
  /// reboots after the commit and the link goes disconnected →
  /// reconnecting → configuring → ready; for [RadioSetupScreen.settleFor] after an apply
  /// the page holds one calm "restarting" line instead of swapping between
  /// the connect branch (with its Connect button) and the form with each
  /// state (first run 2026-11-07: "the screen flickers"). The base flow
  /// already keeps its form up through the reboot (`baseStep2`).
  DateTime? _appliedAt;
  Timer? _settleTimer;

  /// The link has been down since the apply (the hold ends when it is
  /// back, not on the rebuild right after the apply, when it is still up).
  bool _linkDropped = false;

  void _markApplied() {
    _appliedAt = DateTime.now();
    _linkDropped = false;
    _settleTimer?.cancel();
    // Rebuild once the window closes so the connect branch comes back.
    _settleTimer = Timer(RadioSetupScreen.settleFor, () {
      if (mounted) setState(() => _appliedAt = null);
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _scroll.dispose();
    _freqController.dispose();
    _powerController.dispose();
    _scanSub?.cancel();
    _scanner.stopScan();
    super.dispose();
  }

  /// One line on what the base beacon will be, from the base's firmware
  /// when the connected radio is the base, else what it was last set to.
  String _beaconSummary(RadioRoles roles, MeshRadio radio, RadioRole role) {
    if (_beaconSecs == 0) {
      return radio.protocol == RadioProtocol.meshcore
          ? 'Link check: off'
          : 'Base beacon: off';
    }
    if (radio.protocol == RadioProtocol.meshcore) {
      return RadioProfileService.beaconSummary(BeaconConfig(
              intervalSec: _beaconSecs,
              kind: selectBeaconKind(radio.capabilities,
                  protocol: RadioProtocol.meshcore))
          .normalized());
    }
    BeaconKind? kind;
    if (role == RadioRole.base && radio.isReady) {
      kind = selectBeaconKind(radio.capabilities);
    } else if (roles.baseBeacon case final saved?
        when saved.kind != BeaconKind.none) {
      kind = saved.kind;
    }
    if (kind == null) {
      return 'Beacon type: picked from the base\'s firmware when you apply.';
    }
    return RadioProfileService.beaconSummary(
        BeaconConfig(intervalSec: _beaconSecs, kind: kind).normalized());
  }

  /// Off, or an interval the preset's airtime budget allows.
  bool _beaconAllowed(int secs, RadioPreset? p) =>
      secs == 0 ||
      p == null ||
      secs >=
          AirtimeModel.minIntervalSecFor(p,
              override: _faster,
              protocol: _meshCore
                  ? RadioProtocol.meshcore
                  : RadioProtocol.meshtastic);

  /// Keeps the beacon choice if still valid, else bumps it to the smallest
  /// valid option.
  void _onPresetChanged(RadioPreset? v) {
    setState(() {
      _preset = v;
      if (!_beaconAllowed(_beaconSecs, v)) {
        _beaconSecs = _intervals.firstWhere(
          (s) => s != 0 && _beaconAllowed(s, v),
          orElse: () => _intervals.last,
        );
      }
    });
  }

  // ─── MeshCore ────────────────────────────────────────

  bool get _meshCore =>
      ref.read(meshRadioProvider).protocol == RadioProtocol.meshcore;

  /// The radio's own frequency, MHz (0 when unknown).
  static double _radioMHz(MeshRadio radio) =>
      radio.radioSettings?.frequencyMHz ?? radio.regionFrequencyMHz;

  /// The band the radio is built for (915 until known).
  static MeshCoreBand _band(MeshRadio radio) {
    final mhz = _radioMHz(radio);
    return MeshCoreBand.of(mhz > 0 ? mhz : 915);
  }

  /// The usual community modulation of each band, when the radio's own
  /// settings say nothing better.
  static MeshCoreModulation _bandDefault(MeshCoreBand band) =>
      MeshCoreModulations.ofPreset(switch (band) {
        MeshCoreBand.mhz433 => MeshCorePresets.eu433Narrow,
        MeshCoreBand.mhz868 => MeshCorePresets.euUkNarrow,
        MeshCoreBand.mhz915 => MeshCorePresets.usa,
      }) ??
      MeshCoreModulations.fast;

  /// The ladder entry the radio is on now, when it is one.
  static MeshCoreModulation? _radioMod(MeshRadio radio) {
    final current = radio.currentPreset;
    if (current == null) return null;
    return MeshCoreModulations.byId(current.id) ??
        MeshCoreModulations.of(
            bandwidthHz: (current.bwKHz * 1000).round(),
            spreadingFactor: current.sf,
            codingRate: current.cr);
  }

  /// First pick for a MeshCore radio: the modulation it is on (its
  /// community mesh's, or the one it was set up with), else the band's
  /// usual one.
  static MeshCoreModulation _defaultMcMod(MeshRadio radio) =>
      _radioMod(radio) ?? _bandDefault(_band(radio));

  /// Prefill the MeshCore controls from the connected radio.
  void _initMeshCore(MeshRadio radio) {
    _mcMod = _defaultMcMod(radio);
    _freqOther = false;
    _freqController.text = formatFrequencyMHz(_band(radio).clientRepeatMHz);
    _powerController.text = radio.radioSettings?.txPowerDbm?.toString() ?? '';
    _preset = _mcMod!.radioPreset;
    if (!_beaconAllowed(_beaconSecs, _preset)) {
      _beaconSecs = _intervals.firstWhere(
        (s) => s != 0 && _beaconAllowed(s, _preset),
        orElse: () => _intervals.last,
      );
    }
  }

  void _onMcModChanged(MeshCoreModulation? m) {
    if (m == null) return;
    _mcMod = m;
    _onPresetChanged(m.radioPreset);
  }

  /// Nudge the TX power field by [delta] dBm (an empty field, which keeps
  /// the radio's own, starts from that or 22).
  void _nudgePower(MeshRadio radio, int delta) {
    final current = int.tryParse(_powerController.text.trim()) ??
        radio.radioSettings?.txPowerDbm ??
        22;
    setState(() {
      _powerController.text = (current + delta).clamp(0, 22).toString();
    });
  }

  /// Test frequency to write (MeshCore only; null on Meshtastic, where the
  /// region and preset decide).
  double? get _mcFrequency =>
      _meshCore ? double.tryParse(_freqController.text.trim()) : null;

  /// TX power to write (MeshCore only); null keeps the radio's own.
  int? get _mcTxPower {
    if (!_meshCore) return null;
    return int.tryParse(_powerController.text.trim())?.clamp(0, 22);
  }

  String? get _freqError {
    final f = double.tryParse(_freqController.text.trim());
    if (f == null || f < 150 || f > 960) {
      return 'Enter a frequency in MHz, e.g. 918.000';
    }
    return null;
  }

  String? get _powerError {
    final text = _powerController.text.trim();
    if (text.isEmpty) return null;
    final v = int.tryParse(text);
    if (v == null || v < 0 || v > 22) return '0 to 22 dBm';
    return null;
  }

  /// A MeshCore field holds something that can't be applied.
  bool get _mcInvalid =>
      _meshCore && (_freqError != null || _powerError != null);

  RadioProfileService get _service => RadioProfileService(
        ref.read(meshRadioProvider),
        ref.read(sharedPreferencesProvider),
        null,
        ref.read(radioFactoryProvider),
        ref.read(radioRolesProvider),
        () {
          // The phone is beside the base while setting it up.
          final p = ref.read(gpsServiceProvider).lastPosition;
          return p == null
              ? null
              : (LatLng(p.latitude, p.longitude), p.accuracy);
        },
      );

  Future<void> _scan() async {
    final connectedId = ref.read(meshRadioProvider).descriptor?.id;
    setState(() {
      _results = [];
      _scanning = true;
      _error = null;
    });
    _scanSub?.cancel();
    final done = Completer<void>();
    _scanSub = ref
        .read(radioScannerProvider)
        .scan(
          serviceUuids: RadioServices.all,
          timeout: const Duration(seconds: 10),
        )
        .listen(
      (found) {
        if (!mounted) return;
        setState(() {
          _results = [
            for (final r in found)
              if (r.id != connectedId) r,
          ];
        });
      },
      onError: (Object e) {
        if (mounted) {
          setState(() => _error = userMessage(e, doing: 'looking for nodes'));
        }
      },
      onDone: () => done.complete(),
    );
    await done.future;
    if (mounted) setState(() => _scanning = false);
  }

  /// [change]: the radio is already set up in this role, so this only
  /// updates its settings (no channel replacement, no new backup).
  /// A line for the confirm when the radio about to become [role] is the
  /// one recorded as the other role (first run 2026-11-06: the mobile was
  /// made the base and the real base silently lost its role): the swap is
  /// allowed, but named. Null when the radio holds no role or this one.
  String? _swapWarning(RadioRole role, {int? nodeNum, String? deviceId}) {
    final roles = ref.read(radioRolesProvider);
    final other = role.other;
    final holds = roles.roleOfNode(nodeNum) ?? roles.roleOfDevice(deviceId);
    if (holds != other) return null;
    final current = roles.nodeOf(role);
    final loses = current == null || current == nodeNum
        ? ''
        : ' ${_nodeLabel(current)} stops being the ${role.label.toLowerCase()}.';
    return 'This node is your ${other.label.toLowerCase()}. Making it the '
        '${role.label.toLowerCase()} leaves you with no '
        '${other.label.toLowerCase()} until you set up another node as '
        'one.$loses';
  }

  String _nodeLabel(int nodeNum) {
    final name = ref.read(meshRadioProvider).nodes[nodeNum]?.longName ?? '';
    return name.isEmpty ? shortNodeId(nodeNum) : name;
  }

  Future<bool> _confirm(String title,
      {RadioRole? role, bool change = false, String? swap}) async {
    final meshCore = _meshCore;
    final name = role == null || !_rename
        ? ''
        : meshCore
            ? ' It is renamed "${RadioProfileService.radioNames[role]!.$1}".'
            : ' It is renamed "${RadioProfileService.radioNames[role]!.$1}" '
                '(${RadioProfileService.radioNames[role]!.$2} on its screen).';
    final grant = !meshCore && role == RadioRole.base && _allowRemote
        ? ' The mobile node\'s key goes into the base\'s admin list, which '
            'gives the mobile node admin access to the base until you '
            'restore the base.'
        : '';
    // docs/design/ipad step 5: the mobile's GPS can stand in for a device
    // without one (a Wi-Fi iPad).
    final gps = role == RadioRole.mobile
        ? ' If the node has GPS, it is switched on so its position can stand '
            'in when this device has no GPS of its own.'
        : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (swap != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  swap,
                  key: const ValueKey('setup-swap-warning'),
                  style: TextStyle(
                      color: Theme.of(ctx).status.warning,
                      fontWeight: FontWeight.w600),
                ),
              ),
            Text(
              meshCore
                  ? _meshCoreConfirmText(role, change: change) + name + gps
                  : change
                      ? 'This writes the chosen range preset'
                          '${role == RadioRole.base ? ' and beacon interval' : ''} '
                          'to the node, keeps the private '
                          '"${RadioProfileService.channelName}" channel, then '
                          'restarts it.$name$gps$grant'
                      : 'This replaces ALL channels on the node with the private '
                          '"${RadioProfileService.channelName}" channel (the public '
                          'channel and any others are removed), sets the range '
                          'preset, then restarts it.$name Its current settings, '
                          'including its name, are backed up first so you can put '
                          'them back later.$gps$grant',
            ),
          ],
        ),
        actions: [
          // Optional: look at or make backups before applying.
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              _showBackups();
            },
            child: const Text('View backups'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(change ? 'Change settings' : 'Apply'),
          ),
        ],
      ),
    );
    return ok == true && mounted;
  }

  /// What applying writes to a MeshCore radio. No restart: the radio
  /// takes new radio settings at once.
  String _meshCoreConfirmText(RadioRole? role, {required bool change}) {
    final f = _mcFrequency;
    final power = _mcTxPower;
    final settings = [
      if (_mcMod case final m?)
        '${m.name} (${modulationLabel(m.spreadingFactor, m.bandwidthKHz, m.codingRate)})',
      if (f != null) '${formatFrequencyMHz(f)} MHz',
      if (power != null) '$power dBm',
    ].join(' · ');
    final relay = role == RadioRole.base
        ? ' Relaying (client repeat) is turned on, so the base answers the '
            'mobile\'s link checks.'
        : '';
    return change
        ? 'This writes the chosen radio settings ($settings) to the node '
            'and keeps the private "${RadioProfileService.channelName}" '
            'channel.$relay'
        : 'This moves the node off the public mesh to the private test '
            'settings ($settings) and adds the private '
            '"${RadioProfileService.channelName}" channel. It stays off the '
            'public mesh until you change its settings back.$relay Its '
            'current settings, including its name, are backed up first so '
            'you can put them back later.';
  }

  Future<void> _run(Future<void> Function() job, String successText) async {
    setState(() {
      _working = true;
      _error = null;
      _errorDetail = null;
      _showErrorDetail = false;
      _failedMidway = false;
      _success = null;
      _log.clear();
    });
    try {
      await job();
      // Follow the stored roles from here (the connected radio may have
      // changed, or just been given its role).
      if (mounted) {
        setState(() {
          _success = successText;
          _roleChoice = null;
          _markApplied();
        });
      }
    } catch (e, stack) {
      // Written down before anything else: a generic "Something went
      // wrong" on screen is useless without it (2026-11-08, a Wio Tracker
      // base setup failed with no trace anywhere).
      final detail = setupErrorDetail(e, stack, lastStep: _log.lastOrNull);
      DiagLog.instance.log('setup', detail.replaceAll('\n', ' | '));
      if (mounted) {
        setState(() {
          _error = userMessage(e, doing: 'setting up the node');
          _errorDetail = detail;
          _failedMidway = _log.isNotEmpty;
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
      _putBackKey.currentState?.reload();
    }
  }

  void _onStep(String step) {
    if (mounted) setState(() => _log.add(step));
  }

  String _deviceName(RadioDescriptor d) =>
      d.name.isNotEmpty ? d.name : 'this node';

  /// Mobile flow, step 1: set up another radio as the base over a second
  /// connection.
  /// Before a base apply: ask for Location if it was never asked, so the
  /// phone's position gets saved as the base location (first run
  /// 2026-11-06: nothing had asked yet, and the first map had no
  /// location to offer). The prompt is iOS's; declining is fine.
  Future<void> _askLocationForBase() async {
    final gps = ref.read(gpsServiceProvider);
    final status = gps.state.status;
    if (status != GpsStatus.notAsked && status != GpsStatus.unknown) return;
    await gps.ensureStarted(request: true);
  }

  Future<void> _applyToBase(RadioDescriptor device) async {
    if (!await _ensureRegion()) return;
    await _askLocationForBase();
    if (!mounted) return;
    final known =
        ref.read(radioRolesProvider).roleOfDevice(device.id) == RadioRole.base;
    if (!await _confirm(
        known
            ? 'Change ${_deviceName(device)}\'s settings (base)?'
            : 'Set up ${_deviceName(device)} as base?',
        role: RadioRole.base,
        change: known,
        swap: _swapWarning(RadioRole.base, deviceId: device.id))) {
      return;
    }
    await ref.read(radioScannerProvider).stopScan();
    await _run(
      // frequencyMHz / txPowerDbm: merged with meshcore/mc-services.
      () => _service.applyToBase(
        device,
        preset: _preset!,
        beaconSecs: _beaconSecs,
        rename: _rename,
        onStep: _onStep,
        frequencyMHz: _mcFrequency,
        txPowerDbm: _mcTxPower,
        allowRemoteChanges: _allowRemote,
        confirmReplaceAdminKey: _confirmReplaceAdminKey,
      ),
      _meshCore
          ? (known
              ? 'Base settings changed. Now apply the same settings to this '
                  'node (step 2).'
              : 'Base node set up. Now apply the same settings to this '
                  'node (step 2).')
          : known
              ? 'Base settings changed; it is restarting. Now apply the same '
                  'preset to this node (step 2).'
              : 'Base node set up and restarting. Now apply the same preset '
                  'to this node (step 2).',
    );
  }

  /// Set up the connected radio as [role].
  Future<void> _applyToConnected(RadioRole role) async {
    if (!await _ensureRegion()) return;
    if (role == RadioRole.base) {
      await _askLocationForBase();
      if (!mounted) return;
    }
    final radio = ref.read(meshRadioProvider);
    final change = _alreadySetUp(radio, role);
    if (!await _confirm(
        change
            ? 'Change ${radio.displayName}\'s settings '
                '(${role.label.toLowerCase()})?'
            : 'Set up ${radio.displayName} as ${role.label.toLowerCase()}?',
        role: role,
        change: change,
        swap: _swapWarning(role,
            nodeNum: radio.myNodeId, deviceId: radio.descriptor?.id))) {
      return;
    }
    final meshCore = _meshCore;
    await _run(
      // frequencyMHz / txPowerDbm: merged with meshcore/mc-services.
      () => _service.applyToConnected(
        role,
        preset: _preset!,
        beaconSecs: _beaconSecs,
        rename: _rename,
        onStep: _onStep,
        frequencyMHz: _mcFrequency,
        txPowerDbm: _mcTxPower,
        allowRemoteChanges: _allowRemote,
        confirmReplaceAdminKey: _confirmReplaceAdminKey,
      ),
      meshCore
          ? switch ((role, change)) {
              (RadioRole.base, true) => 'Base settings changed. If the '
                  'mobile uses different settings, apply the same ones to it '
                  '(step 2).',
              (RadioRole.base, false) => 'Base set up. Now find the node '
                  'you\'ll carry (step 2); the phone switches to it.',
              (RadioRole.mobile, true) => 'Settings changed.',
              (RadioRole.mobile, false) => 'Applied to this node.',
            }
          : switch ((role, change)) {
              (RadioRole.base, true) =>
                'Base settings changed; it is restarting. If the mobile uses a '
                    'different preset, apply the same one to it (step 2).',
              (RadioRole.base, false) =>
                'Base set up and restarting. Now find the node you\'ll carry '
                    '(step 2); the phone switches to it.',
              (RadioRole.mobile, true) =>
                'Settings changed. Your node is restarting; the app connects to '
                    'it again on its own.',
              (RadioRole.mobile, false) =>
                'Applied. Your node is restarting; the app connects to it again '
                    'on its own (the status pill at the top of the Live tab shows '
                    'when).',
            },
    );
    // Base flow: keep showing step 2 while the base reboots.
    if (role == RadioRole.base && mounted) {
      setState(() => _roleChoice = RadioRole.base);
    }
  }

  /// Base flow, step 2: connect the phone to the mobile and set it up.
  Future<void> _switchToMobile(RadioDescriptor device) async {
    final known = ref.read(radioRolesProvider).roleOfDevice(device.id) ==
        RadioRole.mobile;
    if (!await _confirm(
        known
            ? 'Change ${_deviceName(device)}\'s settings (mobile)?'
            : 'Set up ${_deviceName(device)} as mobile?',
        role: RadioRole.mobile,
        change: known,
        swap: _swapWarning(RadioRole.mobile, deviceId: device.id))) {
      return;
    }
    await ref.read(radioScannerProvider).stopScan();
    final meshCore = _meshCore;
    await _run(
      // frequencyMHz / txPowerDbm: merged with meshcore/mc-services.
      () => _service.switchToAndApplyMobile(
        device,
        preset: _preset!,
        rename: _rename,
        onStep: _onStep,
        frequencyMHz: _mcFrequency,
        txPowerDbm: _mcTxPower,
      ),
      meshCore
          ? 'Both nodes are set up. Your phone is connected to the mobile '
              'node.'
          : 'Both nodes are set up. Your phone is paired with the mobile '
              'node and connects to it once it has restarted.',
    );
  }

  /// Scan results, tagged with their protocol and any role they already
  /// have. A radio speaking another protocol than the connected one is
  /// listed but can't be picked: the two radios could never hear each
  /// other.
  List<Widget> _scanResults(RadioRoles roles, RadioProtocol connected,
      void Function(RadioDescriptor) onTap) {
    return [
      for (final r in _results)
        ListTile(
          key: ValueKey('setup-result-${r.id}'),
          leading: const Icon(Icons.router),
          title: Text(r.name.isNotEmpty ? r.name : 'Unnamed node'),
          subtitle: Text(r.protocol == connected
              ? 'Tap to set up this node'
              : 'Speaks ${protocolLabel(r.protocol)}: the base and mobile '
                  'must match'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ProtocolTag(r.protocol),
              if (roles.roleOfDevice(r.id) case final role?) ...[
                const SizedBox(width: 4),
                RoleChip(role),
              ],
            ],
          ),
          enabled: !_working && r.protocol == connected,
          onTap: () => onTap(r),
        ),
    ];
  }

  /// The connected radio's region, with a button to set or change it. A
  /// new radio has none, and setup would otherwise fall back to US.
  Widget _regionRow(MeshRadio radio, bool linkReady) {
    final meshtastic = radioAs<MeshtasticRadio>(radio);
    final unset = meshtastic != null && meshtastic.regionUnset;
    final region = MeshtasticRegions.byCode(radio.regionName);
    return Row(
      children: [
        Expanded(
          child: Text(
            unset
                ? 'Region: not set — pick one before setting up'
                : 'Region: ${region?.code ?? (radio.regionName.isEmpty ? 'not set' : radio.regionName)}',
            style: TextStyle(color: unset ? context.status.warning : null),
          ),
        ),
        if (meshtastic != null)
          TextButton(
            // Rarely needed once set: keep it quiet unless it's missing.
            style: unset
                ? null
                : TextButton.styleFrom(
                    foregroundColor:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                    textStyle: Theme.of(context).textTheme.bodySmall,
                  ),
            onPressed: _working || !linkReady
                ? null
                : () async {
                    if (await showRegionDialog(context, meshtastic,
                            newRadio: unset) &&
                        mounted) {
                      setState(() {
                        _error = null;
                        _success = 'Region set. Your node is restarting '
                            'and the app reconnects on its own.';
                        _markApplied();
                      });
                    }
                  },
            child: Text(unset ? 'Set region' : 'change'),
          ),
      ],
    );
  }

  /// Before writing settings: a radio without a region gets one chosen
  /// now instead of silently becoming US. Setting it restarts the radio,
  /// so the setup itself waits for the user to tap again once it's back.
  Future<bool> _ensureRegion() async {
    final radio = radioAs<MeshtasticRadio>(ref.read(meshRadioProvider));
    if (radio == null || !radio.regionUnset) return true;
    if (await showRegionDialog(context, radio, newRadio: true) && mounted) {
      setState(() {
        _error = null;
        _success = 'Region set. Your node is restarting; tap the button '
            'again once it has reconnected.';
        _markApplied();
      });
    }
    return false;
  }

  /// MeshCore: what the connected radio is on now.
  List<Widget> _meshCoreState(MeshRadio radio, RadioRole role, bool linkReady) {
    final theme = Theme.of(context);
    final status = theme.status;
    final p = radio.currentPreset;
    final mhz = _radioMHz(radio);
    final settings = [
      if (p != null) modulationLabel(p.sf, p.bwKHz, p.cr),
      if (mhz > 0) '${formatFrequencyMHz(mhz)} MHz',
      if (radio.radioSettings?.txPowerDbm case final dbm?) '$dbm dBm',
    ].join(' · ');
    final mod = _radioMod(radio);
    final relays = radio.capabilities.canRelay;
    return [
      Text(
        settings.isEmpty ? 'Radio settings: unknown' : settings,
        key: const ValueKey('mc-settings'),
        style: theme.readout.value,
      ),
      if (mod != null)
        Text('Range setting: ${mod.name}', style: theme.textTheme.bodyMedium),
      RadioFirmwareLine(radio: radio),
      Text(
        radio.onPublicChannel
            ? 'On your community mesh'
                '${radio.regionName.isEmpty ? '' : ' (${radio.regionName})'}. '
                'Setup moves it to the private test frequency.'
            : 'On the private test frequency.',
        key: const ValueKey('mc-public'),
        style: TextStyle(color: radio.onPublicChannel ? status.warning : null),
      ),
      if (role == RadioRole.base && linkReady && relays != null)
        Text(
          relays
              ? '✓ Relays, so it answers link checks'
              : 'Not relaying yet: setting it up as base turns relaying on',
          style: TextStyle(color: relays ? status.ok : status.warning),
        ),
    ];
  }

  /// MeshCore: the range setting (one of the community modulations, by
  /// airtime), the band's relay frequency and transmit power.
  List<Widget> _meshCoreControls(MeshRadio radio, TextStyle? hint) {
    final theme = Theme.of(context);
    final band = _band(radio);
    final f = double.tryParse(_freqController.text.trim());
    final meshMod = radio.onPublicChannel ? _radioMod(radio) : null;
    final mono = theme.readout.value.copyWith(fontWeight: FontWeight.w400);
    final small = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    String airtime(MeshCoreModulation m) => AirtimeExplainer.formatAirtime(
        AirtimeModel.probeAirtimeMsFor(m.radioPreset,
            protocol: RadioProtocol.meshcore));
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child:
                  _meshCoreModDropdown(radio, meshMod, mono, small, airtime)),
          InfoButton(
              key: const ValueKey('range-info'),
              title: 'Range setting',
              body: _rangeInfo(true)),
        ],
      ),
      const SizedBox(height: 12),
      ..._meshCoreFrequencyAndPower(radio, band, f, mono, small, theme),
    ];
  }

  Widget _meshCoreModDropdown(
      MeshRadio radio,
      MeshCoreModulation? meshMod,
      TextStyle mono,
      TextStyle? small,
      String Function(MeshCoreModulation) airtime) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<MeshCoreModulation>(
      key: ValueKey('mc-mod-${_mcMod?.id}'),
      initialValue: _mcMod,
      isExpanded: true,
      itemHeight: null,
      decoration: const InputDecoration(
          labelText: 'Range setting',
          helperText: 'Longer settings reach further and allow fewer '
              'link checks per minute',
          helperMaxLines: 2),
      selectedItemBuilder: (_) => [
        for (final m in MeshCoreModulations.all)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${m.name} · '
              '${modulationLabel(m.spreadingFactor, m.bandwidthKHz, m.codingRate)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      items: [
        for (final m in MeshCoreModulations.all)
          DropdownMenuItem(
            value: m,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          m == meshMod
                              ? '${m.name} · same as your mesh'
                              : m.name,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      Text('≈${airtime(m)}', style: mono),
                    ],
                  ),
                  Text(
                    modulationLabel(
                        m.spreadingFactor, m.bandwidthKHz, m.codingRate),
                    style: mono.copyWith(fontSize: 12),
                  ),
                  Text(meshCoreCommunitiesLabel(m, first: radio.regionName),
                      style: small),
                ],
              ),
            ),
          ),
      ],
      onChanged: _working ? null : _onMcModChanged,
    );
  }

  List<Widget> _meshCoreFrequencyAndPower(MeshRadio radio, MeshCoreBand band,
      double? f, TextStyle mono, TextStyle? small, ThemeData theme) {
    return [
      // ─── Test frequency: one right answer per band ───
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Test frequency', style: small),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: '${formatFrequencyMHz(band.clientRepeatMHz)} MHz',
                        style: mono),
                    TextSpan(
                        text: ' · the relay frequency for ${band.label} radios',
                        style: small),
                  ]),
                  key: const ValueKey('mc-frequency-line'),
                ),
              ],
            ),
          ),
          if (!_freqOther)
            TextButton(
              key: const ValueKey('mc-frequency-other'),
              onPressed:
                  _working ? null : () => setState(() => _freqOther = true),
              child: const Text('Other…'),
            ),
        ],
      ),
      if (_freqOther) ...[
        const SizedBox(height: 4),
        TextField(
          key: const ValueKey('mc-frequency'),
          controller: _freqController,
          enabled: !_working,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Test frequency (MHz)',
            errorText: _freqError,
            helperText: 'The base relays, and so answers link checks, only '
                'on 433.000, 869.495 or 918.000 MHz.',
            helperMaxLines: 2,
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (f != null && _freqError == null && !isClientRepeatFrequency(f))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Not a relay frequency: a base on it can\'t answer link checks.',
              key: const ValueKey('mc-freq-warning'),
              style: TextStyle(color: theme.status.warning),
            ),
          ),
      ],
      const SizedBox(height: 12),
      // ─── TX power: a stepper on the field ───
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('mc-power'),
              controller: _powerController,
              enabled: !_working,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'TX power (dBm)',
                errorText: _powerError,
                helperText: 'Up to 22; the radio limits it to what it '
                    'supports. Empty keeps its own.',
                helperMaxLines: 2,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            key: const ValueKey('mc-power-down'),
            tooltip: 'Lower power',
            onPressed: _working ? null : () => _nudgePower(radio, -1),
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            key: const ValueKey('mc-power-up'),
            tooltip: 'Raise power',
            onPressed: _working ? null : () => _nudgePower(radio, 1),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    ];
  }

  /// The remote-changes switch (Meshtastic only), and when the base holds
  /// the mobile's key already, a row to take it back out.
  List<Widget> _remoteAdminControls(RadioRoles roles, TextStyle? hint) {
    final granted = roles.remoteAdminGrantedNode;
    return [
      SwitchListTile(
        key: const ValueKey('allow-remote'),
        contentPadding: EdgeInsets.zero,
        value: _allowRemote,
        onChanged: _working ? null : (v) => setState(() => _allowRemote = v),
        title: const Row(
          children: [
            Flexible(child: Text(remoteAdminSwitchTitle)),
            InfoButton(
              key: ValueKey('allow-remote-info'),
              title: 'Remote changes',
              body: remoteAdminSwitchSubtitle,
            ),
          ],
        ),
      ),
      if (granted != null)
        ListTile(
          key: const ValueKey('revoke-remote'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.key_off_outlined),
          title: const Text('The mobile node can change the base from a '
              'distance'),
          subtitle: Text(
              'Its key is in the base node\'s admin list. Stop '
              'allowing it to take the key back out (the phone connects to '
              'the base, which restarts).',
              style: hint),
          trailing: TextButton(
            onPressed: _working ? null : _revokeRemote,
            child: const Text('Stop allowing'),
          ),
        ),
      if (granted != null)
        ListTile(
          key: const ValueKey('open-remote-change'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.settings_remote_outlined),
          title: const Row(
            children: [
              Flexible(child: Text('Change the base from here')),
              SizedBox(width: 6),
              ProTag(),
            ],
          ),
          subtitle: Text(
              'Its range setting or TX power, over the mesh, without '
              'walking to it.',
              style: hint),
          trailing: const Icon(Icons.chevron_right),
          onTap: _working
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const RemoteBaseChangeScreen())),
        ),
    ];
  }

  /// Why "Change the base from here" can't be offered, once a base is
  /// recorded: MeshCore has no remote admin, and a Meshtastic base needs the
  /// mobile's key first. Null when there is no base yet or it is granted
  /// (the live row above covers that).
  String? _remoteChangeUnavailable(RadioRoles roles, bool meshCore) {
    if (roles.nodeOf(RadioRole.base) == null) return null;
    if (meshCore) {
      return 'MeshCore nodes can\'t be changed over the mesh. Take the phone '
          'to the base node and change it here over Bluetooth.';
    }
    if (roles.remoteAdminGrantedNode != null) return null;
    return 'The base node doesn\'t hold the mobile node\'s key yet. Turn on '
        '"$remoteAdminSwitchTitle" and set up the base again (at the base, '
        'over Bluetooth).';
  }

  /// The same row as when it's granted, greyed out, with the reason.
  Widget _remoteChangeUnavailableRow(String why, TextStyle? hint) => ListTile(
        key: const ValueKey('remote-change-unavailable'),
        contentPadding: EdgeInsets.zero,
        enabled: false,
        leading: const Icon(Icons.settings_remote_outlined),
        title: const Text('Change the base from here'),
        subtitle: Text(why, style: hint),
      );

  Future<void> _revokeRemote() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop remote changes?'),
        content: const Text('This takes the mobile node\'s key out of the '
            'base node\'s admin list, so it can no longer change the base '
            'from a distance. The base must be near the phone; it restarts. '
            'Guided tests then change the base over Bluetooth.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop allowing'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => _service.revokeRemoteAdminAtBase(onStep: _onStep),
        'The mobile node can no longer change the base from a distance.');
  }

  /// Asked mid-setup when the base already holds the most admin keys the
  /// firmware allows. Skipping (the default) leaves its list alone.
  Future<bool> _confirmReplaceAdminKey(String oldestKey) async {
    if (!mounted) return false;
    final replace = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('The base node\'s admin list is full'),
        content: Text('It already has 3 admin keys, so the mobile node\'s '
            'key does not fit. Replacing the oldest one ($oldestKey) takes '
            'admin access away from whatever node or app holds it. Skip to '
            'leave the list as it is: guided tests then change the base over '
            'Bluetooth.'),
        actions: [
          TextButton(
            key: const ValueKey('replace-admin-key'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace oldest'),
          ),
          FilledButton(
            key: const ValueKey('skip-admin-key'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    return replace == true;
  }

  /// The primary (filled) style goes to the next step only; the other
  /// step is outlined, so the brightest control is the thing to do now.
  Widget _stepButton({
    required bool primary,
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    Key? key,
  }) =>
      primary
          ? FilledButton.icon(
              key: key,
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label))
          : OutlinedButton.icon(
              key: key,
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label));

  Widget _findButton(String label, {required bool primary}) => _stepButton(
        primary: primary,
        onPressed: (_scanning || _working || _mcInvalid) ? null : _scan,
        icon: Icons.bluetooth_searching,
        label: _scanning ? 'Scanning…' : label,
      );

  /// What the range setting is, behind its ⓘ.
  static String _rangeInfo(bool meshCore) => meshCore
      ? 'Each range setting is one of the modulations MeshCore communities '
          'use, fastest link check first. Longer settings reach further but '
          'stay on air longer, so the mobile can check the link less often. '
          'The base and the mobile must use the same one to hear each '
          'other.\n\n'
          'To test other settings: bring the base back, pick them, apply to '
          'both, then start a new session. Each session records the settings '
          'it used.'
      : 'Meshtastic calls this the modem preset. Slower presets reach '
          'further, but each packet stays on air longer, so pings and the '
          'base beacon go out less often. The base and the mobile must use '
          'the same one to hear each other; only the presets your region '
          'allows are listed.\n\n'
          'To test another range preset: bring the base back, pick the '
          'preset, apply to both, then start a new session. Each session '
          'records the preset it used.';

  /// The beacon's ⓘ: what it is, then the airtime explainer.
  Widget _beaconInfo(BuildContext context, bool meshCore) {
    final preset = _preset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          meshCore
              ? 'While a session records, the mobile checks the link to the '
                  'base on this timer and records how well each check is '
                  'heard both ways. Nothing is written to the base.'
              : 'The base sends a small signal on this timer (device '
                  'telemetry or a Range Test message, picked from its '
                  'firmware when you apply; telemetry goes out at most once '
                  'a minute) and the mobile measures each one it hears. Your '
                  'pings come on top of it.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (preset != null) ...[
          const SizedBox(height: 12),
          AirtimeExplainer.forPreset(preset,
              inline: true,
              protocol:
                  meshCore ? RadioProtocol.meshcore : RadioProtocol.meshtastic),
        ],
      ],
    );
  }

  /// Helper under the beacon interval: what one beacon costs and the
  /// shortest interval offered, e.g. "≈0.2 s of air per beacon · shortest
  /// interval 5 s" ("per link check" on MeshCore, where the beacon is the
  /// mobile's trace).
  String? _airtimeLine() {
    final p = _preset;
    if (p == null) return null;
    final protocol =
        _meshCore ? RadioProtocol.meshcore : RadioProtocol.meshtastic;
    final air = AirtimeExplainer.formatAirtime(
        AirtimeModel.beaconAirtimeMsFor(p, protocol: protocol));
    final floor = AirtimeModel.minIntervalSecFor(p,
        override: _faster, protocol: protocol);
    return '≈$air of air per ${_meshCore ? 'link check' : 'beacon'} · '
        'shortest interval ${AppConstants.formatSeconds(floor)}';
  }

  @override
  Widget build(BuildContext context) {
    final linkState = ref.watch(meshLinkStateProvider).valueOrNull;
    final radio = ref.watch(meshRadioProvider);
    final meshCore = radio.protocol == RadioProtocol.meshcore;
    final roles = ref.watch(radioRolesProvider);
    final role = _connectedRole(radio);
    // Base flow step 2 doesn't need the (rebooting) base connected.
    final baseStep2 = role == RadioRole.base &&
        _roleChoice == RadioRole.base &&
        roles.roleOf(radio) == RadioRole.base;
    final ready = linkState == RadioConnectionState.ready || baseStep2;
    final service = _service;
    final linkReady = linkState == RadioConnectionState.ready;
    // Down, then back after the apply: the hold is over.
    if (!linkReady) {
      _linkDropped = true;
    } else if (_linkDropped) {
      _linkDropped = false;
      _appliedAt = null;
    }
    final settling = _appliedAt != null &&
        DateTime.now().difference(_appliedAt!) < RadioSetupScreen.settleFor;
    // Only the presets the firmware accepts in this region (EU_868: no
    // 500 kHz; EU_866: LITE_*; EU_N_868: NARROW_*).
    final offered = MeshtasticPresets.presetsForRegion(service.regionName,
        firmwareVersion: radio.capabilities.firmwareVersion);

    // A radio of the other protocol starts the choice over.
    if (ready && _presetProtocol != radio.protocol) {
      _presetProtocol = radio.protocol;
      _preset = null;
      _mcMod = null;
    }
    // MeshCore: prefill from the radio once. Meshtastic: pick (or, once
    // the region changed, re-pick) a preset the region allows, the radio's
    // own if it is one, else the region's default.
    if (meshCore) {
      if (ready && _mcMod == null) _initMeshCore(radio);
    } else if (ready &&
        (_preset == null || (linkReady && !offered.contains(_preset)))) {
      final current = radio.currentPreset;
      _preset = offered.contains(current)
          ? current
          : MeshtasticPresets.defaultForRegion(service.regionName);
      if (!_beaconAllowed(_beaconSecs, _preset)) {
        _beaconSecs = _intervals.firstWhere(
          (s) => s != 0 && _beaconAllowed(s, _preset),
          orElse: () => _intervals.last,
        );
      }
    }
    final matches =
        linkReady && _preset != null && service.mobileMatches(_preset!);
    final theme = Theme.of(context);
    final status = theme.status;
    // Explanatory text under a control: body size, soft ink.
    final hint = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: const Text('Node Setup')),
      body: WideColumn(
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'You need two nodes: one stays put (the base) and one you '
                'carry (the mobile). This puts both on a private test channel.',
                style: theme.textTheme.bodyLarge,
              ),
            ),
            if (!ready) ...[
              if (settling) ...[
                // One calm line through the reboot; the log and the success
                // line (which says the app reconnects on its own) follow
                // below. No Connect button: the radio comes back by itself,
                // and a tap here would only get in its way.
                Text(
                  'Restarting. Waiting for the node to come back…',
                  key: const ValueKey('setup-settling'),
                  style: hint,
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
              ] else if (linkState == RadioConnectionState.reconnecting ||
                  linkState == RadioConnectionState.configuring)
                Text('Waiting for your node to reconnect over Bluetooth…',
                    style: TextStyle(color: status.warning))
              else ...[
                Text(
                  'Connect to one of your nodes. You choose here whether it '
                  'is the base or the mobile.',
                  style: TextStyle(color: status.warning),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const ValueKey('setup-connect'),
                  onPressed: () => showConnectDialog(context),
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Connect a node'),
                ),
              ],
            ] else ...[
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: SetupMismatchBanner(),
              ),
              _whoCard(radio, roles, role, meshCore, linkReady, matches),
              _settingsCard(
                  radio, roles, role, meshCore, linkReady, offered, hint),
              _applyCard(radio, roles, role, meshCore, linkReady, baseStep2,
                  service, hint),
            ],

            // ─── Progress ───
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final line in _log) Text('• $line'),
            ],
            if (_working)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline,
                            size: 18, color: theme.colorScheme.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_error!,
                              style: TextStyle(color: theme.colorScheme.error)),
                        ),
                      ],
                    ),
                    if (_errorDetail != null) ...[
                      TextButton(
                        key: const ValueKey('setup-error-details'),
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        onPressed: () => setState(
                            () => _showErrorDetail = !_showErrorDetail),
                        child:
                            Text(_showErrorDetail ? 'Hide details' : 'Details'),
                      ),
                      if (_showErrorDetail)
                        SelectableText(
                          _errorDetail!,
                          key: const ValueKey('setup-error-detail-text'),
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: ReadoutStyles.monoFamily,
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                    if (_failedMidway)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          meshCore
                              ? 'Your node may be half-configured. Use Backups '
                                  '→ Restore or run Node Setup again.'
                              : 'Your node may be half-configured. Power-cycle '
                                  'it, then use Backups → Restore or run Node '
                                  'Setup again.',
                          style: TextStyle(color: status.warning),
                        ),
                      ),
                  ],
                ),
              ),
            if (_success != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 18, color: status.ok),
                    const SizedBox(width: 6),
                    Expanded(
                      child:
                          Text(_success!, style: TextStyle(color: status.ok)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            // ─── Undo and backups (the backups have their own screen) ───
            RestoreOriginalButton(
              key: _putBackKey,
              asLink: true,
              onlyWhen: _service.isOnTestChannel,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('setup-backups'),
                onPressed: _showBackups,
                icon: const Icon(Icons.save_alt),
                label: const Text('Backups…'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Card 1: which radio is connected, what it is on now, and whether it
  /// is the mobile or the base.
  Widget _whoCard(MeshRadio radio, RadioRoles roles, RadioRole role,
      bool meshCore, bool linkReady, bool matches) {
    final theme = Theme.of(context);
    final status = theme.status;
    return _SetupCard(
      key: const ValueKey('setup-card-who'),
      title: 'Who is this node?',
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Connected: ${radio.displayName}',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (roles.roleOf(radio) != null) RoleChip(roles.roleOf(radio)!),
            // Switch to the other radio without leaving this screen.
            TextButton(
              key: const ValueKey('setup-switch-radio'),
              onPressed: () => showConnectDialog(context),
              child: const Text('Change'),
            ),
          ],
        ),
        if (meshCore)
          ..._meshCoreState(radio, role, linkReady)
        else ...[
          Text('Range setting: '
              '${radio.currentPreset?.displayName ?? 'unknown'}'),
          RadioFirmwareLine(radio: radio),
          Text(
            radio.onPublicChannel
                ? 'Channel: public — not usable for testing'
                : 'Channel: ${radio.primaryChannelName.isEmpty ? 'unnamed' : radio.primaryChannelName} (private)',
            style: TextStyle(
              color: radio.onPublicChannel ? status.warning : null,
            ),
          ),
        ],
        if (matches)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                meshCore
                    ? '✓ On the test frequency with this range setting'
                    : '✓ On the test channel with this preset',
                style: TextStyle(color: status.ok)),
          ),
        const SizedBox(height: 12),
        Text('The connected node is my…', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<RadioRole>(
          segments: const [
            ButtonSegment(
              value: RadioRole.mobile,
              icon: Icon(Icons.directions_walk),
              label: FittedBox(
                  fit: BoxFit.scaleDown, child: Text('Mobile (I carry it)')),
            ),
            ButtonSegment(
              value: RadioRole.base,
              icon: Icon(Icons.cell_tower),
              label: FittedBox(
                  fit: BoxFit.scaleDown, child: Text('Base (stays put)')),
            ),
          ],
          selected: {role},
          onSelectionChanged: _working
              ? null
              : (v) => setState(() {
                    _roleChoice = v.first;
                    _results = [];
                  }),
        ),
      ],
    );
  }

  /// Card 2: region, range setting, beacon (and on MeshCore frequency
  /// and power). One sentence under each control; the rest behind ⓘ.
  Widget _settingsCard(
      MeshRadio radio,
      RadioRoles roles,
      RadioRole role,
      bool meshCore,
      bool linkReady,
      List<RadioPreset> offered,
      TextStyle? hint) {
    return _SetupCard(
      key: const ValueKey('setup-card-settings'),
      title: 'Settings',
      children: [
        if (meshCore)
          ..._meshCoreControls(radio, hint)
        else ...[
          _regionRow(radio, linkReady),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<RadioPreset>(
                  initialValue: _preset,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Range setting (modem preset)',
                      helperText:
                          'Slower settings reach further; both nodes must '
                          'match.',
                      helperMaxLines: 2),
                  items: [
                    for (final p in offered)
                      DropdownMenuItem(value: p, child: Text(_presetLabel(p))),
                  ],
                  onChanged: _working ? null : _onPresetChanged,
                ),
              ),
              InfoButton(
                  key: const ValueKey('range-info'),
                  title: 'Range setting',
                  body: _rangeInfo(false)),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                // initialValue is read once; re-key so a preset-driven bump
                // shows.
                key: ValueKey('beacon-$_preset-$_beaconSecs'),
                initialValue: _beaconSecs,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText:
                      meshCore ? 'Link check interval' : 'Base beacon interval',
                  helperText: _airtimeLine(),
                  helperMaxLines: 2,
                ),
                items: [
                  for (final s in _intervals)
                    if (_beaconAllowed(s, _preset))
                      DropdownMenuItem(
                        value: s,
                        child: Text(s == 0
                            ? 'Off'
                            : 'Every ${AppConstants.formatSeconds(s)}'),
                      ),
                ],
                onChanged: _working
                    ? null
                    : (v) => setState(() => _beaconSecs = v ?? 30),
              ),
            ),
            InfoButton(
              key: const ValueKey('beacon-info'),
              title: meshCore ? 'Link check' : 'Base beacon',
              builder: (ctx) => _beaconInfo(ctx, meshCore),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _beaconSummary(roles, radio, role),
            key: const ValueKey('beacon-summary'),
            style: hint,
          ),
        ),
        if (meshCore)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Nothing is written to the base for it.',
              key: const ValueKey('trace-beacon-note'),
              style: hint,
            ),
          ),
      ],
    );
  }

  /// Card 3: the two steps, in the order the role needs them (mobile: the
  /// base first, then this radio; base: this radio, then switch to the
  /// mobile). Only the next step is filled.
  Widget _applyCard(
      MeshRadio radio,
      RadioRoles roles,
      RadioRole role,
      bool meshCore,
      bool linkReady,
      bool baseStep2,
      RadioProfileService service,
      TextStyle? hint) {
    final theme = Theme.of(context);
    final step = theme.textTheme.titleSmall;
    final applyDisabled = _working || !linkReady || _mcInvalid;
    return _SetupCard(
      key: const ValueKey('setup-card-apply'),
      title: 'Apply to the nodes',
      children: [
        Text(
          meshCore
              ? 'Private channel "${RadioProfileService.channelName}" · '
                  'test frequency '
                  '${_mcFrequency == null ? '?' : formatFrequencyMHz(_mcFrequency!)} '
                  'MHz. Put both nodes side by side while applying.'
              : 'Private channel "${RadioProfileService.channelName}" · '
                  'Region ${service.regionName}. Put both nodes side by '
                  'side while applying.',
          style: hint,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _rename,
          onChanged:
              _working ? null : (v) => setState(() => _rename = v ?? true),
          title: Text(meshCore
              ? 'Name the nodes '
                  '"${RadioProfileService.radioNames[RadioRole.base]!.$1}" '
                  'and '
                  '"${RadioProfileService.radioNames[RadioRole.mobile]!.$1}"'
              : 'Name the nodes BASE and MOBL on their screens'),
          subtitle: const Text('Their current names are saved in the backup.'),
        ),
        if (!meshCore) ..._remoteAdminControls(roles, hint),
        if (_remoteChangeUnavailable(roles, meshCore) case final why?)
          _remoteChangeUnavailableRow(why, hint),
        const SizedBox(height: 8),
        if (role == RadioRole.mobile) ...[
          // ─── Mobile flow: the base first ───
          Builder(builder: (_) {
            final base = roles.nodeOf(RadioRole.base);
            final baseDone = base != null && base != radio.myNodeId;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('1. Base node', style: step),
                const SizedBox(height: 8),
                _findButton('Find base node', primary: !baseDone),
                ..._scanResults(roles, radio.protocol, _applyToBase),
                const SizedBox(height: 16),
                Text('2. This node (mobile)', style: step),
                const SizedBox(height: 8),
                _stepButton(
                  primary: baseDone,
                  onPressed: applyDisabled
                      ? null
                      : () => _applyToConnected(RadioRole.mobile),
                  icon: Icons.settings_input_antenna,
                  label: _alreadySetUp(radio, RadioRole.mobile)
                      ? 'Change this node\'s settings'
                      : 'Apply to this node',
                ),
              ],
            );
          }),
        ] else ...[
          // ─── Base flow: this radio, then switch to the mobile ───
          Builder(builder: (_) {
            final baseDone = baseStep2 || _alreadySetUp(radio, RadioRole.base);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('1. This node (base)', style: step),
                const SizedBox(height: 8),
                _stepButton(
                  primary: !baseDone,
                  onPressed: applyDisabled
                      ? null
                      : () => _applyToConnected(RadioRole.base),
                  icon: Icons.cell_tower,
                  label: _alreadySetUp(radio, RadioRole.base)
                      ? 'Change this node\'s settings'
                      : 'Set up this node as base',
                ),
                const SizedBox(height: 16),
                Text('2. The node you\'ll carry (mobile)', style: step),
                const SizedBox(height: 4),
                Text(
                  'Your phone switches to it, because mapping uses the node '
                  'you carry.',
                  style: hint,
                ),
                const SizedBox(height: 8),
                _findButton('Find mobile node', primary: baseDone),
                ..._scanResults(roles, radio.protocol, _switchToMobile),
              ],
            );
          }),
        ],
      ],
    );
  }

  static String _presetLabel(RadioPreset p) {
    const labels = {
      'LONG_SLOW': 'Long Slow (deprecated; longest range, slowest)',
      'LONG_MODERATE': 'Long Moderate',
      'LONG_FAST': 'Long Fast (default)',
      'LONG_TURBO': 'Long Turbo (500 kHz)',
      'MEDIUM_SLOW': 'Medium Slow',
      'MEDIUM_FAST': 'Medium Fast',
      'SHORT_SLOW': 'Short Slow',
      'SHORT_FAST': 'Short Fast',
      'SHORT_TURBO': 'Short Turbo (shortest range, fastest)',
      'LITE_FAST': 'Lite Fast (default)',
      'NARROW_SLOW': 'Narrow Slow (default)',
    };
    return labels[p.id] ?? p.displayName;
  }
}

/// One of Radio Setup's three cards: a title, then its controls.
class _SetupCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SetupCard({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// What went wrong in a Radio Setup apply, for the Details toggle and the
/// diag log: the error's type and text, the step it failed in, and the top
/// of the stack (enough to find the line; the full trace is too long to
/// read off a phone).
String setupErrorDetail(Object error, StackTrace stack, {String? lastStep}) {
  final frames = stack
      .toString()
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .take(6)
      .join('\n');
  final text = '$error';
  final type = '${error.runtimeType}';
  return [
    text.startsWith(type) ? text : '$type: $text',
    if (lastStep != null) 'Last step: $lastStep',
    frames,
  ].join('\n');
}
