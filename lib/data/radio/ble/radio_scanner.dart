// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../radio_types.dart';
import 'radio_services.dart';

/// Phone Bluetooth adapter state (mirrors the platform's, without the
/// plugin type).
enum RadioAdapterState {
  unknown,
  unavailable,
  unauthorized,
  turningOn,
  on,
  turningOff,
  off,
}

/// Finds radios over Bluetooth LE. Together with `BleTransport`, the only
/// code that touches flutter_blue_plus.
class RadioScanner {
  /// Demo mode never touches Bluetooth (no permission prompt): the adapter
  /// reads as on and nothing is scanned.
  final bool demo;

  RadioScanner({this.demo = false});

  static RadioAdapterState _map(BluetoothAdapterState s) => switch (s) {
        BluetoothAdapterState.unknown => RadioAdapterState.unknown,
        BluetoothAdapterState.unavailable => RadioAdapterState.unavailable,
        BluetoothAdapterState.unauthorized => RadioAdapterState.unauthorized,
        BluetoothAdapterState.turningOn => RadioAdapterState.turningOn,
        BluetoothAdapterState.on => RadioAdapterState.on,
        BluetoothAdapterState.turningOff => RadioAdapterState.turningOff,
        BluetoothAdapterState.off => RadioAdapterState.off,
      };

  Stream<RadioAdapterState> get adapterState => demo
      ? Stream.value(RadioAdapterState.on)
      : FlutterBluePlus.adapterState.map(_map);

  RadioAdapterState get adapterStateNow =>
      demo ? RadioAdapterState.on : _map(FlutterBluePlus.adapterStateNow);

