// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/services/airtime_meter.dart';

void main() {
  test('duty sums airtime over the 60 s window', () {
    final meter = AirtimeMeter();
    addTearDown(meter.dispose);
    final now = DateTime.now();
    meter.record(600, at: now);
    meter.record(1200, at: now.subtract(const Duration(seconds: 10)));
    expect(meter.duty, closeTo(1800 / 60000, 1e-9));
  });

  test('entries older than 60 s drop out', () {
    final meter = AirtimeMeter();
    addTearDown(meter.dispose);
    final now = DateTime.now();
    meter.record(3000, at: now.subtract(const Duration(seconds: 61)));
    meter.record(600, at: now);
    expect(meter.duty, closeTo(600 / 60000, 1e-9));
  });

  test('dutyStream emits on record', () async {
    final meter = AirtimeMeter();
    addTearDown(meter.dispose);
    final first = meter.dutyStream.first;
    meter.record(6000);
    expect(await first, closeTo(0.1, 1e-3));
  });
}
