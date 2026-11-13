// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/database/app_database.dart';
import '../data/radio/meshtastic/meshtastic_presets.dart';
import '../utils/constants.dart';
import '../utils/user_errors.dart';
import 'range_stats.dart';
import 'rig_comparison.dart';

// ---------------------------------------------------------------------------
// Digest: the ONLY thing that leaves the phone. Aggregates, never positions.

/// Everything the backend may see about one side (A or B) of a comparison.
class SideStats {
  final int sessions;
  final List<String> presets;
  final String mobileRig, baseRig;
  final double? mobileNetGainDb, baseNetGainDb;
  final double durationMin;
  final int rxCount;
  final double? snrMin, snrMedian, snrMax, rssiMedian;
  final int pingsTotal, pingsOk;

  /// Failed pings by kind: `timeout`, `throttled`, `error:<reason>`.
  final Map<String, int> pingFailures;
  final double? packetAirtimeMs;
  final int? pingIntervalSec;

  /// Highest share (%) of the last hour the radio transmitted / of the
  /// channel that was busy, as the radio reported it.
  final double? radioAirUtilTxPct, channelUtilPct;

  const SideStats({
    required this.sessions,
    required this.presets,
    required this.mobileRig,
    required this.baseRig,
    this.mobileNetGainDb,
    this.baseNetGainDb,
    required this.durationMin,
    required this.rxCount,
    this.snrMin,
    this.snrMedian,
    this.snrMax,
    this.rssiMedian,
    required this.pingsTotal,
    required this.pingsOk,
    required this.pingFailures,
    this.packetAirtimeMs,
    this.pingIntervalSec,
    this.radioAirUtilTxPct,
    this.channelUtilPct,
  });

  /// Builds one side from its sessions, their received packets' signal values
  /// and the ack status of each ping. Positions are never read.
  factory SideStats.from(
    List<Session> sessions, {
    required List<PacketEvent> events,
    required Iterable<String> pingStatuses,
  }) {
    final snr = <double>[], rssi = <double>[];
    var rx = 0;
    for (final e in events) {
      if (e.direction != PacketDirection.rx) continue;
      rx++;
      if (e.rxSnr != null) snr.add(e.rxSnr!);
      if (e.rxRssi != null) rssi.add(e.rxRssi!.toDouble());
    }
    var ok = 0, total = 0;
    final failures = <String, int>{};
    for (final s in pingStatuses) {
      total++;
      if (s == AckStatus.received || s == AckStatus.implicit) {
        ok++;
      } else {
        failures[s] = (failures[s] ?? 0) + 1;
      }
    }
    var minutes = 0.0;
    for (final s in sessions) {
      if (s.endedAt != null) {
        minutes += s.endedAt!.difference(s.startedAt).inSeconds / 60;
      }
    }
    final mobile = groupRig(sessions, mobile: true);
    final base = groupRig(sessions, mobile: false);
    double? maxOf(Iterable<double?> v) {
      final k = v.whereType<double>();
      return k.isEmpty ? null : k.reduce((a, b) => a > b ? a : b);
    }

    final airtimes = [
      for (final s in sessions)
        if (s.packetAirtimeMs > 0) s.packetAirtimeMs,
    ];
    final intervals = [
      for (final s in sessions)
        if (s.pingIntervalSec > 0) s.pingIntervalSec,
    ];
    return SideStats(
      sessions: sessions.length,
      presets: {
        for (final s in sessions)
          if (s.loraPreset.isNotEmpty) s.loraPreset,
      }.toList(),
      mobileRig: mobile.label,
      baseRig: base.label,
      mobileNetGainDb: mobile.netGainDb,
      baseNetGainDb: base.netGainDb,
      durationMin: minutes,
      rxCount: rx,
      snrMin: snr.isEmpty ? null : snr.reduce((a, b) => a < b ? a : b),
      snrMedian: snr.isEmpty ? null : median(snr),
      snrMax: snr.isEmpty ? null : snr.reduce((a, b) => a > b ? a : b),
      rssiMedian: rssi.isEmpty ? null : median(rssi),
      pingsTotal: total,
      pingsOk: ok,
      pingFailures: failures,
      packetAirtimeMs: airtimes.isEmpty
          ? null
          : airtimes.reduce((a, b) => a + b) / airtimes.length,
      pingIntervalSec: intervals.isEmpty
          ? null
          : (intervals.reduce((a, b) => a + b) / intervals.length).round(),
      radioAirUtilTxPct: maxOf(sessions.map((s) => s.radioAirUtilTx)),
      channelUtilPct: maxOf(sessions.map((s) => s.radioChannelUtil)),
    );
  }

