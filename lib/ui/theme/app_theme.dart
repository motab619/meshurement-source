// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:flutter/material.dart';

import 'status_colors.dart';

export 'status_colors.dart';

/// The app's one theme, light and dark. See docs/design/theme.md.
///
/// Direction: an instrument with a quiet 80s-arcade streak, not a
/// Material app. Warm "paper and ink" neutrals (the chart palette in
/// `ProfileChartColors`), one arcade-orange accent (the ring colour of the
/// app icon) with cyan as its foil, the B612 cockpit typeface (B612 Mono
/// for readouts and section labels), flat surfaces with 1 px hairlines
/// instead of shadows, and squared corners instead of Material's pills.
abstract final class AppTheme {
  /// Arcade orange, the app icon's node ring. `fromSeed` would wash the
  /// dark primary out to peach, so the primaries are pinned below.
  static const seed = Color(0xFFFF6A13);

  /// Dark-theme accent: saturated, reads as a lit element on charcoal.
  static const _orangeBright = Color(0xFFFF7A1F);

  /// Light-theme accent: burnt, so text and icons in it stay readable on
  /// paper (4.6:1 on #F7F6F3).
  static const _orangeDeep = Color(0xFFB83E00);

  static const fontFamily = 'B612';

  /// Corner radii. One small radius everywhere; sheets and dialogs a step up.
  static const radiusSmall = 6.0;
  static const radius = 8.0;
  static const radiusLarge = 12.0;
  static const radiusSheet = 16.0;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final seeded = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    // Neutral warm greys replace the seed-tinted surfaces: paper (light)
    // and charcoal (dark), the same tokens the charts already use.
    final scheme = dark
        ? seeded.copyWith(
            primary: _orangeBright,
            onPrimary: const Color(0xFF2A1200),
            primaryContainer: const Color(0xFF6B2A00),
            onPrimaryContainer: const Color(0xFFFFD8C2),
            inversePrimary: _orangeDeep,
            secondary: const Color(0xFF2BD9E6),
            onSecondary: const Color(0xFF00363B),
            secondaryContainer: const Color(0xFF00525A),
            onSecondaryContainer: const Color(0xFFCFF7FA),
            surface: const Color(0xFF141413),
            onSurface: const Color(0xFFF0EFEC),
            onSurfaceVariant: const Color(0xFFC3C2B7),
            surfaceContainerLowest: const Color(0xFF0F0F0E),
            surfaceContainerLow: const Color(0xFF1A1A19),
            surfaceContainer: const Color(0xFF202020),
            surfaceContainerHigh: const Color(0xFF262625),
            surfaceContainerHighest: const Color(0xFF2C2C2A),
            surfaceDim: const Color(0xFF101010),
            surfaceBright: const Color(0xFF3A3A38),
            outline: const Color(0xFF898781),
            outlineVariant: const Color(0xFF34342F),
            inverseSurface: const Color(0xFFF0EFEC),
            onInverseSurface: const Color(0xFF1A1A19),
            // A clearer error red than the seeded one, matching the charts.
            error: const Color(0xFFE2473E),
            onError: const Color(0xFFFFFFFF),
            errorContainer: const Color(0xFFA32626),
            onErrorContainer: const Color(0xFFFFE9E7),
          )
        : seeded.copyWith(
            primary: _orangeDeep,
            onPrimary: const Color(0xFFFFFFFF),
            primaryContainer: const Color(0xFFFFDBC8),
            onPrimaryContainer: const Color(0xFF3A1400),
            inversePrimary: _orangeBright,
            secondary: const Color(0xFF007C87),
            onSecondary: const Color(0xFFFFFFFF),
            secondaryContainer: const Color(0xFFCDEEF2),
            onSecondaryContainer: const Color(0xFF003A3F),
            surface: const Color(0xFFF7F6F3),
            onSurface: const Color(0xFF1A1A19),
            onSurfaceVariant: const Color(0xFF4A4943),
            surfaceContainerLowest: const Color(0xFFFFFFFF),
            surfaceContainerLow: const Color(0xFFF0EFEC),
            surfaceContainer: const Color(0xFFEAE8E3),
            surfaceContainerHigh: const Color(0xFFE2E0D9),
            surfaceContainerHighest: const Color(0xFFD8D6CE),
            surfaceDim: const Color(0xFFD8D6CE),
            surfaceBright: const Color(0xFFFFFFFF),
            outline: const Color(0xFF898781),
            outlineVariant: const Color(0xFFD8D6CE),
            inverseSurface: const Color(0xFF2C2C2A),
            onInverseSurface: const Color(0xFFF0EFEC),
            error: const Color(0xFFC12B2B),
            onError: const Color(0xFFFFFFFF),
            errorContainer: const Color(0xFFFFDAD6),
            onErrorContainer: const Color(0xFF5C0E0E),
          );

