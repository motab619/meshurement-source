// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import '../radio_types.dart';

/// Bluetooth LE service UUIDs each protocol's radios advertise, and how a
/// scan result is told apart. Plain Dart (no plugin types), so tests and
/// protocol code can use it.
class RadioServices {
  RadioServices._();

  /// Meshtastic's own GATT service.
  static const meshtastic = '6ba1b218-15a8-461f-9fa8-5dcae273eafd';

  /// MeshCore companion radios: the Nordic UART Service.
  static const meshCore = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

  /// NUS RX: the phone writes frames here.
  static const meshCoreRx = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

  /// NUS TX: the radio notifies frames here.
  static const meshCoreTx = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  /// Service UUID [protocol]'s radios advertise.
  static String serviceFor(RadioProtocol protocol) => switch (protocol) {
        RadioProtocol.meshtastic => meshtastic,
        RadioProtocol.meshcore => meshCore,
      };

  /// Every protocol's service, for a scan that finds both kinds.
  static const all = [meshtastic, meshCore];

  /// The protocol of a radio advertising [serviceUuids] (128-bit strings,
  /// any case). Null when none is ours.
  static RadioProtocol? protocolFor(Iterable<String> serviceUuids) {
    final ids = {for (final u in serviceUuids) u.toLowerCase()};
    if (ids.contains(meshtastic)) return RadioProtocol.meshtastic;
    if (ids.contains(meshCore)) return RadioProtocol.meshcore;
    return null;
  }

  /// Advertised-name prefix of MeshCore companions.
  static const meshCoreNamePrefix = 'MeshCore-';

  /// The protocol a radio's Bluetooth [name] gives away, if any.
  static RadioProtocol? protocolForName(String name) =>
      name.startsWith(meshCoreNamePrefix) ? RadioProtocol.meshcore : null;
}
