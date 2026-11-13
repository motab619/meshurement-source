// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import '../../utils/app_info.dart';
import 'splash_overlay.dart';

/// The Meshurement wordmark (`assets/brand/wordmark.png`) on the splash's
/// navy panel. The art's "Mesh" is white, so it always sits on navy, in the
/// light theme too. Screen readers hear [AppInfo.displayName].
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.height = 56});

  /// Height of the wordmark image; the panel adds padding around it.
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: height * 0.3, vertical: height * 0.22),
      decoration: BoxDecoration(
        color: SplashOverlay.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Image.asset(
        'assets/brand/wordmark.png',
        height: height,
        fit: BoxFit.contain,
        semanticLabel: AppInfo.displayName,
      ),
    );
  }
}
