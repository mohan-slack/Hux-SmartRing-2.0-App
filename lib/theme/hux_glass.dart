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

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'hux_tokens.dart';

/// The app's dark stage: deep green-black with two soft radial glows
/// (mint top-left, teal bottom-right). Painted ONCE behind the whole
/// shell — screens never paint their own background.
class HuxBackground extends StatelessWidget {
  const HuxBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: HuxColors.bg),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-1.2, -1.1),
                radius: 1.4,
                colors: [HuxColors.bgGlowMint, Colors.transparent],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(1.3, 1.2),
                radius: 1.5,
                colors: [HuxColors.bgGlowTeal, Colors.transparent],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A liquid-glass panel: translucent white gradient fill, 1px glass
/// stroke, a subtle top-rim highlight, and an optional colored outer
/// glow + inner tint for accented panels (Today's state-tinted header,
/// the active mode card). Pass [frosted] for hero panels that should
/// carry a REAL backdrop blur — see the file-level performance note.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// An optional wash blended under the glass fill (e.g. a recovery
  /// state color at [HuxOpacity.headerWash], or the active-mode mint).
  final Color? tint;

  /// An optional soft outer glow in this color — the "lit from within"
  /// look on hero/active panels. Rendered as a BoxShadow, not a blur.
  final Color? glow;

  /// Border override for emphasized panels (defaults to the standard
  /// glass stroke).
  final Color? strokeColor;

  /// Real backdrop blur — budgeted for hero panels only.
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

    Widget body = Stack(
      children: [
        // Tint underlay first, glass gradient over it — a Container
        // can't have both a color and a gradient at once.
        if (tint != null) Positioned.fill(child: ColoredBox(color: tint!)),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [HuxColors.glassFillTop, HuxColors.glassFillBottom],
              ),
            ),
          ),
        ),
        // The top rim highlight — the specular edge that sells
        // "glass" more than the fill does.
        const Positioned(
          top: 0,
          left: HuxSpacing.lg,
          right: HuxSpacing.lg,
          child: SizedBox(
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    HuxColors.glassHighlight,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: strokeColor ?? HuxColors.glassStroke),
          ),
          padding: padding,
          child: child,
        ),
      ],
    );

    if (frosted) {
      body = BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: HuxGlass.panelBlurSigma,
          sigmaY: HuxGlass.panelBlurSigma,
        ),
        child: body,
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: glow == null
            ? null
            : [
                BoxShadow(
                  color: glow!.withValues(alpha: HuxOpacity.panelGlow),
                  blurRadius: HuxGlass.glowBlurRadius,
                  spreadRadius: HuxGlass.glowSpread,
                ),
              ],
      ),
      child: ClipRRect(borderRadius: radius, child: body),
    );
  }
}
