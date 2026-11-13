// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import '../data/database/app_database.dart';
import '../utils/constants.dart';
import '../utils/link_margin.dart';

/// What the estimated-coverage layer is built from: every received signal,
/// plus silence. A ping that went unanswered, or whose reply came back
/// without a usable signal (relayed, or acked by another node), is a place
/// the base was not heard directly. Each counts as a "no margin" sample at
/// the phone's position, so a stretch the base didn't reach can't be painted
/// green from the strong samples around it (TestFlight report, 2026-11-04:
/// "why would it be green between the base and the red?").
class EstimateSamples {
  final List<double> lats;
  final List<double> lons;

  /// Link margin in dB (SNR mode) or RSSI in dBm (RSSI mode).
  final List<double> values;

  /// Packet event ids behind each sample (cache key material).
  final List<int> ids;

  /// How many of the samples are silence rather than a measurement.
  final int silent;

  const EstimateSamples({
    required this.lats,
    required this.lons,
    required this.values,
    required this.ids,
    required this.silent,
  });

  bool get isEmpty => lats.isEmpty;

  /// The value silence gets: no margin (0 dB above the decode limit), or an
  /// RSSI at the red end of the ramp (the legend's "RSSI ≤ -120").
  static const silentMarginDb = 0.0;
  static const silentRssi = -130.0;

  /// [rx] are the map's base → you events (direction rx or ack, with a
  /// position); [pings] every ping sent in its sessions, whose outcome
  /// decides what silence is: a timeout, or an older MAX_RETRANSMIT NAK
  /// ([AckStatus.isNoReply], sample at the phone's position when it was
  /// sent), or a reply that was received or implicit but
  /// carries no signal (relayed, or acked by another node: sample at the
  /// reply's position). NAKs and throttled pings also leave a reply row
  /// without a signal, but they are not silence: the radio refused to
  /// send, nothing was on air. [scaleOf] is the margin scale (decode
  /// limit and sensitivity) of an event's preset; margins are the hybrid
  /// SNR/RSSI [linkMarginDb].
  static EstimateSamples from({
    required List<PacketEvent> rx,
    required List<PingResult> pings,
    required bool rssi,
    required MarginScale Function(PacketEvent) scaleOf,
  }) {
    final lats = <double>[], lons = <double>[], values = <double>[];
    final ids = <int>[];
    var silent = 0;
    final silence = rssi ? silentRssi : silentMarginDb;
    double? signalOf(PacketEvent e) => rssi
        ? e.rxRssi?.toDouble()
        : scaleOf(e).marginDb(snr: e.rxSnr, rssi: e.rxRssi);
    final byId = <int, PacketEvent>{};
    for (final e in rx) {
      if (e.rxLat == null || e.rxLon == null) continue;
      byId[e.id] = e;
      final v = signalOf(e);
      if (v == null) continue;
      lats.add(e.rxLat!);
      lons.add(e.rxLon!);
      values.add(v);
      ids.add(e.id);
    }
    for (final p in pings) {
      final status = p.correlation.ackStatus;
      final PacketEvent? at;
      if (AckStatus.isNoReply(status)) {
        at = p.tx;
      } else if (status == AckStatus.received || status == AckStatus.implicit) {
        final ackId = p.correlation.ackEventId;
        final ack = ackId == null ? null : byId[ackId];
        at = ack != null && signalOf(ack) == null ? ack : null;
      } else {
        at = null;
      }
      if (at == null || at.rxLat == null || at.rxLon == null) continue;
      lats.add(at.rxLat!);
      lons.add(at.rxLon!);
      values.add(silence);
      ids.add(at.id);
      silent++;
    }
    return EstimateSamples(
        lats: lats, lons: lons, values: values, ids: ids, silent: silent);
  }
}
