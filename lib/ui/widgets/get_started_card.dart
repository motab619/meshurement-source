// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/radio/radio_types.dart';
import '../../demo/demo_mode.dart';
import '../../providers.dart';
import '../../services/last_radio.dart';
import '../../services/radio_roles.dart';
import '../../utils/user_errors.dart';
import '../screens/guided/guided_test_flow.dart';
import '../screens/radio_setup_screen.dart';
import '../theme/app_theme.dart';
import 'connection_banner.dart' show showConnectDialog;
import 'create_map_dialog.dart';

/// One step of the checklist: what to do, what has happened, and whether
/// it is done.
class GetStartedStep {
  final String title;

  /// Shown under the title: the hint while it is still to do, what was
  /// done once it is.
  final String detail;
  final bool done;

  /// Label of the button on the current step.
  final String action;

  const GetStartedStep({
    required this.title,
    required this.detail,
    required this.done,
    required this.action,
  });
}

/// The four steps from a fresh install to a first recorded walk, each
/// read from real state: a radio connected (now, or ever), Radio Setup
/// run on both radios, a map made, a session recorded.
List<GetStartedStep> getStartedSteps({
  required RadioConnectionState link,
  required RadioRoles roles,
  required RadioDescriptor? lastRadio,
  required int mapCount,
  required int sessionCount,
  String Function(int nodeNum)? nameOf,
}) {
  // The radio's name when known ("MeshTest Base"), else its short id.
  String name(int n) {
    final known = nameOf?.call(n);
    return known == null || known.isEmpty ? shortNodeId(n) : known;
  }

  final base = roles.nodeOf(RadioRole.base);
  final mobile = roles.nodeOf(RadioRole.mobile);
  final connected = link == RadioConnectionState.ready ||
      lastRadio != null ||
      base != null ||
      mobile != null;
  final lastName = lastRadio == null || lastRadio.name.isEmpty
      ? 'A node has been connected'
      : lastRadio.name;
  String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
  return [
    GetStartedStep(
      title: 'Connect one of your nodes',
      detail: connected
          ? (link == RadioConnectionState.ready
              ? 'Connected: $lastName'
              : lastName)
          : 'Pair over Bluetooth. Either node will do for now.',
      done: connected,
      action: 'Connect',
    ),
    GetStartedStep(
      title: 'Run Node Setup',
      detail: base != null && mobile != null
          ? 'Base: ${name(base)} · Mobile: ${name(mobile)}'
          : base != null
              ? 'Base set. The mobile still needs doing.'
              : mobile != null
                  ? 'Mobile set. The base still needs doing.'
                  : 'Puts both nodes alone on a private channel and names '
                      'one the base, one the mobile. A few minutes; '
                      'Meshtastic nodes restart.',
      done: base != null && mobile != null,
      action: 'Open Node Setup',
    ),
    GetStartedStep(
      title: 'Make a map',
      detail: mapCount > 0
          ? plural(mapCount, 'map')
          : 'A map is a place: where the base sits. Sessions collect under it.',
      done: mapCount > 0,
      action: 'New map',
    ),
    GetStartedStep(
      title: 'Record your first walk',
      detail: sessionCount > 0
          ? plural(sessionCount, 'session')
          : 'Leave the base behind, take the mobile and the phone, then tap '
              'Start session on the Live tab.',
      done: sessionCount > 0,
      action: 'Go to Live',
    ),
  ];
}

/// True while the checklist shows and its current step is the last one
/// (a radio connected, Radio Setup run, a map made, no session yet). The
/// start form says "Last step…" then, and only then: with earlier steps
/// open the line would contradict "Connect to your radio first" under it
/// (seen on the simulator 2026-11-08).
bool onLastGetStartedStep(WidgetRef ref) {
  if (DemoMode.enabled || ref.watch(checklistHiddenProvider)) return false;
  final sessions = ref.watch(sessionCountProvider).valueOrNull;
  if (sessions == null) return false;
  final steps = getStartedSteps(
    link: ref.watch(meshLinkStateProvider).valueOrNull ??
        RadioConnectionState.disconnected,
    roles: ref.watch(radioRolesProvider),
    lastRadio: LastRadio(ref.watch(sharedPreferencesProvider)).load(),
    mapCount: ref.watch(coverageMapsProvider).valueOrNull?.length ?? 0,
    sessionCount: sessions,
  );
  return steps.indexWhere((s) => !s.done) == steps.length - 1;
}

