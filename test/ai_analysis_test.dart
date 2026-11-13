// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/services/ai_analysis.dart';
import 'package:mesh_analyzer/services/rig_comparison.dart';
import 'package:mesh_analyzer/services/rig_math.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:mesh_analyzer/utils/user_errors.dart';

const _lat = 33.68007;
const _lon = -116.24006;

SidePoints _route(double rssi, {double snr = 5}) {
  final lats = <double>[], lons = <double>[];
  final r = <double?>[], s = <double?>[];
  for (var i = 0; i < 20; i++) {
    lats.add(_lat);
    lons.add(_lon + i * 0.0003);
    r.add(rssi);
    s.add(snr);
  }
  return SidePoints(lats, lons, r, s);
}

Future<SessionDigest> _digest(AppDatabase db) async {
  final nodeId = await db.upsertNode(nodeId: 0xdeadbeef, longName: 'Secret');
  final mapId = await db.createCoverageMap(name: 'Home', baseNodeId: nodeId);
  Future<Session> session(
      RigSpec rig, List<(double, int, String)> rx, List<String> pings) async {
    final id = await db.createSession(
        coverageMapId: mapId,
        loraPreset: 'MEDIUM_FAST',
        packetAirtimeMs: 180,
        pingIntervalSec: 15,
        mobileRigJson: rig.encode());
    for (final (snr, rssi, _) in rx) {
      await db.insertPacketEvent(PacketEventsCompanion.insert(
        sessionId: id,
        timestamp: DateTime(2026, 10, 1),
        direction: PacketDirection.rx,
        sourceNodeId: nodeId,
        packetType: PacketType.ping,
        rxSnr: Value(snr),
        rxRssi: Value(rssi),
        rxLat: const Value(_lat),
        rxLon: const Value(_lon),
      ));
    }
    for (final status in pings) {
      final tx = await db.insertPacketEvent(PacketEventsCompanion.insert(
        sessionId: id,
        timestamp: DateTime(2026, 10, 1),
        direction: PacketDirection.tx,
        sourceNodeId: nodeId,
        packetType: PacketType.ping,
        rxLat: const Value(_lat),
        rxLon: const Value(_lon),
      ));
      await db.insertPingCorrelation(PingCorrelationsCompanion.insert(
          txEventId: tx, ackStatus: Value(status)));
    }
    return (await db.getSessionById(id))!;
  }

  final a = await session(
      const RigSpec(name: 'Stock', antennaGainDbi: 2),
      [(4.0, -95, ''), (6.0, -90, ''), (-8.0, -110, '')],
      ['received', 'timeout', 'error:NO_RESPONSE', 'implicit']);
  final b = await session(const RigSpec(name: 'Whip', antennaGainDbi: 5.8),
      [(7.0, -88, '')], ['received', 'received']);
  final cmp = compareRoutes(_route(-95), _route(-90))!;
  return buildSessionDigest(db,
      sessionsA: [a],
      sessionsB: [b],
      comparison: cmp,
      expected: expectedRigDelta([a], [b]),
      check: checkComparable([a], [b]));
}

