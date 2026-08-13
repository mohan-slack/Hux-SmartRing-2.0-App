/// HUX Theme — vivid gradient edition
/// -------------------------------------
/// Builds the ONE `ThemeData` every screen renders under. Reads
/// `hux_tokens.dart` exclusively — no color/radius/spacing literal
/// lives in this file either, beyond assembling tokens into Flutter's
/// theming types.
///
/// SECOND typography pass: Urbanist (a single geometric sans) replaces
/// the first pass's Fraunces/Space Grotesk serif+sans pairing, for
/// EVERY text slot — display, body, and numerals alike. The stage
/// moved from charcoal-grey glass to near-black solid/gradient cards;
/// Hot Pink is the new hero accent doing the glowing, in the same role
/// mint played before.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'hux_tokens.dart';

ThemeData buildHuxTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: HuxColors.accentPurple,
    brightness: Brightness.dark,
  ).copyWith(
    primary: HuxColors.accentPink,
    onPrimary: HuxColors.inkOnAccent,
    primaryContainer: _overCard(HuxColors.accentPink, HuxOpacity.iconChip),
    onPrimaryContainer: HuxColors.ink,
    secondary: HuxColors.accentCherry,
    onSecondary: HuxColors.inkOnAccent,
    secondaryContainer:
        _overCard(HuxColors.accentPink, HuxOpacity.activeCardWash),
    onSecondaryContainer: HuxColors.ink,
    tertiary: HuxColors.accentPurple,
    onTertiary: HuxColors.ink,
    tertiaryContainer:
        _overCard(HuxColors.accentPurple, HuxOpacity.activeCardWash),
    onTertiaryContainer: HuxColors.ink,
    error: HuxColors.rundown,
    onError: HuxColors.inkOnAccent,
    surface: HuxColors.card,
    onSurface: HuxColors.ink,
    onSurfaceVariant: HuxColors.mutedText,
    outline: HuxColors.glassStroke,
    outlineVariant: HuxColors.hairline,
  );

  final textTheme = _huxTextTheme();

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: HuxColors.bg,
    colorScheme: colorScheme,
    textTheme: textTheme,
    dividerColor: HuxColors.hairline,
    dividerTheme: const DividerThemeData(
      color: HuxColors.hairline,
      thickness: 1,
      space: HuxSpacing.xxl,
    ),
    // Material Cards read as simple glass out of the box: translucent
    // fill + glass stroke over the dark stage. Hero panels that want
    // the highlight/glow treatment use GlassPanel instead.
    cardTheme: CardThemeData(
      color: HuxColors.glassFillBottom,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HuxRadii.card),
        side: const BorderSide(color: HuxColors.glassStroke),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: HuxColors.glassFillTop,
      selectedColor: _overCard(HuxColors.accentPink, HuxOpacity.activeCardWash),
      side: const BorderSide(color: HuxColors.glassStroke),
      labelStyle: textTheme.labelLarge?.copyWith(color: HuxColors.ink),
      deleteIconColor: HuxColors.mutedText,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HuxRadii.chip),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
    ),
    // The nav bar itself is translucent; the REAL glass (BackdropFilter
    // over scrolling content) is applied where it's mounted — see
    // app_shell.dart.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: HuxColors.card.withValues(alpha: HuxOpacity.navGlass),
      indicatorColor: _overCard(HuxColors.accentPink, HuxOpacity.iconChip),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelMedium?.copyWith(
          color: selected ? HuxColors.accentPink : HuxColors.mutedText,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? HuxColors.accentPink : HuxColors.mutedText,
        );
      }),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? HuxColors.accentPink
              : HuxColors.glassFillTop;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? HuxColors.inkOnAccent
              : HuxColors.ink;
        }),
        side: const WidgetStatePropertyAll(
            BorderSide(color: HuxColors.glassStroke)),
        minimumSize: const WidgetStatePropertyAll(Size(0, huxMinTapTarget)),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: HuxColors.cardElevated,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: HuxColors.ink),
      actionTextColor: HuxColors.accentPink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HuxSpacing.sm),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: HuxColors.accentPink,
      circularTrackColor: HuxColors.hairline,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: HuxColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HuxRadii.card),
      ),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: HuxColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(HuxRadii.card)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: HuxColors.ink,
      iconColor: HuxColors.mutedText,
      minVerticalPadding: HuxSpacing.md,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HuxColors.glassFillBottom,
      labelStyle: textTheme.bodyMedium?.copyWith(color: HuxColors.mutedText),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HuxSpacing.sm),
        borderSide: const BorderSide(color: HuxColors.glassStroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HuxSpacing.sm),
        borderSide: const BorderSide(color: HuxColors.glassStroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HuxSpacing.sm),
        borderSide: const BorderSide(color: HuxColors.accentPink),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: HuxColors.accentPink,
        foregroundColor: HuxColors.inkOnAccent,
        disabledBackgroundColor: HuxColors.glassFillTop,
        disabledForegroundColor: HuxColors.mutedText,
        minimumSize: const Size(0, huxMinTapTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HuxRadii.chip),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: HuxColors.accentPink,
        side: const BorderSide(color: HuxColors.accentPink),
        minimumSize: const Size(0, huxMinTapTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HuxRadii.chip),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: HuxColors.accentPink,
        minimumSize: const Size(0, huxMinTapTarget),
        textStyle: textTheme.labelLarge,
      ),
    ),
  );
}

