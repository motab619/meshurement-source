// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:csv/csv.dart';

import '../rig_math.dart';
import '../track_distance.dart';
import 'export_data.dart';

/// One column of the analysis export: header name plus how to read it from
/// an event. The same list feeds CSV, GeoJSON properties and KML
/// ExtendedData, so the formats never drift apart.
class ExportColumn {
  final String name;
  final Object? Function(SessionExport s, ExportEvent e) value;
  const ExportColumn(this.name, this.value);
}

/// `!` + 8 lowercase hex digits, e.g. `!0000a1b2` (Meshtastic node id form).
String nodeIdHex(int nodeNum) =>
    '!${(nodeNum & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')}';

/// ISO 8601 local time with numeric offset, e.g. `2026-10-17T07:03:22-07:00`.
String isoWithOffset(DateTime t) {
  final local = t.toLocal();
  final off = local.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final a = off.abs();
  String two(int n) => n.toString().padLeft(2, '0');
  final base = local.toIso8601String().split('.').first;
  return '$base$sign${two(a.inHours)}:${two(a.inMinutes % 60)}';
}

double? _r(double? v, int dp) =>
    v == null ? null : double.parse(v.toStringAsFixed(dp));

/// Track length of a session, computed once per export (session-level
/// value repeated on every row, like `packet_airtime_ms`).
final _distanceCache = Expando<double>('session_distance_m');
int sessionDistanceM(SessionExport s) =>
    (_distanceCache[s] ??= trackDistanceM([for (final e in s.events) e.event]))
        .round();

