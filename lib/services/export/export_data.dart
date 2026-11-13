// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import '../../data/database/app_database.dart';
import '../../utils/constants.dart';

/// One packet event with the node and ping outcome it belongs to.
class ExportEvent {
  final PacketEvent event;
  final Node? node;

  /// Ping outcome; only set on the TX event of a ping.
  final PingCorrelation? ping;

  const ExportEvent(this.event, this.node, this.ping);

  /// A synthesised beacon miss (no signal). Only the full-data CSV keeps
  /// these; maps and the firmware layout leave them out.
  bool get isMiss => event.sourceKind == SourceKind.telemetryMiss;

  /// Kept for the log only (origin unknown, `SourceKind.logOnly`): like a
  /// miss, only the full-data CSV lists it.
  bool get isLogOnly => event.sourceKind == SourceKind.logOnly;

  bool get hasPosition => event.rxLat != null && event.rxLon != null;
}

/// Everything the exporters need for one session, loaded once.
class SessionExport {
  final Session session;
  final CoverageMap? map;
  final List<ExportEvent> events;

  /// The session's base radio (its map's for sessions from before schema
  /// v8); null when unknown.
  final Node? baseNode;

  const SessionExport(this.session, this.map, this.events, {this.baseNode});

  /// [events] without beacon misses and log-only packets: samples only.
  Iterable<ExportEvent> get heardEvents =>
      events.where((e) => !e.isMiss && !e.isLogOnly);

  String get mapName => map?.name ?? '';
}

/// A coverage map with its sessions.
class MapExport {
  final CoverageMap map;

  /// Base radio of the newest session (the map's own for maps from before
  /// schema v8). Each session's is on [SessionExport.baseNode].
  final Node? baseNode;
  final List<SessionExport> sessions;

  const MapExport(this.map, this.baseNode, this.sessions);
}

/// Loads export data from the database.
class ExportLoader {
  final AppDatabase _db;
  ExportLoader(this._db);

  Future<SessionExport?> session(
    int sessionId, {
    Map<int, Node>? nodes,
    Map<int, CoverageMap>? maps,
  }) async {
    final s = await _db.getSessionById(sessionId);
    if (s == null) return null;
    nodes ??= {for (final n in await _db.getAllNodes()) n.id: n};
    maps ??= {for (final m in await _db.getAllCoverageMaps()) m.id: m};
    final events =
        await _db.getEventsForSession(sessionId, includeMisses: true);
    final pings = await _db.getPingsForSession(sessionId);
    final baseId = s.baseNodeId ?? maps[s.coverageMapId]?.baseNodeId;
    return SessionExport(
      s,
      maps[s.coverageMapId],
      [
        for (final e in events)
          ExportEvent(e, nodes[e.sourceNodeId], pings[e.id]),
      ],
      baseNode: nodes[baseId],
    );
  }

  Future<MapExport?> map(int mapId) async {
    final nodes = {for (final n in await _db.getAllNodes()) n.id: n};
    final maps = {for (final m in await _db.getAllCoverageMaps()) m.id: m};
    final m = maps[mapId];
    if (m == null) return null;
    final sessions = await _db.getSessionsForMap(mapId);
    final baseId = await _db.latestBaseNodeIdForMap(mapId);
    return MapExport(m, nodes[baseId], [
      for (final s in sessions)
        if (await session(s.id, nodes: nodes, maps: maps) case final x?) x,
    ]);
  }

  Future<List<MapExport>> allMaps() async {
    final out = <MapExport>[];
    for (final m in await _db.getAllCoverageMaps()) {
      final x = await map(m.id);
      if (x != null) out.add(x);
    }
    return out;
  }
}
