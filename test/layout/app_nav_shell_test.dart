// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mesh_analyzer/ui/layout/app_nav_shell.dart';
import 'package:mesh_analyzer/ui/layout/window_class.dart';

import 'window_sizes.dart';

/// The tab shell follows the window, not the device
/// (docs/design/ipad/README.md): bottom bar on a phone (either way up), a
/// rail on an iPad or an unfolded iPhone Duo, and the tabs keep their state
/// when the window changes between the two.
void main() {
  group('WindowClass.forSize', () {
    test('phones stay compact, portrait and landscape', () {
      expect(WindowClass.forSize(phone), WindowClass.compact);
      expect(WindowClass.forSize(phoneLandscape), WindowClass.compact);
      expect(WindowClass.forSize(phoneMaxLandscape), WindowClass.compact);
      expect(WindowClass.forSize(duoOuter), WindowClass.compact);
    });

    test('iPad Slide Over and a third of Split View stay compact', () {
      expect(WindowClass.forSize(const Size(375, 1032)), WindowClass.compact);
    });

    test('upright Duo and smaller iPads are wide; 860 up gets the side panel',
        () {
      expect(WindowClass.forSize(duoInner), WindowClass.wide);
      expect(WindowClass.forSize(iPadMini), WindowClass.wide);
      expect(WindowClass.forSize(iPadPro105), WindowClass.wide);
      expect(WindowClass.forSize(duoInnerLandscape), WindowClass.sidePanel);
      expect(WindowClass.forSize(iPad13Landscape), WindowClass.sidePanel);
    });
  });

  Widget shell({required int index, ValueChanged<int>? onSelect}) =>
      MaterialApp(
        home: AppNavShell(
          selectedIndex: index,
          onSelect: onSelect ?? (_) {},
          destinations: const [
            AppNavDestination(
                icon: Icons.radar_outlined,
                selectedIcon: Icons.radar,
                label: 'Live'),
            AppNavDestination(
                icon: Icons.layers_outlined,
                selectedIcon: Icons.layers,
                label: 'Coverage'),
            AppNavDestination(
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings,
                label: 'Settings'),
          ],
          body: const _Counter(),
        ),
      );

  for (final (name, size) in [
    ('phone', phone),
    ('phone landscape', phoneLandscape),
    ('Duo folded', duoOuter),
    ('Duo unfolded', duoInner),
    ('iPad Pro 10.5', iPadPro105),
    ('iPad 13 landscape', iPad13Landscape),
  ]) {
    testWidgets('$name: the bottom tab bar, no rail', (tester) async {
      await setWindow(tester, size);
      int? picked;
      await tester.pumpWidget(shell(index: 1, onSelect: (i) => picked = i));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      await tester.tap(find.text('Settings'));
      expect(picked, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unfolding and folding keeps the tab state', (tester) async {
    await setWindow(tester, duoOuter);
    await tester.pumpWidget(shell(index: 0));
    await tester.tap(find.byKey(const ValueKey('counter')));
    await tester.pump();
    expect(find.text('taps 1'), findsOneWidget);
    for (final size in [duoInner, iPad13Landscape, duoOuter]) {
      await setWindow(tester, size);
      await tester.pump();
      expect(find.text('taps 1'), findsOneWidget);
    }
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(
          key: const ValueKey('counter'),
          onPressed: () => setState(() => _taps++),
          child: Text('taps $_taps'),
        ),
      );
}
