// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

/// Meaning colours: good / warning / danger / info / neutral, each with a
/// text-on-it colour and a quiet container pair for bands and badges.
///
/// These are the only "status" colours the UI should use; the signal
/// ramp (green → amber → red for SNR/RSSI) lives in
/// `SignalColorMapper` and is deliberately not part of the theme.
/// `warning` and `danger` match the chart tokens in
/// `ProfileChartColors`, so a chart and the text beside it agree.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.ok,
    required this.onOk,
    required this.okContainer,
    required this.onOkContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.lost,
    required this.onLost,
    required this.lostContainer,
    required this.onLostContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.neutral,
    required this.onNeutral,
    required this.muted,
  });

  /// Hearing the base, connected, success.
  final Color ok, onOk, okContainer, onOkContainer;

  /// Reconnecting, airtime high, faster than recommended, public channel.
  final Color warning, onWarning, warningContainer, onWarningContainer;

  /// The phone↔radio link is down: nothing is being recorded. Hot orange
  /// (#FF7700), between amber warning and red danger.
  final Color lost, onLost, lostContainer, onLostContainer;

  /// Base lost, errors, destructive actions (End session, Delete).
  final Color danger, onDanger, dangerContainer, onDangerContainer;

  /// Busy / in progress / informational.
  final Color info, onInfo, infoContainer, onInfoContainer;

  /// Unknown / waiting band.
  final Color neutral, onNeutral;

  /// Secondary text that is not a status: "not set", hints, footnotes.
  final Color muted;

  static const dark = StatusColors(
    ok: Color(0xFF3DC46E),
    onOk: Color(0xFF00210C),
    okContainer: Color(0xFF1B6B3A),
    onOkContainer: Color(0xFFEAF7EE),
    warning: Color(0xFFFAB219),
    onWarning: Color(0xFF261A00),
    warningContainer: Color(0xFF8A5A00),
    onWarningContainer: Color(0xFFFFF3DA),
    lost: Color(0xFFFF7700),
    onLost: Color(0xFF1F0D00),
    lostContainer: Color(0xFFFF7700),
    onLostContainer: Color(0xFF1F0D00),
    danger: Color(0xFFE2473E),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFA32626),
    onDangerContainer: Color(0xFFFFE9E7),
    info: Color(0xFF2BD9E6),
    onInfo: Color(0xFF00363B),
    infoContainer: Color(0xFF00525A),
    onInfoContainer: Color(0xFFD9F6FA),
    neutral: Color(0xFF3A3F42),
    onNeutral: Color(0xFFE6E8E9),
    muted: Color(0xFF9A988F),
  );

  static const light = StatusColors(
    ok: Color(0xFF1E8E4E),
    onOk: Color(0xFFFFFFFF),
    okContainer: Color(0xFFD5F2DF),
    onOkContainer: Color(0xFF0B3A1D),
    // Dark enough to read as 11.5–13 pt text in sunlight (≈4.9:1 on
    // white; the old #C98A00 was ≈2.9:1). Still amber next to the orange.
    warning: Color(0xFF9A6600),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFFE9B8),
    onWarningContainer: Color(0xFF4A3300),
    lost: Color(0xFFC85A00),
    onLost: Color(0xFFFFFFFF),
    lostContainer: Color(0xFFFF7700),
    onLostContainer: Color(0xFF1F0D00),
    danger: Color(0xFFC12B2B),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFFFDAD6),
    onDangerContainer: Color(0xFF5C0E0E),
    info: Color(0xFF007C87),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFCDEEF2),
    onInfoContainer: Color(0xFF003A3F),
    neutral: Color(0xFFDCDBD5),
    onNeutral: Color(0xFF2B2B29),
    muted: Color(0xFF6E6C65),
  );

  static StatusColors of(Brightness b) => b == Brightness.dark ? dark : light;

  @override
  StatusColors copyWith({
    Color? ok,
    Color? onOk,
    Color? okContainer,
    Color? onOkContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? lost,
    Color? onLost,
    Color? lostContainer,
    Color? onLostContainer,
    Color? danger,
    Color? onDanger,
    Color? dangerContainer,
    Color? onDangerContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? neutral,
    Color? onNeutral,
    Color? muted,
  }) =>
      StatusColors(
        ok: ok ?? this.ok,
        onOk: onOk ?? this.onOk,
        okContainer: okContainer ?? this.okContainer,
        onOkContainer: onOkContainer ?? this.onOkContainer,
        warning: warning ?? this.warning,
        onWarning: onWarning ?? this.onWarning,
        warningContainer: warningContainer ?? this.warningContainer,
        onWarningContainer: onWarningContainer ?? this.onWarningContainer,
        lost: lost ?? this.lost,
        onLost: onLost ?? this.onLost,
        lostContainer: lostContainer ?? this.lostContainer,
        onLostContainer: onLostContainer ?? this.onLostContainer,
        danger: danger ?? this.danger,
        onDanger: onDanger ?? this.onDanger,
        dangerContainer: dangerContainer ?? this.dangerContainer,
        onDangerContainer: onDangerContainer ?? this.onDangerContainer,
        info: info ?? this.info,
        onInfo: onInfo ?? this.onInfo,
        infoContainer: infoContainer ?? this.infoContainer,
        onInfoContainer: onInfoContainer ?? this.onInfoContainer,
        neutral: neutral ?? this.neutral,
        onNeutral: onNeutral ?? this.onNeutral,
        muted: muted ?? this.muted,
      );

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return StatusColors(
      ok: l(ok, other.ok),
      onOk: l(onOk, other.onOk),
      okContainer: l(okContainer, other.okContainer),
      onOkContainer: l(onOkContainer, other.onOkContainer),
      warning: l(warning, other.warning),
      onWarning: l(onWarning, other.onWarning),
      warningContainer: l(warningContainer, other.warningContainer),
      onWarningContainer: l(onWarningContainer, other.onWarningContainer),
      lost: l(lost, other.lost),
      onLost: l(onLost, other.onLost),
      lostContainer: l(lostContainer, other.lostContainer),
      onLostContainer: l(onLostContainer, other.onLostContainer),
      danger: l(danger, other.danger),
      onDanger: l(onDanger, other.onDanger),
      dangerContainer: l(dangerContainer, other.dangerContainer),
      onDangerContainer: l(onDangerContainer, other.onDangerContainer),
      info: l(info, other.info),
      onInfo: l(onInfo, other.onInfo),
      infoContainer: l(infoContainer, other.infoContainer),
      onInfoContainer: l(onInfoContainer, other.onInfoContainer),
      neutral: l(neutral, other.neutral),
      onNeutral: l(onNeutral, other.onNeutral),
      muted: l(muted, other.muted),
    );
  }
}

