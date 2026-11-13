// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:mesh_analyzer/proto/meshtastic/channel.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/config.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;

import '../data/database/app_database.dart';
import '../data/radio/mesh_radio.dart';
import '../data/radio/meshtastic/meshtastic_presets.dart';
import '../data/radio/meshtastic/meshtastic_radio.dart';
import '../data/radio/switchable_radio.dart';
import '../services/airtime_meter.dart';
import '../services/airtime_model.dart';
import '../services/gps_service.dart';
import '../services/out_of_range_monitor.dart';
import '../services/rig_math.dart';
import '../services/session_manager.dart';
import '../utils/constants.dart';
import 'demo_site.dart';
import 'demo_walk.dart';

/// Fills the (separate, throwaway) demo database with the current
/// [DemoSite]'s sessions and makes the radio pretend to be connected. Demo
/// mode only.
class DemoSeeder {
  static const mobileNodeNum = 0x8a2fe4ea;
  static const baseNodeNum = 0x4f68b8f4;

  static Future<void> run({
    required AppDatabase db,
    required MeshRadio radio,
    required SessionManager sessions,
    required OutOfRangeMonitor monitor,
    required GpsService gps,
    required AirtimeMeter airtime,
    required List<int> channelKey,
  }) async {
    _setUpRadio(radio, channelKey);
    _feedAirtime(airtime);

    final site = DemoSite.current;
    final selfId = await db.upsertNode(
      nodeId: mobileNodeNum,
      longName: site.mobileName,
      shortName: site.mobileShort,
      hwModel: 'TRACKER_T1000_E',
    );
    final baseId = await db.upsertNode(
      nodeId: baseNodeNum,
      longName: site.baseName,
      shortName: 'BASE',
      hwModel: 'TRACKER_T1000_E',
    );

    final baseLat = site.base.latitude;
    final baseLon = site.base.longitude;
    await db.updateNodePosition(baseNodeNum, baseLat, baseLon);

    final mapId = await db.createCoverageMap(
      name: site.mapName,
      baseLat: baseLat,
      baseLon: baseLon,
      description: site.mapDescription,
    );
    final now = DateTime.now();
    final mobileRig = RigProfilesCompanion.insert(
      name: 'Stock stubby',
      role: const Value(rigRoleMobile),
      radioModel: const Value('Seeed T1000-E'),
      antennaName: const Value('Stock stubby'),
      antennaGainDbi: const Value(2.0),
      createdAt: now,
      updatedAt: now,
    );
    final baseRig = RigProfilesCompanion.insert(
      name: 'Fiberglass 5.8 dBi + 3 m LMR-240',
      role: const Value(rigRoleBase),
      radioModel: const Value('Seeed T1000-E'),
      antennaName: const Value('Fiberglass collinear'),
      antennaGainDbi: const Value(5.8),
      cableType: const Value('lmr240'),
      cableLengthM: const Value(3.0),
      connectorCount: const Value(2),
      createdAt: now,
      updatedAt: now,
    );
    final mobileRigId = await db.insertRigProfile(mobileRig);
    final baseRigId = await db.insertRigProfile(baseRig);
    final mobileSpec =
        RigSpec.fromProfile((await db.getRigProfile(mobileRigId))!);
    final baseSpec = RigSpec.fromProfile((await db.getRigProfile(baseRigId))!);

    Future<int> newSession(String name, RigSpec mobile, int mobileId) =>
        db.createSession(
          mobileRigId: mobileId,
          baseRigId: baseRigId,
          mobileRigJson: mobile.encode(),
          baseRigJson: baseSpec.encode(),
          hwAntenna: mobile.antennaName,
          hwNodeModel: mobile.radioModel,
          coverageMapId: mapId,
          baseNodeId: baseId,
          name: name,
          pingIntervalSec: 15,
          loraPreset: 'MEDIUM_FAST',
          packetAirtimeMs:
              AirtimeModel.pingAirtimeMs(MeshtasticPresets.mediumFast),
          beaconKind: BeaconKind.telemetry.dbValue,
          beaconIntervalSec: 60,
        );

    final live = site.live;
    final sessionId = await newSession(site.liveName, mobileSpec, mobileRigId);

    // The walk ends ~20 s ago, so it fills the live charts' time window.
    final end = DateTime.now().subtract(const Duration(seconds: 20));
    final start = end.subtract(Duration(seconds: live.last.t));
    await (db.update(db.sessions)..where((s) => s.id.equals(sessionId)))
        .write(SessionsCompanion(startedAt: Value(start)));
    await _insertRows(db, sessionId, live, start, selfId, baseId, Random(7));

    final lapStart = start.subtract(const Duration(hours: 2));
    final secondLap = site.secondLap;
    if (secondLap == null) {
      await _seedSecondLap(
        db: db,
        mapId: mapId,
        selfId: selfId,
        baseId: baseId,
        baseRigId: baseRigId,
        baseSpec: baseSpec,
        lapStart: lapStart,
        rows: live,
        name: site.secondLapName,
      );
    } else {
      final whipId = await _insertWhip(db);
      final whip = RigSpec.fromProfile((await db.getRigProfile(whipId))!);
      final id = await newSession(site.secondLapName, whip, whipId);
      await _finish(db, id, lapStart, secondLap);
      await _insertRows(
          db, id, secondLap, lapStart, selfId, baseId, Random(11));
    }

    for (final x in site.extra) {
      final id = await newSession(x.name, mobileSpec, mobileRigId);
      final t0 = start.subtract(Duration(days: x.daysAgo, minutes: 40));
      await _finish(db, id, t0, x.rows);
      await _insertRows(db, id, x.rows, t0, selfId, baseId, Random(13));
    }

    final last = live.last;
    gps.useDemoPosition(last.lat, last.lon, altitude: last.alt ?? 0);

    final session = await db.getSessionById(sessionId);
    if (session != null) await sessions.attachDemo(session);
    monitor.onPacketReceived(baseNodeNum); // base in range
  }