/// Columns of the CSV v2 export (one row per packet event).
///
/// Times: `timestamp_utc` is ISO 8601 with `Z`, `timestamp_local` carries the
/// phone's offset, `unix_ms` is epoch milliseconds (the database stores whole
/// seconds). Node: `source_node_id` is `!` + 8 lowercase hex digits,
/// `source_node_num` the same number in decimal; names are included for
/// reading only. `ping_status` / `round_trip_ms` are filled on the TX event
/// of a ping. Positions are WGS84, 7 decimals. Empty = not recorded.
///
/// Append new columns at the end only (existing scripts index by name, but
/// spreadsheets by position).
final List<ExportColumn> csvV2Columns = [
  ExportColumn('event_id', (s, e) => e.event.id),
  ExportColumn('session_id', (s, e) => s.session.id),
  ExportColumn(
      'session_name',
      (s, e) =>
          s.session.name.isEmpty ? 'Session ${s.session.id}' : s.session.name),
  ExportColumn('map_id', (s, e) => s.session.coverageMapId),
  ExportColumn('map_name', (s, e) => s.mapName),
  ExportColumn(
      'timestamp_utc', (s, e) => e.event.timestamp.toUtc().toIso8601String()),
  ExportColumn('timestamp_local', (s, e) => isoWithOffset(e.event.timestamp)),
  ExportColumn('unix_ms', (s, e) => e.event.timestamp.millisecondsSinceEpoch),
  ExportColumn('direction', (s, e) => e.event.direction),
  ExportColumn('packet_type', (s, e) => e.event.packetType),
  ExportColumn('mesh_packet_id', (s, e) => e.event.meshPacketId),
  ExportColumn('source_node_id',
      (s, e) => e.node == null ? null : nodeIdHex(e.node!.nodeId)),
  ExportColumn('source_node_num', (s, e) => e.node?.nodeId),
  ExportColumn('source_long_name', (s, e) => e.node?.longName),
  ExportColumn('source_short_name', (s, e) => e.node?.shortName),
  ExportColumn('rx_lat', (s, e) => _r(e.event.rxLat, 7)),
  ExportColumn('rx_lon', (s, e) => _r(e.event.rxLon, 7)),
  ExportColumn('rx_alt', (s, e) => _r(e.event.rxAlt, 1)),
  ExportColumn('gps_accuracy', (s, e) => _r(e.event.gpsAccuracy, 1)),
  ExportColumn('rx_snr', (s, e) => _r(e.event.rxSnr, 2)),
  ExportColumn('rx_rssi', (s, e) => e.event.rxRssi),
  ExportColumn('hop_count', (s, e) => e.event.hopCount),
  ExportColumn('via_mqtt', (s, e) => e.event.viaMqtt),
  ExportColumn('channel_index', (s, e) => e.event.channelIndex),
  ExportColumn('ping_status', (s, e) => e.ping?.ackStatus),
  ExportColumn('round_trip_ms', (s, e) => e.ping?.roundTripMs),
  ExportColumn('lora_preset', (s, e) => s.session.loraPreset),
  ExportColumn('packet_airtime_ms', (s, e) => _r(s.session.packetAirtimeMs, 1)),
  ExportColumn('ping_interval_sec', (s, e) => s.session.pingIntervalSec),
  ExportColumn(
      'mobile_rig', (s, e) => RigSpec.decode(s.session.mobileRigJson)?.name),
  ExportColumn('mobile_net_gain_db',
      (s, e) => _r(RigSpec.decode(s.session.mobileRigJson)?.netGainDb, 1)),
  ExportColumn(
      'base_rig', (s, e) => RigSpec.decode(s.session.baseRigJson)?.name),
  ExportColumn('base_net_gain_db',
      (s, e) => _r(RigSpec.decode(s.session.baseRigJson)?.netGainDb, 1)),
  ExportColumn('protocol', (s, e) => s.session.protocol),
  ExportColumn(
      'radio_air_util_tx_pct', (s, e) => _r(s.session.radioAirUtilTx, 2)),
  ExportColumn(
      'radio_channel_util_pct', (s, e) => _r(s.session.radioChannelUtil, 2)),
  // Beacon columns (schema v7). `source_kind` tells beacon samples
  // (range_test, telemetry) from ACKs and passive packets; telemetry_miss
  // rows are beacons the mobile should have heard but did not (no signal,
  // position interpolated by time); log_only rows are packets whose
  // over-the-air origin is unknown (signal of an unknown relay).
  ExportColumn('seq', (s, e) => e.event.seq),
  ExportColumn('source_kind', (s, e) => e.event.sourceKind),
  ExportColumn('base_channel_util', (s, e) => _r(e.event.baseChannelUtil, 2)),
  ExportColumn('beacon_kind', (s, e) => s.session.beaconKind),
  ExportColumn('beacon_interval_sec', (s, e) => s.session.beaconIntervalSec),
  // Distance travelled during the session (metres, whole), from the GPS
  // fixes of its events: a mileage log for test drives. Session-level,
  // repeated per row.
  ExportColumn('session_distance_m', (s, e) => sessionDistanceM(s)),
  // Radio settings beyond the preset at session start (schema v9): region
  // code, 1-based frequency slot (empty under a frequency override), centre
  // frequency, transmit power and hop limit. Session-level, repeated.
  ExportColumn('session_region', (s, e) => s.session.region),
  ExportColumn('session_frequency_slot', (s, e) => s.session.frequencySlot),
  ExportColumn(
      'session_frequency_mhz', (s, e) => _r(s.session.frequencyMhz, 3)),
  ExportColumn('session_tx_power_dbm', (s, e) => s.session.txPowerDbm),
  ExportColumn('session_hop_limit', (s, e) => s.session.hopLimit),
  // How well the base heard our ping (mobile → base, dB) on ping reply
  // rows, when the protocol reports it (MeshCore trace; schema v10).
  ExportColumn('uplink_snr', (s, e) => _r(e.event.uplinkSnr, 2)),
];

/// The CSV v2 header names, in order.
List<String> get csvV2Header => [for (final c in csvV2Columns) c.name];

/// Property map (header name to typed value) for one event.
Map<String, Object?> eventProperties(SessionExport s, ExportEvent e) =>
    {for (final c in csvV2Columns) c.name: c.value(s, e)};

/// Neutralise spreadsheet formulas: a text cell starting with `= + - @` or a
/// control character gets a leading apostrophe. Applied to text only, so
/// negative numbers stay numbers.
String csvSafeText(String s) {
  if (s.isEmpty) return s;
  const risky = ['=', '+', '-', '@', '\t', '\r'];
  return risky.contains(s[0]) ? "'$s" : s;
}

Object _cell(Object? v) {
  if (v == null) return '';
  if (v is bool) return v ? 'true' : 'false';
  if (v is String) return csvSafeText(v);
  return v;
}

/// CSV v2 for the given sessions (one header, rows in session order).
String buildCsvV2(Iterable<SessionExport> sessions) {
  final rows = <List<Object>>[csvV2Header];
  for (final s in sessions) {
    for (final e in s.events) {
      rows.add([for (final c in csvV2Columns) _cell(c.value(s, e))]);
    }
  }
  return const ListToCsvConverter().convert(rows);
}
