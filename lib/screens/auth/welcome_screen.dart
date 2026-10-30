/// The first screen a signed-out user sees: night plum, the HUX
/// wordmark, a live 3D scene (the Charge ring with sleep, food, steps
/// and heart orbiting it), one line, and the two ways in.
library;

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../theme/hux_motion.dart';
import '../../theme/hux_tokens.dart';
import '../../widgets/hux/hux_3d.dart';
import '../../widgets/hux/hux_kit.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class WelcomeScreen extends StatelessWidget {
  final AuthService authService;

  const WelcomeScreen({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: huxNight,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // A soft glow behind the scene, nothing more.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.25),
                radius: 0.9,
                colors: [Color(0xFF3A1A5C), huxNight],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: HuxSpacing.lg),
                  Center(
                    child: Image.asset('assets/images/brand/hux-wordmark-white.png', height: 30, semanticLabel: 'HUX'),
                  ),
                  const Expanded(child: _OrbitScene()),
                  const HuxEntrance(
                    child: Text(
                      'Know your\ncharge.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1.02, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const HuxEntrance(
                    index: 1,
                    child: Text(
                      'Sleep, food and steps, read for you every morning.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 17, height: 1.35, color: huxNightMuted),
                    ),
                  ),
                  const SizedBox(height: 28),
                  HuxEntrance(
                    index: 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: Colors.white,
                        foregroundColor: huxInk,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SignUpScreen(authService: authService),
                      )),
                      child: const Text('Get started', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  HuxEntrance(
                    index: 3,
                    child: TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: Colors.white),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => LoginScreen(authService: authService),
                      )),
                      child: const Text('I have an account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: HuxSpacing.sm),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Charge ring, big, with four small worlds orbiting it on a tilted
/// path: nearer ones grow and pass in front, farther ones shrink and go
/// behind. Loops every ~14 s; still when reduce-motion is on.
class _OrbitScene extends StatefulWidget {
  const _OrbitScene();

  @override
  State<_OrbitScene> createState() => _OrbitSceneState();
}

class _OrbitSceneState extends State<_OrbitScene> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14));

  static final bool _inTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  static const _orbiters = [
    (Hux3D.moon, HuxColors.ringSleep),
    (Hux3D.bowl, HuxColors.ringFood),
    (Hux3D.steps, HuxColors.ringSteps),
    (Hux3D.heart, HuxColors.ringHeart),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce || _inTest) {
      _c.stop();
      _c.value = 0.12;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'The HUX Charge ring with sleep, food, steps and heart around it',
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, box) {
        final side = math.min(box.maxWidth, box.maxHeight);
        final hero = side * 0.52;
        final small = side * 0.2;
        return AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final items = <(double, Widget)>[];
            for (var i = 0; i < _orbiters.length; i++) {
              final a = (_c.value + i / _orbiters.length) * 2 * math.pi;
              final depth = math.sin(a); // -1 far … 1 near
              final scale = 0.72 + 0.28 * (depth + 1) / 2;
              final dx = math.cos(a) * box.maxWidth * 0.40;
              final dy = depth * side * 0.17;
              items.add((
                depth,
                Positioned(
                  key: ValueKey(i),
                  left: box.maxWidth / 2 + dx - small * scale / 2,
                  top: box.maxHeight / 2 + dy - small * scale / 2,
                  child: Opacity(
                    opacity: 0.55 + 0.45 * (depth + 1) / 2,
                    child: Hux3DObject(_orbiters[i].$1, color: _orbiters[i].$2, size: small * scale),
                  ),
                ),
              ));
            }
            items.sort((a, b) => a.$1.compareTo(b.$1));
            final behind = [for (final it in items) if (it.$1 < 0) it.$2];
            final front = [for (final it in items) if (it.$1 >= 0) it.$2];
            return Stack(
              children: [
                ...behind,
                Center(child: Hux3DObject(Hux3D.ring, color: HuxColors.accentPink, size: hero)),
                ...front,
              ],
            );
          },
        );
      }),
    );
  }
}
