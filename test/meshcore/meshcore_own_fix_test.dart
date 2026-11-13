// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_frames.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_lpp.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_settings.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_protocol.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_radio.dart';

import 'fake_meshcore_transport.dart';
import 'meshcore_radio_test.dart'
    show ownKey, baseKey, desc, fakeRadio, pump, connected;

/// Our MeshCore node's GPS (docs/design/ipad step 5): asked for with the
/// self telemetry request, answered over Bluetooth only, as Cayenne LPP.
List<int> _s24(int v) => [(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

/// What a T1000-E sends: voltage, MCU temperature, then GPS on channel 1.
Uint8List lppWithGps(double lat, double lon, double altM) =>
    Uint8List.fromList([
      1, 116, 0x01, 0x9A, // 4.10 V
      1, 103, 0x00, 0xFA, // 25.0 °C
      1, 136,
      ..._s24((lat * 10000).round()),
      ..._s24((lon * 10000).round()),
      ..._s24((altM * 100).round()),
    ]);

Uint8List lppNoGps() => Uint8List.fromList([1, 116, 0x01, 0x9A]);

/// PUSH_CODE_TELEMETRY_RESPONSE `[0x8B][0][key prefix x6][lpp…]`.
List<int> telemetryPush(Uint8List key, Uint8List lpp) =>
    [MeshCorePush.telemetryResponse, 0, ...key.sublist(0, 6), ...lpp];

void main() {
  group('lppGps', () {
    test('finds the GPS after other entries, negative longitude', () {
      final g = lppGps(lppWithGps(33.6801, -116.2405, 12.5))!;
      expect(g.latitude, closeTo(33.6801, 1e-9));
      expect(g.longitude, closeTo(-116.2405, 1e-9));
      expect(g.altitudeM, closeTo(12.5, 1e-9));
    });

    test('none without a GPS entry, or past an unknown type', () {
      expect(lppGps(lppNoGps()), isNull);
      expect(lppGps(Uint8List.fromList([1, 250, 0, 0, ...lppWithGps(1, 2, 3)])),
          isNull);
      expect(lppGps(Uint8List(0)), isNull);
    });

    test('a 0,0 position is no fix', () {
      expect(nodeFixFromLpp(lppWithGps(0, 0, 0), now: DateTime(2026)), isNull);
    });
  });

  group('MeshCoreRadio own fixes', () {
    MeshCoreRadio radio(FakeMeshCoreTransport t) => MeshCoreRadio(
          transport: t,
          commandTimeout: const Duration(milliseconds: 500),
          contactsIdleTimeout: const Duration(milliseconds: 500),
          statsInterval: const Duration(hours: 1),
          fixInterval: const Duration(milliseconds: 40),
          noGpsFixInterval: const Duration(hours: 1),
        );

    int polls(FakeMeshCoreTransport t) =>
        t.writtenCodes.where((c) => c == MeshCoreCmd.sendTelemetryReq).length;

    test('our telemetry with GPS becomes a fix; polling keeps going', () async {
      final t = fakeRadio();
      final r = radio(t);
      final fixes = <NodeFix>[];
      final sub = r.ownFixes.listen(fixes.add);
      await r.connect(desc);
      await pump();
      expect(t.writes.last, [MeshCoreCmd.sendTelemetryReq, 0, 0, 0]);

      t.push(telemetryPush(ownKey, lppWithGps(33.68, -116.24, 20)));
      await pump();
      expect(fixes, hasLength(1));
      expect(fixes.single.latitude, closeTo(33.68, 1e-9));
      expect(r.lastOwnFix, same(fixes.single));

      final before = polls(t);
      await pump(150);
      expect(polls(t), greaterThan(before), reason: 'every fixInterval');
      await sub.cancel();
      await r.dispose();
    });

    test("another node's telemetry is not ours", () async {
      final t = fakeRadio();
      final r = radio(t);
      await r.connect(desc);
      await pump();
      t.push(telemetryPush(baseKey, lppWithGps(33.68, -116.24, 20)));
      await pump();
      expect(r.lastOwnFix, isNull);
      await r.dispose();
    });

    test('not wanted (the phone has its own fix): no polling', () async {
      final t = fakeRadio();
      final r = radio(t)..ownFixesWanted = false;
      await r.connect(desc);
      await pump(150);
      expect(polls(t), 0);
      r.ownFixesWanted = true;
      await pump();
      expect(polls(t), greaterThan(0), reason: 'asks at once when wanted');
      await r.dispose();
    });

    test('a node without GPS is asked rarely', () async {
      final t = fakeRadio();
      final r = radio(t);
      await r.connect(desc);
      await pump();
      t.push(telemetryPush(ownKey, lppNoGps()));
      await pump(150);
      final after = polls(t);
      await pump(150);
      expect(polls(t), after, reason: 'noGpsFixInterval is an hour');
      expect(r.lastOwnFix, isNull);
      await r.dispose();
    });
  });

  group('Node Setup turns the mobile GPS on (custom var gps)', () {
    const preset = RadioPreset(
        id: 'MC_TEST', displayName: 'Test', sf: 8, bwKHz: 62.5, cr: 5);
    TestProfile profile({required bool base}) => TestProfile(
          channelName: 'MeshTest',
          channelKey: Uint8List(32),
          preset: preset,
          isBase: base,
          baseRelays: false,
          frequencyMHz: 918.0,
        );

    String? gpsWrite(FakeMeshCoreTransport t) {
      final w = t.writes.where((c) => c[0] == MeshCoreCmd.setCustomVar);
      return w.isEmpty ? null : String.fromCharCodes(w.last.sublist(1));
    }

    List<List<int>> varsReply(String text) => [
          [MeshCoreResp.customVars, ...text.codeUnits]
        ];

    test('parseCustomVars', () {
      expect(parseCustomVars('gps:0,gps_interval:30'),
          {'gps': '0', 'gps_interval': '30'});
      expect(parseCustomVars(''), isEmpty);
    });

    test('a mobile T1000-E with its GPS off gets gps:1', () async {
      final t = fakeRadio();
      t.overrides[MeshCoreCmd.getCustomVars] = (_) => varsReply('gps:0');
      final r = await connected(t);
      final steps = <String>[];
      await r.applyTestProfile(profile(base: false), onStep: steps.add);
      expect(gpsWrite(t), 'gps:1');
      expect(steps, contains("Turning on this node's GPS"));
      expect(r.settings?.gps, '1');
      await r.dispose();
    });

    test('the base, a GPS already on, or no GPS switch: nothing written',
        () async {
      for (final (vars, base) in [
        ('gps:0', true),
        ('gps:1', false),
        ('', false)
      ]) {
        final t = fakeRadio();
        t.overrides[MeshCoreCmd.getCustomVars] = (_) => varsReply(vars);
        final r = await connected(t);
        await r.applyTestProfile(profile(base: base));
        expect(gpsWrite(t), isNull, reason: '$vars base=$base');
        await r.dispose();
      }
    });

    test('the backup keeps gps; Restore turns it back off', () async {
      final t = fakeRadio();
      t.overrides[MeshCoreCmd.getCustomVars] = (_) => varsReply('gps:0');
      final r = await connected(t);
      await r.readCustomVars();
      final saved = r.settings!;
      expect(saved.gps, '0');
      final again = MeshCoreSettings.fromJson(saved.toJson());
      expect(again.gps, '0');
      expect(again.sameAs(saved), isTrue);

      await r.applyTestProfile(profile(base: false));
      expect(gpsWrite(t), 'gps:1');
      await r.applySettings(again);
      expect(gpsWrite(t), 'gps:0');
      await r.dispose();
    });
  });
}
