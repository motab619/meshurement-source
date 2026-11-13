// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import '../radio_preset.dart';

/// One suggested MeshCore radio setting: frequency plus modulation, and the
/// path hash size the community network uses where it says so.
class MeshCorePreset {
  /// Stable id, "MC_" + a slug of the title (e.g. "MC_USA").
  final String id;

  /// Title as the official apps show it.
  final String title;
  final double frequencyMHz;
  final double bandwidthKHz;
  final int spreadingFactor;

  /// Coding-rate denominator (5 = 4/5).
  final int codingRate;

  /// Bytes per hop hash the network expects (the official app's
  /// `network_settings.path_hash_size`); null when unspecified (1).
  final int? pathHashSize;

  /// The official list marks it "(Deprecated)".
  final bool deprecated;

  const MeshCorePreset({
    required this.id,
    required this.title,
    required this.frequencyMHz,
    required this.bandwidthKHz,
    required this.spreadingFactor,
    required this.codingRate,
    this.pathHashSize,
    this.deprecated = false,
  });

  /// Frequency as the radio reports and takes it (SELF_INFO,
  /// CMD_SET_RADIO_PARAMS).
  int get frequencyKHz => (frequencyMHz * 1000).round();

  /// Bandwidth as the radio reports and takes it.
  int get bandwidthHz => (bandwidthKHz * 1000).round();

  /// The modulation as our protocol-neutral preset (frequency is not part
  /// of [RadioPreset]).
  RadioPreset get radioPreset => RadioPreset(
        id: id,
        displayName: title,
        sf: spreadingFactor,
        bwKHz: bandwidthKHz,
        cr: codingRate,
        deprecated: deprecated,
      );

  /// Whether the radio parameters equal this preset. Frequency is compared
  /// to the kHz the firmware reports (it stores MHz as a float).
  bool matches({
    required int frequencyKHz,
    required int bandwidthHz,
    required int spreadingFactor,
    required int codingRate,
  }) =>
      (frequencyKHz - this.frequencyKHz).abs() <= 1 &&
      (bandwidthHz - this.bandwidthHz).abs() <= 1 &&
      spreadingFactor == this.spreadingFactor &&
      codingRate == this.codingRate;

  @override
  String toString() => 'MeshCorePreset($title $frequencyMHz MHz '
      'SF$spreadingFactor/$bandwidthKHz/4/$codingRate)';
}

/// One of the distinct modulations the community presets use, named by
/// its place on the range ladder (fast and short to slow and long, by the
/// airtime of one link check). Frequency is not part of it: whichever
/// modulation is picked, the app tests on the band's relay frequency, so
/// this, not a community preset, is what a MeshCore test radio is "on".
class MeshCoreModulation {
  /// Stable id, e.g. "MC_SF7_BW62.5_CR5" (sessions store it as
  /// `loraPreset`).
  final String id;

  /// Ladder name, e.g. "Fast", "Medium, most robust".
  final String name;
  final int spreadingFactor;
  final double bandwidthKHz;

  /// Coding-rate denominator (5 = 4/5).
  final int codingRate;

  const MeshCoreModulation({
    required this.name,
    required this.spreadingFactor,
    required this.bandwidthKHz,
    required this.codingRate,
  }) : id = 'MC_SF${spreadingFactor}_BW${bandwidthKHz}_CR$codingRate';

  int get bandwidthHz => (bandwidthKHz * 1000).round();

  bool matches({
    required int bandwidthHz,
    required int spreadingFactor,
    required int codingRate,
  }) =>
      (bandwidthHz - this.bandwidthHz).abs() <= 1 &&
      spreadingFactor == this.spreadingFactor &&
      codingRate == this.codingRate;

  /// The community presets that use this modulation (on their own
  /// frequencies), the deprecated ones left out.
  List<MeshCorePreset> get communities => [
        for (final p in MeshCorePresets.all)
          if (!p.deprecated &&
              matches(
                  bandwidthHz: p.bandwidthHz,
                  spreadingFactor: p.spreadingFactor,
                  codingRate: p.codingRate))
            p
      ];

  /// As our protocol-neutral preset.
  RadioPreset get radioPreset => RadioPreset(
        id: id,
        displayName: name,
        sf: spreadingFactor,
        bwKHz: bandwidthKHz,
        cr: codingRate,
      );

  @override
  String toString() => 'MeshCoreModulation($name)';
}

/// The range ladder: every distinct modulation in [MeshCorePresets.all],
/// fastest link check first (SF7/62.5/4/5 ≈ 0.23 s, SF11/125/4/5 ≈ 1.6 s).
class MeshCoreModulations {
  MeshCoreModulations._();

