// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;
import 'dart:ui' show Color;

import '../data/radio/radio_preset.dart';
import '../ui/protocol_text.dart' show presetForId;
import 'signal_color_mapper.dart';

// Link margin: how many dB a reading is above what the radio can still
// decode on its preset. One definition for every map, legend, report,
// export and analysis (RF review 2026-11-10, items 1 and 4).
//
// SNR margin (SNR minus the preset's decode limit) is the right measure
// near the edge of range, but SX126x/SX127x packet SNR stops rising at
// about +10 to +13 dB once the signal is well above the noise. On an SF7
// preset (limit -7.5 dB) that caps the margin near 18 to 20 dB, so a
// reading next to the base could never be Strong while LONG_FAST (limit
// -17.5 dB) easily is. From [snrInformativeBelowDb] to [snrSaturatedDb] the margin moves
// from the SNR margin to the larger of it and RSSI above the preset's
// sensitivity ([MarginScale.sensitivityDbm]).

/// Receiver noise figure (dB) used for sensitivity: SX1262/SX1276 class
/// front ends. With it, SF7/125 kHz comes to about -124.5 dBm and
/// SF12/125 kHz about -137 dBm, the Semtech SX1262 datasheet figures.
const receiverNoiseFigureDb = 6.0;

/// Thermal noise density at room temperature, dBm/Hz.
const thermalNoiseDbmPerHz = -174.0;

/// Reported packet SNR at and above which SNR no longer tells strong from
/// very strong: the chip's SNR estimate flattens at roughly +10 to +13 dB,
/// and from about +5 dB up the margin can be read from RSSI instead. Below
/// it the link is noise- or interference-limited, where RSSI (which counts
/// the noise and interference too) overstates the margin, so SNR alone is
/// used.
const snrInformativeBelowDb = 5.0;

/// Reported SNR at and above which the RSSI margin counts in full. Between
/// [snrInformativeBelowDb] and this, the RSSI margin's lead over the SNR
/// margin is phased in linearly, so a reading never jumps a band because
/// its SNR crossed one value (a fixed switch at +5 dB turned 4.9 dB into
/// 17 dB of margin and 5.0 dB into 36 dB on MEDIUM_FAST).
const snrSaturatedDb = 10.0;

/// Bandwidth assumed when the preset is unknown: LONG_FAST's 250 kHz, to go
/// with [SignalColorMapper.defaultSnrFloorDb].
const defaultBandwidthKHz = 250.0;

/// Sensitivity (dBm) of a receiver with decode limit [snrFloorDb] at
/// bandwidth [bwKHz]: noise floor (-174 + 10·log10(BW Hz) + NF) plus the
/// SNR decode limit.
double sensitivityDbmFor(double snrFloorDb, double bwKHz) =>
    thermalNoiseDbmPerHz +
    10 * math.log(bwKHz * 1000) / math.ln10 +
    receiverNoiseFigureDb +
    snrFloorDb;

/// The decode limit and bandwidth margin is measured against: one preset,
/// or the default (LONG_FAST) when the preset is unknown.
class MarginScale {
  /// SNR decode limit, dB ([RadioPreset.snrFloorDb]).
  final double snrFloorDb;
  final double bwKHz;

  const MarginScale({required this.snrFloorDb, required this.bwKHz});

  /// LONG_FAST: the default preset, used when a reading's preset is unknown.
  static const fallback = MarginScale(
      snrFloorDb: SignalColorMapper.defaultSnrFloorDb,
      bwKHz: defaultBandwidthKHz);

  factory MarginScale.of(RadioPreset? preset) => preset == null
      ? fallback
      : MarginScale(snrFloorDb: preset.snrFloorDb, bwKHz: preset.bwKHz);

  /// For a stored preset id (`sessions.lora_preset`), either protocol.
  factory MarginScale.forPresetId(String? id) =>
      MarginScale.of(id == null || id.isEmpty ? null : presetForId(id));

  /// Sensitivity in dBm, see [sensitivityDbmFor].
  double get sensitivityDbm => sensitivityDbmFor(snrFloorDb, bwKHz);

  /// Link margin of a reading, see [linkMarginDb].
  double? marginDb({double? snr, num? rssi}) =>
      linkMarginDb(snr: snr, rssi: rssi, scale: this);

  @override
  bool operator ==(Object other) =>
      other is MarginScale &&
      other.snrFloorDb == snrFloorDb &&
      other.bwKHz == bwKHz;

  @override
  int get hashCode => Object.hash(snrFloorDb, bwKHz);
}

/// Link margin (dB) of one reading:
/// - SNR margin = snr − decode limit;
/// - with snr ≥ [snrInformativeBelowDb] and RSSI known, the SNR margin
///   plus a share of how far rssi − sensitivity is above it: none at
///   [snrInformativeBelowDb], all of it from [snrSaturatedDb] up (SNR has
///   stopped rising), linear in between;
/// - no SNR: rssi − sensitivity; neither: null.
/// An RSSI of 0 means "not reported" (Meshtastic leaves it unset).
double? linkMarginDb({
  double? snr,
  num? rssi,
  MarginScale scale = MarginScale.fallback,
}) {
  final r = (rssi == null || rssi == 0) ? null : rssi.toDouble();
  if (snr == null) return r == null ? null : r - scale.sensitivityDbm;
  final snrMargin = snr - scale.snrFloorDb;
  if (r == null || snr < snrInformativeBelowDb) return snrMargin;
  final lead = r - scale.sensitivityDbm - snrMargin;
  if (lead <= 0) return snrMargin;
  final w =
      ((snr - snrInformativeBelowDb) / (snrSaturatedDb - snrInformativeBelowDb))
          .clamp(0.0, 1.0);
  return snrMargin + w * lead;
}

/// The one margin scale every surface names: legend, Field Report, KML.
/// Colours come from [SignalColorMapper.fromMargin] (red at 0 dB, yellow
/// at 10, green at 20).
enum MarginBand {
  strong('Strong', '20+ dB', '20+', 20),
  good('Good', '10 to 20 dB', '10–20', 10),
  weak('Weak', '0 to 10 dB', '0–10', 0),
  below('Below limit', 'under 0 dB', '<0', null);

  const MarginBand(this.label, this.range, this.shortRange, this.fromDb);
  final String label;

  /// "10 to 20 dB", for sentences and report rows.
  final String range;

  /// "10–20", for the compact legend.
  final String shortRange;

  /// Lower bound in dB (inclusive); null for the open bottom band.
  final double? fromDb;

  /// A margin that shows this band's colour on the ramp.
  double get colourMarginDb => switch (this) {
        strong => 20,
        good => 15,
        weak => 5,
        below => -5,
      };

  Color get colour => SignalColorMapper.fromMargin(colourMarginDb);

  static MarginBand of(double marginDb) => marginDb >= 20
      ? strong
      : marginDb >= 10
          ? good
          : marginDb >= 0
              ? weak
              : below;
}
