/// Petal chart: one petal per food around a centre bowl, each showing
/// its share. More foods → more petals (up to 8; the rest are "Other").
/// Each petal glows from the centre in its own colour.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/food/plate_shares.dart';
import '../theme/hux_tokens.dart';
import 'hux/hux_3d.dart';
import 'hux/hux_kit.dart';

/// One colour per petal, in order (also used by the list under the chart).
const petalColors = [
  HuxColors.ringFood,
  HuxColors.ringSteps,
  HuxColors.accentPink,
  HuxColors.ringSleep,
  HuxColors.ringHabit,
  HuxColors.ringHeart,
  Color(0xFF2F8FE0),
  HuxColors.accentPurple,
];

class PetalChart extends StatelessWidget {
  final List<PlateShare> shares;
  final double size;

  const PetalChart({super.key, required this.shares, this.size = 300});

  @override
  Widget build(BuildContext context) {
    final n = shares.length;
    if (n == 0) return SizedBox(width: size, height: size);
    final geo = _PetalGeometry(size, n);
    return Semantics(
      label: 'Plate: ${shares.map((s) => '${s.name} ${s.percent} percent').join(', ')}',
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutBack,
          builder: (context, t, _) => SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PetalPainter(
                      n: n,
                      grow: t,
                      petal: HuxColors.card,
                      shadow: HuxColors.shadow,
                      dark: HuxPalette.current.dark,
                    ),
                  ),
                ),
                for (var i = 0; i < n; i++)
                  Positioned(
                    left: geo.labelCenter(i).dx - geo.labelWidth / 2,
                    top: geo.labelCenter(i).dy - geo.labelHeight / 2,
                    width: geo.labelWidth,
                    height: geo.labelHeight,
                    child: Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${shares[i].percent}%',
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: geo.percentFont, fontWeight: FontWeight.w800, height: 1.1, color: huxInk)),
                          Text(shares[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: geo.nameFont, fontWeight: FontWeight.w600, height: 1.2, color: huxMuted)),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  left: size / 2 - geo.hub,
                  top: size / 2 - geo.hub,
                  width: geo.hub * 2,
                  height: geo.hub * 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: HuxColors.card,
                      border: Border.all(color: HuxColors.bg, width: 3),
                      boxShadow: [BoxShadow(color: HuxColors.shadow, blurRadius: 10, offset: const Offset(0, 3))],
                    ),
                    child: Center(
                      child: Hux3DObject(Hux3D.bowl, color: HuxColors.ringFood, size: geo.hub * 1.45, animate: false),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared sizes, so the painter and the labels agree.
class _PetalGeometry {
  final double size;
  final int n;

  _PetalGeometry(this.size, this.n);

  double get length => size / 2 - 4;
  double get hub => size * 0.115;

  /// Half the petal's width: as wide as its slice of the circle allows.
  double get halfWidth {
    final byAngle = n <= 2 ? double.infinity : length * 0.64 * math.tan(math.pi / n) * 0.94;
    return math.min(length * 0.40, byAngle);
  }

  double angle(int i) => -math.pi / 2 + i * 2 * math.pi / n;

  Offset labelCenter(int i) {
    final r = length * 0.66;
    return Offset(size / 2 + r * math.cos(angle(i)), size / 2 + r * math.sin(angle(i)));
  }

  double get labelWidth => math.max(44, halfWidth * 2 - 6);
  double get labelHeight => 44;
  double get percentFont => n <= 5 ? 20 : (n <= 6 ? 18 : 16);
  double get nameFont => n <= 6 ? 13 : 11.5;
}

class _PetalPainter extends CustomPainter {
  final int n;
  final double grow;
  final Color petal;
  final Color shadow;
  final bool dark;

  _PetalPainter({required this.n, required this.grow, required this.petal, required this.shadow, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final geo = _PetalGeometry(size.width, n);
    final len = geo.length * grow.clamp(0.0, 1.2);
    final hw = geo.halfWidth * grow.clamp(0.0, 1.2);
    final inner = geo.hub * 0.6;
    if (len <= inner) return;

    // One petal, pointing up from the centre.
    final path = Path()
      ..moveTo(0, -inner)
      ..cubicTo(hw * 0.55, -inner, hw, -len * 0.42, hw, -len * 0.66)
      ..cubicTo(hw, -len * 0.90, hw * 0.58, -len, 0, -len)
      ..cubicTo(-hw * 0.58, -len, -hw, -len * 0.90, -hw, -len * 0.66)
      ..cubicTo(-hw, -len * 0.42, -hw * 0.55, -inner, 0, -inner)
      ..close();

    for (var i = 0; i < n; i++) {
      final color = petalColors[i % petalColors.length];
      canvas.save();
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(i * 2 * math.pi / n);
      canvas.drawPath(
        path.shift(const Offset(0, 2)),
        Paint()
          ..color = shadow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawPath(path, Paint()..color = petal);
      // The glow: strongest by the bowl, gone before the petal's tip.
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: dark ? 0.85 : 0.70),
              color.withValues(alpha: dark ? 0.40 : 0.30),
              color.withValues(alpha: 0),
            ],
            stops: const [0.12, 0.5, 0.92],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: len)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PetalPainter o) =>
      o.n != n || o.grow != grow || o.petal != petal || o.shadow != shadow || o.dark != dark;
}
