// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'elevation_source.dart';

/// Client for the public Open Topo Data API
/// (https://www.opentopodata.org/api/).
///
/// Public-server limits that are enforced here: at most 100 locations per
/// request, at most 1 request per second (requests are serialized and
/// spaced), and about 1000 requests per day (counted in memory per UTC day;
/// [ElevationQuotaExceeded] is thrown beyond that).
///
/// Datasets: `ned10m` (USGS 3DEP/NED, 10 m) when every point lies inside the
/// contiguous-US bounding box, otherwise `srtm30m` (SRTM, 30 m). Points for
/// which `ned10m` returns null are re-requested from `srtm30m`.
class OpenTopoDataSource implements ElevationSource {
  OpenTopoDataSource({
    http.Client? client,
    this.baseUrl = 'https://api.opentopodata.org/v1',
    this.timeout = const Duration(seconds: 15),
    this.minInterval = const Duration(seconds: 1),
    this.retryBackoff = const Duration(seconds: 2),
    this.dailyLimit = 1000,
    Future<void> Function(Duration)? delay,
    DateTime Function()? now,
  })  : _client = client ?? http.Client(),
        _delay = delay ?? Future<void>.delayed,
        _now = now ?? DateTime.now;

  static const int maxLocationsPerRequest = 100;
  static const String usDataset = 'ned10m';
  static const String globalDataset = 'srtm30m';

  final String baseUrl;
  final Duration timeout;
  final Duration minInterval;
  final Duration retryBackoff;
  final int dailyLimit;
  final http.Client _client;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _now;

  DateTime? _lastRequestAt;
  String? _countDay;
  int _countToday = 0;
  Future<void> _queue = Future<void>.value();

  /// Requests issued so far today (UTC), including retries.
  int get requestsToday => _countDay == _dayKey() ? _countToday : 0;

  @override
  String get name => 'Open Topo Data';

  /// Contiguous US bounding box (approximate): lat 24.4..49.5, lon -125..-66.9.
  static bool inContiguousUs(LatLng p) =>
      p.latitude >= 24.4 &&
      p.latitude <= 49.5 &&
      p.longitude >= -125.0 &&
      p.longitude <= -66.9;

  /// Dataset used for [points].
  static String datasetFor(List<LatLng> points) =>
      points.isNotEmpty && points.every(inContiguousUs)
          ? usDataset
          : globalDataset;

  @override
  Future<List<double?>> elevations(List<LatLng> points) async {
    if (points.isEmpty) return const [];
    final dataset = datasetFor(points);
    final out = List<double?>.filled(points.length, null);
    for (var i = 0; i < points.length; i += maxLocationsPerRequest) {
      final end = (i + maxLocationsPerRequest).clamp(0, points.length);
      final batch = points.sublist(i, end);
      var res = await _query(dataset, batch);
      if (dataset == usDataset && res.any((e) => e == null)) {
        final missing = <int>[
          for (var k = 0; k < res.length; k++)
            if (res[k] == null) k,
        ];
        final fb =
            await _query(globalDataset, [for (final k in missing) batch[k]]);
        res = List<double?>.of(res);
        for (var k = 0; k < missing.length; k++) {
          res[missing[k]] = fb[k];
        }
      }
      out.setRange(i, end, res);
    }
    return out;
  }

  String _dayKey() {
    final d = _now().toUtc();
    return '${d.year}-${d.month}-${d.day}';
  }

  /// Runs [fn] after all previously queued requests and after the minimum
  /// spacing since the last one; enforces the daily budget.
  Future<T> _throttled<T>(Future<T> Function() fn) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        final last = _lastRequestAt;
        if (last != null) {
          final wait = minInterval - _now().difference(last);
          if (wait > Duration.zero) await _delay(wait);
        }
        final day = _dayKey();
        if (_countDay != day) {
          _countDay = day;
          _countToday = 0;
        }
        if (_countToday >= dailyLimit) {
          throw ElevationQuotaExceeded(
              'Open Topo Data daily limit of $dailyLimit requests reached');
        }
        _countToday++;
        _lastRequestAt = _now();
        completer.complete(await fn());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<List<double?>> _query(String dataset, List<LatLng> batch) async {
    final locations = batch
        .map((p) =>
            '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}')
        .join('|');
    final uri = Uri.parse('$baseUrl/$dataset')
        .replace(queryParameters: {'locations': locations});
    for (var attempt = 0;; attempt++) {
      final http.Response resp;
      try {
        resp = await _throttled(() => _client.get(uri).timeout(timeout));
      } on ElevationUnavailable {
        rethrow;
      } on SocketException catch (e) {
        throw ElevationUnavailable('offline: ${e.message}');
      } on http.ClientException catch (e) {
        throw ElevationUnavailable('offline: ${e.message}');
      } on TimeoutException {
        throw const ElevationUnavailable('request timed out');
      }
      final retryable = resp.statusCode >= 500 || resp.statusCode == 429;
      if (retryable && attempt == 0) {
        await _delay(retryBackoff);
        continue;
      }
      if (resp.statusCode != 200) {
        throw ElevationUnavailable(
            'Open Topo Data HTTP ${resp.statusCode} for $dataset');
      }
      return _parse(resp.body, batch.length);
    }
  }

  List<double?> _parse(String body, int expected) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['status'] != 'OK') {
        throw ElevationUnavailable('Open Topo Data: ${json['error']}');
      }
      final results = json['results'] as List<dynamic>;
      if (results.length != expected) {
        throw const ElevationUnavailable('unexpected result count');
      }
      return [
        for (final r in results) ((r as Map)['elevation'] as num?)?.toDouble(),
      ];
    } on ElevationUnavailable {
      rethrow;
    } catch (e) {
      throw ElevationUnavailable('malformed response: $e');
    }
  }

  void close() => _client.close();
}
