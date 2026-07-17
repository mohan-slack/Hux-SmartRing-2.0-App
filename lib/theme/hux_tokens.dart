/// HUX Design Tokens — dark "liquid glass" edition
/// -------------------------------------------------
/// The ONLY place a hex code or a spacing/radius/blur magic number is
/// allowed to live. Screens import this file and reference its
/// constants/helpers — never `Color(0x...)`, never a bare `16.0` for
/// padding. `hux_theme.dart` and `hux_glass.dart` are the only other
/// files that read these directly; everything else should get what it
/// needs from `Theme.of(context)` plus the per-domain helpers below.
///
/// DARK-FIRST since the liquid-glass pass: a deep green-black base
/// with soft mint/teal radial glows behind everything, translucent
/// "glass" surfaces on top (see hux_glass.dart for why most glass here
/// is translucency + stroke + highlight rather than a real
/// BackdropFilter blur), and the brand mint doing the glowing. The
/// original light palette lives on only in the two places light
/// matters: text ON a bright accent (buttons, the amber banner) keeps
/// a near-black ink of its own.

import 'package:flutter/material.dart';

import '../core/meaning/daily_readout.dart';

class HuxColors {
  const HuxColors._();

  // ---- the dark stage -------------------------------------------------
  /// App background — dark charcoal-grey (with a whisper of the brand
  /// green), NOT pitch black: per design review, pages read as grey so
  /// the glass panels and glows have somewhere to sit above them.
  static const bg = Color(0xFF1A1F1D);

  /// Elevated OPAQUE surface: dialogs, sheets, pickers, snackbars —
  /// places where see-through would hurt readability.
  static const card = Color(0xFF242A28);

  /// A step above [card] for the snackbar, so it reads as floating.
  static const cardElevated = Color(0xFF2D3431);

  // ---- text -----------------------------------------------------------
  /// Primary text — near-white with the brand's green cast.
  /// ~16:1 on [bg], comfortably >4.5:1 on every glass surface.
  static const ink = Color(0xFFEDF5F1);

  /// Secondary text — ~7:1 on [bg].
  static const mutedText = Color(0xFF93A69F);

  /// Text ON a bright accent fill (mint buttons, the amber banner):
  /// the old light-theme ink, kept for exactly this job. ~12:1 on
  /// mint, ~10:1 on the demo amber.
  static const inkOnAccent = Color(0xFF10201B);

  // ---- brand accents ---------------------------------------------------
  /// The hero accent — glows on dark. Readable AS text on [bg] (~11:1).
  static const accentMint = Color(0xFF9AE6C8);

  /// Bright teal for glyphs/labels/lines on dark surfaces (~8.6:1 on
  /// [bg]) — [accentDeepTeal] is too dim to read on dark and is kept
  /// for fills and gradient ends only.
  static const accentTeal = Color(0xFF2DD4BF);

  /// Depth end of the brand gradient; fills, never text on dark.
  static const accentDeepTeal = Color(0xFF0F766E);

  // ---- glass ------------------------------------------------------------
  /// Translucent white layers that make a surface read as glass over
  /// the dark stage. Pre-baked alphas (not `withValues` at call sites)
  /// so "how glassy" stays a single tunable per role. Strengthened in
  /// the review round — the first cut read as flat cards, not glass.
  static const glassFillTop = Color(0x1FFFFFFF); // white 12% — panel top
  static const glassFillBottom = Color(0x0DFFFFFF); // white 5% — panel base
  static const glassStroke = Color(0x2EFFFFFF); // white 18% — 1px border
  static const glassHighlight = Color(0x73FFFFFF); // white 45% — top rim

  /// Hairline for dividers/tracks on dark — white 10%.
  static const hairline = Color(0x1AFFFFFF);

  /// Faint full-height slot track behind chart bars — white 7%.
  static const chartTrack = Color(0x12FFFFFF);

  /// The "misty" grey bars on the sleep chart (every night EXCEPT the
  /// highlighted latest one, per the analytics-card reference): lit at
  /// the top, fading toward the base.
  static const chartBarGreyTop = Color(0x61FFFFFF); // white 38%
  static const chartBarGreyBottom = Color(0x24FFFFFF); // white 14%

  // ---- background glows --------------------------------------------------
  /// The two soft radial glows painted once behind the whole app
  /// (see HuxBackground) — mint top-left, teal bottom-right. Strong
  /// enough that frosted panels visibly blur them (that's what makes
  /// the glassmorphism READ as glass).
  static const bgGlowMint = Color(0x249AE6C8); // mint 14%
  static const bgGlowTeal = Color(0x330F766E); // deep teal 20%

  // ---- recovery states (dot, header glow, chart accents) -----------------
  /// Brightened from the light-theme set so they carry on dark. Used
  /// for dots, washes, and glows — never body text.
  static const recharged = Color(0xFF3FBF78);
  static const steady = Color(0xFF2DD4BF);
  static const stretched = Color(0xFFF5A524);
  static const rundown = Color(0xFFF0705F);
  static const learning = Color(0xFF8A9490);

