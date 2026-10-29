/// The first screen a signed-out user sees: HUX logo, three animated
/// score rings drawn in code (no photos), one line of promise, and the
/// two ways in. Light, OxeAI-style.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../theme/hux_glass.dart';
import '../../theme/hux_motion.dart';
import '../../theme/hux_tokens.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class WelcomeScreen extends StatelessWidget {
  final AuthService authService;

  const WelcomeScreen({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const HuxBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: HuxSpacing.lg),
                  Center(
                    child: Image.asset(
                      'assets/images/brand/hux-wordmark-dark.png',
                      height: 36,
                      semanticLabel: 'HUX',
                    ),
                  ),
                  const Expanded(child: Center(child: _RingsHero())),
                  HuxEntrance(
                    child: Text(
                      'Your body,\nexplained.',
                      textAlign: TextAlign.center,
                      style: text.displaySmall?.copyWith(fontWeight: FontWeight.w700, height: 1.1),
                    ),
                  ),
                  const SizedBox(height: HuxSpacing.md),
                  HuxEntrance(
                    index: 1,
                    child: Text(
                      'Sleep, energy, steps and food — with an AI coach that speaks your language. '
                      'Made for India.',
                      textAlign: TextAlign.center,
                      style: text.bodyLarge?.copyWith(color: HuxColors.mutedText, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: HuxSpacing.xl),
                  HuxEntrance(
                    index: 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SignUpScreen(authService: authService),
                      )),
                      child: const Text('Get Started'),
                    ),
                  ),
                  const SizedBox(height: HuxSpacing.sm),
                  HuxEntrance(
                    index: 3,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => LoginScreen(authService: authService),
                      )),
                      child: Text.rich(
                        TextSpan(
                          style: text.bodyMedium,
                          children: const [
                            TextSpan(text: 'Already have an account? '),
                            TextSpan(
                              text: 'Log In',
                              style: TextStyle(color: HuxColors.accentPink, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: HuxSpacing.md),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three concentric rings (charge, sleep, steps) that sweep in once,
/// with the HUX "H" in the middle. Pure code — no image assets.
class _RingsHero extends StatelessWidget {
  const _RingsHero();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => SizedBox(
        width: 230,
        height: 230,
        child: CustomPaint(
          painter: _RingsPainter(t),
          child: Center(
            child: Opacity(
              opacity: t,
              child: Text(
                'H',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w300,
                      color: HuxColors.accentPurple,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final double t;
  _RingsPainter(this.t);

  static const _rings = [
    (color: HuxColors.ringCharge, value: 0.82),
    (color: HuxColors.ringSleep, value: 0.68),
    (color: HuxColors.ringSteps, value: 0.55),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    const gap = 8.0;
    final center = size.center(Offset.zero);
    for (var i = 0; i < _rings.length; i++) {
      final r = size.width / 2 - stroke / 2 - i * (stroke + gap);
      final rect = Rect.fromCircle(center: center, radius: r);
      canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = _rings[i].color.withValues(alpha: 0.12),
      );
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * _rings[i].value * t,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = _rings[i].color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t;
}