/// True once the first two checklist steps are done (a radio connected,
/// Radio Setup run on both: both roles set), or when the checklist no
/// longer shows (hidden, or demo mode). The Coverage tab's "Plan a test"
/// is the primary button only then: before it, a guided test can't run
/// and the checklist's current step is the thing to tap (new-user
/// walkthrough 2026-11-08).
bool radioSetupDone(WidgetRef ref) {
  if (DemoMode.enabled || ref.watch(checklistHiddenProvider)) return true;
  final steps = getStartedSteps(
    link: ref.watch(meshLinkStateProvider).valueOrNull ??
        RadioConnectionState.disconnected,
    roles: ref.watch(radioRolesProvider),
    lastRadio: LastRadio(ref.watch(sharedPreferencesProvider)).load(),
    mapCount: 0,
    sessionCount: 0,
  );
  return steps[0].done && steps[1].done;
}

/// A radio's name from the radio's node list or the stored nodes.
String Function(int) _nameOf(WidgetRef ref) {
  final live = ref.read(meshRadioProvider).nodes;
  final stored = ref.watch(nodesProvider).valueOrNull ?? const [];
  return (n) {
    final l = live[n]?.longName ?? '';
    if (l.isNotEmpty) return l;
    for (final node in stored) {
      if (node.nodeId == n) return node.longName;
    }
    return '';
  };
}

/// Hide the checklist everywhere (Coverage card and the Live pill share
/// the same preference). About → Show checklist again brings it back.
Future<void> hideGetStarted(WidgetRef ref) async {
  ref.read(checklistHiddenProvider.notifier).state = true;
  await ref
      .read(sharedPreferencesProvider)
      .setBool(onboardingChecklistHiddenKey, true);
}

/// Sessions recorded, read once and again when a session starts or ends.
/// The Live pill uses this rather than the live [sessionCountProvider]
/// stream, so the Live map holds no extra database watcher while it
/// records.
final _liveSessionCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final maps = await ref.watch(coverageMapsProvider.future);
  ref.watch(activeSessionProvider); // re-count when a session starts or ends
  final db = ref.watch(databaseProvider);
  var n = 0;
  for (final m in maps) {
    n += (await db.getSessionsForMap(m.id)).length;
  }
  return n;
});

/// The Live tab's pointer to the checklist: one line naming the current
/// step ("Get started · 2 of 4: Run Radio Setup"). Tapping it opens the
/// Coverage tab, where the full card is; on the last step (record a walk)
/// it calls [onStartSession] instead. Hidden with the card (same
/// preference), once every step is done, and in demo mode.
class GetStartedPill extends ConsumerWidget {
  final VoidCallback onStartSession;
  const GetStartedPill({super.key, required this.onStartSession});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (DemoMode.enabled || ref.watch(checklistHiddenProvider)) {
      return const SizedBox.shrink();
    }
    final prefs = ref.watch(sharedPreferencesProvider);
    // Wait for the session count, so the pill doesn't flash for returning
    // users.
    // Nothing to point at while a session records.
    if (ref.watch(activeSessionProvider).valueOrNull != null) {
      return const SizedBox.shrink();
    }
    final sessions = ref.watch(_liveSessionCountProvider).valueOrNull;
    if (sessions == null) return const SizedBox.shrink();
    final steps = getStartedSteps(
      link: ref.watch(meshLinkStateProvider).valueOrNull ??
          RadioConnectionState.disconnected,
      roles: ref.watch(radioRolesProvider),
      lastRadio: LastRadio(prefs).load(),
      mapCount: ref.watch(coverageMapsProvider).valueOrNull?.length ?? 0,
      sessionCount: sessions,
    );
    final current = steps.indexWhere((s) => !s.done);
    if (current < 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final chrome = theme.mapChrome;
    final label =
        'Get started · ${current + 1} of ${steps.length}: ${steps[current].title}';
    return Material(
      color: chrome.overlay,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(chrome.radius),
        side: BorderSide(color: chrome.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: current == 3
                  ? '$label. Opens the session panel.'
                  : '$label. Opens the checklist on the Coverage tab.',
              excludeSemantics: true,
              child: InkWell(
                key: const ValueKey('get-started-pill'),
                onTap: () {
                  if (current == 3) {
                    onStartSession();
                  } else {
                    ref.read(mainTabProvider.notifier).state = 1;
                  }
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(label,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: chrome.onOverlay)),
                        ),
                        Icon(Icons.chevron_right, color: chrome.onOverlayMuted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Hide checklist',
            icon: Icon(Icons.close, size: 18, color: chrome.onOverlayMuted),
            onPressed: () => hideGetStarted(ref),
          ),
        ],
      ),
    );
  }
}

