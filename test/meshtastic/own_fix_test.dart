// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;

import 'fake_meshtastic_transport.dart';

/// Our Meshtastic node's own position as a phone-side fix (docs/design/
/// ipad step 5): firmware 2.8 sends it to the phone every 60 s, never on
/// air; it arrives as our own NodeInfo or a POSITION_APP packet from us.
void main() {
  final now = DateTime.utc(2026, 11, 10, 12);
  int secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  pb.NodeInfo node(int num, pb.Position pos) =>
      pb.NodeInfo(num: num, position: pos);

  test('our own node with a position is a fix, timed by the node', () {
    final taken = now.subtract(const Duration(seconds: 40));
    final fix = ownFixFromNodeInfo(
      node(
          7,
          pb.Position(
              latitudeI: 336801000,
              longitudeI: -1162405000,
              altitude: 41,
              time: secs(taken))),
      myNodeNum: 7,
      now: now,
    )!;
    expect(fix.latitude, closeTo(33.6801, 1e-9));
    expect(fix.longitude, closeTo(-116.2405, 1e-9));
    expect(fix.altitudeM, 41);
    expect(fix.time.isAtSameMomentAs(taken), isTrue);
    expect(fix.accuracyM, 10, reason: 'no DOP sent by default');
  });

  test("another node's position, or none, is not a fix", () {
    final pos = pb.Position(latitudeI: 336801000, longitudeI: -1162405000);
    expect(ownFixFromNodeInfo(node(8, pos), myNodeNum: 7, now: now), isNull);
    expect(ownFixFromNodeInfo(pb.NodeInfo(num: 7), myNodeNum: 7, now: now),
        isNull);
    expect(ownFixFromNodeInfo(node(7, pos), myNodeNum: null, now: now), isNull);
    expect(
        ownFixFromNodeInfo(node(7, pb.Position(time: secs(now))),
            myNodeNum: 7, now: now),
        isNull,
        reason: '0,0 is no fix');
  });

  test('a time in the future (clock not set) falls back to now', () {
    final fix = nodeFixFromPosition(
        pb.Position(
            latitudeI: 1,
            longitudeI: 1,
            time: secs(now.add(const Duration(hours: 3)))),
        now: now);
    expect(fix.time, now);
  });

  test('DOP and the GPS accuracy give the accuracy when sent', () {
    final fix = nodeFixFromPosition(
        pb.Position(latitudeI: 1, longitudeI: 1, hDOP: 150, gpsAccuracy: 3000),
        now: now);
    expect(fix.accuracyM, closeTo(4.5, 1e-9));
  });

  group('firmware before 2.8: node list re-read (want_config_id 69421)', () {
    const me = 0x11;
    FakeMeshtasticTransport node({
      required String firmware,
      pb.Config_PositionConfig_GpsMode gps =
          pb.Config_PositionConfig_GpsMode.ENABLED,
    }) =>
        FakeMeshtasticTransport(myNodeNum: me, nodes: [
          pb.NodeInfo(num: me, user: pb.User(longName: 'Mobile')),
          pb.NodeInfo(num: 0x22, user: pb.User(longName: 'Base')),
        ])
          ..firmwareVersion = firmware
          ..position = pb.Config_PositionConfig(gpsMode: gps);

    Future<MeshtasticRadio> connected(FakeMeshtasticTransport t) async {
      final r = MeshtasticRadio(transport: t);
      await r.connect(const RadioDescriptor(id: 'm', name: 'Mobile'));
      return r;
    }

    int rereads(FakeMeshtasticTransport t) => t.written
        .where((w) => w.hasWantConfigId() && w.wantConfigId == 69421)
        .length;

    test('2.7.26 with GPS on: re-read brings our fresh position', () async {
      final t = node(firmware: '2.7.26.54e0d8d');
      final r = await connected(t);
      expect(r.needsOwnFixRefresh, isTrue);
      final fixes = <NodeFix>[];
      final sub = r.ownFixes.listen(fixes.add);

      // The GPS has a new fix since the handshake.
      t.nodes[0] = pb.NodeInfo(
          num: me,
          user: pb.User(longName: 'Mobile'),
          position: pb.Position(
              latitudeI: 336801000,
              longitudeI: -1162405000,
              time: DateTime.now().millisecondsSinceEpoch ~/ 1000));
      r.refreshOwnFixNow();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rereads(t), 1);
      expect(fixes.single.latitude, closeTo(33.6801, 1e-9));
      expect(r.isReady, isTrue, reason: 'the link carries on');

      // Not wanted (the phone has its own fix): no re-read.
      r.ownFixesWanted = false;
      r.refreshOwnFixNow();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rereads(t), 1);
      await sub.cancel();
      await r.dispose();
    });

    test('2.8, or the GPS off: never re-read', () async {
      for (final t in [
        node(firmware: '2.8.1.8e6a88d'),
        node(
            firmware: '2.7.26.54e0d8d',
            gps: pb.Config_PositionConfig_GpsMode.DISABLED),
      ]) {
        final r = await connected(t);
        expect(r.needsOwnFixRefresh, isFalse);
        r.refreshOwnFixNow();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(rereads(t), 0);
        await r.dispose();
      }
    });
  });
}
