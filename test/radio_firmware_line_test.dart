// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/ui/widgets/radio_firmware_line.dart';

import 'fakes/fake_mesh_radio.dart';

class _FwRadio extends FakeMeshRadio {
  final String fw;
  _FwRadio(this.fw);

  @override
  Future<RadioInfo> queryDevice() async => RadioInfo(
      protocol: RadioProtocol.meshtastic, model: 'X', firmwareVersion: fw);
}

void main() {
  test('version parsing and the 2.5.0 threshold', () {
    expect(parseFirmwareVersion('2.5.11.abc123'), [2, 5, 11]);
    expect(parseFirmwareVersion('garbage'), isNull);
    expect(firmwareTooOld('2.4.9'), isTrue);
    expect(firmwareTooOld('1.9.0'), isTrue);
    expect(firmwareTooOld('2.5.0'), isFalse);
    expect(firmwareTooOld('2.7.1.x'), isFalse);
    expect(firmwareTooOld(''), isFalse);
  });

  Future<void> show(WidgetTester t, String fw) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(body: RadioFirmwareLine(radio: _FwRadio(fw)))));
    await t.pump();
  }

  testWidgets('old firmware shows the version and the warning', (t) async {
    await show(t, '2.4.2.abc');
    expect(find.text('Firmware 2.4.2.abc'), findsOneWidget);
    expect(find.text(firmwareWarning), findsOneWidget);
  });

  testWidgets('current firmware shows no warning', (t) async {
    await show(t, '2.7.4.def');
    expect(find.text('Firmware 2.7.4.def'), findsOneWidget);
    expect(find.text(firmwareWarning), findsNothing);
  });

  testWidgets('unknown firmware shows nothing', (t) async {
    await show(t, '');
    expect(find.textContaining('Firmware'), findsNothing);
  });
}
