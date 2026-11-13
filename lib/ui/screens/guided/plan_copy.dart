// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import '../../../services/guided/plan_models.dart';

/// The Plan screen's words per template (design mock), and the time
/// estimate. Deterministic app strings; no model in the loop.
abstract final class PlanCopy {
  /// The one paragraph under the readouts.
  static String why(PlanRecord plan) => switch (plan.intent.template) {
        PlanTemplate.antennas =>
          'Two walks on the same route, one per antenna, with the base '
              'untouched. The app records each walk and compares them cell '
              'by cell.',
        PlanTemplate.rangeSettings => plan.remoteChanges
            ? 'Both nodes switch between settings and you walk the same '
                'route for each. The base is changed from where you stand, '
                'then your node, then the app checks the base is heard '
                'before you go.'
            : 'Both nodes switch between settings and you walk the same '
                'route for each. The app walks you to the base and changes '
                'it over Bluetooth, then your node.',
        PlanTemplate.radios =>
          'One walk per node on the same route, the base untouched. You '
              'connect the other node between walks; the app checks its '
              'setup and compares the walks cell by cell.',
        PlanTemplate.txPower =>
          'The radio switches transmit power and you walk the same route '
              'for each. Everything else stays the same.',
        PlanTemplate.reach =>
          'One walk: head away from the base until it drops out, then come '
              'back. The app records how far the link held and where it '
              'gave out.',
      };

  /// The one-line note under the track.
  static String note(PlanRecord plan) => switch (plan.intent.template) {
        PlanTemplate.antennas =>
          'Nothing on the nodes changes. You swap the antenna; the app '
              'does the rest.',
        PlanTemplate.rangeSettings => plan.remoteChanges
            ? 'The base is changed without touching it (Meshtastic, remote '
                'changes enabled in Node Setup). The app saves its settings '
                'first and explains the risk before the first change.'
            : "The base is changed by walking to it; the app connects over "
                "Bluetooth. It saves the base's settings first.",
        PlanTemplate.radios =>
          'Both nodes need to be set up as the mobile on the MeshTest '
              'channel; the app checks before each walk.',
        PlanTemplate.txPower =>
          'Only the transmit power changes; the app puts it back at the end.',
        PlanTemplate.reach => 'Nothing on the nodes changes.',
      };

  /// Rough minutes for one step.
  static int stepMinutes(PlanStep s, PlanIntent intent) => switch (s.kind) {
        StepKind.walk =>
          (s.params['minutes'] as num?)?.toInt() ?? intent.route.minutes,
        StepKind.swapHardware || StepKind.switchRadio || StepKind.goTo => 3,
        StepKind.changeRadios => 4,
        StepKind.settle =>
          (((s.params['seconds'] as num?)?.toInt() ?? 20) / 60).ceil(),
        StepKind.preflight || StepKind.analyze => 1,
      };

  static int totalMinutes(List<StepRecord> steps, PlanIntent intent) {
    var m = 0;
    for (final s in steps) {
      m += stepMinutes(s.step, intent);
    }
    return m;
  }

  static int walkCount(List<StepRecord> steps) =>
      steps.where((s) => s.step.kind == StepKind.walk).length;

  /// What a second pass costs: one more walk per setup.
  static int secondPassMinutes(PlanIntent intent) =>
      intent.variants.length * intent.route.minutes;
}
