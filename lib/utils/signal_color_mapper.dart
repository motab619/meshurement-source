// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:ui';

/// Maps SNR or RSSI values to colors on the green→yellow→red scale.
class SignalColorMapper {
  SignalColorMapper._();

  /// SNR decode limit used when the preset is unknown: LONG_FAST (SF11),
  /// the default preset.
  static const defaultSnrFloorDb = -17.5;

  /// Link margin (dB above the preset's decode limit) at which the ramp is
  /// fully green; 0 dB is red, half of it yellow.
  static const fullMarginDb = 20.0;

  /// Map SNR (dB) to a color by link margin: how far it is above
  /// [floorDb], the decode limit of the preset it was received on
  /// (`RadioPreset.snrFloorDb`). The same SNR means different things on
  /// different presets: -10 dB is comfortable on LONG_FAST and lost on
  /// SHORT_FAST. Red = no margin, yellow = 10 dB of margin, green = 20+.
  static Color fromSnr(double snr, {double floorDb = defaultSnrFloorDb}) =>
      fromMargin(snr - floorDb);

  /// Map a link margin (dB above the decode limit) to a color.
  static Color fromMargin(double marginDb) =>
      _gradientColor(marginDb / fullMarginDb);

  /// Map RSSI (dBm) to a color.
  /// Typical range: -140 (very weak) to -50 (very strong). At the edge of
  /// range RSSI stops falling at the receiver's noise floor (about -105
  /// dBm on a T1000-E) while SNR keeps dropping, so SNR is the better
  /// colour there.
  static Color fromRssi(int rssi) {
    final clamped = rssi.clamp(-140, -30);
    final normalized = (clamped + 140.0) / 110.0;
    return _gradientColor(normalized);
  }

  /// Green (1.0) → Yellow (0.5) → Red (0.0)
  static Color _gradientColor(double normalized) {
    final t = normalized.clamp(0.0, 1.0);
    if (t > 0.5) {
      // Green to Yellow
      final localT = (t - 0.5) * 2.0;
      return Color.lerp(
        const Color(0xFFF1C40F), // Yellow
        const Color(0xFF27AE60), // Green
        localT,
      )!;
    } else {
      // Yellow to Red
      final localT = t * 2.0;
      return Color.lerp(
        const Color(0xFFC0392B), // Red
        const Color(0xFFF1C40F), // Yellow
        localT,
      )!;
    }
  }

  /// Color for "no data" areas
  static const Color noData = Color(0xFFBBBBBB);

  /// Color for "out of range" indicator
  static const Color outOfRange = Color(0xFFC0392B);

  /// Color for "in range" indicator
  static const Color inRange = Color(0xFF27AE60);
}
