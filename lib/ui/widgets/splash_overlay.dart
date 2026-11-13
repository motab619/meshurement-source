// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

/// The launch splash (`assets/brand/splash.png`, the same picture as the
/// native LaunchScreen) held briefly over the app, then faded out, so the
/// hand-over from the launch screen is smooth and the logo is seen even on
/// a fast start. Brief by design (2026-11-05, held a little longer the same day): [hold] then [fade].
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({
    super.key,
    required this.child,
    this.hold = const Duration(milliseconds: 1500),
    this.fade = const Duration(milliseconds: 400),
  });

  final Widget child;
  final Duration hold, fade;

  /// Background of the splash art's edges (also the LaunchScreen colour).
  static const background = Color(0xFF01011A);

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> {
  bool _fading = false, _gone = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.hold, () {
      if (mounted) setState(() => _fading = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _fading ? 0 : 1,
            duration: widget.fade,
            onEnd: () => setState(() => _gone = true),
            child: const ColoredBox(
              color: SplashOverlay.background,
              child: Image(
                image: AssetImage('assets/brand/splash.png'),
                fit: BoxFit.contain,
                semanticLabel: 'Meshurement',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