  Map<String, dynamic> toJson() => {
        'sessions': sessions,
        'presets': presets,
        'mobileRig': mobileRig,
        'baseRig': baseRig,
        if (mobileNetGainDb != null) 'mobileNetGainDb': _r(mobileNetGainDb!),
        if (baseNetGainDb != null) 'baseNetGainDb': _r(baseNetGainDb!),
        'durationMin': _r(durationMin),
        'rxCount': rxCount,
        if (snrMin != null) 'snrMinDb': _r(snrMin!),
        if (snrMedian != null) 'snrMedianDb': _r(snrMedian!),
        if (snrMax != null) 'snrMaxDb': _r(snrMax!),
        if (rssiMedian != null) 'rssiMedianDbm': _r(rssiMedian!),
        'pingsTotal': pingsTotal,
        'pingsOk': pingsOk,
        'pingFailures': pingFailures,
        if (packetAirtimeMs != null) 'packetAirtimeMs': _r(packetAirtimeMs!),
        if (pingIntervalSec != null) 'pingIntervalSec': pingIntervalSec,
        if (radioAirUtilTxPct != null)
          'radioAirUtilTxPct': _r(radioAirUtilTxPct!),
        if (channelUtilPct != null) 'channelUtilPct': _r(channelUtilPct!),
      };
}

/// One decimal place. Also guarantees no number in the digest carries enough
/// digits to pass for a coordinate.
double _r(double v) => (v * 10).round() / 10;

/// The summary of a comparison sent for analysis.
class SessionDigest {
  /// Bumped when the shape changes (the backend validates it).
  static const schema = 1;

  /// Local session ids, only used for the cache key. NOT serialized.
  final List<int> sessionIdsA, sessionIdsB;
  final SideStats a, b;

  /// Overlap of the two routes in grid cells (cellMeters wide): matched,
  /// A only, B only. The model is told to say so when the routes differ.
  final int cellsMatched, cellsAOnly, cellsBOnly;
  final double cellMeters;
  final MetricStats rssi, snr;

  /// Expected B - A from the hardware profiles (null = unknown).
  final double? expectedDeltaDb, expectedMobileDeltaDb, expectedBaseDeltaDb;
  final bool noProfiles;
  final String? presetWarning;

  /// The app's own one-sentence verdict (numbers only).
  final String verdict;

  /// Filled later from `range_stats.dart`: how each side did by distance from
  /// the base. Aggregates only; the expected shape (all keys optional):
  /// ```
  /// {
  ///   "bandsM": [0, 250, 500, 1000, 2000],        // band edges, metres
  ///   "a": {                                       // and "b": same shape
  ///     "successPerBand": [{"fromM":0,"toM":250,"ok":12,"total":12}, ...],
  ///     "farthestAckM": 1840,       // farthest ping that was acknowledged
  ///     "firstMissM": 1210,         // nearest ping that failed
  ///     "heardOutToM": 2300,        // farthest received packet
  ///     "medianRssiPerBand": [-92.0, -101.5, ...],  // dBm, per band
  ///     "medianSnrPerBand": [6.5, 2.0, ...]         // dB, per band
  ///   },
  ///   "b": { ... },
  ///   "appReading": {            // the app's own wording, numbers only
  ///     "proved": "You proved ...",
  ///     "strengths": ["Whip: ...", "Stock: ..."],
  ///     "nextStep": "To split them: ...",
  ///     "dataFlags": ["other_radio_heard", "relay_only_acks"]
  ///   }
  /// }
  /// ```
  /// Distances only, never coordinates; [assertNoLocationData] runs over it.
  final Map<String, dynamic>? distanceStats;

