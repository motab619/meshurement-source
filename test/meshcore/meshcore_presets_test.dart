// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_frames.dart';
import 'package:mesh_analyzer/data/radio/meshcore/meshcore_presets.dart';

void main() {
  test('ids are unique and stable', () {
    final ids = MeshCorePresets.all.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids, everyElement(startsWith('MC_')));
    expect(MeshCorePresets.all.length, 26);
    expect(MeshCorePresets.byId('MC_USA'), MeshCorePresets.usa);
    expect(MeshCorePresets.byId('nope'), isNull);
  });

  test('every preset is a setting the firmware accepts', () {
    // CMD_SET_RADIO_PARAMS bounds, MyMesh.cpp:1440-1441@81dbae5.
    for (final p in MeshCorePresets.all) {
      expect(p.frequencyKHz, inInclusiveRange(150000, 2500000), reason: p.id);
      expect(p.bandwidthHz, inInclusiveRange(7000, 500000), reason: p.id);
      expect(p.spreadingFactor, inInclusiveRange(5, 12), reason: p.id);
      expect(p.codingRate, inInclusiveRange(5, 8), reason: p.id);
    }
  });

  test('neutral RadioPreset carries the modulation', () {
    final r = MeshCorePresets.usa.radioPreset;
    expect(r.id, 'MC_USA');
    expect(r.displayName, 'USA');
    expect(r.sf, 7);
    expect(r.bwKHz, 62.5);
    expect(r.cr, 5);
    expect(r.deprecated, isFalse);
    final d = MeshCorePresets.euUkDeprecated.radioPreset;
    expect(d.deprecated, isTrue);
    expect(d.label, 'EU/UK (deprecated)'); // not doubled
  });

  test('matches the radio parameters SELF_INFO reports', () {
    expect(
        MeshCorePresets.match(
            frequencyKHz: 910525,
            bandwidthHz: 62500,
            spreadingFactor: 7,
            codingRate: 5),
        MeshCorePresets.usa);
    // Float rounding in the firmware: tolerate 1 kHz.
    expect(
        MeshCorePresets.match(
            frequencyKHz: 869617,
            bandwidthHz: 62500,
            spreadingFactor: 8,
            codingRate: 8),
        MeshCorePresets.euUkNarrow);
    // Identical settings (Hungary/Netherlands/Slovakia): without a hint,
    // the one with no path hash size; with DEVICE_INFO's, the matching one.
    const nl = (f: 869618, bw: 62500, sf: 7, cr: 5);
    expect(
        MeshCorePresets.matchAll(
                frequencyKHz: nl.f,
                bandwidthHz: nl.bw,
                spreadingFactor: nl.sf,
                codingRate: nl.cr)
            .map((p) => p.id),
        ['MC_HUNGARY', 'MC_NETHERLANDS', 'MC_SLOVAKIA']);
    expect(
        MeshCorePresets.match(
            frequencyKHz: nl.f,
            bandwidthHz: nl.bw,
            spreadingFactor: nl.sf,
            codingRate: nl.cr),
        MeshCorePresets.netherlands);
    expect(
        MeshCorePresets.match(
            frequencyKHz: nl.f,
            bandwidthHz: nl.bw,
            spreadingFactor: nl.sf,
            codingRate: nl.cr,
            pathHashSize: 2),
        MeshCorePresets.hungary);
    // USA vs Canada (3-byte hashes).
    expect(
        MeshCorePresets.match(
            frequencyKHz: 910525,
            bandwidthHz: 62500,
            spreadingFactor: 7,
            codingRate: 5,
            pathHashSize: 3),
        MeshCorePresets.canada);
    expect(
        MeshCorePresets.match(
            frequencyKHz: 915000,
            bandwidthHz: 250000,
            spreadingFactor: 10,
            codingRate: 5),
        isNull);
  });

  test('radioPresetFor names the ladder entry, else a custom preset', () {
    final c = MeshCorePresets.radioPresetFor(
        bandwidthHz: 500000, spreadingFactor: 12, codingRate: 5);
    expect(c.id, 'CUSTOM');
    expect(c.bwKHz, 500);
    // Whatever the frequency, a community modulation keeps its name.
    expect(
        MeshCorePresets.radioPresetFor(
                bandwidthHz: 62500, spreadingFactor: 7, codingRate: 5)
            .id,
        'MC_SF7_BW62.5_CR5');
  });

  test('the ladder covers every community modulation once, fastest first',
      () {
    final ids = MeshCoreModulations.all.map((m) => m.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final p in MeshCorePresets.all) {
      expect(MeshCoreModulations.ofPreset(p), isNotNull, reason: p.id);
    }
    final distinct = {
      for (final p in MeshCorePresets.all)
        (p.spreadingFactor, p.bandwidthKHz, p.codingRate)
    };
    expect(MeshCoreModulations.all.length, distinct.length);
    expect(MeshCoreModulations.all.first, MeshCoreModulations.fast);
    expect(MeshCoreModulations.all.last, MeshCoreModulations.longest);
    expect(MeshCoreModulations.byId('MC_SF8_BW62.5_CR8'),
        MeshCoreModulations.mediumMostRobust);
    expect(MeshCoreModulations.fast.communities.map((p) => p.id),
        contains('MC_USA'));
    expect(MeshCoreModulations.long.communities.map((p) => p.id),
        isNot(contains('MC_VIETNAM_DEPRECATED')));
    expect(MeshCoreModulations.fast.radioPreset.displayName, 'Fast');
  });

  test('a preset builds the matching SET_RADIO_PARAMS frame', () {
    const p = MeshCorePresets.australiaNarrow;
    final f = MeshCoreCommands.setRadioParams(
        frequencyMHz: p.frequencyMHz,
        bandwidthKHz: p.bandwidthKHz,
        spreadingFactor: p.spreadingFactor,
        codingRate: p.codingRate);
    final d = ByteData.sublistView(f);
    expect(d.getUint32(1, Endian.little), 916575);
    expect(d.getUint32(5, Endian.little), 62500);
    expect(f.sublist(9), [7, 7]);
  });
}
