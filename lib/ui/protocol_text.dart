// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import '../data/database/app_database.dart';
import '../data/radio/meshcore/meshcore_presets.dart';
import '../data/radio/meshtastic/meshtastic_presets.dart';
import '../data/radio/radio_preset.dart';
import '../data/radio/radio_types.dart';

/// Protocol-aware wording and lookups shared by the screens.

/// "Meshtastic" / "MeshCore", for factual labels (never branding).
String protocolLabel(RadioProtocol p) => switch (p) {
      RadioProtocol.meshtastic => 'Meshtastic',
      RadioProtocol.meshcore => 'MeshCore',
    };

/// What the app calls one probe exchange with the base: "ping" on
/// Meshtastic (a direct message with an ACK), "link check" on MeshCore (a
/// trace). [plural] gives "pings" / "link checks"; [capital] starts with a
/// capital letter for labels and sentence starts.
String probeNoun(RadioProtocol p, {bool plural = false, bool capital = false}) {
  final base = p == RadioProtocol.meshcore ? 'link check' : 'ping';
  final word = plural ? '${base}s' : base;
  return capital ? word[0].toUpperCase() + word.substring(1) : word;
}

/// [probeNoun] for a stored `sessions.protocol` value.
String probeNounFor(String? protocol,
        {bool plural = false, bool capital = false}) =>
    probeNoun(
        protocol == RadioProtocol.meshcore.name
            ? RadioProtocol.meshcore
            : RadioProtocol.meshtastic,
        plural: plural,
        capital: capital);

/// The protocol a session was recorded with (`sessions.protocol`).
RadioProtocol sessionProtocol(Session s) =>
    s.protocol == RadioProtocol.meshcore.name
        ? RadioProtocol.meshcore
        : RadioProtocol.meshtastic;

/// The preset a stored id names, on either protocol; null for a custom
/// setting or an unknown id.
RadioPreset? presetForId(String id) =>
    MeshtasticPresets.fromId(id) ??
    MeshCoreModulations.byId(id)?.radioPreset ??
    MeshCorePresets.byId(id)?.radioPreset;

/// Display name for a stored preset id on either protocol ("Long Fast",
/// "Fast (SF7 / 62.5 kHz / 4/5)", "USA" for a community preset id from
/// before the ladder); the id itself when unknown.
String anyPresetDisplayName(String id) {
  final meshtastic = MeshtasticPresets.fromId(id);
  if (meshtastic != null) return meshtastic.displayName;
  final mod = MeshCoreModulations.byId(id);
  if (mod != null) return meshCoreModulationLabel(mod);
  return MeshCorePresets.byId(id)?.title ?? id;
}

/// "Fast (SF7 / 62.5 kHz / 4/5)".
String meshCoreModulationLabel(MeshCoreModulation m) =>
    '${m.name} (${modulationLabel(m.spreadingFactor, m.bandwidthKHz, m.codingRate)})';

/// "USA, Canada, Hungary +5": the communities that use [m], the first
/// [shown] by name, [first] (the radio's own community) leading when it
/// is one of them.
String meshCoreCommunitiesLabel(MeshCoreModulation m,
    {int shown = 3, String first = ''}) {
  final titles = [for (final p in m.communities) p.title];
  if (titles.isEmpty) return 'No community uses this';
  if (titles.remove(first)) titles.insert(0, first);
  final head = titles.take(shown).join(', ');
  final rest = titles.length - shown;
  return rest > 0 ? '$head +$rest' : head;
}

/// "62.5", "250".
String formatBandwidthKHz(double bw) =>
    bw == bw.roundToDouble() ? bw.toInt().toString() : bw.toString();

/// "SF7 / 62.5 kHz / 4/5": the modulation alone.
String modulationLabel(int sf, double bwKHz, int cr) =>
    'SF$sf / ${formatBandwidthKHz(bwKHz)} kHz / 4/$cr';

/// "SF7 / 62.5 kHz / 4/5 · USA", "(deprecated)" appended when so.
String meshCorePresetLabel(MeshCorePreset p) =>
    '${modulationLabel(p.spreadingFactor, p.bandwidthKHz, p.codingRate)} · '
    '${p.title}'
    '${p.deprecated && !p.title.toLowerCase().contains('deprecated') ? ' (deprecated)' : ''}';

/// The three LoRa band families the MeshCore presets fall into.
enum MeshCoreBand {
  mhz433('433 MHz'),
  mhz868('868 MHz'),
  mhz915('915 MHz');

  const MeshCoreBand(this.label);
  final String label;

  /// The family [mhz] belongs to.
  static MeshCoreBand of(double mhz) => mhz < 600
      ? MeshCoreBand.mhz433
      : mhz < 900
          ? MeshCoreBand.mhz868
          : MeshCoreBand.mhz915;

  /// The client-repeat frequency in this band: the only one a MeshCore
  /// companion radio relays on (firmware allows exactly 433.000, 869.495
  /// and 918.000 MHz), so the base must sit on it to answer link checks.
  double get clientRepeatMHz => switch (this) {
        MeshCoreBand.mhz433 => 433.000,
        MeshCoreBand.mhz868 => 869.495,
        MeshCoreBand.mhz915 => 918.000,
      };
}

/// Every client-repeat frequency, for "is this one?" checks.
const meshCoreClientRepeatMHz = [433.000, 869.495, 918.000];

/// [mhz] is a frequency a MeshCore base can relay on (to the kHz).
bool isClientRepeatFrequency(double mhz) =>
    meshCoreClientRepeatMHz.any((f) => (f - mhz).abs() < 0.0005);

/// Factual compatibility wording for About (beside the Meshtastic
/// trademark notice). Never branding.
const meshCoreCompatibilityNotice =
    'Works with MeshCore companion nodes over Bluetooth. MeshCore is a '
    'project of its authors; this app is not affiliated with it.';

/// One-line note for a comparison whose sides differ in protocol or
/// bandwidth, or null when they don't (or it can't be told). Narrow
/// bandwidth has a lower noise floor, so the same signal gives a higher
/// SNR: such sides compare by link margin, not raw SNR.
String? comparabilityNote(Iterable<Session> a, Iterable<Session> b) {
  Set<RadioProtocol> protocols(Iterable<Session> g) =>
      {for (final s in g) sessionProtocol(s)};
  Set<double> bandwidths(Iterable<Session> g) => {
        for (final s in g)
          if (presetForId(s.loraPreset) case final p?) p.bwKHz,
      };
  final pa = protocols(a), pb = protocols(b);
  final protocolDiffers = pa.length > 1 || pb.length > 1 || !pa.containsAll(pb);
  final ba = bandwidths(a), bb = bandwidths(b);
  final bandwidthDiffers = ba.isNotEmpty &&
      bb.isNotEmpty &&
      (ba.length > 1 || bb.length > 1 || !ba.containsAll(bb));
  if (!protocolDiffers && !bandwidthDiffers) return null;
  String bw(Set<double> v) =>
      '${(v.toList()..sort()).map(formatBandwidthKHz).join('/')} kHz';
  final what = [
    if (protocolDiffers)
      '${pa.map(protocolLabel).join('/')} vs ${pb.map(protocolLabel).join('/')}',
    if (bandwidthDiffers) '${bw(ba)} vs ${bw(bb)}',
  ].join(', ');
  return bandwidthDiffers
      ? 'Sides differ ($what): narrower bandwidth reads a higher SNR for '
          'the same signal, so compare link margin and ping success, not '
          'raw SNR.'
      : 'Sides differ ($what): compare link margin and ping success, not '
          'raw SNR.';
}
