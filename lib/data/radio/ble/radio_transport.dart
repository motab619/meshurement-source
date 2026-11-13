// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

/// The byte link to one radio: connect, find the protocol's
/// characteristics, subscribe, write. [BleTransport] is the Bluetooth LE
/// implementation; tests use a scripted fake. Plain Dart (no plugin
/// types), so protocol code and tests can depend on it.
abstract class RadioTransport {
  /// Bluetooth name of the connected radio, if known.
  String get platformName;

  /// Open the link to the radio with platform id [deviceId].
  Future<void> connect(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  });

  /// Find the protocol's service and characteristics.
  Future<void> discover();

  /// Calls [onLost] when the link drops. Cancel the returned subscription
  /// on teardown.
  StreamSubscription<void> listenLinkLost(void Function() onLost);

  /// Enable notifications on [uuid] (may show the iOS pairing prompt).
  Future<void> setNotify(String uuid, {required Duration timeout});

  /// Notification payloads of [uuid].
  Stream<List<int>> notifications(String uuid);

  Future<List<int>> read(String uuid);

  /// Write with response (one write per message, no framing).
  Future<void> write(
    String uuid,
    List<int> data, {
    Duration timeout = const Duration(seconds: 15),
  });

  /// Forget the characteristics (after a link loss or before reconnecting).
  void clearCharacteristics();

  Future<void> disconnect();
}
