/// HUX Design Tokens
/// -------------------
/// The ONLY place a hex code or a spacing/radius magic number is
/// allowed to live. Screens import this file and reference its
/// constants/helpers — never `Color(0x...)`, never a bare `16.0` for
/// padding. `hux_theme.dart` is the only other file that reads these
/// directly to build a `ThemeData`; everything else should be able to
/// get what it needs from `Theme.of(context)` plus the handful of
/// per-domain helpers below (`RecoveryStateColor`, `HuxModeAccent`).
///
/// LIGHT MODE ONLY this phase. Deliberately structured as plain static
/// constants (not yet a `ColorScheme.dark()`-style pair) so a dark
/// variant can be added later without every screen changing — the
/// day it's needed, `HuxColors` becomes a small light/dark pair and
/// `hux_theme.dart` picks one based on `Brightness`.

import 'package:flutter/material.dart';

import '../core/meaning/daily_readout.dart';

class HuxColors {
  const HuxColors._();

  // ---- neutrals ----------------------------------------------------
  static const ink = Color(0xFF16211E);
  static const paper = Color(0xFFF4F8F6);
  static const card = Color(0xFFFFFFFF);
  static const hairline = Color(0xFFE2E8E6);
  static const mutedText = Color(0xFF5C6B67);

  // ---- brand accents -------------------------------------------------
  static const accentMint = Color(0xFF9AE6C8);
  static const accentDeepTeal = Color(0xFF0F766E);

  // ---- recovery states (dot, header wash, chart accents) -------------
  static const recharged = Color(0xFF2F9E62);
  static const steady = Color(0xFF0F766E);
  static const stretched = Color(0xFFD97706);
  static const rundown = Color(0xFFC2554A);
  static const learning = Color(0xFF8A9490);

  // ---- source banners (meaning unchanged from prior phases) ----------
  /// DEMO — simulated ring data. Black text on this is >=4.5:1 (~13:1).
  static const demoAmber = Color(0xFFFFC107);

  /// DEV — health app data. Darker than Material's stock blueGrey so
  /// white text clears 4.5:1 (~7.2:1) — the stock swatch only manages
  /// ~4.0:1 and would fail the contrast bar.
  static const devBlueGrey = Color(0xFF455A64);
}

class HuxRadii {
  const HuxRadii._();

  static const card = 20.0;
  static const chip = 999.0;
}

/// The 4/8/12/16/24/32 spacing scale. Name them by feel (xs..xxl), not
/// by number, so a screen reads "space it like a section gap" rather
/// than a bare `24.0` whose intent isn't obvious at the call site.
class HuxSpacing {
  const HuxSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Named opacity levels for tints/washes — kept here so "how strong is
/// a wash" is a single tunable, not a scattered set of `withValues`
/// calls that drift apart over time.
class HuxOpacity {
  const HuxOpacity._();

  /// The soft state-tinted wash behind Today's header block.
  static const headerWash = 0.10;

  /// The personal sleep-duration target band on the Trends bar chart.
  static const targetBand = 0.25;

  /// The circular backdrop behind a mode/lifestyle accent icon.
  static const iconChip = 0.20;

  /// The active-mode-card mint wash on the Modes screen.
  static const activeCardWash = 0.16;
}

/// Minimum touch target side length (Material/HIG accessibility floor).
const huxMinTapTarget = 44.0;

/// Maps a [RecoveryState] to its token color — the ONE place that
/// mapping lives. Used for the Today recovery dot, the header wash,
/// and small chart accents. Never a full-screen color flood.
extension RecoveryStateColor on RecoveryState {
  Color get huxColor => switch (this) {
        RecoveryState.recharged => HuxColors.recharged,
        RecoveryState.steady => HuxColors.steady,
        RecoveryState.stretched => HuxColors.stretched,
        RecoveryState.rundown => HuxColors.rundown,
        RecoveryState.learning => HuxColors.learning,
      };
}

/// The shared visual treatment for a mode/lifestyle accent icon chip
/// (flag/heart/grad-cap/bedtime/twilight) — one consistent brand
/// accent (mint backdrop, deep-teal glyph) rather than a different
/// invented color per mode.
class HuxModeAccent {
  const HuxModeAccent._();

  static const background = HuxColors.accentMint;
  static const foreground = HuxColors.accentDeepTeal;
}
