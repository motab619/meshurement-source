// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter_test/flutter_test.dart';

import 'package:mesh_analyzer/data/radio/meshcore/meshcore_presets.dart';
import 'package:mesh_analyzer/services/guided/plan_builder.dart';
import 'package:mesh_analyzer/services/guided/plan_models.dart';

List<StepKind> kinds(List<PlanStep> steps) => [for (final s in steps) s.kind];

const antennas = PlanIntent(
    template: PlanTemplate.antennas,
    variants: ['Stock whip', '5.8 dBi fiberglass']);
const presets = PlanIntent(
    template: PlanTemplate.rangeSettings,
    variants: ['MEDIUM_FAST', 'LONG_FAST']);

List<PlanStep> build(PlanIntent i,
        {bool remote = false, String protocol = 'meshtastic', String? restore}) =>
    buildSteps(i, remoteChanges: remote, protocol: protocol, restoreTo: restore);

void main() {
  group('antennas', () {
    test('track: preflight, swap, go to start, walk, per variant, analyze',
        () {
      final steps = build(antennas);
      expect(kinds(steps), [
        StepKind.preflight,
        StepKind.swapHardware,
        StepKind.goTo,
        StepKind.walk,
        StepKind.swapHardware,
        StepKind.goTo,
        StepKind.walk,
        StepKind.analyze,
      ]);
      expect([for (final s in steps) s.ordinal], List.generate(8, (i) => i));
      expect(steps[1].title, 'Put the Stock whip on');
      expect(steps[1].summary, 'On the mobile node, hand-tight, upright');
      expect(steps[1].variant, 0);
      expect(steps[1].params, {'side': 'mobile', 'name': 'Stock whip'});
      expect(steps[2].title, 'Go to the start point');
      expect(steps[2].summary, 'Next to the base this first time');
      expect(steps[2].params, {'target': 'start'});
      expect(steps[3].title, 'Walk the route');
      expect(steps[3].summary, '≈12 min · the app records');
      expect(steps[3].params,
          {'minutes': 12, 'pass': 1, 'walk': 1, 'walks': 2});
      expect(steps[4].title, 'Put the 5.8 dBi fiberglass on');
      expect(steps[4].summary, 'Same node, same spot');
      expect(steps[5].title, 'Walk to where you started');
      expect(steps[6].title, 'Walk the same route');
      expect(steps[6].summary, 'Follow the ghost line · route match shown live');
      expect(steps[6].variant, 1);
      expect(steps[7].title, 'Compare');
      expect(steps[7].summary, 'Cell by cell, farthest reach, pings answered');
      expect(steps[0].summary, 'Nodes, channel, base location, GPS');
    });

    test('base side names the base radio', () {
      final steps = build(antennas.copyWith(side: PlanSide.base));
      expect(steps[1].summary, 'On the base node, hand-tight, upright');
      expect(steps[1].params['side'], 'base');
    });

    test('repeat adds a second pass in the other order without a swap for '
        'the variant already on', () {
      final steps = build(antennas.copyWith(repeat: true));
      expect(kinds(steps), [
        StepKind.preflight,
        StepKind.swapHardware, // A
        StepKind.goTo,
        StepKind.walk, // A pass 1
        StepKind.swapHardware, // B
        StepKind.goTo,
        StepKind.walk, // B pass 1
        StepKind.goTo, // B again: no swap
        StepKind.walk, // B pass 2
        StepKind.swapHardware, // A
        StepKind.goTo,
        StepKind.walk, // A pass 2
        StepKind.analyze,
      ]);
      final walks = steps.where((s) => s.kind == StepKind.walk).toList();
      expect([for (final w in walks) w.variant], [0, 1, 1, 0]);
      expect([for (final w in walks) w.params['pass']], [1, 1, 2, 2]);
      expect([for (final w in walks) w.params['walks']], [4, 4, 4, 4]);
      expect(walks[2].title, 'Walk the same route again');
      expect(walks[2].summary, 'Follow the ghost line · other order');
    });

    test('three variants keep walk order', () {
      final steps = build(antennas.copyWith(variants: ['A', 'B', 'C']));
      final walks = steps.where((s) => s.kind == StepKind.walk).toList();
      expect([for (final w in walks) w.variant], [0, 1, 2]);
      expect(walks.last.params['walk'], 3);
    });

    test('drive route changes the verb', () {
      final steps = build(antennas.copyWith(
          route: const PlanRoute(kind: RouteKind.drive, minutes: 20)));
      final walk = steps.firstWhere((s) => s.kind == StepKind.walk);
      expect(walk.title, 'Drive the route');
      expect(walk.params['minutes'], 20);
    });
  });

  group('radios', () {
    test('connects the other radio instead of swapping', () {
      final steps = build(const PlanIntent(
          template: PlanTemplate.radios, variants: ['T1000-E', 'Heltec V3']));
      expect(kinds(steps), [
        StepKind.preflight,
        StepKind.switchRadio,
        StepKind.goTo,
        StepKind.walk,
        StepKind.switchRadio,
        StepKind.goTo,
        StepKind.walk,
        StepKind.analyze,
      ]);
      expect(steps[1].title, 'Connect the T1000-E');
      expect(steps[1].params, {'name': 'T1000-E'});
      expect(steps[4].title, 'Connect the Heltec V3');
      expect(planTitle(steps.isEmpty ? antennas : const PlanIntent(
          template: PlanTemplate.radios, variants: ['a', 'b'])), 'Node test');
    });
  });

  group('reach', () {
    test('one walk until the base is lost', () {
      final steps = build(const PlanIntent(
          template: PlanTemplate.reach, variants: ['Current setup']));
      expect(kinds(steps),
          [StepKind.preflight, StepKind.goTo, StepKind.walk, StepKind.analyze]);
      expect(steps[2].title, 'Walk until the base is lost, then come back');
      expect(steps[2].variant, 0);
      expect(steps[3].title, 'Measure');
      expect(steps[3].summary, 'Farthest reach, where the base was lost');
    });
  });

  group('range settings', () {
    test('track: base, change, walk per variant, then put back and compare',
        () {
      final steps = build(presets, remote: true, restore: 'MEDIUM_FAST');
      expect(kinds(steps), [
        StepKind.preflight,
        StepKind.goTo,
        StepKind.changeRadios,
        StepKind.walk,
        StepKind.goTo,
        StepKind.changeRadios,
        StepKind.walk,
        StepKind.goTo,
        StepKind.changeRadios,
        StepKind.analyze,
      ]);
      expect(steps[0].summary,
          'Nodes, channel, remote changes allowed, base backup, GPS');
      expect(steps[1].title, 'Stand within sight of the base');
      expect(steps[1].summary, 'Radio changes happen where the link is strongest');
      expect(steps[1].params, {'target': 'base'});
      expect(steps[2].title, 'Switch both nodes to Medium Fast');
      expect(steps[2].summary,
          'Base changed from here, then yours · checks the base is heard');
      expect(steps[2].params, {'preset': 'MEDIUM_FAST'});
      expect(steps[2].variant, 0);
      expect(steps[4].title, 'Back to the base');
      expect(steps[5].title, 'Switch both nodes to Long Fast');
      expect(steps[5].params, {'preset': 'LONG_FAST'});
      expect(steps[8].title, 'Put both nodes back on Medium Fast');
      expect(steps[8].summary, 'Your everyday setting');
      expect(steps[8].params, {'restore': true, 'preset': 'MEDIUM_FAST'});
      expect(steps[8].variant, isNull);
      expect(steps[9].summary, 'Reach, margin, airtime per ping');
      expect(steps[9].instruction, contains('airtime per ping'));
    });

    test('restore without a known setting says so and leaves the value open',
        () {
      final steps = build(presets, remote: true);
      final restore = steps[8];
      expect(restore.title, 'Put both nodes back the way they were');
      expect(restore.params, {'restore': true});
    });

    test('Bluetooth path wording when remote is unavailable', () {
      final steps = build(presets, remote: false);
      expect(steps[0].summary,
          'Nodes, channel, base backup, base location, GPS');
      expect(steps[2].summary,
          'Walk to the base; the app connects over Bluetooth, then changes yours');
      expect(steps[2].instruction, contains('connects to the base over Bluetooth'));
      expect(steps[1].instruction, contains('within about 20 m'));
    });

    test('MeshCore never changes the base from a distance', () {
      final steps = build(
          presets.copyWith(variants: [
            MeshCoreModulations.fast.id,
            MeshCoreModulations.longest.id,
          ]),
          remote: true,
          protocol: 'meshcore');
      expect(steps[2].title, 'Switch both nodes to Fast');
      expect(steps[5].title, 'Switch both nodes to Longest');
      expect(steps[2].summary,
          'Walk to the base; the app connects over Bluetooth, then changes yours');
      expect(steps[2].instruction, startsWith('MeshCore: the base is changed by walking to it'));
    });

    test('a pre-ladder MeshCore community id is named by its ladder step', () {
      expect(presetDisplayName('MC_USA'), isNot('MC_USA'));
      expect(presetDisplayName('UNKNOWN_X'), 'UNKNOWN_X');
    });

    test('repeat: the setting already on is not changed again', () {
      final steps = build(presets.copyWith(repeat: true), remote: true);
      expect(kinds(steps), [
        StepKind.preflight,
        StepKind.goTo,
        StepKind.changeRadios, // A
        StepKind.walk,
        StepKind.goTo,
        StepKind.changeRadios, // B
        StepKind.walk,
        StepKind.goTo, // B again: back to the start, no change
        StepKind.walk,
        StepKind.goTo,
        StepKind.changeRadios, // A
        StepKind.walk,
        StepKind.goTo,
        StepKind.changeRadios, // restore
        StepKind.analyze,
      ]);
      expect(steps[7].params, {'target': 'start'});
      expect(steps[7].title, 'Walk to where you started');
      final walks = steps.where((s) => s.kind == StepKind.walk).toList();
      expect([for (final w in walks) w.variant], [0, 1, 1, 0]);
    });
  });

  group('TX power', () {
    test('mobile side: only your radio changes, dBm named', () {
      final steps = build(
          const PlanIntent(
              template: PlanTemplate.txPower, variants: ['20', '27']),
          restore: '27');
      expect(kinds(steps), [
        StepKind.preflight,
        StepKind.goTo,
        StepKind.changeRadios,
        StepKind.walk,
        StepKind.goTo,
        StepKind.changeRadios,
        StepKind.walk,
        StepKind.goTo,
        StepKind.changeRadios,
        StepKind.analyze,
      ]);
      expect(steps[2].title, 'Set the mobile node to 20 dBm');
      expect(steps[2].params, {'txPower': 20, 'side': 'mobile'});
      expect(steps[2].summary, 'Your node only · over Bluetooth, restarts');
      expect(steps[8].title, 'Put the mobile node back on 27 dBm');
      expect(steps[8].params, {'restore': true, 'txPower': 27, 'side': 'mobile'});
      expect(steps[9].summary, 'Cell by cell, farthest reach, pings answered');
    });

    test('base side: the base is changed, remotely or by Bluetooth', () {
      const intent = PlanIntent(
          template: PlanTemplate.txPower,
          side: PlanSide.base,
          variants: ['10', '27']);
      final remote = build(intent, remote: true);
      expect(remote[2].title, 'Set the base node to 10 dBm');
      expect(remote[2].summary,
          'Base changed from here, then yours · checks the base is heard');
      final bt = build(intent);
      expect(bt[2].summary,
          'Walk to the base; the app connects over Bluetooth, then changes yours');
    });
  });

  group('validation and helpers', () {
    test('an invalid intent throws PlanError with the validation line', () {
      expect(
          () => build(const PlanIntent(
              template: PlanTemplate.antennas, variants: ['one'])),
          throwsA(isA<PlanError>().having((e) => e.message, 'message',
              'Name at least two things to compare.')));
    });

    test('variant names per template', () {
      expect(variantName(presets, 1), 'Long Fast');
      expect(
          variantName(
              const PlanIntent(
                  template: PlanTemplate.txPower, variants: ['20', '27']),
              0),
          '20 dBm');
      expect(variantName(antennas, 1), '5.8 dBi fiberglass');
      expect(variantName(antennas, 5), '');
    });

    test('titles', () {
      expect(planTitle(antennas), 'Antenna test');
      expect(planTitle(presets), 'Range setting test');
      expect(
          planTitle(const PlanIntent(
              template: PlanTemplate.txPower, variants: ['1', '2'])),
          'TX power test');
      expect(
          planTitle(const PlanIntent(
              template: PlanTemplate.reach, variants: ['x'])),
          'Reach test');
    });

    test('planned minutes count the walks plus hands-on allowances', () {
      final steps = build(antennas);
      // 2 walks × 12 + 2 swaps × 2 + 2 goTo × 2 + preflight + analyze.
      expect(plannedMinutes(antennas, steps), 24 + 4 + 4 + 2);
    });

    test('every step round-trips through JSON', () {
      for (final s in build(presets.copyWith(repeat: true), remote: true)) {
        final back = PlanStep.fromJson(s.toJson());
        expect(back.kind, s.kind);
        expect(back.title, s.title);
        expect(back.params, s.params);
        expect(back.variant, s.variant);
      }
    });
  });
}
