// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/ai_analysis.dart';
import 'package:mesh_analyzer/services/privacy_settings.dart';
import 'package:mesh_analyzer/services/pro_entitlement.dart';
import 'package:mesh_analyzer/services/rig_comparison.dart';
import 'package:mesh_analyzer/ui/widgets/ai_analysis_card.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:mesh_analyzer/utils/user_errors.dart';

import 'pro_entitlement_test.dart' show FakeStore;

SidePoints _route(double rssi) => SidePoints(
      [for (var i = 0; i < 20; i++) 33.68],
      [for (var i = 0; i < 20; i++) -116.24 + i * 0.0003],
      [for (var i = 0; i < 20; i++) rssi],
      [for (var i = 0; i < 20; i++) 5.0],
    );

class _Env {
  final AppDatabase db;
  final List<Session> a, b;
  final SharedPreferences prefs;
  _Env(this.db, this.a, this.b, this.prefs);
}

Future<_Env> _env(WidgetTester tester, {Map<String, Object>? prefs}) async {
  SharedPreferences.setMockInitialValues(prefs ?? {});
  final env = await tester.runAsync(() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final node = await db.upsertNode(nodeId: 1, longName: 'Base');
    final mapId = await db.createCoverageMap(name: 'Map', baseNodeId: node);
    Future<Session> s() async => (await db.getSessionById(await db
        .createSession(coverageMapId: mapId, loraPreset: 'LONG_FAST')))!;
    return _Env(
        db, [await s()], [await s()], await SharedPreferences.getInstance());
  });
  addTearDown(() => tester.runAsync(env!.db.close));
  return env!;
}

Widget _app(_Env env, FakeAiAnalysisGateway gateway,
    {bool available = true, bool pro = true}) {
  final service = ProEntitlement(
      prefs: env.prefs,
      store: FakeStore(),
      clock: () => DateTime(2026, 10, 14),
      proOverride: pro);
  final cmp = compareRoutes(_route(-95), _route(-90))!;
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(env.db),
      sharedPreferencesProvider.overrideWithValue(env.prefs),
      proEntitlementProvider.overrideWithValue(service),
      aiAnalysisAvailableProvider.overrideWithValue(available),
      aiAnalysisGatewayProvider.overrideWithValue(gateway),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AiAnalysisCard(
            a: env.a,
            b: env.b,
            result: cmp,
            expected: expectedRigDelta(env.a, env.b),
            check: checkComparable(env.a, env.b),
          ),
        ),
      ),
    ),
  );
}

/// Lets real async work (drift) finish between fake-clock pumps.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('hidden when the backend is not configured', (tester) async {
    final env = await _env(tester);
    await tester
        .pumpWidget(_app(env, FakeAiAnalysisGateway(), available: false));
    expect(find.text('Reading it'), findsNothing);
    expect(find.text('Analyze with AI'), findsNothing);
  });

  testWidgets('consent sheet, then result; consent is remembered',
      (tester) async {
    final env = await _env(tester);
    final gateway = FakeAiAnalysisGateway();
    await tester.pumpWidget(_app(env, gateway));
    expect(find.text('Reading it'), findsOneWidget);

    await tester.tap(find.text('Analyze with AI'));
    await tester.pumpAndSettle();
    expect(find.text('What is sent'), findsOneWidget);
    expect(find.text('What is not sent'), findsOneWidget);
    expect(find.textContaining('Your route, GPS positions'), findsOneWidget);
    expect(find.textContaining('question or context you type'), findsOneWidget);
    expect(find.textContaining('install id'), findsOneWidget);
    expect(find.text('What to expect'), findsOneWidget);
    expect(find.textContaining('can misread them'), findsOneWidget);

    // "Not now" sends nothing and does not store consent.
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(gateway.received, isEmpty);
    expect(env.prefs.getBool(AppConstants.prefAiConsent), isNull);

    await tester.tap(find.text('Analyze with AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send & analyze'));
    await _settle(tester);

    expect(gateway.received, hasLength(1));
    expect(find.text(FakeAiAnalysisGateway.sample.headline), findsOneWidget);
    expect(find.textContaining('18 of 20'), findsOneWidget);
    expect(find.text('Next step'), findsOneWidget);
    expect(find.textContaining('Written by Claude Haiku'), findsOneWidget);
    expect(find.text('Report a problem'), findsOneWidget);
    expect(env.prefs.getBool(AppConstants.prefAiConsent), isTrue);
    // Same state the Settings → Privacy switch shows.
    expect(
        ProviderScope.containerOf(tester.element(find.byType(AiAnalysisCard)))
            .read(privacyProvider)
            .aiConsent,
        isTrue);

    // Analyze again: no second consent sheet, a fresh request.
    await tester.tap(find.text('Analyze again'));
    await _settle(tester);
    expect(find.text('What is sent'), findsNothing);
    expect(gateway.received, hasLength(2));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('shows a plain-English error', (tester) async {
    final env = await _env(tester, prefs: {AppConstants.prefAiConsent: true});
    final gateway =
        FakeAiAnalysisGateway(error: const HttpStatusException(429));
    await tester.pumpWidget(_app(env, gateway));
    await tester.tap(find.text('Analyze with AI'));
    await _settle(tester);
    expect(find.text('Daily limit reached. Try again tomorrow.'), findsOneWidget);
    expect(find.text('Analyze with AI'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('a missing or refused app token reads as unavailable',
      (tester) async {
    final env = await _env(tester, prefs: {AppConstants.prefAiConsent: true});
    final gateway =
        FakeAiAnalysisGateway(error: const AiUnavailableException());
    await tester.pumpWidget(_app(env, gateway));
    await tester.tap(find.text('Analyze with AI'));
    await _settle(tester);
    expect(find.text('AI analysis is unavailable.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('a usage limit reads as a note, not an error', (tester) async {
    final env = await _env(tester, prefs: {AppConstants.prefAiConsent: true});
    final gateway = FakeAiAnalysisGateway(
        error: const AiAnalysisLimitException(
            "You've used this month's 300 analyses; more on the 1st (UTC).",
            reason: 'monthly'));
    await tester.pumpWidget(_app(env, gateway));
    await tester.tap(find.text('Analyze with AI'));
    await _settle(tester);
    expect(find.text('Analysis limit reached'), findsOneWidget);
    final line = find
        .text("You've used this month's 300 analyses; more on the 1st (UTC).");
    expect(line, findsOneWidget);
    final context = tester.element(line);
    expect(tester.widget<Text>(line).style?.color,
        isNot(Theme.of(context).colorScheme.error));
    expect(find.text('Analyze with AI'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('reopening shows the cached result without a request',
      (tester) async {
    final env = await _env(tester);
    await env.prefs.setString(
        aiAnalysisCacheKey(
            [for (final s in env.a) s.id], [for (final s in env.b) s.id]),
        '{"headline":"Cached headline","bullets":["one"],"caveats":[],'
        '"next_step":"","model":"claude-haiku-5-5"}');
    final gateway = FakeAiAnalysisGateway();
    await tester.pumpWidget(_app(env, gateway));
    expect(find.text('Cached headline'), findsOneWidget);
    expect(gateway.received, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('non-Pro tapping Analyze sees the paywall', (tester) async {
    final env = await _env(tester);
    final gateway = FakeAiAnalysisGateway();
    await tester.pumpWidget(_app(env, gateway, pro: false));
    await tester.tap(find.text('Analyze with AI'));
    await tester.pumpAndSettle();
    expect(find.text('AI session analysis is a Pro feature.'), findsOneWidget);
    expect(gateway.received, isEmpty);
  });
}