  static Future<void> _finish(
      AppDatabase db, int sessionId, DateTime start, List<DemoRow> rows) {
    return (db.update(db.sessions)..where((s) => s.id.equals(sessionId)))
        .write(SessionsCompanion(
      startedAt: Value(start),
      endedAt: Value(start.add(Duration(seconds: rows.last.t))),
      isActive: const Value(false),
    ));
  }

  /// Packet rows of one session, with each delivered ping linked to the
  /// base's reply nearest its round trip.
  static Future<void> _insertRows(
      AppDatabase db,
      int sessionId,
      List<DemoRow> rows,
      DateTime start,
      int selfId,
      int baseId,
      Random rng) async {
    final pingTx = <int, int>{}; // row index → tx event id
    final ackAt = <int, int>{}; // seconds from start → ack event id

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final isPing = r.direction == PacketDirection.tx;
      final id = await db.insertPacketEvent(PacketEventsCompanion.insert(
        sessionId: sessionId,
        timestamp: start.add(Duration(seconds: r.t)),
        direction: r.direction,
        sourceNodeId: r.fromBase ? baseId : selfId,
        rxSnr: Value(r.snr),
        rxRssi: Value(r.rssi),
        hopCount: Value(r.hops),
        rxLat: Value(r.lat),
        rxLon: Value(r.lon),
        rxAlt: Value(_isMiss(r) ? null : r.alt),
        gpsAccuracy: Value(_isMiss(r) ? null : r.accuracy),
        packetType: _demoType(r),
        sourceKind: Value(_demoKind(r)),
        baseChannelUtil: Value(_demoUtil(r, rng)),
        meshPacketId: Value(_isMiss(r) ? null : rng.nextInt(0x7fffffff)),
      ));
      if (isPing) {
        pingTx[i] = id;
        await db.insertPingCorrelation(
          PingCorrelationsCompanion.insert(txEventId: id),
        );
      } else if (r.direction == PacketDirection.ack) {
        ackAt[r.t] = id;
      }
    }

