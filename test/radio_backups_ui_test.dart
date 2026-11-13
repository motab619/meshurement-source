// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/database/app_database.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_frames.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_settings.dart';
import 'package:mesh_analyzer/data/radio/radio_types.dart';
import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/proto/meshtastic/channel.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/services/radio_backup_service.dart';
import 'package:mesh_analyzer/services/radio_roles.dart';
import 'package:mesh_analyzer/ui/widgets/radio_backups_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_mesh_radio.dart';

MeshtasticBackup backup(int node, String owner, DateTime at,
        {int hop = 3, String reason = 'Before Node Setup'}) =>
    MeshtasticBackup(
      path: '',
      nodeNum: node,
      radioName: 'Radio$node',
      savedAt: at,
      reason: reason,
      channels: [
        pb.Channel(
          index: 0,
          role: pb.Channel_Role.PRIMARY,
          settings: pb.ChannelSettings(psk: [1]),
        ),
        pb.Channel(
          index: 1,
          role: pb.Channel_Role.SECONDARY,
          settings:
              pb.ChannelSettings(name: 'Friends', psk: List.filled(32, 7)),
        ),
        for (var i = 2; i < 8; i++)
          pb.Channel(index: i, role: pb.Channel_Role.DISABLED),
      ],
      lora: pb.Config_LoRaConfig(
        usePreset: true,
        modemPreset: pb.Config_LoRaConfig_ModemPreset.LONG_FAST,
        region: pb.Config_LoRaConfig_RegionCode.US,
        hopLimit: hop,
      ),
      rangeTest: null,
      owner: pb.User(longName: owner, shortName: 'X'),
    );

