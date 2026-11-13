// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesh_analyzer/services/terrain/default_elevation_source.dart';
import 'package:mesh_analyzer/services/terrain/elevation_source.dart';

class _Counting implements ElevationSource {
  int calls = 0;
  @override
  String get name => 'fake';
  @override
  Future<List<double?>> elevations(List<LatLng> points) async {
    calls++;
    return [for (final _ in points) 10.0];
  }
}

void main() {
  test('disabled: throws ElevationDisabled and never reaches the network',
      () async {
    final inner = _Counting();
    final dir = Directory.systemTemp.createTempSync('elev');
    addTearDown(() => dir.deleteSync(recursive: true));
    var on = false;
    final src = DefaultElevationSource(
        enabled: () => on, inner: inner, cacheDir: Future.value(dir));
    await expectLater(
        src.elevations([const LatLng(1, 2)]),
        throwsA(isA<ElevationDisabled>().having(
            (e) => e.message, 'message', contains('terrain elevation'))));
    expect(inner.calls, 0);
    on = true;
    expect(await src.elevations([const LatLng(1, 2)]), [10.0]);
    expect(inner.calls, 1);
  });
}
