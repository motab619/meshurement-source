// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:drift/drift.dart';

// ─── nodes ───────────────────────────────────────────────

class Nodes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get nodeId => integer().unique()();
  TextColumn get longName => text().withDefault(const Constant(''))();
  TextColumn get shortName => text().withDefault(const Constant(''))();
  TextColumn get userLabel => text().nullable()();
  TextColumn get hwModel => text().withDefault(const Constant(''))();
  DateTimeColumn get firstSeenAt => dateTime()();
  DateTimeColumn get lastHeardAt => dateTime()();
  RealColumn get lastLat => real().nullable()();
  RealColumn get lastLon => real().nullable()();
}

// ─── coverage_maps ───────────────────────────────────────

class CoverageMaps extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  /// Base radio of maps made before schema v8. A map is a place; the base
  /// radio belongs to each session (`Sessions.baseNodeId`), so new maps
  /// leave this null. Old sessions without their own base fall back to it.
  IntColumn get baseNodeId => integer().nullable().references(Nodes, #id)();

  /// Where the base stands for this map (schema v8). Null until known.
  RealColumn get baseLat => real().nullable()();
  RealColumn get baseLon => real().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get colorMetric =>
      text().withDefault(const Constant('snr'))(); // 'snr' or 'rssi'
  TextColumn get signalDirection =>
      text().withDefault(const Constant('rx'))(); // 'rx', 'tx', 'both'
}

// ─── rig_profiles ────────────────────────────────────────

/// Hardware setup (radio, antenna, cable) for a mobile or base node (v4).
class RigProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get role =>
      text().withDefault(const Constant('either'))(); // mobile/base/either
  TextColumn get radioModel => text().withDefault(const Constant(''))();
  TextColumn get antennaName => text().withDefault(const Constant(''))();
  RealColumn get antennaGainDbi => real().withDefault(const Constant(0))();
  TextColumn get cableType => text().withDefault(const Constant('none'))();
  RealColumn get cableLengthM => real().withDefault(const Constant(0))();
  IntColumn get connectorCount => integer().withDefault(const Constant(0))();
  RealColumn get connectorLossDb =>
      real().withDefault(const Constant(0.1))(); // per connector
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

// ─── sessions ────────────────────────────────────────────

