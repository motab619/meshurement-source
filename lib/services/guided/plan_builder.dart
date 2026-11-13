// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import '../../data/radio/meshcore/meshcore_presets.dart';
import '../../data/radio/meshtastic/meshtastic_presets.dart';
import 'plan_models.dart';

/// Guided test: intent → steps (design `docs/design/guided-test/README.md`
/// §2 and §3). Pure: no radios, no database, so every template is unit
/// tested. The runner (`plan_runner.dart`) interprets `PlanStep.params`.
///
/// Tracks:
///
/// * antennas / radios: preflight → per variant: swap (or connect) →
///   go to the start → walk → … → analyze. The first "go to" is "next to
///   the base" (the start point is set there); later ones follow the pin.
/// * reach: preflight → go to the start → one walk until the base is
///   lost → analyze.
/// * range settings / TX power: preflight → stand by the base → change
///   the radios → walk → back to the base → change → walk → … → put the
///   radios back (`restore: true`) → analyze.
///
/// `repeat` adds a second pass in the other order (A B · B A); the variant
/// that is already on when the second pass starts is not changed again.

/// Protocol name as sessions store it (`RadioProtocol.name`).
const protocolMeshcore = 'meshcore';

/// Title of the plan ("Antenna test"); the sessions and the result screen
/// carry it.
String planTitle(PlanIntent intent) => switch (intent.template) {
      PlanTemplate.antennas => 'Antenna test',
      PlanTemplate.rangeSettings => 'Range setting test',
      PlanTemplate.radios => 'Node test',
      PlanTemplate.txPower => 'TX power test',
      PlanTemplate.reach => 'Reach test',
    };

/// The person's word for variant [i]: antenna and radio names as typed,
/// presets and ladder steps by their display name, TX power as "20 dBm".
String variantName(PlanIntent intent, int i) {
  if (i < 0 || i >= intent.variants.length) return '';
  final raw = intent.variants[i].trim();
  switch (intent.template) {
    case PlanTemplate.rangeSettings:
      return presetDisplayName(raw);
    case PlanTemplate.txPower:
      return '$raw dBm';
    case PlanTemplate.antennas:
    case PlanTemplate.radios:
    case PlanTemplate.reach:
      return raw;
  }
}

/// Human name of a preset id (Meshtastic "LONG_FAST" → "Long Fast",
/// MeshCore ladder "MC_SF9_BW125_CR5" → "Medium (125 kHz)"); the id when
/// unknown.
String presetDisplayName(String id) =>
    MeshtasticPresets.fromId(id)?.displayName ??
    MeshCoreModulations.byId(MeshCoreModulations.ladderId(id))?.name ??
    id;

/// "the mobile node" / "the base node".
String _radioOf(PlanSide side) =>
    side == PlanSide.mobile ? 'the mobile node' : 'the base node';

/// Builds the steps for a valid [intent] (callers run
/// [PlanIntent.validate] first; an invalid intent throws [PlanError]).
///
/// [remoteChanges]: the base is changed over the mesh (Meshtastic remote
/// admin granted and the base heard); otherwise the person walks to it and
/// the app connects over Bluetooth. [protocol] is `'meshtastic'` or
/// `'meshcore'` (MeshCore never changes the base from a distance).
/// [restoreTo] names the setting the radios had before the plan (a preset
/// id or dBm text) when it is already known; the runner fills it in at
/// start otherwise.
List<PlanStep> buildSteps(
  PlanIntent intent, {
  required bool remoteChanges,
  required String protocol,
  String? restoreTo,
}) {
  final problem = intent.validate();
  if (problem != null) throw PlanError(problem);
  final remote = remoteChanges && protocol != protocolMeshcore;
  final b = _Builder(intent, remote: remote, protocol: protocol);
  switch (intent.template) {
    case PlanTemplate.antennas:
    case PlanTemplate.radios:
      b.hardwareTrack();
    case PlanTemplate.reach:
      b.reachTrack();
    case PlanTemplate.rangeSettings:
    case PlanTemplate.txPower:
      b.settingsTrack(restoreTo: restoreTo);
  }
  return b.steps;
}

/// Order of variants over the passes: 0..n-1, then (repeat) n-1..0.
List<(int variant, int pass)> variantOrder(PlanIntent intent) {
  final n = intent.variants.length;
  final order = <(int, int)>[for (var i = 0; i < n; i++) (i, 1)];
  if (intent.repeat) {
    order.addAll([for (var i = n - 1; i >= 0; i--) (i, 2)]);
  }
  return order;
}

/// Minutes the whole plan takes, for the Plan screen: the walks plus a
/// flat allowance per step that needs hands or radios.
int plannedMinutes(PlanIntent intent, List<PlanStep> steps) {
  var min = 0;
  for (final s in steps) {
    switch (s.kind) {
      case StepKind.walk:
        min += (s.params['minutes'] as num?)?.toInt() ?? intent.route.minutes;
      case StepKind.changeRadios:
        min += 4;
      case StepKind.swapHardware:
      case StepKind.switchRadio:
      case StepKind.goTo:
        min += 2;
      case StepKind.preflight:
      case StepKind.settle:
      case StepKind.analyze:
        min += 1;
    }
  }
  return min;
}

