// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:convert';

import 'csv_v2.dart';
import 'export_data.dart';

List<double> _pos(ExportEvent e) => [e.event.rxLon!, e.event.rxLat!];

/// RFC 7946 FeatureCollection as a map: one Point per positioned event
/// (coordinates are `[lon, lat]`, properties are the CSV v2 columns plus
/// `kind: "event"`) and one LineString per session with at least two
/// positioned events (the GPS track, time ordered, `kind: "gps_track"`).
/// Events without a fix have no geometry and are left out.
Map<String, Object?> buildGeoJsonMap(Iterable<SessionExport> sessions) {
  final features = <Map<String, Object?>>[];
  for (final s in sessions) {
    final positioned = [
      for (final e in s.heardEvents)
        if (e.hasPosition) e
    ]..sort((a, b) => a.event.timestamp.compareTo(b.event.timestamp));
    for (final e in positioned) {
      features.add({
        'type': 'Feature',
        'geometry': {'type': 'Point', 'coordinates': _pos(e)},
        'properties': {'kind': 'event', ...eventProperties(s, e)},
      });
    }
    if (positioned.length >= 2) {
      features.add({
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': [for (final e in positioned) _pos(e)],
        },
        'properties': {
          'kind': 'gps_track',
          'session_id': s.session.id,
          'session_name': s.session.name,
          'map_id': s.session.coverageMapId,
          'map_name': s.mapName,
          'start_utc':
              positioned.first.event.timestamp.toUtc().toIso8601String(),
          'end_utc': positioned.last.event.timestamp.toUtc().toIso8601String(),
        },
      });
    }
  }
  return {'type': 'FeatureCollection', 'features': features};
}

String buildGeoJson(Iterable<SessionExport> sessions) =>
    const JsonEncoder.withIndent(' ').convert(buildGeoJsonMap(sessions));