    for (final entry in pingTx.entries) {
      final r = rows[entry.key];
      final status = r.ackStatus ?? AckStatus.timeout;
      if (status == AckStatus.timeout) continue; // the default
      final expected = r.t + ((r.roundTripMs ?? 0) / 1000).round();
      int? ackId;
      var best = 1 << 30;
      ackAt.forEach((t, id) {
        final d = (t - expected).abs();
        if (t >= r.t && d < best && d <= 5) {
          best = d;
          ackId = id;
        }
      });
      await db.updatePingCorrelation(
        txEventId: entry.value,
        ackEventId: ackId,
        roundTripMs: r.roundTripMs,
        status: status,
      );
    }
  }

  /// A beacon the base sent that the mobile did not hear (generated sites
  /// write these like the app's BeaconTracker does).
  static bool _isMiss(DemoRow r) => r.type == 'miss';

  // The demo base runs the telemetry beacon (what firmware 2.8 supports):
  // the walk's beacon rows become device telemetry from the base.
  static String _demoType(DemoRow r) =>
      r.type == PacketType.rangeTest || _isMiss(r)
          ? PacketType.telemetry
          : r.type;

  static String _demoKind(DemoRow r) => switch (_demoType(r)) {
        _ when _isMiss(r) => SourceKind.telemetryMiss,
        PacketType.telemetry => SourceKind.telemetry,
        PacketType.ack => SourceKind.ack,
        _ => SourceKind.passive,
      };

  static double? _demoUtil(DemoRow r, Random rng) =>
      _demoKind(r) == SourceKind.telemetry ? 2 + rng.nextDouble() * 4 : null;

  /// A finished second lap of the same route two hours earlier with a
  /// 5.8 dBi whip instead of the stock stubby (+3.7 dB net on paper), so
  /// rig comparison has something to show. Readings follow the first walk
  /// with a few metres of GPS wobble and about 4 dB more signal.
  static Future<void> _seedSecondLap({
    required AppDatabase db,
    required int mapId,
    required int selfId,
    required int baseId,
    required int baseRigId,
    required RigSpec baseSpec,
    required DateTime lapStart,
    required List<DemoRow> rows,
    required String name,
  }) async {
    final whipId = await _insertWhip(db);
    final whip = RigSpec.fromProfile((await db.getRigProfile(whipId))!);
    final sessionId = await db.createSession(
      mobileRigId: whipId,
      baseRigId: baseRigId,
      mobileRigJson: whip.encode(),
      baseRigJson: baseSpec.encode(),
      hwAntenna: whip.antennaName,
      hwNodeModel: whip.radioModel,
      coverageMapId: mapId,
      baseNodeId: baseId,
      name: name,
      pingIntervalSec: 15,
      loraPreset: 'MEDIUM_FAST',
      packetAirtimeMs: AirtimeModel.pingAirtimeMs(MeshtasticPresets.mediumFast),
      beaconKind: BeaconKind.telemetry.dbValue,
      beaconIntervalSec: 60,
    );
    final end = lapStart.add(Duration(seconds: rows.last.t));
    await (db.update(db.sessions)..where((s) => s.id.equals(sessionId))).write(
      SessionsCompanion(
        startedAt: Value(lapStart),
        endedAt: Value(end),
        isActive: const Value(false),
      ),
    );

    final rng = Random(11);
    double jitter(double span) => (rng.nextDouble() - 0.5) * span;
    for (final r in rows) {
      if (r.rssi == null || r.direction == PacketDirection.tx) continue;
      // ~5 m of GPS wobble (1e-5 deg is about a metre).
      final gain = 4.2 + jitter(3);
      await db.insertPacketEvent(PacketEventsCompanion.insert(
        sessionId: sessionId,
        timestamp: lapStart.add(Duration(seconds: r.t)),
        direction: r.direction,
        sourceNodeId: r.fromBase ? baseId : selfId,
        rxSnr: Value(r.snr == null ? null : r.snr! + gain * 0.5),
        rxRssi: Value((r.rssi! + gain).round().clamp(-125, -20)),
        hopCount: Value(r.hops),
        rxLat: Value(r.lat + jitter(1e-4)),
        rxLon: Value(r.lon + jitter(1e-4)),
        rxAlt: Value(r.alt),
        gpsAccuracy: Value(r.accuracy),
        packetType: _demoType(r),
        sourceKind: Value(_demoKind(r)),
        baseChannelUtil: Value(_demoUtil(r, rng)),
        meshPacketId: Value(rng.nextInt(0x7fffffff)),
      ));
    }
  }

  static Future<int> _insertWhip(AppDatabase db) {
    final now = DateTime.now();
    return db.insertRigProfile(RigProfilesCompanion.insert(
      name: '5.8 dBi whip',
      role: const Value(rigRoleMobile),
      radioModel: const Value('Seeed T1000-E'),
      antennaName: const Value('Whip 5.8 dBi'),
      antennaGainDbi: const Value(5.8),
      connectorCount: const Value(1),
      createdAt: now,
      updatedAt: now,
    ));
  }

  /// The demo radio sends nothing, so feed the airtime meter what a ping
  /// every 15 s on MEDIUM_FAST would use (~1.1 %): four recent pings, then
  /// one more every 15 s for as long as the app runs.
  static void _feedAirtime(AirtimeMeter meter) {
    final pingMs = AirtimeModel.pingAirtimeMs(MeshtasticPresets.mediumFast);
    final now = DateTime.now();
    for (final ago in const [50, 35, 20, 5]) {
      meter.record(pingMs, at: now.subtract(Duration(seconds: ago)));
    }
    Timer.periodic(const Duration(seconds: 15), (_) => meter.record(pingMs));
  }

  static void _setUpRadio(MeshRadio phoneRadio, List<int> key) {
    // Demo mode pretends to be a Meshtastic radio.
    final radio = radioAs<MeshtasticRadio>(phoneRadio);
    if (radio == null) {
      throw StateError('Demo mode needs a Meshtastic node');
    }
    pb.NodeInfo node(int num, String long, String short, int hopsAway) =>
        pb.NodeInfo(
          num: num,
          user: pb.User(
            longName: long,
            shortName: short,
            hwModel: pb.HardwareModel.TRACKER_T1000_E,
          ),
          hopsAway: hopsAway,
          lastHeard: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );

    radio.enterDemo(
      name: 'T1000-E_e4ea',
      myNodeNum: mobileNodeNum,
      nodeInfos: [
        node(mobileNodeNum, DemoSite.current.mobileName,
            DemoSite.current.mobileShort, 0),
        node(baseNodeNum, DemoSite.current.baseName, 'BASE', 0),
      ],
      lora: pb.Config_LoRaConfig(
        usePreset: true,
        modemPreset: pb.Config_LoRaConfig_ModemPreset.MEDIUM_FAST,
        region: pb.Config_LoRaConfig_RegionCode.US,
        hopLimit: 3,
        txEnabled: true,
      ),
      channelTable: [
        pb.Channel(
          index: 0,
          role: pb.Channel_Role.PRIMARY,
          settings: pb.ChannelSettings(name: 'MeshTest', psk: key),
        ),
        for (var i = 1; i < 8; i++)
          pb.Channel(index: i, role: pb.Channel_Role.DISABLED),
      ],
    );

    // The demo radio never reports on its own: a quiet field, refreshed
    // every minute like a real radio so the age stays "just now".
    void report() => radio.feedChannelStats(RadioChannelStats(
          airUtilTxPercent: 0.9,
          channelUtilizationPercent: 6,
          measuredAt: DateTime.now(),
        ));
    report();
    Timer.periodic(const Duration(seconds: 60), (_) => report());
  }
}