/// Floating chrome drawn over the map: the radio pill, base status band,
/// signal readout, legend, layer toggles and the first-run card. Tinted
/// surface rather than black, so it belongs to the same paper as the rest
/// of the app and still reads over bright tiles.
@immutable
class MapChrome extends ThemeExtension<MapChrome> {
  const MapChrome({
    required this.overlay,
    required this.onOverlay,
    required this.onOverlayMuted,
    required this.hairline,
    required this.radius,
    required this.scrim,
  });

  /// Background of a floating panel (already translucent).
  final Color overlay;

  /// Primary text and icons on [overlay].
  final Color onOverlay;

  /// Labels and secondary text on [overlay].
  final Color onOverlayMuted;

  /// 1 px edge around a floating panel.
  final Color hairline;

  /// Corner radius of floating panels.
  final double radius;

  /// Dark veil for text drawn straight on the tiles (attribution, hints).
  final Color scrim;

  static const dark = MapChrome(
    overlay: Color(0xF01A1A19),
    onOverlay: Color(0xFFF0EFEC),
    onOverlayMuted: Color(0xFFC3C2B7),
    hairline: Color(0xFF3A3A38),
    radius: 10,
    scrim: Color(0xB3000000),
  );

  static const light = MapChrome(
    overlay: Color(0xF2FBFAF7),
    onOverlay: Color(0xFF1A1A19),
    onOverlayMuted: Color(0xFF4A4943),
    hairline: Color(0xFFCFCDC5),
    radius: 10,
    scrim: Color(0xB3000000),
  );

