// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:mesh_analyzer/data/radio/ble/radio_scanner.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';

/// A [RadioScanner] that "finds" [found] at once and never touches
/// Bluetooth (the adapter reads as on).
class FakeRadioScanner extends RadioScanner {
  FakeRadioScanner(this.found) : super(demo: true);

  final List<RadioDescriptor> found;

  /// The service UUIDs of every scan, in order.
  final List<List<String>> scans = [];

  @override
  Stream<List<RadioDescriptor>> scan({
    required List<String> serviceUuids,
    Duration timeout = const Duration(seconds: 15),
  }) {
    scans.add(serviceUuids);
    return Stream.value(found);
  }
}