  /// What the user typed as the question or context for this analysis
  /// (optional, ≤ 300 characters, their own words).
  final String? question;

  const SessionDigest({
    required this.sessionIdsA,
    required this.sessionIdsB,
    required this.a,
    required this.b,
    required this.cellsMatched,
    required this.cellsAOnly,
    required this.cellsBOnly,
    required this.cellMeters,
    required this.rssi,
    required this.snr,
    required this.expectedDeltaDb,
    required this.expectedMobileDeltaDb,
    required this.expectedBaseDeltaDb,
    required this.noProfiles,
    this.presetWarning,
    required this.verdict,
    this.distanceStats,
    this.question,
  });

  /// From what the Compare screen already has plus the per-side raw data.
  factory SessionDigest.from({
    required List<Session> sessionsA,
    required List<Session> sessionsB,
    required RouteComparison comparison,
    required RigExpectation expected,
    required ComparisonCheck check,
    required SideStats a,
    required SideStats b,
    Map<String, dynamic>? distanceStats,
  }) {
    var matched = 0, aOnly = 0, bOnly = 0;
    // A cell counts as measured by a side if either metric has a value there.
    for (var i = 0; i < comparison.rssiA.length; i++) {
      final inA = !comparison.rssiA[i].isNaN || !comparison.snrA[i].isNaN;
      final inB = !comparison.rssiB[i].isNaN || !comparison.snrB[i].isNaN;
      if (inA && inB) {
        matched++;
      } else if (inA) {
        aOnly++;
      } else if (inB) {
        bOnly++;
      }
    }
    return SessionDigest(
      sessionIdsA: [for (final s in sessionsA) s.id],
      sessionIdsB: [for (final s in sessionsB) s.id],
      a: a,
      b: b,
      cellsMatched: matched,
      cellsAOnly: aOnly,
      cellsBOnly: bOnly,
      cellMeters: comparison.grid.cellMeters,
      rssi: comparison.rssi,
      snr: comparison.snr,
      expectedDeltaDb: expected.deltaDb,
      expectedMobileDeltaDb:
          expected.noProfiles ? null : expected.mobileDeltaDb,
      expectedBaseDeltaDb: expected.noProfiles ? null : expected.baseDeltaDb,
      noProfiles: expected.noProfiles,
      presetWarning: check.warning,
      verdict: comparisonVerdict(
          measuredMedianDb: comparison.rssi.medianDelta,
          expected: expected,
          cells: comparison.rssi.cells),
      distanceStats: distanceStats,
    );
  }

  /// Stable key for the cached result of this comparison.
  String get cacheKey => aiAnalysisCacheKey(sessionIdsA, sessionIdsB);

  /// Same digest with the user's question attached.
  SessionDigest withQuestion(String? q) {
    final t = q?.trim();
    return SessionDigest(
      sessionIdsA: sessionIdsA,
      sessionIdsB: sessionIdsB,
      a: a,
      b: b,
      cellsMatched: cellsMatched,
      cellsAOnly: cellsAOnly,
      cellsBOnly: cellsBOnly,
      cellMeters: cellMeters,
      rssi: rssi,
      snr: snr,
      expectedDeltaDb: expectedDeltaDb,
      expectedMobileDeltaDb: expectedMobileDeltaDb,
      expectedBaseDeltaDb: expectedBaseDeltaDb,
      noProfiles: noProfiles,
      presetWarning: presetWarning,
      verdict: verdict,
      distanceStats: distanceStats,
      question: t == null || t.isEmpty
          ? null
          : (t.length > 300 ? t.substring(0, 300) : t),
    );
  }

