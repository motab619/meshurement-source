// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/radio/ble/radio_scanner.dart';
import '../../data/radio/ble/radio_services.dart';
import '../../data/radio/mesh_radio.dart';
import '../../data/radio/meshtastic/meshtastic_radio.dart';
import '../../data/radio/switchable_radio.dart';
import '../../providers.dart';
import '../../utils/constants.dart';
import '../../services/last_radio.dart';
import '../../services/radio_roles.dart';
import '../screens/radio_setup_screen.dart';
import '../protocol_text.dart';
import '../theme/app_theme.dart';
import '../../utils/user_errors.dart';
import 'connect_failure.dart';
import 'connect_progress_view.dart';
import 'protocol_tag.dart';
import 'region_dialog.dart';
import 'radio_firmware_line.dart';
import 'role_chip.dart';

/// Scan for radios and connect to the chosen one.
Future<void> showConnectDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _ScanDialog(),
    );

/// Compact radio status pill for the top of the map. Tap to connect, or
/// (when connected) to see radio details and disconnect. While there is no
/// radio it is a "Connect a radio" button instead.
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adapter = ref.watch(bleAdapterStateProvider).valueOrNull;
    final linkState = ref.watch(meshLinkStateProvider).valueOrNull ??
        RadioConnectionState.disconnected;
    final radio = ref.read(meshRadioProvider);
    final name = radio.displayName;
    final inSession = ref.watch(activeSessionProvider).valueOrNull != null;
    final range = ref.watch(rangeStateProvider).valueOrNull;
    final knownRole = linkState == RadioConnectionState.ready
        ? ref.watch(radioRolesProvider).roleOf(radio)
        : null;
    // Skip "· Mobile" when the name already says it ("MeshTest Mobile"),
    // except for the base, which is worth flagging.
    final role = knownRole != null &&
            knownRole != RadioRole.base &&
            name.toLowerCase().contains(knownRole.label.toLowerCase())
        ? null
        : knownRole;

    final theme = Theme.of(context);
    final status = theme.status;
    final chrome = theme.mapChrome;
    final labelStyle =
        theme.textTheme.bodyMedium?.copyWith(color: chrome.onOverlay);

    final (Color dot, String? label) = switch (linkState) {
      RadioConnectionState.ready => (status.ok, name),
      RadioConnectionState.connecting ||
      RadioConnectionState.pairing ||
      RadioConnectionState.configuring =>
        (status.info, null),
      RadioConnectionState.reconnecting => (status.lost, null),
      RadioConnectionState.disconnected => (
          theme.colorScheme.error,
          adapter == RadioAdapterState.off
              ? 'Bluetooth off'
              : adapter == RadioAdapterState.unauthorized
                  ? 'Bluetooth not allowed'
                  : 'Connect a node',
        ),
    };

    // Disconnected with Bluetooth usable: an action, not a status, so it
    // looks like a button and says what a tap does (new-user walkthrough
    // 2026-11-08: "Connect radio" read as status). "Node" since the
    // 2026-11-09 wording sweep: the radio is part of the node.
    if (linkState == RadioConnectionState.disconnected &&
        adapter != RadioAdapterState.off &&
        adapter != RadioAdapterState.unauthorized) {
      return FilledButton.tonalIcon(
        key: const ValueKey('connect-radio-button'),
        onPressed: () => showConnectDialog(context),
        icon: const Icon(Icons.bluetooth, size: 18),
        label: const Text('Connect a node'),
      );
    }

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(chrome.radius),
      side: BorderSide(color: chrome.hairline),
    );
    return Material(
      color: chrome.overlay,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: () => linkState == RadioConnectionState.disconnected
            ? showConnectDialog(context)
            : showModalBottomSheet<void>(
                context: context,
                builder: (_) => const _RadioSheet(),
              ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 10, color: dot),
              const SizedBox(width: 8),
              Flexible(
                child: label != null
                    ? Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle,
                      )
                    : const _ProgressLabel(),
              ),
              if (role != null)
                // Flexible so a long name + role at large text ellipsises
                // here instead of overflowing the pill (Android review).
                Flexible(
                  child: Text(
                    ' · ${role.label}',
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle?.copyWith(
                      // The base connected to the phone is usually a mistake.
                      color: role == RadioRole.base
                          ? status.warning
                          : chrome.onOverlayMuted,
                    ),
                  ),
                ),
              if (inSession &&
                  linkState == RadioConnectionState.ready &&
                  range != null) ...[
                const SizedBox(width: 10),
                _RangeBadge(range: range),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill text while connecting: the current step, node-list percentage or
/// elapsed time. Ticks once a second.
class _ProgressLabel extends ConsumerStatefulWidget {
  const _ProgressLabel();

  @override
  ConsumerState<_ProgressLabel> createState() => _ProgressLabelState();
}

class _ProgressLabelState extends ConsumerState<_ProgressLabel> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(connectProgressProvider).valueOrNull;
    final theme = Theme.of(context);
    return Text(
      connectProgressLabel(p, DateTime.now()),
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium
          ?.copyWith(color: theme.mapChrome.onOverlay),
    );
  }
}

