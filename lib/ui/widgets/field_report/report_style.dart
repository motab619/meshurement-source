// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/units.dart';
import '../../theme/app_theme.dart';

/// Image sizes of a Field Report, in pixels (the card is laid out at this
/// size in logical pixels and captured at a pixel ratio of 1).
enum ReportFormat {
  feed('Feed', Size(1080, 1350)),
  story('Story', Size(1080, 1920)),
  wide('Wide', Size(1200, 675));

  const ReportFormat(this.label, this.size);
  final String label;
  final Size size;
}

/// The card's own palette: always the dark night-sky look of the design
/// mock, whatever the phone's appearance, so every share looks the same.
class ReportStyle {
  ReportStyle._();

  static const bgTop = Color(0xFF0E1C40);
  static const bgBottom = Color(0xFF070E22);
  static const panel = Color(0xFF0C1736);
  static const border = Color(0xFF22335E);
  static const grid = Color(0xFF16264C);
  static const track = Color(0xFF3B5B9A);
  static const text = Color(0xFFF4F6FB);
  static const soft = Color(0xFFA9B6D3);
  static const cyan = Color(0xFF22D3EE);
  static const orange = Color(0xFFFF7A1F);
  static const magenta = Color(0xFFE040FB);
  static const violet = Color(0xFF7C4DFF);

  static const radius = 26.0;

  static TextStyle sans(double size,
          {Color color = text, bool bold = false, bool italic = false}) =>
      TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: size,
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        height: 1.2,
        decoration: TextDecoration.none,
      );

  /// For numbers that can hold a decimal point ("2.2 mi"). B612Mono gives
  /// the full stop a whole cell, which reads as a gap ("2. 2 mi"), so these
  /// use B612 with the readout line height.
  static TextStyle figure(double size,
          {Color color = text, bool bold = false}) =>
      TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: size,
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        fontFeatures: const [FontFeature.tabularFigures()],
        height: 1.15,
        decoration: TextDecoration.none,
      );

  static TextStyle mono(double size,
          {Color color = text, bool bold = false, double spacing = 0}) =>
      TextStyle(
        fontFamily: ReadoutStyles.monoFamily,
        fontSize: size,
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        letterSpacing: spacing,
        height: 1.15,
        decoration: TextDecoration.none,
      );
}

/// "Oct 28, 2026".
String reportDate(DateTime t) =>
    DateFormat('MMM d, y', 'en_US').format(t.toLocal());

/// "1h 48m", "35m".
String reportDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${d.inMinutes}m';
}

/// "+6 dB", "-2 dB".
String reportDb(double v) {
  final r = v.round();
  return '${r > 0 ? '+' : ''}$r dB';
}

/// The safe default card title: range setting and date, never the session
/// name ("Short Turbo · Oct 28, 2026").
String defaultReportTitle(String presetName, DateTime startedAt) =>
    [if (presetName.isNotEmpty) presetName, reportDate(startedAt)].join(' · ');

/// Distance for the card.
String reportDistance(double m, bool miles) => formatDistance(m, miles: miles);
