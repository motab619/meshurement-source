// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mesh_analyzer/services/terrain/elevation_cache.dart';
import 'package:mesh_analyzer/services/terrain/elevation_source.dart';
import 'package:mesh_analyzer/services/terrain/open_topo_data_source.dart';

List<LatLng> pts(int n, {double lat = 33.0, double lon = -116.0}) =>
    [for (var i = 0; i < n; i++) LatLng(lat + i * 0.001, lon)];

http.Response ok(http.Request r, {double? elev = 123.0}) {
  final locs = r.url.queryParameters['locations']!.split('|');
  return http.Response(
      jsonEncode({
        'status': 'OK',
        'results': [
          for (final _ in locs) {'elevation': elev, 'location': {}},
        ],
      }),
      200);
}

void main() {
  group('OpenTopoDataSource', () {
    test('250 points -> 3 requests (100/100/50)', () async {
      final sizes = <int>[];
      final client = MockClient((r) async {
        sizes.add(r.url.queryParameters['locations']!.split('|').length);
        return ok(r);
      });
      final src = OpenTopoDataSource(
          client: client, delay: (_) async {}, now: () => DateTime.utc(2026));
      final res = await src.elevations(pts(250));
      expect(sizes, [100, 100, 50]);
      expect(res.length, 250);
      expect(res.every((e) => e == 123.0), isTrue);
    });

    test('dataset selection US vs non-US', () async {
      final paths = <String>[];
      final client = MockClient((r) async {
        paths.add(r.url.path);
        return ok(r);
      });
      final src = OpenTopoDataSource(client: client, delay: (_) async {});
      await src.elevations(pts(3)); // California
      await src.elevations(pts(3, lat: 46.5, lon: 7.9)); // Switzerland
      await src.elevations([...pts(2), const LatLng(46.5, 7.9)]); // mixed
      expect(paths, ['/v1/ned10m', '/v1/srtm30m', '/v1/srtm30m']);
    });

    test('ned10m nulls fall back to srtm30m', () async {
      final paths = <String>[];
      final client = MockClient((r) async {
        paths.add(r.url.path);
        return ok(r, elev: r.url.path.endsWith('ned10m') ? null : 55.0);
      });
      final src = OpenTopoDataSource(client: client, delay: (_) async {});
      final res = await src.elevations(pts(3));
      expect(paths, ['/v1/ned10m', '/v1/srtm30m']);
      expect(res, [55.0, 55.0, 55.0]);
    });

    test('throttles to one request per second', () async {
      var t = DateTime.utc(2026);
      final waits = <Duration>[];
      final client = MockClient((r) async => ok(r));
      final src = OpenTopoDataSource(
        client: client,
        now: () => t,
        delay: (d) async {
          waits.add(d);
          t = t.add(d);
        },
      );
      await src.elevations(pts(250));
      expect(waits, [const Duration(seconds: 1), const Duration(seconds: 1)]);
    });

    test('retries once on 503 then succeeds; gives up on second failure',
        () async {
      var n = 0;
      final client = MockClient((r) async {
        n++;
        return n == 1 ? http.Response('x', 503) : ok(r);
      });
      final src = OpenTopoDataSource(client: client, delay: (_) async {});
      expect((await src.elevations(pts(2))).length, 2);
      expect(n, 2);

      final bad = MockClient((r) async => http.Response('x', 429));
      final src2 = OpenTopoDataSource(client: bad, delay: (_) async {});
      await expectLater(
          src2.elevations(pts(2)), throwsA(isA<ElevationUnavailable>()));
    });

    test('offline throws ElevationUnavailable', () async {
      final client =
          MockClient((r) async => throw const SocketException('no route'));
      final src = OpenTopoDataSource(client: client, delay: (_) async {});
      await expectLater(
          src.elevations(pts(2)), throwsA(isA<ElevationUnavailable>()));
    });

    test('daily limit throws ElevationQuotaExceeded, resets next day',
        () async {
      var t = DateTime.utc(2026, 1, 1);
      final client = MockClient((r) async => ok(r));
      final src = OpenTopoDataSource(
          client: client,
          dailyLimit: 2,
          now: () => t,
          delay: (_) async {});
      await src.elevations(pts(150)); // 2 requests
      await expectLater(
          src.elevations(pts(1)), throwsA(isA<ElevationQuotaExceeded>()));
      t = DateTime.utc(2026, 1, 2);
      expect((await src.elevations(pts(1))).length, 1);
    });
  });

  group('CachedElevationSource', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('elevcache'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('cache hit avoids network, persists across instances', () async {
      var requests = 0;
      final client = MockClient((r) async {
        requests++;
        return ok(r, elev: 321.5);
      });
      OpenTopoDataSource mk() =>
          OpenTopoDataSource(client: client, delay: (_) async {});
      final points = pts(50);

      final a = CachedElevationSource(mk(), dir);
      final r1 = await a.elevations(points);
      expect(requests, 1);
      expect(r1.every((e) => e == 321.5), isTrue);

      await a.elevations(points);
      expect(requests, 1);

      // New instance reads from disk; slightly shifted points share cells.
      final b = CachedElevationSource(mk(), dir);
      final r3 = await b.elevations(
          [for (final p in points) LatLng(p.latitude + 0.00001, p.longitude)]);
      expect(requests, 1);
      expect(r3.first, 321.5);
      expect(dir.listSync().whereType<File>().isNotEmpty, isTrue);
    });

    test('only misses are fetched; nulls are not cached', () async {
      final seen = <int>[];
      final inner = _Fn((ps) {
        seen.add(ps.length);
        return [for (final p in ps) p.latitude > 33.0045 ? null : 10.0];
      });
      final c = CachedElevationSource(inner, dir);
      await c.elevations(pts(5));
      expect(seen, [5]);
      // 0.001 deg steps are ~3.6 cells apart so cells are distinct.
      await c.elevations(pts(8));
      // First 5 are cached except the null ones (not cached, retried).
      expect(seen.length, 2);
      expect(seen[1], lessThan(8));
      expect(seen[1], greaterThanOrEqualTo(3));
    });
  });
}

class _Fn implements ElevationSource {
  _Fn(this.f);
  final List<double?> Function(List<LatLng>) f;
  @override
  String get name => 'fn';
  @override
  Future<List<double?>> elevations(List<LatLng> points) async => f(points);
}
