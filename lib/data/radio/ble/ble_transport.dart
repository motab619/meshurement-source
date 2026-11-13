// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../services/diag_log.dart';
import 'radio_transport.dart';

export 'radio_transport.dart';

/// The Bluetooth LE link to one radio, for any protocol that exposes a
/// GATT service with a few characteristics (Meshtastic's own service,
/// MeshCore's Nordic UART Service). This is the only place that talks to
/// flutter_blue_plus for connections; protocol code sits on top of it.
class BleTransport implements RadioTransport {
  /// GATT service the radio speaks, e.g. Meshtastic's.
  final String serviceUuid;

  /// Characteristics the protocol needs (all must exist on the service).
  final List<String> characteristicUuids;

  /// Name used in error messages ("Meshtastic service not found").
  final String protocolName;

  BleTransport({
    required this.serviceUuid,
    required this.characteristicUuids,
    this.protocolName = 'radio',
  });

  BluetoothDevice? _device;
  final Map<Guid, BluetoothCharacteristic> _chars = {};

  /// Android only: the bond (pairing) state of the radio, logged so a
  /// cancelled or mistyped PIN shows up in diag.log ("bonding -> none").
  StreamSubscription<BluetoothBondState>? _bondSub;

  /// Bluetooth name of the connected radio, if known.
  @override
  String get platformName => _device?.platformName ?? '';

  /// Open the Bluetooth connection to the radio with platform id [deviceId].
  @override
  Future<void> connect(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final device = BluetoothDevice.fromId(deviceId);
    _device = device;
    // mtu: 512 is applied on Android only (flutter_blue_plus calls
    // requestMtu right after the link is up); iOS negotiates MTU itself.
    // autoConnect stays false (the default): a direct connection that
    // fails fast, and MeshtasticRadio/MeshCoreRadio retry with backoff.
    try {
      await device.connect(
        timeout: timeout,
        mtu: Platform.isAndroid ? 512 : null,
      );
    } on FlutterBluePlusException catch (e) {
      // Android's catch-all GATT 133 often clears on a second try (a scan
      // just stopped, a stale link being torn down); the plugin has
      // already closed the failed GATT client.
      if (!Platform.isAndroid || e.code != _androidGattError) rethrow;
      DiagLog.instance.log('ble', 'connect: GATT 133, retrying once');
      await Future<void>.delayed(const Duration(seconds: 1));
      await device.connect(timeout: timeout, mtu: 512);
    } catch (e) {
      // Android: the link came up and dropped again before the plugin's
      // requestMtu ("device is disconnected"). The stack's reason (logcat:
      // "Encryption failure 6" = the phone's bond no longer matches the
      // radio's keys, after a reflash) only shows as a disconnect code
      // here, so log what there is for diag.log and rethrow.
      if (Platform.isAndroid) {
        DiagLog.instance.log('ble',
            'connect failed: $e; disconnect reason: ${device.disconnectReason}');
      }
      rethrow;
    }
    if (Platform.isAndroid) _watchBond(device);
  }

  /// Android's GATT_ERROR / ANDROID_SPECIFIC_ERROR (0x85).
  static const _androidGattError = 133;

  /// Android only: drop the phone's pairing record for the radio with
  /// platform id [deviceId], so the next connect pairs afresh. The way out
  /// when the radio lost its keys (a factory flash on an ESP32; firmware 2.8's
  /// first boot) while the phone kept its bond: every connect then fails
  /// with "Encryption failure 6" (HCI key missing) in the Bluetooth stack
  /// and the plugin reports the link gone before requestMtu. iOS offers no
  /// equivalent (Settings → Bluetooth → Forget This Device by hand).
  /// Returns false when not on Android or no bond existed.
  static Future<bool> removeBond(String deviceId) async {
    if (!Platform.isAndroid) return false;
    final device = BluetoothDevice.fromId(deviceId);
    final before = await device.bondState.first;
    if (before == BluetoothBondState.none) return false;
    await device.removeBond();
    DiagLog.instance.log('ble', 'bond removed for $deviceId');
    return true;
  }

  /// Android pairs on the first access to an encrypted characteristic (the
  /// stack retries the GATT operation once bonded, like iOS), so nothing
  /// is driven from here; the states only go to the diagnostics log.
  void _watchBond(BluetoothDevice device) {
    _bondSub?.cancel();
    BluetoothBondState? last;
    _bondSub = device.bondState.listen((s) {
      if (s == last) return;
      DiagLog.instance
          .log('ble', 'bond ${last?.name ?? 'start'} -> ${s.name}');
      last = s;
    }, onError: (Object e) {});
  }

  /// Discover services and find the protocol's characteristics.
  @override
  Future<void> discover() async {
    final device = _device;
    if (device == null) throw StateError('Not connected to a node');
    final wanted = Guid(serviceUuid);
    var services = await device.discoverServices();
    if (Platform.isAndroid && !services.any((s) => s.serviceUuid == wanted)) {
      // Android keeps a bonded radio's GATT table across connections; after
      // a reflash (Meshtastic <-> MeshCore on the same board) it can hand
      // back the old firmware's services. Drop the cache and look again.
      DiagLog.instance.log('ble', '$protocolName service missing: '
          'clearing the GATT cache');
      try {
        await device.clearGattCache();
        services = await device.discoverServices();
      } catch (e) {
        DiagLog.instance.log('ble', 'GATT cache refresh failed: $e');
      }
    }
    final service = services.firstWhere(
      (s) => s.serviceUuid == wanted,
      orElse: () => throw StateError('$protocolName service not found'),
    );
    _chars.clear();
    for (final uuid in characteristicUuids) {
      final guid = Guid(uuid);
      _chars[guid] = service.characteristics.firstWhere(
        (c) => c.characteristicUuid == guid,
        orElse: () => throw StateError('Missing characteristic $guid'),
      );
    }
  }

  BluetoothCharacteristic _char(String uuid) {
    final c = _chars[Guid(uuid)];
    if (c == null) throw StateError('Not connected to a node');
    return c;
  }

  /// Calls [onLost] when the link drops (not for our own [disconnect]
  /// being awaited by the caller; callers filter with a generation
  /// counter). Cancel the returned subscription on teardown.
  @override
  StreamSubscription<void> listenLinkLost(void Function() onLost) {
    final device = _device;
    if (device == null) throw StateError('Not connected to a node');
    return device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) onLost();
    });
  }

  /// Enable notifications on [uuid]. The first access to an encrypted
  /// characteristic shows the system PIN prompt (iOS; Android too, as a
  /// dialog or a "Pairing request" notification), so [timeout] should
  /// allow time to type it.
  @override
  Future<void> setNotify(String uuid, {required Duration timeout}) =>
      _char(uuid).setNotifyValue(true, timeout: timeout.inSeconds);

  /// Notification payloads of [uuid].
  @override
  Stream<List<int>> notifications(String uuid) => _char(uuid).onValueReceived;

  @override
  Future<List<int>> read(String uuid) => _char(uuid).read();

  /// Write with response (one write per message, no framing).
  @override
  Future<void> write(
    String uuid,
    List<int> data, {
    Duration timeout = const Duration(seconds: 15),
  }) =>
      _char(uuid).write(
        data,
        withoutResponse: false,
        timeout: timeout.inSeconds,
      );

  /// Forget the characteristics (after a link loss or before reconnecting).
  @override
  void clearCharacteristics() => _chars.clear();

  @override
  Future<void> disconnect() async {
    await _bondSub?.cancel();
    _bondSub = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
  }
}
