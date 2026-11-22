import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/nutrients.dart';
import 'oklch.dart';

/// Design tokens. Every colour is defined in OKLCH; borders are translucent so they sit on any
/// surface; dark mode shows depth with lighter surfaces instead of shadows.
@immutable
class FT extends ThemeExtension<FT> {
  const FT({
    required this.dark,
    required this.bg,
    required this.surface,
    required this.raised,
    required this.inset,
    required this.fg,
    required this.muted,
    required this.border,
    required this.accent,
    required this.onAccent,
    required this.calories,
    required this.caloriesO,
    required this.over,
    required this.warn,
    required this.good,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.weight,
    required this.shadow,
  });

  final bool dark;
  final Color bg;
  final Color surface; // cards
  final Color raised; // menus, sheets, things above cards
  final Color inset; // wells, tracks, segmented backgrounds
  final Color fg;
  final Color muted;
  final Color border;

  /// Primary controls (buttons, the add button, selection): plain white on black, black on white.
  final Color accent;
  final Color onAccent;
  final Color calories;
  final Oklch caloriesO;
  final Color over;
  final Color warn;
  final Color good;
  final Color protein;
  final Color carbs;
  final Color fat;
  final Color weight;
  final List<BoxShadow> shadow;

  // Neutrals carry no hue: black, white and true greys. Colour is reserved for data
  // (calories, macros) and status (on target, over, unverified).
  static FT light() {
    const cal = Oklch(0.62, 0.17, 150);
    return FT(
      dark: false,
      bg: const Oklch(0.975, 0, 0).toColor(),
      surface: const Oklch(1, 0, 0).toColor(),
      raised: const Oklch(1, 0, 0).toColor(),
      inset: const Oklch(0.94, 0, 0).toColor(),
      fg: const Oklch(0.18, 0, 0).toColor(),
      muted: const Oklch(0.50, 0, 0).toColor(),
      border: const Color.from(alpha: 0.10, red: 0, green: 0, blue: 0),
      accent: const Oklch(0.18, 0, 0).toColor(),
      onAccent: Colors.white,
      calories: cal.toColor(),
      caloriesO: cal,
      over: const Oklch(0.60, 0.19, 28).toColor(),
      warn: const Oklch(0.68, 0.15, 70).toColor(),
      good: cal.toColor(),
      protein: const Oklch(0.62, 0.16, 255).toColor(),
      carbs: const Oklch(0.62, 0.16, 55).toColor(),
      fat: const Oklch(0.62, 0.16, 318).toColor(),
      weight: const Oklch(0.58, 0.11, 205).toColor(),
      shadow: const [], // one depth cue per surface: the hairline border
    );
  }

  static FT darkTheme() {
    const cal = Oklch(0.76, 0.17, 150);
    return FT(
      dark: true,
      bg: const Oklch(0, 0, 0).toColor(), // true black
      surface: const Oklch(0.19, 0, 0).toColor(),
      raised: const Oklch(0.24, 0, 0).toColor(),
      inset: const Oklch(0.27, 0, 0).toColor(),
      fg: const Oklch(0.97, 0, 0).toColor(),
      // Secondary text: Lc ≥60 (APCA) on every dark surface, from the background to input fields.
      muted: const Oklch(0.78, 0, 0).toColor(),
      border: const Color.from(alpha: 0.12, red: 1, green: 1, blue: 1),
      accent: const Oklch(0.97, 0, 0).toColor(),
      onAccent: Colors.black,
      calories: cal.toColor(),
      caloriesO: cal,
      over: const Oklch(0.78, 0.14, 28).toColor(), // Lc 61 on cards (0.72 was 50)
      warn: const Oklch(0.80, 0.14, 80).toColor(),
      good: cal.toColor(),
      // Macro peers share one L and C. L 0.78 keeps their small labels above Lc 60 on cards.
      protein: const Oklch(0.78, 0.125, 255).toColor(),
      carbs: const Oklch(0.78, 0.125, 55).toColor(),
      fat: const Oklch(0.78, 0.125, 318).toColor(),
      weight: const Oklch(0.78, 0.095, 205).toColor(),
      shadow: const [], // shadows barely read on black; lighter surfaces carry the depth
    );
  }

  /// Body measures (weight and water) share one teal, kept clear of protein's blue.
  Oklch get bodyO => dark ? const Oklch(0.78, 0.095, 205) : const Oklch(0.58, 0.11, 205);

  Color macro(Macro m) => switch (m) {
    Macro.protein => protein,
    Macro.carbs => carbs,
    Macro.fat => fat,
  };

  static FT of(BuildContext context) => Theme.of(context).extension<FT>()!;

  @override
  FT copyWith() => this;

  @override
  FT lerp(covariant FT? other, double t) => t < 0.5 ? this : (other ?? this);
}

/// Spacing, radii and motion.
abstract final class S {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0, xl = 24.0, xxl = 32.0;

  /// Cards use 24; anything nested inside gets `inner(24, padding)`.
  static const radiusCard = 20.0;
  static const radiusControl = 10.0;

  /// Nested rounded corners: inner radius = outer radius − padding, never below 4.
  static double inner(double outer, double padding) => (outer - padding).clamp(4.0, outer);

  /// Minimum hit target on every platform (Fitts's law).
  static const minTarget = 48.0;
}

