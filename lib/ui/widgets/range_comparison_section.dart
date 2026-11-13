// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/radio/radio_types.dart' show formatFrequencyMHz;
import '../../services/link_asymmetry.dart';
import '../../services/range_stats.dart';
import '../theme/app_theme.dart';
import '../../utils/coverage_raster.dart'
    show comparisonBetterAColor, comparisonBetterBColor;
import 'range_polar_plot.dart';

/// "By distance from base": headline, grouped bar chart of ping success per
/// distance band, side-by-side table and polar plots. Works whether or not
/// the two routes overlap.
class RangeComparisonSection extends StatefulWidget {
  final RangeComparison range;

  /// One-line amber note when the sides aren't like for like (protocol or
  /// bandwidth; `comparabilityNote` in `protocol_text.dart`).
  final String? comparabilityNote;

  const RangeComparisonSection(
      {super.key, required this.range, this.comparabilityNote});

  @override
  State<RangeComparisonSection> createState() => _RangeComparisonSectionState();
}

class _RangeComparisonSectionState extends State<RangeComparisonSection> {
  PolarColorMode _mode = PolarColorMode.result;

  @override
  Widget build(BuildContext context) {
    final r = widget.range;
    final text = Theme.of(context).textTheme;
    final outer = polarOuterRingM(r.maxDistanceM);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('By distance from base', style: text.titleMedium),
            const SizedBox(height: 8),
            if (widget.comparabilityNote case final note?) ...[
              Text(
                note,
                key: const ValueKey('comparability-note'),
                style: text.bodyMedium
                    ?.copyWith(color: Theme.of(context).status.warning),
              ),
              const SizedBox(height: 8),
            ],
            if (r.baseLooksMisplaced) ...[
              Text(
                'Nothing here came closer than '
                '${polarRingLabel(r.nearestPointM)} to the base location, so '
                'the map\'s base is probably in the wrong place. Fix it from '
                'the map menu (Set base location…) or by long-pressing the '
                'map, and these numbers will follow.',
                key: const ValueKey('base-misplaced'),
                style: text.bodyMedium
                    ?.copyWith(color: Theme.of(context).status.warning),
              ),
              const SizedBox(height: 8),
            ],
            Text(r.headline, style: text.titleSmall),
            if (r.summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(r.summary, style: text.bodyMedium),
            ],
            if (r.proved != null) ...[
              const SizedBox(height: 12),
              Text('What this test proved', style: text.labelLarge),
              const SizedBox(height: 2),
              Text(r.proved!, style: text.bodyMedium),
            ],
            if (r.strengths.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Where each side led', style: text.labelLarge),
              for (final s in r.strengths) _Bullet(s, style: text.bodyMedium),
            ],
            const SizedBox(height: 16),
            Text('Ping success by distance from base', style: text.titleSmall),
            const SizedBox(height: 8),
            _BandChart(a: r.a, b: r.b),
            const SizedBox(height: 16),
            Text('Side by side', style: text.titleSmall),
            const SizedBox(height: 4),
            _SideBySide(a: r.a, b: r.b),
            const SizedBox(height: 16),
            Text('Range rings', style: text.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<PolarColorMode>(
              segments: [
                for (final m in PolarColorMode.values)
                  ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              onSelectionChanged: (v) => setState(() => _mode = v.first),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, c) {
              Widget plot(SideRangeStats s, Color accent) => RangePolarPlot(
                  stats: s, accent: accent, outerRingM: outer, mode: _mode);
              final pa = plot(r.a, comparisonBetterAColor);
              final pb = plot(r.b, comparisonBetterBColor);
              if (c.maxWidth >= 560) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: pa),
                    const SizedBox(width: 12),
                    Expanded(child: pb),
                  ],
                );
              }
              return Column(children: [pa, const SizedBox(height: 12), pb]);
            }),
            const SizedBox(height: 6),
            _PlotLegend(mode: _mode, outerRingM: outer),
            const SizedBox(height: 16),
            Text('What the numbers say', style: text.titleSmall),
            const SizedBox(height: 4),
            for (final b in r.readingIt) _Bullet(b, style: text.bodySmall),
            if (r.dataNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Heads up', style: text.labelLarge),
              for (final n in r.dataNotes)
                _Bullet(n,
                    style: text.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.tertiary)),
            ],
            if (r.nextStep != null) ...[
              const SizedBox(height: 12),
              Text('Next', style: text.labelLarge),
              const SizedBox(height: 2),
              Text(r.nextStep!, style: text.bodyMedium),
            ],
            const SizedBox(height: 10),
            Text(r.footnote,
                style: text.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const _Bullet(this.text, {this.style});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•  ', style: style),
            Expanded(child: Text(text, style: style)),
          ],
        ),
      );
}