class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get coverageMapId => integer().references(CoverageMaps, #id)();
  TextColumn get name => text().withDefault(const Constant(''))();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  IntColumn get remoteNodeId => integer().nullable().references(Nodes, #id)();

  /// The base radio this session pinged and listened for (schema v8).
  /// Null on sessions from before v8 whose map had no base; readers fall
  /// back to `CoverageMaps.baseNodeId`.
  IntColumn get baseNodeId => integer().nullable().references(Nodes, #id)();
  TextColumn get hwAntenna => text().withDefault(const Constant(''))();
  TextColumn get hwNodeModel => text().withDefault(const Constant(''))();
  TextColumn get hwNotes => text().withDefault(const Constant(''))();

  /// LoRa modem preset in use, e.g. "LONG_FAST" (schema v2).
  TextColumn get loraPreset => text().withDefault(const Constant(''))();

  /// Radio protocol the session was recorded with: "meshtastic" or
  /// "meshcore" (schema v5).
  TextColumn get protocol => text().withDefault(const Constant('meshtastic'))();
  IntColumn get pingIntervalSec => integer().withDefault(const Constant(0))();

  /// Estimated airtime of one ping in ms at session start (schema v3).
  RealColumn get packetAirtimeMs => real().withDefault(const Constant(0))();

  /// Rig used on the mobile / base radio (schema v4). Ids may dangle if a
  /// profile is ever removed; the JSON snapshots are the source of truth.
  IntColumn get mobileRigId => integer().nullable()();
  IntColumn get baseRigId => integer().nullable()();

  /// Rig as it was when the session started (`RigSpec.toJson`).
  TextColumn get mobileRigJson => text().nullable()();
  TextColumn get baseRigJson => text().nullable()();

  /// Highest air_util_tx (% of the last hour our radio transmitted) and
  /// channel utilization the radio reported during the session (schema v6).
  /// Null when it never reported.
  RealColumn get radioAirUtilTx => real().nullable()();
  RealColumn get radioChannelUtil => real().nullable()();

  /// Base beacon the session ran with: 'rangeTest', 'telemetry', 'trace'
  /// (MeshCore pulled beacon: the mobile's trace pings) or 'none' (schema
  /// v7). Empty on older sessions.
  TextColumn get beaconKind => text().withDefault(const Constant(''))();

  /// Beacon interval in seconds (schema v7); 0 when unknown or off.
  IntColumn get beaconIntervalSec => integer().withDefault(const Constant(0))();

  /// Radio settings beyond the preset at session start (schema v9), so a
  /// preset or antenna comparison isn't silently a frequency or power one.
  /// Null on older sessions and when the radio didn't say. Region code
  /// ("US"), effective 1-based frequency slot (null under a frequency
  /// override), transmit power, hop limit and centre frequency.
  TextColumn get region => text().nullable()();
  IntColumn get frequencySlot => integer().nullable()();
  IntColumn get txPowerDbm => integer().nullable()();
  IntColumn get hopLimit => integer().nullable()();
  RealColumn get frequencyMhz => real().nullable()();

  /// The guided-test step (`test_steps.id`) that recorded this session
  /// (schema v11); null for ordinary sessions. No foreign key: the steps
  /// table points back at sessions.
  IntColumn get testStepId => integer().nullable()();
  BoolColumn get rangeTestActive =>
      boolean().withDefault(const Constant(false))();
  IntColumn get packetCount => integer().withDefault(const Constant(0))();
}

// ─── packet_events ───────────────────────────────────────

@DataClassName('PacketEvent')
class PacketEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(Sessions, #id)();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get direction => text()(); // 'rx', 'tx', 'ack'
  IntColumn get sourceNodeId => integer().references(Nodes, #id)();
  RealColumn get rxSnr => real().nullable()();
  IntColumn get rxRssi => integer().nullable()();
  IntColumn get hopCount => integer().withDefault(const Constant(0))();
  RealColumn get rxLat => real().nullable()();
  RealColumn get rxLon => real().nullable()();
  RealColumn get rxAlt => real().nullable()();
  RealColumn get gpsAccuracy => real().nullable()();
  TextColumn get packetType => text()();
  IntColumn get meshPacketId => integer().nullable()();
  IntColumn get channelIndex => integer().withDefault(const Constant(0))();
  BoolColumn get viaMqtt => boolean().withDefault(const Constant(false))();

  /// Beacon sequence number (Range Test `seq N`); null for anything else
  /// (schema v7).
  IntColumn get seq => integer().nullable()();

  /// What produced the row (schema v7): `range_test | telemetry | position |
  /// ack | traceroute | passive | telemetry_miss | log_only`. Rows from
  /// before v7 and ordinary non-beacon packets are `passive`; `log_only`
  /// rows (schema v10) are packets whose over-the-air origin is unknown,
  /// kept for the log but never a coverage sample (`SourceKind.notSamples`).
  TextColumn get sourceKind => text().withDefault(const Constant('passive'))();

  /// The sender's own channel utilisation (%) from a telemetry beacon:
  /// busy/noise context at the base end (schema v7).
  RealColumn get baseChannelUtil => real().nullable()();

  /// How well the base heard our ping (mobile → base, dB), on ping reply
  /// rows when the protocol reports it (MeshCore trace hop SNR). Null
  /// otherwise (schema v10).
  RealColumn get uplinkSnr => real().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [];

  // Custom indexes are defined in the database class
}

// ─── ping_correlations ───────────────────────────────────

class PingCorrelations extends Table {
  IntColumn get id => integer().autoIncrement()();
  @ReferenceName('pingCorrelationsTx')
  IntColumn get txEventId => integer().references(PacketEvents, #id)();
  @ReferenceName('pingCorrelationsAck')
  IntColumn get ackEventId =>
      integer().nullable().references(PacketEvents, #id)();
  IntColumn get roundTripMs => integer().nullable()();
  TextColumn get ackStatus => text().withDefault(const Constant('timeout'))();
}

// ─── test_plans ──────────────────────────────────────────

/// A guided test (schema v11, `docs/design/guided-test/`): what the person
/// wanted to find out, as a stored plan. A child of a coverage map.
class TestPlans extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get coverageMapId => integer().references(CoverageMaps, #id)();
  TextColumn get title => text()();

  /// `PlanTemplate.name`.
  TextColumn get template => text()();

  /// `PlanIntent.toJson()`.
  TextColumn get intentJson => text()();

  /// `PlanStatus.name`: draft | running | paused | done | abandoned.
  TextColumn get status => text().withDefault(const Constant('draft'))();

  /// Ordinal of the current step while running or paused.
  IntColumn get currentStep => integer().withDefault(const Constant(0))();

  /// The base is changed from a distance (Meshtastic remote admin) rather
  /// than by walking to it.
  BoolColumn get remoteChanges =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  /// `PlanAnalysisResult.toJson()` once analysed.
  TextColumn get resultJson => text().nullable()();

  /// Cached AI narrative, so reopening does not re-bill.
  TextColumn get aiResultJson => text().nullable()();
}

// ─── test_steps ──────────────────────────────────────────

/// One stop on a plan's track, plus what happened to it.
class TestSteps extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get planId => integer().references(TestPlans, #id)();
  IntColumn get ordinal => integer()();

  /// `StepKind.name`.
  TextColumn get kind => text()();

  /// Index into the intent's variants; null for preflight/goTo/analyze.
  IntColumn get variant => integer().nullable()();
  TextColumn get title => text()();
  TextColumn get instruction => text()();
  TextColumn get summary => text().withDefault(const Constant(''))();
  TextColumn get paramsJson => text().withDefault(const Constant('{}'))();

  /// `StepStatus.name`: todo | active | done | skipped.
  TextColumn get status => text().withDefault(const Constant('todo'))();

  /// The session a `walk` step recorded.
  IntColumn get sessionId => integer().nullable().references(Sessions, #id)();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
}
