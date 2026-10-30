/// Soft 3D objects (clay style), drawn in code: no image assets, crisp
/// at any size, tinted by any colour, and gently floating. One shared
/// light (top-left), one shared ground shadow, so every object in the
/// app reads as part of the same little world.
///
/// Motion: a slow bob and a slight turn, ~3 s per loop. Off when the
/// user asks the OS to reduce motion, and off under `flutter test`
/// (repeating animations never "settle").
library;

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/profile/feature_catalog.dart';

enum Hux3D {
  ring,
  moon,
  steps,
  bowl,
  leaf,
  family,
  cube,
  drop,
  heart,
  bubble,
  book,
  sun,
  clock,
  flame,
  pill,
  dumbbell,
  person,
  parent,
  phone,
  watch,
  band,
  smartRing,
  egg,
  laptop,
  chart,
}

/// The object that stands for a feature.
Hux3D hux3dFor(FeatureId id) => switch (id) {
      FeatureId.sleepRegularity => Hux3D.moon,
      FeatureId.targetBedtime => Hux3D.moon,
      FeatureId.nightShiftMode => Hux3D.moon,
      FeatureId.weeklyStory => Hux3D.book,
      FeatureId.indianJournal => Hux3D.book,
      FeatureId.doctorReport => Hux3D.book,
      FeatureId.shaadiMode => Hux3D.heart,
      FeatureId.examMode => Hux3D.cube,
      FeatureId.fastingMode => Hux3D.sun,
      FeatureId.airAndHeatAlerts => Hux3D.sun,
      FeatureId.effortTarget => Hux3D.ring,
      FeatureId.nextStepTargets => Hux3D.steps,
      FeatureId.walkAfterMeal => Hux3D.steps,
      FeatureId.beginnerWalkPlan => Hux3D.steps,
      FeatureId.zeroTo5k => Hux3D.flame,
      FeatureId.proteinGap => Hux3D.bowl,
      FeatureId.sitTooLong => Hux3D.clock,
      FeatureId.streaksMonthly => Hux3D.flame,
      FeatureId.aiCoach => Hux3D.bubble,
      FeatureId.familyCircle => Hux3D.family,
      FeatureId.medicineReminders => Hux3D.pill,
      FeatureId.cycleTracker => Hux3D.drop,
      FeatureId.homeWorkouts => Hux3D.dumbbell,
    };

class Hux3DObject extends StatefulWidget {
  final Hux3D kind;
  final Color color;
  final double size;

  /// Null = float unless reduce-motion is on (and never in tests).
  final bool? animate;

  const Hux3DObject(this.kind, {super.key, required this.color, this.size = 56, this.animate});

  static final bool _inTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  @override
  State<Hux3DObject> createState() => _Hux3DObjectState();
}