class _PlotLegend extends StatelessWidget {
  final PolarColorMode mode;
  final double outerRingM;

  const _PlotLegend({required this.mode, required this.outerRingM});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    Widget dot(Color c, String t) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(t, style: style),
        ]);
    return Wrap(
      spacing: 12,
      runSpacing: 2,
      children: [
        if (mode == PolarColorMode.result) ...[
          dot(polarAckedColor, 'ACKed'),
          dot(polarMissedColor, 'missed'),
          dot(polarImplicitColor, 'relay ACK only'),
        ] else ...[
          dot(const Color(0xFF27AE60), 'strong SNR'),
          dot(const Color(0xFFC0392B), 'weak SNR'),
          dot(const Color(0xFFBBBBBB), 'no ACK'),
        ],
        Text('Rings every 250 m · north up · same scale on both', style: style),
      ],
    );
  }
}

/// Grouped bars: A and B ping success per distance band.
class _BandChart extends StatelessWidget {
  final SideRangeStats a, b;

  const _BandChart({required this.a, required this.b});

  static const _plotHeight = 120.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.labelSmall!;

    Widget bar(BandStat s, Color color) {
      final rate = s.rate;
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // One line, shrunk if the column is narrow: five bands of two
            // bars each leave little room, and a wrapped label overflows
            // the fixed plot height.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(rate == null ? '–' : '${(rate * 100).round()}%',
                  maxLines: 1,
                  softWrap: false,
                  style: small.copyWith(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 2),
            Container(
              height: rate == null ? 1 : math.max(1, rate * (_plotHeight - 28)),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: rate == null ? scheme.outlineVariant : color,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ],
        ),
      );
    }

    Widget count(BandStat s) => Expanded(
        child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('${s.acked}/${s.sent}',
                maxLines: 1, softWrap: false, style: small)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _plotHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < a.bands.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                        border:
                            Border(bottom: BorderSide(color: scheme.outline))),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        bar(a.bands[i], comparisonBetterAColor),
                        bar(b.bands[i], comparisonBetterBColor),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 3),
        Row(children: [
          for (var i = 0; i < a.bands.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Row(children: [count(a.bands[i]), count(b.bands[i])]),
            ),
          ],
        ]),
        const SizedBox(height: 2),
        Row(children: [
          for (var i = 0; i < a.bands.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Text(a.bands[i].label.replaceAll(' m', ''),
                  textAlign: TextAlign.center,
                  style: small.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 2, children: [
          _key(comparisonBetterAColor, a.name, small),
          _key(comparisonBetterBColor, b.name, small),
          Text('Meters from base · under each bar: answered/sent', style: small),
        ]),
      ],
    );
  }

  static Widget _key(Color c, String t, TextStyle style) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, color: c),
        const SizedBox(width: 4),
        Text(t, style: style),
      ]);
}

String _m(double? v) => v == null ? '–' : '${v.round()} m';
String _ms(double? v) => v == null ? '–' : '${v.round()} ms';
String _db(double? v) => v == null ? '–' : '${v.toStringAsFixed(1)} dB';
String _dbm(double? v) => v == null ? '–' : '${v.round()} dBm';
String _pctv(double? v) =>
    v == null ? '–' : '${v.toStringAsFixed(v < 10 ? 1 : 0)}%';

/// Channel utilisation text: radio-measured channel use, else own air time.
String _channel(SideRangeStats s) => s.channelUtilPct != null
    ? _pctv(s.channelUtilPct)
    : s.airUtilTxPct != null
        ? '${_pctv(s.airUtilTxPct)} (own TX)'
        : '–';

