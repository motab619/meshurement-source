// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;

import '../radio_preset.dart';
import '../radio_types.dart' show parseFirmwareVersion;

/// Meshtastic modem presets as protocol-neutral [RadioPreset]s.
///
/// Preset parameters are the firmware's own table, `modemPresetToParams`
/// in meshtastic/firmware src/mesh/MeshRadio.h (non-wide LoRa):
/// v2.7.26.54e0d8d lines 132-181 for the classic presets, v2.8.2.d5f1619
/// lines 215-299 for the rest (MEDIUM_TURBO, LITE_*, NARROW_*, TINY_*).
/// Firmware 2.7.26 has no case for LITE_*/NARROW_* (they hit `default:`
/// and run as LONG_FAST); 2.8 implements them. We use the real 2.8
/// parameters: a radio that reports one is either really running it (2.8+)
/// or, on 2.7, running LONG_FAST, which is the longer airtime for NARROW_*,
/// so the ping floor errs short there (see the airtime tests).
/// MEDIUM_TURBO and TINY_* exist only from 2.8 (protobufs v2.8.2): the
/// pickers leave out MEDIUM_TURBO for a radio known to run older firmware
/// ([presetsForRegion]), and TINY_* belong to the 2.8-only ham 2 m regions.
class MeshtasticPresets {
  MeshtasticPresets._();

  static const shortTurbo = RadioPreset(
      id: 'SHORT_TURBO', displayName: 'Short Turbo', sf: 7, bwKHz: 500, cr: 5);
  static const shortFast = RadioPreset(
      id: 'SHORT_FAST', displayName: 'Short Fast', sf: 7, bwKHz: 250, cr: 5);
  static const shortSlow = RadioPreset(
      id: 'SHORT_SLOW', displayName: 'Short Slow', sf: 8, bwKHz: 250, cr: 5);
  static const mediumFast = RadioPreset(
      id: 'MEDIUM_FAST', displayName: 'Medium Fast', sf: 9, bwKHz: 250, cr: 5);

  /// 2.8+: Medium Fast's spreading factor on 500 kHz.
  static const mediumTurbo = RadioPreset(
      id: 'MEDIUM_TURBO',
      displayName: 'Medium Turbo',
      sf: 9,
      bwKHz: 500,
      cr: 5);
  static const mediumSlow = RadioPreset(
      id: 'MEDIUM_SLOW', displayName: 'Medium Slow', sf: 10, bwKHz: 250, cr: 5);
  static const longTurbo = RadioPreset(
      id: 'LONG_TURBO', displayName: 'Long Turbo', sf: 11, bwKHz: 500, cr: 8);
  static const longFast = RadioPreset(
      id: 'LONG_FAST', displayName: 'Long Fast', sf: 11, bwKHz: 250, cr: 5);
  static const longModerate = RadioPreset(
      id: 'LONG_MODERATE',
      displayName: 'Long Moderate',
      sf: 11,
      bwKHz: 125,
      cr: 8);

  /// Deprecated in 2.7 (config.proto) but still implemented by the
  /// firmware, and older sessions were recorded with it.
  static const longSlow = RadioPreset(
      id: 'LONG_SLOW',
      displayName: 'Long Slow (deprecated)',
      sf: 12,
      bwKHz: 125,
      cr: 8,
      deprecated: true);

  /// Deprecated in 2.5; the firmware has no case for it (2.7.26 and 2.8.1
  /// both fall through to `default:`), so it runs as LONG_FAST.
  static const veryLongSlow = RadioPreset(
      id: 'VERY_LONG_SLOW',
      displayName: 'Very Long Slow (deprecated)',
      sf: 11,
      bwKHz: 250,
      cr: 5,
      deprecated: true);

  /// EU 866 MHz SRD band (region EU_866), 125 kHz.
  static const liteFast = RadioPreset(
      id: 'LITE_FAST', displayName: 'Lite Fast', sf: 9, bwKHz: 125, cr: 5);
  static const liteSlow = RadioPreset(
      id: 'LITE_SLOW', displayName: 'Lite Slow', sf: 10, bwKHz: 125, cr: 5);

  /// EU 868 MHz narrow presets (region EU_N_868), 62.5 kHz.
  static const narrowFast = RadioPreset(
      id: 'NARROW_FAST', displayName: 'Narrow Fast', sf: 7, bwKHz: 62.5, cr: 6);
  static const narrowSlow = RadioPreset(
      id: 'NARROW_SLOW', displayName: 'Narrow Slow', sf: 8, bwKHz: 62.5, cr: 6);

