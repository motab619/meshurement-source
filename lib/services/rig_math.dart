// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';

import '../data/database/app_database.dart';

/// Coax types with approximate attenuation in dB per metre at 915 MHz.
///
/// Figures are rounded from manufacturer datasheets (Times Microwave LMR
/// series, generic RG data at ~900 MHz, converted from dB/100 ft).
/// 868 MHz (EU) attenuation is about 2-3 % lower (loss scales ~sqrt(f)),
/// i.e. the same within rounding, so one column serves both bands.
class CableType {
  final String key;
  final String label;
  final double lossDbPerM;

  const CableType(this.key, this.label, this.lossDbPerM);
}

const List<CableType> cableTypes = [
  CableType('none', 'None / direct', 0),
  CableType('rg174', 'RG-174', 0.95), // ~29 dB/100 ft
  CableType('rg316', 'RG-316', 0.85), // ~26 dB/100 ft
  CableType('rg58', 'RG-58', 0.50), // ~15 dB/100 ft
  CableType('rg8x', 'RG-8X', 0.38), // ~11.5 dB/100 ft
  CableType('lmr195', 'LMR-195', 0.35), // 10.7 dB/100 ft (Times)
  CableType('lmr240', 'LMR-240', 0.25), // 7.6 dB/100 ft (Times)
  CableType('lmr400', 'LMR-400', 0.128), // 3.9 dB/100 ft (Times)
  CableType('lmr600', 'LMR-600', 0.082), // 2.5 dB/100 ft (Times)
];

CableType cableTypeFor(String key) =>
    cableTypes.firstWhere((c) => c.key == key, orElse: () => cableTypes.first);

/// Radios offered as suggestions in the rig form.
const List<String> supportedRadioModels = [
  'Seeed T1000-E',
  'Heltec V3',
  'Muzi Works H1',
  'RAK4631',
  'T-Echo',
  'T-Beam',
  'Wio Tracker L1',
  'Heltec T114',
];

/// Friendly names for the hardware models radios report (Meshtastic
/// `HardwareModel` names), matching [supportedRadioModels] where they
/// overlap.
const Map<String, String> _radioModelNames = {
  'TRACKER_T1000_E': 'Seeed T1000-E',
  'HELTEC_V3': 'Heltec V3',
  'HELTEC_V4': 'Heltec V4',
  'HELTEC_WSL_V3': 'Heltec Wireless Stick Lite V3',
  'HELTEC_MESH_NODE_T114': 'Heltec T114',
  'HELTEC_WIRELESS_TRACKER': 'Heltec Wireless Tracker',
  'HELTEC_WIRELESS_TRACKER_V1_0': 'Heltec Wireless Tracker',
  'HELTEC_WIRELESS_TRACKER_V2': 'Heltec Wireless Tracker V2',
  'HELTEC_VISION_MASTER_T190': 'Heltec Vision Master T190',
  'HELTEC_VISION_MASTER_E213': 'Heltec Vision Master E213',
  'HELTEC_VISION_MASTER_E290': 'Heltec Vision Master E290',
  'RAK4631': 'RAK4631',
  'RAK11310': 'RAK11310',
  'T_ECHO': 'T-Echo',
  'T_ECHO_LITE': 'T-Echo Lite',
  'TBEAM': 'T-Beam',
  'LILYGO_TBEAM_S3_CORE': 'T-Beam Supreme',
  'TLORA_T3_S3': 'T3-S3',
  'T_DECK': 'T-Deck',
  'SEEED_WIO_TRACKER_L1': 'Wio Tracker L1',
  'SEEED_WIO_TRACKER_L1_EINK': 'Wio Tracker L1 E-Ink',
  'SEEED_XIAO_S3': 'XIAO ESP32-S3',
  'XIAO_NRF52_KIT': 'XIAO nRF52840 Kit',
  'MUZI_BASE': 'Muzi Works Base',
  'MUZI_R1_NEO': 'Muzi Works R1 Neo',
  'STATION_G2': 'Station G2',
  'NANO_G2_ULTRA': 'Nano G2 Ultra',
};

