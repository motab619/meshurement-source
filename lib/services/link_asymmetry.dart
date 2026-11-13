// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import '../data/database/app_database.dart';
import '../utils/constants.dart';
import 'rig_comparison.dart' show median;

// Pings are round trips: a reply needs the ping to reach the base (uplink,
// you → base) and the base's answer to come back (downlink, base → you).
// The reply's SNR/RSSI is measured by our node, so it is a downlink figure.
// Only a MeshCore trace also says how well the base heard us (`uplinkSnr`,
// measured by the base); a Meshtastic ACK says only that it heard us. Pure
// Dart: the numbers and the wording shown for them.

/// Fewer replies with both legs than this and no asymmetry line is shown.
const linkAsymmetryMinCount = 5;

/// Within this many dB either way the legs read "about the same".
const linkAsymmetrySameDb = 1.0;

/// How the two legs of a round trip compare over a set of replies.
class LinkAsymmetry {
  /// Median of uplink SNR minus downlink SNR (dB): negative = the base
  /// hears us worse than we hear it.
  final double medianDeltaDb;

  /// Replies that carried both legs.
  final int count;

  const LinkAsymmetry(this.medianDeltaDb, this.count);

  bool get aboutTheSame => medianDeltaDb.abs() <= linkAsymmetrySameDb;
}

/// Asymmetry over (uplink SNR, downlink SNR) pairs; null with fewer than
/// [minCount] pairs.
LinkAsymmetry? linkAsymmetryOf(Iterable<({double up, double down})> pairs,
    {int minCount = linkAsymmetryMinCount}) {
  final deltas = [for (final p in pairs) p.up - p.down];
  if (deltas.isEmpty || deltas.length < minCount) return null;
  return LinkAsymmetry(median(deltas), deltas.length);
}

/// The (uplink, downlink) SNR pair of one stored reply row, when it has
/// both: a ping reply (`direction == ack`) answered by the base itself
/// (relayed replies carry no SNR). Only MeshCore traces have an uplink.
({double up, double down})? replyLegs(PacketEvent e) {
  if (e.direction != PacketDirection.ack) return null;
  final up = e.uplinkSnr, down = e.rxSnr;
  if (up == null || down == null) return null;
  return (up: up, down: down);
}

/// [linkAsymmetryOf] over a session's (or map's) stored events.
LinkAsymmetry? linkAsymmetryFromEvents(Iterable<PacketEvent> events,
        {int minCount = linkAsymmetryMinCount}) =>
    linkAsymmetryOf(events.map(replyLegs).nonNulls, minCount: minCount);

/// "−3.2 dB": one decimal, a real minus sign.
String formatDb(double v) {
  final s = v.abs().toStringAsFixed(1);
  return v < 0 && s != '0.0' ? '−$s dB' : '$s dB';
}

/// "Up −3.2 dB · Down −5.0 dB".
String upDownText(double up, double down) =>
    'Up ${formatDb(up)} · Down ${formatDb(down)}';

/// "Uplink 2.1 dB weaker than downlink (median of 34 link checks)", or
/// "Uplink and downlink about the same (…)" within ±[linkAsymmetrySameDb].
/// [noun] is the plural probe noun ("link checks").
String linkAsymmetryText(LinkAsymmetry a, {String noun = 'link checks'}) {
  final of = '(median of ${a.count} $noun)';
  if (a.aboutTheSame) return 'Uplink and downlink about the same $of';
  final gap = a.medianDeltaDb.abs().toStringAsFixed(1);
  final how = a.medianDeltaDb < 0 ? 'weaker' : 'stronger';
  return 'Uplink $gap dB $how than downlink $of';
}

/// One ping or link check on the round-trip layer, for its tap readout:
/// "Base replied · Up −3.2 dB · Down −5.0 dB · round trip 1.4 s". Without
/// an uplink figure (Meshtastic) the reply's SNR is labelled as what it is,
/// a base → you reading.
String roundTripReadout({
  required String status,
  double? downSnr,
  int? downRssi,
  double? upSnr,
  int? roundTripMs,
}) {
  final String outcome;
  if (status == AckStatus.received) {
    outcome = 'Base replied';
  } else if (status == AckStatus.implicit) {
    outcome = 'Relayed only';
  } else if (status == AckStatus.throttled) {
    outcome = 'Held back by radio (not sent)';
  } else if (AckStatus.isError(status)) {
    final reason = status.contains(':') ? status.split(':').last : '';
    outcome = reason.isEmpty ? 'Refused' : 'Refused ($reason)';
  } else {
    outcome = 'No reply';
  }
  final parts = [
    outcome,
    if (upSnr != null && downSnr != null)
      upDownText(upSnr, downSnr)
    else if (downSnr != null)
      'Reply ${formatDb(downSnr)} SNR (base → you)',
    if (downRssi != null) '$downRssi dBm',
    if (roundTripMs != null && status == AckStatus.received)
      'round trip ${(roundTripMs / 1000).toStringAsFixed(1)} s',
  ];
  return parts.join(' · ');
}
