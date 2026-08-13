/// The very first thing a signed-out user sees — before Login/Sign Up.
/// Full-bleed brand hero (`assets/images/welcome/welcome-hero.jpg`,
/// already carrying the HUX wordmark/tagline baked into the image) with
/// scrims fading into the app's own near-black stage top and bottom, so
/// the transition into [LoginScreen]/[SignUpScreen] reads as one
/// continuous surface rather than a hard cut between screens.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../theme/hux_motion.dart';
import '../../theme/hux_tokens.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class WelcomeScreen extends StatelessWidget {
  final AuthService authService;

  const WelcomeScreen({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HuxColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // One-shot fade-in so the hero arrives softly rather than
          // popping in fully opaque on first frame.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: HuxMotion.slow,
            curve: HuxMotion.easeOut,
            builder: (context, t, child) => Opacity(opacity: t, child: child),
            child: Image.asset(
              'assets/images/welcome/welcome-hero.jpg',
              fit: BoxFit.cover,
            ),
          ),
          // Top scrim: the source image's headline sits right at its own
          // top edge, which (at full-bleed cover) lands flush against the
          // status bar with no breathing room — this softens that seam
          // instead of shifting/cropping the image itself.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.1],
                  colors: [HuxColors.bg.withValues(alpha: 0.75), Colors.transparent],
                ),
              ),
            ),
          ),
          // Bottom scrim blending the photo into HuxColors.bg — kept
          // TIGHT to the very bottom edge (not a big wash up the whole
          // lower half) so the dock shot stays visible; the glass CTA
          // carries its own translucent fill for contrast regardless,
          // this scrim is really only for the plain "Log In" text below it.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.8, 1.0],
                  colors: [Colors.transparent, HuxColors.bg],
                ),
              ),
            ),
          ),
          // bottom: false — deliberately sits past the home-indicator
          // safe-area inset so the CTA rides lower, past the dock's
          // charging-puck art instead of cutting across it; the fixed
          // padding below still keeps it clear of the literal screen edge.
          SafeArea(
            bottom: false,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(HuxSpacing.xl, 0, HuxSpacing.xl, HuxSpacing.lg),
                  child: Column(
                    children: [
                      HuxEntrance(
                        index: 0,
                        child: _GlassArrowButton(
                          label: 'Get Started',
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => SignUpScreen(authService: authService),
                          )),
                        ),
                      ),
                      const SizedBox(height: HuxSpacing.md),
                      HuxEntrance(
                        index: 1,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => LoginScreen(authService: authService),
                          )),
                          child: RichText(
                            text: TextSpan(
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: HuxColors.ink),
                              children: const [
                                TextSpan(text: 'Already have an account? '),
                                TextSpan(text: 'Log In', style: TextStyle(color: HuxColors.accentPink)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The welcome screen's CTA: a compact, auto-width "liquid glass" pill
/// (real BackdropFilter blur — a one-off hero control, squarely the
/// "budgeted" case the file-level rule in hux_glass.dart carves out)
/// ending in a solid accent arrow chip, rather than a full-width solid
/// button — reads as "continue," Apple-style, without the heavier visual
/// weight a full-bleed filled button carries over a busy photo.
class _GlassArrowButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GlassArrowButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: HuxTapScale(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(HuxRadii.chip),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: HuxGlass.panelBlurSigma, sigmaY: HuxGlass.panelBlurSigma),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(HuxSpacing.xl, HuxSpacing.sm, HuxSpacing.sm, HuxSpacing.sm),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(HuxRadii.chip),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [HuxColors.glassFillTop, HuxColors.glassFillBottom],
                    ),
                    border: Border.all(color: HuxColors.glassStroke),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: HuxColors.ink)),
                      const SizedBox(width: HuxSpacing.md),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: HuxColors.accentPink),
                        child: const Icon(Icons.arrow_forward_rounded, size: 18, color: HuxColors.inkOnAccent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