  // ---- source banners (meaning unchanged — these stay SOLID) -------------
  /// DEMO — simulated ring data. [inkOnAccent] text on this is ~10:1.
  /// Deliberately NOT glass: the banner is a safety feature and must
  /// never blend into the design.
  static const demoAmber = Color(0xFFFFC107);

  /// DEV — health app data. White text on this is ~7.2:1.
  static const devBlueGrey = Color(0xFF455A64);
}

class HuxRadii {
  const HuxRadii._();

  static const card = 20.0;
  static const chip = 999.0;
}

/// The 4/8/12/16/24/32 spacing scale. Named by feel (xs..xxl), not by
/// number, so a screen reads "space it like a section gap" rather than
/// a bare `24.0` whose intent isn't obvious at the call site.
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

  /// The soft state-tinted wash across Today's header glass.
  static const headerWash = 0.10;

  /// The state-colored radial glow inside Today's header panel.
  static const headerGlow = 0.30;

  /// The personal sleep-duration target band on the Trends bar chart —
  /// faint on purpose; the dashed target LINE is the star now.
  static const targetBand = 0.12;

  /// The dashed personal-target line on the sleep chart.
  static const targetLine = 0.90;

  /// The circular backdrop behind a mode/lifestyle accent icon.
  static const iconChip = 0.18;

  /// The active-mode mint wash on cards/strips.
  static const activeCardWash = 0.14;

  /// Outer glow (BoxShadow) behind an accented glass panel.
  static const panelGlow = 0.25;

  /// Neon glow behind a chart line (fl_chart line shadow).
  static const chartLineGlow = 0.45;

  /// Area fill under a chart line, fading to transparent.
  static const chartAreaFill = 0.28;

  /// Halo ring around a chart's endpoint dot.
  static const chartDotHalo = 0.30;

  /// The glass nav bar's fill over the blurred content behind it.
  static const navGlass = 0.72;
}

/// Type-scale numbers that live OUTSIDE the ThemeData text theme:
/// the big stat/chart numerals. The brand rule is "numbers are Space
/// Grotesk", but every display/headline theme slot is Fraunces — so
/// numeral styles are built at the call site from a Space Grotesk
/// slot (titleLarge) plus these token sizes.
class HuxType {
  const HuxType._();

  /// Stat-tile numerals (Today's Last-sleep grid).
  static const numeral = 28.0;

  /// Chart hero numerals (the big value on each Trends card).
  static const numeralLarge = 34.0;
}

/// Structural numbers for the glass treatment itself.
class HuxGlass {
  const HuxGlass._();

  /// Blur sigma for the nav bar's BackdropFilter.
  static const navBlurSigma = 18.0;

  /// Blur sigma for frosted hero panels (GlassPanel(frosted: true)) —
  /// lighter than the nav's, per guidance to keep sigmas moderate.
  static const panelBlurSigma = 14.0;

  /// Outer-glow geometry for accented panels.
  static const glowBlurRadius = 28.0;
  static const glowSpread = -6.0;

  /// Neon-glow blur behind a Trends chart line.
  static const chartGlowBlur = 12.0;

  /// Dash pattern for the personal-target line on the sleep chart.
  static const dashArray = [6, 4];

  /// Bottom clearance scrollables add so their last card can scroll
  /// clear of the floating glass nav bar (nav height + home indicator
  /// + breathing room; the body extends behind the bar).
  static const navClearance = 120.0;
}

/// Motion tokens — every animation in the app is built from these.
/// HARD RULE (test-driven, not taste-driven): every animation must
/// COMPLETE — one-shot entrances, count-ups, grow-ins, finite pulses.
/// Nothing repeats forever, because several widget tests rely on
/// `pumpAndSettle`, which hangs until the tree goes quiet.
class HuxMotion {
  const HuxMotion._();

  /// Tap feedback (press-scale on tiles).
  static const quick = Duration(milliseconds: 140);

  /// Standard transitions: entrance fade/slide, chart data swaps.
  static const base = Duration(milliseconds: 380);

  /// Hero moments: chart grow-in, numeral count-up.
  static const slow = Duration(milliseconds: 700);

  /// Per-item delay in a staggered list entrance.
  static const stagger = Duration(milliseconds: 70);

  /// One damped pulse cycle of the recovery dot's halo.
  static const pulse = Duration(milliseconds: 1600);

  /// How far an entering card slides up from, in logical px.
  static const slideDistance = 14.0;

  /// Pressed-state scale for tap feedback.
  static const pressScale = 0.97;

  static const easeOut = Curves.easeOutCubic;
  static const easeSwap = Curves.easeInOutCubic;
}

/// Minimum touch target side length (Material/HIG accessibility floor).
const huxMinTapTarget = 44.0;

/// Maps a [RecoveryState] to its token color — the ONE place that
/// mapping lives. Used for the Today recovery dot, the header glow,
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
/// accent (mint backdrop glow, bright-teal glyph) rather than a
/// different invented color per mode.
class HuxModeAccent {
  const HuxModeAccent._();

  static const background = HuxColors.accentMint;
  static const foreground = HuxColors.accentTeal;
}
