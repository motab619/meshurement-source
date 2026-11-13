// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:async';

import 'package:drift/drift.dart';

import '../data/database/app_database.dart';
import '../data/radio/mesh_radio.dart';
import '../models/processed_signal_event.dart';
import '../utils/constants.dart';
import 'beacon_tracker.dart';
import 'gps_service.dart';
import 'other_radio_monitor.dart';
import 'rig_math.dart';
import 'out_of_range_monitor.dart';
import 'range_test_detector.dart';
import 'diag_log.dart';

/// Central orchestrator: subscribes to the radio's packet stream,
/// processes each packet, writes to DB, and emits to UI.
class PacketProcessor {
  /// Replayed/old packets ignored this run (see `_onPacketReceived`).
  int _staleDropped = 0;
  int get staleDropped => _staleDropped;

  final AppDatabase _db;
  final MeshRadio _radio;
  final GpsService _gps;
  final RangeTestDetector _rangeTestDetector;
  final OutOfRangeMonitor _outOfRangeMonitor;

  StreamSubscription<ReceivedPacket>? _packetSubscription;
  StreamSubscription<RadioNode>? _nodeSubscription;
  final StreamController<ProcessedSignalEvent> _signalController =
      StreamController<ProcessedSignalEvent>.broadcast();

  /// The active session ID. Set by SessionManager.
  int? activeSessionId;

  /// Cache of known node IDs (mesh node ID → local DB id)
  final Map<int, int> _nodeCache = {};

  /// Lookups/creations in flight, so two packets from a new node arriving
  /// together don't both try to insert it (the second would be dropped).
  final Map<int, Future<int>> _nodeLookups = {};

  /// Follows the base's beacon while a session records (see
  /// [startBeaconTracking]).
  final BeaconTracker beacons;
  Timer? _beaconTimer;

  /// Notices radios other than the base (and ours) while a session
  /// records; started and stopped by SessionManager.
  final OtherRadioMonitor otherRadios;

  /// Callback for when a new node is auto-detected
  void Function(int meshNodeId, String longName)? onNewNodeDetected;

  /// Whether relayed packets (hops > 0) are measurements (Settings →
  /// "Count relayed packets"). Default: no — see [AppConstants.countRelayedPackets].
  final bool Function() _countRelayed;

  /// `nodes.last_heard_at` is written about once per node per
  /// [lastHeardWriteInterval] at most: each write re-runs every node-list query
  /// (and rebuilds the screens watching it), and packets arrive every few
  /// seconds while a session records. A heard time held back is written
  /// when the interval is up, at [flushLastHeard] (session end) or [stop].
  static const lastHeardWriteInterval = Duration(seconds: 30);
  final Map<int, DateTime> _lastHeardWritten = {};
  final Map<int, DateTime> _lastHeardPending = {};
  Timer? _lastHeardTimer;
  final DateTime Function() _now;

  /// Relayed packets ignored this run.
  int _relayedDropped = 0;
  int get relayedDropped => _relayedDropped;

  PacketProcessor({
    required AppDatabase db,
    required MeshRadio radio,
    required GpsService gps,
    required RangeTestDetector rangeTestDetector,
    required OutOfRangeMonitor outOfRangeMonitor,
    bool Function()? countRelayed,
    BeaconTracker? beacons,
    OtherRadioMonitor? otherRadios,
    DateTime Function()? clock,
  })  : _now = clock ?? DateTime.now,
        beacons = beacons ?? BeaconTracker(),
        otherRadios = otherRadios ?? OtherRadioMonitor(),
        _db = db,
        _radio = radio,
        _gps = gps,
        _rangeTestDetector = rangeTestDetector,
        _outOfRangeMonitor = outOfRangeMonitor,
        _countRelayed = countRelayed ?? (() => false);

  /// Stream of processed signal events for the UI
  Stream<ProcessedSignalEvent> get signalStream => _signalController.stream;

  bool get isRunning => _packetSubscription != null;