  /// What differs between the two sides (the variable under test), what is
  /// the same, and whether both walks covered the same ground — so the
  /// model knows WHY these two were put side by side.
  ComparisonIntent get intent => ComparisonIntent.of(this);

  Map<String, dynamic> _metric(MetricStats m) => {
        'comparedCells': m.cells,
        'medianDeltaDb': _r(m.medianDelta),
        'pctBBetterBy3Db': _r(m.pctBBetter),
        'pctABetterBy3Db': _r(m.pctABetter),
      };

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'comparison': {
          'meaning': 'delta is B minus A; positive means B is stronger',
          'cellMeters': cellMeters.round(),
          'cellsMatched': cellsMatched,
          'cellsAOnly': cellsAOnly,
          'cellsBOnly': cellsBOnly,
          'rssi': _metric(rssi),
          'snr': _metric(snr),
          'appVerdict': verdict,
          if (presetWarning != null) 'warning': presetWarning,
        },
        'expectedFromSpecs': {
          'hasProfiles': !noProfiles,
          if (expectedDeltaDb != null) 'deltaDb': _r(expectedDeltaDb!),
          if (expectedMobileDeltaDb != null)
            'mobileDeltaDb': _r(expectedMobileDeltaDb!),
          if (expectedBaseDeltaDb != null)
            'baseDeltaDb': _r(expectedBaseDeltaDb!),
        },
        'intent': intent.toJson(),
        'sideA': {...a.toJson(), 'name': intent.nameA},
        'sideB': {...b.toJson(), 'name': intent.nameB},
        if (distanceStats != null) 'distanceStats': distanceStats,
      };
}

/// `ai_analysis_<hash of the session ids>`; order of the ids does not matter.
String aiAnalysisCacheKey(List<int> idsA, List<int> idsB) {
  final x = [...idsA]..sort(), y = [...idsB]..sort();
  return '${AppConstants.prefAiAnalysisPrefix}'
      '${_fnv1a('A:${x.join(',')}|B:${y.join(',')}').toRadixString(16)}';
}

int _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// Reads the sessions' stored data (signal values and ping outcomes only)
/// and builds the digest.
Future<SessionDigest> buildSessionDigest(
  AppDatabase db, {
  required List<Session> sessionsA,
  required List<Session> sessionsB,
  required RouteComparison comparison,
  required RigExpectation expected,
  required ComparisonCheck check,
  Map<String, dynamic>? distanceStats,
}) async {
  Future<SideStats> side(List<Session> group) async {
    final events = <PacketEvent>[];
    final statuses = <String>[];
    for (final s in group) {
      events.addAll(await db.getEventsForSession(s.id));
      statuses.addAll([
        for (final c in (await db.getPingsForSession(s.id)).values) c.ackStatus,
      ]);
    }
    return SideStats.from(group, events: events, pingStatuses: statuses);
  }

  return SessionDigest.from(
    sessionsA: sessionsA,
    sessionsB: sessionsB,
    comparison: comparison,
    expected: expected,
    check: check,
    a: await side(sessionsA),
    b: await side(sessionsB),
    distanceStats: distanceStats,
  );
}

// ---------------------------------------------------------------------------
// Scrubber

const _forbiddenKeys = {
  'lat',
  'lon',
  'lng',
  'long',
  'latitude',
  'longitude',
  'nodenum',
  'nodeid',
  'node_num',
  'node_id',
  'key',
  'psk',
  'pubkey',
  'publickey',
};

final _coordText = RegExp(r'-?\d{1,3}\.\d{3,}\s*[,;/ ]\s*-?\d{1,3}\.\d{3,}');