/// Readable radio model for a reported hardware model (e.g.
/// `TRACKER_T1000_E` → "Seeed T1000-E"); unknown ones are tidied up
/// ("SOME_NEW_BOARD" → "Some New Board"). Empty for unknown/unset.
String radioModelName(String hwModel) {
  if (hwModel.isEmpty || hwModel == 'UNSET') return '';
  final known = _radioModelNames[hwModel];
  if (known != null) return known;
  return hwModel
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w.length <= 3 && w.contains(RegExp(r'\d'))
          ? w
          : w[0] + w.substring(1).toLowerCase())
      .join(' ');
}

const String rigRoleMobile = 'mobile';
const String rigRoleBase = 'base';
const String rigRoleEither = 'either';

/// Plain-value copy of a rig, used for maths and for the per-session
/// snapshot so later edits to a profile do not change old sessions.
class RigSpec {
  final int? id;
  final String name;
  final String radioModel;
  final String antennaName;
  final double antennaGainDbi;
  final String cableType;
  final double cableLengthM;
  final int connectorCount;
  final double connectorLossDb;
  final String notes;

  const RigSpec({
    this.id,
    required this.name,
    this.radioModel = '',
    this.antennaName = '',
    this.antennaGainDbi = 0,
    this.cableType = 'none',
    this.cableLengthM = 0,
    this.connectorCount = 0,
    this.connectorLossDb = 0.1,
    this.notes = '',
  });

  factory RigSpec.fromProfile(RigProfile r) => RigSpec(
        id: r.id,
        name: r.name,
        radioModel: r.radioModel,
        antennaName: r.antennaName,
        antennaGainDbi: r.antennaGainDbi,
        cableType: r.cableType,
        cableLengthM: r.cableLengthM,
        connectorCount: r.connectorCount,
        connectorLossDb: r.connectorLossDb,
        notes: r.notes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'radioModel': radioModel,
        'antennaName': antennaName,
        'antennaGainDbi': antennaGainDbi,
        'cableType': cableType,
        'cableLengthM': cableLengthM,
        'connectorCount': connectorCount,
        'connectorLossDb': connectorLossDb,
        'notes': notes,
      };

  factory RigSpec.fromJson(Map<String, dynamic> j) => RigSpec(
        id: (j['id'] as num?)?.toInt(),
        name: j['name'] as String? ?? '',
        radioModel: j['radioModel'] as String? ?? '',
        antennaName: j['antennaName'] as String? ?? '',
        antennaGainDbi: (j['antennaGainDbi'] as num?)?.toDouble() ?? 0,
        cableType: j['cableType'] as String? ?? 'none',
        cableLengthM: (j['cableLengthM'] as num?)?.toDouble() ?? 0,
        connectorCount: (j['connectorCount'] as num?)?.toInt() ?? 0,
        connectorLossDb: (j['connectorLossDb'] as num?)?.toDouble() ?? 0.1,
        notes: j['notes'] as String? ?? '',
      );

  String encode() => jsonEncode(toJson());

  /// Null for null, empty or malformed input.
  static RigSpec? decode(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final v = jsonDecode(json);
      return v is Map<String, dynamic> ? RigSpec.fromJson(v) : null;
    } catch (_) {
      return null;
    }
  }

  double get netGainDb => rigNetGainDb(this);
}

/// Cable attenuation of the rig in dB (positive number).
double cableLossDb(RigSpec r) =>
    r.cableLengthM * cableTypeFor(r.cableType).lossDbPerM;

/// antenna gain - cable length x loss/m - connectors x connector loss, in dB.
double rigNetGainDb(RigSpec r) =>
    r.antennaGainDbi - cableLossDb(r) - r.connectorCount * r.connectorLossDb;

/// Convenience for a drift row.
double netGainDb(RigProfile r) => rigNetGainDb(RigSpec.fromProfile(r));

/// Expected signal difference of [a] over [b] (net gain A minus net gain B).
double expectedDeltaDb(RigSpec a, RigSpec b) =>
    rigNetGainDb(a) - rigNetGainDb(b);

/// "+4.4 dB" / "-1.0 dB".
String formatGainDb(double db) {
  final v = db.abs() < 0.05 ? 0.0 : db;
  return '${v >= 0 ? '+' : '-'}${v.abs().toStringAsFixed(1)} dB';
}
