// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_presets.dart';
import 'package:mesh_analyzer/data/radio/radio_preset.dart';
import 'package:mesh_analyzer/utils/signal_color_mapper.dart';

void main() {
  test('decode limit follows the spreading factor', () {
    expect(MeshtasticPresets.shortFast.snrFloorDb, -7.5); // SF7
    expect(MeshtasticPresets.mediumSlow.snrFloorDb, -15); // SF10
    expect(MeshtasticPresets.longFast.snrFloorDb, -17.5); // SF11
    expect(RadioPreset.custom(12, 125, 5).snrFloorDb, -20); // SF12
  });

  test('the same SNR is comfortable on LONG_FAST and at the limit on '
      'SHORT_FAST', () {
    final longFast = SignalColorMapper.fromSnr(-7.5,
        floorDb: MeshtasticPresets.longFast.snrFloorDb);
    final shortFast = SignalColorMapper.fromSnr(-7.5,
        floorDb: MeshtasticPresets.shortFast.snrFloorDb);
    expect(longFast, SignalColorMapper.fromMargin(10)); // yellow
    expect(shortFast, SignalColorMapper.fromMargin(0)); // red
    expect(longFast, isNot(shortFast));
  });

  test('margin ramp: red at 0, yellow at 10, green from 20', () {
    expect(SignalColorMapper.fromMargin(-5), SignalColorMapper.fromMargin(0));
    expect(SignalColorMapper.fromMargin(30), SignalColorMapper.fromMargin(20));
    expect(SignalColorMapper.fromMargin(20).g,
        greaterThan(SignalColorMapper.fromMargin(20).r));
    expect(SignalColorMapper.fromMargin(0).r,
        greaterThan(SignalColorMapper.fromMargin(0).g));
  });

  test('unknown preset uses the LONG_FAST limit', () {
    expect(SignalColorMapper.fromSnr(0),
        SignalColorMapper.fromSnr(0, floorDb: -17.5));
  });
}
