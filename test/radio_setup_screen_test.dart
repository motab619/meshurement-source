// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/services/base_node.dart';
import 'package:mesh_analyzer/services/gps_service.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:mesh_analyzer/ui/screens/radio_backups_screen.dart';
import 'package:mesh_analyzer/ui/screens/radio_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_location_backend.dart';
import 'fakes/fake_mesh_radio.dart';

void main() {
  // Location never asked for; granted when asked.
  late FakeLocationBackend location;
  setUp(() => location = FakeLocationBackend(
      permission: LocationPermission.denied,
      afterRequest: LocationPermission.whileInUse));

  Future<FakeMeshRadio> pump(WidgetTester tester,
      {RadioRole? initialRole,
      Map<String, Object> prefsValues = const {}}) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(prefsValues);
    final prefs = await SharedPreferences.getInstance();
    final radio = FakeMeshRadio(myNodeId: 10);
    await radio.connect(const RadioDescriptor(id: 'A', name: 'a'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        meshRadioProvider.overrideWithValue(radio),
        gpsServiceProvider.overrideWithValue(GpsService(backend: location)),
      ],
      child: MaterialApp(home: RadioSetupScreen(initialRole: initialRole)),
    ));
    await tester.pumpAndSettle();
    return radio;
  }

  // A link state change reaches the page a frame after the stream event.
  Future<void> setLink(
      WidgetTester tester, FakeMeshRadio radio, RadioConnectionState s) async {
    radio.setState(s);
    await tester.pump();
    await tester.pump();
  }

  // Apply to the connected radio through the confirm dialog.
  Future<void> applyToThisRadio(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Apply to this node'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply to this node'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
  }

  testWidgets('mobile by default: find base, then apply to this radio',
      (tester) async {
    await pump(tester);
    expect(find.text('Find base node'), findsOneWidget);
    expect(find.text('Apply to this node'), findsOneWidget);
    expect(find.text('Set up this node as base'), findsNothing);
  });

  testWidgets('choosing Base flips the steps', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Base (stays put)'));
    await tester.pumpAndSettle();
    expect(find.text('Set up this node as base'), findsOneWidget);
    expect(find.text('Find mobile node'), findsOneWidget);
    expect(find.text('Find base node'), findsNothing);
  });

  testWidgets('both flows show the same remote-changes switch, on',
      (tester) async {
    await pump(tester);
    expect(find.text(remoteAdminSwitchTitle), findsOneWidget,
        reason: 'mobile flow');
    // One line; what it gives away is behind its ⓘ.
    expect(find.textContaining('admin access to the base'), findsNothing);
    final box = tester
        .widget<SwitchListTile>(find.byKey(const ValueKey('allow-remote')));
    expect(box.value, isTrue);
    await tester.tap(find.byKey(const ValueKey('allow-remote-info')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('admin access to the base (settings and '
            'channel keys) until you restore the base'),
        findsOneWidget);
    expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('allow-remote')))
            .value,
        isTrue,
        reason: 'the ⓘ does not flip the switch');
    await tester.tapAt(const Offset(10, 10)); // close the sheet
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('revoke-remote')), findsNothing,
        reason: 'nothing granted yet');
    await tester.tap(find.text('Base (stays put)'));
    await tester.pumpAndSettle();
    expect(find.text(remoteAdminSwitchTitle), findsOneWidget,
        reason: 'base flow');
  });

  testWidgets('a recorded grant offers Stop allowing', (tester) async {
    await pump(tester, prefsValues: {RadioRoles.remoteAdminNodeKey: 20});
    expect(find.byKey(const ValueKey('revoke-remote')), findsOneWidget);
    await tester.tap(find.text('Stop allowing'));
    await tester.pumpAndSettle();
    expect(find.text('Stop remote changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('no base yet: no remote-change row at all', (tester) async {
    await pump(tester);
    expect(
        find.byKey(const ValueKey('remote-change-unavailable')), findsNothing);
    expect(find.byKey(const ValueKey('open-remote-change')), findsNothing);
  });

  testWidgets('a base without the grant shows the row greyed out with why',
      (tester) async {
    await pump(tester, prefsValues: {baseNodePrefKey: 20});
    final row = find.byKey(const ValueKey('remote-change-unavailable'));
    expect(row, findsOneWidget);
    expect(tester.widget<ListTile>(row).enabled, isFalse);
    expect(find.textContaining('doesn\'t hold the mobile node\'s key yet'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('open-remote-change')), findsNothing);
  });

  testWidgets('a granted base opens the remote change, no greyed row',
      (tester) async {
    await pump(tester, prefsValues: {
      baseNodePrefKey: 20,
      RadioRoles.remoteAdminNodeKey: 10,
    });
    expect(find.byKey(const ValueKey('open-remote-change')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('remote-change-unavailable')), findsNothing);
  });

  testWidgets('"Make this the base" opens with Base selected', (tester) async {
    await pump(tester, initialRole: RadioRole.base);
    expect(find.text('Set up this node as base'), findsOneWidget);
  });

  testWidgets('applying to the recorded mobile as base names the swap',
      (tester) async {
    // Node 10 (the connected radio) is the mobile; node 20 is the base.
    await pump(tester, initialRole: RadioRole.base, prefsValues: {
      RadioRoles.mobileNodeKey: 10,
      baseNodePrefKey: 20,
    });
    await tester.tap(find.text('Set up this node as base'));
    await tester.pumpAndSettle();
    final warning = find.byKey(const ValueKey('setup-swap-warning'));
    expect(warning, findsOneWidget);
    final text = tester.widget<Text>(warning).data!;
    expect(text, contains('This node is your mobile'));
    expect(text, contains('no mobile'));
    expect(text, contains('stops being the base'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('no swap line when the radio holds no role; base asks Location',
      (tester) async {
    await pump(tester, initialRole: RadioRole.base);
    await tester.tap(find.text('Set up this node as base'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('setup-swap-warning')), findsNothing);
    // A base apply asks for Location first (its position is saved).
    expect(location.requests, 1);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('three cards in order: who, settings, apply', (tester) async {
    await pump(tester);
    double y(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;
    expect(y('setup-card-who'), lessThan(y('setup-card-settings')));
    expect(y('setup-card-settings'), lessThan(y('setup-card-apply')));
    expect(find.text('Range setting (modem preset)'), findsOneWidget);
    // The airtime line is the beacon's helper text.
    expect(find.textContaining('of air per beacon · shortest interval'),
        findsOneWidget);
    // Backups live on their own screen now.
    expect(find.text('Backups'), findsNothing);
    expect(find.byKey(const ValueKey('setup-backups')), findsOneWidget);
  });

  testWidgets('only the next step is filled', (tester) async {
    await pump(tester);
    // Mobile flow, no base yet: finding the base is next.
    expect(find.widgetWithText(FilledButton, 'Find base node'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Apply to this node'),
        findsOneWidget);
    // Base flow: this radio first.
    await tester.tap(find.text('Base (stays put)'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Set up this node as base'),
        findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Find mobile node'),
        findsOneWidget);
  });

  testWidgets('with a base recorded, applying to this radio is next',
      (tester) async {
    await pump(tester, prefsValues: {baseNodePrefKey: 20});
    expect(
        find.widgetWithText(OutlinedButton, 'Find base node'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Apply to this node'),
        findsOneWidget);
  });

  testWidgets('the beacon ⓘ explains airtime', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('beacon-info')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Airtime is how long'), findsOneWidget);
  });

  testWidgets('the apply dialog and the Backups link open the backups screen',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Apply to this node'));
    await tester.pumpAndSettle();
    expect(find.textContaining('including its name'), findsOneWidget);
    await tester.tap(find.text('View backups'));
    await tester.pumpAndSettle();
    expect(find.text('Apply'), findsNothing); // dialog closed
    expect(find.byType(RadioBackupsScreen), findsOneWidget);
    expect(find.text('Node backups'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('setup-backups')));
    await tester.pumpAndSettle();
    expect(find.byType(RadioBackupsScreen), findsOneWidget);
  });

  testWidgets('a failed apply shows the raw error and step behind Details',
      (tester) async {
    final radio = await pump(tester);
    radio.applyError = RangeError('Value not in range: 9');
    await applyToThisRadio(tester);
    expect(find.textContaining('Something went wrong while setting up'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('setup-error-detail-text')), findsNothing);
    await tester
        .ensureVisible(find.byKey(const ValueKey('setup-error-details')));
    await tester.tap(find.byKey(const ValueKey('setup-error-details')));
    await tester.pump();
    final detail = tester
        .widget<SelectableText>(
            find.byKey(const ValueKey('setup-error-detail-text')))
        .data!;
    expect(detail, startsWith('RangeError: '));
    expect(detail, contains('Value not in range: 9'));
    expect(detail, contains('Last step: '));
  });

  testWidgets(
      'after Apply the page holds a restarting line while the node '
      'reboots, no Connect button', (tester) async {
    final radio = await pump(tester);
    await applyToThisRadio(tester);
    expect(find.textContaining('Your node is restarting'), findsOneWidget);
    // The radio reboots: the link drops. The page stays calm.
    await setLink(tester, radio, RadioConnectionState.disconnected);
    expect(find.byKey(const ValueKey('setup-settling')), findsOneWidget);
    expect(find.byKey(const ValueKey('setup-connect')), findsNothing);
    await setLink(tester, radio, RadioConnectionState.reconnecting);
    expect(find.byKey(const ValueKey('setup-settling')), findsOneWidget);
    expect(find.text('Waiting for your node to reconnect…'), findsNothing);
    // Back: the form again, and the hold is over.
    await setLink(tester, radio, RadioConnectionState.ready);
    expect(find.byKey(const ValueKey('setup-settling')), findsNothing);
    expect(find.text('Apply to this node'), findsOneWidget);
    // A later drop is not an apply any more.
    await setLink(tester, radio, RadioConnectionState.disconnected);
    expect(find.byKey(const ValueKey('setup-connect')), findsOneWidget);
  });

  testWidgets('the hold ends after a minute without the radio', (tester) async {
    final radio = await pump(tester);
    await applyToThisRadio(tester);
    await setLink(tester, radio, RadioConnectionState.disconnected);
    expect(find.byKey(const ValueKey('setup-settling')), findsOneWidget);
    await tester.pump(RadioSetupScreen.settleFor + const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('setup-settling')), findsNothing);
    expect(find.byKey(const ValueKey('setup-connect')), findsOneWidget);
  });
}
