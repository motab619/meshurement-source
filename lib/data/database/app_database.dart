// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../demo/demo_mode.dart';
import '../../utils/constants.dart';
import '../radio/radio_types.dart' show BeaconKind, RadioSettings;
import 'tables/all_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Nodes,
  CoverageMaps,
  Sessions,
  PacketEvents,
  PingCorrelations,
  RigProfiles,
  TestPlans,
  TestSteps,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // For testing
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          // Create indexes for performance
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_packet_events_session_time '
            'ON packet_events (session_id, timestamp)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_packet_events_source_time '
            'ON packet_events (source_node_id, timestamp)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_packet_events_location '
            'ON packet_events (rx_lat, rx_lon)',
          );
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.addColumn(sessions, sessions.loraPreset);
          }
          if (from < 3) {
            await m.addColumn(sessions, sessions.packetAirtimeMs);
          }
          if (from < 4) {
            await m.createTable(rigProfiles);
            await m.addColumn(sessions, sessions.mobileRigId);
            await m.addColumn(sessions, sessions.baseRigId);
            await m.addColumn(sessions, sessions.mobileRigJson);
            await m.addColumn(sessions, sessions.baseRigJson);
          }
          if (from < 5) {
            await m.addColumn(sessions, sessions.protocol);
          }
          if (from < 6) {
            await m.addColumn(sessions, sessions.radioAirUtilTx);
            await m.addColumn(sessions, sessions.radioChannelUtil);
          }
          if (from < 7) {
            await m.addColumn(packetEvents, packetEvents.seq);
            await m.addColumn(packetEvents, packetEvents.sourceKind);
            await m.addColumn(packetEvents, packetEvents.baseChannelUtil);
            await m.addColumn(sessions, sessions.beaconKind);
            await m.addColumn(sessions, sessions.beaconIntervalSec);
          }
          if (from < 8) {
            // The session, not the map, owns the base radio (field failure
            // 2026-10-27: a map's fixed base outlived Radio Setup). Rebuild
            // coverage_maps so base_node_id can be null, add the map's own
            // base location, and give old sessions their map's base.
            // drift's documented way to change a column's nullability.
            // ignore: experimental_member_use
            await m.alterTable(TableMigration(coverageMaps, newColumns: [
              coverageMaps.baseLat,
              coverageMaps.baseLon,
            ]));
            await m.addColumn(sessions, sessions.baseNodeId);
            await customStatement(
              'UPDATE sessions SET base_node_id = (SELECT m.base_node_id '
              'FROM coverage_maps m WHERE m.id = sessions.coverage_map_id) '
              'WHERE base_node_id IS NULL',
            );
            // Base location from the base node's own position. A position
            // the user placed (SharedPreferences, not reachable here) wins;
            // MapBaseMigration applies it at app start.
            await customStatement(
              'UPDATE coverage_maps SET '
              'base_lat = (SELECT n.last_lat FROM nodes n '
              'WHERE n.id = coverage_maps.base_node_id), '
              'base_lon = (SELECT n.last_lon FROM nodes n '
              'WHERE n.id = coverage_maps.base_node_id) '
              'WHERE base_lat IS NULL AND EXISTS (SELECT 1 FROM nodes n '
              'WHERE n.id = coverage_maps.base_node_id '
              'AND n.last_lat IS NOT NULL AND n.last_lon IS NOT NULL)',
            );
          }
          if (from < 9) {
            // Radio settings beyond the preset; old sessions stay null.
            await m.addColumn(sessions, sessions.region);
            await m.addColumn(sessions, sessions.frequencySlot);
            await m.addColumn(sessions, sessions.txPowerDbm);
            await m.addColumn(sessions, sessions.hopLimit);
            await m.addColumn(sessions, sessions.frequencyMhz);
          }
          if (from < 10) {
            // Uplink SNR (mobile → base) on ping replies; old rows null.
            await m.addColumn(packetEvents, packetEvents.uplinkSnr);
          }
          if (from < 11) {
            // Guided tests: plans with their steps, and the step a session
            // was recorded for.
            await m.createTable(testPlans);
            await m.createTable(testSteps);
            await m.addColumn(sessions, sessions.testStepId);
          }
        },
      );

  // ─── Node queries ────────────────────────────────────

  Future<Node?> getNodeByMeshId(int meshNodeId) =>
      (select(nodes)..where((n) => n.nodeId.equals(meshNodeId)))
          .getSingleOrNull();

  Future<int> upsertNode({
    required int nodeId,
    String longName = '',
    String shortName = '',
    String hwModel = '',
  }) {
    return into(nodes).insertOnConflictUpdate(
      NodesCompanion.insert(
        nodeId: nodeId,
        longName: Value(longName),
        shortName: Value(shortName),
        hwModel: Value(hwModel),
        firstSeenAt: DateTime.now(),
        lastHeardAt: DateTime.now(),
      ),
    );
  }

  /// Update names/hardware for a known node; no-op if it isn't in the DB.
  Future<void> updateNodeIdentity({
    required int nodeId,
    required String longName,
    required String shortName,
    required String hwModel,
  }) async {
    await (update(nodes)..where((n) => n.nodeId.equals(nodeId))).write(
      NodesCompanion(
        longName: Value(longName),
        shortName: Value(shortName),
        hwModel: Value(hwModel),
      ),
    );
  }

  Future<void> updateNodeLastHeard(int nodeId, {DateTime? at}) async {
    await (update(nodes)..where((n) => n.nodeId.equals(nodeId)))
        .write(NodesCompanion(lastHeardAt: Value(at ?? DateTime.now())));
  }

  Future<void> updateNodePosition(int nodeId, double lat, double lon) async {
    await (update(nodes)..where((n) => n.nodeId.equals(nodeId)))
        .write(NodesCompanion(lastLat: Value(lat), lastLon: Value(lon)));
  }

  Future<void> updateNodeLabel(int localId, String label) async {
    await (update(nodes)..where((n) => n.id.equals(localId)))
        .write(NodesCompanion(userLabel: Value(label)));
  }

  Future<List<Node>> getAllNodes() => select(nodes).get();

  Stream<List<Node>> watchAllNodes() => select(nodes).watch();

  // ─── Coverage Map queries ────────────────────────────

  /// A coverage map is a place: [baseLat]/[baseLon] say where the base
  /// stands. [baseNodeId] (local Nodes.id) is only for maps from before
  /// schema v8 and tests; sessions carry their own base radio.
  Future<int> createCoverageMap({
    required String name,
    int? baseNodeId,
    double? baseLat,
    double? baseLon,
    String description = '',
  }) {
    return into(coverageMaps).insert(
      CoverageMapsCompanion.insert(
        name: name,
        baseNodeId: Value(baseNodeId),
        baseLat: Value(baseLat),
        baseLon: Value(baseLon),
        createdAt: DateTime.now(),
        description: Value(description),
      ),
    );
  }

  Future<CoverageMap?> getCoverageMap(int id) =>
      (select(coverageMaps)..where((m) => m.id.equals(id))).getSingleOrNull();

  /// Set (or, with nulls, clear) where the base stands for a map.
  Future<void> setMapBaseLocation(int mapId, double? lat, double? lon) =>
      (update(coverageMaps)..where((m) => m.id.equals(mapId))).write(
        CoverageMapsCompanion(
          baseLat: Value(lat == null || lon == null ? null : lat),
          baseLon: Value(lat == null || lon == null ? null : lon),
        ),
      );

  /// Local Nodes.id of [session]'s base radio: its own, else (sessions
  /// from before schema v8) its map's.
  Future<int?> baseNodeIdForSession(Session session) async {
    if (session.baseNodeId != null) return session.baseNodeId;
    return (await getCoverageMap(session.coverageMapId))?.baseNodeId;
  }

  /// Mesh node number of [session]'s base radio (see
  /// [baseNodeIdForSession]).
  Future<int?> baseMeshNodeIdForSession(Session session) async {
    final localId = await baseNodeIdForSession(session);
    if (localId == null) return null;
    final node = await (select(nodes)..where((n) => n.id.equals(localId)))
        .getSingleOrNull();
    return node?.nodeId;
  }

  /// Local Nodes.id of the base used by the newest session on a map that
  /// has one, else the map's own (pre-v8) base. Null when neither exists.
  Future<int?> latestBaseNodeIdForMap(int coverageMapId) async {
    final s = await (select(sessions)
          ..where((s) =>
              s.coverageMapId.equals(coverageMapId) & s.baseNodeId.isNotNull())
          ..orderBy([(s) => OrderingTerm.desc(s.startedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (s != null) return s.baseNodeId;
    return (await getCoverageMap(coverageMapId))?.baseNodeId;
  }

  /// Mesh node number of the base the newest session (any map) used, else
  /// the newest map's own (pre-v8) base. Null when nothing is known.
  Future<int?> latestBaseMeshNodeNum() async {
    final rows = await customSelect(
      'SELECT n.node_id AS num FROM sessions s '
      'JOIN nodes n ON n.id = s.base_node_id '
      'ORDER BY s.started_at DESC LIMIT 1',
      readsFrom: {sessions, nodes},
    ).get();
    if (rows.isNotEmpty) return rows.first.read<int>('num');
    final maps = await customSelect(
      'SELECT n.node_id AS num FROM coverage_maps m '
      'JOIN nodes n ON n.id = m.base_node_id '
      'ORDER BY m.created_at DESC LIMIT 1',
      readsFrom: {coverageMaps, nodes},
    ).get();
    return maps.isEmpty ? null : maps.first.read<int>('num');
  }

  /// Mesh node numbers of every base radio a map or session used.
  Future<Set<int>> mapBaseNodeNums() async {
    final rows = await customSelect(
      'SELECT DISTINCT n.node_id AS num FROM nodes n WHERE n.id IN '
      '(SELECT base_node_id FROM coverage_maps WHERE base_node_id IS NOT NULL '
      'UNION SELECT base_node_id FROM sessions WHERE base_node_id IS NOT NULL)',
      readsFrom: {coverageMaps, sessions, nodes},
    ).get();
    return {for (final r in rows) r.read<int>('num')};
  }

  Future<List<CoverageMap>> getAllCoverageMaps() => select(coverageMaps).get();

  Stream<List<CoverageMap>> watchAllCoverageMaps() =>
      select(coverageMaps).watch();

  /// Number of sessions, all maps.
  Stream<int> watchSessionCount() {
    final n = sessions.id.count();
    return (selectOnly(sessions)..addColumns([n]))
        .map((r) => r.read(n) ?? 0)
        .watchSingle();
  }

  /// Delete a map with its sessions, packets and ping links, all or
  /// nothing. Callers must not delete the map a session is recording into
  /// (check `SessionManager.isRecordingInto` first).
  Future<void> deleteCoverageMap(int id) => transaction(() async {
        // Guided tests are children of the map: their steps point at
        // sessions, so they go before the sessions do.
        final planIds = selectOnly(testPlans)
          ..addColumns([testPlans.id])
          ..where(testPlans.coverageMapId.equals(id));
        // A session filed under another map may still name one of these
        // steps (moved before moveSessions unlinked them): it stays, unlinked.
        final stepIds = selectOnly(testSteps)
          ..addColumns([testSteps.id])
          ..where(testSteps.planId.isInQuery(planIds));
        await (update(sessions)..where((s) => s.testStepId.isInQuery(stepIds)))
            .write(const SessionsCompanion(testStepId: Value(null)));
        await (delete(testSteps)..where((t) => t.planId.isInQuery(planIds)))
            .go();
        await (delete(testPlans)..where((t) => t.coverageMapId.equals(id)))
            .go();
        final sessionIds = (await (select(sessions)
                  ..where((s) => s.coverageMapId.equals(id)))
                .get())
            .map((s) => s.id)
            .toList();
        if (sessionIds.isNotEmpty) {
          // And another map's plan may name one of these sessions.
          await (update(testSteps)..where((t) => t.sessionId.isIn(sessionIds)))
              .write(const TestStepsCompanion(sessionId: Value(null)));
          final eventIds = selectOnly(packetEvents)
            ..addColumns([packetEvents.id])
            ..where(packetEvents.sessionId.isIn(sessionIds));
          await (delete(pingCorrelations)
                ..where((c) =>
                    c.txEventId.isInQuery(eventIds) |
                    c.ackEventId.isInQuery(eventIds)))
              .go();
          await (delete(packetEvents)
                ..where((e) => e.sessionId.isIn(sessionIds)))
              .go();
        }
        await (delete(sessions)..where((s) => s.coverageMapId.equals(id))).go();
        await (delete(coverageMaps)..where((m) => m.id.equals(id))).go();
      });

  /// File [ids] under another map (recorded on the wrong one). A session
  /// carries its own base radio, so that stays. A guided test belongs to
  /// the map it was planned on: a session moved away from its plan's map
  /// leaves the plan (the step keeps its place and loses its session, as
  /// when the session is deleted), so the plan never points at another
  /// map's session.
  Future<void> moveSessions(List<int> ids, int toCoverageMapId) =>
      transaction(() async {
        if (ids.isEmpty) return;
        final planOnOtherMap = selectOnly(testPlans)
          ..addColumns([testPlans.id])
          ..where(testPlans.coverageMapId.equals(toCoverageMapId).not());
        final leaving = selectOnly(testSteps)
          ..addColumns([testSteps.id])
          ..where(testSteps.sessionId.isIn(ids) &
              testSteps.planId.isInQuery(planOnOtherMap));
        await (update(sessions)
              ..where((s) => s.id.isIn(ids) & s.testStepId.isInQuery(leaving)))
            .write(const SessionsCompanion(testStepId: Value(null)));
        await (update(testSteps)
              ..where((t) =>
                  t.sessionId.isIn(ids) & t.planId.isInQuery(planOnOtherMap)))
            .write(const TestStepsCompanion(sessionId: Value(null)));
        await (update(sessions)..where((s) => s.id.isIn(ids))).write(
            SessionsCompanion(coverageMapId: Value(toCoverageMapId)));
      });

  /// Delete sessions with their packets and ping links, all or nothing. The
  /// map stays. Callers must not delete a session that is recording.
  Future<void> deleteSessions(List<int> ids) => transaction(() async {
        if (ids.isEmpty) return;
        // A guided-test step keeps its place; it just loses its session.
        await (update(testSteps)..where((t) => t.sessionId.isIn(ids)))
            .write(const TestStepsCompanion(sessionId: Value(null)));
        final eventIds = selectOnly(packetEvents)
          ..addColumns([packetEvents.id])
          ..where(packetEvents.sessionId.isIn(ids));
        await (delete(pingCorrelations)
              ..where((c) =>
                  c.txEventId.isInQuery(eventIds) |
                  c.ackEventId.isInQuery(eventIds)))
            .go();
        await (delete(packetEvents)..where((e) => e.sessionId.isIn(ids))).go();
        await (delete(sessions)..where((s) => s.id.isIn(ids))).go();
      });

  /// Drop what [sessionId] recorded at or after [from] (the base rode
  /// along with the phone from then on): its packet events and their ping
  /// correlations, in one transaction. An ended session's end time moves
  /// back to [from] and its packet count is refreshed. Returns how many
  /// events went, and how many of those were received (map points).
  Future<({int deleted, int received})> trimSessionAfter(
          int sessionId, DateTime from) =>
      transaction(() async {
        Expression<bool> inTrim($PacketEventsTable e) =>
            e.sessionId.equals(sessionId) &
            e.timestamp.isBiggerOrEqualValue(from);
        final eventIds = selectOnly(packetEvents)
          ..addColumns([packetEvents.id])
          ..where(inTrim(packetEvents));
        await (delete(pingCorrelations)
              ..where((c) =>
                  c.txEventId.isInQuery(eventIds) |
                  c.ackEventId.isInQuery(eventIds)))
            .go();
        final received = packetEvents.id.count();
        final r = await (selectOnly(packetEvents)
              ..addColumns([received])
              ..where(inTrim(packetEvents) &
                  packetEvents.direction.equals(PacketDirection.tx).not() &
                  packetEvents.sourceKind.isIn(SourceKind.notSamples).not()))
            .map((row) => row.read(received) ?? 0)
            .getSingle();
        final deleted =
            await (delete(packetEvents)..where((e) => inTrim(e))).go();
        final session = await getSessionById(sessionId);
        if (session != null) {
          final ended = session.endedAt;
          await (update(sessions)..where((s) => s.id.equals(sessionId)))
              .write(SessionsCompanion(
            packetCount: Value(await _countPacketEvents(sessionId)),
            endedAt: !session.isActive && ended != null && ended.isAfter(from)
                ? Value(from)
                : const Value.absent(),
          ));
        }
        return (deleted: deleted, received: r);
      });

  /// Sessions and packets recorded on a map (for the delete dialog).
  Future<({int sessions, int packets})> coverageMapCounts(int id) async {
    final sessionCount = sessions.id.count();
    final s = await (selectOnly(sessions)
          ..addColumns([sessionCount])
          ..where(sessions.coverageMapId.equals(id)))
        .map((r) => r.read(sessionCount) ?? 0)
        .getSingle();
    final packetCount = packetEvents.id.count();
    final p = await (selectOnly(packetEvents).join([
      innerJoin(sessions, sessions.id.equalsExp(packetEvents.sessionId),
          useColumns: false),
    ])
          ..addColumns([packetCount])
          ..where(sessions.coverageMapId.equals(id)))
        .map((r) => r.read(packetCount) ?? 0)
        .getSingle();
    return (sessions: s, packets: p);
  }

  // ─── Erasing history ─────────────────────────────────

  /// Delete nodes that no map, session or packet refers to (e.g. other
  /// groups' radios that were only heard in passing). Returns how many.
  Future<int> deleteUnusedNodes() => customUpdate(
        'DELETE FROM nodes WHERE id NOT IN (SELECT base_node_id FROM coverage_maps WHERE base_node_id IS NOT NULL) '
        'AND id NOT IN (SELECT base_node_id FROM sessions WHERE base_node_id IS NOT NULL) '
        'AND id NOT IN (SELECT remote_node_id FROM sessions WHERE remote_node_id IS NOT NULL) '
        'AND id NOT IN (SELECT source_node_id FROM packet_events)',
        updates: {nodes},
        updateKind: UpdateKind.delete,
      );

  /// Delete every coverage map, session, packet and ping result.
  Future<void> deleteAllMeasurements() => transaction(() async {
        await delete(testSteps).go();
        await delete(testPlans).go();
        await delete(pingCorrelations).go();
        await delete(packetEvents).go();
        await delete(sessions).go();
        await delete(coverageMaps).go();
      });

  /// Delete everything: measurements, nodes and rig profiles.
  Future<void> deleteAllData() => transaction(() async {
        await deleteAllMeasurements();
        await delete(nodes).go();
        await delete(rigProfiles).go();
      });

  // ─── Session queries ─────────────────────────────────

  Future<int> createSession({
    required int coverageMapId,
    String name = '',
    int? remoteNodeId,
    int? baseNodeId,
    String hwAntenna = '',
    String hwNodeModel = '',
    String hwNotes = '',
    int pingIntervalSec = 0,
    String loraPreset = '',
    String protocol = 'meshtastic',
    double packetAirtimeMs = 0,
    int? mobileRigId,
    int? baseRigId,
    String? mobileRigJson,
    String? baseRigJson,
    String beaconKind = '',
    int beaconIntervalSec = 0,
    RadioSettings? radioSettings,
  }) {
    final rs = radioSettings;
    return into(sessions).insert(
      SessionsCompanion.insert(
        coverageMapId: coverageMapId,
        name: Value(name),
        startedAt: DateTime.now(),
        isActive: const Value(true),
        remoteNodeId: Value(remoteNodeId),
        baseNodeId: Value(baseNodeId),
        hwAntenna: Value(hwAntenna),
        hwNodeModel: Value(hwNodeModel),
        loraPreset: Value(loraPreset),
        protocol: Value(protocol),
        hwNotes: Value(hwNotes),
        pingIntervalSec: Value(pingIntervalSec),
        packetAirtimeMs: Value(packetAirtimeMs),
        mobileRigId: Value(mobileRigId),
        baseRigId: Value(baseRigId),
        mobileRigJson: Value(mobileRigJson),
        baseRigJson: Value(baseRigJson),
        beaconKind: Value(beaconKind),
        beaconIntervalSec: Value(beaconIntervalSec),
        region: Value(rs == null || rs.region.isEmpty ? null : rs.region),
        frequencySlot: Value(rs?.frequencySlot),
        txPowerDbm: Value(rs?.txPowerDbm),
        hopLimit: Value(rs?.hopLimit),
        frequencyMhz: Value(rs?.frequencyMHz),
      ),
    );
  }

  // ─── Rig profile queries ─────────────────────────────

  /// Non-archived rigs, oldest first.
  Stream<List<RigProfile>> watchRigProfiles() => (select(rigProfiles)
        ..where((r) => r.archived.equals(false))
        ..orderBy([(r) => OrderingTerm.asc(r.id)]))
      .watch();

  Future<RigProfile?> getRigProfile(int id) =>
      (select(rigProfiles)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<int> insertRigProfile(RigProfilesCompanion rig) =>
      into(rigProfiles).insert(rig);

  Future<void> updateRigProfile(int id, RigProfilesCompanion rig) =>
      (update(rigProfiles)..where((r) => r.id.equals(id))).write(
        rig.copyWith(updatedAt: Value(DateTime.now())),
      );

  /// The non-archived rig called [name] (case-insensitive), or null.
  Future<RigProfile?> findRigProfileByName(String name) async {
    final rows = await (select(rigProfiles)
          ..where((r) =>
              r.archived.equals(false) &
              r.name.lower().equals(name.trim().toLowerCase()))
          ..orderBy([(r) => OrderingTerm.asc(r.id)])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Hide a rig from pickers; sessions that used it keep their snapshot.
  Future<void> archiveRigProfile(int id) =>
      (update(rigProfiles)..where((r) => r.id.equals(id))).write(
        RigProfilesCompanion(
          archived: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Store the highest radio-reported airtime figures seen in a session.
  Future<void> updateSessionRadioStats(
    int sessionId, {
    required double airUtilTx,
    required double channelUtil,
  }) =>
      (update(sessions)..where((s) => s.id.equals(sessionId))).write(
        SessionsCompanion(
          radioAirUtilTx: Value(airUtilTx),
          radioChannelUtil: Value(channelUtil),
        ),
      );

  Future<void> endSession(int sessionId) async {
    final count = await _countPacketEvents(sessionId);
    await (update(sessions)..where((s) => s.id.equals(sessionId))).write(
      SessionsCompanion(
        endedAt: Value(DateTime.now()),
        isActive: const Value(false),
        packetCount: Value(count),
      ),
    );
  }

  Future<int> _countPacketEvents(int sessionId) async {
    final query = selectOnly(packetEvents)
      ..addColumns([packetEvents.id.count()])
      ..where(packetEvents.sessionId.equals(sessionId) &
          packetEvents.sourceKind.isIn(SourceKind.notSamples).not());
    final result = await query.getSingle();
    return result.read(packetEvents.id.count()) ?? 0;
  }

  Future<Session?> getActiveSession() =>
      (select(sessions)..where((s) => s.isActive.equals(true)))
          .getSingleOrNull();

  Future<Session?> getSessionById(int id) =>
      (select(sessions)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<List<Session>> getSessionsByIds(Iterable<int> ids) =>
      (select(sessions)..where((s) => s.id.isIn(ids))).get();

  Future<List<Session>> getSessionsForMap(int coverageMapId) =>
      (select(sessions)..where((s) => s.coverageMapId.equals(coverageMapId)))
          .get();

  Stream<List<Session>> watchSessionsForMap(int coverageMapId) =>
      (select(sessions)
            ..where((s) => s.coverageMapId.equals(coverageMapId))
            ..orderBy([(s) => OrderingTerm.desc(s.startedAt)]))
          .watch();

  /// All packet events recorded in any session of a coverage map.
  Stream<List<PacketEvent>> watchEventsForMap(int coverageMapId) {
    final sessionIds = selectOnly(sessions)
      ..addColumns([sessions.id])
      ..where(sessions.coverageMapId.equals(coverageMapId));
    return (select(packetEvents)
          ..where((e) =>
              e.sessionId.isInQuery(sessionIds) &
              e.sourceKind.isIn(SourceKind.notSamples).not())
          ..orderBy([(e) => OrderingTerm.asc(e.timestamp)]))
        .watch();
  }

  /// Each ping sent in a coverage map's sessions, with its outcome.
  Stream<List<PingResult>> watchPingsForMap(int coverageMapId) {
    final sessionIds = selectOnly(sessions)
      ..addColumns([sessions.id])
      ..where(sessions.coverageMapId.equals(coverageMapId));
    final query = select(pingCorrelations).join([
      innerJoin(
        packetEvents,
        packetEvents.id.equalsExp(pingCorrelations.txEventId),
      ),
    ])
      ..where(packetEvents.sessionId.isInQuery(sessionIds));
    return query.watch().map((rows) => [
          for (final row in rows)
            PingResult(
              tx: row.readTable(packetEvents),
              correlation: row.readTable(pingCorrelations),
            ),
        ]);
  }

  Stream<Session?> watchActiveSession() =>
      (select(sessions)..where((s) => s.isActive.equals(true)))
          .watchSingleOrNull();

  /// Record which beacon a session turned out to run (learned from the
  /// first beacon heard when the session didn't start with it).
  Future<void> updateSessionBeacon(int sessionId,
      {required String kind, int? intervalSec}) async {
    await (update(sessions)..where((s) => s.id.equals(sessionId))).write(
      SessionsCompanion(
        beaconKind: Value(kind),
        beaconIntervalSec:
            intervalSec == null ? const Value.absent() : Value(intervalSec),
      ),
    );
  }

  /// Beacons heard and missed in a session, live. Range Test misses are
  /// the gaps in its sequence numbers (exact); telemetry misses are the
  /// synthesised `telemetry_miss` rows (timing, approximate). A trace
  /// session's beacon is its trace pings (MeshCore pulled beacon): heard =
  /// answered, missed = timed out (exact, every miss is a known timeout).
  Stream<BeaconStats> watchBeaconStats(int sessionId) =>
      // Built from watch streams only (no awaited query), so a listener
      // cancelled before the first row never leaves a query pending.
      (select(sessions)..where((s) => s.id.equals(sessionId)))
          .watchSingleOrNull()
          .take(1)
          .asyncExpand((session) =>
              session?.beaconKind == BeaconKind.trace.dbValue
                  ? _watchTraceBeaconStats(sessionId)
                  : _watchBeaconRowStats(sessionId));

  Stream<BeaconStats> _watchTraceBeaconStats(int sessionId) {
    final query = selectOnly(pingCorrelations).join([
      innerJoin(packetEvents,
          packetEvents.id.equalsExp(pingCorrelations.txEventId),
          useColumns: false),
    ])
      ..addColumns([
        pingCorrelations.ackStatus,
        pingCorrelations.ackEventId,
        packetEvents.timestamp,
      ])
      ..where(packetEvents.sessionId.equals(sessionId))
      ..orderBy([OrderingTerm.asc(packetEvents.timestamp)]);
    return query.watch().map((rows) {
      var heard = 0, missed = 0;
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final status = r.read(pingCorrelations.ackStatus);
        if (status == AckStatus.received) heard++;
        if (status != AckStatus.timeout) continue;
        // A ping row starts out as 'timeout' until its outcome is known.
        // Trace pings time out within one interval, so only the newest can
        // still be in flight.
        final sentAt = r.read(packetEvents.timestamp);
        final inFlight = i == rows.length - 1 &&
            r.read(pingCorrelations.ackEventId) == null &&
            sentAt != null &&
            DateTime.now().difference(sentAt) <
                const Duration(seconds: AppConstants.defaultAckTimeoutSec);
        if (!inFlight) missed++;
      }
      return BeaconStats(heard, missed, exact: true);
    });
  }

  Stream<BeaconStats> _watchBeaconRowStats(int sessionId) {
    final q = selectOnly(packetEvents)
      ..addColumns([
        packetEvents.seq,
        packetEvents.sourceKind,
        packetEvents.timestamp,
      ])
      ..where(packetEvents.sessionId.equals(sessionId) &
          packetEvents.sourceKind.isIn([
            SourceKind.rangeTest,
            SourceKind.telemetry,
            SourceKind.telemetryMiss,
          ]))
      ..orderBy([OrderingTerm.asc(packetEvents.timestamp)]);
    return q.watch().map((rows) => BeaconStats.fromRows([
          for (final r in rows)
            (r.read(packetEvents.sourceKind) ?? '', r.read(packetEvents.seq)),
        ]));
  }

  Future<void> markSessionRangeTestActive(int sessionId) async {
    await (update(sessions)..where((s) => s.id.equals(sessionId)))
        .write(const SessionsCompanion(rangeTestActive: Value(true)));
  }

  // ─── Packet Event queries ────────────────────────────

  /// Live count of packets recorded in a session.
  Stream<int> watchPacketCount(int sessionId) {
    final count = packetEvents.id.count();
    return (selectOnly(packetEvents)
          ..addColumns([count])
          ..where(packetEvents.sessionId.equals(sessionId) &
              packetEvents.sourceKind.isIn(SourceKind.notSamples).not()))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }

  Future<int> insertPacketEvent(PacketEventsCompanion event) =>
      into(packetEvents).insert(event);

  Future<void> insertPacketEventsBatch(
      List<PacketEventsCompanion> events) async {
    await batch((b) {
      b.insertAll(packetEvents, events);
    });
  }

  /// Get signal dots for a map viewport (bounding box query)
  Future<List<PacketEvent>> getEventsInBounds({
    required int coverageMapId,
    required double southLat,
    required double northLat,
    required double westLon,
    required double eastLon,
    String? directionFilter,
  }) {
    // Get all session IDs for this coverage map
    final sessionIdsQuery = selectOnly(sessions)
      ..addColumns([sessions.id])
      ..where(sessions.coverageMapId.equals(coverageMapId));

    final query = select(packetEvents)
      ..where((e) =>
          e.sessionId.isInQuery(sessionIdsQuery) &
          e.sourceKind.isIn(SourceKind.notSamples).not() &
          e.rxLat.isNotNull() &
          e.rxLon.isNotNull() &
          e.rxLat.isBiggerOrEqualValue(southLat) &
          e.rxLat.isSmallerOrEqualValue(northLat) &
          e.rxLon.isBiggerOrEqualValue(westLon) &
          e.rxLon.isSmallerOrEqualValue(eastLon));

    if (directionFilter != null) {
      query.where((e) => e.direction.equals(directionFilter));
    }

    return query.get();
  }

  /// Get all events for a session (for CSV export)
  ///
  /// Beacon misses (`telemetry_miss`, synthesised, no signal) and log-only
  /// packets (`log_only`, origin unknown) are left out unless
  /// [includeMisses]; only the full-data export wants them.
  Future<List<PacketEvent>> getEventsForSession(int sessionId,
          {bool includeMisses = false}) =>
      (select(packetEvents)
            ..where((e) =>
                e.sessionId.equals(sessionId) &
                (includeMisses
                    ? const Constant(true)
                    : e.sourceKind.isIn(SourceKind.notSamples).not()))
            ..orderBy([(e) => OrderingTerm.asc(e.timestamp)]))
          .get();

  // ─── Ping Correlation queries ────────────────────────

  /// Ping outcomes for a session, keyed by TX event id.
  Future<Map<int, PingCorrelation>> getPingsForSession(int sessionId) async {
    final query = select(pingCorrelations).join([
      innerJoin(
        packetEvents,
        packetEvents.id.equalsExp(pingCorrelations.txEventId),
      ),
    ])
      ..where(packetEvents.sessionId.equals(sessionId));
    final rows = await query.get();
    return {
      for (final row in rows)
        row.readTable(pingCorrelations).txEventId:
            row.readTable(pingCorrelations),
    };
  }

  Future<int> insertPingCorrelation(PingCorrelationsCompanion corr) =>
      into(pingCorrelations).insert(corr);

  Future<void> updatePingCorrelation({
    required int txEventId,
    required int? ackEventId,
    required int? roundTripMs,
    required String status,
  }) async {
    await (update(pingCorrelations)
          ..where((pc) => pc.txEventId.equals(txEventId)))
        .write(PingCorrelationsCompanion(
      ackEventId: Value(ackEventId),
      roundTripMs: Value(roundTripMs),
      ackStatus: Value(status),
    ));
  }

  Future<void> timeoutPendingPing(int txEventId) async {
    await (update(pingCorrelations)
          ..where((pc) => pc.txEventId.equals(txEventId)))
        .write(const PingCorrelationsCompanion(
      ackStatus: Value('timeout'),
    ));
  }
}

// ─── Guided test queries (schema v11) ────────────────────

/// Guided-test plans and their steps (`services/guided/plan_runner.dart`
/// is the only writer).
extension GuidedTestQueries on AppDatabase {
  Future<int> insertTestPlan(TestPlansCompanion plan) =>
      into(testPlans).insert(plan);

  Future<void> insertTestSteps(List<TestStepsCompanion> steps) =>
      batch((b) => b.insertAll(testSteps, steps));

  Future<TestPlan?> getTestPlan(int id) =>
      (select(testPlans)..where((p) => p.id.equals(id))).getSingleOrNull();

  Stream<TestPlan?> watchTestPlan(int id) =>
      (select(testPlans)..where((p) => p.id.equals(id))).watchSingleOrNull();

  Future<void> updateTestPlan(int id, TestPlansCompanion plan) =>
      (update(testPlans)..where((p) => p.id.equals(id))).write(plan);

  /// Plans of a map, newest first.
  Stream<List<TestPlan>> watchTestPlansForMap(int coverageMapId) =>
      (select(testPlans)
            ..where((p) => p.coverageMapId.equals(coverageMapId))
            ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
          .watch();

  /// Plans that are running or paused, newest first (normally one).
  Future<List<TestPlan>> getActiveTestPlans() => (select(testPlans)
        ..where((p) => p.status.isIn(const ['running', 'paused']))
        ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
      .get();

  /// The one plan that is running or paused, or null.
  Stream<TestPlan?> watchActiveTestPlan() => (select(testPlans)
        ..where((p) => p.status.isIn(const ['running', 'paused']))
        ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])
        ..limit(1))
      .watch()
      .map((rows) => rows.isEmpty ? null : rows.first);

  /// The steps of a plan in order.
  Future<List<TestStep>> getTestSteps(int planId) => (select(testSteps)
        ..where((t) => t.planId.equals(planId))
        ..orderBy([(t) => OrderingTerm.asc(t.ordinal)]))
      .get();

  Stream<List<TestStep>> watchTestSteps(int planId) => (select(testSteps)
        ..where((t) => t.planId.equals(planId))
        ..orderBy([(t) => OrderingTerm.asc(t.ordinal)]))
      .watch();

  Future<void> updateTestStep(int id, TestStepsCompanion step) =>
      (update(testSteps)..where((t) => t.id.equals(id))).write(step);

  /// Replace a plan's steps (drafts only: nothing has happened yet).
  Future<void> replaceTestSteps(int planId, List<TestStepsCompanion> steps) =>
      transaction(() async {
        await (delete(testSteps)..where((t) => t.planId.equals(planId))).go();
        await insertTestSteps(steps);
      });

  /// Record that [sessionId] is the walk of step [stepId], on both rows.
  Future<void> linkSessionToStep(int stepId, int sessionId) =>
      transaction(() async {
        await updateTestStep(
            stepId, TestStepsCompanion(sessionId: Value(sessionId)));
        await (update(sessions)..where((s) => s.id.equals(sessionId)))
            .write(SessionsCompanion(testStepId: Value(stepId)));
      });

  /// Forget the step's session (the session itself is kept).
  Future<void> unlinkStepSession(int stepId) => transaction(() async {
        await (update(sessions)..where((s) => s.testStepId.equals(stepId)))
            .write(const SessionsCompanion(testStepId: Value(null)));
        await updateTestStep(
            stepId, const TestStepsCompanion(sessionId: Value(null)));
      });

  /// Store the analysis and mark the plan done.
  Future<void> storeTestPlanResult(int planId, String resultJson) =>
      updateTestPlan(
          planId,
          TestPlansCompanion(
            resultJson: Value(resultJson),
            status: const Value('done'),
            finishedAt: Value(DateTime.now()),
          ));

  /// Delete a plan with its steps; its sessions stay on the map.
  Future<void> deleteTestPlan(int planId) => transaction(() async {
        await (update(sessions)..where((s) => s.testStepId.isInQuery(
                selectOnly(testSteps)
                  ..addColumns([testSteps.id])
                  ..where(testSteps.planId.equals(planId)))))
            .write(const SessionsCompanion(testStepId: Value(null)));
        await (delete(testSteps)..where((t) => t.planId.equals(planId))).go();
        await (delete(testPlans)..where((p) => p.id.equals(planId))).go();
      });
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    // Demo mode gets its own throwaway database, recreated each launch.
    final name =
        DemoMode.enabled ? 'mesh_analyzer_demo.sqlite' : 'mesh_analyzer.sqlite';
    final file = File(p.join(dbFolder.path, name));
    if (DemoMode.enabled && await file.exists()) await file.delete();
    return NativeDatabase.createInBackground(file);
  });
}

/// A ping's TX event plus its correlation row (ack status, round trip).
class PingResult {
  final PacketEvent tx;
  final PingCorrelation correlation;

  const PingResult({required this.tx, required this.correlation});
}

/// Beacons heard and missed in one session.
class BeaconStats {
  final int heard;
  final int missed;

  /// True when [missed] comes from sequence numbers; false when it is
  /// estimated from timing.
  final bool exact;

  const BeaconStats(this.heard, this.missed, {this.exact = false});

  static const none = BeaconStats(0, 0);

  /// From rows of (source kind, seq) in time order.
  factory BeaconStats.fromRows(Iterable<(String, int?)> rows) {
    var heard = 0, missed = 0, misses = 0;
    var sawSeq = false;
    int? last;
    for (final (kind, seq) in rows) {
      if (kind == SourceKind.telemetryMiss) {
        misses++;
        continue;
      }
      heard++;
      if (seq == null) continue;
      sawSeq = true;
      // A lower number means the base restarted its counter.
      if (last != null && seq > last + 1) missed += seq - last - 1;
      last = seq;
    }
    return sawSeq
        ? BeaconStats(heard, missed, exact: true)
        : BeaconStats(heard, misses);
  }
}
