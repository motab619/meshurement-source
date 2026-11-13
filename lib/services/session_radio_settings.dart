// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import '../data/database/app_database.dart';
import '../data/radio/radio_types.dart';

/// The radio settings a session recorded at start (schema v9).
extension SessionRadioSettings on Session {
  /// Null on sessions from before v9 or when the radio didn't say.
  RadioSettings? get radioSettings {
    if (region == null &&
        frequencySlot == null &&
        txPowerDbm == null &&
        hopLimit == null &&
        frequencyMhz == null) {
      return null;
    }
    return RadioSettings(
      region: region ?? '',
      frequencySlot: frequencySlot,
      txPowerDbm: txPowerDbm,
      hopLimit: hopLimit,
      frequencyMHz: frequencyMhz,
    );
  }

  /// "Slot 20 · 906.875 MHz · 27 dBm · hops 3"; empty when unknown.
  String get radioSettingsLine => radioSettingsSummary(
        frequencySlot: frequencySlot,
        frequencyMHz: frequencyMhz,
        txPowerDbm: txPowerDbm,
        hopLimit: hopLimit,
      );
}
