/// HUX Design Tokens — "vivid gradient" edition
/// -----------------------------------------------
/// The ONLY place a hex code or a spacing/radius/blur magic number is
/// allowed to live. Screens import this file and reference its
/// constants/helpers — never `Color(0x...)`, never a bare `16.0` for
/// padding. `hux_theme.dart` and `hux_glass.dart` are the only other
/// files that read these directly; everything else should get what it
/// needs from `Theme.of(context)` plus the per-domain helpers below.
///
/// SECOND full palette pass (first was "dark liquid glass" — mint/teal
/// on charcoal-grey, still visible in git history). This pass moves to
/// a near-black stage and a saturated four-color brand set — Hot Pink,
/// Cherry (red-orange), Solid Purple, and Athens Indigo — each named
/// for exactly what it looks like, no metaphor. Cards move from
/// translucent glass to solid/gradient fills as the primary surface
/// (see hux_glass.dart's GlassPanel, kept for the surfaces that haven't
/// been repainted yet — dialogs, sheets, Trends/Story in the interim).
/// Text ON a bright accent fill still keeps its own near-black ink,
/// same role [inkOnAccent] always played.
library;

import 'package:flutter/material.dart';

import '../core/meaning/daily_readout.dart';

class HuxColors {
  const HuxColors._();

  // ---- the dark stage -------------------------------------------------
  /// App background — near-black, not charcoal-grey: the vivid cards
  /// are the light sources now, so the stage recedes further than the
  /// first (glass) pass needed it to.
  static const bg = Color(0xFF0A0A0D);

  /// Elevated OPAQUE surface: dialogs, sheets, pickers, snackbars, and
  /// any card not yet repainted to a bespoke gradient (see
  /// [accentIndigo]'s doc comment for which Today/Modes cards use one).
  static const card = Color(0xFF17161C);

  /// A step above [card] for the snackbar, so it reads as floating.
  static const cardElevated = Color(0xFF201F27);

  // ---- text -----------------------------------------------------------
  /// Primary text — near-white with a faint warm/violet cast to match
  /// the new palette. ~17:1 on [bg].
  static const ink = Color(0xFFF3F1F6);

  /// Secondary text — ~7.5:1 on [bg].
  static const mutedText = Color(0xFF9C97A8);

  /// Text ON a bright accent fill (Hot Pink buttons, the amber banner):
  /// a near-black ink of its own, kept for exactly this job.
  static const inkOnAccent = Color(0xFF1A0E17);

  // ---- brand accents ---------------------------------------------------
  /// The hero accent — Hot Pink. Glows on dark, readable AS text on
  /// [bg] (~5.2:1 — large numerals/labels only, not fine print; see
  /// [accentCherry] for a slightly higher-contrast alternative where
  /// body-sized text needs it).
  static const accentPink = Color(0xFFF567B5);

  /// Cherry — a saturated red-orange, the app's second bright accent
  /// (glyphs/labels/lines, ~6.8:1 on [bg]).
  static const accentCherry = Color(0xFFFF6A4D);

  /// Solid Purple — depth end of the Hot-Pink gradient family; fills
  /// and gradient ends only, too dim to read as text on dark.
  static const accentPurple = Color(0xFF622585);

  /// Athens Indigo — the palette's fourth color, reserved for
  /// device/connectivity-themed surfaces (Battery, Test Ring) per its
  /// literal signal-wave motif in the reference design. Fills and
  /// glows only, same too-dim-for-text role as [accentPurple].
  static const accentIndigo = Color(0xFF182788);

  // ---- glass (kept for surfaces not yet repainted — see file header) -----
  /// Translucent white layers that make a surface read as glass over
  /// the dark stage. Pre-baked alphas (not `withValues` at call sites)
  /// so "how glassy" stays a single tunable per role.
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
  /// (see HuxBackground) — pink top-left, purple bottom-right.
  static const bgGlowPink = Color(0x24F567B5); // pink 14%
  static const bgGlowPurple = Color(0x33622585); // purple 20%

  // ---- recovery states (dot, header glow, chart accents) -----------------
  /// A SEPARATE semantic system from the brand accents above — these
  /// read as a wellness traffic-light (good/neutral/caution), which the
  /// brand palette doesn't attempt to encode. Unchanged across both
  /// design passes on purpose.
  static const recharged = Color(0xFF3FBF78);
  static const steady = Color(0xFF2DD4BF);
  static const stretched = Color(0xFFF5A524);
  static const rundown = Color(0xFFF0705F);
  static const learning = Color(0xFF8A9490);