class _Builder {
  final PlanIntent intent;
  final bool remote;
  final String protocol;
  final steps = <PlanStep>[];

  _Builder(this.intent, {required this.remote, required this.protocol});

  int get _walkCount => variantOrder(intent).length;
  int _walksSoFar = 0;

  String _name(int i) => variantName(intent, i);

  void _add(
    StepKind kind, {
    int? variant,
    required String title,
    required String instruction,
    required String summary,
    Map<String, dynamic> params = const {},
  }) {
    steps.add(PlanStep(
      ordinal: steps.length,
      kind: kind,
      variant: variant,
      title: title,
      instruction: instruction,
      summary: summary,
      params: params,
    ));
  }

  // ─── Shared steps ────────────────────────────────────────────────────

  void _preflight() {
    final changes = intent.template.changesRadios;
    _add(
      StepKind.preflight,
      title: 'Checking your setup',
      instruction: 'Nothing to do here; the next step starts when every '
          'check passes.',
      summary: changes
          ? (remote
              ? 'Nodes, channel, remote changes allowed, base backup, GPS'
              : 'Nodes, channel, base backup, base location, GPS')
          : 'Nodes, channel, base location, GPS',
    );
  }

  /// Go to the start point. The first time the start point is next to the
  /// base (and becomes the start pin); later the pin from the first walk.
  void _goToStart({required bool first}) {
    _add(
      StepKind.goTo,
      title: first ? 'Go to the start point' : 'Walk to where you started',
      instruction: first
          ? 'Stand next to the base this first time. Every walk starts '
              'from the same spot, so the walks can be compared.'
          : 'Same start point every time makes the walks comparable.',
      summary:
          first ? 'Next to the base this first time' : 'Same spot as before',
      params: const {'target': 'start'},
    );
  }

  /// Stand by the base for a radio change.
  void _goToBase({required bool first}) {
    _add(
      StepKind.goTo,
      title: first ? 'Stand within sight of the base' : 'Back to the base',
      instruction: remote
          ? 'Radio changes happen where the link is strongest, so a problem '
              'is cheapest to fix.'
          : 'The app connects to the base over Bluetooth to change it, so it '
              'needs to be within about 20 m.',
      summary: first
          ? 'Radio changes happen where the link is strongest'
          : 'Same spot as before',
      params: const {'target': 'base'},
    );
  }

  void _walk(int? variant, int pass, {bool reach = false}) {
    _walksSoFar++;
    final n = _walksSoFar;
    final minutes = intent.route.minutes;
    final who = intent.route.kind == RouteKind.drive ? 'Drive' : 'Walk';
    final String title, instruction, summary;
    if (reach) {
      title = '$who until the base is lost, then come back';
      instruction = 'Keep going until the pings stop being answered and the '
          'app says the base is out of range, then turn around. The app '
          'records the whole way.';
      summary = '≈$minutes min · the app records';
    } else if (n == 1) {
      title = '$who the route';
      instruction = '$who where you want coverage checked. The app records '
          'and remembers this route for the next walk.';
      summary = '≈$minutes min · the app records';
    } else if (pass == 1) {
      title = '$who the same route';
      instruction = 'Follow the dashed line of your first walk. "Done '
          'walking" lights at 80 % route match.';
      summary = 'Follow the ghost line · route match shown live';
    } else {
      title = '$who the same route again';
      instruction = 'Second pass, other order. Follow the dashed line; '
          '"Done walking" lights at 80 % route match.';
      summary = 'Follow the ghost line · other order';
    }
    _add(
      StepKind.walk,
      variant: variant,
      title: title,
      instruction: instruction,
      summary: summary,
      params: {
        'minutes': minutes,
        'pass': pass,
        'walk': n,
        'walks': _walkCount,
      },
    );
  }

  void _analyze() {
    final airtime = intent.template == PlanTemplate.rangeSettings;
    _add(
      StepKind.analyze,
      title: intent.template == PlanTemplate.reach ? 'Measure' : 'Compare',
      instruction: intent.template == PlanTemplate.reach
          ? 'Farthest answered ping, where the base was lost, signal by '
              'distance.'
          : 'Cell by cell on the shared route, farthest reach, pings '
              'answered${airtime ? ', airtime per ping' : ''}.',
      summary: intent.template == PlanTemplate.reach
          ? 'Farthest reach, where the base was lost'
          : airtime
              ? 'Reach, margin, airtime per ping'
              : 'Cell by cell, farthest reach, pings answered',
    );
  }

  // ─── Tracks ──────────────────────────────────────────────────────────

