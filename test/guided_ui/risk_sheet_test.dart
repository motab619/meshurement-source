// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mesh_analyzer/providers.dart';
import 'package:mesh_analyzer/ui/widgets/guided/risk_sheet.dart';

import 'fakes.dart';

/// A page with one button that opens the sheet and records the choice.
class _Host extends StatefulWidget {
  const _Host({this.reminder = false});

  final bool reminder;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  RiskChoice? choice;
  bool closed = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(children: [
            TextButton(
              onPressed: () async {
                choice = await showRiskSheet(context,
                    targetName: 'Long Fast',
                    baseDistanceM: 340,
                    reminder: widget.reminder);
                setState(() => closed = true);
              },
              child: const Text('open'),
            ),
            if (closed) Text('choice=${choice?.name}'),
          ]),
        ),
      );
}

void main() {
  testWidgets('the copy, the distance pill, the checkbox gating the key, '
      'and the pref on confirm', (tester) async {
    final env = await GuidedEnv.create();
    await tester.pumpWidget(env.app(const _Host()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Changing the base from here'), findsOneWidget);
    expect(find.textContaining('tell the base node to switch to'), findsOneWidget);
    expect(find.textContaining('The base restarts to do it.'), findsOneWidget);
    expect(find.textContaining("fix it in Node Setup"), findsOneWidget);
    expect(find.text('340 m'), findsOneWidget);
    expect(find.textContaining("saves the base's settings first"), findsOneWidget);
    expect(find.text('I can get to the base if I need to'), findsOneWidget);

    FilledButton go() => tester.widget<FilledButton>(find.ancestor(
        of: find.text('Change base from here'),
        matching: find.byType(FilledButton)));
    expect(go().onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('risk-check')));
    await tester.pump();
    expect(go().onPressed, isNotNull);
    await tester.tap(find.text('Change base from here'));
    await tester.pumpAndSettle();

    expect(find.text('choice=changeHere'), findsOneWidget);
    expect(env.prefs.getBool(guidedRiskSeenKey), isTrue);
    await unmount(tester);
    await env.close();
  });

  testWidgets('walk instead: no pref written', (tester) async {
    final env = await GuidedEnv.create();
    await tester.pumpWidget(env.app(const _Host()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'll walk to it instead"));
    await tester.pumpAndSettle();
    expect(find.text('choice=walkInstead'), findsOneWidget);
    expect(env.prefs.getBool(guidedRiskSeenKey), isNull);
    await unmount(tester);
    await env.close();
  });

  testWidgets('from the ⓘ: the box is pre-ticked', (tester) async {
    final env = await GuidedEnv.create(prefs: {guidedRiskSeenKey: true});
    await tester.pumpWidget(env.app(const _Host(reminder: true)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final box = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('risk-check')));
    expect(box.value, isTrue);
    await unmount(tester);
    await env.close();
  });
}