/// Throws [ArgumentError] if [json] (a decoded JSON value) has a field that
/// could carry a position or a radio identity, a pair of numbers that looks
/// like a coordinate, or a string that contains one. Called before every send.
void assertNoLocationData(Object? json, [String path = r'$']) {
  switch (json) {
    case Map():
      json.forEach((k, v) {
        if (_forbiddenKeys.contains('$k'.toLowerCase())) {
          throw ArgumentError('Forbidden field "$k" at $path');
        }
        assertNoLocationData(v, '$path.$k');
      });
    case List():
      if (json.length == 2 &&
          json.every((v) => v is num && _looksPrecise(v)) &&
          _inCoordRange(json[0] as num, json[1] as num)) {
        throw ArgumentError('Coordinate-like number pair at $path');
      }
      for (var i = 0; i < json.length; i++) {
        assertNoLocationData(json[i], '$path[$i]');
      }
    case String():
      if (_coordText.hasMatch(json)) {
        throw ArgumentError('Coordinate-like text at $path');
      }
    default:
      break;
  }
}

/// Three or more decimals (4.5 and 12 are fine; 33.8121 is not).
bool _looksPrecise(num v) {
  if (v is int) return false;
  final s = v.toString();
  final dot = s.indexOf('.');
  return dot >= 0 && s.length - dot - 1 >= 3 && !s.contains('e');
}

bool _inCoordRange(num a, num b) => a.abs() <= 90 && b.abs() <= 180;

// ---------------------------------------------------------------------------
// Result

class AiAnalysisResult {
  final String headline;
  final List<String> bullets, caveats;
  final String nextStep, model;

  const AiAnalysisResult({
    required this.headline,
    required this.bullets,
    required this.caveats,
    required this.nextStep,
    required this.model,
  });

