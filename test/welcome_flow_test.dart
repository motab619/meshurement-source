// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:geolocator/geolocator.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/base_node.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/services/privacy_settings.dart';
import 'package:mesh_analyzer/ui/screens/onboarding/welcome_flow.dart';
import 'package:mesh_analyzer/ui/theme/app_theme.dart';
import 'package:mesh_analyzer/ui/widgets/coverage_diagram.dart';
import 'package:mesh_analyzer/utils/constants.dart';

import 'fakes/fake_location_backend.dart';
import 'fakes/fake_mesh_radio.dart';
import 'fakes/fake_radio_scanner.dart';

Future<SharedPreferences> _prefs([Map<String, Object>? v]) async {
  SharedPreferences.setMockInitialValues(v ?? {});
  return SharedPreferences.getInstance();
}

/// A home screen with a button that opens the flow, plus a probe that shows
/// the live privacyProvider state.
/// Location not yet asked for; granted on request.
FakeLocationBackend _location = FakeLocationBackend(
    permission: LocationPermission.denied,
    afterRequest: LocationPermission.whileInUse);

Widget _app(SharedPreferences prefs, {ThemeData? theme}) => ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiAnalysisAvailableProvider.overrideWithValue(true),
        gpsServiceProvider.overrideWithValue(GpsService(backend: _location)),
        radioScannerProvider.overrideWithValue(FakeRadioScanner(const [])),
        meshRadioProvider.overrideWithValue(FakeMeshRadio(myNodeId: 1)),
      ],
      child: MaterialApp(
        theme: theme,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Column(
              children: [
                Text('tiles=${ref.watch(privacyProvider).mapTiles}'),
                TextButton(
                  onPressed: () => showWelcomeFlow(context),
                  child: const Text('open'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester, SharedPreferences prefs) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(prefs));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('four pages, Next ×3, then Done sets the flag', (tester) async {
    final prefs = await _prefs();
    await _open(tester, prefs);

    expect(find.text('01/04'), findsOneWidget);
    expect(find.text('See how far your mesh really reaches'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('02/04'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('03/04'), findsOneWidget);
    // flutter test reports Android as the platform.
    expect(find.text('Three things the app asks Android for'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Radios last, so the flow ends on Open Radio Setup.
    expect(find.text('04/04'), findsOneWidget);
    expect(find.text('Open Node Setup'), findsOneWidget);
    expect(prefs.getBool(onboardingSeenKey), isNull);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeFlow), findsNothing);
    expect(prefs.getBool(onboardingSeenKey), isTrue);
  });

  testWidgets('Permissions page asks for Location; granted shows a tick',
      (tester) async {
    _location = FakeLocationBackend(
        permission: LocationPermission.denied,
        afterRequest: LocationPermission.whileInUse);
    final prefs = await _prefs();
    await _open(tester, prefs);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    final allow = find.byKey(const ValueKey('welcome-allow-location'));
    expect(allow, findsOneWidget);
    expect(find.textContaining('Marks where the base sits'), findsOneWidget);
    await tester.tap(allow);
    await tester.pumpAndSettle();
    expect(_location.requests, 1);
    expect(allow, findsNothing);
    expect(find.byKey(const ValueKey('welcome-location-ok')), findsOneWidget);

    // Bluetooth: the fake scanner (demo) reads as on once asked.
    final bt = find.byKey(const ValueKey('welcome-allow-bluetooth'));
    expect(find.byKey(const ValueKey('welcome-bluetooth-ok')), findsOneWidget);
    expect(bt, findsNothing);
    // Notifications: no iOS plugin in tests, so the answer stays unknown
    // and the button stays; tapping it must not throw.
    final notify = find.byKey(const ValueKey('welcome-allow-notifications'));
    expect(notify, findsOneWidget);
    await tester.tap(notify);
    await tester.pumpAndSettle();
    expect(notify, findsOneWidget);
  });

  testWidgets('Skip closes the flow and sets the flag', (tester) async {
    final prefs = await _prefs();
    await _open(tester, prefs);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeFlow), findsNothing);
    expect(prefs.getBool(onboardingSeenKey), isTrue);
  });

  testWidgets('privacy switch writes through to privacyProvider',
      (tester) async {
    final prefs = await _prefs();
    await _open(tester, prefs);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('AI helpers'), findsOneWidget);
    await tester.tap(find.text('Map tiles'));
    await tester.pump();
    expect(prefs.getBool(AppConstants.prefMapTilesEnabled), isFalse);
    await tester.tap(find.text('Ground height lookups'));
    await tester.pump();
    expect(AppConstants.terrainOnlineEnabled(prefs), isTrue);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    // The home screen reads the same provider state.
    expect(find.text('tiles=false'), findsOneWidget);
  });

  group('iPhone 18 Pro size (402×874 pt, safe area 62/34)', () {
    // Real glyph widths, not the test font's 1 em squares: the app's B612
    // and B612 Mono, and B612 again standing in for the system face the
    // prose uses (Roboto under the test platform). B612 is wider than SF,
    // so a layout that fits here fits on the phone.
    setUpAll(() async {
      Future<void> load(String family, List<String> files) async {
        final loader = FontLoader(family);
        for (final f in files) {
          final bytes = File('assets/fonts/$f').readAsBytesSync();
          loader.addFont(Future.value(ByteData.sublistView(bytes)));
        }
        await loader.load();
      }

      const b612 = ['B612-Regular.ttf', 'B612-Bold.ttf'];
      await load('B612', b612);
      await load('Roboto', b612);
      await load('B612Mono', ['B612Mono-Regular.ttf', 'B612Mono-Bold.ttf']);
    });

    Future<void> openPhone(WidgetTester tester, SharedPreferences prefs) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.padding =
          const FakeViewPadding(top: 62 * 3.0, bottom: 34 * 3.0);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(prefs, theme: AppTheme.dark()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    /// Top of the Next / Done button: the bar under the pages.
    double barTop(WidgetTester tester, String label) =>
        tester.getTopLeft(find.widgetWithText(FilledButton, label)).dy;

    testWidgets('Notifications Allow is on screen without scrolling',
        (tester) async {
      _location = FakeLocationBackend(
          permission: LocationPermission.denied,
          afterRequest: LocationPermission.whileInUse);
      final prefs = await _prefs();
      await openPhone(tester, prefs);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('03/04'), findsOneWidget);

      final notify = find.byKey(const ValueKey('welcome-allow-notifications'));
      expect(notify, findsOneWidget);
      final bottom = tester.getBottomLeft(notify).dy;
      expect(bottom, lessThan(874 - 34));
      expect(bottom, lessThanOrEqualTo(barTop(tester, 'Next')));
      // The reason line under it is on screen too.
      final reason = find.textContaining('Alerts you on the lock screen');
      expect(tester.getBottomLeft(reason).dy,
          lessThanOrEqualTo(barTop(tester, 'Next')));
      // Location's Allow too (the first row).
      expect(
          tester
              .getBottomLeft(
                  find.byKey(const ValueKey('welcome-allow-location')))
              .dy,
          lessThan(barTop(tester, 'Next')));
    });

    testWidgets('Privacy: AI helpers and the policy link fit; Details opens',
        (tester) async {
      final prefs = await _prefs();
      await openPhone(tester, prefs);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('02/04'), findsOneWidget);

      final next = barTop(tester, 'Next');
      expect(tester.getBottomLeft(find.text('AI helpers')).dy,
          lessThanOrEqualTo(next));
      expect(tester.getBottomLeft(find.text('Privacy policy')).dy,
          lessThanOrEqualTo(next));

      // The long wording is behind Details.
      expect(find.textContaining('on to Anthropic'), findsNothing);
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('welcome-details-ai')),
          matching: find.text('Details')));
      await tester.pumpAndSettle();
      expect(find.textContaining('on to Anthropic'), findsOneWidget);
    });
  });

  testWidgets('page 01 has the short trademark line; page 04 the diagram',
      (tester) async {
    final prefs = await _prefs();
    await _open(tester, prefs);
    expect(find.text(welcomeTrademarkLine), findsOneWidget);
    expect(welcomeTrademarkLine, contains('Meshtastic® is a trademark'));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.byType(CoverageDiagram), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('base node stays in one place')),
        findsOneWidget);
  });

  group('shouldShowWelcome', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('fresh install: show, flag left unset', () async {
      final prefs = await _prefs();
      expect(await shouldShowWelcome(prefs, db), isTrue);
      expect(prefs.getBool(onboardingSeenKey), isNull);
    });

    test('already seen: not shown', () async {
      final prefs = await _prefs({onboardingSeenKey: true});
      expect(await shouldShowWelcome(prefs, db), isFalse);
    });

    test('existing install with a map counts as seen, checklist hidden',
        () async {
      final prefs = await _prefs();
      await db.createCoverageMap(name: 'Home', baseNodeId: 1);
      expect(await shouldShowWelcome(prefs, db), isFalse);
      expect(prefs.getBool(onboardingSeenKey), isTrue);
      expect(prefs.getBool(onboardingChecklistHiddenKey), isTrue);
    });

    test('fresh install leaves the checklist visible', () async {
      final prefs = await _prefs();
      expect(await shouldShowWelcome(prefs, db), isTrue);
      expect(prefs.getBool(onboardingChecklistHiddenKey), isNull);
    });

    test('existing install with a session counts as seen', () async {
      final prefs = await _prefs();
      final mapId = await db.createCoverageMap(name: 'Home', baseNodeId: 1);
      await db.createSession(coverageMapId: mapId);
      // Only the session left (the map row gone).
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await (db.delete(db.coverageMaps)..where((m) => m.id.equals(mapId))).go();
      expect(await shouldShowWelcome(prefs, db), isFalse);
      expect(prefs.getBool(onboardingSeenKey), isTrue);
    });

    test('existing install with a Radio Setup base counts as seen', () async {
      final prefs = await _prefs({baseNodePrefKey: 0x1234});
      expect(await shouldShowWelcome(prefs, db), isFalse);
      expect(prefs.getBool(onboardingSeenKey), isTrue);
    });
  });
}
