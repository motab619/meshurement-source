// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';

import 'package:mesh_analyzer/proto/meshtastic/channel.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;

import '../radio_types.dart';
import 'meshtastic_presets.dart';

/// One region's band plan as the firmware's `regions[]` table has it.
class _Band {
  final double start;
  final double end;

  /// dBm the firmware caps transmit power at (unlicensed).
  final int powerLimit;

  /// Gap between slots (MHz, 2.8 region profile).
  final double spacing;

  /// Gap at each side of a slot (MHz, 2.8 region profile).
  final double padding;

  /// 2.8 `override_slot`: > 0 a fixed 1-based default slot, 0 the channel
  /// name hash, -1 the preset name hash.
  final int overrideSlot;

  /// 2.4 GHz band: presets run at wider bandwidths.
  final bool wideLora;

  /// Present in firmware 2.7.26's table (2.7 has no 2.8-only regions).
  final bool in27;

  const _Band(this.start, this.end, this.powerLimit,
      {this.spacing = 0,
      this.padding = 0,
      this.overrideSlot = 0,
      this.wideLora = false,
      this.in27 = true});
}

/// Works out which frequency slot and centre frequency a Meshtastic radio
/// is on, the way the firmware does.
///
/// Source: meshtastic/firmware `src/mesh/RadioInterface.cpp`
/// `applyModemConfig` (v2.7.26.54e0d8d l.845-871, v2.8.1.8e6a88d
/// l.1342-1394), `hash()` (djb2: h = 5381; h = h * 33 + byte, uint32), the
/// `regions[]` RDEF tables and the 2.8 `RegionProfile`s (spacing/padding),
/// `Channels::getName` (empty name → preset display name, "Custom" without
/// a preset) and `DisplayFormatters::getModemPresetDisplayName`.
///
/// Firmware 2.8:
///   width  = spacing + 2·padding + bw/1000            (MHz)
///   slots  = round((end − start + spacing) / width)
///   slot0  = channel_num − 1 if channel_num is set (and in range), else
///            override_slot − 1 for regions with a fixed default slot,
///            else djb2(primary channel name) % slots
///   freq   = start + bw/2000 + padding + slot0 · width
/// Firmware 2.7 (and unknown firmware on a 2.7-table region):
///   slots  = floor((end − start) / (bw/1000))
///   slot0  = (channel_num ? channel_num − 1 : djb2(name)) % slots
///   freq   = start + bw/2000 + slot0 · bw/1000
/// `override_frequency` replaces the frequency (no slot); the firmware adds
/// `frequency_offset` either way. Slots are reported 1-based (slot0 + 1),
/// as `channel_num` and the Meshtastic apps number them: LongFast in the
/// US is slot 20, 906.875 MHz.
class MeshtasticFrequency {
  MeshtasticFrequency._();

  static const _lite = (spacing: 0.4, padding: 0.0375);
  static const _narrow = 0.0104;
  static const _ham20 = 0.0022;
  static const _ham100 = 0.01875;

  static final Map<String, _Band> _bands = {
    'US': const _Band(902.0, 928.0, 30),
    'EU_433': const _Band(433.0, 434.0, 10),
    'EU_868': const _Band(869.4, 869.65, 27),
    'EU_866': _Band(865.6, 867.6, 27,
        spacing: _lite.spacing, padding: _lite.padding, in27: false),
    'EU_N_868': const _Band(869.4, 869.65, 27,
        padding: _narrow, overrideSlot: 1, in27: false),
    'CN': const _Band(470.0, 510.0, 19),
    'JP': const _Band(920.5, 923.5, 13),
    'ANZ': const _Band(915.0, 928.0, 30),
    'ANZ_433': const _Band(433.05, 434.79, 14),
    'RU': const _Band(868.7, 869.2, 20),
    'KR': const _Band(920.0, 923.0, 23),
    'TW': const _Band(920.0, 925.0, 27),
    'IN': const _Band(865.0, 867.0, 30),
    'NZ_865': const _Band(864.0, 868.0, 36),
    'TH': const _Band(920.0, 925.0, 27),
    'UA_433': const _Band(433.0, 434.7, 10),
    // 2.7.26 only; 2.8.1 dropped it from the table.
    'UA_868': const _Band(868.0, 868.6, 14),
    'MY_433': const _Band(433.0, 435.0, 20),
    'MY_919': const _Band(919.0, 924.0, 27),
    'SG_923': const _Band(917.0, 925.0, 20),
    'PH_433': const _Band(433.0, 434.7, 10),
    'PH_868': const _Band(868.0, 869.4, 14),
    'PH_915': const _Band(915.0, 918.0, 24),
    'KZ_433': const _Band(433.075, 434.775, 10),
    'KZ_863': const _Band(863.0, 868.0, 30),
    'NP_865': const _Band(865.0, 868.0, 30),
    'BR_902': const _Band(902.0, 907.5, 30),
    'ITU1_2M': const _Band(144.0, 146.0, 30,
        padding: _ham20, overrideSlot: 26, in27: false),
    'ITU2_2M': const _Band(144.0, 148.0, 30,
        padding: _ham20, overrideSlot: 51, in27: false),
    'ITU3_2M': const _Band(144.0, 148.0, 30,
        padding: _ham20, overrideSlot: 33, in27: false),
    'ITU2_125CM': const _Band(220.0, 225.0, 30,
        padding: _ham100, overrideSlot: 37, in27: false),
    'ITU1_70CM': const _Band(430.0, 440.0, 30,
        padding: _ham100, overrideSlot: 37, in27: false),
    'ITU2_70CM': const _Band(420.0, 450.0, 30,
        padding: _ham100, overrideSlot: 137, in27: false),
    'ITU3_70CM': const _Band(430.0, 450.0, 30,
        padding: _ham100, overrideSlot: 37, in27: false),
    'LORA_24': const _Band(2400.0, 2483.5, 10, wideLora: true),
  };

