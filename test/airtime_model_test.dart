// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/services/airtime_model.dart';

void main() {
  test('LONG_FAST ping is about 559 ms, min interval 12 s', () {
    expect(AirtimeModel.pingAirtimeMs(MeshtasticPresets.longFast),
        closeTo(559, 5));
    expect(AirtimeModel.minIntervalSec(MeshtasticPresets.longFast), 12);
  });

  test('LONG_SLOW is about 3023 ms, min interval 61 s', () {
    expect(AirtimeModel.pingAirtimeMs(MeshtasticPresets.longSlow),
        closeTo(3023, 5));
    expect(AirtimeModel.minIntervalSec(MeshtasticPresets.longSlow), 61);
  });

  test('SHORT_TURBO hits the 5 s floor', () {
    expect(AirtimeModel.minIntervalSec(MeshtasticPresets.shortTurbo), 5);
  });

  test('VERY_LONG_SLOW falls back to LONG_FAST', () {
    final p = MeshtasticPresets.fromModemPreset(
        pb.Config_LoRaConfig_ModemPreset.VERY_LONG_SLOW);
    expect(AirtimeModel.pingAirtimeMs(p),
        AirtimeModel.pingAirtimeMs(MeshtasticPresets.longFast));
  });

  test('NARROW_SLOW (SF8 / 62.5 kHz / 4/6) is 386.048 ms, min interval 8 s',
      () {
    // Hand calculation, 40-byte ping, 16-symbol preamble, explicit header,
    // CRC on:
    //   Tsym     = 2^8 / 62.5 kHz             = 4.096 ms (< 16 ms: LDRO off)
    //   preamble = (16 + 4.25) × 4.096        = 82.944 ms
    //   payload  = 8 + ceil((8×40 − 4×8 + 28 + 16) / (4×8)) × 6
    //            = 8 + ceil(332 / 32) × 6 = 8 + 11 × 6 = 74 symbols
    //            = 74 × 4.096                 = 303.104 ms
    //   total    = 82.944 + 303.104           = 386.048 ms
    //   interval = ceil(0.386048 s / 5%)      = ceil(7.72) = 8 s
    expect(AirtimeModel.pingAirtimeMs(MeshtasticPresets.narrowSlow),
        closeTo(386.048, 1e-6));
    expect(AirtimeModel.minIntervalSec(MeshtasticPresets.narrowSlow), 8);
  });

  test('LITE_SLOW (SF10 / 125 kHz / 4/5) is 600.064 ms, min interval 13 s', () {
    //   Tsym = 1024 / 125 = 8.192 ms (LDRO off); preamble 20.25 × 8.192
    //   = 165.888 ms; payload 8 + ceil(324 / 40) × 5 = 53 symbols
    //   = 434.176 ms; total 600.064 ms; ceil(12.001) = 13 s.
    expect(AirtimeModel.pingAirtimeMs(MeshtasticPresets.liteSlow),
        closeTo(600.064, 1e-6));
    expect(AirtimeModel.minIntervalSec(MeshtasticPresets.liteSlow), 13);
  });

  test('NARROW_FAST (SF7 / 62.5 kHz / 4/6) is 205.312 ms', () {
    //   Tsym = 128 / 62.5 = 2.048 ms; preamble 41.472 ms; payload
    //   8 + ceil(336 / 28) × 6 = 80 symbols = 163.84 ms.
    expect(AirtimeModel.pingAirtimeMs(MeshtasticPresets.narrowFast),
        closeTo(205.312, 1e-6));
  });

  test('62.5 kHz switches LDRO on once a symbol exceeds 16 ms', () {
    // Custom SF10 / 62.5 kHz / 4/5: Tsym = 1024 / 62.5 = 16.384 ms, so
    // LDRO is on and the payload divisor is 4 × (10 − 2) = 32:
    //   preamble 20.25 × 16.384 = 331.776 ms
    //   payload  8 + ceil(324 / 32) × 5 = 8 + 11 × 5 = 63 symbols
    //            = 1032.192 ms; total 1363.968 ms.
    // (LDRO off would give 8 + ceil(324 / 40) × 5 = 53 symbols.)
    final custom = MeshtasticPresets.fromConfig(pb.Config_LoRaConfig(
      usePreset: false,
      spreadFactor: 10,
      bandwidth: 62, // firmware code for 62.5 kHz
      codingRate: 5,
    ))!;
    expect(custom.bwKHz, 62.5);
    expect(AirtimeModel.pingAirtimeMs(custom), closeTo(1363.968, 1e-6));
  });

  test('airtime ordering across preset families', () {
    double air(p) => AirtimeModel.pingAirtimeMs(p);
    // NARROW_SLOW's symbol (SF8 / 62.5 kHz = 4.1 ms) is half LONG_FAST's
    // (SF11 / 250 kHz = 8.2 ms), so its ping is shorter on air, not longer.
    expect(air(MeshtasticPresets.longSlow),
        greaterThan(air(MeshtasticPresets.liteSlow)));
    expect(air(MeshtasticPresets.liteSlow),
        greaterThan(air(MeshtasticPresets.longFast)));
    expect(air(MeshtasticPresets.longFast),
        greaterThan(air(MeshtasticPresets.narrowSlow)));
    expect(air(MeshtasticPresets.narrowSlow),
        greaterThan(air(MeshtasticPresets.narrowFast)));
    expect(air(MeshtasticPresets.narrowFast),
        greaterThan(air(MeshtasticPresets.shortTurbo)));
  });

  test('custom SF12/BW125/CR8 equals LONG_SLOW', () {
    final custom = MeshtasticPresets.fromConfig(pb.Config_LoRaConfig(
      usePreset: false,
      spreadFactor: 12,
      bandwidth: 125,
      codingRate: 8,
    ));
    expect(AirtimeModel.pingAirtimeMsFor(custom),
        AirtimeModel.pingAirtimeMs(MeshtasticPresets.longSlow));
    expect(AirtimeModel.minIntervalSecFor(custom), 61);
  });

  test('unknown radio uses the LONG_FAST numbers', () {
    expect(AirtimeModel.pingAirtimeMsFor(null),
        AirtimeModel.pingAirtimeMs(MeshtasticPresets.longFast));
    expect(AirtimeModel.minIntervalSecFor(null), 12);
  });

  test('clampInterval keeps a larger request and raises a smaller one', () {
    expect(AirtimeModel.clampInterval(300, MeshtasticPresets.longSlow), 300);
    expect(AirtimeModel.clampInterval(15, MeshtasticPresets.longSlow), 61);
  });

  test('"Faster than recommended" drops to the physical floor', () {
    // Long Fast: ~0.6 s per ping → ACK round trip + 1 s margin = 3 s,
    // instead of the 12 s airtime budget.
    final fast = AirtimeModel.fastestIntervalSecFor(MeshtasticPresets.longFast);
    expect(fast,
        lessThan(AirtimeModel.minIntervalSec(MeshtasticPresets.longFast)));
    expect(fast, greaterThanOrEqualTo(AirtimeModel.overrideFloorSec));
    expect(
        AirtimeModel.minIntervalSecFor(MeshtasticPresets.longFast,
            override: true),
        fast);
    // Never below 2 s, even on the fastest preset.
    expect(AirtimeModel.fastestIntervalSecFor(MeshtasticPresets.shortTurbo),
        AirtimeModel.overrideFloorSec);
    // Slow presets still need time for the ping and ACK to go out.
    final slowAir = AirtimeModel.pingAirtimeMs(MeshtasticPresets.longSlow);
    expect(AirtimeModel.fastestIntervalSecFor(MeshtasticPresets.longSlow),
        greaterThan(2 * slowAir / 1000));
  });

  test('dutyFor is airtime over interval', () {
    final air = AirtimeModel.pingAirtimeMs(MeshtasticPresets.longFast);
    expect(AirtimeModel.dutyFor(MeshtasticPresets.longFast, 10),
        closeTo(air / 10000, 1e-9));
    expect(AirtimeModel.dutyFor(MeshtasticPresets.longFast, 0), 0);
  });
}
