/// HUX intro — picks up exactly where the native launch screen leaves
/// off (same aurora, same glass ring, same size and centre), then:
/// the pearl pulses, the ring releases, the pearl flows into the H's
/// crossbar, the H glides left, U rises, X turns in, "Know your charge."
///
/// Full (~3 s) on first launch; afterwards a quick fade. Tap to skip.
/// With the system "reduce motion" setting on, always the quick fade.
/// Brand kit: docs/release/BRANDING.md.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

enum IntroMode { off, full, quick }

class HuxIntro extends StatefulWidget {
  final IntroMode mode;
  final Widget child;

  const HuxIntro({super.key, required this.mode, required this.child});

  @override
  State<HuxIntro> createState() => _HuxIntroState();
}

class _HuxIntroState extends State<HuxIntro> with TickerProviderStateMixin {
  static const fullSeconds = 3.0;

  AnimationController? _play;
  late final AnimationController _out =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    if (widget.mode == IntroMode.off) {
      _visible = false;
      return;
    }
    final reduce = SchedulerBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _out.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _visible = false);
    });
    if (widget.mode == IntroMode.full && !reduce) {
      _play = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _out.forward();
        })
        ..forward();
    } else {
      // Quick: hold the launch-screen look for one beat, then fade.
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted) _out.forward();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_visible) precacheImage(const AssetImage(_IntroArt.background), context);
  }

  void _skip() {
    _play?.stop();
    _out.forward();
  }

  @override
  void dispose() {
    _play?.dispose();
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_visible)
          FadeTransition(
            opacity: ReverseAnimation(_out),
            child: Semantics(
              label: 'HUX. Know your charge.',
              button: true,
              onTapHint: 'Skip intro',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _skip,
                child: _play == null
                    ? const _IntroFrame(t: 0)
                    : AnimatedBuilder(
                        animation: _play!,
                        builder: (_, __) => _IntroFrame(t: _play!.value * fullSeconds),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

class _IntroArt {
  static const background = 'assets/splash/splash_bg.png';
  static const u = 'assets/images/brand/intro_u.png';
  static const x = 'assets/images/brand/intro_x.png';
  static const midnight = Color(0xFF1A0B30);
  static const charge = [Color(0xFFFF8FCB), Color(0xFFF567B5), Color(0xFFC93B86), Color(0xFF8B3FD0), Color(0xFF5B6CF0)];
}

// ---- timing helpers ---------------------------------------------------

double _p(double t, double a, double b) => t <= a ? 0 : t >= b ? 1 : (t - a) / (b - a);
double _io(double t) => t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;
double _out(double t) => 1 - math.pow(1 - t, 3).toDouble();
double _back(double t, [double s = 1.5]) {
  final u = t - 1;
  return u * u * ((s + 1) * u + s) + 1;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Geometry shared by the painter and the letter widgets. Units: logical
/// px. The H/U/X numbers are measured from images/logo.png (native px).
class _Layout {
  final Size size;
  _Layout(this.size);

  double get cx => size.width / 2;
  double get cy => size.height / 2;

  // Launch-screen mark: ring radius 66 (splash_mark.png is 800 px at 4x,
  // ring radius 0.33 of it), tube 8.2% / 33.5%, H width 33% / 33.5%.
  static const r0 = 66.0;
  static const t0 = r0 * 0.082 / 0.335;
  static const h0 = r0 * 0.33 / 0.335;

  // Wordmark: 1249 native px wide.
  double get k => math.min(size.width * 0.64, 320) / 1249;
  double get left => cx - 1249 * k / 2;
  double get h1 => 381 * k; // H width in the wordmark
  double get h1x => left + 193.5 * k;
  double get uX => left + 612 * k;
  double get xX => left + 1038 * k;
  double get glyphH => 341 * k;
  double get glyphY => cy + 1.5 * k;
}

class _IntroFrame extends StatelessWidget {
  final double t;

  const _IntroFrame({required this.t});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final l = _Layout(box.biggest);
      final pu = _p(t, 1.1, 1.65);
      final px = _p(t, 1.35, 1.95);
      final pg = _out(_p(t, 2.2, 2.75));

      Widget glyph(String asset, double cx, double width, {double dx = 0, double dy = 0, double scale = 1, double rot = 0, double opacity = 1}) {
        return Positioned(
          left: cx - width / 2 + dx,
          top: l.glyphY - l.glyphH / 2 + dy,
          width: width,
          height: l.glyphH,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: rot,
              child: Transform.scale(scale: scale, child: Image.asset(asset, fit: BoxFit.fill)),
            ),
          ),
        );
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: _IntroArt.midnight),
          Image.asset(_IntroArt.background, fit: BoxFit.cover),
          CustomPaint(painter: _MarkPainter(t, l)),
          if (pu > 0)
            glyph(_IntroArt.u, l.uX, 424 * l.k,
                dx: (1 - _out(pu)) * l.size.width * 0.05,
                dy: (1 - _out(pu)) * l.glyphH * 0.25,
                scale: _lerp(0.82, 1, _back(pu)),
                opacity: pu * 1.7),
          if (px > 0)
            glyph(_IntroArt.x, l.xX, 422 * l.k,
                scale: _lerp(0.55, 1, _back(px)), rot: _lerp(math.pi / 2, 0, _out(px)), opacity: px * 1.7),
          if (pg > 0)
            Positioned(
              left: 0,
              right: 0,
              top: l.cy + l.h1 * 0.62 + (1 - pg) * 20,
              child: Text(
                'Know your charge.',
                textAlign: TextAlign.center,
                style: GoogleFonts.urbanist(
                  fontSize: math.min(l.size.width * 0.045, 20),
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.92 * pg),
                  decoration: TextDecoration.none,
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _MarkPainter extends CustomPainter {
  final double t;
  final _Layout l;

  _MarkPainter(this.t, this.l);

  // H strokes in native logo px (box 381 × 334, stroke 31): left stem,
  // right stem, crossbar (floats free of the left stem — the HUX gap).
  static const _segs = [
    [15.5, 15.5, 15.5, 318.5],
    [365.5, 15.5, 365.5, 318.5],
    [83.5, 166.5, 365.5, 166.5],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(l.cx, l.cy);
    final pulse = math.sin(math.pi * _p(t, 0, 0.3));
    final rel = _io(_p(t, 0.3, 0.8));
    final pm = _io(_p(t, 0.7, 1.4));
    final hw = _lerp(_Layout.h0, l.h1, pm);
    final hx = _lerp(l.cx, l.h1x, pm);

    // ---- glass ring + charge light (releases outward, fades)
    if (rel < 1) {
      final a = 1 - rel;
      final r = _Layout.r0 * _lerp(1, 1.22, rel);
      final tt = _Layout.t0 * _lerp(1, 0.6, rel);
      final rect = Rect.fromCircle(center: c, radius: r);

      canvas.drawCircle(c, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = tt
        ..color = Colors.white.withValues(alpha: 0.10 * a));
      final rim = SweepGradient(
        colors: [Colors.white.withValues(alpha: 0.15 * a), Colors.white.withValues(alpha: 0.65 * a), Colors.white.withValues(alpha: 0.15 * a)],
        stops: const [0, 0.625, 1], // brightest at 225° (top-left, facing the light)
      );
      for (final rr in [r - tt * 0.43, r + tt * 0.43]) {
        canvas.drawCircle(c, rr, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, tt * 0.08)
          ..shader = rim.createShader(Rect.fromCircle(center: c, radius: rr)));
      }

      final fill = const SweepGradient(
        colors: _IntroArt.charge,
        endAngle: math.pi * 1.5,
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect);
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = tt * 0.48
        ..shader = fill
        ..color = Colors.black.withValues(alpha: a);
      canvas.drawArc(rect, -math.pi / 2, math.pi * 1.5, false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = tt * 0.48
            ..shader = fill
            ..color = Colors.black.withValues(alpha: 0.9 * a)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, tt * 0.7));
      canvas.drawArc(rect, -math.pi / 2, math.pi * 1.5, false, arc);
      canvas.drawArc(rect, -math.pi / 2, math.pi * 1.5, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = tt * 0.1
        ..color = Colors.white.withValues(alpha: 0.55 * a));
    }

    // ---- the pearl: pulses, then flows into the crossbar
    final flow = _io(_p(t, 0.3, 0.75));
    final pearlA = 1 - _io(_p(t, 0.7, 0.85));
    if (pearlA > 0) {
      final r = _Layout.r0 * _lerp(1, 1.22, rel);
      final barX = hx - hw / 2 + 83.5 * hw / 381;
      final p = Offset(_lerp(l.cx - r, barX, flow), l.cy);
      final s = _Layout.t0 * 0.62 * (1 + 0.25 * pulse) * _lerp(1, 0.4, flow);
      canvas.drawCircle(p, s * 2.6, Paint()
        ..color = const Color(0xFFFFD6EE).withValues(alpha: 0.55 * pearlA)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 1.6));
      canvas.drawCircle(p, s, Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.38),
          colors: [
            Colors.white.withValues(alpha: pearlA),
            const Color(0xFFFFEEF8).withValues(alpha: pearlA),
            const Color(0xFFDCCDE0).withValues(alpha: pearlA),
          ],
          stops: const [0, 0.35, 1],
        ).createShader(Rect.fromCircle(center: p, radius: s)));
    }

    // ---- the H (glows as the pearl lands)
    final weight = _lerp(1.12, 1.0, pm);
    final k = hw / 381;
    final hh = 334 * k;
    final o = Offset(hx - hw / 2, l.cy - hh / 2);
    final path = Path();
    for (final s in _segs) {
      path
        ..moveTo(o.dx + s[0] * k, o.dy + s[1] * k)
        ..lineTo(o.dx + s[2] * k, o.dy + s[3] * k);
    }
    final glow = 0.3 + 0.35 * _out(_p(t, 0.65, 0.8)) * (1 - _p(t, 0.8, 1.2));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 31 * k * weight
      ..color = Colors.white.withValues(alpha: glow)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, hw / 22));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 31 * k * weight
      ..color = Colors.white);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.t != t || old.l.size != l.size;
}