/// "Get started" checklist at the top of the Coverage tab: four steps that
/// tick themselves off as the real thing happens, one button for the
/// current step. Hidden once dismissed (About → Show checklist again
/// brings it back), for existing installs, and in demo mode.
class GetStartedCard extends ConsumerWidget {
  const GetStartedCard({super.key});

  Future<void> _hide(WidgetRef ref) => hideGetStarted(ref);

  void _act(BuildContext context, WidgetRef ref, int step) {
    switch (step) {
      case 0:
        showConnectDialog(context);
      case 1:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RadioSetupScreen()),
        );
      case 2:
        showCreateMapDialog(context, ref);
      case 3:
        // Straight to the form, not just the tab.
        ref.read(openStartFormProvider.notifier).state = true;
        ref.read(mainTabProvider.notifier).state = 0;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (DemoMode.enabled || ref.watch(checklistHiddenProvider)) {
      return const SizedBox.shrink();
    }
    final prefs = ref.watch(sharedPreferencesProvider);
    final steps = getStartedSteps(
      link: ref.watch(meshLinkStateProvider).valueOrNull ??
          RadioConnectionState.disconnected,
      roles: ref.watch(radioRolesProvider),
      lastRadio: LastRadio(prefs).load(),
      mapCount: ref.watch(coverageMapsProvider).valueOrNull?.length ?? 0,
      sessionCount: ref.watch(sessionCountProvider).valueOrNull ?? 0,
      nameOf: _nameOf(ref),
    );
    final current = steps.indexWhere((s) => !s.done);
    final allDone = current < 0;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kicker = theme.readout.label.copyWith(
      fontFamily: ReadoutStyles.monoFamily,
      fontSize: 12,
      letterSpacing: 1.0,
      color: scheme.primary,
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    allDone
                        ? 'ALL SET'
                        : 'GET STARTED · ${current + 1}/${steps.length}',
                    style: kicker,
                  ),
                ),
                IconButton(
                  tooltip: 'Hide checklist',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => _hide(ref),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                allDone
                    ? "You've recorded a session"
                    : 'Your first coverage test',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            if (allDone) ...[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  'Open a map to see where the signal held and where it gave '
                  'out. Record a second walk and the two can be compared.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => _hide(ref),
                  child: const Text('Done'),
                ),
              ),
            ] else
              for (var i = 0; i < steps.length; i++)
                _StepRow(
                  number: i + 1,
                  step: steps[i],
                  isCurrent: i == current,
                  onAction: () => _act(context, ref, i),
                  // The last step has a second way in: the guided test.
                  secondAction: i == 3 ? 'Walk me through a test' : null,
                  onSecondAction:
                      i == 3 ? () => GuidedTestFlow.open(context) : null,
                ),
          ],
        ),
      ),
    );
  }
}

/// A numbered line: mono number (a tick once done, orange while current,
/// muted when still ahead), title, detail, and a button on every step not
/// yet done (filled on the current one, outlined on those ahead), plus
/// the second button on the current
/// step.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.step,
    required this.isCurrent,
    required this.onAction,
    this.secondAction,
    this.onSecondAction,
  });

  final int number;
  final GetStartedStep step;
  final bool isCurrent;
  final VoidCallback onAction;

  /// Optional second key on the current step.
  final String? secondAction;
  final VoidCallback? onSecondAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ahead = !step.done && !isCurrent;
    final muted = scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: step.done
                ? Icon(Icons.check, size: 18, color: scheme.primary)
                : Text(
                    number.toString().padLeft(2, '0'),
                    style: theme.readout.label.copyWith(
                      fontFamily: ReadoutStyles.monoFamily,
                      fontSize: 14,
                      color: isCurrent ? scheme.primary : muted,
                    ),
                  ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: ahead ? muted : null,
                    decoration: step.done ? TextDecoration.lineThrough : null,
                    decorationColor: muted,
                  ),
                ),
                if (!ahead) ...[
                  const SizedBox(height: 2),
                  Text(
                    step.detail,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
                // Every step still to do has its button, so they can be
                // taken out of order (first run 2026-11-06: with Radio
                // Setup half done, "Make a map" had no way in). The
                // current one is filled, the ones ahead outlined.
                if (!step.done) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (isCurrent)
                        FilledButton.tonal(
                          onPressed: onAction,
                          child: Text(step.action),
                        )
                      else
                        OutlinedButton(
                          onPressed: onAction,
                          child: Text(step.action),
                        ),
                      if (secondAction != null && isCurrent)
                        OutlinedButton(
                          onPressed: onSecondAction,
                          child: Text(secondAction!),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
