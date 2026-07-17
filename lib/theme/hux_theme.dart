/// HUX Theme
/// -----------
/// Builds the ONE `ThemeData` every screen renders under. Reads
/// `hux_tokens.dart` exclusively — no color/radius/spacing literal
/// lives in this file either, beyond assembling tokens into Flutter's
/// theming types.
///
/// Typography: Fraunces (serif, warm, editorial) for display/headline
/// slots — Today's hero readout, Story's title, section headers.
/// Space Grotesk for everything else — body copy, numerals, labels,
/// UI chrome. `GoogleFonts` fetches+caches these at runtime; see the
/// README for why no bundled font assets are needed this phase.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'hux_tokens.dart';

ThemeData buildHuxTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: HuxColors.accentDeepTeal,
    brightness: Brightness.light,
  ).copyWith(
    primary: HuxColors.accentDeepTeal,
    onPrimary: Colors.white,
    primaryContainer: _tint(HuxColors.accentDeepTeal, HuxOpacity.iconChip),
    onPrimaryContainer: HuxColors.ink,
    secondary: HuxColors.accentMint,
    onSecondary: HuxColors.ink,
    secondaryContainer: _tint(HuxColors.accentMint, HuxOpacity.activeCardWash),
    onSecondaryContainer: HuxColors.ink,
    tertiary: HuxColors.accentDeepTeal,
    onTertiary: Colors.white,
    tertiaryContainer: _tint(HuxColors.accentDeepTeal, HuxOpacity.activeCardWash),
    onTertiaryContainer: HuxColors.ink,
    error: HuxColors.rundown,
    onError: Colors.white,
    surface: HuxColors.card,
    onSurface: HuxColors.ink,
    onSurfaceVariant: HuxColors.mutedText,
    outline: HuxColors.hairline,
    outlineVariant: HuxColors.hairline,
  );

  final textTheme = _huxTextTheme();

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: HuxColors.paper,
    colorScheme: colorScheme,
    textTheme: textTheme,
    dividerColor: HuxColors.hairline,
    dividerTheme: const DividerThemeData(
      color: HuxColors.hairline,
      thickness: 1,
      space: HuxSpacing.xxl,
    ),
    cardTheme: CardThemeData(
      color: HuxColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HuxRadii.card),
        side: const BorderSide(color: HuxColors.hairline),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: HuxColors.paper,
      selectedColor: _tint(HuxColors.accentMint, HuxOpacity.activeCardWash),
      side: const BorderSide(color: HuxColors.hairline),
      labelStyle: textTheme.labelLarge?.copyWith(color: HuxColors.ink),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HuxRadii.chip),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: HuxColors.card,
      indicatorColor: _tint(HuxColors.accentMint, HuxOpacity.activeCardWash),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelMedium?.copyWith(
          color: selected ? HuxColors.accentDeepTeal : HuxColors.mutedText,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? HuxColors.accentDeepTeal : HuxColors.mutedText,
        );
      }),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? HuxColors.accentDeepTeal
              : HuxColors.card;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? Colors.white
              : HuxColors.ink;
        }),
        side: const WidgetStatePropertyAll(
            BorderSide(color: HuxColors.hairline)),
        minimumSize: const WidgetStatePropertyAll(Size(0, huxMinTapTarget)),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: HuxColors.ink,
      contentTextStyle:
          textTheme.bodyMedium?.copyWith(color: HuxColors.paper),
      actionTextColor: HuxColors.accentMint,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HuxSpacing.sm),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: HuxColors.accentDeepTeal,
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
    listTileTheme: const ListTileThemeData(
      textColor: HuxColors.ink,
      iconColor: HuxColors.mutedText,
      minVerticalPadding: HuxSpacing.md,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HuxColors.paper,
      labelStyle: textTheme.bodyMedium?.copyWith(color: HuxColors.mutedText),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HuxSpacing.sm),
        borderSide: const BorderSide(color: HuxColors.hairline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: HuxColors.accentDeepTeal,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, huxMinTapTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HuxSpacing.sm),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: HuxColors.accentDeepTeal,
        side: const BorderSide(color: HuxColors.accentDeepTeal),
        minimumSize: const Size(0, huxMinTapTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HuxSpacing.sm),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: HuxColors.accentDeepTeal,
        minimumSize: const Size(0, huxMinTapTarget),
        textStyle: textTheme.labelLarge,
      ),
    ),
  );
}

/// A flat tint of [color] over the paper background at [opacity] —
/// used for washes/containers so they read as "a hint of the accent",
/// never a saturated color flood. A plain `withValues(alpha:)` would
/// work too, but pre-blending against paper keeps text drawn on top
/// (always `HuxColors.ink`) at a predictable, pre-verified contrast
/// ratio regardless of what's layered underneath.
Color _tint(Color color, double opacity) =>
    Color.alphaBlend(color.withValues(alpha: opacity), HuxColors.paper);

TextTheme _huxTextTheme() {
  final base = GoogleFonts.spaceGroteskTextTheme().apply(
    bodyColor: HuxColors.ink,
    displayColor: HuxColors.ink,
  );

  return base.copyWith(
    displayLarge: GoogleFonts.fraunces(
        textStyle: base.displayLarge, fontWeight: FontWeight.w600),
    displayMedium: GoogleFonts.fraunces(
        textStyle: base.displayMedium, fontWeight: FontWeight.w600),
    // Today's hero headline lives here: Fraunces at 36 — the top of
    // the brand's specified 32-36 range.
    displaySmall: GoogleFonts.fraunces(
      textStyle: base.displaySmall,
      fontSize: 36,
      fontWeight: FontWeight.w600,
      height: 1.15,
    ),
    headlineLarge: GoogleFonts.fraunces(
      textStyle: base.headlineLarge,
      fontSize: 32,
      fontWeight: FontWeight.w600,
      height: 1.2,
    ),
    headlineMedium: GoogleFonts.fraunces(
        textStyle: base.headlineMedium, fontWeight: FontWeight.w600),
    // Story's title and Modes'/Trends' section headers — Fraunces,
    // still editorial but a step down from the Today hero.
    headlineSmall: GoogleFonts.fraunces(
      textStyle: base.headlineSmall,
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 1.25,
    ),
    // Story paragraphs read here (bodyLarge): 1.6 line height for
    // comfortable, editorial-feeling long-form reading.
    bodyLarge: GoogleFonts.spaceGrotesk(
      textStyle: base.bodyLarge,
      height: 1.6,
      color: HuxColors.ink,
    ),
    bodyMedium: GoogleFonts.spaceGrotesk(
      textStyle: base.bodyMedium,
      color: HuxColors.ink,
    ),
    bodySmall: GoogleFonts.spaceGrotesk(
      textStyle: base.bodySmall,
      color: HuxColors.mutedText,
    ),
    labelLarge: GoogleFonts.spaceGrotesk(
      textStyle: base.labelLarge,
      fontWeight: FontWeight.w600,
      color: HuxColors.ink,
    ),
    labelMedium: GoogleFonts.spaceGrotesk(
      textStyle: base.labelMedium,
      color: HuxColors.mutedText,
    ),
    labelSmall: GoogleFonts.spaceGrotesk(
      textStyle: base.labelSmall,
      color: HuxColors.mutedText,
    ),
  );
}
