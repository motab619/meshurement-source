// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/ui/widgets/connect_failure.dart';
import 'package:mesh_analyzer/utils/platform_text.dart';

void main() {
  const far = RadioDescriptor(
      id: 'a',
      name: 'MeshCore-MeshTest Base',
      protocol: RadioProtocol.meshcore,
      scanRssi: -106);
  const near = RadioDescriptor(
      id: 'b',
      name: 'Heltec',
      protocol: RadioProtocol.meshtastic,
      scanRssi: -60);

  test('a dropped link on a weak scan blames distance, keeps the raw text', () {
    final f = connectFailure(
        StateError('Finding the MeshCore service: FlutterBluePlusException | '
            'discoverServices | fbp-code: 6 | Device is disconnected.'),
        far);
    expect(f.headline, 'Couldn\'t connect to MeshCore-MeshTest Base');
    expect(f.cause, contains('dropped the connection'));
    expect(f.cause, contains('-106 dBm'));
    expect(f.tips, isNot(contains(startsWith('Move the node closer'))));
    expect(f.tips.first, startsWith('Close the MeshCore app'));
    expect(f.detail, startsWith('Finding the MeshCore service'));
    expect(f.detail, isNot(startsWith('Bad state')));
  });

  test('a dropped link on a good scan suggests moving closer first', () {
    final f = connectFailure(StateError('Device is disconnected'), near);
    expect(f.cause, 'It dropped the connection before answering.');
    expect(f.tips.first, 'Move the node closer to the phone.');
    expect(f.tips[1], startsWith('Close the Meshtastic app'));
  });

  test('timeout, pairing and lost bond get their own cause', () {
    expect(connectFailure(TimeoutException('x'), near).cause,
        startsWith('It didn\'t answer in time'));
    expect(
        connectFailure(StateError('Pairing (subscribe): failed'), near).cause,
        'Pairing didn\'t complete.');
    final bond =
        connectFailure(StateError('Peer removed pairing information'), near);
    expect(bond.cause,
        contains(PlatformText.isAndroid ? 'Unpair' : 'Forget This Device'));
    expect(bond.tips, isEmpty);
  });

  testWidgets('the view: headline, numbered tips, details behind a toggle',
      (tester) async {
    final f = connectFailure(StateError('Device is disconnected'), near);
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: ConnectFailureView(f))));
    expect(find.text('Couldn\'t connect to Heltec'), findsOneWidget);
    expect(find.text('Things to try'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('3.'), findsOneWidget);
    expect(find.text('Device is disconnected'), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pump();
    expect(find.text('Device is disconnected'), findsOneWidget);
    expect(find.text('Hide details'), findsOneWidget);
  });
}
