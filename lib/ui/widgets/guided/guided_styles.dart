// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// Text styles and small pieces every guided-test screen shares (the
/// design mock: `docs/design/guided-test/concept.html`).
extension GuidedStyles on BuildContext {
  /// Mono orange caption with 1 px tracking ("WHAT DO YOU WANT TO FIND
  /// OUT?", "STEP 3 OF 7").
  TextStyle get guidedCaption => readout.label.copyWith(
        fontFamily: ReadoutStyles.monoFamily,
        fontSize: 12,
        letterSpacing: 1.0,
        color: Theme.of(this).colorScheme.primary,
      );

  /// Mono muted label under a readout ("MINUTES", "TO THE BASE").
  TextStyle get guidedMonoLabel => readout.label.copyWith(
        fontFamily: ReadoutStyles.monoFamily,
        fontSize: 11,
        letterSpacing: 1.0,
        fontWeight: FontWeight.w400,
        color: status.muted,
      );

  /// Mono text at body size (the band's "SNR +7.5", the distance pill).
  TextStyle get guidedMono => readout.value.copyWith(fontWeight: FontWeight.w400);

  /// The screen title (24 px bold, line height 1.2).
  TextStyle get guidedTitle =>
      Theme.of(this).textTheme.headlineSmall!.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.2,
          );

  /// The one or two instruction sentences on a Run step (20 px).
  TextStyle get guidedBig => Theme.of(this)
      .textTheme
      .bodyLarge!
      .copyWith(fontSize: 20, height: 1.35);

  /// Footnotes (12 px, muted).
  TextStyle get guidedFine =>
      Theme.of(this).textTheme.bodySmall!.copyWith(color: status.muted);

  /// Soft-ink paragraph.
  TextStyle get guidedSoft => Theme.of(this)
      .textTheme
      .bodyMedium!
      .copyWith(color: Theme.of(this).colorScheme.onSurfaceVariant);
}

/// Key taps tick; a completed step thumps.
abstract final class GuidedHaptics {
  static void tap() => HapticFeedback.selectionClick();
  static void stepDone() => HapticFeedback.mediumImpact();
}

/// The one primary key of a screen. 56 px on the Run screen (gloves,
/// outdoors), 44 px elsewhere.
class GuidedKey extends StatelessWidget {
  const GuidedKey(
    this.label, {
    super.key,
    required this.onPressed,
    this.tall = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool tall;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final status = context.status;
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: Size(double.infinity, tall ? 56 : 44),
        backgroundColor: danger ? status.danger : null,
        foregroundColor: danger ? status.onDanger : null,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      onPressed: onPressed == null
          ? null
          : () {
              GuidedHaptics.tap();
              onPressed!();
            },
      child: Text(label),
    );
  }
}

/// A secondary key: hairline outline, regular weight, 44 px.
class GuidedGhostKey extends StatelessWidget {
  const GuidedGhostKey(this.label, {super.key, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 44),
      ),
      onPressed: onPressed == null
          ? null
          : () {
              GuidedHaptics.tap();
              onPressed!();
            },
      child: Text(label),
    );
  }
}

/// Cyan inline text link ("Pause", "I'm stuck", "Finish anyway").
class GuidedTextLink extends StatelessWidget {
  const GuidedTextLink(this.label, {super.key, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.secondary,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        minimumSize: const Size(44, 36),
        textStyle: const TextStyle(fontSize: 14),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

/// Card with the app's surface, hairline and 12 px radius (Material's
/// Card, without its margin).
class GuidedCard extends StatelessWidget {
  const GuidedCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Footer under a screen's body: hairline on top, the keys, safe area.
class GuidedFooter extends StatelessWidget {
  const GuidedFooter({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A variant name drawn as a tappable value: dashed cyan underline.
TextSpan variantValueSpan(BuildContext context, String name,
    {VoidCallback? onTap}) {
  final scheme = Theme.of(context).colorScheme;
  return TextSpan(
    text: name,
    style: TextStyle(
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dashed,
      decorationColor: scheme.secondary,
      color: scheme.onSurface,
    ),
    recognizer: onTap == null ? null : (TapGestureRecognizer()..onTap = onTap),
  );
}
