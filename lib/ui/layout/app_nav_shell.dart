// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

/// One tab of the app's shell.
class AppNavDestination {
  const AppNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// The app's tab shell: the bottom [NavigationBar] on every window size.
/// A side rail on wide windows was tried and dropped (Andy, 2026-11-10: it
/// takes ~80 pt of width an upright iPad can't spare). Kept as its own
/// widget so the shell can be tested at any size.
class AppNavShell extends StatelessWidget {
  const AppNavShell({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.destinations,
    required this.body,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<AppNavDestination> destinations;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final divider =
        BorderSide(color: Theme.of(context).colorScheme.outlineVariant);
    return Scaffold(
      body: body,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: divider)),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelect,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      ),
    );
  }
}
