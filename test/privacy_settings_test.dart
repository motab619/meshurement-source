// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/demo/demo_mode.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/privacy_settings.dart';
import 'package:mesh_analyzer/ui/screens/privacy_screen.dart';
import 'package:mesh_analyzer/ui/widgets/base_map_layers.dart';
import 'package:mesh_analyzer/ui/widgets/terrain_opt_in_sheet.dart';
import 'package:mesh_analyzer/utils/constants.dart';
import 'package:mesh_analyzer/utils/map_tiles.dart';

Future<SharedPreferences> _prefs([Map<String, Object>? v]) async {
  SharedPreferences.setMockInitialValues(v ?? {});
  return SharedPreferences.getInstance();
}

Widget _app(SharedPreferences prefs, Widget home) => ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        aiAnalysisAvailableProvider.overrideWithValue(true),
        mapTileConfigProvider.overrideWithValue(MapTileConfig.fromValues()),
      ],
      child: MaterialApp(home: home),
    );

void main() {
  test('defaults: tiles on, terrain off, AI off', () async {
    final s = PrivacyState.load(await _prefs());
    expect(s.mapTiles, isTrue);
    expect(s.terrain, isFalse);
    expect(s.aiConsent, isFalse);
  });

  test('existing AI consent and terrain opt-in are kept', () async {
    final s = PrivacyState.load(await _prefs({
      AppConstants.prefAiConsent: true,
      AppConstants.prefTerrainOnlineEnabled: true,
    }));
    expect(s.aiConsent, isTrue);
    expect(s.terrain, isTrue);
  });

  test('notifier persists to the feature prefs', () async {
    final prefs = await _prefs();
    final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    final n = c.read(privacyProvider.notifier);
    await n.setMapTiles(false);
    await n.setTerrain(true);
    await n.setAiConsent(true);
    expect(prefs.getBool(AppConstants.prefMapTilesEnabled), isFalse);
    expect(AppConstants.terrainOnlineEnabled(prefs), isTrue);
    expect(prefs.getBool(AppConstants.prefAiConsent), isTrue);
    expect(c.read(mapTilesEnabledProvider), isFalse);
  });

  testWidgets('switches on the Privacy screen persist', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);
    final prefs = await _prefs();
    await tester.pumpWidget(_app(prefs, const PrivacyScreen()));
    await tester.tap(find.text('Map tiles'));
    await tester.pump();
    expect(prefs.getBool(AppConstants.prefMapTilesEnabled), isFalse);
    await tester.tap(find.text('Ground height lookups'));
    await tester.pump();
    expect(AppConstants.terrainOnlineEnabled(prefs), isTrue);
    expect(find.text('Privacy policy'), findsOneWidget);
  });

  testWidgets('AI switch shares the consent sheet pref; off revokes + clears',
      (tester) async {
    final prefs = await _prefs({
      '${AppConstants.prefAiAnalysisPrefix}abc': '{}',
      AppConstants.prefAiDeviceId: 'id',
    });
    await tester.pumpWidget(_app(prefs, const PrivacyScreen()));
    await tester.tap(find.text('AI helpers'));
    await tester.pumpAndSettle();
    expect(find.text('What is sent'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(prefs.getBool(AppConstants.prefAiConsent), isNot(true));

    await tester.tap(find.text('AI helpers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(prefs.getBool(AppConstants.prefAiConsent), isTrue);

    await tester.tap(find.text('AI helpers'));
    await tester.pumpAndSettle();
    expect(prefs.getBool(AppConstants.prefAiConsent), isFalse);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(
        prefs.containsKey('${AppConstants.prefAiAnalysisPrefix}abc'), isFalse);
    expect(prefs.getString(AppConstants.prefAiDeviceId), 'id');
  });

  Widget map() => const FlutterMap(
        options:
            MapOptions(initialCenter: LatLng(33.7, -116.2), initialZoom: 12),
        children: [BaseMapLayers()],
      );

  testWidgets('tiles on: a tile layer; off: none, with a hint', (tester) async {
    final on = await _prefs();
    await tester.pumpWidget(_app(on, Scaffold(body: map())));
    expect(find.byType(TileLayer), findsOneWidget);
    expect(find.textContaining('Map tiles are off'), findsNothing);

    final off = await _prefs({AppConstants.prefMapTilesEnabled: false});
    await tester.pumpWidget(_app(off, Scaffold(body: map())));
    await tester.pump();
    expect(find.byType(TileLayer), findsNothing);
    expect(find.text('Map tiles are off — Settings → Privacy'), findsOneWidget);
  });

  testWidgets('demo mode draws tiles even when off', (tester) async {
    DemoMode.enabled = true;
    addTearDown(() => DemoMode.enabled = false);
    final off = await _prefs({AppConstants.prefMapTilesEnabled: false});
    await tester.pumpWidget(_app(off, Scaffold(body: map())));
    expect(find.byType(TileLayer), findsOneWidget);
  });

  group('terrain gate', () {
    Future<bool?> run(
        WidgetTester tester, SharedPreferences prefs, String? tap) async {
      bool? result;
      await tester.pumpWidget(_app(
          prefs,
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async =>
                  result = await ensureTerrainOptIn(context, ref),
              child: const Text('go'),
            ),
          )));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      if (tap != null) {
        expect(find.textContaining('Open Topo Data'), findsOneWidget);
        await tester.tap(find.text(tap));
        await tester.pumpAndSettle();
      } else {
        expect(find.text('Turn on'), findsNothing);
      }
      return result;
    }

    testWidgets('Not now leaves it off', (tester) async {
      final prefs = await _prefs();
      expect(await run(tester, prefs, 'Not now'), isFalse);
      expect(AppConstants.terrainOnlineEnabled(prefs), isFalse);
    });

    testWidgets('Turn on sets the same pref', (tester) async {
      final prefs = await _prefs();
      expect(await run(tester, prefs, 'Turn on'), isTrue);
      expect(AppConstants.terrainOnlineEnabled(prefs), isTrue);
    });

    testWidgets('already on: no sheet', (tester) async {
      final prefs = await _prefs({AppConstants.prefTerrainOnlineEnabled: true});
      expect(await run(tester, prefs, null), isTrue);
    });

    testWidgets('demo: no sheet', (tester) async {
      DemoMode.enabled = true;
      addTearDown(() => DemoMode.enabled = false);
      expect(await run(tester, await _prefs(), null), isTrue);
    });
  });
}