  /// Throws [FormatException] if the shape is wrong.
  factory AiAnalysisResult.fromJson(Object? j) {
    if (j is! Map) throw const FormatException('not an object');
    List<String> strings(Object? v) {
      if (v is! List) throw const FormatException('not a list');
      return [for (final x in v) x.toString()];
    }

    final headline = j['headline'];
    if (headline is! String || headline.isEmpty) {
      throw const FormatException('no headline');
    }
    return AiAnalysisResult(
      headline: headline,
      bullets: strings(j['bullets']),
      caveats: strings(j['caveats'] ?? const []),
      nextStep: (j['next_step'] ?? '').toString(),
      model: (j['model'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'headline': headline,
        'bullets': bullets,
        'caveats': caveats,
        'next_step': nextStep,
        'model': model,
      };
}

/// What went wrong, already in plain English.
class AiAnalysisException implements Exception {
  final String message;
  const AiAnalysisException(this.message);

  @override
  String toString() => message;
}

/// The backend cannot be used from this build: no app token was compiled
/// in, or the backend refused it (401/403). Nothing more to try.
class AiUnavailableException extends AiAnalysisException {
  const AiUnavailableException() : super(aiUnavailableMessage);
}

/// What the AI cards show when the backend cannot be used.
const aiUnavailableMessage = 'AI analysis is unavailable.';

/// Shared token for the backend's `X-App-Token` check. Never a committed
/// literal: pass it at build time with
/// `--dart-define=AI_APP_TOKEN=...` (tool/ai-analysis/README.md). Empty
/// in a build without it, and then no AI request is made.
const String aiAppToken = String.fromEnvironment('AI_APP_TOKEN');

/// The headers every AI backend request carries, or
/// [AiUnavailableException] when [appToken] is empty (no request is made).
Map<String, String> aiRequestHeaders({
  required String appToken,
  required String deviceId,
  required String appVersion,
}) {
  if (appToken.isEmpty) throw const AiUnavailableException();
  return {
    'Content-Type': 'application/json',
    'X-App-Token': appToken,
    'X-Device-Id': deviceId,
    'X-App-Version': appVersion,
  };
}

/// A usage limit was reached (HTTP 429): not a failure, the user just has
/// to wait. [reason] is the server's `daily`, `monthly` or `global`, or
/// null when it gave none (older backends).
class AiAnalysisLimitException extends AiAnalysisException {
  final String? reason;
  const AiAnalysisLimitException(super.message, {this.reason});

  /// The server's `message` when it sent a usable one, else text for
  /// [reason].
  factory AiAnalysisLimitException.fromServer(
      {String? reason, String? message}) {
    final m = message?.trim();
    if (m != null && m.isNotEmpty && m.length <= 200) {
      return AiAnalysisLimitException(m, reason: reason);
    }
    return AiAnalysisLimitException(
        switch (reason) {
          'daily' => "You've used today's analyses; more tomorrow (UTC).",
          'monthly' =>
            "You've used this month's analyses; more on the 1st (UTC).",
          'global' =>
            'AI analysis has reached its daily limit for everyone; more '
                'tomorrow (UTC).',
          _ => userMessage(const HttpStatusException(429)),
        },
        reason: reason);
  }
}

// ---------------------------------------------------------------------------
// Gateway seam

abstract class AiAnalysisGateway {
  /// Sends [digest] and returns the parsed answer. Throws
  /// [AiAnalysisLimitException] for 429 and [HttpStatusException] for
  /// other non-200 answers.
  Future<AiAnalysisResult> analyze(
    Map<String, dynamic> digest, {
    required String deviceId,
    required String appVersion,
  });
}

class HttpAiAnalysisGateway implements AiAnalysisGateway {
  final Uri url;
  final http.Client _client;

  /// [aiAppToken] unless a test passes its own.
  final String appToken;

  HttpAiAnalysisGateway(this.url, {http.Client? client, String? appToken})
      : _client = client ?? http.Client(),
        appToken = appToken ?? aiAppToken;

  @override
  Future<AiAnalysisResult> analyze(
    Map<String, dynamic> digest, {
    required String deviceId,
    required String appVersion,
  }) async {
    final headers = aiRequestHeaders(
        appToken: appToken, deviceId: deviceId, appVersion: appVersion);
    final res =
        await _client.post(url, headers: headers, body: jsonEncode(digest));
    if (res.statusCode == 401 || res.statusCode == 403) {
      print('AI analysis: app token refused (HTTP ${res.statusCode})');
      throw const AiUnavailableException();
    }
    if (res.statusCode == 429) {
      final body = _errorBody(res);
      print('AI analysis: limit reached (${body['reason'] ?? 'no reason'})');
      throw AiAnalysisLimitException.fromServer(
          reason: _str(body['reason']), message: _str(body['message']));
    }
    if (res.statusCode != 200) {
      final e =
          HttpStatusException(res.statusCode, _str(_errorBody(res)['error']));
      print('AI analysis: $e');
      throw e;
    }
    return AiAnalysisResult.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }
}

/// The JSON object of an error reply (`error`, and for 429 `reason` and
/// `message`), or empty.
Map<String, dynamic> _errorBody(http.Response res) {
  try {
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    return body is Map<String, dynamic> ? body : const {};
  } catch (_) {
    return const {};
  }
}

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

/// Used when no backend URL is configured.
class UnavailableAiAnalysisGateway implements AiAnalysisGateway {
  const UnavailableAiAnalysisGateway();

  @override
  Future<AiAnalysisResult> analyze(Map<String, dynamic> digest,
          {required String deviceId, required String appVersion}) =>
      Future.error(const AiAnalysisException('AI analysis is not available.'));
}

/// Canned answer (or error) for tests and demo mode. Records what it got.
class FakeAiAnalysisGateway implements AiAnalysisGateway {
  FakeAiAnalysisGateway({this.result, this.error, this.delay = Duration.zero});

  AiAnalysisResult? result;
  Object? error;
  Duration delay;
  final received = <Map<String, dynamic>>[];
  final deviceIds = <String>[];

  static const sample = AiAnalysisResult(
    headline: 'B was about 4 dB stronger over the shared route.',
    bullets: [
      'Median RSSI was 4 dB higher on side B.',
      'B answered 18 of 20 pings; A answered 15 of 20.',
    ],
    caveats: ['Only 20 pings per side.'],
    nextStep: 'Repeat the walk on a different day to confirm.',
    model: 'claude-haiku-5-5',
  );

  @override
  Future<AiAnalysisResult> analyze(
    Map<String, dynamic> digest, {
    required String deviceId,
    required String appVersion,
  }) async {
    received.add(digest);
    deviceIds.add(deviceId);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return result ?? sample;
  }
}

// ---------------------------------------------------------------------------
// Client

class AiAnalysisClient {
  /// Haiku usually answers in seconds; the backend allows up to 45 s.
  static const timeout = Duration(seconds: 55);

  final SharedPreferences prefs;
  final AiAnalysisGateway gateway;
  final Future<String> Function() _appVersion;

  AiAnalysisClient({
    required this.prefs,
    required this.gateway,
    Future<String> Function()? appVersion,
  }) : _appVersion = appVersion ?? _packageVersion;

  static Future<String> _packageVersion() async {
    try {
      final i = await PackageInfo.fromPlatform();
      return '${i.version}+${i.buildNumber}';
    } catch (_) {
      return 'unknown';
    }
  }

  /// The `X-App-Version` header value (`version+build`, or `unknown`).
  Future<String> appVersion() => _appVersion();

  /// Random id for the daily and monthly quotas; created on first use.
  String get deviceId {
    var id = prefs.getString(AppConstants.prefAiDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      prefs.setString(AppConstants.prefAiDeviceId, id);
    }
    return id;
  }

  bool get hasConsent => prefs.getBool(AppConstants.prefAiConsent) ?? false;

  Future<void> setConsent() => prefs.setBool(AppConstants.prefAiConsent, true);

  AiAnalysisResult? cached(String cacheKey) {
    final raw = prefs.getString(cacheKey);
    if (raw == null) return null;
    try {
      return AiAnalysisResult.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCached(String cacheKey) => prefs.remove(cacheKey);

  /// The cached answer for this comparison, else one network call (billed).
  /// [refresh] skips the cache. Throws [AiAnalysisException].
  Future<AiAnalysisResult> analyze(SessionDigest digest,
      {bool refresh = false}) async {
    if (refresh) {
      await clearCached(digest.cacheKey);
    } else if (cached(digest.cacheKey) case final hit?) {
      return hit;
    }
    final json = digest.toJson();
    assertNoLocationData(json);
    try {
      final result = await gateway
          .analyze(json, deviceId: deviceId, appVersion: await _appVersion())
          .timeout(timeout);
      try {
        await prefs.setString(digest.cacheKey, jsonEncode(result.toJson()));
      } catch (e) {
        debugPrint('AI analysis cache write failed: $e');
      }
      return result;
    } on AiAnalysisException {
      rethrow;
    } on TimeoutException {
      throw const AiAnalysisException(
          'The analysis took too long. Try again in a moment.');
    } on FormatException {
      throw const AiAnalysisException(
          'The service sent an answer the app could not read. Try again.');
    } on HttpStatusException catch (e) {
      if (e.statusCode == 429) throw AiAnalysisLimitException.fromServer();
      throw AiAnalysisException(userMessage(e));
    } on SocketException catch (e) {
      throw AiAnalysisException(userMessage(e));
    } on http.ClientException {
      throw const AiAnalysisException('No internet connection.');
    } catch (e) {
      throw AiAnalysisException(userMessage(e, doing: 'analyzing'));
    }
  }
}

double? _r1(double? v) => v == null ? null : (v * 10).round() / 10;

Map<String, dynamic> _sideDistance(SideRangeStats s) => {
      'successPerBand': [
        for (final b in s.bands)
          {
            'fromM': b.fromM.round(),
            if (b.toM != null) 'toM': b.toM!.round(),
            'ok': b.acked,
            'total': b.sent,
          },
      ],
      if (s.farthestAckM != null) 'farthestAckM': s.farthestAckM!.round(),
      if (s.firstMissM != null) 'firstMissM': s.firstMissM!.round(),
      if (s.heardBaseOutToM != null) 'heardOutToM': s.heardBaseOutToM!.round(),
      if (s.medianSnr != null) 'medianSnrDb': _r1(s.medianSnr),
      if (s.medianRssi != null) 'medianRssiDbm': _r1(s.medianRssi),
      'pingsWithin200m': s.pingsWithin200m,
    };

/// The by-distance numbers for [SessionDigest.distanceStats]: band
/// success counts, farthest ACK, first miss, heard-out-to and medians per
/// side. Distances only, never positions; the base method is named, not
/// its coordinates.
Map<String, dynamic> digestDistanceStats(RangeComparison r) => {
      'bandsM': [for (final e in rangeBandEdgesM) e.round()],
      'baseFrom': r.base.method.name,
      'a': _sideDistance(r.a),
      'b': _sideDistance(r.b),
      'appReading': {
        if (r.proved != null) 'proved': r.proved,
        'strengths': r.strengths,
        if (r.nextStep != null) 'nextStep': r.nextStep,
        'dataFlags': dataFlags(r),
      },
    };

/// Neutral codes for the data-quality notes (the notes themselves may name
/// radios, so they stay on the phone).
List<String> dataFlags(RangeComparison r) => [
      if (r.a.acksFromOtherNodes.isNotEmpty ||
          r.b.acksFromOtherNodes.isNotEmpty)
        'acks_from_other_node',
      if (r.a.otherNodesHeard.isNotEmpty || r.b.otherNodesHeard.isNotEmpty)
        'other_radio_heard',
      if (r.a.pingsImplicit > 0 || r.b.pingsImplicit > 0) 'relay_only_acks',
    ];

/// The reason two session groups are being compared, derived from what
/// differs between them. Names each side by the thing that changed.
class ComparisonIntent {
  /// Which inputs differ between A and B ("preset", "mobile antenna",
  /// "base antenna"); empty when nothing known differs.
  final List<String> changed;

  /// Inputs that are the same on both sides.
  final List<String> same;

  /// Both walks covered mostly the same cells.
  final bool sameRoute;
  final String nameA, nameB;
  final String? question;

  const ComparisonIntent({
    required this.changed,
    required this.same,
    required this.sameRoute,
    required this.nameA,
    required this.nameB,
    this.question,
  });

  static String _presetName(List<String> presets) =>
      presets.map(presetDisplayName).join(' + ');

  factory ComparisonIntent.of(SessionDigest d) {
    final changed = <String>[], same = <String>[];
    final pa = _presetName(d.a.presets), pb = _presetName(d.b.presets);
    (pa != pb ? changed : same).add('preset');
    (d.a.mobileRig != d.b.mobileRig ? changed : same).add('mobile antenna');
    (d.a.baseRig != d.b.baseRig ? changed : same).add('base antenna');
    final overlap = d.cellsMatched /
        math.max(1, d.cellsMatched + math.min(d.cellsAOnly, d.cellsBOnly));
    // Names: the first thing that differs, else A/B.
    String nameA = 'A', nameB = 'B';
    if (pa != pb) {
      nameA = pa;
      nameB = pb;
    } else if (d.a.mobileRig != d.b.mobileRig) {
      nameA = d.a.mobileRig;
      nameB = d.b.mobileRig;
    } else if (d.a.baseRig != d.b.baseRig) {
      nameA = d.a.baseRig;
      nameB = d.b.baseRig;
    }
    return ComparisonIntent(
      changed: changed,
      same: same,
      sameRoute: overlap >= 0.5,
      nameA: nameA,
      nameB: nameB,
      question: d.question,
    );
  }

  /// One sentence the app can show as the default question.
  String get summary {
    if (changed.isEmpty) {
      return 'Same preset and antennas on both sides: a repeat of the same '
          'test (different day, placement or route).';
    }
    return 'Changed: ${changed.join(', ')} ($nameA → $nameB). '
        'Same: ${same.isEmpty ? 'nothing else known' : same.join(', ')}. '
        '${sameRoute ? 'Same route.' : 'Different routes — compare by distance.'}';
  }

  Map<String, dynamic> toJson() => {
        'changed': changed,
        'same': same,
        'sameRoute': sameRoute,
        'nameA': nameA,
        'nameB': nameB,
        'summary': summary,
        if (question != null) 'question': question,
      };
}