class _Hux3DObjectState extends State<Hux3DObject> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 3000 + widget.kind.index * 97 % 900),
    value: (widget.kind.index * 0.137) % 1.0,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final on = widget.animate ?? (!reduce && !Hux3DObject._inTest);
    if (on && !_c.isAnimating) {
      _c.repeat();
    } else if (!on && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(painter: _ObjectPainter(widget.kind, widget.color, _c.value)),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

const _deep = Color(0xFF1A0B30);

Color _light(Color c, double t) => Color.lerp(c, Colors.white, t)!;
Color _dark(Color c, double t) => Color.lerp(c, _deep, t)!;

class _ObjectPainter extends CustomPainter {
  final Hux3D kind;
  final Color color;
  final double t; // 0..1 loop

  _ObjectPainter(this.kind, this.color, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final wave = math.sin(t * 2 * math.pi);
    final lift = (wave + 1) / 2; // 0..1

    // Ground shadow: tighter and darker when the object is low.
    final shadow = Paint()
      ..color = _deep.withValues(alpha: 0.16 + 0.08 * (1 - lift))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * s);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(50 * s, 92 * s), width: (52 - 8 * lift) * s, height: 9 * s),
      shadow,
    );

    canvas.save();
    canvas.translate(50 * s, (46 - 4 * lift) * s);
    canvas.rotate(0.06 * math.sin(t * 2 * math.pi + 1.2));
    canvas.translate(-50 * s, -46 * s);
    canvas.scale(s);
    _draw(canvas);
    canvas.restore();
  }

  /// Fill [path] as a lit clay surface, then a soft highlight.
  void _clay(Canvas canvas, Path path, Color base, {double gloss = 0.7, Alignment light = const Alignment(-0.5, -0.6)}) {
    final b = path.getBounds();
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: light,
          radius: 1.15,
          colors: [_light(base, 0.5), base, _dark(base, 0.38)],
          stops: const [0, 0.5, 1],
        ).createShader(b),
    );
    canvas.save();
    canvas.clipPath(path);
    // Bounce light on the lower edge, then the specular spot.
    canvas.drawOval(
      Rect.fromLTWH(b.left + b.width * 0.15, b.bottom - b.height * 0.22, b.width * 0.7, b.height * 0.4),
      Paint()
        ..color = _light(base, 0.3).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawOval(
      Rect.fromLTWH(b.left + b.width * 0.18, b.top + b.height * 0.1, b.width * 0.3, b.height * 0.2),
      Paint()
        ..color = Colors.white.withValues(alpha: gloss)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.restore();
  }

  Path _circle(double x, double y, double r) => Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r));

  Path _rrect(double l, double tp, double w, double h, double r) =>
      Path()..addRRect(RRect.fromLTRBR(l, tp, l + w, tp + h, Radius.circular(r)));

  void _draw(Canvas c) {
    switch (kind) {
      case Hux3D.ring:
        final ring = Path.combine(PathOperation.difference, _circle(50, 50, 32), _circle(50, 50, 15));
        _clay(c, ring, color);
        // Hole depth: darker inner lip on the top edge.
        c.save();
        c.clipPath(ring);
        c.drawCircle(
          const Offset(52, 53),
          18,
          Paint()
            ..color = _dark(color, 0.5).withValues(alpha: 0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        c.restore();
        _clay(c, _circle(19, 50, 8), Colors.white, gloss: 0.9); // the pearl
      case Hux3D.moon:
        final moon = Path.combine(PathOperation.difference, _circle(48, 50, 32), _circle(64, 38, 27));
        _clay(c, moon, color, light: const Alignment(-0.7, 0.1));
        _clay(c, _circle(76, 22, 4), _light(color, 0.6), gloss: 0.9);
        _clay(c, _circle(84, 40, 2.5), _light(color, 0.6), gloss: 0.9);
      case Hux3D.steps:
        _clay(c, _rrect(14, 54, 20, 30, 10), _light(color, 0.35));
        _clay(c, _rrect(40, 40, 20, 44, 10), _light(color, 0.15));
        _clay(c, _rrect(66, 22, 20, 62, 10), color);
      case Hux3D.bowl:
        final rim = Rect.fromCenter(center: const Offset(50, 52), width: 76, height: 22);
        c.drawOval(rim, Paint()..color = _dark(const Color(0xFFF3EFF7), 0.18));
        _clay(c, _circle(38, 46, 12), color);
        _clay(c, _circle(58, 42, 13), const Color(0xFFF2B33D));
        _clay(c, _circle(70, 51, 8), const Color(0xFF5BBF6A));
        final body = Path()
          ..moveTo(12, 52)
          ..arcTo(Rect.fromCenter(center: const Offset(50, 52), width: 76, height: 60), math.pi, -math.pi, false)
          ..arcTo(rim, 0, math.pi, false)
          ..close();
        _clay(c, body, const Color(0xFFF7F4FA), gloss: 0.5, light: const Alignment(-0.6, -0.2));
        c.drawPath(
          Path()..addArc(rim, 0, math.pi),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white,
        );
      case Hux3D.leaf:
        final leaf = Path()
          ..moveTo(50, 14)
          ..cubicTo(84, 30, 84, 66, 50, 86)
          ..cubicTo(16, 66, 16, 30, 50, 14)
          ..close();
        c.save();
        c.translate(50, 50);
        c.rotate(-0.35);
        c.translate(-50, -50);
        _clay(c, leaf, color);
        c.drawLine(
          const Offset(50, 22),
          const Offset(50, 80),
          Paint()
            ..color = _dark(color, 0.3).withValues(alpha: 0.6)
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
        c.restore();
      case Hux3D.family:
        _clay(c, _circle(66, 40, 17), _light(color, 0.35));
        _clay(c, _circle(40, 54, 23), color);
        _clay(c, _circle(74, 70, 11), const Color(0xFFF2B33D));
      case Hux3D.cube:
        final top = Path()..addPolygon(const [Offset(50, 16), Offset(82, 32), Offset(50, 48), Offset(18, 32)], true);
        final left = Path()..addPolygon(const [Offset(18, 32), Offset(50, 48), Offset(50, 84), Offset(18, 68)], true);
        final right = Path()..addPolygon(const [Offset(50, 48), Offset(82, 32), Offset(82, 68), Offset(50, 84)], true);
        Paint face(Color col) => Paint()
          ..color = col
          ..style = PaintingStyle.fill;
        Paint edge(Color col) => Paint()
          ..color = col
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeJoin = StrokeJoin.round;
        for (final (p, col) in [(left, color), (right, _dark(color, 0.3)), (top, _light(color, 0.45))]) {
          c.drawPath(p, edge(col));
          c.drawPath(p, face(col));
        }
        c.drawOval(
          const Rect.fromLTWH(34, 24, 18, 8),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      case Hux3D.drop:
        final drop = Path()
          ..moveTo(50, 10)
          ..cubicTo(62, 28, 80, 44, 80, 60)
          ..arcToPoint(const Offset(20, 60), radius: const Radius.circular(30))
          ..cubicTo(20, 44, 38, 28, 50, 10)
          ..close();
        _clay(c, drop, color, gloss: 0.85);
      case Hux3D.heart:
        final heart = Path()
          ..moveTo(50, 84)
          ..cubicTo(18, 64, 10, 44, 20, 28)
          ..cubicTo(30, 14, 46, 18, 50, 32)
          ..cubicTo(54, 18, 70, 14, 80, 28)
          ..cubicTo(90, 44, 82, 64, 50, 84)
          ..close();
        _clay(c, heart, color, gloss: 0.85);
      case Hux3D.bubble:
        final bubble = Path()
          ..addRRect(RRect.fromLTRBR(12, 16, 88, 68, const Radius.circular(24)))
          ..addPolygon(const [Offset(28, 60), Offset(22, 84), Offset(46, 66)], true);
        _clay(c, bubble, color);
        for (final x in [34.0, 50.0, 66.0]) {
          _clay(c, _circle(x, 42, 5.5), Colors.white, gloss: 0.9);
        }
      case Hux3D.book:
        c.save();
        c.translate(50, 50);
        c.rotate(-0.18);
        c.translate(-50, -50);
        _clay(c, _rrect(30, 20, 52, 64, 8), const Color(0xFFF7F4FA), gloss: 0.4);
        _clay(c, _rrect(20, 16, 54, 66, 9), color);
        c.drawRRect(
          RRect.fromLTRBR(30, 30, 64, 36, const Radius.circular(3)),
          Paint()..color = Colors.white.withValues(alpha: 0.75),
        );
        c.drawRRect(
          RRect.fromLTRBR(30, 42, 56, 46, const Radius.circular(2)),
          Paint()..color = Colors.white.withValues(alpha: 0.5),
        );
        c.restore();
      case Hux3D.sun:
        c.save();
        c.translate(50, 50);
        c.rotate(t * math.pi / 2);
        for (var i = 0; i < 8; i++) {
          c.rotate(math.pi / 4);
          _clay(c, _rrect(-4, -44, 8, 14, 4), _light(color, 0.2), gloss: 0.5);
        }
        c.restore();
        _clay(c, _circle(50, 50, 24), color, gloss: 0.85);
      case Hux3D.clock:
        _clay(c, _circle(50, 50, 34), color);
        _clay(c, _circle(50, 50, 25), const Color(0xFFF7F4FA), gloss: 0.4, light: const Alignment(0.4, 0.6));
        final hand = Paint()
          ..color = _deep
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;
        final a = t * 2 * math.pi;
        c.drawLine(const Offset(50, 50), Offset(50 + 15 * math.sin(a), 50 - 15 * math.cos(a)), hand);
        c.drawLine(const Offset(50, 50), const Offset(50, 36), hand);
        c.drawCircle(const Offset(50, 50), 3.5, Paint()..color = color);
      case Hux3D.flame:
        final outer = Path()
          ..moveTo(50, 8)
          ..cubicTo(66, 28, 80, 40, 78, 60)
          ..cubicTo(76, 78, 62, 86, 50, 86)
          ..cubicTo(38, 86, 22, 78, 22, 60)
          ..cubicTo(22, 46, 32, 38, 38, 26)
          ..cubicTo(42, 34, 46, 38, 50, 40)
          ..cubicTo(52, 28, 52, 18, 50, 8)
          ..close();
        _clay(c, outer, color, gloss: 0.6);
        final core = Path()
          ..moveTo(50, 46)
          ..cubicTo(60, 56, 64, 64, 62, 72)
          ..cubicTo(60, 80, 54, 82, 50, 82)
          ..cubicTo(46, 82, 38, 80, 38, 70)
          ..cubicTo(38, 62, 44, 56, 50, 46)
          ..close();
        _clay(c, core, const Color(0xFFFFC44D), gloss: 0.8);
      case Hux3D.pill:
        c.save();
        c.translate(50, 50);
        c.rotate(-0.6);
        c.translate(-50, -50);
        final left = Path()
          ..addRRect(RRect.fromLTRBAndCorners(16, 34, 50, 66,
              topLeft: const Radius.circular(16), bottomLeft: const Radius.circular(16)));
        final right = Path()
          ..addRRect(RRect.fromLTRBAndCorners(50, 34, 84, 66,
              topRight: const Radius.circular(16), bottomRight: const Radius.circular(16)));
        _clay(c, right, const Color(0xFFF7F4FA), gloss: 0.6);
        _clay(c, left, color);
        c.restore();
      case Hux3D.dumbbell:
        _clay(c, _rrect(24, 45, 52, 10, 5), const Color(0xFF8F8AA0), gloss: 0.6);
        _clay(c, _rrect(10, 28, 18, 44, 7), color);
        _clay(c, _rrect(72, 28, 18, 44, 7), color);
      case Hux3D.person:
        _clay(c, _rrect(26, 50, 48, 38, 22), color);
        _clay(c, _circle(50, 30, 16), _light(color, 0.55), gloss: 0.8);
      case Hux3D.parent:
        _clay(c, _rrect(46, 46, 42, 40, 20), _light(color, 0.3));
        _clay(c, _circle(67, 30, 13), _light(color, 0.65), gloss: 0.8);
        _clay(c, _rrect(12, 58, 34, 28, 16), color);
        _clay(c, _circle(29, 44, 11), _light(color, 0.55), gloss: 0.8);
      case Hux3D.phone:
        _clay(c, _rrect(28, 8, 44, 84, 12), const Color(0xFF2A2238), gloss: 0.5);
        c.drawRRect(
          RRect.fromLTRBR(32, 14, 68, 86, const Radius.circular(8)),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_light(color, 0.35), color, const Color(0xFF4453D6)],
            ).createShader(const Rect.fromLTRB(32, 14, 68, 86)),
        );
        c.drawRRect(RRect.fromLTRBR(44, 17, 56, 21, const Radius.circular(2)), Paint()..color = const Color(0xFF2A2238));
        c.drawOval(
          const Rect.fromLTWH(35, 18, 12, 30),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      case Hux3D.watch:
        _clay(c, _rrect(38, 2, 24, 96, 10), _dark(color, 0.15), gloss: 0.4);
        _clay(c, _rrect(24, 26, 52, 50, 16), const Color(0xFF2A2238), gloss: 0.6);
        c.drawRRect(RRect.fromLTRBR(30, 32, 70, 70, const Radius.circular(11)), Paint()..color = const Color(0xFF120A1F));
        c.drawArc(
          const Rect.fromLTRB(38, 39, 62, 63),
          -math.pi / 2,
          math.pi * 2 * (0.55 + 0.25 * math.sin(t * 2 * math.pi)).clamp(0.1, 0.95),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round
            ..color = color,
        );
        _clay(c, _rrect(76, 44, 5, 12, 2.5), const Color(0xFF8F8AA0), gloss: 0.5);
      case Hux3D.band:
        _clay(c, _rrect(40, 2, 20, 96, 10), color, gloss: 0.5);
        _clay(c, _rrect(32, 28, 36, 44, 16), const Color(0xFF2A2238), gloss: 0.7);
        c.drawRRect(
          RRect.fromLTRBR(38, 36, 62, 64, const Radius.circular(10)),
          Paint()..color = _light(color, 0.2).withValues(alpha: 0.85),
        );
      case Hux3D.smartRing:
        // A ring seen at an angle: outer band minus the inner opening.
        final outer = Path()..addOval(const Rect.fromLTRB(12, 26, 88, 78));
        final inner = Path()..addOval(const Rect.fromLTRB(24, 34, 76, 66));
        _clay(c, Path.combine(PathOperation.difference, outer, inner), color, gloss: 0.9);
        // Inner wall: the far side of the band, a darker metal.
        c.save();
        c.clipPath(inner);
        c.drawOval(
          const Rect.fromLTRB(24, 40, 76, 76),
          Paint()..color = _dark(color, 0.35),
        );
        c.restore();
        c.drawRRect(RRect.fromLTRBR(42, 69, 58, 76, const Radius.circular(3)), Paint()..color = const Color(0xFF120A1F));
      case Hux3D.egg:
        _clay(c, Path()..addOval(const Rect.fromLTRB(28, 12, 72, 86)), const Color(0xFFFFF4E2), gloss: 0.8);
      case Hux3D.laptop:
        _clay(c, _rrect(22, 16, 56, 42, 6), const Color(0xFF2A2238), gloss: 0.4);
        c.drawRRect(RRect.fromLTRBR(26, 20, 74, 54, const Radius.circular(3)), Paint()..color = _light(color, 0.2));
        final base = Path()..addPolygon(const [Offset(14, 62), Offset(86, 62), Offset(92, 72), Offset(8, 72)], true);
        _clay(c, base, const Color(0xFFB9B4C7), gloss: 0.5);
      case Hux3D.chart:
        _clay(c, _rrect(14, 58, 18, 26, 6), _light(color, 0.4));
        _clay(c, _rrect(38, 42, 18, 42, 6), _light(color, 0.2));
        _clay(c, _rrect(62, 24, 18, 60, 6), color);
        _clay(c, _circle(71, 14, 6), Colors.white, gloss: 0.9);
    }
  }

  @override
  bool shouldRepaint(_ObjectPainter o) => o.t != t || o.kind != kind || o.color != color;
}
