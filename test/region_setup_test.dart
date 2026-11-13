// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_regions.dart';
import 'package:mesh_analyzer/proto/meshtastic/admin.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/channel.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/ui/widgets/region_dialog.dart';

_AdminCapture _newRadio({
  pb.Config_LoRaConfig_RegionCode region =
      pb.Config_LoRaConfig_RegionCode.UNSET,
}) =>
    _AdminCapture()
      ..enterDemo(
        name: 'T1000-E_1a2b',
        myNodeNum: 7,
        nodeInfos: [pb.NodeInfo(num: 7)],
        lora: pb.Config_LoRaConfig(
          usePreset: true,
          modemPreset: pb.Config_LoRaConfig_ModemPreset.LONG_FAST,
          region: region,
          txPower: 22,
          hopLimit: 3,
        ),
        channelTable: [pb.Channel(index: 0, role: pb.Channel_Role.PRIMARY)],
      );

void main() {
  group('MeshtasticRegions', () {
    test('every choice is a real firmware region', () {
      final codes = MeshtasticRegions.all.map((r) => r.code).toSet();
      expect(codes, hasLength(MeshtasticRegions.all.length));
      for (final r in MeshtasticRegions.all) {
        expect(r.pbCode.name, r.code);
      }
      final firmware = pb.Config_LoRaConfig_RegionCode.values
          .where((r) => r != pb.Config_LoRaConfig_RegionCode.UNSET)
          .map((r) => r.name)
          .toSet();
      expect(codes, firmware, reason: 'offer every region the firmware has');
    });

    test('guesses from the phone\'s country', () {
      expect(MeshtasticRegions.guessFor('US').code, 'US');
      expect(MeshtasticRegions.guessFor('ca').code, 'US');
      expect(MeshtasticRegions.guessFor('GB').code, 'EU_868');
      expect(MeshtasticRegions.guessFor('DE').code, 'EU_868');
      expect(MeshtasticRegions.guessFor('AU').code, 'ANZ');
      expect(MeshtasticRegions.guessFor('JP').code, 'JP');
      expect(MeshtasticRegions.guessFor(null).code, 'US');
    });
  });

  group('setRegion', () {
    test('an out-of-the-box radio reports no region', () {
      expect(_newRadio().regionUnset, isTrue);
      expect(_newRadio(region: pb.Config_LoRaConfig_RegionCode.US).regionUnset,
          isFalse);
    });

    test('writes only the region (and transmit on) in one edit', () async {
      final radio = _newRadio();
      await radio.setRegion('EU_868');

      final sent = radio.sent;
      expect(sent.first.beginEditSettings, isTrue);
      expect(sent.last.commitEditSettings, isTrue);
      final lora = sent.singleWhere((m) => m.hasSetConfig()).setConfig.lora;
      expect(lora.region, pb.Config_LoRaConfig_RegionCode.EU_868);
      expect(lora.txEnabled, isTrue);
      expect(lora.modemPreset, pb.Config_LoRaConfig_ModemPreset.LONG_FAST);
      expect(lora.txPower, 22, reason: 'other LoRa settings are kept');
      expect(sent.where((m) => m.hasSetChannel()), isEmpty);
      expect(radio.regionUnset, isFalse);
    });

    test('refuses UNSET or unknown codes', () {
      expect(() => _newRadio().setRegion('UNSET'), throwsArgumentError);
      expect(() => _newRadio().setRegion('MARS'), throwsArgumentError);
    });
  });

  testWidgets('region dialog writes the chosen region', (tester) async {
    final radio = _newRadio();
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              result = await showRegionDialog(context, radio, newRadio: true),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no LoRa region yet'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<MeshtasticRegion>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe, UK (868 MHz)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set region'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    final lora = radio.sent.singleWhere((m) => m.hasSetConfig()).setConfig.lora;
    expect(lora.region, pb.Config_LoRaConfig_RegionCode.EU_868);
  });

  testWidgets('Later leaves the radio alone', (tester) async {
    final radio = _newRadio();
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              result = await showRegionDialog(context, radio, newRadio: true),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(radio.sent, isEmpty);
  });
}

/// Records admin messages instead of sending them over Bluetooth.
class _AdminCapture extends MeshtasticRadio {
  final sent = <pb.AdminMessage>[];

  @override
  Future<void> sendAdmin(
    pb.AdminMessage msg, {
    Duration timeout = const Duration(seconds: 10),
    int retries = 1,
  }) async =>
      sent.add(msg);
}