/// Motion tokens. Everything the user triggers finishes under 300 ms.
abstract final class Motion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 280);

  /// Slow in, slow out.
  static const standard = Curves.easeInOutCubic;

  /// Arrives fast and settles gently.
  static const enter = Curves.easeOutCubic;

  /// Overshoots slightly and settles: follow-through.
  static const settle = Cubic(0.34, 1.36, 0.64, 1);

  /// Pulls back a little before going: anticipation.
  static const anticipate = Cubic(0.5, -0.45, 0.4, 1);

  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration d) => reduced(context) ? Duration.zero : d;
}

const _fontBody = 'Inter';
const _fontDisplay = 'InterTight';

ThemeData buildTheme(FT t) {
  final scheme = ColorScheme.fromSeed(seedColor: t.accent, brightness: t.dark ? Brightness.dark : Brightness.light)
      .copyWith(
        primary: t.accent,
        onPrimary: t.onAccent,
        // Tonal buttons one step below input fields: a field is always the brightest slab.
        secondaryContainer: t.raised,
        onSecondaryContainer: t.fg,
        surface: t.surface,
        onSurface: t.fg,
        onSurfaceVariant: t.muted,
        outline: t.border,
        outlineVariant: t.border,
        error: t.over,
        surfaceContainerLowest: t.bg,
        surfaceContainerLow: t.surface,
        surfaceContainer: t.surface,
        surfaceContainerHigh: t.raised,
        surfaceContainerHighest: t.inset,
      );

  TextStyle s(double size, FontWeight w, {double? height, double ls = 0, String family = _fontBody, Color? color}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: w,
        height: height,
        letterSpacing: ls,
        color: color ?? t.fg,
      );

  final text = TextTheme(
    displaySmall: s(40, FontWeight.w600, family: _fontDisplay, ls: -0.8, height: 1.05),
    headlineMedium: s(30, FontWeight.w600, family: _fontDisplay, ls: -0.4, height: 1.1),
    headlineSmall: s(22, FontWeight.w600, family: _fontDisplay, ls: -0.2),
    titleLarge: s(19, FontWeight.w600, family: _fontDisplay),
    titleMedium: s(16, FontWeight.w600),
    titleSmall: s(14, FontWeight.w600),
    bodyLarge: s(16, FontWeight.w400, height: 1.4),
    bodyMedium: s(14.5, FontWeight.w400, height: 1.4),
    bodySmall: s(12.5, FontWeight.w400, height: 1.35, color: t.muted),
    labelLarge: s(14.5, FontWeight.w600),
    labelMedium: s(12.5, FontWeight.w500, color: t.muted),
    labelSmall: s(12, FontWeight.w500, ls: 0.1, color: t.muted),
  );

  final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.radiusControl));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    fontFamily: _fontBody,
    textTheme: text,
    extensions: [t],
    // The web build skips shader assets, so it uses the plain ripple.
    splashFactory: kIsWeb ? InkRipple.splashFactory : InkSparkle.splashFactory,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge,
      foregroundColor: t.fg,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: t.inset,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (st) => s(12, FontWeight.w600, color: st.contains(WidgetState.selected) ? t.fg : t.muted),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: t.surface,
      indicatorColor: t.inset,
      selectedLabelTextStyle: s(12.5, FontWeight.w600),
      unselectedLabelTextStyle: s(12.5, FontWeight.w500, color: t.muted),
    ),
    // Filled fields with the floating label kept inside the box (an underline-style border):
    // an outline border would lift the label onto the box's top edge, where it collides with
    // dividers and the content above.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.inset,
      isDense: true,
      contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      border: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(S.radiusControl - 2),
        borderSide: BorderSide.none,
      ),
      enabledBorder: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(S.radiusControl - 2),
        borderSide: BorderSide.none,
      ),
      disabledBorder: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(S.radiusControl - 2),
        borderSide: BorderSide.none,
      ),
      focusedBorder: UnderlineInputBorder(
        borderRadius: BorderRadius.circular(S.radiusControl - 2),
        borderSide: BorderSide(color: t.fg.withValues(alpha: 0.6), width: 1.4),
      ),
      floatingLabelStyle: s(12.5, FontWeight.w500, color: t.muted),
      labelStyle: s(14.5, FontWeight.w400, color: t.muted),
      hintStyle: s(14.5, FontWeight.w400, color: t.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, S.minTarget),
        shape: controlShape,
        textStyle: s(15, FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, S.minTarget),
        shape: controlShape,
        side: BorderSide(color: t.border),
        foregroundColor: t.fg,
        textStyle: s(15, FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, S.minTarget),
        shape: controlShape,
        textStyle: s(15, FontWeight.w600),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: t.inset,
        selectedBackgroundColor: t.raised,
        selectedForegroundColor: t.fg,
        foregroundColor: t.muted,
        side: BorderSide(color: t.border),
        textStyle: s(13.5, FontWeight.w600),
        minimumSize: const Size(48, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.radiusControl)),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStatePropertyAll(t.border),
      trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? t.calories : t.inset),
      thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? Colors.white : t.muted),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.fg, linearTrackColor: t.inset),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.bg,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: t.muted.withValues(alpha: 0.4),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(backgroundColor: t.raised, surfaceTintColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.dark ? t.inset : t.fg,
      contentTextStyle: s(14, FontWeight.w500, color: t.dark ? t.fg : t.bg),
      actionTextColor: t.dark ? t.fg : t.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(S.radiusControl)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: t.dark ? t.inset : t.fg, borderRadius: BorderRadius.circular(8)),
      textStyle: s(12, FontWeight.w500, color: t.dark ? t.fg : t.bg),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

/// Tabular figures so digits line up in columns.
const tabular = [FontFeature.tabularFigures()];