  static const fast = MeshCoreModulation(
      name: 'Fast', spreadingFactor: 7, bandwidthKHz: 62.5, codingRate: 5);
  static const fastRobust = MeshCoreModulation(
      name: 'Fast, more robust',
      spreadingFactor: 7,
      bandwidthKHz: 62.5,
      codingRate: 6);
  static const fastMostRobust = MeshCoreModulation(
      name: 'Fast, most robust',
      spreadingFactor: 7,
      bandwidthKHz: 62.5,
      codingRate: 7);
  static const mediumWide = MeshCoreModulation(
      name: 'Medium (125 kHz)',
      spreadingFactor: 9,
      bandwidthKHz: 125,
      codingRate: 5);
  static const mediumWidest = MeshCoreModulation(
      name: 'Medium (250 kHz)',
      spreadingFactor: 10,
      bandwidthKHz: 250,
      codingRate: 5);
  static const medium = MeshCoreModulation(
      name: 'Medium', spreadingFactor: 8, bandwidthKHz: 62.5, codingRate: 5);
  static const mediumMostRobust = MeshCoreModulation(
      name: 'Medium, most robust',
      spreadingFactor: 8,
      bandwidthKHz: 62.5,
      codingRate: 8);
  static const long = MeshCoreModulation(
      name: 'Long', spreadingFactor: 11, bandwidthKHz: 250, codingRate: 5);
  static const longRobust = MeshCoreModulation(
      name: 'Long, more robust',
      spreadingFactor: 9,
      bandwidthKHz: 62.5,
      codingRate: 6);
  static const longest = MeshCoreModulation(
      name: 'Longest', spreadingFactor: 11, bandwidthKHz: 125, codingRate: 5);

  /// Fastest link check first.
  static const all = <MeshCoreModulation>[
    fast,
    fastRobust,
    fastMostRobust,
    mediumWide,
    mediumWidest,
    medium,
    mediumMostRobust,
    long,
    longRobust,
    longest,
  ];

  static MeshCoreModulation? byId(String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// The ladder entry with these parameters, or null for a modulation no
  /// community uses.
  static MeshCoreModulation? of({
    required int bandwidthHz,
    required int spreadingFactor,
    required int codingRate,
  }) {
    for (final m in all) {
      if (m.matches(
          bandwidthHz: bandwidthHz,
          spreadingFactor: spreadingFactor,
          codingRate: codingRate)) {
        return m;
      }
    }
    return null;
  }

  /// The entry a community preset uses.
  static MeshCoreModulation? ofPreset(MeshCorePreset p) => of(
      bandwidthHz: p.bandwidthHz,
      spreadingFactor: p.spreadingFactor,
      codingRate: p.codingRate);

  /// A stored preset id with any community preset id (what Radio Setup
  /// recorded before the ladder, 2026-10-29) replaced by its ladder entry,
  /// so two radios on the same modulation compare equal.
  static String ladderId(String id) {
    final community = MeshCorePresets.byId(id);
    return community == null ? id : (ofPreset(community)?.id ?? id);
  }
}

/// The regional radio settings the official MeshCore apps suggest.
///
/// The apps don't hard-code these: they fetch them from the MeshCore App API
/// (`https://api.meshcore.nz/api/v1/config`,
/// `config.suggested_radio_settings.entries`; see docs/radio_presets.md in
/// meshcore-dev/MeshCore@81dbae5). This is a snapshot of that list taken
/// 2026-10-24, in the API's order. Several entries share identical settings
/// (e.g. Netherlands / Hungary / Slovakia differ only in path hash size),
/// and USA / Canada too), so a radio's parameters can match more than one;
/// see [match] for how it picks.
class MeshCorePresets {
  MeshCorePresets._();