  /// djb2, as the firmware's `hash()` (uint32 arithmetic over the UTF-8
  /// bytes of [s]).
  static int djb2(String s) {
    var h = 5381;
    for (final c in utf8.encode(s)) {
      h = (h * 33 + c) & 0xffffffff;
    }
    return h;
  }

  /// The firmware's display name for a preset, which an unnamed primary
  /// channel hashes as ("LongFast", "MediumSlow", "LongMod"...).
  static String presetHashName(pb.Config_LoRaConfig lora) {
    if (!lora.usePreset) return 'Custom';
    return switch (lora.modemPreset) {
      pb.Config_LoRaConfig_ModemPreset.SHORT_TURBO => 'ShortTurbo',
      pb.Config_LoRaConfig_ModemPreset.SHORT_SLOW => 'ShortSlow',
      pb.Config_LoRaConfig_ModemPreset.SHORT_FAST => 'ShortFast',
      pb.Config_LoRaConfig_ModemPreset.MEDIUM_SLOW => 'MediumSlow',
      pb.Config_LoRaConfig_ModemPreset.MEDIUM_FAST => 'MediumFast',
      pb.Config_LoRaConfig_ModemPreset.LONG_SLOW => 'LongSlow',
      pb.Config_LoRaConfig_ModemPreset.LONG_FAST => 'LongFast',
      pb.Config_LoRaConfig_ModemPreset.LONG_TURBO => 'LongTurbo',
      pb.Config_LoRaConfig_ModemPreset.LONG_MODERATE => 'LongMod',
      pb.Config_LoRaConfig_ModemPreset.LITE_FAST => 'LiteFast',
      pb.Config_LoRaConfig_ModemPreset.LITE_SLOW => 'LiteSlow',
      pb.Config_LoRaConfig_ModemPreset.NARROW_FAST => 'NarrowFast',
      pb.Config_LoRaConfig_ModemPreset.NARROW_SLOW => 'NarrowSlow',
      _ => 'Invalid',
    };
  }

  /// Settings of a radio with [lora] whose primary channel is
  /// [primaryChannel]. [firmware28] picks the 2.8 slot formula; null
  /// (unknown firmware) uses 2.8 too, the current release. Returns null
  /// without a region.
  static RadioSettings? settingsFor(
    pb.Config_LoRaConfig? lora, {
    pb.Channel? primaryChannel,
    bool? firmware28,
  }) {
    if (lora == null) return null;
    final region = lora.region == pb.Config_LoRaConfig_RegionCode.UNSET
        ? ''
        : lora.region.name;
    final band = _bands[region];
    final hopLimit = lora.hopLimit > 0 ? lora.hopLimit : null;
    final txPower = lora.txPower > 0
        ? lora.txPower
        : band?.powerLimit; // 0 = the region's limit (firmware)

    int? slot;
    double? freq;
    if (lora.overrideFrequency > 0) {
      freq = lora.overrideFrequency + lora.frequencyOffset;
    } else if (band != null) {
      final r = _slotAndFrequency(lora, band, primaryChannel,
          firmware28: firmware28 ?? true);
      if (r != null) {
        slot = r.slot;
        freq = r.freq + lora.frequencyOffset;
      }
    }
    if (slot == null && freq == null && lora.channelNum > 0) {
      slot = lora.channelNum;
    }
    if (freq != null) freq = (freq * 1000).roundToDouble() / 1000;
    return RadioSettings(
      region: region,
      frequencySlot: slot,
      txPowerDbm: txPower,
      hopLimit: hopLimit,
      frequencyMHz: freq,
    );
  }

  static ({int slot, double freq})? _slotAndFrequency(
    pb.Config_LoRaConfig lora,
    _Band band,
    pb.Channel? primary, {
    required bool firmware28,
  }) {
    final preset = MeshtasticPresets.fromConfig(lora);
    if (preset == null) return null;
    var bw = preset.bwKHz;
    if (band.wideLora) {
      final double? wide = switch (bw) {
        500.0 => 1625.0,
        250.0 => 812.5,
        125.0 => 406.25,
        _ => null,
      };
      if (wide == null) return null;
      bw = wide;
    }
    final name = primary?.settings.name ?? '';
    final hashName = name.isNotEmpty ? name : presetHashName(lora);
    final h = djb2(hashName);
    final use28 = firmware28 || !band.in27;

    if (use28) {
      final width = band.spacing + band.padding * 2 + bw / 1000;
      final slots =
          ((band.end - band.start + band.spacing) / width + 1e-9).round();
      if (slots <= 0) return null;
      final int slot0;
      final n = lora.channelNum;
      if (n > 0 && n <= slots) {
        slot0 = n - 1;
      } else if (band.overrideSlot > 0) {
        slot0 = band.overrideSlot - 1;
      } else if (band.overrideSlot < 0) {
        slot0 = djb2(presetHashName(lora)) % slots;
      } else {
        slot0 = h % slots;
      }
      return (
        slot: slot0 + 1,
        freq: band.start + bw / 2000 + band.padding + slot0 * width,
      );
    }
    final slots = ((band.end - band.start) / (bw / 1000) + 1e-9).floor();
    if (slots <= 0) return null;
    final n = lora.channelNum;
    final slot0 = (n > 0 ? n - 1 : h) % slots;
    return (slot: slot0 + 1, freq: band.start + bw / 2000 + slot0 * bw / 1000);
  }
}
