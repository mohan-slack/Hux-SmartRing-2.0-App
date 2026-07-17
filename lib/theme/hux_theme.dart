/// HUX Theme — dark liquid-glass edition
/// ---------------------------------------
/// Builds the ONE `ThemeData` every screen renders under. Reads
/// `hux_tokens.dart` exclusively — no color/radius/spacing literal
/// lives in this file either, beyond assembling tokens into Flutter's
/// theming types.
///
/// Typography is unchanged from the first design pass: Fraunces
/// (serif, warm, editorial) for display/headline slots, Space Grotesk
/// for body/numerals/UI chrome. What changed is the stage: dark-first,
/// glass surfaces, mint doing the glowing. Buttons flip to bright mint
/// fills with near-black text — accents READ as light sources on the
/// dark stage instead of dark stamps on paper.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'hux_tokens.dart';

ThemeData buildHuxTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: HuxColors.accentDeepTeal,
    brightness: Brightness.dark,
  ).copyWith(
    primary: HuxColors.accentMint,
    onPrimary: HuxColors.inkOnAccent,
    primaryContainer: _overCard(HuxColors.accentMint, HuxOpacity.iconChip),
    onPrimaryContainer: HuxColors.ink,
    secondary: HuxColors.accentTeal,
    onSecondary: HuxColors.inkOnAccent,
    secondaryContainer:
        _overCard(HuxColors.accentMint, HuxOpacity.activeCardWash),
    onSecondaryContainer: HuxColors.ink,
    tertiary: HuxColors.accentTeal,
    onTertiary: HuxColors.inkOnAccent,
    tertiaryContainer:
        _overCard(HuxColors.accentTeal, HuxOpacity.activeCardWash),
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
      selectedColor: _overCard(HuxColors.accentMint, HuxOpacity.activeCardWash),
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
      indicatorColor: _overCard(HuxColors.accentMint, HuxOpacity.iconChip),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelMedium?.copyWith(
          color: selected ? HuxColors.accentMint : HuxColors.mutedText,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? HuxColors.accentMint : HuxColors.mutedText,
        );
      }),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? HuxColors.accentMint
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
      actionTextColor: HuxColors.accentMint,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HuxSpacing.sm),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: HuxColors.accentMint,
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
        borderSide: const BorderSide(color: HuxColors.accentMint),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: HuxColors.accentMint,
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
        foregroundColor: HuxColors.accentMint,
        side: const BorderSide(color: HuxColors.accentMint),
        minimumSize: const Size(0, huxMinTapTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HuxRadii.chip),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: HuxColors.accentMint,
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