  static const australia = MeshCorePreset(
      id: 'MC_AUSTRALIA',
      title: 'Australia',
      frequencyMHz: 915.800,
      bandwidthKHz: 250,
      spreadingFactor: 10,
      codingRate: 5);
  static const australiaNarrow = MeshCorePreset(
      id: 'MC_AUSTRALIA_NARROW',
      title: 'Australia (Narrow)',
      frequencyMHz: 916.575,
      bandwidthKHz: 62.5,
      spreadingFactor: 7,
      codingRate: 7);
  static const australiaMid = MeshCorePreset(
      id: 'MC_AUSTRALIA_MID',
      title: 'Australia (Mid)',
      frequencyMHz: 915.075,
      bandwidthKHz: 125,
      spreadingFactor: 9,
      codingRate: 5);
  static const australiaSaWa = MeshCorePreset(
      id: 'MC_AUSTRALIA_SA_WA',
      title: 'Australia: SA, WA',
      frequencyMHz: 923.125,
      bandwidthKHz: 62.5,
      spreadingFactor: 8,
      codingRate: 8);
  static const australiaQld = MeshCorePreset(
      id: 'MC_AUSTRALIA_QLD',
      title: 'Australia: QLD',
      frequencyMHz: 923.125,
      bandwidthKHz: 62.5,
      spreadingFactor: 8,
      codingRate: 5);
  static const brazil = MeshCorePreset(
      id: 'MC_BRAZIL',
      title: 'Brazil',
      frequencyMHz: 923.125,
      bandwidthKHz: 62.5,
      spreadingFactor: 8,
      codingRate: 8);
  static const canada = MeshCorePreset(
      id: 'MC_CANADA',
      title: 'Canada',
      frequencyMHz: 910.525,
      bandwidthKHz: 62.5,
      spreadingFactor: 7,
      codingRate: 5,
      pathHashSize: 3);
  static const costaRica = MeshCorePreset(
      id: 'MC_COSTA_RICA',
      title: 'Costa Rica',
      frequencyMHz: 910.525,
      bandwidthKHz: 125,
      spreadingFactor: 11,
      codingRate: 5);
  static const euUkNarrow = MeshCorePreset(
      id: 'MC_EU_UK_NARROW',
      title: 'EU/UK (Narrow)',
      frequencyMHz: 869.618,
      bandwidthKHz: 62.5,
      spreadingFactor: 8,
      codingRate: 8);
  static const euUkDeprecated = MeshCorePreset(
      id: 'MC_EU_UK_DEPRECATED',
      title: 'EU/UK (deprecated)',
      frequencyMHz: 869.525,
      bandwidthKHz: 250,
      spreadingFactor: 11,
      codingRate: 5,
      deprecated: true);
  static const czechNarrow = MeshCorePreset(
      id: 'MC_CZECH_REPUBLIC_NARROW',
      title: 'Czech Republic (Narrow)',
      frequencyMHz: 869.432,
      bandwidthKHz: 62.5,
      spreadingFactor: 7,
      codingRate: 5,
      pathHashSize: 2);
  static const eu433LongRange = MeshCorePreset(
      id: 'MC_EU_433_LONG_RANGE',
      title: 'EU 433MHz (Long Range)',
      frequencyMHz: 433.650,
      bandwidthKHz: 250,
      spreadingFactor: 11,
      codingRate: 5);
  static const eu433Narrow = MeshCorePreset(
      id: 'MC_EU_433_NARROW',
      title: 'EU 433MHz (Narrow)',
      frequencyMHz: 433.650,
      bandwidthKHz: 62.5,
      spreadingFactor: 8,
      codingRate: 8);
  static const hungary = MeshCorePreset(
      id: 'MC_HUNGARY',
      title: 'Hungary',
      frequencyMHz: 869.618,
      bandwidthKHz: 62.5,
      spreadingFactor: 7,
      codingRate: 5,
      pathHashSize: 2);
  static const netherlands = MeshCorePreset(
      id: 'MC_NETHERLANDS',
      title: 'Netherlands',
      frequencyMHz: 869.618,
      bandwidthKHz: 62.5,
      spreadingFactor: 7,
      codingRate: 5);
  static const netherlandsLimburg = MeshCorePreset(
      id: 'MC_NETHERLANDS_LIMBURG',
      title: 'Netherlands (Limburg)',
      frequencyMHz: 869.618,
      bandwidthKHz: 62.5,
      spreadingFactor: 8,
      codingRate: 8,
      pathHashSize: 2);
  static const newZealandNarrow = MeshCorePreset(
      id: 'MC_NEW_ZEALAND_NARROW',
      title: 'New Zealand (Narrow)',
      frequencyMHz: 917.375,
      bandwidthKHz: 62.5,
      spreadingFactor: 7,
      codingRate: 5,
      pathHashSize: 2);
  static const newZealandGisborne = MeshCorePreset(
      id: 'MC_NEW_ZEALAND_GISBORNE',
      title: 'New Zealand (Gisborne)',
      frequencyMHz: 917.375,
      bandwidthKHz: 250,
      spreadingFactor: 11,
      codingRate: 5,
      pathHashSize: 1);
  static const portugal433 = MeshCorePreset(
      id: 'MC_PORTUGAL_433',
      title: 'Portugal 433',
      frequencyMHz: 433.375,
      bandwidthKHz: 62.5,
      spreadingFactor: 9,
      codingRate: 6);
  static const portugal868 = MeshCorePreset(
      id: 'MC_PORTUGAL_868',
      title: 'Portugal 868',
      frequencyMHz: 869.618,
      bandwidthKHz: 62.5,
      spreadingFactor: 7,
      codingRate: 6);
  static const slovakia = MeshCorePreset(
      id: 'MC_SLOVAKIA',
      title: 'Slovakia',
      frequencyMHz: 869.618,
      bandwidthKHz: 62.5,
      spreadingFactor: 7,
      codingRate: 5,
      pathHashSize: 2);
  static const switzerland = MeshCorePreset(
      id: 'MC_SWITZERLAND',
      title: 'Switzerland',
      frequencyMHz: 869.618,
      bandwidthKHz: 62.5,
      spreadingFactor: 8,
      codingRate: 8);
  static const usa = MeshCorePreset(
      id: 'MC_USA',
      title: 'USA',
      frequencyMHz: 910.525,
      bandwidthKHz: 62.5,
      spreadingFactor: 7,
      codingRate: 5);
  static const usaSoCal = MeshCorePreset(
      id: 'MC_USA_SOUTHERN_CALIFORNIA',
      title: 'USA - Southern California',
      frequencyMHz: 927.875,
      bandwidthKHz: 62.5,
      spreadingFactor: 7,
      codingRate: 5,
      pathHashSize: 3);
  static const vietnamNarrow = MeshCorePreset(
      id: 'MC_VIETNAM_NARROW',
      title: 'Vietnam (Narrow)',
      frequencyMHz: 920.250,
      bandwidthKHz: 62.5,
      spreadingFactor: 8,
      codingRate: 5);
  static const vietnamDeprecated = MeshCorePreset(
      id: 'MC_VIETNAM_DEPRECATED',
      title: 'Vietnam (deprecated)',
      frequencyMHz: 920.250,
      bandwidthKHz: 250,
      spreadingFactor: 11,
      codingRate: 5,
      deprecated: true);

