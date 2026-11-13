// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/field_report/comparison_report_data.dart';
import 'package:mesh_analyzer/services/field_report/field_report_data.dart';
import 'package:mesh_analyzer/services/field_report/field_report_loader.dart';
import 'package:mesh_analyzer/services/field_report/private_route.dart';
import 'package:mesh_analyzer/services/pro_entitlement.dart';
import 'package:mesh_analyzer/ui/screens/pro_paywall_screen.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/comparison_report_card.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/field_report_card.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/field_report_sheet.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/report_basemap.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/report_parts.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/report_style.dart';
import 'package:mesh_analyzer/ui/widgets/field_report/report_theme.dart';
import 'package:mesh_analyzer/utils/app_info.dart';

import '../pro_entitlement_test.dart' show FakeStore;
import 'fixtures.dart';

const _base = (lat: baseLat, lon: baseLon);

ComparisonReportData _comparison(int sides) => ComparisonReportData.build(
    [
      testSide('Stock stubby', 1, 600, 0),
      testSide('5.8 dBi whip', 2, 1500, 6),
      if (sides > 2) testSide('Yagi', 3, 900, 3),
      if (sides > 3) testSide('Long Fast', 4, 700, 1),
    ].take(sides).toList(),
    base: _base);

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({'distance_units': 'miles'});
    PackageInfo.setMockInitialValues(
      appName: 'Meshurement',
      packageName: 'x',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<Widget> app(FieldReportLoad load, {bool pro = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final service =
        ProEntitlement(prefs: prefs, store: FakeStore(), proOverride: pro);
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        proEntitlementProvider.overrideWithValue(service),
      ],
      child: MaterialApp(home: Scaffold(body: FieldReportSheet(load: load))),
    );
  }

  // The style thumbnails hold cards too: look inside the big preview.
  Finder inPreview(Finder f) => find.descendant(
      of: find.byKey(const ValueKey('field-report-preview')), matching: f);

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<FieldReportData> session32(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final s = await seedSession32(db);
        return FieldReportLoader(db).session(s.sessionId);
      }))!;

  testWidgets('title is the range setting and date, never the session name',
      (tester) async {
    bigScreen(tester);
    final d = await session32(tester);
    await tester.pumpWidget(await app((_) async => SingleReport(d)));
    await tester.pumpAndSettle();

    final field = tester
        .widget<TextField>(find.byKey(const ValueKey('field-report-title')));
    expect(field.controller!.text, 'Short Turbo · Oct 28, 2026');
    expect(find.textContaining('short turbo EOD'), findsNothing);
    // Card header shows the title; the footer is always there.
    expect(find.text('Short Turbo · Oct 28, 2026'), findsWidgets);
    expect(inPreview(find.text(AppInfo.website)), findsOneWidget);
    // Miles region: 400 m headline in miles, hide choices in feet.
    expect(inPreview(find.text('0.2 mi')), findsOneWidget);
    expect(find.text('400 ft'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('field-report-title')), 'Evening walk');
    await tester.pump();
    expect(find.text('Evening walk'), findsWidgets);
    // The session keeps its name.
    final s =
        await tester.runAsync(() => db.getSessionById(d.sessionIds.single));
    expect(s!.name, 'short turbo EOD');
  });

  testWidgets('Points only reaches the card and is remembered',
      (tester) async {
    bigScreen(tester);
    final d = await session32(tester);
    await tester.pumpWidget(await app((_) async => SingleReport(d)));
    await tester.pumpAndSettle();
    FieldReportCard card() =>
        tester.widget<FieldReportCard>(inPreview(find.byType(FieldReportCard)));
    expect(card().showPath, isTrue);

    await tester.ensureVisible(find.text('Points only'));
    await tester.tap(find.text('Points only'));
    await tester.pumpAndSettle();
    expect(card().showPath, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(reportShowPathPref), isFalse);

    // Reopen: the choice comes back.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(await app((_) async => SingleReport(d)));
    await tester.pumpAndSettle();
    expect(card().showPath, isFalse);
  });

  testWidgets('format switch changes the preview shape', (tester) async {
    bigScreen(tester);
    final d = await session32(tester);
    await tester.pumpWidget(await app((_) async => SingleReport(d)));
    await tester.pumpAndSettle();
    double ratio() {
      final s =
          tester.getSize(find.byKey(const ValueKey('field-report-preview')));
      return s.height / s.width;
    }

    expect(ratio(), closeTo(1350 / 1080, 0.01));
    await tester.tap(find.text('Story'));
    await tester.pumpAndSettle();
    expect(ratio(), closeTo(1920 / 1080, 0.01));
    expect(inPreview(find.byType(FieldReportCard)), findsOneWidget);
    await tester.tap(find.text('Wide'));
    await tester.pumpAndSettle();
    expect(ratio(), closeTo(675 / 1200, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('two-setup comparison shares free', (tester) async {
    bigScreen(tester);
    await tester
        .pumpWidget(await app((_) async => ComparisonReport(_comparison(2))));
    await tester.pumpAndSettle();
    expect(inPreview(find.byType(ComparisonReportCard)), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Share'), findsOneWidget);
    expect(find.text('Share (Pro)'), findsNothing);
  });

  for (final n in [3, 4]) {
    testWidgets('$n-setup comparison is Pro: the paywall opens',
        (tester) async {
      bigScreen(tester);
      await tester
          .pumpWidget(await app((_) async => ComparisonReport(_comparison(n))));
      await tester.pumpAndSettle();
      // The preview is free to look at; sharing it is Pro.
      expect(inPreview(find.byType(ComparisonReportCard)), findsOneWidget);
      expect(find.text('Share (Pro)'), findsOneWidget);
      await tester.tap(find.text('Share (Pro)'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ProPaywallScreen), findsOneWidget);
    });
  }

  testWidgets('with Pro, four setups share', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(
        await app((_) async => ComparisonReport(_comparison(4)), pro: true));
    await tester.pumpAndSettle();
    expect(find.text('Share (Pro)'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Share'), findsOneWidget);
  });

  group('style picker', () {
    Finder tile(ReportTheme t) =>
        find.byKey(ValueKey('field-report-theme-${t.name}'));

    // The preview card is the one outside the picker row.
    T preview<T extends Widget>(WidgetTester tester) =>
        tester.widget<T>(find.descendant(
            of: find.byKey(const ValueKey('field-report-preview')),
            matching: find.byType(T)));

    testWidgets('five tiles for a single report, one live card each',
        (tester) async {
      bigScreen(tester);
      final d = await session32(tester);
      await tester.pumpWidget(await app((_) async => SingleReport(d)));
      await tester.pumpAndSettle();
      for (final t in ReportTheme.values) {
        expect(tile(t), findsOneWidget);
        expect(find.descendant(of: tile(t), matching: find.text(t.label)),
            findsOneWidget);
        final card = tester.widget<FieldReportCard>(find.descendant(
            of: tile(t), matching: find.byType(FieldReportCard)));
        expect(card.theme, t);
        expect(card.background, ReportBackground.plain);
        expect(card.tiles, isNull);
      }
      // Night is the default; free users see PRO tags on the Pro styles.
      expect(preview<FieldReportCard>(tester).theme, ReportTheme.night);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('field-report-theme')),
              matching: find.text('PRO')),
          findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('five tiles for a comparison; the pick reaches the card',
        (tester) async {
      bigScreen(tester);
      await tester
          .pumpWidget(await app((_) async => ComparisonReport(_comparison(2))));
      await tester.pumpAndSettle();
      for (final t in ReportTheme.values) {
        expect(tile(t), findsOneWidget);
      }
      expect(preview<ComparisonReportCard>(tester).theme, ReportTheme.night);
      await tester.tap(tile(ReportTheme.bridge));
      await tester.pumpAndSettle();
      expect(preview<ComparisonReportCard>(tester).theme, ReportTheme.bridge);
      // Two setups are free, the Bridge style is Pro.
      expect(find.text('Share (Pro)'), findsOneWidget);
    });

    testWidgets('picking a style updates the preview and is remembered',
        (tester) async {
      bigScreen(tester);
      final d = await session32(tester);
      await tester.pumpWidget(await app((_) async => SingleReport(d)));
      await tester.pumpAndSettle();
      await tester.tap(tile(ReportTheme.mission));
      await tester.pumpAndSettle();
      expect(preview<FieldReportCard>(tester).theme, ReportTheme.mission);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(reportThemePref), 'mission');

      // Reopen: the remembered Pro style comes back, even without Pro.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(await app((_) async => SingleReport(d)));
      await tester.pumpAndSettle();
      expect(preview<FieldReportCard>(tester).theme, ReportTheme.mission);
      expect(find.text('Share (Pro)'), findsOneWidget);
    });

    testWidgets('a free user on a Pro style: preview, then the paywall',
        (tester) async {
      bigScreen(tester);
      final d = await session32(tester);
      await tester.pumpWidget(await app((_) async => SingleReport(d)));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Share'), findsOneWidget);
      expect(find.byKey(const ValueKey('field-report-theme-pro-note')),
          findsNothing);

      await tester.tap(tile(ReportTheme.pop));
      await tester.pumpAndSettle();
      expect(preview<FieldReportCard>(tester).theme, ReportTheme.pop);
      expect(
          find.text('Pop, Bridge and Mission are part of ${AppInfo.proName}. '
              'You can preview them here.'),
          findsOneWidget);
      await tester.tap(find.text('Share (Pro)'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final paywall =
          tester.widget<ProPaywallScreen>(find.byType(ProPaywallScreen));
      expect(paywall.feature, ProFeature.reportStyles);
    });

    testWidgets('Basic is free', (tester) async {
      bigScreen(tester);
      final d = await session32(tester);
      await tester.pumpWidget(await app((_) async => SingleReport(d)));
      await tester.pumpAndSettle();
      await tester.tap(tile(ReportTheme.basic));
      await tester.pumpAndSettle();
      expect(preview<FieldReportCard>(tester).theme, ReportTheme.basic);
      expect(find.text('Share (Pro)'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Share'), findsOneWidget);
    });

    testWidgets('a Pro user shares any style, no tags', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(
          await app((_) async => ComparisonReport(_comparison(4)), pro: true));
      await tester.pumpAndSettle();
      await tester.tap(tile(ReportTheme.pop));
      await tester.pumpAndSettle();
      expect(find.text('Share (Pro)'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Share'), findsOneWidget);
      expect(find.text('PRO'), findsNothing);
      expect(find.byKey(const ValueKey('field-report-theme-pro-note')),
          findsNothing);
    });

    testWidgets('maps stay Night-only', (tester) async {
      bigScreen(tester);
      SharedPreferences.setMockInitialValues({
        'distance_units': 'miles',
        reportThemePref: 'basic',
      });
      await tester
          .pumpWidget(await app((_) async => ComparisonReport(_comparison(2))));
      await tester.pumpAndSettle();
      expect(preview<ComparisonReportCard>(tester).theme, ReportTheme.basic);
      expect(find.text('Maps are only on the Night style for now.'),
          findsOneWidget);
    });
  });

  group('render smoke test', () {
    Future<void> render(WidgetTester tester, Widget card, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(Center(
          child: RepaintBoundary(
              key: key, child: SizedBox.fromSize(size: size, child: card))));
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await tester.runAsync(() => boundary.toImage()))!;
      expect(image.width, size.width.toInt());
      expect(image.height, size.height.toInt());
      image.dispose();
    }

    for (final f in ReportFormat.values) {
      testWidgets('session card, ${f.label}', (tester) async {
        final d = await session32(tester);
        for (final miles in [true, false]) {
          await render(
              tester,
              FieldReportCard(
                  data: d,
                  title: 'Short Turbo · Oct 28, 2026',
                  format: f,
                  miles: miles),
              f.size);
        }
      });

      testWidgets('comparison card, ${f.label}, 2 and 4 setups',
          (tester) async {
        for (final n in [2, 4]) {
          await render(
              tester,
              ComparisonReportCard(
                  data: _comparison(n),
                  title: 'Antennas',
                  format: f,
                  miles: false),
              f.size);
        }
      });
    }

    for (final f in ReportFormat.values) {
      testWidgets('the far-reading note sits under the route, ${f.label}',
          (tester) async {
        final d = await session32(tester);
        await render(
            tester,
            FieldReportCard(data: d, title: 'x', format: f, miles: true),
            f.size);
        final note = find.textContaining('had no second reading');
        expect(note, findsOneWidget);
        final box = tester.getRect(find.byType(RouteBox));
        final text = tester.getRect(note);
        expect(text.top, greaterThanOrEqualTo(box.bottom));
        expect(text.left, greaterThanOrEqualTo(box.left - 0.5));
        expect(text.bottom, lessThanOrEqualTo(f.size.height));
      });
    }

    testWidgets('a wrong-map session still renders, with a note',
        (tester) async {
      final d = (await tester.runAsync(() async {
        final s = await seedSession32(db, mapBaseNorthM: 49700);
        return FieldReportLoader(db).session(s.sessionId);
      }))!;
      await render(
          tester,
          FieldReportCard(
              data: d, title: 'x', format: ReportFormat.feed, miles: true),
          ReportFormat.feed.size);
      expect(find.textContaining("far from its map's base"), findsOneWidget);
      expect(find.text('route length'), findsOneWidget);
    });
  });
}
