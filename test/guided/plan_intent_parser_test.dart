// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/services/ai_analysis.dart';
import 'package:mesh_analyzer/services/guided/plan_intent_parser.dart';
import 'package:mesh_analyzer/services/guided/plan_models.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:mesh_analyzer/utils/user_errors.dart';

const _ctx = ParserContext(
  rigNames: ['Stock whip', '5.8 dBi fiberglass', 'T1000-E', 'Heltec V3'],
  presetNames: {
    'LONG_FAST': 'Long Fast',
    'MEDIUM_FAST': 'Medium Fast',
    'SHORT_FAST': 'Short Fast',
  },
);

/// One row of the table test: what the sentence should yield.
class _Row {
  final String text;
  final PlanTemplate template;
  final List<String>? variants;
  final PlanSide side;
  final bool repeat;
  final int? minutes;
  final RouteKind kind;
  final double minConfidence, maxConfidence;
  final bool clarifies;

  const _Row(
    this.text,
    this.template, {
    this.variants,
    this.side = PlanSide.mobile,
    this.repeat = false,
    this.minutes,
    this.kind = RouteKind.walk,
    required this.minConfidence,
    double? maxConfidence,
    this.clarifies = false,
  }) : maxConfidence = maxConfidence ?? minConfidence;
}

const _rows = [
  _Row('I want to test multiple antennas', PlanTemplate.antennas,
      minConfidence: 0.6, clarifies: true),
  _Row('which range setting is best here', PlanTemplate.rangeSettings,
      minConfidence: 0.6, clarifies: true),
  _Row('compare my T1000-E with the Heltec', PlanTemplate.radios,
      variants: ['T1000-E', 'Heltec V3'], minConfidence: 0.9),
  _Row('does 20 dBm beat 10 dBm on the base', PlanTemplate.txPower,
      variants: ['20', '10'], side: PlanSide.base, minConfidence: 0.9),
  _Row('how far does it reach', PlanTemplate.reach,
      variants: ['Current setup'], minConfidence: 0.9),
  _Row('test the stock whip vs the 5.8 dBi fiberglass twice, 20 minute walks',
      PlanTemplate.antennas,
      variants: ['Stock whip', '5.8 dBi fiberglass'],
      repeat: true,
      minutes: 20,
      minConfidence: 0.9),
  _Row('long fast vs medium fast', PlanTemplate.rangeSettings,
      variants: ['LONG_FAST', 'MEDIUM_FAST'], minConfidence: 0.9),
  _Row('Is MEDIUM_FAST or SHORT_FAST better on a half an hour drive?',
      PlanTemplate.rangeSettings,
      variants: ['MEDIUM_FAST', 'SHORT_FAST'],
      minutes: 30,
      kind: RouteKind.drive,
      minConfidence: 0.9),
  _Row('compare "Big Yagi" and "Rubber duck" on the base antenna',
      PlanTemplate.antennas,
      variants: ['Big Yagi', 'Rubber duck'],
      side: PlanSide.base,
      minConfidence: 0.9),
  _Row('17 vs 27 dBm, both orders', PlanTemplate.txPower,
      variants: ['17', '27'], repeat: true, minConfidence: 0.9),
  _Row('how much power do I need', PlanTemplate.txPower,
      minConfidence: 0.6, clarifies: true),
  _Row('what is the range test distance from the car', PlanTemplate.reach,
      kind: RouteKind.drive, minConfidence: 0.9),
  // TestFlight 2026-11-10: "radio settings" is the range setting.
  _Row('compare two separate radio settings', PlanTemplate.rangeSettings,
      minConfidence: 0.6, clarifies: true),
  _Row('which LoRa settings reach further on my node',
      PlanTemplate.rangeSettings,
      minConfidence: 0.6, clarifies: true),
  _Row('test two nodes', PlanTemplate.radios,
      minConfidence: 0.6, clarifies: true),
  _Row('hello there', PlanTemplate.antennas,
      minConfidence: 0.3, clarifies: true),
  _Row('', PlanTemplate.antennas, minConfidence: 0.3, clarifies: true),
  _Row('whip, dipole, yagi, and a 2 hour walk', PlanTemplate.antennas,
      variants: ['whip', 'dipole', 'yagi'], minutes: 60, minConfidence: 0.9),
  _Row('SF7 against SF9 repeat', PlanTemplate.rangeSettings,
      repeat: true, minConfidence: 0.6, clarifies: true),
  _Row('compare the Heltec with the T1000-E on the base', PlanTemplate.radios,
      variants: ['Heltec V3', 'T1000-E'],
      side: PlanSide.mobile,
      minConfidence: 0.9),
];

