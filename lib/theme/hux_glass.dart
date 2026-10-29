/// HUX Glass
/// -----------
/// The reusable pieces of the liquid-glass treatment: the shared dark
/// stage every screen sits on, and the translucent panel surface the
/// hero blocks are made of.
///
/// PERFORMANCE NOTE — where real BackdropFilter blur is allowed: blur
/// is one of the most expensive raster operations, so it's budgeted,
/// not scattered. HERO panels (one or two per screen — Today's header,
/// each chart card, the active-mode card, Story's takeaway) opt in
/// with `frosted: true` and get a real backdrop blur over the stage's
/// glows, which is what makes the glassmorphism visibly READ as glass.
/// The MANY small surfaces (stat tiles, list tiles) stay faux —
/// translucent fill + stroke + top highlight — which over a flat
/// gradient reads nearly the same at near-zero GPU cost. The nav bar
/// keeps its own BackdropFilter in app_shell.dart, blurring genuinely
/// scrolling content.

import 'package:flutter/material.dart';

import 'hux_tokens.dart';

/// The app's dark stage: deep green-black with two soft radial glows
/// (mint top-left, teal bottom-right). Painted ONCE behind the whole
/// shell — screens never paint their own background.
class HuxBackground extends StatelessWidget {
  const HuxBackground({super.key});

  /// Light, OxeAI-style stage: soft lavender at the top fading to the
  /// near-white page colour, with a faint pink glow top-left.
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.45],
          colors: [HuxColors.bgTop, HuxColors.bg],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-1.1, -1.05),
                radius: 1.0,
                colors: [HuxColors.bgGlowPink, Colors.transparent],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(1.2, -0.6),
                radius: 1.1,
                colors: [HuxColors.bgGlowPurple, Colors.transparent],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The app's standard card: white, rounded, hairline border and a soft
/// shadow (OxeAI-style). Kept under its old name so every screen picks
/// up the new look without changes.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Optional wash over the white (e.g. a state colour at low alpha).
  final Color? tint;

  /// Optional coloured shadow for hero/active cards.
  final Color? glow;

  /// Border override for emphasised cards.
  final Color? strokeColor;

  /// Ignored in the light theme (kept for API compatibility).
  final bool frosted;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(HuxSpacing.lg),
    this.tint,
    this.glow,
    this.strokeColor,
    this.frosted = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(HuxRadii.card);
    return Container(
      decoration: BoxDecoration(
        color: tint == null ? HuxColors.card : Color.alphaBlend(tint!, HuxColors.card),
        borderRadius: radius,
        border: Border.all(color: strokeColor ?? HuxColors.glassStroke),
        boxShadow: [
          BoxShadow(
            color: glow == null ? HuxColors.shadow : glow!.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: padding,
      child: child,
    );
  }
}

class HuxGlassCorner extends StatelessWidget {
  final BorderRadius borderRadius;

  const HuxGlassCorner({super.key, this.borderRadius = const BorderRadius.all(Radius.circular(HuxRadii.vividCard))});

  /// No sheen in the light theme; kept so existing call sites compile.
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
