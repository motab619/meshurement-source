// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/data/radio/radio_preset.dart';
import 'package:mesh_analyzer/utils/link_margin.dart';
import 'package:mesh_analyzer/utils/signal_color_mapper.dart';

void main() {
  group('sensitivity', () {
    test('matches the SX1262 datasheet at 125 kHz', () {
      expect(MarginScale.of(RadioPreset.custom(7, 125, 5)).sensitivityDbm,
          closeTo(-124.5, 0.1));
      expect(MarginScale.of(RadioPreset.custom(12, 125, 5)).sensitivityDbm,
          closeTo(-137.0, 0.1));
    });

    test('wider bandwidth is less sensitive', () {
      // LONG_FAST: SF11 / 250 kHz.
      expect(MarginScale.of(MeshtasticPresets.longFast).sensitivityDbm,
          closeTo(-131.5, 0.1));
    });
  });

  group('linkMarginDb', () {
    final shortFast = MarginScale.of(MeshtasticPresets.shortFast); // SF7
    final longFast = MarginScale.of(MeshtasticPresets.longFast); // SF11

    test('a strong SF7 reading reaches Strong through RSSI', () {
      // Reported SNR tops out near +12 dB: 19.5 dB of SNR margin only.
      expect(12 - shortFast.snrFloorDb, lessThan(20));
      final m = shortFast.marginDb(snr: 12, rssi: -70)!;
      expect(m, greaterThanOrEqualTo(20));
      expect(MarginBand.of(m), MarginBand.strong);
    });

    test('a weak reading keeps its SNR margin', () {
      // Below +5 dB SNR the link is noise-limited: RSSI is ignored.
      expect(shortFast.marginDb(snr: -3, rssi: -60), -3 - -7.5);
      expect(longFast.marginDb(snr: -10, rssi: -80), 7.5);
    });

    test('RSSI never lowers the SNR margin', () {
      // SNR 8 on LONG_FAST: 25.5 dB; -120 dBm is only 11.5 above -131.5.
      expect(longFast.marginDb(snr: 8, rssi: -120), 25.5);
    });

    test('no jump where SNR stops being informative', () {
      // MEDIUM_FAST-like scale; RSSI far above sensitivity.
      double m(double snr) =>
          linkMarginDb(snr: snr, rssi: -90, scale: shortFast)!;
      expect(m(4.9), closeTo(4.9 - shortFast.snrFloorDb, 1e-9));
      expect((m(5.0) - m(4.9)).abs(), lessThan(1.0));
      for (var s = 5.0; s < 10; s += 0.1) {
        expect(m(s + 0.1) - m(s), lessThan(8.0), reason: 'step at $s dB');
      }
      expect(m(10), closeTo(-90 - shortFast.sensitivityDbm, 1e-9));
    });

    test('missing fields', () {
      expect(longFast.marginDb(), isNull);
      expect(longFast.marginDb(snr: 2), 19.5);
      expect(longFast.marginDb(snr: 8), 25.5);
      expect(longFast.marginDb(rssi: -121.5), closeTo(10, 0.1));
      // RSSI 0 is "not reported".
      expect(longFast.marginDb(snr: 8, rssi: 0), 25.5);
      expect(longFast.marginDb(rssi: 0), isNull);
    });

    test('unknown preset falls back to LONG_FAST', () {
      expect(MarginScale.forPresetId(''), MarginScale.fallback);
      expect(MarginScale.forPresetId('NOT_A_PRESET'), MarginScale.fallback);
      expect(
          MarginScale.fallback.snrFloorDb, SignalColorMapper.defaultSnrFloorDb);
      expect(MarginScale.forPresetId('LONG_FAST'), longFast);
      expect(linkMarginDb(snr: -7.5), 10);
    });

    test('demo site: MEDIUM_FAST readings near the base are Strong', () {
      // lib/demo/cove_data.dart, first rows of the stubby drive (SF9).
      final mf = MarginScale.of(MeshtasticPresets.mediumFast);
      for (final (snr, rssi) in [(11.5, -48), (12.0, -64), (12.5, -89)]) {
        expect(MarginBand.of(mf.marginDb(snr: snr, rssi: rssi)!),
            MarginBand.strong);
      }
      // Farther out, SNR +3 at -109 dBm: SNR margin 15.5 (Good).
      expect(MarginBand.of(mf.marginDb(snr: 3, rssi: -109)!), MarginBand.good);
    });
  });

  test('one band scale: Strong 20+, Good 10-20, Weak 0-10, Below limit', () {
    expect(MarginBand.of(20), MarginBand.strong);
    expect(MarginBand.of(19.9), MarginBand.good);
    expect(MarginBand.of(10), MarginBand.good);
    expect(MarginBand.of(0), MarginBand.weak);
    expect(MarginBand.of(-0.1), MarginBand.below);
    expect(MarginBand.strong.colour, SignalColorMapper.fromMargin(20));
    expect(MarginBand.below.colour, SignalColorMapper.fromMargin(0));
  });
}
