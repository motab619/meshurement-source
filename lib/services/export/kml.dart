// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:ui' show Color;

import '../../utils/constants.dart';
import '../../utils/link_margin.dart';
import '../../utils/signal_color_mapper.dart';
import 'csv_v2.dart';
import 'export_data.dart';
import '../../utils/app_info.dart';

String xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;')
    // Characters XML 1.0 cannot carry at all.
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

/// KML colour is aabbggrr hex.
String _kmlColor(Color c) {
  String h(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
  return 'ff${h(c.b)}${h(c.g)}${h(c.r)}';
}

/// Style id per link-margin band ([MarginBand], the scale the legend and
/// Field Report use), coloured by the same SignalColorMapper as the dots.
String _bandStyleId(MarginBand b) => 'margin_${b.name}';

/// Style id for a link margin in dB (null gets the grey `no_signal` style).
String kmlStyleIdForMargin(double? marginDb) =>
    marginDb == null ? 'no_signal' : _bandStyleId(MarginBand.of(marginDb));

/// Hybrid SNR/RSSI link margin of an event on its session's preset (the
/// default preset when the session's is unknown).
double? _marginOf(SessionExport s, ExportEvent e) =>
    MarginScale.forPresetId(s.session.loraPreset)
        .marginDb(snr: e.event.rxSnr, rssi: e.event.rxRssi);

const _pingFailures = {AckStatus.timeout, AckStatus.error, AckStatus.throttled};

String _styleFor(SessionExport s, ExportEvent e) {
  final st = e.ping?.ackStatus;
  if (st != null && _pingFailures.contains(st)) return 'ping_failed';
  return kmlStyleIdForMargin(_marginOf(s, e));
}

String _style(String id, Color c, {double scale = 1.0, String? icon}) =>
    '<Style id="$id"><IconStyle><color>${_kmlColor(c)}</color>'
    '<scale>$scale</scale><Icon><href>${icon ?? 'http://maps.google.com/mapfiles/kml/shapes/shaded_dot.png'}</href></Icon>'
    '</IconStyle><LabelStyle><scale>0</scale></LabelStyle></Style>';

String _data(Map<String, Object?> props) {
  final b = StringBuffer('<ExtendedData>');
  props.forEach((k, v) {
    if (v == null || v == '') return;
    b.write(
        '<Data name="${xmlEscape(k)}"><value>${xmlEscape('$v')}</value></Data>');
  });
  b.write('</ExtendedData>');
  return b.toString();
}

/// KML document: one Folder per session; a Placemark per positioned event
/// with a TimeStamp (Google Earth time slider), a style per link-margin
/// band (Strong 20+ dB, Good 10 to 20, Weak 0 to 10, Below limit), a
/// distinct style for failed pings, and the CSV v2 fields as ExtendedData.
/// Each folder also holds the GPS track as a LineString.
String buildKml(Iterable<SessionExport> sessions,
    {String name = AppInfo.displayName}) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8"?>\n')
    ..write('<kml xmlns="http://www.opengis.net/kml/2.2"><Document>')
    ..write('<name>${xmlEscape(name)}</name>');
  for (final band in MarginBand.values) {
    b.write(_style(_bandStyleId(band), band.colour));
  }
  b.write(_style('no_signal', SignalColorMapper.noData, scale: 0.7));
  b.write(_style('ping_failed', const Color(0xFFC2185B),
      scale: 1.1,
      icon: 'http://maps.google.com/mapfiles/kml/shapes/caution.png'));
  for (final s in sessions) {
    final sname =
        s.session.name.isEmpty ? 'Session ${s.session.id}' : s.session.name;
    b.write('<Folder><name>${xmlEscape(sname)}</name>'
        '<description>${xmlEscape('Map: ${s.mapName}; preset: ${s.session.loraPreset}')}</description>');
    final positioned = [
      for (final e in s.heardEvents)
        if (e.hasPosition) e
    ]..sort((a, b) => a.event.timestamp.compareTo(b.event.timestamp));
    for (final e in positioned) {
      final ev = e.event;
      final margin = _marginOf(s, e);
      final label = e.ping != null
          ? 'ping ${e.ping!.ackStatus}'
          : '${ev.direction} ${margin == null ? ev.packetType : '${MarginBand.of(margin).label}, ${margin.toStringAsFixed(1)} dB margin'}';
      b.write('<Placemark><name>${xmlEscape(label)}</name>'
          '<styleUrl>#${_styleFor(s, e)}</styleUrl>'
          '<TimeStamp><when>${ev.timestamp.toUtc().toIso8601String()}</when></TimeStamp>'
          '${_data(eventProperties(s, e))}'
          '<Point><coordinates>${ev.rxLon},${ev.rxLat},${ev.rxAlt ?? 0}</coordinates></Point>'
          '</Placemark>');
    }
    if (positioned.length >= 2) {
      b.write(
          '<Placemark><name>GPS track</name><LineString><tessellate>1</tessellate><coordinates>'
          '${positioned.map((e) => '${e.event.rxLon},${e.event.rxLat},${e.event.rxAlt ?? 0}').join(' ')}'
          '</coordinates></LineString></Placemark>');
    }
    b.write('</Folder>');
  }
  b.write('</Document></kml>');
  return b.toString();
}