/// Base-node reachability during a session.
class _RangeBadge extends StatelessWidget {
  final RangeState range;

  const _RangeBadge({required this.range});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = theme.status;
    final (Color color, String text) = switch (range) {
      RangeState.inRange => (status.ok, 'base ✓'),
      RangeState.outOfRange => (theme.colorScheme.error, 'base lost'),
      RangeState.radioLost => (status.lost, 'base ?'),
      RangeState.unknown => (theme.mapChrome.onOverlayMuted, 'base …'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cell_tower, size: 14, color: color),
        const SizedBox(width: 3),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}

/// Details of the connected radio, with Disconnect.
class _RadioSheet extends ConsumerWidget {
  const _RadioSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linkState = ref.watch(meshLinkStateProvider).valueOrNull;
    final radio = ref.read(meshRadioProvider);
    final channel = radio.primaryChannelName;
    final nodeNum = radio.myNodeId;
    final role = ref.watch(radioRolesProvider).roleOf(radio);
    final meshCore = radio.protocol == RadioProtocol.meshcore;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(radio.displayName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (linkState != RadioConnectionState.ready) ...[
              const ConnectProgressView(),
              const SizedBox(height: 12),
            ],
            if (nodeNum != null)
              Text('Node id: !${nodeNum.toRadixString(16).padLeft(8, '0')}'),
            if (radio.currentPreset case final p?)
              Text(meshCore
                  ? '${modulationLabel(p.sf, p.bwKHz, p.cr)} · '
                      '${formatFrequencyMHz(radio.regionFrequencyMHz)} MHz'
                  : 'Range setting: ${anyPresetDisplayName(p.id)} · '
                      'Region: ${radio.regionName.isEmpty ? 'not set' : radio.regionName}'),
            RadioFirmwareLine(radio: radio),
            Text(meshCore
                ? (radio.onPublicChannel
                    ? 'Public mesh settings'
                        '${radio.regionName.isEmpty ? '' : ' (${radio.regionName})'}'
                    : 'Private test settings')
                : radio.onPublicChannel
                    ? 'Channel: public'
                    : 'Channel: ${channel.isEmpty ? '(unnamed)' : channel} (private)'),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Role: '),
                if (role != null)
                  RoleChip(role)
                else
                  Text('not set', style: TextStyle(color: theme.status.muted)),
                const SizedBox(width: 8),
                // Flexible: the label must give way on a narrow phone.
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        final nav = Navigator.of(context);
                        nav.pop();
                        nav.push(MaterialPageRoute<void>(
                          builder: (_) => RadioSetupScreen(
                            initialRole: role?.other,
                          ),
                        ));
                      },
                      child: Text(
                        role == null
                            ? 'Set role…'
                            : 'Make this the ${role.other.label.toLowerCase()}…',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (role == RadioRole.base)
              Text(
                'This is your base node. For mapping, connect the phone to '
                'the node you carry.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.status.warning),
              ),
            const SizedBox(height: 8),
            // Switching used to mean Disconnect, then the pill again; testers
            // didn't find it (2026-11-01).
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('sheet-switch-radio'),
                    onPressed: () {
                      final nav = Navigator.of(context);
                      nav.pop();
                      showConnectDialog(nav.context);
                    },
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Switch node…'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      radio.disconnect();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.bluetooth_disabled),
                    label: const Text('Disconnect'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Scan dialog. Scans with [RadioScanner], then hands the chosen device to
/// the radio, which switches protocol if needed, connects and downloads the
/// radio's config.
class _ScanDialog extends ConsumerStatefulWidget {
  const _ScanDialog();

  @override
  ConsumerState<_ScanDialog> createState() => _ScanDialogState();
}

/// Plain-English connection failure with the usual fixes.
class _ScanDialogState extends ConsumerState<_ScanDialog> {
  final List<RadioDescriptor> _scanResults = [];

  /// Radios already connected to the phone at the system level (e.g. by
  /// another app). They stop advertising, so a scan alone won't find them.
  final List<RadioDescriptor> _systemDevices = [];
  bool _scanning = false;
  bool _connecting = false;
  String? _error;

  /// A failed connect, shown in parts (headline, cause, tips, details).
  ConnectFailure? _failure;
  bool _permDenied = false;
  StreamSubscription<List<RadioDescriptor>>? _scanSubscription;

  static const _scanTimeout = Duration(seconds: 15);

  /// Read once: `ref` can't be used in [dispose].
  late final RadioScanner _scanner;

  @override
  void initState() {
    super.initState();
    _scanner = ref.read(radioScannerProvider);
    _startScan();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _scanner.stopScan();
    super.dispose();
  }

  /// The runtime permissions a scan needs: iOS has one Bluetooth
  /// permission; Android 12+ splits it into scan and connect (on Android 11
  /// and older both read as granted, and flutter_blue_plus asks for
  /// location itself when the scan starts).
  static List<Permission> get _bluetoothPermissions =>
      defaultTargetPlatform == TargetPlatform.android
          ? const [Permission.bluetoothScan, Permission.bluetoothConnect]
          : const [Permission.bluetooth];

  Future<bool> _ensureBluetoothPermission() async {
    final perms = _bluetoothPermissions;
    final statuses = <Permission, PermissionStatus>{
      for (final p in perms) p: await p.status,
    };
    debugPrint('Bluetooth permission: $statuses');

    if (statuses.values.every((s) => s.isGranted)) return true;

    if (statuses.values.any((s) => s.isPermanentlyDenied)) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _permDenied = true;
          _error = defaultTargetPlatform == TargetPlatform.android
              ? 'Nearby devices permission was denied. '
                  'Tap "Open Settings" to allow it, then tap Rescan.'
              : 'Bluetooth permission was denied. '
                  'Tap "Open Settings" to enable it, then tap Rescan.';
        });
      }
      return false;
    }

