// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_frames.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_settings.dart';
import 'package:mesh_analyzer/proto/meshtastic/apponly.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/channel.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/module_config.pb.dart' as pb;
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/proto/meshtastic/admin.pb.dart' as pb;
import 'package:mesh_analyzer/services/radio_backup_service.dart';

import 'meshtastic/fake_meshtastic_transport.dart';

MeshtasticBackup sampleMeshtastic({
  DateTime? at,
  String reason = 'Before Radio Setup',
  int node = 0x8a2fe4ea,
  int hop = 3,
}) =>
    MeshtasticBackup(
      path: '/tmp/x.json',
      nodeNum: node,
      radioName: 'Pr8A_e4ea',
      savedAt: at ?? DateTime.utc(2026, 10, 12, 15),
      reason: reason,
      channels: [
        pb.Channel(
          index: 0,
          role: pb.Channel_Role.PRIMARY,
          settings: pb.ChannelSettings(
            name: 'Friends',
            psk: List.generate(32, (i) => i),
            moduleSettings: pb.ModuleSettings(positionPrecision: 32),
          ),
        ),
        pb.Channel(
          index: 1,
          role: pb.Channel_Role.SECONDARY,
          settings: pb.ChannelSettings(name: 'Public', psk: [1]),
        ),
        for (var i = 2; i < 8; i++)
          pb.Channel(index: i, role: pb.Channel_Role.DISABLED),
      ],
      lora: pb.Config_LoRaConfig(
        usePreset: true,
        modemPreset: pb.Config_LoRaConfig_ModemPreset.MEDIUM_FAST,
        region: pb.Config_LoRaConfig_RegionCode.US,
        channelNum: 20,
        hopLimit: hop,
      ),
      rangeTest: pb.ModuleConfig_RangeTestConfig(enabled: true, sender: 15),
      owner: pb.User(longName: 'Andy T1000', shortName: 'AT1'),
    );