/// A MeshCore radio's original settings (node 0x30, never connected here).
MeshCoreBackup meshCoreBackup(DateTime at) => MeshCoreBackup(
      path: '',
      nodeNum: 0x30,
      radioName: 'MeshCore-abcd',
      savedAt: at,
      reason: 'Before Node Setup',
      settings: MeshCoreSettings(
        name: 'Mobile',
        txPowerDbm: 22,
        frequencyKHz: 910525,
        bandwidthHz: 62500,
        spreadingFactor: 7,
        codingRate: 5,
        clientRepeat: false,
        manufacturer: 'Seeed Wio Tracker L1',
        channels: [
          MeshCoreChannelInfo(Uint8List(0), 0, 'Public',
              Uint8List.fromList(List.filled(16, 0x8b))),
          MeshCoreChannelInfo(Uint8List(0), 1, '', Uint8List(16)),
        ],
      ),
    );

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('backups_ui'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester, {bool recording = false}) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({RadioRoles.mobileNodeKey: 10});
    final prefs = await SharedPreferences.getInstance();
    final svc = RadioBackupService(directory: dir);
    await tester.runAsync(() async {
      // Node 0x20 (other radio) is newer, but the connected node 10 is first.
      await svc.store(backup(10, 'Andy T1000', DateTime.utc(2026, 10, 12, 15)));
      for (var i = 0; i < 4; i++) {
        await svc.store(backup(
            10, 'MeshTest Mobile', DateTime.utc(2026, 10, 13 + i),
            hop: 4 + i, reason: 'Saved by hand'));
      }
      await svc
          .store(backup(0x20, 'Base Orig', DateTime.utc(2026, 10, 14, 15)));
      await svc.store(meshCoreBackup(DateTime.utc(2026, 10, 11, 15)));
    });
    final radio = FakeMeshRadio(myNodeId: 10);
    await radio.connect(const RadioDescriptor(id: 'A', name: 'a'));
    final session = Session(
      id: 1,
      coverageMapId: 1,
      name: '',
      startedAt: DateTime(2026, 10, 1),
      isActive: true,
      hwAntenna: '',
      hwNodeModel: '',
      hwNotes: '',
      loraPreset: 'LONG_FAST',
      protocol: 'meshtastic',
      pingIntervalSec: 30,
      packetAirtimeMs: 0,
      rangeTestActive: false,
      packetCount: 0,
      beaconKind: '',
      beaconIntervalSec: 0,
    );
    await tester.runAsync(() => tester.pumpWidget(ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            meshRadioProvider.overrideWithValue(radio),
            activeSessionProvider.overrideWith(
                (ref) => Stream.value(recording ? session : null)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RadioBackupsSection(service: svc),
              ),
            ),
          ),
        )));
    for (var i = 0; i < 5; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('connected radio first with pinned original and 3 newest',
      (tester) async {
    await pump(tester);
    // Group title: owner of the OLDEST backup, node id.
    expect(find.text('Andy T1000  !0000000a'), findsOneWidget);
    expect(find.text('Mobile'), findsOneWidget); // role badge
    expect(find.text('Original settings'), findsOneWidget);
    expect(find.text('LongFast · 2 channels (LongFast, Friends)'),
        findsNWidgets(4)); // original + 3 shown
    expect(find.text('Show all (4)'), findsOneWidget);
    // Connected group is above the other radio's one-liner.
    expect(
        tester.getTopLeft(find.text('Andy T1000  !0000000a')).dy <
            tester.getTopLeft(find.textContaining('Base Orig · original')).dy,
        isTrue);
    await tester.tap(find.text('Show all (4)'));
    await tester.pumpAndSettle();
    expect(find.text('LongFast · 2 channels (LongFast, Friends)'),
        findsNWidgets(5));
    // Connected radio: Restore is enabled.
    final btns = tester
        .widgetList<TextButton>(find.widgetWithText(TextButton, 'Restore'));
    expect(btns.length, 5);
    expect(btns.every((b) => b.onPressed != null), isTrue);
  });

  testWidgets('other radios are one line and say why Restore is off',
      (tester) async {
    await pump(tester);
    final line = find.text(
        'Base Orig · original settings saved Oct 14 · Connect to restore');
    expect(line, findsOneWidget);
    await tester.tap(line);
    await tester.pumpAndSettle();
    expect(find.text('Connect to Base Orig to restore'), findsOneWidget);
    // ...and a way to do that right here.
    expect(find.byKey(const ValueKey('connect-Base Orig')), findsOneWidget);
    expect(find.text('Connect…'), findsWidgets);
  });

  testWidgets('recording disables Restore with a reason', (tester) async {
    await pump(tester, recording: true);
    expect(find.text('End the recording session first'), findsWidgets);
    final btns = tester
        .widgetList<TextButton>(find.widgetWithText(TextButton, 'Restore'));
    expect(btns, isNotEmpty);
    expect(btns.every((b) => b.onPressed == null), isTrue);
  });

  testWidgets('overflow menu holds Share file, Copy channel link, Delete',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
    expect(find.text('Share file'), findsOneWidget);
    expect(find.text('Copy channel link'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Share file'));
    await tester.pumpAndSettle();
    expect(find.textContaining('channel keys'), findsOneWidget);
  });

  testWidgets('Copy channel link warns before anything is copied',
      (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pump(tester);
    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy channel link'));
    await tester.pumpAndSettle();
    expect(find.text('Copy channel link?'), findsOneWidget);
    expect(find.textContaining('channel keys'), findsOneWidget);
    expect(clipboard, isNull, reason: 'nothing copied before the yes');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(clipboard, isNull);

    await tester.tap(find.byIcon(Icons.more_horiz).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy channel link'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Copy'));
    await tester.pumpAndSettle();
    expect(clipboard, startsWith('https://meshtastic.org/e/#'));
  });

  testWidgets('a MeshCore backup lists like the others, without a channel link',
      (tester) async {
    await pump(tester);
    final line = find.textContaining('Mobile · original settings saved Oct 11');
    expect(line, findsOneWidget);
    await tester.tap(line);
    await tester.pumpAndSettle();
    expect(find.text('!00000030 · Seeed Wio Tracker L1'), findsOneWidget);
    expect(find.text('Fast · 910.525 MHz, USA · 22 dBm · 1 channel (Public)'),
        findsOneWidget);
    expect(find.text('Connect to Mobile to restore'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_horiz).last);
    await tester.pumpAndSettle();
    expect(find.text('Share file'), findsOneWidget);
    expect(find.text('Copy channel link'), findsNothing);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('Put this radio back is offered for the connected radio',
      (tester) async {
    await pump(tester);
    expect(find.text('Put this node back the way it was'), findsOneWidget);
    // The fake is neither radio class: the flow reports that.
    await tester.tap(find.text('Put this node back the way it was'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Meshtastic or MeshCore node'), findsOneWidget);
  });

  test('restoreDiff calls out a public primary', () {
    final orig = backup(10, 'Andy T1000', DateTime.utc(2026, 10, 12));
    final now = backup(10, 'MeshTest Mobile', DateTime.utc(2026, 10, 13));
    final d = restoreDiff(now, orig);
    expect(d.first.label, 'Name');
    expect(d.first.from, 'MeshTest Mobile');
    expect(d.first.to, 'Andy T1000');
    final ch = d.firstWhere((l) => l.label == 'Channels');
    expect(ch.to, 'public LongFast, Friends');
  });
}