  // ---- source banners (meaning unchanged — these stay SOLID) -------------
  /// DEMO — simulated ring data. [inkOnAccent] text on this is ~10:1.
  /// Deliberately never a brand gradient: the banner is a safety
  /// feature and must never blend into the design.
  static const demoAmber = Color(0xFFFFC107);

  /// DEV — health app data. White text on this is ~7.2:1.
  static const devBlueGrey = Color(0xFF455A64);

  // ---- vivid card families (hux_vivid_cards.dart, hux_cards.dart) --------
  /// Per-card gradient END colors that aren't already covered by a
  /// named brand accent above (the START of each gradient below IS a
  /// brand accent — [accentCherry]/[accentPink]/[accentPurple]/
  /// [accentIndigo] — named once, reused; only the darker END of each
  /// gradient needs its own token, since it's specific to that fade).
  static const vividCherryEnd = Color(0xFF1A0805); // Cherry -> near-black
  static const vividPinkPurpleMid = Color(0xFF3A1240); // pink -> purple midpoint wash

  /// Decorative-only heart-rate waveform stroke — a lighter tint of
  /// [accentCherry], never a data series (see hux_vivid_cards.dart).
  static const vividHeartWave = Color(0xFFFFB199);

  /// Stage-breakdown/segmented-bar tints, lightest to darkest: Light
  /// sleep reads as the palest tint, Deep as the brightest/most
  /// saturated — same "brightness = more of the deep, restorative
  /// stage" convention the first design pass used.
  static const vividSleepLight = Color(0xFFF6D3EA);
  static const vividSleepRem = Color(0xFFF567B5);
  static const vividSleepDeep = Color(0xFF9B3FA8);

  // ---- Modes/Lifestyle image cards (modes_screen.dart) -------------------
  /// The bottom-scrim end color on a photo mode card — [bg] at ~80%,
  /// not pure black, so the scrim reads as "this app's dark" rather
  /// than a generic vignette.
  static const modeScrimEnd = Color(0xCC0A0A0D);
}

class HuxRadii {
  const HuxRadii._();

  static const card = 20.0;
  static const chip = 999.0;

  /// The Today-screen vivid highlight cards read as bolder/chunkier than
  /// the glass system's cards, per the reference — a larger radius.
  static const vividCard = 28.0;
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

  /// Secondary/label text on a vivid highlight card (hux_vivid_cards.dart)
  /// — white text over a saturated gradient reads as too heavy at full
  /// opacity for anything but the hero numeral.
  static const vividSecondaryText = 0.72;

  /// The flat "no data" track a vivid card's bar collapses to when it
  /// has nothing real to show — faint on the same logic as [chartTrack].
  static const vividEmptyTrack = 0.14;

  /// [HuxGlassCorner]'s diagonal sheen and top-rim line — faint enough
  /// to read as a light catching a glass edge, not a visible white
  /// smear over a saturated gradient card or a busy photo.
  static const glassCornerSheen = 0.16;
  static const glassCornerRim = 0.55;

  /// The drop shadow [HuxHoverLift] adds while a card is hovered.
  static const hoverShadow = 0.35;

  /// [HuxHoverLift]'s accent-colored outer glow — bright enough that
  /// "this card is the active one" reads clearly even over a busy
  /// photo background, not just a faint tint.
  static const hoverGlow = 0.55;

  /// A mode-card icon chip's backdrop — more opaque than [iconChip]
  /// since it sits on top of a busy photo, not a flat surface, and
  /// needs real contrast to stay legible.
  static const modeIconChipBg = 0.68;
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

  /// Blur radius for [HuxHoverLift]'s hover shadow.
  static const hoverShadowBlur = 24.0;

  /// Blur radius for [HuxHoverLift]'s accent glow.
  static const hoverGlowBlur = 18.0;
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
/// accent (Hot Pink backdrop glow, Cherry glyph) rather than a
/// different invented color per mode.
class HuxModeAccent {
  const HuxModeAccent._();

  static const background = HuxColors.accentPink;
  static const foreground = HuxColors.accentCherry;
}