void main() {
  // DiagLog wants the services binding for its log file.
  TestWidgetsFlutterBinding.ensureInitialized();
  meshCoreMain();
  adminKeyTests();
  const sample = sampleMeshtastic;

  test('backup survives JSON round trip exactly', () {
    final b = sample();
    final json = jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>;
    final back = RadioBackup.fromJson('/tmp/x.json', json) as MeshtasticBackup;
    expect(back.nodeNum, b.nodeNum);
    expect(back.savedAt, b.savedAt);
    expect(back.channels.length, 8);
    for (var i = 0; i < 8; i++) {
      expect(back.channels[i], b.channels[i]);
    }
    expect(back.lora, b.lora);
    expect(back.owner, b.owner);
    expect(back.rangeTest, b.rangeTest);
    expect(back.channelSummary, 'Friends, Public');
    expect(json['summary']['preset'], 'MEDIUM_FAST');
  });

  test('the GPS settings (step 5) survive the round trip and show in Restore',
      () {
    final gpsOff = pb.Config_PositionConfig(
        gpsMode: pb.Config_PositionConfig_GpsMode.DISABLED,
        positionBroadcastSecs: 900);
    final b = MeshtasticBackup(
      path: '/x',
      nodeNum: 1,
      radioName: 'T1000',
      savedAt: DateTime.utc(2026, 11, 10),
      reason: 'Before Node Setup',
      channels: sample().channels,
      lora: sample().lora,
      rangeTest: null,
      position: gpsOff,
    );
    final back = RadioBackup.fromJson(
            '/x', jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>)
        as MeshtasticBackup;
    expect(back.position, gpsOff);
    expect(back.sameSettingsAs(b), isTrue);
    final now = b.copyWith();
    final changed = MeshtasticBackup(
      path: '/y',
      nodeNum: 1,
      radioName: 'T1000',
      savedAt: DateTime.utc(2026, 11, 11),
      reason: 'manual',
      channels: sample().channels,
      lora: sample().lora,
      rangeTest: null,
      position: gpsOff.deepCopy()
        ..gpsMode = pb.Config_PositionConfig_GpsMode.ENABLED
        ..gpsUpdateInterval = 30,
    );
    expect(changed.sameSettingsAs(now), isFalse);
    final gpsLine =
        restoreDiff(changed, now).firstWhere((l) => l.label == 'GPS');
    expect(gpsLine.from, 'on, every 30 s');
    expect(gpsLine.to, 'off');
  });

  test('channel link decodes to the enabled channels + LoRa settings', () {
    final b = sample();
    final url = b.channelUrl;
    expect(url, startsWith('https://meshtastic.org/e/#'));
    var frag = url.split('#').last;
    frag = frag.padRight((frag.length + 3) ~/ 4 * 4, '=');
    final set = pb.ChannelSet.fromBuffer(base64Url.decode(frag));
    expect(set.settings.map((s) => s.name), ['Friends', 'Public']);
    expect(set.settings.first.psk, List.generate(32, (i) => i));
    expect(set.loraConfig.channelNum, 20);
  });

  group('store', () {
    late Directory dir;
    late RadioBackupService svc;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('backups_test');
      svc = RadioBackupService(directory: dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('first backup of a node is the original; file is UTC .mabackup',
        () async {
      final b = await svc.store(sample());
      expect(b.original, isTrue);
      expect(b.path, endsWith('8a2fe4ea_2026-10-12T15-00-00Z.mabackup'));
      final again = (await svc.list()).single;
      expect(again.original, isTrue);
      expect(again.lastConfirmedAt, again.savedAt);
    });

    test('identical settings update lastConfirmedAt instead of a new file',
        () async {
      await svc.store(sample());
      final r = await svc.store(sample(at: DateTime.utc(2026, 10, 14)));
      expect(r.unchanged, isTrue);
      final all = await svc.list();
      expect(all, hasLength(1));
      expect(all.single.savedAt, DateTime.utc(2026, 10, 12, 15));
      expect(all.single.lastConfirmedAt, DateTime.utc(2026, 10, 14));
      expect(dir.listSync(), hasLength(1));
    });

    test('changed settings write a new, non-original file', () async {
      await svc.store(sample());
      final r = await svc.store(sample(at: DateTime.utc(2026, 10, 14), hop: 5));
      expect(r.unchanged, isFalse);
      expect(r.original, isFalse);
      expect(await svc.list(), hasLength(2));
    });

    test('other nodes are independent', () async {
      await svc.store(sample());
      final r =
          await svc.store(sample(node: 0x1234, at: DateTime.utc(2026, 11)));
      expect(r.original, isTrue);
      expect(await svc.list(), hasLength(2));
    });

    test('reads a v1 file (no original / lastConfirmedAt)', () async {
      final j = sample().toJson()
        ..['version'] = 1
        ..remove('original')
        ..remove('lastConfirmedAt');
      final f = File('${dir.path}/8a2fe4ea_2026-10-12T15-00-00.json')
        ..writeAsStringSync(jsonEncode(j));
      final b = (await svc.list()).single;
      expect(b.path, f.path);
      expect(b.original, isFalse);
      expect(b.lastConfirmedAt, b.savedAt);
      // Legacy: oldest "Before Radio Setup" counts as the original.
      expect(RadioBackup.originalOf([b]), b);
    });

    test('import validates and files the backup under its node', () async {
      final src = File('${dir.path}/in.tmp')
        ..writeAsStringSync(jsonEncode(sample().toJson()));
      final out = Directory('${dir.path}/out')..createSync();
      final b = await RadioBackupService(directory: out).import(src);
      expect(b.nodeNum, 0x8a2fe4ea);
      expect(b.original, isTrue);
      expect(b.path, startsWith(out.path));

      for (final bad in [
        'nope',
        '{}',
        '{"format":"mesh-analyzer-radio-backup","version":9}'
      ]) {
        src.writeAsStringSync(bad);
        await expectLater(RadioBackupService(directory: out).import(src),
            throwsA(isA<FormatException>()));
      }
      final j = sample().toJson();
      (j['protobuf'] as Map)['lora'] = base64Encode([0xff, 0xff, 0xff]);
      src.writeAsStringSync(jsonEncode(j));
      await expectLater(RadioBackupService(directory: out).import(src),
          throwsA(isA<FormatException>()));
    });

    test('prune keeps original, 5 newest manual and newest automatic',
        () async {
      await svc.store(sample(at: DateTime.utc(2026, 10, 1), hop: 1));
      for (var i = 0; i < 8; i++) {
        await svc.store(sample(
            at: DateTime.utc(2026, 10, 2 + i),
            reason: 'Saved by hand',
            hop: 10 + i));
      }
      for (var i = 0; i < 3; i++) {
        await svc.store(sample(
            at: DateTime.utc(2026, 10, 20 + i),
            reason: 'Before Radio Setup',
            hop: 30 + i));
      }
      await svc.store(sample(node: 0x77, at: DateTime.utc(2026, 9)));
      final mine =
          (await svc.list()).where((b) => b.nodeNum == 0x8a2fe4ea).toList();
      expect(mine.where((b) => b.original), hasLength(1));
      expect(mine.where((b) => b.isManual), hasLength(5));
      expect(
          mine
              .where((b) => b.isManual)
              .map((b) => (b as MeshtasticBackup).lora.hopLimit),
          [17, 16, 15, 14, 13]);
      final auto = mine.where((b) => !b.isManual && !b.original).toList();
      expect((auto.single as MeshtasticBackup).lora.hopLimit, 32);
      expect(mine, hasLength(7));
      expect((await svc.list()).where((b) => b.nodeNum == 0x77), hasLength(1));
    });
  });
}

// ─── MeshCore ──────────────────────────────────────────────

MeshCoreChannelInfo _slot(int i, String name, int fill) => MeshCoreChannelInfo(
    Uint8List(0), i, name, Uint8List.fromList(List.filled(16, fill)));

MeshCoreSettings meshCoreSettings({
  String name = 'Mobile',
  int power = 22,
  int freqKHz = 910525,
  int bwHz = 62500,
  int sf = 7,
  int cr = 5,
  bool? repeat = false,
  List<MeshCoreChannelInfo>? channels,
}) =>
    MeshCoreSettings(
      name: name,
      txPowerDbm: power,
      frequencyKHz: freqKHz,
      bandwidthHz: bwHz,
      spreadingFactor: sf,
      codingRate: cr,
      clientRepeat: repeat,
      manufacturer: 'Seeed Wio Tracker L1',
      firmwareVersion: 'v1.18.0',
      channels: channels ??
          [
            _slot(0, 'Public', 0x8b),
            _slot(2, 'Friends', 0x11), // out of order on purpose
            _slot(1, '', 0),
            _slot(3, '', 0),
          ],
    );

MeshCoreBackup meshCoreBackup({
  int node = 0x11223344,
  DateTime? at,
  String reason = 'Before Radio Setup',
  MeshCoreSettings? settings,
}) =>
    MeshCoreBackup(
      path: '',
      nodeNum: node,
      radioName: 'MeshCore-Mobile',
      savedAt: at ?? DateTime.utc(2026, 10, 29, 15),
      reason: reason,
      firmwareVersion: 'v1.18.0',
      settings: settings ?? meshCoreSettings(),
    );

void meshCoreMain() {
  group('MeshCore backups', () {
    test('JSON round trip keeps every setting and the channel secrets', () {
      final b = meshCoreBackup();
      final json = jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>;
      expect(json['version'], 3);
      expect(json['protocol'], 'meshcore');
      expect(json['summary']['frequencyMHz'], 910.525);
      expect(json['summary']['modulation'], 'Fast');
      expect(json['summary']['community'], 'USA');
      final back = RadioBackup.fromJson('/x', json) as MeshCoreBackup;
      expect(back.nodeNum, 0x11223344);
      expect(back.nodeId, '!11223344');
      expect(back.protocol, RadioProtocol.meshcore);
      expect(back.settings.sameAs(b.settings), isTrue);
      expect(back.settings.channels.map((c) => c.index), [0, 1, 2, 3]);
      expect(back.settings.channels[2].secret, List.filled(16, 0x11));
      expect(back.settings.clientRepeat, isFalse);
      expect(back.hardwareLabel, 'Seeed Wio Tracker L1');
      expect(back.channelUrl, isNull);
    });

    test('labels: summary, modulation, frequency with its community', () {
      final b = meshCoreBackup();
      expect(b.summary,
          'Fast · 910.525 MHz, USA · 22 dBm · 2 channels (Public, Friends)');
      expect(b.modulationLabel, 'Fast (SF7 / 62.5 kHz / 4/5)');
      expect(b.ownerName, 'Mobile');
      expect(b.savedName, 'Mobile');
      final custom = meshCoreBackup(
          settings: meshCoreSettings(
              freqKHz: 918000, sf: 12, bwHz: 500000, cr: 8, name: ''));
      expect(custom.frequencyLabel, '918.000 MHz');
      expect(custom.modulationLabel, 'Custom (SF12 / 500 kHz / 4/8)');
      expect(custom.ownerName, 'MeshCore-Mobile');
      expect(custom.savedName, isNull);
    });

    test('same settings compare equal; any change does not', () {
      final a = meshCoreBackup();
      expect(a.sameSettingsAs(meshCoreBackup(at: DateTime.utc(2027))), isTrue);
      expect(
          a.sameSettingsAs(
              meshCoreBackup(settings: meshCoreSettings(power: 20))),
          isFalse);
      expect(
          a.sameSettingsAs(
              meshCoreBackup(settings: meshCoreSettings(repeat: true))),
          isFalse);
      expect(
          a.sameSettingsAs(
              meshCoreBackup(settings: meshCoreSettings(repeat: null))),
          isFalse);
      expect(
          a.sameSettingsAs(meshCoreBackup(
              settings: meshCoreSettings(channels: [
            _slot(0, 'Public', 0x8b),
            _slot(1, 'MeshTest', 0x42),
            _slot(2, 'Friends', 0x11),
            _slot(3, '', 0),
          ]))),
          isFalse);
      // Never equal to a Meshtastic backup, whatever the node.
      expect(a.sameSettingsAs(sampleMeshtastic(node: 0x11223344)), isFalse);
    });

    test('restore diff names what changes, dims the rest', () {
      final after = meshCoreBackup(
          settings: meshCoreSettings(
              name: 'MeshTest Base',
              freqKHz: 918000,
              repeat: true,
              channels: [
            _slot(0, 'Public', 0x8b),
            _slot(1, 'MeshTest', 0x42),
            _slot(2, 'Friends', 0x11),
            _slot(3, '', 0),
          ]));
      final d = restoreDiff(after, meshCoreBackup());
      expect(d.map((l) => l.label), [
        'Name',
        'Frequency',
        'Range setting',
        'Transmit power',
        'Relaying',
        'Channels',
      ]);
      expect(d[0].from, 'MeshTest Base');
      expect(d[0].to, 'Mobile');
      expect(d[1].from, '918.000 MHz');
      expect(d[1].to, '910.525 MHz, USA');
      expect(d[2].changed, isFalse);
      expect(d[3].changed, isFalse);
      expect(d[4].from, 'on');
      expect(d[4].to, 'off');
      expect(d[5].from, 'Public, MeshTest, Friends');
      expect(d[5].to, 'Public, Friends');
      expect(() => restoreDiff(after, sampleMeshtastic()), throwsArgumentError);
    });

    test('a file without a protocol field is a Meshtastic backup', () {
      final json = jsonDecode(jsonEncode(sampleMeshtastic().toJson()))
          as Map<String, dynamic>;
      expect(json['version'], 2); // still readable by older app versions
      json.remove('protocol');
      expect(RadioBackup.fromJson('/x', json), isA<MeshtasticBackup>());
      json['protocol'] = 'lora-thing';
      expect(() => RadioBackup.fromJson('/x', json), throwsFormatException);
    });

    test('store keeps both protocols apart and dedupes MeshCore saves',
        () async {
      final dir = Directory.systemTemp.createTempSync('mc_backups');
      addTearDown(() => dir.deleteSync(recursive: true));
      final svc = RadioBackupService(directory: dir);
      final first = await svc.store(meshCoreBackup());
      expect(first.original, isTrue);
      expect(first.path, endsWith('.mabackup'));
      final again = await svc.store(meshCoreBackup(
          at: DateTime.utc(2026, 10, 30), reason: 'Saved by hand'));
      expect(again.unchanged, isTrue);
      expect(again.lastConfirmedAt, DateTime.utc(2026, 10, 30));
      final changed = await svc.store(meshCoreBackup(
          at: DateTime.utc(2026, 10, 31),
          reason: 'Saved by hand',
          settings: meshCoreSettings(freqKHz: 918000)));
      expect(changed.unchanged, isFalse);
      expect(changed.original, isFalse);
      await svc.store(sampleMeshtastic());
      final all = await svc.list();
      expect(all.whereType<MeshCoreBackup>(), hasLength(2));
      expect(all.whereType<MeshtasticBackup>(), hasLength(1));
      expect(
          RadioBackup.originalOf(all.where((b) => b.nodeNum == 0x11223344))
              ?.path,
          first.path);
      // Re-import of the file lands as the same (deduped) backup.
      final imported = await svc.import(File(first.path));
      expect(imported, isA<MeshCoreBackup>());
    });
  });
}

/// The base's `security.admin_key` in backups (security audit 2026-11-04:
/// Restore and "Put this radio back" must take the mobile's key out).
void adminKeyTests() {
  final mobileKey = keyOf([0xA1]);
  final otherKey = keyOf([0x55]);
  final ownKey = keyOf([0xB1]);
  final ownPrivate = keyOf([0xB2]);
  const node = 0x20;

  MeshtasticBackup withKeys(List<List<int>>? keys) => MeshtasticBackup(
        path: '/tmp/x.mabackup',
        nodeNum: node,
        radioName: 'Base',
        savedAt: DateTime.utc(2026, 11, 4),
        reason: backupReasonBeforeSetup,
        channels: sampleMeshtastic().channels,
        lora: sampleMeshtastic().lora,
        rangeTest: null,
        adminKeys: keys,
      );

  group('admin keys in Meshtastic backups', () {
    test('saved as file version 4 and read back; no private key', () {
      final b = withKeys([otherKey]);
      final json = jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>;
      expect(json['version'], 4);
      expect(jsonEncode(json), isNot(contains(base64Encode(ownPrivate))));
      final back = RadioBackup.fromJson('/x', json) as MeshtasticBackup;
      expect(back.adminKeys, [otherKey]);
      expect(back.sameSettingsAs(b), isTrue);
      // An empty list is saved too (restoring it clears the grant).
      final none = RadioBackup.fromJson(
          '/x',
          jsonDecode(jsonEncode(withKeys([]).toJson()))
              as Map<String, dynamic>) as MeshtasticBackup;
      expect(none.adminKeys, isEmpty);
    });

    test('older files (no admin keys) still read, as version 2', () {
      final b = withKeys(null);
      final json = jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>;
      expect(json['version'], 2);
      final back = RadioBackup.fromJson('/x', json) as MeshtasticBackup;
      expect(back.adminKeys, isNull);
    });

    test('a different admin list is a different backup', () {
      expect(
          withKeys([otherKey]).sameSettingsAs(withKeys([otherKey, mobileKey])),
          isFalse);
      expect(withKeys(null).sameSettingsAs(withKeys([])), isFalse);
    });

    test('a damaged admin key is refused', () {
      final json = jsonDecode(jsonEncode(withKeys([otherKey]).toJson()))
          as Map<String, dynamic>;
      (json['protobuf'] as Map<String, dynamic>)['adminKeys'] = [
        base64Encode([1, 2, 3])
      ];
      expect(() => RadioBackup.fromJson('/x', json),
          throwsA(isA<FormatException>()));
    });

    test('the restore preview lists the admin keys', () {
      final line = restoreDiff(withKeys([otherKey, mobileKey]), withKeys([]))
          .singleWhere((l) => l.label.startsWith('Admin keys'));
      expect(line.from, '55000102…, a1000102…');
      expect(line.to, 'none');
      expect(line.changed, isTrue);
    });
  });

  group('restore writes the admin keys back', () {
    late Directory dir;
    late MeshtasticRadio radio;
    late FakeMeshtasticTransport t;
    late RadioBackupService svc;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('backups_admin');
      svc = RadioBackupService(directory: dir);
      t = FakeMeshtasticTransport(
        myNodeNum: node,
        nodes: [
          pb.NodeInfo(
              num: node, user: pb.User(longName: 'Base', publicKey: ownKey))
        ],
        security: pb.Config_SecurityConfig(
            publicKey: ownKey,
            privateKey: ownPrivate,
            adminKey: [otherKey, mobileKey]),
      );
      radio = MeshtasticRadio(transport: t);
      await radio.connect(const RadioDescriptor(id: 'base', name: 'Base'));
    });
    tearDown(() async {
      await radio.dispose();
      dir.deleteSync(recursive: true);
    });

    pb.Config_SecurityConfig written() => t.localAdmin
        .singleWhere((m) => m.hasSetConfig() && m.setConfig.hasSecurity())
        .setConfig
        .security;

    test('a snapshot saves the admin keys from the config download', () async {
      final b = await svc.snapshot(radio) as MeshtasticBackup;
      expect(b.adminKeys, [otherKey, mobileKey]);
    });

    test('a backup with keys puts exactly that list back, identity kept',
        () async {
      final outcome =
          await svc.restore(radio, withKeys([otherKey]), onStep: (_) {});
      final s = written();
      expect(s.adminKey, [otherKey]);
      expect(s.privateKey, ownPrivate);
      expect(s.publicKey, ownKey);
      expect(outcome.removed(mobileKey), isTrue);
      // Inside the one transaction, before the commit.
      final kinds = t.localAdmin.map((m) => m.whichPayloadVariant()).toList();
      expect(
          kinds.indexOf(pb.AdminMessage_PayloadVariant.beginEditSettings),
          lessThan(
              kinds.lastIndexOf(pb.AdminMessage_PayloadVariant.setConfig)));
      expect(kinds.last, pb.AdminMessage_PayloadVariant.commitEditSettings);
    });

    test('an older backup only loses the key it is told to remove', () async {
      final outcome = await svc.restore(radio, withKeys(null),
          onStep: (_) {}, removeAdminKeys: [mobileKey]);
      expect(written().adminKey, [otherKey]);
      expect(outcome.removed(mobileKey), isTrue);
    });

    test('an older backup with nothing to remove leaves security alone',
        () async {
      final outcome = await svc.restore(radio, withKeys(null), onStep: (_) {});
      expect(
          t.localAdmin
              .where((m) => m.hasSetConfig() && m.setConfig.hasSecurity()),
          isEmpty);
      expect(outcome.adminKeys, isNull);
      expect(outcome.removed(mobileKey), isFalse);
    });

    test('the same list writes no security config', () async {
      final outcome = await svc.restore(radio, withKeys([otherKey, mobileKey]),
          onStep: (_) {});
      expect(
          t.localAdmin
              .where((m) => m.hasSetConfig() && m.setConfig.hasSecurity()),
          isEmpty);
      expect(outcome.removed(mobileKey), isFalse);
    });

    test('without the private key the keys are skipped, the rest restored',
        () async {
      t.security = pb.Config_SecurityConfig(
          publicKey: ownKey, adminKey: [otherKey, mobileKey]);
      final steps = <String>[];
      final outcome = await svc.restore(radio, withKeys([]), onStep: steps.add);
      expect(
          t.localAdmin
              .where((m) => m.hasSetConfig() && m.setConfig.hasSecurity()),
          isEmpty);
      expect(outcome.adminKeyProblem, isNotNull);
      expect(outcome.removed(mobileKey), isFalse);
      expect(steps.last, 'Done');
    });
  });
}