  /// Every preset, in the official list's order.
  static const all = <MeshCorePreset>[
    australia,
    australiaNarrow,
    australiaMid,
    australiaSaWa,
    australiaQld,
    brazil,
    canada,
    costaRica,
    euUkNarrow,
    euUkDeprecated,
    czechNarrow,
    eu433LongRange,
    eu433Narrow,
    hungary,
    netherlands,
    netherlandsLimburg,
    newZealandNarrow,
    newZealandGisborne,
    portugal433,
    portugal868,
    slovakia,
    switzerland,
    usa,
    usaSoCal,
    vietnamNarrow,
    vietnamDeprecated,
  ];

  /// The preset with [id], or null.
  static MeshCorePreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Every preset equal to the radio's parameters (as SELF_INFO reports
  /// them), in list order.
  static List<MeshCorePreset> matchAll({
    required int frequencyKHz,
    required int bandwidthHz,
    required int spreadingFactor,
    required int codingRate,
  }) =>
      [
        for (final p in all)
          if (p.matches(
              frequencyKHz: frequencyKHz,
              bandwidthHz: bandwidthHz,
              spreadingFactor: spreadingFactor,
              codingRate: codingRate))
            p
      ];

  /// The preset for the radio's parameters, or null for a custom setting.
  /// Among identical settings it prefers the one whose path hash size
  /// equals [pathHashSize] (DEVICE_INFO `pathHashMode + 1`, when known),
  /// else one that doesn't specify a path hash size, else the first.
  static MeshCorePreset? match({
    required int frequencyKHz,
    required int bandwidthHz,
    required int spreadingFactor,
    required int codingRate,
    int? pathHashSize,
  }) {
    final hits = matchAll(
        frequencyKHz: frequencyKHz,
        bandwidthHz: bandwidthHz,
        spreadingFactor: spreadingFactor,
        codingRate: codingRate);
    if (hits.isEmpty) return null;
    if (pathHashSize != null) {
      for (final p in hits) {
        if ((p.pathHashSize ?? 1) == pathHashSize) return p;
      }
    }
    for (final p in hits) {
      if (p.pathHashSize == null) return p;
    }
    return hits.first;
  }

  /// The neutral preset for the radio's parameters: its place on the
  /// [MeshCoreModulations] ladder (whatever the frequency: a radio moved to
  /// the test frequency keeps its modulation's name), else
  /// [RadioPreset.custom].
  static RadioPreset radioPresetFor({
    required int bandwidthHz,
    required int spreadingFactor,
    required int codingRate,
  }) =>
      MeshCoreModulations.of(
              bandwidthHz: bandwidthHz,
              spreadingFactor: spreadingFactor,
              codingRate: codingRate)
          ?.radioPreset ??
      RadioPreset.custom(spreadingFactor, bandwidthHz / 1000.0, codingRate);
}
