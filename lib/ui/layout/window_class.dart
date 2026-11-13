// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/widgets.dart';

/// How much room the app's window has, decided by its size alone, never by
/// the device (docs/design/ipad/README.md). An iPad in a narrow Split View
/// pane is [compact]; an iPhone Duo unfolded is [wide]; a phone turned
/// sideways stays [compact] (too short), keeping today's phone layout.
enum WindowClass {
  /// The phone layout: bottom tab bar, bottom sheets.
  compact,

  /// Room for a navigation rail and centred columns, but the maps keep
  /// their bottom sheets (too narrow for a map plus a side column).
  wide,

  /// Wide and wide enough for a map with a side panel next to it.
  sidePanel;

  /// At least this wide (logical pixels) for [wide].
  static const double wideMinWidth = 600;

  /// At least this tall for [wide]: an iPhone in landscape (≈ 440) is not.
  static const double wideMinHeight = 480;

  /// At least this wide for [sidePanel]: a map beside a ~400 pt column
  /// needs phone width (~400) itself, plus the rail. iPad mini portrait
  /// (744) overflowed the Live map's base pill and an iPad Pro 10.5
  /// (834) left Coverage ~330 pt of map (2026-11-10); those dock under
  /// the map or keep the sheet instead.
  static const double sidePanelMinWidth = 860;

  /// Widest a single column of settings-like content grows to.
  static const double columnMaxWidth = 640;

  static WindowClass forSize(Size size) {
    if (size.width < wideMinWidth || size.height < wideMinHeight) {
      return compact;
    }
    return size.width >= sidePanelMinWidth ? sidePanel : wide;
  }

  static WindowClass of(BuildContext context) =>
      forSize(MediaQuery.sizeOf(context));

  bool get isWide => this != compact;
  bool get hasSidePanel => this == sidePanel;
}

/// Centres [child] in a column at most [maxWidth] wide when the window is
/// wide; on a compact window it returns [child] untouched, so the phone
/// layout doesn't change by a pixel.
class WideColumn extends StatelessWidget {
  const WideColumn({
    super.key,
    required this.child,
    this.maxWidth = WindowClass.columnMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!WindowClass.of(context).isWide) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
