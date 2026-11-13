// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

/// LoRa modulation settings, independent of protocol: a Meshtastic named
/// preset, a MeshCore SF/BW/CR setting or a custom one.
class RadioPreset {
  /// Stable id: the protocol's preset name (e.g. "LONG_FAST") or "CUSTOM".
  final String id;

  /// Human name, e.g. "Long Fast".
  final String displayName;
  final int sf;
  final double bwKHz;

  /// Coding-rate denominator: 5 means 4/5, 8 means 4/8.
  final int cr;

  /// Still accepted but on its way out of the firmware.
  final bool deprecated;

  const RadioPreset({
    required this.id,
    required this.displayName,
    required this.sf,
    required this.bwKHz,
    required this.cr,
    this.deprecated = false,
  });

  /// A non-preset setting.
  factory RadioPreset.custom(int sf, double bwKHz, int cr) => RadioPreset(
        id: 'CUSTOM',
        displayName: 'Custom (SF$sf / ${_bw(bwKHz)} kHz / 4/$cr)',
        sf: sf,
        bwKHz: bwKHz,
        cr: cr,
      );

  static String _bw(double b) =>
      b == b.roundToDouble() ? b.toInt().toString() : b.toString();

  /// "Long Slow (deprecated)" style label for pickers (the display name
  /// may already say so).
  String get label => deprecated && !displayName.contains('deprecated')
      ? '$displayName (deprecated)'
      : displayName;

  @override
  bool operator ==(Object other) =>
      other is RadioPreset &&
      other.id == id &&
      other.sf == sf &&
      other.bwKHz == bwKHz &&
      other.cr == cr;

  @override
  int get hashCode => Object.hash(id, sf, bwKHz, cr);

  /// Lowest SNR (dB) a packet on this preset can be decoded at: the
  /// SX126x/SX127x demodulator limit for the spreading factor (-7.5 dB at
  /// SF7, 2.5 dB lower per step; LONG_FAST SF11 = -17.5 dB). Link margin
  /// is SNR minus this; strong readings also use RSSI above the preset's
  /// sensitivity (`MarginScale` in `lib/utils/link_margin.dart`).
  double get snrFloorDb => -7.5 - 2.5 * (sf - 7);

  @override
  String toString() => 'RadioPreset($id SF$sf/${_bw(bwKHz)}/4/$cr)';
}
