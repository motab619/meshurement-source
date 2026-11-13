// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:csv/csv.dart';
import 'package:latlong2/latlong.dart';

import 'csv_v2.dart';
import 'export_data.dart';

/// Header of the firmware's `rangetest.csv`, byte for byte.
const meshtasticCsvHeader =
    'time,from,sender name,sender lat,sender long,rx lat,rx long,'
    'rx elevation,rx snr,distance,hop limit,payload,rx rssi';

/// Meshtastic-compatible CSV: the firmware's columns, received rows only.
///
/// `time` is the UTC wall clock as `HH:MM:SS` and `from` is the decimal node
/// number, exactly as firmware 2.7's RangeTestModule.cpp prints them
/// (`%02d:%02d:%02d` from gettimeofday, `%d` of getFrom).
/// `sender lat`/`sender long` are the map's base location on rows from the
/// session's base radio (the firmware uses the sender's reported position;
/// a map is a place and the base stands at it), with `distance` in whole
/// metres from there to the phone. Other senders' rows leave them empty.
/// `hop limit` stays empty: we store the hops a packet used, not its limit.
String buildMeshtasticCsv(Iterable<SessionExport> sessions) {
  final rows = <List<Object>>[
    meshtasticCsvHeader.split(','),
  ];
  for (final s in sessions) {
    final baseLat = s.map?.baseLat, baseLon = s.map?.baseLon;
    final baseAt = baseLat == null || baseLon == null
        ? null
        : LatLng(baseLat, baseLon);
    for (final e in s.heardEvents) {
      if (e.event.direction != 'rx') continue;
      final ev = e.event;
      final fromBase =
          baseAt != null && e.node != null && e.node!.id == s.baseNode?.id;
      final distance = fromBase && ev.rxLat != null && ev.rxLon != null
          ? _distance(baseAt, LatLng(ev.rxLat!, ev.rxLon!)).round()
          : null;
      final name = e.node == null
          ? ''
          : (e.node!.longName.isNotEmpty
              ? e.node!.longName
              : e.node!.shortName);
      rows.add([
        _hms(ev.timestamp.toUtc()),
        e.node == null ? '' : e.node!.nodeId,
        csvSafeText(name),
        fromBase ? baseAt.latitude : '',
        fromBase ? baseAt.longitude : '',
        ev.rxLat ?? '',
        ev.rxLon ?? '',
        ev.rxAlt ?? '',
        ev.rxSnr ?? '',
        distance ?? '',
        '', // hop limit: not recorded
        ev.seq == null ? '' : 'seq ${ev.seq}',
        ev.rxRssi ?? '',
      ]);
    }
  }
  return const ListToCsvConverter().convert(rows);
}

const _distance = Distance();

String _two(int v) => v.toString().padLeft(2, '0');

/// `HH:MM:SS` of [t] (already UTC), the firmware's time column.
String _hms(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