/// An accent blended flat over the opaque [HuxColors.card] surface at
/// [opacity] — used for container/indicator colors so washes stay
/// predictable, opaque colors (text contrast on top is verifiable)
/// rather than stacking translucency on translucency.
Color _overCard(Color color, double opacity) =>
    Color.alphaBlend(color.withValues(alpha: opacity), HuxColors.card);

/// H1-role letter spacing from the reference type spec: -1% of the
/// resolved font size (a small NEGATIVE tracking reads as tighter,
/// more "designed" at display sizes — the opposite of body text).
double _h1Tracking(double fontSize) => fontSize * -0.01;

/// Body-role letter spacing from the same spec: +2% of the resolved
/// font size (a touch of positive tracking keeps small Urbanist text
/// from feeling cramped, since it's a geometric sans, not a serif).
double _bodyTracking(double fontSize) => fontSize * 0.02;

TextTheme _huxTextTheme() {
  final base = GoogleFonts.urbanistTextTheme().apply(
    bodyColor: HuxColors.ink,
    displayColor: HuxColors.ink,
  );

  // H1-role slots (display/headline): Medium weight, 120% line height,
  // -1% tracking — the reference spec's "H1 Title" spelled out exactly
  // once, applied at each slot's own size rather than repeating the
  // spec's literal 64sp everywhere (that size is a hero/marketing
  // scale; in-app headlines stay at their existing, screen-tested
  // sizes — only the WEIGHT/HEIGHT/TRACKING recipe carries over).
  TextStyle h1(TextStyle? textStyle, double fontSize) => GoogleFonts.urbanist(
        textStyle: textStyle,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        height: 1.2,
        letterSpacing: _h1Tracking(fontSize),
      );

  return base.copyWith(
    displayLarge: h1(base.displayLarge, base.displayLarge?.fontSize ?? 57),
    displayMedium: h1(base.displayMedium, base.displayMedium?.fontSize ?? 45),
    // Today's hero headline lives here.
    displaySmall: h1(base.displaySmall, 36),
    headlineLarge: h1(base.headlineLarge, 32),
    headlineMedium:
        h1(base.headlineMedium, base.headlineMedium?.fontSize ?? 28),
    // Story's title and Modes'/Trends' section headers — a step down
    // from the Today hero, same H1 recipe.
    headlineSmall: h1(base.headlineSmall, 24),
    // Story paragraphs read here (bodyLarge): 1.6 line height for
    // comfortable long-form reading (kept from the first pass — the
    // reference spec's 120% is for shorter UI copy, not paragraphs).
    bodyLarge: GoogleFonts.urbanist(
      textStyle: base.bodyLarge,
      height: 1.6,
      letterSpacing: _bodyTracking(base.bodyLarge?.fontSize ?? 16),
      color: HuxColors.ink,
    ),
    bodyMedium: GoogleFonts.urbanist(
      textStyle: base.bodyMedium,
      height: 1.2,
      letterSpacing: _bodyTracking(base.bodyMedium?.fontSize ?? 14),
      color: HuxColors.ink,
    ),
    bodySmall: GoogleFonts.urbanist(
      textStyle: base.bodySmall,
      height: 1.2,
      letterSpacing: _bodyTracking(base.bodySmall?.fontSize ?? 12),
      color: HuxColors.mutedText,
    ),
    labelLarge: GoogleFonts.urbanist(
      textStyle: base.labelLarge,
      fontWeight: FontWeight.w600,
      letterSpacing: _bodyTracking(base.labelLarge?.fontSize ?? 14),
      color: HuxColors.ink,
    ),
    labelMedium: GoogleFonts.urbanist(
      textStyle: base.labelMedium,
      letterSpacing: _bodyTracking(base.labelMedium?.fontSize ?? 12),
      color: HuxColors.mutedText,
    ),
    labelSmall: GoogleFonts.urbanist(
      textStyle: base.labelSmall,
      letterSpacing: _bodyTracking(base.labelSmall?.fontSize ?? 11),
      color: HuxColors.mutedText,
    ),
  );
}
