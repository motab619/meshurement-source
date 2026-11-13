// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers.dart';
import '../../utils/constants.dart';
import '../../utils/link_margin.dart';
import '../../utils/signal_color_mapper.dart';
import '../theme/app_theme.dart';

/// Preference: the Live tab legend is collapsed to a single chip.
const prefLegendCollapsed = 'signal_legend_collapsed';

/// The margin bands ([MarginBand], the one scale shared with the Field
/// Report and KML), strongest first: (label, a link margin in dB above the
/// preset's decode limit that shows the band's colour, RSSI dBm for the
/// RSSI colour mode). The colours come from [SignalColorMapper], so the
/// legend always matches the map dots.
final signalLevels = [
  for (final (b, dbm) in [
    (MarginBand.strong, -70),
    (MarginBand.good, -95),
    (MarginBand.weak, -115),
    (MarginBand.below, -135),
  ])
    (b.label, b.colourMarginDb, dbm),
];

/// Small key for the dot colours on the Live map: swatch plus a word, so
/// colour is not the only cue. Tap to collapse or expand.
class SignalLegend extends ConsumerStatefulWidget {
  /// Explain the two dot sizes. Only when a relayed (small) dot is on the
  /// map; with relaying off the note would describe something not shown.
  final bool showRelayedNote;

  const SignalLegend({super.key, this.showRelayedNote = false});

  @override
  ConsumerState<SignalLegend> createState() => _SignalLegendState();
}

class _SignalLegendState extends ConsumerState<SignalLegend> {
  late bool _collapsed;

  @override
  void initState() {
    super.initState();
    _collapsed = _prefs.getBool(prefLegendCollapsed) ?? false;
  }

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  void _toggle() {
    setState(() => _collapsed = !_collapsed);
    try {
      _prefs.setBool(prefLegendCollapsed, _collapsed);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final rssi = _prefs.getString(AppConstants.prefColorMetric) == 'rssi';
    final title = rssi ? 'RSSI' : 'Margin';
    final theme = Theme.of(context);
    final chrome = theme.mapChrome;
    return Semantics(
      button: true,
      label: _collapsed
          ? 'Signal color legend, collapsed. Tap to expand.'
          : 'Signal color legend. Tap to collapse.',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: _toggle,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: chrome.panel,
              child: _collapsed
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final l in signalLevels) _swatch(l, rssi, chrome),
                      const SizedBox(width: 6),
                      Icon(Icons.expand_less,
                          size: 16, color: chrome.onOverlayMuted),
                    ])
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title above, the four levels in one row: a
                        // wrapped fourth item looked like an afterthought.
                        Text(title.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: chrome.onOverlayMuted,
                                letterSpacing: 1.2)),
                        const SizedBox(height: 3),
                        // Two rows of two at full size (Andy 2026-11-10:
                        // one row of four was shrunk to fit beside the
                        // Session button and read far too small). Still
                        // scales down if a huge text size needs it.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Table(
                            defaultColumnWidth: const IntrinsicColumnWidth(),
                            defaultVerticalAlignment:
                                TableCellVerticalAlignment.middle,
                            children: [
                              for (var r = 0; r < signalLevels.length; r += 2)
                                TableRow(children: [
                                  for (var i = r; i < r + 2; i++)
                                    i < signalLevels.length
                                        ? Padding(
                                            padding: EdgeInsets.only(
                                                right: i == r ? 14 : 0,
                                                top: r == 0 ? 0 : 3),
                                            child:
                                                _item(i, rssi, theme, chrome),
                                          )
                                        : const SizedBox.shrink(),
                                ]),
                            ],
                          ),
                        ),
                        if (widget.showRelayedNote)
                          Text('Large dot: direct · Small dot: relayed',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: chrome.onOverlayMuted)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Swatch, name and (margin mode) dB edges of level [i].
  Widget _item(int i, bool rssi, ThemeData theme, MapChrome chrome) {
    final l = signalLevels[i];
    final text = theme.textTheme.bodyMedium;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _swatch(l, rssi, chrome),
        const SizedBox(width: 4),
        Text(l.$1,
            style: text?.copyWith(
                color: chrome.onOverlay, fontWeight: FontWeight.w600)),
        // dB edges in margin mode; RSSI has none.
        if (!rssi) ...[
          const SizedBox(width: 4),
          Text(MarginBand.values[i].shortRange,
              style: text?.copyWith(color: chrome.onOverlayMuted)),
        ],
      ],
    );
  }

  Widget _swatch((String, double, int) level, bool rssi, MapChrome chrome) {
    final color = rssi
        ? SignalColorMapper.fromRssi(level.$3)
        : SignalColorMapper.fromMargin(level.$2);
    return Container(
      width: 16,
      height: 16,
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: chrome.onOverlayMuted, width: 1),
      ),
    );
  }
}