void main() {
  group('LocalPlanIntentParser', () {
    const parser = LocalPlanIntentParser();

    for (final r in _rows) {
      test('"${r.text}"', () async {
        final g = await parser.parse(r.text, ctx: _ctx);
        final i = g.intent;
        expect(i.validate(), isNull, reason: 'always a valid intent');
        expect(g.fromAi, isFalse);
        expect(i.template, r.template);
        expect(i.side, r.side);
        expect(i.repeat, r.repeat);
        expect(i.route.kind, r.kind);
        if (r.minutes != null) expect(i.route.minutes, r.minutes);
        if (r.variants != null) expect(i.variants, r.variants);
        expect(
            g.confidence, inInclusiveRange(r.minConfidence, r.maxConfidence));
        expect(g.clarification, r.clarifies ? isNotNull : isNull);
        if (r.text.isNotEmpty) expect(i.question, r.text);
      });
    }

    test('placeholders ask for the names', () async {
      final g = await parser.parse('antennas', ctx: _ctx);
      expect(g.intent.variants, ['Antenna A', 'Antenna B']);
      expect(g.clarification, contains('Which two antennas'));
      final p = await parser.parse('tx power', ctx: const ParserContext());
      expect(p.intent.template, PlanTemplate.txPower);
      expect(p.intent.validate(), isNull);
      expect(p.clarification, contains('dBm'));
    });

    test('a single named variant gets a placeholder partner', () async {
      final g = await parser.parse('test the stock whip', ctx: _ctx);
      expect(g.intent.template, PlanTemplate.antennas);
      expect(g.intent.variants.first, 'Stock whip');
      expect(g.intent.variants.length, 2);
      expect(g.confidence, 0.6);
      expect(g.clarification, contains('Stock whip'));
    });

    test('truncates to the variant limit and keeps names unique', () async {
      final g = await parser.parse(
          'compare antennas "A", "B", "C", "D", "E", "b"',
          ctx: const ParserContext());
      expect(g.intent.variants, ['A', 'B', 'C', 'D']);
      expect(g.intent.validate(), isNull);
    });

    test('presets without a radio use the Meshtastic names', () async {
      final g = await parser.parse('Long Fast or Short Turbo?',
          ctx: const ParserContext());
      expect(g.intent.variants, ['LONG_FAST', 'SHORT_TURBO']);
    });

    test('route minutes are clamped to the limits', () async {
      final short = await parser.parse('how far, 2 minute walk', ctx: _ctx);
      expect(short.intent.route.minutes, PlanLimits.minRouteMinutes);
      final long = await parser.parse('how far, 3 hours', ctx: _ctx);
      expect(long.intent.route.minutes, PlanLimits.maxRouteMinutes);
    });

    test('a position in the text is not kept as the question', () async {
      final g =
          await parser.parse('antennas from 33.68007, -116.24006', ctx: _ctx);
      expect(g.intent.question, isNull);
      expect(g.intent.template, PlanTemplate.antennas);
    });
  });

  group('AiPlanIntentParser', () {
    late SharedPreferences prefs;
    late FakePlanIntentGateway gateway;

    Map<String, dynamic> reply({
      String template = 'antennas',
      List<String> variants = const ['Stock whip', '5.8 dBi fiberglass'],
      double confidence = 0.95,
      String? clarification,
    }) =>
        {
          'intent': {
            'template': template,
            'side': 'mobile',
            'variants': variants,
            'repeat': false,
            'route': {'kind': 'walk', 'minutes': 15},
          },
          'confidence': confidence,
          'clarification': clarification,
          'model': 'claude-haiku-5-5',
        };

    AiPlanIntentParser parser({Duration? timeout}) => AiPlanIntentParser(
          prefs: prefs,
          gateway: gateway,
          timeout: timeout ?? AiPlanIntentParser.defaultTimeout,
          appVersion: () async => '1.2.3+4',
        );

    setUp(() async {
      SharedPreferences.setMockInitialValues(
          {AppConstants.prefAiConsent: true});
      prefs = await SharedPreferences.getInstance();
      gateway = FakePlanIntentGateway(reply: reply());
    });

    test('happy path: the backend intent, marked fromAi', () async {
      final g =
          await parser().parse('test my two antennas up the hill', ctx: _ctx);
      expect(g.fromAi, isTrue);
      expect(g.confidence, 0.95);
      expect(g.clarification, isNull);
      expect(g.intent.template, PlanTemplate.antennas);
      expect(g.intent.variants, ['Stock whip', '5.8 dBi fiberglass']);
      expect(g.intent.route.minutes, 15);
      expect(g.intent.question, 'test my two antennas up the hill');
      expect(g.intent.validate(), isNull);

      final sent = gateway.received.single;
      expect(sent['kind'], 'plan');
      expect(sent['text'], 'test my two antennas up the hill');
      expect(sent['protocol'], 'meshtastic');
      expect(sent['rigNames'], _ctx.rigNames);
      expect(sent['presets'], _ctx.presetNames);
      expect(sent['limits'], {
        'minVariants': 2,
        'maxVariants': 4,
        'minRouteMinutes': 5,
        'maxRouteMinutes': 60,
      });
      final templates = sent['templates'] as List;
      expect(templates.length, PlanTemplate.values.length);
      expect((templates.first as Map).keys,
          containsAll(['id', 'chip', 'variantsMean']));
      expect(sent.keys, isNot(contains('nodeId')));
      expect(gateway.deviceIds.single,
          prefs.getString(AppConstants.prefAiDeviceId));
    });

    test('clarification is passed through, confidence clamped', () async {
      gateway.reply = reply(confidence: 1.7, clarification: '  Which two? ');
      final g = await parser().parse('antennas', ctx: _ctx);
      expect(g.fromAi, isTrue);
      expect(g.confidence, 1.0);
      expect(g.clarification, 'Which two?');
    });

    test('no consent: local guess, nothing sent', () async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      final g = await parser().parse('long fast vs medium fast', ctx: _ctx);
      expect(g.fromAi, isFalse);
      expect(g.intent.variants, ['LONG_FAST', 'MEDIUM_FAST']);
      expect(gateway.received, isEmpty);
    });

    test('coordinate-like text stays on the phone', () async {
      final g =
          await parser().parse('antennas near 33.68007, -116.24006', ctx: _ctx);
      expect(g.fromAi, isFalse);
      expect(g.intent.template, PlanTemplate.antennas);
      expect(g.intent.question, isNull);
      expect(gateway.received, isEmpty);
    });

    test('too long or empty text is not sent', () async {
      expect((await parser().parse('x' * 501, ctx: _ctx)).fromAi, isFalse);
      expect((await parser().parse('   ', ctx: _ctx)).fromAi, isFalse);
      expect(gateway.received, isEmpty);
    });

    test('429 falls back locally', () async {
      gateway.error = const AiAnalysisLimitException('limit', reason: 'daily');
      final g = await parser().parse('does 20 dBm beat 10 dBm', ctx: _ctx);
      expect(g.fromAi, isFalse);
      expect(g.intent.template, PlanTemplate.txPower);
      expect(g.intent.variants, ['20', '10']);
    });

    test('HTTP error and network errors fall back locally', () async {
      gateway.error = const HttpStatusException(502, 'plan failed');
      expect((await parser().parse('how far does it reach', ctx: _ctx)).fromAi,
          isFalse);
      gateway.error = StateError('socket');
      final g = await parser().parse('how far does it reach', ctx: _ctx);
      expect(g.fromAi, isFalse);
      expect(g.intent.template, PlanTemplate.reach);
    });

    test('unparsable or invalid replies fall back locally', () async {
      gateway.reply = {'nonsense': true};
      expect((await parser().parse('antennas', ctx: _ctx)).fromAi, isFalse);
      gateway.reply = {'intent': 'antennas'};
      expect((await parser().parse('antennas', ctx: _ctx)).fromAi, isFalse);
      // Valid JSON, invalid intent: one variant for a comparison.
      gateway.reply = reply(variants: ['Only one']);
      expect((await parser().parse('antennas', ctx: _ctx)).fromAi, isFalse);
      // Unknown template id decodes to antennas, but radios on the base
      // side is refused by validate().
      gateway.reply = {
        'intent': {
          'template': 'radios',
          'side': 'base',
          'variants': ['A', 'B'],
        },
        'confidence': 0.9,
      };
      final g = await parser().parse('compare nodes', ctx: _ctx);
      expect(g.fromAi, isFalse);
      expect(g.intent.validate(), isNull);
    });

    test('a slow backend times out into the local guess', () async {
      gateway.delay = const Duration(milliseconds: 200);
      final g = await parser(timeout: const Duration(milliseconds: 20))
          .parse('how far does it reach', ctx: _ctx);
      expect(g.fromAi, isFalse);
      expect(g.intent.template, PlanTemplate.reach);
    });

    test('never caches: every call goes to the backend', () async {
      final p = parser();
      await p.parse('antennas', ctx: _ctx);
      await p.parse('antennas', ctx: _ctx);
      expect(gateway.received.length, 2);
      expect(
          prefs.getKeys().where((k) =>
              k.startsWith(AppConstants.prefAiAnalysisPrefix) &&
              k != AppConstants.prefAiConsent),
          isEmpty);
    });

    group('over HTTP', () {
      final url = Uri.parse('https://ai.example.test/');
      late List<http.Request> requests;
      late int status;

      MockClient client() => MockClient((req) async {
            requests.add(req);
            return http.Response(
                status == 200 ? jsonEncode(reply()) : '{"error": "nope"}',
                status);
          });

      AiPlanIntentParser httpParser({String token = 'tok-123'}) =>
          AiPlanIntentParser(
            prefs: prefs,
            gateway:
                HttpPlanIntentGateway(url, client: client(), appToken: token),
            appVersion: () async => '1.2.3+4',
          );

      setUp(() {
        requests = [];
        status = 200;
      });

      test('switch off: no network call at all', () async {
        await prefs.setBool(AppConstants.prefAiConsent, false);
        final g = await httpParser().parse('test my antennas', ctx: _ctx);
        expect(g.fromAi, isFalse);
        expect(requests, isEmpty);
      });

      test('sends the app token header with the request', () async {
        final g = await httpParser().parse('test my antennas', ctx: _ctx);
        expect(g.fromAi, isTrue);
        final req = requests.single;
        expect(req.headers['X-App-Token'], 'tok-123');
        expect(req.headers['X-App-Version'], '1.2.3+4');
        expect(req.headers['X-Device-Id'],
            prefs.getString(AppConstants.prefAiDeviceId));
      });

      test('no token compiled in: local guess, no network call', () async {
        final p = httpParser(token: '');
        expect(p.gateway.canSend, isFalse);
        final g = await p.parse('test my antennas', ctx: _ctx);
        expect(g.fromAi, isFalse);
        expect(requests, isEmpty);
      });

      test('token refused (401/403): local guess', () async {
        for (final code in [401, 403]) {
          status = code;
          final g = await httpParser().parse('test my antennas', ctx: _ctx);
          expect(g.fromAi, isFalse, reason: 'HTTP $code');
        }
        expect(requests.length, 2);
      });

      test('the gateway throws AiUnavailableException without a token',
          () async {
        final gw = HttpPlanIntentGateway(url, client: client(), appToken: '');
        await expectLater(gw.plan(const {}, deviceId: 'd', appVersion: 'v'),
            throwsA(isA<AiUnavailableException>()));
        expect(requests, isEmpty);
      });
    });

    group('consent offer on the Ask screen', () {
      test('offered once while the switch is off', () async {
        await prefs.setBool(AppConstants.prefAiConsent, false);
        final p = parser();
        expect(p.shouldOfferConsent, isTrue);
        await p.markConsentOffered();
        expect(p.shouldOfferConsent, isFalse);
        expect(parser().shouldOfferConsent, isFalse);
      });

      test('not offered when already on or when nothing could be sent',
          () async {
        expect(parser().shouldOfferConsent, isFalse);
        await prefs.setBool(AppConstants.prefAiConsent, false);
        gateway.canSend = false;
        expect(parser().shouldOfferConsent, isFalse);
      });
    });
  });
}