/// "−2.1 dB (34)": uplink minus downlink SNR and how many replies.
String _asym(SideRangeStats s) {
  final x = s.linkAsymmetry;
  return x == null ? '–' : '${formatDb(x.medianDeltaDb)} (${x.count})';
}

String _acked(SideRangeStats s) {
  if (s.pingsSent == 0) return '–';
  final rate = '${s.pingsAcked} (${(s.ackRate! * 100).round()}%)';
  return s.pingsImplicit > 0 ? '$rate +${s.pingsImplicit} relay' : rate;
}

class _SideBySide extends StatelessWidget {
  final SideRangeStats a, b;

  const _SideBySide({required this.a, required this.b});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget head(String t, Color c) => Expanded(
          flex: 3,
          child: Text(t,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: text.labelLarge
                  ?.copyWith(color: c, fontWeight: FontWeight.w700)),
        );
    Widget row(String label, String va, String vb) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: Text(label, style: text.bodyMedium)),
              Expanded(
                  flex: 3,
                  child: Text(va,
                      textAlign: TextAlign.end, style: text.labelLarge)),
              Expanded(
                  flex: 3,
                  child: Text(vb,
                      textAlign: TextAlign.end, style: text.labelLarge)),
            ],
          ),
        );
    return Column(
      children: [
        Row(children: [
          const Expanded(flex: 4, child: SizedBox()),
          head(a.name, comparisonBetterAColor),
          head(b.name, comparisonBetterBColor),
        ]),
        const Divider(height: 10),
        row(
            'Packet airtime',
            a.packetAirtimeMs > 0 ? _ms(a.packetAirtimeMs) : '–',
            b.packetAirtimeMs > 0 ? _ms(b.packetAirtimeMs) : '–'),
        row('Pings sent', '${a.pingsSent}', '${b.pingsSent}'),
        row('Pings ACKed', _acked(a), _acked(b)),
        row('Farthest ACK', _m(a.farthestAckM), _m(b.farthestAckM)),
        row('Closest miss', _m(a.firstMissM), _m(b.firstMissM)),
        row('Farthest point walked', _m(a.farthestWalkedM),
            _m(b.farthestWalkedM)),
        row('Heard base out to', _m(a.heardBaseOutToM), _m(b.heardBaseOutToM)),
        row('Median round trip', _ms(a.medianRoundTripMs),
            _ms(b.medianRoundTripMs)),
        row('Median SNR', _db(a.medianSnr), _db(b.medianSnr)),
        // MeshCore traces only: how the base heard us vs how we heard it.
        if (a.linkAsymmetry != null || b.linkAsymmetry != null)
          row('Uplink minus downlink SNR (median)', _asym(a), _asym(b)),
        row('Median RSSI', _dbm(a.medianRssi), _dbm(b.medianRssi)),
        row('Channel utilisation', _channel(a), _channel(b)),
        if (a.frequencySlots.isNotEmpty ||
            b.frequencySlots.isNotEmpty ||
            a.frequenciesMHz.isNotEmpty ||
            b.frequenciesMHz.isNotEmpty)
          row('Frequency', _frequency(a), _frequency(b)),
        if (a.txPowersDbm.isNotEmpty || b.txPowersDbm.isNotEmpty)
          row('Transmit power', _set(a.txPowersDbm, ' dBm'),
              _set(b.txPowersDbm, ' dBm')),
        if (a.hopLimits.isNotEmpty || b.hopLimits.isNotEmpty)
          row('Hop limit', _set(a.hopLimits), _set(b.hopLimits)),
      ],
    );
  }

  /// "27 dBm", "22/27 dBm" when sessions differ, "–" when unknown.
  static String _set(Set<num> v, [String unit = '']) {
    if (v.isEmpty) return '–';
    final l = v.toList()..sort();
    return '${l.join('/')}$unit';
  }

  /// "Slot 20 · 906.875 MHz", either part alone, or "–".
  static String _frequency(SideRangeStats s) {
    final parts = [
      if (s.frequencySlots.isNotEmpty) 'Slot ${_set(s.frequencySlots)}',
      if (s.frequenciesMHz.isNotEmpty)
        '${(s.frequenciesMHz.toList()..sort()).map(formatFrequencyMHz).join('/')} MHz',
    ];
    return parts.isEmpty ? '–' : parts.join(' · ');
  }
}
