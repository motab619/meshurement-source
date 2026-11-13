// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/services/export/geojson.dart';

import 'fixture.dart';

void main() {
  late ExportFixture f;
  setUp(() async => f = await ExportFixture.create());
  tearDown(() => f.db.close());

  test('valid FeatureCollection with lon,lat points and one track', () async {
    final text = buildGeoJson([await f.session(f.session1)]);
    final j = jsonDecode(text) as Map<String, dynamic>;
    expect(j['type'], 'FeatureCollection');
    final feats = (j['features'] as List).cast<Map<String, dynamic>>();
    final points = feats.where((x) => x['geometry']['type'] == 'Point');
    final lines = feats.where((x) => x['geometry']['type'] == 'LineString');
    // 3 positioned events (the unpositioned rx is skipped), 1 track.
    expect(points, hasLength(3));
    expect(lines, hasLength(1));
    expect(points.first['geometry']['coordinates'], [-116.24, 33.68]);
    expect(points.first['properties']['source_node_id'], '!0000a1b2');
    expect(lines.first['geometry']['coordinates'], hasLength(3));
    expect(lines.first['geometry']['coordinates'].first, [-116.24, 33.68]);
  });

  test('a session with one fix has a point but no track', () async {
    final j = buildGeoJsonMap([await f.session(f.session2)]);
    final feats = j['features'] as List;
    expect(feats, hasLength(1));
  });

  test('several sessions: one track each', () async {
    final j = buildGeoJsonMap(
        [await f.session(f.session1), await f.session(f.session2)]);
    final feats = (j['features'] as List).cast<Map>();
    expect(feats.where((x) => x['properties']['kind'] == 'gps_track'),
        hasLength(1));
    expect(feats, hasLength(5));
  });
}