  /// Start listening to the radio. The radio's streams survive reconnects,
  /// so this only needs to be called once.
  void start() {
    if (isRunning) return;
    _packetSubscription = _radio.packets.listen(
      _onPacketReceived,
      onError: (error) {
        print('PacketProcessor error: $error');
      },
    );
    _nodeSubscription = _radio.nodeUpdates.listen(_onNodeInfo);
  }

  /// Forget cached node ids (after nodes were deleted from the DB).
  void clearNodeCache() => _nodeCache.clear();

  /// Follow [baseNodeId]'s beacon for the active session: count what is
  /// heard, write a `telemetry_miss` row for each telemetry beacon that
  /// should have arrived and didn't, and notice when the beacon is off.
  /// [kind] none means unknown; the first beacon heard decides.
  void startBeaconTracking({
    required int baseNodeId,
    required BeaconKind kind,
    required int intervalSec,
  }) {
    beacons.start(baseNodeId: baseNodeId, kind: kind, intervalSec: intervalSec);
    _beaconLinkDown = false;
    _beaconTimer?.cancel();
    _beaconTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => tickBeacons(DateTime.now()));
  }

  void stopBeaconTracking() {
    _beaconTimer?.cancel();
    _beaconTimer = null;
    beacons.stop();
  }

  /// Set while the phone's link to its radio is down, so the beacon
  /// schedule is moved past the outage when it comes back.
  bool _beaconLinkDown = false;

  /// Write the telemetry beacons missed as of [now]. Only while the phone's
  /// link to the mobile radio is up (otherwise we couldn't have heard them)
  /// and a session records. Beacons sent during an outage are neither heard
  /// nor missed: their slots are skipped, not made up afterwards.
  Future<void> tickBeacons(DateTime now) async {
    final sessionId = activeSessionId;
    final baseId = beacons.baseNodeId;
    if (sessionId == null || baseId == null) return;
    if (!_radio.isReady) {
      beacons.skipSlots(now);
      _beaconLinkDown = true;
      return;
    }
    if (_beaconLinkDown) {
      beacons.skipSlots(now);
      _beaconLinkDown = false;
    }
    final slots = beacons.dueMisses(now);
    if (slots.isEmpty) return;
    try {
      final localId = await _ensureNodeExists(baseId);
      final here = _gps.lastPosition;
      for (final slot in slots) {
        final (lat, lon) =
            beacons.positionAt(slot, now, here?.latitude, here?.longitude);
        await _db.insertPacketEvent(PacketEventsCompanion.insert(
          sessionId: sessionId,
          timestamp: slot,
          direction: PacketDirection.rx,
          sourceNodeId: localId,
          packetType: PacketType.telemetry,
          sourceKind: const Value(SourceKind.telemetryMiss),
          rxLat: Value(lat),
          rxLon: Value(lon),
        ));
      }
    } catch (e) {
      print('Error recording missed beacons: $e');
    }
  }

  void stop() {
    _packetSubscription?.cancel();
    _packetSubscription = null;
    _nodeSubscription?.cancel();
    _nodeSubscription = null;
    unawaited(flushLastHeard().catchError((Object e) {
      print('PacketProcessor: last heard not saved: $e');
    }));
  }

  /// Record that [meshNodeId] was heard now, throttled (see
  /// [lastHeardWriteInterval]).
  Future<void> _noteLastHeard(int meshNodeId) async {
    final now = _now();
    final written = _lastHeardWritten[meshNodeId];
    if (written == null || now.difference(written) >= lastHeardWriteInterval) {
      _lastHeardWritten[meshNodeId] = now;
      _lastHeardPending.remove(meshNodeId);
      await _db.updateNodeLastHeard(meshNodeId, at: now);
      return;
    }
    _lastHeardPending[meshNodeId] = now;
    _lastHeardTimer ??=
        Timer(lastHeardWriteInterval - now.difference(written), () {
      _lastHeardTimer = null;
      unawaited(flushLastHeard().catchError((Object e) {
        print('PacketProcessor: last heard not saved: $e');
      }));
    });
  }

  /// Write every heard time held back by the throttle.
  Future<void> flushLastHeard() async {
    _lastHeardTimer?.cancel();
    _lastHeardTimer = null;
    if (_lastHeardPending.isEmpty) return;
    final pending = Map.of(_lastHeardPending);
    _lastHeardPending.clear();
    for (final e in pending.entries) {
      _lastHeardWritten[e.key] = e.value;
      await _db.updateNodeLastHeard(e.key, at: e.value);
    }
  }

  /// Keep names/hardware of nodes already in the DB current.
  Future<void> _onNodeInfo(RadioNode info) async {
    // Remember where the node is (used as the base location for terrain
    // profiles). Only accepts a plausible fix; 0,0 means "no position".
    if (info.hasPosition) {
      try {
        await _db.updateNodePosition(
          info.num,
          info.latitude!,
          info.longitude!,
        );
      } catch (e) {
        print('Error updating node position: $e');
      }
    }
    if (!info.hasUser) return;
    try {
      await _db.updateNodeIdentity(
        nodeId: info.num,
        longName: info.longName,
        shortName: info.shortName,
        hwModel: info.hwModel,
      );
    } catch (e) {
      print('Error updating node info: $e');
    }
  }

  Future<void> _onPacketReceived(ReceivedPacket packet) async {
    try {
      final int fromNode = packet.from;

      // Our own radio's packets (e.g. locally generated NAKs) carry no
      // over-the-air signal data; the radio already leaves them out.
      if (fromNode == 0 || fromNode == _radio.myNodeId) return;

      // Replayed from the radio's buffer, or old by the radio's clock: the
      // phone wasn't necessarily here when it was heard, so it must not
      // become a dot, a reading or proof the base is in range now.
      if (packet.isStale(DateTime.now())) {
        _staleDropped++;
        if (_staleDropped == 1 || _staleDropped % 25 == 0) {
          DiagLog.instance.log('packets',
              'dropped $_staleDropped stale/replayed packet(s) so far');
        }
        return;
      }

      // A radio that is neither the base nor ours (a second base left on)
      // is flagged live, before the relay filter: a relayed answer from it
      // is exactly the case that spoiled a lap on 2026-10-26.
      final stranger = otherRadios.classify(
        from: fromNode,
        type: packet.type,
        channelIndex: packet.channelIndex,
        decoded: packet.type != PacketType.other || packet.payload.isNotEmpty,
        myNodeId: _radio.myNodeId,
      );
      if (stranger != null) {
        otherRadios.notice(
          nodeId: fromNode,
          name: await _nodeLabel(fromNode),
          hwModel: await _nodeHw(fromNode),
          reason: stranger,
          hops: packet.hops,
        );
      }

      // Travelled distance unknown (a MeshCore direct packet still on its
      // way along a path): its signal is an unknown relay's, so it is kept
      // for the log only. Not a sample, not a dot, not proof the base is
      // in range, never a beacon.
      if (!packet.hopsKnown) {
        await _logOnly(packet);
        return;
      }

      // A relayed copy says nothing about the base's own link (the signal
      // is the relay's) and would keep a dead spot "in range", so by
      // default it is neither recorded nor counted as hearing the base.
      if (packet.hops > 0 && !_countRelayed()) {
        _relayedDropped++;
        if (_relayedDropped == 1 || _relayedDropped % 25 == 0) {
          DiagLog.instance.log('packets',
              'ignored $_relayedDropped relayed packet(s) so far (hops > 0)');
        }
        return;
      }

      // Anything heard from the base proves it is in range, whatever
      // happens to the packet below (ACKs, unanswered Range Test prompts).
      _outOfRangeMonitor.onPacketReceived(fromNode);
      final isBase = beacons.active && fromNode == beacons.baseNodeId;
      if (isBase && packet.hops == 0) beacons.onBaseHeard(DateTime.now());

      final double? rxSnr = packet.snr;
      final int? rxRssi = packet.rssi;
      final int hopCount = packet.hops;
      final int meshPacketId = packet.packetId;
      final bool viaMqtt = packet.viaMqtt;
      final int channelIndex = packet.channelIndex;

      // ACK/NAK replies are recorded by ActiveProbeService (as 'ack'
      // events with their signal); logging them here too would count
      // each reply twice.
      if (packet.type == PacketType.ack) return;

      final String packetType = packet.type;

      // Auto-detect new nodes
      final int localNodeId = await _ensureNodeExists(fromNode);

      // Not awaited: whether this packet's time is written or held back
      // must not change how far it gets before the next packet.
      unawaited(_noteLastHeard(fromNode).catchError((Object e) {
        print('PacketProcessor: last heard not saved: $e');
      }));

      // Range Test beacons: only judged while a session records (no
      // prompt while idle). Recorded unless the user said no for this node.
      final sessionId = activeSessionId;
      if (packet.type == PacketType.rangeTest && sessionId != null) {
        if (!_rangeTestDetector.shouldLogRangeTest(fromNode)) return;
        await _db.markSessionRangeTestActive(sessionId);
      }

      // Get current GPS position
      final position = _gps.lastPosition;

      // What kind of row this is. A beacon sample is the base's own
      // broadcast heard directly (hops == 0): a relayed copy carries the
      // relay's signal, not the base's.
      var sourceKind = SourceKind.passive;
      final int? beaconSeq = packet.beaconSeq;
      double? baseChannelUtil;
      BeaconKind? beaconHeard;
      if (packet.type == PacketType.rangeTest) {
        sourceKind = SourceKind.rangeTest;
        if (isBase &&
            packet.hops == 0 &&
            beacons.accepts(BeaconKind.rangeTest)) {
          beaconHeard = BeaconKind.rangeTest;
        }
      } else if (packet.type == PacketType.telemetry &&
          isBase &&
          packet.hops == 0 &&
          packet.senderChannelUtil != null &&
          beacons.accepts(BeaconKind.telemetry)) {
        sourceKind = SourceKind.telemetry;
        baseChannelUtil = packet.senderChannelUtil;
        beaconHeard = BeaconKind.telemetry;
      }
      if (beaconHeard != null && sessionId != null) {
        final learned = beacons.kind == BeaconKind.none;
        beacons.onBeacon(beaconHeard, DateTime.now(),
            seq: beaconSeq, lat: position?.latitude, lon: position?.longitude);
        final interval = beacons.takeLearnedInterval();
        if (learned || interval != null) {
          await _db.updateSessionBeacon(sessionId,
              kind: beacons.kind.dbValue, intervalSec: interval);
        }
      }

      // Build the processed event
      final event = ProcessedSignalEvent(
        timestamp: DateTime.now(),
        sourceNodeId: fromNode,
        sourceNodeName: await _getNodeName(fromNode),
        rxSnr: rxSnr,
        rxRssi: rxRssi,
        hopCount: hopCount,
        latitude: position?.latitude,
        longitude: position?.longitude,
        altitude: position?.altitude,
        gpsAccuracy: position?.accuracy,
        packetType: packetType,
        direction: PacketDirection.rx,
        meshPacketId: meshPacketId,
        viaMqtt: viaMqtt,
      );

      // Write to DB if session is active
      if (activeSessionId != null) {
        await _db.insertPacketEvent(PacketEventsCompanion.insert(
          sessionId: activeSessionId!,
          timestamp: event.timestamp,
          direction: event.direction,
          sourceNodeId: localNodeId,
          rxSnr: Value(event.rxSnr),
          rxRssi: Value(event.rxRssi),
          hopCount: Value(event.hopCount),
          rxLat: Value(event.latitude),
          rxLon: Value(event.longitude),
          rxAlt: Value(event.altitude),
          gpsAccuracy: Value(event.gpsAccuracy),
          packetType: event.packetType,
          meshPacketId: Value(event.meshPacketId),
          channelIndex: Value(channelIndex),
          viaMqtt: Value(viaMqtt),
          seq: Value(beaconSeq),
          sourceKind: Value(sourceKind),
          baseChannelUtil: Value(baseChannelUtil),
        ));
      }

      // Emit to UI
      _signalController.add(event);
    } catch (e) {
      print('Error processing packet: $e');
    }
  }

  /// Store [packet] as a `log_only` row (see [SourceKind.logOnly]) while a
  /// session records; nothing is emitted to the UI.
  Future<void> _logOnly(ReceivedPacket packet) async {
    final sessionId = activeSessionId;
    if (sessionId == null) return;
    final localNodeId = await _ensureNodeExists(packet.from);
    final position = _gps.lastPosition;
    await _db.insertPacketEvent(PacketEventsCompanion.insert(
      sessionId: sessionId,
      timestamp: DateTime.now(),
      direction: PacketDirection.rx,
      sourceNodeId: localNodeId,
      rxSnr: Value(packet.snr),
      rxRssi: Value(packet.rssi),
      // Hops travelled are unknown; 0 here means nothing (source_kind says
      // so).
      hopCount: const Value(0),
      rxLat: Value(position?.latitude),
      rxLon: Value(position?.longitude),
      rxAlt: Value(position?.altitude),
      gpsAccuracy: Value(position?.accuracy),
      packetType: packet.type,
      meshPacketId: Value(packet.packetId),
      channelIndex: Value(packet.channelIndex),
      viaMqtt: Value(packet.viaMqtt),
      sourceKind: const Value(SourceKind.logOnly),
    ));
  }

  /// Ensure a node exists in the DB, auto-creating if needed.
  /// Returns the local DB id.
  Future<int> _ensureNodeExists(int meshNodeId) async {
    if (_nodeCache.containsKey(meshNodeId)) {
      return _nodeCache[meshNodeId]!;
    }
    // (Block body: returning the removed future would make it wait on
    // itself.)
    return _nodeLookups[meshNodeId] ??=
        _lookUpOrCreateNode(meshNodeId).whenComplete(() {
      _nodeLookups.remove(meshNodeId);
    });
  }

  Future<int> _lookUpOrCreateNode(int meshNodeId) async {
    final existing = await _db.getNodeByMeshId(meshNodeId);
    if (existing != null) {
      _nodeCache[meshNodeId] = existing.id;
      return existing.id;
    }

    // Auto-create the node, named from the radio's node DB if known
    final node = _radio.nodes[meshNodeId];
    final longName = node?.longName ?? '';

    final localId = await _db.upsertNode(
      nodeId: meshNodeId,
      longName: longName,
      shortName: node?.shortName ?? '',
      hwModel: node?.hwModel ?? '',
    );

    _nodeCache[meshNodeId] = localId;
    onNewNodeDetected?.call(meshNodeId, longName);
    return localId;
  }

  Future<String> _getNodeName(int meshNodeId) async {
    final node = await _db.getNodeByMeshId(meshNodeId);
    if (node != null) {
      if (node.userLabel != null && node.userLabel!.isNotEmpty) {
        return node.userLabel!;
      }
      if (node.longName.isNotEmpty) return node.longName;
      if (node.shortName.isNotEmpty) return node.shortName;
    }
    return '0x${meshNodeId.toRadixString(16)}';
  }

  /// How the user knows a node: their label, else the radio's long or
  /// short name (from the DB, then the radio's node list), else `!hex`.
  /// Readable hardware model of a node, from the radio or the app's DB;
  /// empty when unknown.
  Future<String> _nodeHw(int meshNodeId) async {
    final live = _radio.nodes[meshNodeId]?.hwModel ?? '';
    if (live.isNotEmpty) return radioModelName(live);
    return radioModelName(
        (await _db.getNodeByMeshId(meshNodeId))?.hwModel ?? '');
  }

  Future<String> _nodeLabel(int meshNodeId) async {
    final node = await _db.getNodeByMeshId(meshNodeId);
    final radioNode = _radio.nodes[meshNodeId];
    for (final name in [
      node?.userLabel,
      node?.longName,
      node?.shortName,
      radioNode?.longName,
      radioNode?.shortName,
    ]) {
      if (name != null && name.isNotEmpty) return name;
    }
    // The full node id, as other mesh apps show it (diagNode is the short
    // log form).
    return '!${meshNodeId.toRadixString(16).padLeft(8, '0')}';
  }

  void dispose() {
    stopBeaconTracking();
    beacons.dispose();
    otherRadios.dispose();
    stop();
    _signalController.close();
  }
}