void main() {
  late AppDatabase db;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  group('digest', () {
    test('summarises sides and carries no positions or ids', () async {
      final d = await _digest(db);
      final j = d.toJson();
      final a = j['sideA'] as Map, b = j['sideB'] as Map;
      expect(a['rxCount'], 3);
      expect(a['snrMinDb'], -8.0);
      expect(a['snrMedianDb'], 4.0);
      expect(a['snrMaxDb'], 6.0);
      expect(a['rssiMedianDbm'], -95.0);
      expect(a['pingsTotal'], 4);
      expect(a['pingsOk'], 2);
      expect(a['pingFailures'], {'timeout': 1, 'error:NO_RESPONSE': 1});
      expect(a['packetAirtimeMs'], 180.0);
      expect(a['presets'], ['MEDIUM_FAST']);
      expect(a['mobileRig'], 'Stock');
      expect(b['pingsOk'], 2);
      expect((j['comparison'] as Map)['cellsMatched'], greaterThan(0));
      expect((j['expectedFromSpecs'] as Map)['deltaDb'], 3.8);

      final text = jsonEncode(j);
      for (final bad in ['33.68', '116.24', 'Secret', 'Home', '3735928559']) {
        expect(text.contains(bad), isFalse, reason: bad);
      }
      assertNoLocationData(j);
      expect(j.containsKey('distanceStats'), isFalse);
    });

    test('distanceStats passes through when set', () async {
      final d = await _digest(db);
      final withDist = SessionDigest.from(
        sessionsA: const [],
        sessionsB: const [],
        comparison: compareRoutes(_route(-95), _route(-90))!,
        expected: const RigExpectation(null, 0, 0, true),
        check: const ComparisonCheck(),
        a: d.a,
        b: d.b,
        distanceStats: {
          'bandsM': [0, 250, 500],
          'a': {'farthestAckM': 480, 'firstMissM': 300},
        },
      );
      final j = withDist.toJson();
      expect((j['distanceStats'] as Map)['bandsM'], [0, 250, 500]);
      assertNoLocationData(j);
    });

    test('intent names the variable under test and carries the question',
        () async {
      final d = await _digest(db);
      final intent = d.intent;
      expect(intent.changed, contains('mobile antenna'));
      expect(intent.changed, isNot(contains('preset')));
      expect(intent.same, contains('preset'));
      expect(intent.nameA, 'Stock');
      expect(intent.nameB, 'Whip');
      expect(intent.summary, contains('Stock → Whip'));

      final json = d.toJson();
      expect((json['sideA'] as Map)['name'], 'Stock');
      expect((json['intent'] as Map)['changed'], contains('mobile antenna'));
      expect((json['intent'] as Map).containsKey('question'), isFalse);

      final q = d.withQuestion('  Does the whip buy range?  ');
      expect((q.toJson()['intent'] as Map)['question'],
          'Does the whip buy range?');
      expect(d.withQuestion('   ').question, isNull);
      expect(d.withQuestion('x' * 400).question!.length, 300);
      assertNoLocationData(q.toJson());
    });

    test('cache key ignores id order and separates sides', () {
      expect(aiAnalysisCacheKey([2, 1], [3]), aiAnalysisCacheKey([1, 2], [3]));
      expect(aiAnalysisCacheKey([1], [2]), isNot(aiAnalysisCacheKey([2], [1])));
      expect(aiAnalysisCacheKey([1], [2]), startsWith('ai_analysis_'));
    });
  });

  group('assertNoLocationData', () {
    void rejects(Object? json) =>
        expect(() => assertNoLocationData(json), throwsArgumentError);

    test('rejects forbidden field names at any depth, any case', () {
      for (final k in [
        'lat',
        'lon',
        'latitude',
        'Longitude',
        'nodeNum',
        'nodeId',
        'key',
        'psk',
      ]) {
        rejects({k: 1});
        rejects({
          'a': [
            {
              'b': {k: 'x'}
            }
          ]
        });
      }
    });

    test('rejects coordinate-like pairs and text', () {
      rejects({
        'p': [33.68007, -116.24006]
      });
      rejects({'note': 'at 33.68007, -116.24006 near the road'});
      rejects({'note': '33.68007,-116.24006'});
    });

    test('allows ordinary stats', () {
      assertNoLocationData({
        'bands': [0, 250],
        'pair': [4.5, -92.0],
        'snr': -8.5,
        'text': 'B was 4 dB stronger, 75 m cells, 12.5 dB',
        'keys': 3,
        'nested': {
          'medianRssiPerBand': [-92.0, -101.5]
        },
      });
    });
  });

  group('client', () {
    late SharedPreferences prefs;
    late SessionDigest digest;

    setUp(() async {
      prefs = await SharedPreferences.getInstance();
      digest = await _digest(db);
    });

    AiAnalysisClient client(FakeAiAnalysisGateway g) => AiAnalysisClient(
        prefs: prefs, gateway: g, appVersion: () async => '1.2.3+4');

    test('success sends the digest, caches, and reuses the cache', () async {
      final g = FakeAiAnalysisGateway();
      final c = client(g);
      final r1 = await c.analyze(digest);
      expect(r1.headline, FakeAiAnalysisGateway.sample.headline);
      expect(g.received, hasLength(1));
      expect(g.received.single['schema'], SessionDigest.schema);
      expect(g.deviceIds.single, prefs.getString(AppConstants.prefAiDeviceId));
      expect(g.deviceIds.single, hasLength(36));
      expect(prefs.getString(digest.cacheKey), isNotNull);

      final r2 = await c.analyze(digest);
      expect(g.received, hasLength(1), reason: 'cache hit must not re-bill');
      expect(r2.bullets, r1.bullets);

      await c.analyze(digest, refresh: true);
      expect(g.received, hasLength(2));
      // The device id is stable.
      expect(g.deviceIds.toSet(), hasLength(1));
    });

    test('429 and 5xx become plain English and are not cached', () async {
      final g = FakeAiAnalysisGateway(error: const HttpStatusException(429));
      await expectLater(
          client(g).analyze(digest),
          throwsA(isA<AiAnalysisLimitException>().having((e) => e.message,
              'message', 'Daily limit reached. Try again tomorrow.')));
      g.error = const HttpStatusException(503);
      await expectLater(
          client(g).analyze(digest),
          throwsA(isA<AiAnalysisException>().having(
              (e) => e.message, 'message', contains('having trouble'))));
      expect(prefs.getString(digest.cacheKey), isNull);
    });

    test('bad answer and timeout map to messages', () async {
      final g = FakeAiAnalysisGateway(error: const FormatException('x'));
      await expectLater(
          client(g).analyze(digest),
          throwsA(isA<AiAnalysisException>().having(
              (e) => e.message, 'message', contains('could not read'))));
      g.error = TimeoutException('slow');
      await expectLater(
          client(g).analyze(digest),
          throwsA(isA<AiAnalysisException>()
              .having((e) => e.message, 'message', contains('too long'))));
    });

    test('refuses to send a digest that would leak a position', () async {
      final bad = SessionDigest.from(
        sessionsA: const [],
        sessionsB: const [],
        comparison: compareRoutes(_route(-95), _route(-90))!,
        expected: const RigExpectation(null, 0, 0, true),
        check: const ComparisonCheck(),
        a: digest.a,
        b: digest.b,
        distanceStats: {'lat': 33.1},
      );
      final g = FakeAiAnalysisGateway();
      await expectLater(client(g).analyze(bad), throwsArgumentError);
      expect(g.received, isEmpty);
    });

    test('a limit from the server passes through unchanged', () async {
      final g = FakeAiAnalysisGateway(
          error: const AiAnalysisLimitException('Monthly text',
              reason: 'monthly'));
      await expectLater(
          client(g).analyze(digest),
          throwsA(isA<AiAnalysisLimitException>()
              .having((e) => e.message, 'message', 'Monthly text')
              .having((e) => e.reason, 'reason', 'monthly')));
      expect(prefs.getString(digest.cacheKey), isNull);
    });

    test('userMessage covers HTTP statuses', () {
      expect(userMessage(const HttpStatusException(429)),
          'Daily limit reached. Try again tomorrow.');
      expect(userMessage(const HttpStatusException(500)),
          contains('having trouble'));
    });
  });

  group('HTTP gateway', () {
    Future<Object?> errorFor(int status, Object body) async {
      final g = HttpAiAnalysisGateway(Uri.parse('https://example.test/'),
          appToken: 'tok',
          client: MockClient((_) async =>
              http.Response(body is String ? body : jsonEncode(body), status)));
      try {
        await g.analyze(const {}, deviceId: 'd', appVersion: 'v');
        return null;
      } catch (e) {
        return e;
      }
    }

    test('429 carries the server message and reason', () async {
      for (final reason in ['daily', 'monthly', 'global']) {
        final e = await errorFor(429, {
          'error': 'x',
          'reason': reason,
          'message': 'Server says $reason',
        });
        expect(
            e,
            isA<AiAnalysisLimitException>()
                .having((e) => e.reason, 'reason', reason)
                .having((e) => e.message, 'message', 'Server says $reason'));
      }
    });

    test('429 without a message falls back to reason text', () async {
      final monthly = await errorFor(429, {'reason': 'monthly'});
      expect((monthly as AiAnalysisLimitException).message,
          contains('more on the 1st'));
      final daily = await errorFor(429, {'reason': 'daily'});
      expect((daily as AiAnalysisLimitException).message,
          contains('more tomorrow'));
      final old = await errorFor(429, {'error': 'daily limit reached'});
      expect((old as AiAnalysisLimitException).message,
          'Daily limit reached. Try again tomorrow.');
      final junk = await errorFor(429, 'not json');
      expect(junk, isA<AiAnalysisLimitException>());
    });

    test('sends the app token with the other headers', () async {
      late http.Request sent;
      final g = HttpAiAnalysisGateway(Uri.parse('https://example.test/'),
          appToken: 'tok-123', client: MockClient((req) async {
        sent = req;
        return http.Response(
            jsonEncode(FakeAiAnalysisGateway.sample.toJson()), 200);
      }));
      await g.analyze(const {'schema': 1}, deviceId: 'dev', appVersion: '1+2');
      expect(sent.headers['X-App-Token'], 'tok-123');
      expect(sent.headers['X-Device-Id'], 'dev');
      expect(sent.headers['X-App-Version'], '1+2');
      expect(sent.headers['Content-Type'], startsWith('application/json'));
    });

    test('no token compiled in: unavailable, nothing sent', () async {
      var calls = 0;
      final g = HttpAiAnalysisGateway(Uri.parse('https://example.test/'),
          appToken: '', client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }));
      await expectLater(g.analyze(const {}, deviceId: 'd', appVersion: 'v'),
          throwsA(isA<AiUnavailableException>()));
      expect(calls, 0);
    });

    test('a refused token (401/403) is unavailable', () async {
      for (final code in [401, 403]) {
        final e = await errorFor(code, {'error': 'missing or bad X-App-Token'});
        expect(
            e,
            isA<AiUnavailableException>()
                .having((e) => e.message, 'message', aiUnavailableMessage));
      }
    });

    test('the client passes the unavailable message through', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final client = AiAnalysisClient(
          prefs: prefs,
          appVersion: () async => 'v',
          gateway: HttpAiAnalysisGateway(Uri.parse('https://example.test/'),
              appToken: '',
              client: MockClient((_) async => http.Response('{}', 200))));
      await expectLater(
          client.analyze(await _digest(db)),
          throwsA(isA<AiAnalysisException>().having(
              (e) => e.message, 'message', 'AI analysis is unavailable.')));
    });

    test('other errors stay HttpStatusException with the reason', () async {
      final e = await errorFor(400, {'error': 'forbidden field'});
      expect(
          e,
          isA<HttpStatusException>()
              .having((e) => e.statusCode, 'status', 400)
              .having((e) => e.reason, 'reason', 'forbidden field'));
    });
  });
}