  /// Show the platform's Bluetooth permission prompt now (the welcome
  /// flow's Permissions page). iOS: reading the adapter state creates the
  /// central manager, which is what triggers the prompt. Android 12+: the
  /// adapter state needs no permission, so ask for Nearby devices (scan +
  /// connect) explicitly; [RadioAdapterState.unauthorized] when refused.
  /// Later calls, and demo mode, do nothing visible.
  Future<RadioAdapterState> requestPermission() async {
    if (demo) return RadioAdapterState.on;
    if (Platform.isAndroid) {
      final result = await const [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      if (!result.values.every((s) => s.isGranted)) {
        return RadioAdapterState.unauthorized;
      }
    }
    return _map(await FlutterBluePlus.adapterState.first);
  }

  /// Android: whether Nearby devices (scan + connect) is granted, without
  /// asking (on Android 11 and older both read as granted). Null elsewhere
  /// and in demo mode, where the adapter state tells.
  Future<bool?> nearbyDevicesGranted() async {
    if (demo || !Platform.isAndroid) return null;
    return await Permission.bluetoothScan.isGranted &&
        await Permission.bluetoothConnect.isGranted;
  }

  Stream<bool> get isScanning =>
      demo ? Stream.value(false) : FlutterBluePlus.isScanning;

  /// Whether [turnOn] can switch Bluetooth on from the app (Android only;
  /// iOS has no API for it).
  bool get canTurnOn => !demo && Platform.isAndroid;

  /// Android: show the system "turn on Bluetooth?" dialog and wait for the
  /// adapter to come on. True when it is on; false when the user said no,
  /// it timed out, or the platform can't ([canTurnOn]).
  Future<bool> turnOn() async {
    if (!canTurnOn) return false;
    try {
      await FlutterBluePlus.turnOn(timeout: 30);
      return true;
    } catch (e) {
      print('RadioScanner: turnOn refused: $e');
      return false;
    }
  }

  /// Tagged with the protocol its advertised services belong to, else by
  /// name (MeshCore companions advertise as `MeshCore-` + node name,
  /// examples/companion_radio/MyMesh.h:66 at MeshCore 81dbae5); a radio
  /// matching neither counts as Meshtastic, as before MeshCore was scanned
  /// for.
  ///
  /// Both names are checked for the MeshCore prefix: the platform's cached
  /// name (Android's `BluetoothDevice.getName()`, iOS's `peripheral.name`)
  /// can still be the old firmware's after a reflash, and the advertised
  /// one may be shortened. The cached name is shown when there is one.
  static RadioDescriptor _describe(ScanResult r) {
    final adv = r.advertisementData.advName;
    final cached = r.device.platformName;
    final name = cached.isNotEmpty ? cached : adv;
    return RadioDescriptor(
      id: r.device.remoteId.str,
      name: name,
      protocol: RadioServices.protocolFor(
              r.advertisementData.serviceUuids.map((g) => g.str128)) ??
          RadioServices.protocolForName(adv) ??
          RadioServices.protocolForName(cached) ??
          RadioProtocol.meshtastic,
      scanRssi: r.rssi,
    );
  }

  /// Scan for radios advertising any of [serviceUuids]. Emits the radios
  /// found so far (one entry per radio) whenever a new one appears and
  /// completes when the scan ends ([timeout]) or the listener cancels.
  Stream<List<RadioDescriptor>> scan({
    required List<String> serviceUuids,
    Duration timeout = const Duration(seconds: 15),
  }) {
    late final StreamController<List<RadioDescriptor>> controller;
    StreamSubscription<List<ScanResult>>? sub;

    Future<void> run() async {
      final found = <String, RadioDescriptor>{};
      sub = FlutterBluePlus.onScanResults.listen((results) {
        var changed = false;
        for (final r in results) {
          final d = _describe(r);
          if (!found.containsKey(d.id)) {
            print('RadioScanner: found ${d.name} (${d.id})');
            changed = true;
          }
          found[d.id] = d;
        }
        if (changed && !controller.isClosed) {
          controller.add(found.values.toList());
        }
      });
      try {
        // startScan returns as soon as scanning starts; wait for it to end.
        await FlutterBluePlus.startScan(
          withServices: serviceUuids.map(Guid.new).toList(),
          timeout: timeout,
        );
        await FlutterBluePlus.isScanning.where((s) => !s).first;
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      } finally {
        await sub?.cancel();
        sub = null;
        if (!controller.isClosed) await controller.close();
      }
    }

    controller = StreamController<List<RadioDescriptor>>(
      onListen: () {
        if (demo) {
          controller.close();
        } else {
          run();
        }
      },
      onCancel: () async {
        await sub?.cancel();
        sub = null;
        if (!demo) await FlutterBluePlus.stopScan();
      },
    );
    return controller.stream;
  }

  /// Radios already connected to the phone at the system level (e.g. by
  /// another app). They stop advertising, so a scan alone won't find them.
  /// Asked one service at a time so each radio is tagged with its protocol.
  ///
  /// Android ignores the service filter and lists every GATT device the
  /// phone is connected to (watches, earbuds), which can't be told apart
  /// without connecting. There only radios in [known] (Bluetooth id ->
  /// protocol, null = tell by name: the last radio and the Radio Setup
  /// roles) are listed.
  /// `FlutterBluePlus.bondedDevices` is no better a source: MeshCore
  /// companions bond too (PIN pairing), the list holds every paired
  /// headset and car, and a bonded radio that has stopped advertising
  /// can't be connected anyway.
  Future<List<RadioDescriptor>> systemDevices(
    List<String> serviceUuids, {
    Map<String, RadioProtocol?> known = const {},
  }) async {
    if (demo) return const [];
    if (Platform.isAndroid) {
      if (known.isEmpty) return const [];
      final devices = await FlutterBluePlus.systemDevices(const []);
      return [
        for (final d in devices)
          if (known.containsKey(d.remoteId.str))
            RadioDescriptor(
              id: d.remoteId.str,
              name: d.platformName,
              protocol: known[d.remoteId.str] ??
                  RadioServices.protocolForName(d.platformName) ??
                  RadioProtocol.meshtastic,
            ),
      ];
    }
    final found = <String, RadioDescriptor>{};
    for (final uuid in serviceUuids) {
      final protocol =
          RadioServices.protocolFor([uuid]) ?? RadioProtocol.meshtastic;
      final devices = await FlutterBluePlus.systemDevices([Guid(uuid)]);
      for (final d in devices) {
        found.putIfAbsent(
          d.remoteId.str,
          () => RadioDescriptor(
            id: d.remoteId.str,
            name: d.platformName,
            protocol: protocol,
          ),
        );
      }
    }
    return found.values.toList();
  }

  Future<void> stopScan() async {
    if (demo) return;
    await FlutterBluePlus.stopScan();
  }
}
