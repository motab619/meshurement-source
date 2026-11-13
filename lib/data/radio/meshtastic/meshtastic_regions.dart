// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;

/// A LoRa region a Meshtastic radio can be set to. [code] is the protobuf
/// `RegionCode` name (what `MeshRadio.regionName` reports).
class MeshtasticRegion {
  final String code;
  final String label;

  const MeshtasticRegion(this.code, this.label);

  pb.Config_LoRaConfig_RegionCode get pbCode =>
      pb.Config_LoRaConfig_RegionCode.values.firstWhere((r) => r.name == code);
}

/// Region choices, as the firmware defines them (`config.proto`), most
/// common first. The amateur 2 m bands need a ham licence.
class MeshtasticRegions {
  static const all = [
    MeshtasticRegion('US', 'United States, Canada, Mexico (915 MHz)'),
    MeshtasticRegion('EU_868', 'Europe, UK (868 MHz)'),
    MeshtasticRegion('ANZ', 'Australia, New Zealand (915 MHz)'),
    MeshtasticRegion('BR_902', 'Brazil (902 MHz)'),
    MeshtasticRegion('JP', 'Japan (920 MHz)'),
    MeshtasticRegion('KR', 'Korea (920 MHz)'),
    MeshtasticRegion('TW', 'Taiwan (920 MHz)'),
    MeshtasticRegion('CN', 'China (470 MHz)'),
    MeshtasticRegion('IN', 'India (865 MHz)'),
    MeshtasticRegion('RU', 'Russia (868 MHz)'),
    MeshtasticRegion('UA_868', 'Ukraine (868 MHz)'),
    MeshtasticRegion('UA_433', 'Ukraine (433 MHz)'),
    MeshtasticRegion('TH', 'Thailand (920 MHz)'),
    MeshtasticRegion('SG_923', 'Singapore (923 MHz)'),
    MeshtasticRegion('MY_919', 'Malaysia (919 MHz)'),
    MeshtasticRegion('MY_433', 'Malaysia (433 MHz)'),
    MeshtasticRegion('PH_915', 'Philippines (915 MHz)'),
    MeshtasticRegion('PH_868', 'Philippines (868 MHz)'),
    MeshtasticRegion('PH_433', 'Philippines (433 MHz)'),
    MeshtasticRegion('NZ_865', 'New Zealand (865 MHz)'),
    MeshtasticRegion('NP_865', 'Nepal (865 MHz)'),
    MeshtasticRegion('KZ_863', 'Kazakhstan (863 MHz)'),
    MeshtasticRegion('KZ_433', 'Kazakhstan (433 MHz)'),
    MeshtasticRegion('EU_433', 'Europe (433 MHz)'),
    MeshtasticRegion('EU_866', 'Europe, SRD band (866 MHz)'),
    MeshtasticRegion('EU_874', 'Europe, SRD band (874 MHz)'),
    MeshtasticRegion('EU_917', 'Europe, SRD band (917 MHz)'),
    MeshtasticRegion('EU_N_868', 'Europe, narrow presets (868 MHz)'),
    MeshtasticRegion('ANZ_433', 'Australia, New Zealand (433 MHz)'),
    MeshtasticRegion('LORA_24', 'Worldwide 2.4 GHz (2.4 GHz radios only)'),
    MeshtasticRegion('ITU1_2M', 'Ham 2 m, ITU Region 1 (licence needed)'),
    MeshtasticRegion('ITU2_2M', 'Ham 2 m, ITU Region 2 (licence needed)'),
    MeshtasticRegion('ITU3_2M', 'Ham 2 m, ITU Region 3 (licence needed)'),
    MeshtasticRegion('ITU2_125CM', 'Ham 1.25 m, ITU Region 2 (licence needed)'),
    MeshtasticRegion('ITU1_70CM', 'Ham 70 cm, ITU Region 1 (licence needed)'),
    MeshtasticRegion('ITU2_70CM', 'Ham 70 cm, ITU Region 2 (licence needed)'),
    MeshtasticRegion('ITU3_70CM', 'Ham 70 cm, ITU Region 3 (licence needed)'),
  ];

  static MeshtasticRegion? byCode(String code) {
    for (final r in all) {
      if (r.code == code) return r;
    }
    return null;
  }

  /// A starting guess from the phone's country (ISO 3166 code, e.g. from
  /// the locale). The user still confirms it. US when unknown.
  static MeshtasticRegion guessFor(String? countryCode) {
    final cc = countryCode?.toUpperCase();
    final code = switch (cc) {
      'AU' || 'NZ' => 'ANZ',
      'BR' => 'BR_902',
      'JP' => 'JP',
      'KR' => 'KR',
      'TW' => 'TW',
      'CN' => 'CN',
      'IN' => 'IN',
      'RU' => 'RU',
      'UA' => 'UA_868',
      'TH' => 'TH',
      'SG' => 'SG_923',
      'MY' => 'MY_919',
      'PH' => 'PH_915',
      'NP' => 'NP_865',
      'KZ' => 'KZ_863',
      _ when cc != null && _europe.contains(cc) => 'EU_868',
      _ => 'US',
    };
    return byCode(code)!;
  }

  static const _europe = {
    'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', //
    'HU', 'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK',
    'SI', 'ES', 'SE', 'GB', 'NO', 'CH', 'IS', 'LI', 'RS', 'BA', 'ME', 'MK',
    'AL', 'MD',
  };
}