    final missing = [
      for (final e in statuses.entries)
        if (!e.value.isGranted) e.key
    ];
    final results = await missing.request();
    if (results.values.every((s) => s.isGranted)) return true;

    if (mounted) {
      setState(() {
        _scanning = false;
        _permDenied = results.values.any((s) => s.isPermanentlyDenied);
        _error = defaultTargetPlatform == TargetPlatform.android
            ? 'Nearby devices permission is needed to find radios.'
            : 'Bluetooth permission is required to scan for devices.';
      });
    }
    return false;
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _connecting = false;
      _error = null;
      _failure = null;
      _permDenied = false;
      _scanResults.clear();
      _systemDevices.clear();
    });

    try {
      // 1. Check the Bluetooth permission (iOS) / nearby devices (Android)
      final hasPermission = await _ensureBluetoothPermission();
      if (!hasPermission || !mounted) return;

      // 2. Wait for adapter to be ready
      final currentState = _scanner.adapterStateNow;
      debugPrint('BLE adapter state: $currentState');

      if (currentState == RadioAdapterState.unknown ||
          currentState == RadioAdapterState.turningOn) {
        try {
          await _scanner.adapterState
              .firstWhere((s) =>
                  s != RadioAdapterState.unknown &&
                  s != RadioAdapterState.turningOn)
              .timeout(const Duration(seconds: 10));
        } on TimeoutException {
          debugPrint('BLE adapter did not settle, proceeding anyway');
        }
      }

      if (!mounted) return;

      if (_scanner.adapterStateNow == RadioAdapterState.off) {
        // Android can ask to switch it on (system dialog); iOS can't.
        final on = _scanner.canTurnOn && await _scanner.turnOn();
        if (!mounted) return;
        if (!on) {
          setState(() {
            _error = 'Bluetooth is off. Turn it on, then tap Rescan.';
            _scanning = false;
          });
          return;
        }
      }

      // 3. Scan for radios advertising the Meshtastic service or MeshCore's
      // (each result is tagged with its protocol)
      debugPrint('Starting BLE scan...');

      final scan = _scanner.scan(
        serviceUuids: RadioServices.all,
        timeout: _scanTimeout,
      );
      final scanDone = Completer<void>();
      _scanSubscription = scan.listen(
        (results) {
          if (!mounted) return;
          setState(() {
            for (final r in results) {
              final exists = _scanResults.any((e) => e.id == r.id) ||
                  _systemDevices.any((d) => d.id == r.id);
              if (!exists) {
                debugPrint('Found device: ${r.name} (${r.id})');
                _scanResults.add(r);
              }
            }
          });
        },
        onError: scanDone.completeError,
        onDone: scanDone.complete,
      );

      try {
        final system = await _scanner.systemDevices(
          RadioServices.all,
          known: LastRadio(ref.read(sharedPreferencesProvider)).knownRadios(),
        );
        if (mounted) setState(() => _systemDevices.addAll(system));
      } catch (e) {
        debugPrint('systemDevices failed: $e');
      }

      // The scan ends by itself after the timeout.
      await scanDone.future;

      debugPrint('Scan complete, found ${_scanResults.length} devices');
    } catch (e, stack) {
      debugPrint('BLE scan error: $e');
      debugPrint('Stack: $stack');
      if (!mounted) return;
      setState(() {
        _error = userMessage(e, doing: 'scanning for nodes');
      });
    } finally {
      _scanSubscription?.cancel();
      _scanSubscription = null;
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  /// Connecting the phone to the base is usually a mix-up: ask first.
  Future<bool> _confirmBase(RadioDescriptor device) async {
    if (ref.read(radioRolesProvider).roleOfDevice(device.id) !=
        RadioRole.base) {
      return true;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('That\'s your base node'),
        content: const Text(
          'Mapping needs the phone connected to the node you carry (the '
          'mobile). Connect to your mobile instead?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Use it anyway'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Pick the mobile'),
          ),
        ],
      ),
    );
    return ok == true && mounted;
  }

  /// Switching radios while a session records: the session keeps going on
  /// the new radio, but pings stop if it is on the public channel.
  Future<bool> _confirmSwitchWhileRecording(RadioDescriptor device) async {
    if (ref.read(activeSessionProvider).valueOrNull == null) return true;
    final current = ref.read(meshRadioProvider).descriptor?.id ??
        ref.read(radioRolesProvider).deviceOf(RadioRole.mobile);
    if (current == null || current == device.id) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch nodes while recording?'),
        content: const Text(
          'The session keeps recording with this node. Pings stop if it is '
          'on the public channel; run Node Setup on it first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
    return ok == true && mounted;
  }

  Future<void> _connectToDevice(RadioDescriptor device) async {
    // MeshCore radios are free (Andy, 2026-11-05), like Meshtastic ones.
    // Another protocol means another radio object, which a recording
    // session on this protocol can't follow.
    final phoneRadio = ref.read(meshRadioProvider);
    final blocked = phoneRadio is SwitchableRadio
        ? phoneRadio.whyCantSwitchTo(device.protocol)
        : null;
    if (blocked != null) {
      setState(() => _error = blocked);
      return;
    }
    if (!await _confirmBase(device)) return;
    if (!await _confirmSwitchWhileRecording(device)) return;
    setState(() {
      _error = null;
      _failure = null;
      _connecting = true;
    });

    try {
      await _scanner.stopScan();
      debugPrint('Connecting to ${device.name} (${device.id})...');

      // Connect + config handshake (switching protocol first if the radio
      // speaks another one). On first connect iOS shows the Bluetooth
      // pairing prompt; enter the radio's PIN there.
      final radio = ref.read(meshRadioProvider);
      await radio.connect(device);
      debugPrint('Radio ready');

      // A base not yet known by Bluetooth id: say so after connecting.
      final roles = ref.read(radioRolesProvider);
      final knownBefore = roles.roleOfDevice(device.id) == RadioRole.base;
      if (!knownBefore &&
          roles.roleOfNode(radio.myNodeId) == RadioRole.base &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Connected to your base node. For mapping, '
              'connect to the node you carry.'),
          duration: Duration(seconds: 6),
        ));
      }

      // Out-of-the-box radio: choose its region first, as the official
      // app does.
      final meshtastic = radioAs<MeshtasticRadio>(radio);
      if (meshtastic != null && meshtastic.regionUnset && mounted) {
        await showRegionDialog(context, meshtastic, newRadio: true);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Connection error: $e');
      if (mounted) {
        setState(() {
          _connecting = false;
          _failure = connectFailure(e, device);
        });
      }
    }
  }

  /// Role chip and, for MeshCore radios, a protocol tag.
  Widget? _trailing(RadioDescriptor device) {
    final role = ref.watch(radioRolesProvider).roleOfDevice(device.id);
    final meshCore = device.protocol == RadioProtocol.meshcore;
    if (!meshCore) return role == null ? null : RoleChip(role);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ProtocolTag(RadioProtocol.meshcore),
        if (role != null) ...[const SizedBox(width: 4), RoleChip(role)],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Not dismissable while connecting (a half-made connection would be
    // left behind); the height follows the content, up to most of the
    // screen.
    return PopScope(
        canPop: !_connecting,
        child: AlertDialog(
          title: const Text('Connect to a node'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.6),
            child: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_connecting)
                    const ConnectProgressView()
                  else if (_scanning)
                    const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('Scanning for nodes…'),
                        ),
                      ],
                    )
                  else if (_scanResults.isEmpty &&
                      _systemDevices.isEmpty &&
                      _error == null &&
                      _failure == null)
                    const Text('No nodes found. Make sure the node is on and '
                        'nearby, then tap Rescan.'),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ),
                  if (_failure case final f?)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: ConnectFailureView(f),
                    ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _systemDevices.length + _scanResults.length,
                      itemBuilder: (context, index) {
                        if (index < _systemDevices.length) {
                          final device = _systemDevices[index];
                          return ListTile(
                            leading: const Icon(Icons.bluetooth_connected),
                            title: Text(device.name.isNotEmpty
                                ? device.name
                                : 'Unnamed node'),
                            subtitle:
                                const Text('Already connected to this phone'),
                            trailing: _trailing(device),
                            onTap: _connecting
                                ? null
                                : () => _connectToDevice(device),
                          );
                        }
                        final device =
                            _scanResults[index - _systemDevices.length];
                        final name = device.name.isNotEmpty
                            ? device.name
                            : 'Unnamed node';
                        final rssi = device.scanRssi;
                        return ListTile(
                          leading: const Icon(Icons.bluetooth),
                          title: Text(name),
                          subtitle: Text('Signal $rssi dBm'),
                          trailing: _trailing(device),
                          onTap: _connecting
                              ? null
                              : () => _connectToDevice(device),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _connecting ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            if (_permDenied)
              TextButton(
                onPressed: () => openAppSettings(),
                child: const Text('Open Settings'),
              ),
            TextButton(
              onPressed: (_scanning || _connecting) ? null : _startScan,
              child: const Text('Rescan'),
            ),
          ],
        ));
  }
}