  static MapChrome of(Brightness b) => b == Brightness.dark ? dark : light;

  /// Panel decoration: tinted surface, hairline edge, rounded corners.
  BoxDecoration get panel => BoxDecoration(
        color: overlay,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: hairline),
      );

  @override
  MapChrome copyWith({
    Color? overlay,
    Color? onOverlay,
    Color? onOverlayMuted,
    Color? hairline,
    double? radius,
    Color? scrim,
  }) =>
      MapChrome(
        overlay: overlay ?? this.overlay,
        onOverlay: onOverlay ?? this.onOverlay,
        onOverlayMuted: onOverlayMuted ?? this.onOverlayMuted,
        hairline: hairline ?? this.hairline,
        radius: radius ?? this.radius,
        scrim: scrim ?? this.scrim,
      );

  @override
  MapChrome lerp(ThemeExtension<MapChrome>? other, double t) {
    if (other is! MapChrome) return this;
    return MapChrome(
      overlay: Color.lerp(overlay, other.overlay, t)!,
      onOverlay: Color.lerp(onOverlay, other.onOverlay, t)!,
      onOverlayMuted: Color.lerp(onOverlayMuted, other.onOverlayMuted, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      radius: radius + (other.radius - radius) * t,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

/// Instrument readouts: numbers that are compared at a glance (SNR, RSSI,
/// airtime, seq, counts) in the monospaced companion face, so columns
/// line up and digits don't jump as values change.
@immutable
class ReadoutStyles extends ThemeExtension<ReadoutStyles> {
  const ReadoutStyles({
    required this.value,
    required this.valueLarge,
    required this.label,
  });

  /// A measured value in running UI (14 px, bold, mono).
  final TextStyle value;

  /// A headline figure (24 px, bold, mono).
  final TextStyle valueLarge;

  /// The small caption next to a value ("SNR", "RSSI").
  final TextStyle label;

  static const monoFamily = 'B612Mono';

  static const base = ReadoutStyles(
    value: TextStyle(
      fontFamily: monoFamily,
      fontSize: 14,
      fontWeight: FontWeight.w700,
      height: 1.2,
    ),
    valueLarge: TextStyle(
      fontFamily: monoFamily,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.1,
    ),
    label: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      height: 1.2,
    ),
  );

  @override
  ReadoutStyles copyWith({
    TextStyle? value,
    TextStyle? valueLarge,
    TextStyle? label,
  }) =>
      ReadoutStyles(
        value: value ?? this.value,
        valueLarge: valueLarge ?? this.valueLarge,
        label: label ?? this.label,
      );

  @override
  ReadoutStyles lerp(ThemeExtension<ReadoutStyles>? other, double t) {
    if (other is! ReadoutStyles) return this;
    return ReadoutStyles(
      value: TextStyle.lerp(value, other.value, t)!,
      valueLarge: TextStyle.lerp(valueLarge, other.valueLarge, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
    );
  }
}

/// Short-hand lookups with fallbacks, so a widget pumped under a plain
/// `MaterialApp` (tests) still gets sensible colours.
extension AppThemeLookups on ThemeData {
  StatusColors get status =>
      extension<StatusColors>() ?? StatusColors.of(brightness);
  MapChrome get mapChrome => extension<MapChrome>() ?? MapChrome.of(brightness);
  ReadoutStyles get readout => extension<ReadoutStyles>() ?? ReadoutStyles.base;
}

extension AppThemeContext on BuildContext {
  StatusColors get status => Theme.of(this).status;
  MapChrome get mapChrome => Theme.of(this).mapChrome;
  ReadoutStyles get readout => Theme.of(this).readout;
}