  /// Ham 2 m presets (regions ITU1_2M, ITU2_2M, ITU3_2M), 15.6 kHz, 2.8+.
  static const tinyFast = RadioPreset(
      id: 'TINY_FAST', displayName: 'Tiny Fast', sf: 7, bwKHz: 15.6, cr: 5);
  static const tinySlow = RadioPreset(
      id: 'TINY_SLOW', displayName: 'Tiny Slow', sf: 8, bwKHz: 15.6, cr: 6);

  /// Every preset above, keyed by the protobuf enum.
  static const _byEnum = <pb.Config_LoRaConfig_ModemPreset, RadioPreset>{
    pb.Config_LoRaConfig_ModemPreset.SHORT_TURBO: shortTurbo,
    pb.Config_LoRaConfig_ModemPreset.SHORT_FAST: shortFast,
    pb.Config_LoRaConfig_ModemPreset.SHORT_SLOW: shortSlow,
    pb.Config_LoRaConfig_ModemPreset.MEDIUM_FAST: mediumFast,
    pb.Config_LoRaConfig_ModemPreset.MEDIUM_SLOW: mediumSlow,
    pb.Config_LoRaConfig_ModemPreset.MEDIUM_TURBO: mediumTurbo,
    pb.Config_LoRaConfig_ModemPreset.LONG_TURBO: longTurbo,
    pb.Config_LoRaConfig_ModemPreset.LONG_FAST: longFast,
    pb.Config_LoRaConfig_ModemPreset.LONG_MODERATE: longModerate,
    pb.Config_LoRaConfig_ModemPreset.LONG_SLOW: longSlow,
    pb.Config_LoRaConfig_ModemPreset.VERY_LONG_SLOW: veryLongSlow,
    pb.Config_LoRaConfig_ModemPreset.LITE_FAST: liteFast,
    pb.Config_LoRaConfig_ModemPreset.LITE_SLOW: liteSlow,
    pb.Config_LoRaConfig_ModemPreset.NARROW_FAST: narrowFast,
    pb.Config_LoRaConfig_ModemPreset.NARROW_SLOW: narrowSlow,
    pb.Config_LoRaConfig_ModemPreset.TINY_FAST: tinyFast,
    pb.Config_LoRaConfig_ModemPreset.TINY_SLOW: tinySlow,
  };

  /// Every preset that can be offered for testing, longest range first
  /// within each family, the deprecated LONG_SLOW last. Pickers use
  /// [presetsForRegion].
  static const testPresets = [
    longModerate,
    longFast,
    longTurbo,
    mediumSlow,
    mediumFast,
    mediumTurbo,
    shortSlow,
    shortFast,
    shortTurbo,
    liteSlow,
    liteFast,
    narrowSlow,
    narrowFast,
    tinySlow,
    tinyFast,
    longSlow,
  ];

  /// Presets that only firmware 2.8 and later run (2.7 runs them as
  /// LONG_FAST while still reporting them).
  static const firmware28Only = {'MEDIUM_TURBO', 'TINY_FAST', 'TINY_SLOW'};

  // Per-region preset lists: firmware v2.8.2.d5f1619 RadioInterface.cpp
  // PRESETS_STD (l.42-44), PRESETS_EU_868 (l.46-48), PRESETS_LITE (l.52),
  // PRESETS_NARROW (l.54-55), PRESETS_TINY (l.57); region -> profile in
  // the RDEF table (l.101-359): the ham 2 m regions use PROFILE_HAM_20KHZ
  // (TINY_*), 1.25 m and 70 cm PROFILE_HAM_100KHZ (NARROW_*).
  static const _std = {
    'LONG_FAST', 'LONG_SLOW', 'MEDIUM_SLOW', 'MEDIUM_FAST', 'SHORT_SLOW', //
    'SHORT_FAST', 'LONG_MODERATE', 'SHORT_TURBO', 'LONG_TURBO',
    'MEDIUM_TURBO',
  };
  static const _eu868 = {
    'LONG_FAST', 'LONG_SLOW', 'MEDIUM_SLOW', 'MEDIUM_FAST', 'SHORT_SLOW', //
    'SHORT_FAST', 'LONG_MODERATE',
  };
  static const _lite = {'LITE_FAST', 'LITE_SLOW'};
  static const _narrow = {'NARROW_FAST', 'NARROW_SLOW'};
  static const _tiny = {'TINY_FAST', 'TINY_SLOW'};
  static const _ham2m = {'ITU1_2M', 'ITU2_2M', 'ITU3_2M'};
  static const _ham100 = {
    'ITU2_125CM', 'ITU1_70CM', 'ITU2_70CM', 'ITU3_70CM', //
  };