    final status = StatusColors.of(brightness);
    final text = _textTheme(scheme);
    final hairline = BorderSide(color: scheme.outlineVariant);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    final shapeLarge = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusLarge),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      dividerColor: scheme.outlineVariant,
      extensions: [status, MapChrome.of(brightness), ReadoutStyles.base],
    );

    return base.copyWith(
      // Flat bar, same paper as the page, a hairline underneath.
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        shape: Border(bottom: hairline),
        titleTextStyle: text.titleLarge,
        toolbarTextStyle: text.bodyMedium,
        iconTheme: IconThemeData(color: scheme.onSurface),
        actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: shape,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium!.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      // Buttons: 44 px keys with squared corners, no pills.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: shape,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: shape,
          elevation: 0,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: text.labelLarge,
          backgroundColor: scheme.surfaceContainerHigh,
          foregroundColor: scheme.onSurface,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: shape,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: text.labelLarge,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: shape,
          minimumSize: const Size(44, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(shape: shape),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: shapeLarge,
        elevation: 2,
        highlightElevation: 2,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        extendedTextStyle: text.labelLarge,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 18),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: shape,
          side: BorderSide(color: scheme.outline),
          textStyle: text.labelMedium,
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          foregroundColor: scheme.onSurfaceVariant,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        side: hairline,
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        showCheckmark: false,
      ),
      // Lists: flat rows, generous height, secondary text in ink-grey.
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 10,
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle:
            text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
        leadingAndTrailingTextStyle:
            text.labelMedium!.copyWith(color: scheme.onSurfaceVariant),
      ),
      // Cards and sheets: one tint up from the page, a hairline, no shadow.
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: hairline,
        ),
        clipBehavior: Clip.antiAlias,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surfaceContainerLow,
        modalBarrierColor: const Color(0x8C000000),
        elevation: 0,
        modalElevation: 0,
        // The sheets that can be dragged draw their own handle.
        showDragHandle: false,
        dragHandleColor: scheme.outline,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(radiusSheet)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSheet),
          side: hairline,
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle:
            text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: hairline,
        ),
        textStyle: text.bodyMedium,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(2),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge),
            side: hairline,
          )),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: text.bodyMedium,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge),
            side: hairline,
          )),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle:
            text.bodyMedium!.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        shape: shape,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
        hintStyle: text.bodyMedium!.copyWith(color: scheme.outline),
        helperStyle: text.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.outline),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.surfaceContainerHighest),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? Colors.transparent
                : scheme.outline),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
        ),
        side: BorderSide(color: scheme.outline, width: 1.5),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        valueIndicatorColor: scheme.inverseSurface,
        valueIndicatorTextStyle:
            text.labelMedium!.copyWith(color: scheme.onInverseSurface),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        textStyle: text.bodySmall!.copyWith(color: scheme.onInverseSurface),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: scheme.onSurfaceVariant,
        collapsedIconColor: scheme.onSurfaceVariant,
      ),
      // Quick cross-fade between screens instead of the default slide.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: FadePageTransitionsBuilder(),
        TargetPlatform.android: FadePageTransitionsBuilder(),
      }),
    );
  }

  /// B612 is wider than Roboto at the same size, so the scale sits one
  /// step below Material's. Only two weights exist (400 and 700), so no
  /// medium weights are asked for.
  static TextTheme _textTheme(ColorScheme scheme) {
    const f = fontFamily;
    final ink = scheme.onSurface;
    final inkSoft = scheme.onSurfaceVariant;
    return TextTheme(
      displayLarge: TextStyle(
          fontFamily: f,
          fontSize: 48,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.1,
          letterSpacing: -0.5),
      displayMedium: TextStyle(
          fontFamily: f,
          fontSize: 40,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.1,
          letterSpacing: -0.5),
      displaySmall: TextStyle(
          fontFamily: f,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.15),
      headlineLarge: TextStyle(
          fontFamily: f,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.2),
      headlineMedium: TextStyle(
          fontFamily: f,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.2),
      headlineSmall: TextStyle(
          fontFamily: f,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.25),
      titleLarge: TextStyle(
          fontFamily: f,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.25),
      titleMedium: TextStyle(
          fontFamily: f,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.3),
      titleSmall: TextStyle(
          fontFamily: f,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.3,
          letterSpacing: 0.2),
      bodyLarge: TextStyle(
          fontFamily: f,
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: ink,
          height: 1.4),
      bodyMedium: TextStyle(
          fontFamily: f,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: ink,
          height: 1.4),
      bodySmall: TextStyle(
          fontFamily: f,
          fontSize: 11.5,
          fontWeight: FontWeight.w400,
          color: inkSoft,
          height: 1.35),
      labelLarge: TextStyle(
          fontFamily: f,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.2,
          letterSpacing: 0.3),
      labelMedium: TextStyle(
          fontFamily: f,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1.2,
          letterSpacing: 0.3),
      labelSmall: TextStyle(
          fontFamily: f,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: inkSoft,
          height: 1.2,
          letterSpacing: 0.6),
    );
  }
}

/// Route transition: a ~150 ms fade (the first half of the route's
/// 300 ms), so screens change quickly without a hard cut.
class FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: const Interval(0, 0.5, curve: Curves.easeOut),
      ),
      child: child,
    );
  }
}

/// Section heading in a settings-style list: a small mono label in the
/// accent colour (the arcade "HI-SCORE" caption, kept quiet), with the
/// list's own 16 px gutter.
class SectionLabel extends StatelessWidget {
  final String title;

  const SectionLabel(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: theme.readout.label.copyWith(
          fontFamily: ReadoutStyles.monoFamily,
          fontSize: 12,
          color: theme.colorScheme.primary,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