  void hardwareTrack() {
    _preflight();
    int? onNow;
    var firstGoTo = true;
    for (final (v, pass) in variantOrder(intent)) {
      if (onNow != v) {
        if (intent.template == PlanTemplate.antennas) {
          _swap(v, first: onNow == null);
        } else {
          _switchRadio(v);
        }
        onNow = v;
      }
      _goToStart(first: firstGoTo);
      firstGoTo = false;
      _walk(v, pass);
    }
    _analyze();
  }

  void reachTrack() {
    _preflight();
    _goToStart(first: true);
    _walk(0, 1, reach: true);
    _analyze();
  }

  void settingsTrack({String? restoreTo}) {
    _preflight();
    int? onNow;
    var first = true;
    for (final (v, pass) in variantOrder(intent)) {
      if (onNow != v) {
        _goToBase(first: first);
        _change(v);
        onNow = v;
      } else {
        _goToStart(first: false);
      }
      first = false;
      _walk(v, pass);
    }
    _goToBase(first: false);
    _restore(restoreTo);
    _analyze();
  }

  // ─── Variant steps ───────────────────────────────────────────────────

  void _swap(int v, {required bool first}) {
    final name = _name(v);
    final radio = _radioOf(intent.side);
    _add(
      StepKind.swapHardware,
      variant: v,
      title: 'Put the $name on',
      instruction:
          'On $radio${intent.side == PlanSide.mobile ? ' (the one in your hand)' : ''}. '
          'Screw it on hand-tight, then stand it upright.',
      summary:
          first ? 'On $radio, hand-tight, upright' : 'Same node, same spot',
      params: {'side': intent.side.name, 'name': name},
    );
  }

  void _switchRadio(int v) {
    final name = _name(v);
    _add(
      StepKind.switchRadio,
      variant: v,
      title: 'Connect the $name',
      instruction: 'Pick $name in the connect list. The step finishes when '
          'it is connected and set up as the mobile node.',
      summary: 'Same antenna, same spot',
      params: {'name': name},
    );
  }

  /// What a `changeRadios` step applies, from the variant.
  Map<String, dynamic> _changeParams(int v) {
    final raw = intent.variants[v].trim();
    return switch (intent.template) {
      PlanTemplate.txPower => {
          'txPower': int.parse(raw),
          'side': intent.side.name,
        },
      _ => {'preset': raw},
    };
  }

  String _changeSummary({required bool baseChanges}) {
    if (!baseChanges) return 'Your node only · over Bluetooth, restarts';
    return remote
        ? 'Base changed from here, then yours · checks the base is heard'
        : 'Walk to the base; the app connects over Bluetooth, then changes '
            'yours';
  }

  String _changeInstruction({required bool baseChanges}) {
    if (!baseChanges) {
      return 'Only your node changes. It restarts and the app reconnects.';
    }
    if (remote) {
      return 'The base first, from here over the mesh, then yours. Stay '
          'here until the base is heard again.';
    }
    return protocol == protocolMeshcore
        ? 'MeshCore: the base is changed by walking to it; the app connects '
            'over Bluetooth, then changes your node. Stay here until the '
            'base is heard again.'
        : 'The app connects to the base over Bluetooth and changes it, then '
            'your node. Stay here until the base is heard again.';
  }

  bool get _baseChanges =>
      intent.template == PlanTemplate.rangeSettings ||
      intent.side == PlanSide.base;

  void _change(int v) {
    final name = _name(v);
    final baseChanges = _baseChanges;
    final title = intent.template == PlanTemplate.rangeSettings
        ? 'Switch both nodes to $name'
        : 'Set ${_radioOf(intent.side)} to $name';
    _add(
      StepKind.changeRadios,
      variant: v,
      title: title,
      instruction: _changeInstruction(baseChanges: baseChanges),
      summary: _changeSummary(baseChanges: baseChanges),
      params: _changeParams(v),
    );
  }

  void _restore(String? restoreTo) {
    final known = restoreTo != null && restoreTo.trim().isNotEmpty;
    final name = !known
        ? null
        : intent.template == PlanTemplate.txPower
            ? '${restoreTo.trim()} dBm'
            : presetDisplayName(restoreTo.trim());
    final what = intent.template == PlanTemplate.rangeSettings
        ? 'both nodes'
        : _radioOf(intent.side);
    _add(
      StepKind.changeRadios,
      title: name == null
          ? 'Put $what back the way '
              '${what == 'both nodes' ? 'they were' : 'it was'}'
          : 'Put $what back on $name',
      instruction: 'Your everyday setting, so nothing is left changed when '
          'the test is over.',
      summary: 'Your everyday setting',
      params: {
        'restore': true,
        if (known && intent.template == PlanTemplate.txPower)
          'txPower': int.tryParse(restoreTo.trim()),
        if (known && intent.template != PlanTemplate.txPower)
          'preset': restoreTo.trim(),
        if (intent.template == PlanTemplate.txPower) 'side': intent.side.name,
      },
    );
  }
}