  /// Presets the firmware accepts in region [regionCode] (a `RegionCode`
  /// name, as `MeshRadio.regionName` reports it), in [testPresets] order.
  ///
  /// - EU_868: no 500 kHz presets (its sub-band, 869.4-869.65 MHz, is 250
  ///   kHz wide: 2.7.26 falls back to LONG_FAST, 2.8 refuses them).
  /// - EU_866: only LITE_FAST / LITE_SLOW.
  /// - EU_N_868 and the ham 1.25 m / 70 cm regions: only NARROW_FAST /
  ///   NARROW_SLOW.
  /// - Ham 2 m (ITU*_2M): only TINY_FAST / TINY_SLOW.
  /// - Every other region (US, ANZ...), and an unknown or unset one: the
  ///   standard set, including the 500 kHz presets.
  ///
  /// [firmwareVersion] is the radio's (`RadioCapabilities.firmwareVersion`):
  /// when it is known to be older than 2.8, the 2.8-only presets
  /// ([firmware28Only]) are left out. Unknown firmware keeps them.
  static List<RadioPreset> presetsForRegion(String regionCode,
      {String firmwareVersion = ''}) {
    final allowed = _ham2m.contains(regionCode)
        ? _tiny
        : _ham100.contains(regionCode)
            ? _narrow
            : switch (regionCode) {
                'EU_868' => _eu868,
                'EU_866' => _lite,
                'EU_N_868' => _narrow,
                _ => _std,
              };
    final v = parseFirmwareVersion(firmwareVersion);
    final older = v != null && (v[0] < 2 || (v[0] == 2 && v[1] < 8));
    return [
      for (final p in testPresets)
        if (allowed.contains(p.id) && !(older && firmware28Only.contains(p.id)))
          p,
    ];
  }

  /// The firmware's default preset for [regionCode] (RDEF default column,
  /// v2.8.2 RadioInterface.cpp l.151-349): LITE_FAST for EU_866,
  /// NARROW_SLOW for EU_N_868 and the ham 1.25 m / 70 cm regions,
  /// TINY_FAST for ham 2 m, LONG_FAST elsewhere.
  static RadioPreset defaultForRegion(String regionCode) =>
      _ham2m.contains(regionCode)
          ? tinyFast
          : _ham100.contains(regionCode)
              ? narrowSlow
              : switch (regionCode) {
                  'EU_866' => liteFast,
                  'EU_N_868' => narrowSlow,
                  _ => longFast,
                };

  /// The preset for protobuf [preset]. Every value of the vendored enum is
  /// in the table; only a value newer than our protobufs gets here (the
  /// Dart runtime then usually reads it as LONG_FAST), and is given
  /// LONG_FAST's parameters
  /// (keeping its own id and name), which is also what the firmware's
  /// `default:` case runs for a preset it doesn't know.
  static RadioPreset fromModemPreset(pb.Config_LoRaConfig_ModemPreset preset) =>
      _byEnum[preset] ??
      RadioPreset(
        id: preset.name,
        displayName: _label(preset.name),
        sf: longFast.sf,
        bwKHz: longFast.bwKHz,
        cr: longFast.cr,
      );

  /// The protobuf enum for a preset [id] (null for "CUSTOM"/unknown).
  static pb.Config_LoRaConfig_ModemPreset? toModemPreset(String id) {
    for (final e in pb.Config_LoRaConfig_ModemPreset.values) {
      if (e.name == id) return e;
    }
    return null;
  }

  /// The preset with [id] (e.g. "LONG_FAST"), or null.
  static RadioPreset? fromId(String id) {
    for (final p in _byEnum.values) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Modulation for a radio's LoRa config, honouring custom (non-preset)
  /// settings when the radio has them. Null config → null.
  static RadioPreset? fromConfig(pb.Config_LoRaConfig? lora) {
    if (lora == null) return null;
    if (lora.usePreset || lora.spreadFactor == 0 || lora.bandwidth == 0) {
      return fromModemPreset(lora.modemPreset);
    }
    // Firmware bandwidth codes: 31 → 31.25, 62 → 62.5, 200 → 203.125,
    // 400 → 406.25, 800 → 812.5, 1600 → 1625; others are kHz.
    const codes = {
      31: 31.25,
      62: 62.5,
      200: 203.125,
      400: 406.25,
      800: 812.5,
      1600: 1625.0
    };
    final bw = codes[lora.bandwidth] ?? lora.bandwidth.toDouble();
    final cr = lora.codingRate == 0 ? 5 : lora.codingRate;
    return RadioPreset.custom(lora.spreadFactor, bw, cr);
  }

  /// "Long Fast" from "LONG_FAST".
  static String _label(String name) =>
      name.split('_').map((w) => w[0] + w.substring(1).toLowerCase()).join(' ');
}

/// Readable name for a stored preset id (`MEDIUM_FAST` → "Medium Fast");
/// unknown ids are shown as they are.
String presetDisplayName(String id) =>
    MeshtasticPresets.fromId(id)?.displayName ?? id;
