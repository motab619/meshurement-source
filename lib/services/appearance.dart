// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

/// App and map look (Settings → Display → Appearance and the maps' layers
/// button, pref `app_appearance`; field test 2026-11-08: the map read too
/// dark in sunlight). Automatic follows the phone; Bright forces the light
/// theme, never dims the map and softens the Terrain shading; Night forces
/// the dark theme and dims every base map; Automatic dims the Live map while
/// the app is dark.
enum Appearance {
  automatic('Automatic'),
  bright('Bright'),
  night('Night');

  const Appearance(this.label);
  final String label;

  static Appearance fromName(String? name) => Appearance.values
      .firstWhere((a) => a.name == name, orElse: () => automatic);

  ThemeMode get themeMode => switch (this) {
        automatic => ThemeMode.system,
        bright => ThemeMode.light,
        night => ThemeMode.dark,
      };

  /// Opacity of the Terrain hillshade layer.
  double get hillshadeOpacity => this == bright ? 0.45 : 1.0;

  /// Whether a base map is dimmed (`mapDimFilter`). [dimInDark]: this map
  /// dims in Automatic while the app is [dark] (the Live map).
  bool dimsMap({required bool dimInDark, required bool dark}) => switch (this) {
        night => true,
        bright => false,
        automatic => dimInDark && dark,
      };
}
