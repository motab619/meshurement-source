// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mesh_analyzer/data/database/app_database.dart' show BeaconStats;
import 'package:mesh_analyzer/data/radio/ble/radio_services.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_presets.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/pro_entitlement.dart';
import 'package:mesh_analyzer/ui/protocol_text.dart';
import 'package:mesh_analyzer/ui/screens/about_screen.dart';
import 'package:mesh_analyzer/ui/screens/pro_paywall_screen.dart';
import 'package:mesh_analyzer/ui/screens/radio_setup_screen.dart';
import 'package:mesh_analyzer/ui/widgets/beacon_status.dart';
import 'package:mesh_analyzer/ui/widgets/connection_banner.dart';

import 'fakes/fake_mesh_radio.dart';
import 'fakes/fake_radio_scanner.dart';
import 'pro_entitlement_test.dart' show FakeStore;

const _permissions = MethodChannel('flutter.baseflow.com/permissions/methods');

const _meshCoreRadio = RadioDescriptor(
    id: 'MC-1', name: 'MeshCore-ab12', protocol: RadioProtocol.meshcore);
const _meshtasticRadio = RadioDescriptor(
    id: 'MT-1', name: 'Meshtastic_cd34', protocol: RadioProtocol.meshtastic);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Meshurement',
      packageName: 'x',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('connect dialog', () {
    /// Opens the connect dialog with [found] in the scan. Returns the
    /// phone's radio (disconnected).
    Future<FakeMeshRadio> openDialog(WidgetTester tester,
        {required bool pro}) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Bluetooth permission: granted.
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(_permissions, (call) async => 1);
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(_permissions, null));
      final prefs = await SharedPreferences.getInstance();
      final radio = FakeMeshRadio(state: RadioConnectionState.disconnected);
      final entitlement =
          ProEntitlement(prefs: prefs, store: FakeStore(), proOverride: pro);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          meshRadioProvider.overrideWithValue(radio),
          radioScannerProvider.overrideWithValue(
              FakeRadioScanner(const [_meshtasticRadio, _meshCoreRadio])),
          activeSessionProvider.overrideWith((ref) => Stream.value(null)),
          proEntitlementProvider.overrideWithValue(entitlement),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showConnectDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return radio;
    }

    testWidgets('lists MeshCore radios with their protocol tag',
        (tester) async {
      await openDialog(tester, pro: false);
      expect(find.text('MeshCore-ab12'), findsOneWidget);
      expect(find.text('Meshtastic_cd34'), findsOneWidget);
      expect(find.text('MeshCore'), findsOneWidget);
      expect(find.textContaining('coming soon'), findsNothing);
    });

    testWidgets('a MeshCore radio connects without Pro (free since 2026-11-05)',
        (tester) async {
      final radio = await openDialog(tester, pro: false);
      await tester.tap(find.text('MeshCore-ab12'));
      await tester.pumpAndSettle();
      expect(find.byType(ProPaywallScreen), findsNothing);
      expect(radio.descriptor?.protocol, RadioProtocol.meshcore);
      expect(find.text('Connect to a node'), findsNothing); // dialog closed
    });

    testWidgets('a Meshtastic radio never asks for Pro', (tester) async {
      final radio = await openDialog(tester, pro: false);
      await tester.tap(find.text('Meshtastic_cd34'));
      await tester.pumpAndSettle();
      expect(find.byType(ProPaywallScreen), findsNothing);
      expect(radio.descriptor?.id, 'MT-1');
    });
  });

  group('Radio Setup on MeshCore', () {
    Future<FakeMeshRadio> pump(
      WidgetTester tester, {
      double frequencyMHz = 910.525,
      MeshCorePreset? preset = MeshCorePresets.usa,
      int txPowerDbm = 22,
      List<RadioDescriptor> found = const [],
    }) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = await SharedPreferences.getInstance();
      final radio = FakeMeshRadio(
          myNodeId: 10,
          protocol: RadioProtocol.meshcore,
          currentPreset: preset?.radioPreset)
        ..regionFrequencyMHz = frequencyMHz
        ..regionName = preset?.title ?? ''
        ..onPublicChannel = preset != null
        ..radioSettings =
            RadioSettings(frequencyMHz: frequencyMHz, txPowerDbm: txPowerDbm);
      await radio.connect(const RadioDescriptor(
          id: 'A', name: 'a', protocol: RadioProtocol.meshcore));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          meshRadioProvider.overrideWithValue(radio),
          radioScannerProvider.overrideWithValue(FakeRadioScanner(found)),
        ],
        child: const MaterialApp(home: RadioSetupScreen()),
      ));
      await tester.pumpAndSettle();
      return radio;
    }

    String field(WidgetTester tester, String key) =>
        tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

    String frequencyLine(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('mc-frequency-line')))
        .textSpan!
        .toPlainText();

    testWidgets('with a base, "Change the base from here" says why not',
        (tester) async {
      SharedPreferences.setMockInitialValues({'base_node_num': 20});
      await pump(tester);
      final row = find.byKey(const ValueKey('remote-change-unavailable'));
      expect(row, findsOneWidget);
      expect(tester.widget<ListTile>(row).enabled, isFalse);
      expect(
          find.textContaining('MeshCore nodes can\'t be changed over the mesh'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('open-remote-change')), findsNothing);
      expect(find.byKey(const ValueKey('allow-remote')), findsNothing);
    });

    testWidgets('range setting, fixed frequency and power replace the picker',
        (tester) async {
      await pump(tester);
      expect(find.text('Range preset'), findsNothing);
      expect(find.text('Range setting'), findsOneWidget);
      // The radio's own modulation is preselected, named by the ladder.
      expect(find.text('Fast · SF7 / 62.5 kHz / 4/5'), findsOneWidget);
      expect(frequencyLine(tester),
          '918.000 MHz · the relay frequency for 915 MHz radios');
      // The free field only opens on request.
      expect(find.byKey(const ValueKey('mc-frequency')), findsNothing);
      expect(field(tester, 'mc-power'), '22');
      // Meshtastic-only parts are gone, without empty boxes; backups stay
      // (MeshCore radios are backed up too).
      expect(find.text('Backups…'), findsOneWidget);
      expect(find.textContaining('Region'), findsNothing);
      expect(
          find.textContaining('On your community mesh (USA)'), findsOneWidget);
    });

    testWidgets('the ladder lists every modulation once with its users',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('Fast · SF7 / 62.5 kHz / 4/5'));
      await tester.pumpAndSettle();
      expect(find.text('Fast · same as your mesh'), findsOneWidget);
      expect(find.text('Longest'), findsOneWidget);
      expect(find.textContaining('USA, Canada'), findsOneWidget);
      expect(find.text('Medium, most robust'), findsOneWidget);
      // Countries are not choices.
      expect(find.text('Switzerland'), findsNothing);
      await tester.tap(find.text('Longest'));
      await tester.pumpAndSettle();
      expect(find.text('Longest · SF11 / 125 kHz / 4/5'), findsOneWidget);
      // Still on the band's relay frequency.
      expect(frequencyLine(tester), startsWith('918.000 MHz'));
    });

    for (final (mhz, preset, expected) in [
      (869.618, MeshCorePresets.euUkNarrow, '869.495 MHz'),
      (433.650, MeshCorePresets.eu433Narrow, '433.000 MHz'),
      (918.000, null, '918.000 MHz'),
    ]) {
      testWidgets('a radio on $mhz MHz gets $expected', (tester) async {
        await pump(tester, frequencyMHz: mhz, preset: preset);
        expect(frequencyLine(tester), startsWith(expected));
      });
    }

    testWidgets('beacon summary is the link check from the mobile',
        (tester) async {
      await pump(tester);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('beacon-summary')))
              .data,
          'Link check from the mobile every 30 s');
      expect(find.byKey(const ValueKey('trace-beacon-note')), findsOneWidget);
    });

    testWidgets('a frequency the base can\'t relay on is flagged',
        (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('mc-frequency-other')));
      await tester.pumpAndSettle();
      expect(field(tester, 'mc-frequency'), '918.000');
      expect(find.textContaining('433.000, 869.495 or 918.000 MHz'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('mc-freq-warning')), findsNothing);
      await tester.enterText(
          find.byKey(const ValueKey('mc-frequency')), '915.000');
      await tester.pump();
      expect(find.byKey(const ValueKey('mc-freq-warning')), findsOneWidget);
    });

    testWidgets('power steps with the buttons and clamps at 22',
        (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('mc-power-up')));
      await tester.pump();
      expect(field(tester, 'mc-power'), '22');
      await tester.tap(find.byKey(const ValueKey('mc-power-down')));
      await tester.pump();
      expect(field(tester, 'mc-power'), '21');
    });

    testWidgets('power out of range blocks applying', (tester) async {
      await pump(tester);
      await tester.enterText(find.byKey(const ValueKey('mc-power')), '30');
      await tester.pump();
      expect(find.text('0 to 22 dBm'), findsOneWidget);
      final apply = tester.widget<ButtonStyleButton>(find.ancestor(
          of: find.text('Apply to this node'),
          matching: find.bySubtype<ButtonStyleButton>()));
      expect(apply.onPressed, isNull);
    });

    testWidgets('a base speaking the other protocol is listed disabled',
        (tester) async {
      await pump(tester, found: const [
        _meshtasticRadio,
        RadioDescriptor(
            id: 'MC-2', name: 'Base-ef56', protocol: RadioProtocol.meshcore),
      ]);
      await tester.tap(find.text('Find base node'));
      await tester.pumpAndSettle();
      final other = tester
          .widget<ListTile>(find.byKey(const ValueKey('setup-result-MT-1')));
      expect(other.enabled, isFalse);
      expect(find.text('Speaks Meshtastic: the base and mobile must match'),
          findsOneWidget);
      final same = tester
          .widget<ListTile>(find.byKey(const ValueKey('setup-result-MC-2')));
      expect(same.enabled, isTrue);
    });

    testWidgets('scans for both protocols', (tester) async {
      final prefsRadio = await pump(tester);
      expect(prefsRadio.protocol, RadioProtocol.meshcore);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(RadioSetupScreen)));
      final scanner = container.read(radioScannerProvider) as FakeRadioScanner;
      await tester.tap(find.text('Find base node'));
      await tester.pumpAndSettle();
      expect(scanner.scans.single, RadioServices.all);
    });
  });

  group('wording', () {
    test('trace beacon stats read as link checks', () {
      const stats = BeaconStats(41, 3);
      expect(beaconStatsText(stats), 'Beacons 41 of ~44 (93 %)');
      expect(beaconStatsText(stats, kind: BeaconKind.trace),
          'Link checks 41 of 44 answered (93 %)');
    });

    test('bands and relay frequencies', () {
      expect(MeshCoreBand.of(910.525).clientRepeatMHz, 918.000);
      expect(MeshCoreBand.of(869.618).clientRepeatMHz, 869.495);
      expect(MeshCoreBand.of(433.650).clientRepeatMHz, 433.000);
      expect(isClientRepeatFrequency(918.0), isTrue);
      expect(isClientRepeatFrequency(910.525), isFalse);
      expect(meshCorePresetLabel(MeshCorePresets.euUkDeprecated),
          'SF11 / 250 kHz / 4/5 · EU/UK (deprecated)');
      expect(anyPresetDisplayName('MC_USA'), 'USA');
      expect(anyPresetDisplayName('MC_SF7_BW62.5_CR5'),
          'Fast (SF7 / 62.5 kHz / 4/5)');
      expect(presetForId('MC_SF11_BW125.0_CR5'),
          MeshCoreModulations.longest.radioPreset);
      expect(meshCoreCommunitiesLabel(MeshCoreModulations.fast),
          'Canada, Czech Republic (Narrow), Hungary +5');
      expect(meshCoreCommunitiesLabel(MeshCoreModulations.fast, first: 'USA'),
          'USA, Canada, Czech Republic (Narrow) +5');
      expect(
          meshCoreCommunitiesLabel(MeshCoreModulations.longest), 'Costa Rica');
      expect(anyPresetDisplayName('LONG_FAST'), 'Long Fast');
    });

    testWidgets('About names MeshCore factually beside the trademark notice',
        (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: AboutScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.text(trademarkNotice), findsOneWidget);
      expect(find.text(meshCoreCompatibilityNotice), findsOneWidget);
      expect(meshCoreCompatibilityNotice, contains('not affiliated'));
    });
  });
}
