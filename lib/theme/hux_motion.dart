/// HUX Motion
/// ------------
/// The small set of motion primitives that make pages feel alive
/// instead of static: staggered entrances, counting numerals, press
/// feedback, and a breathing recovery dot.
///
/// HARD RULE (see HuxMotion in hux_tokens.dart): every animation here
/// COMPLETES. No `repeat()`, ever — several widget tests drive the
/// tree with `pumpAndSettle`, which hangs until animations go quiet.
/// "Alive" comes from things settling gracefully, not looping.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hux_tokens.dart';

/// One-shot fade + slide-up entrance, staggered by [index] so a column
/// of cards cascades in instead of popping as a block.
///
/// Stateless-by-design trade-off: a ListView rebuilds children that
/// scroll back into view, which replays the entrance. With the small
/// slide distance and quick fade this reads as intentional life, not
/// jank — and it keeps the widget free of keep-alive bookkeeping.
class HuxEntrance extends StatelessWidget {
  final int index;
  final Widget child;

  const HuxEntrance({super.key, this.index = 0, required this.child});

  @override
  Widget build(BuildContext context) {
    final delay = HuxMotion.stagger * index;
    final total = HuxMotion.base + delay;
    // The delay is expressed as an Interval so one TweenAnimationBuilder
    // covers delay + animation and still completes deterministically.
    final start = delay.inMilliseconds / total.inMilliseconds;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: HuxMotion.easeOut),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, HuxMotion.slideDistance * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// A numeral that counts up from zero to [value] once, formatted by
/// [format] (so "432 minutes" can render as "7:12" mid-flight).
class HuxCountUp extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle? style;

  const HuxCountUp({
    super.key,
    required this.value,
    required this.format,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: HuxMotion.slow,
      curve: HuxMotion.easeOut,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}

/// Press-scale feedback: the child dips to [HuxMotion.pressScale]
/// while a finger is down. Uses a raw [Listener] so it never competes
/// with the child's own tap handling (ListTile/InkWell taps still
/// land normally).
class HuxTapScale extends StatefulWidget {
  final Widget child;

  const HuxTapScale({super.key, required this.child});

  @override
  State<HuxTapScale> createState() => _HuxTapScaleState();
}

class _HuxTapScaleState extends State<HuxTapScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? HuxMotion.pressScale : 1,
        duration: HuxMotion.quick,
        curve: HuxMotion.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// The recovery dot with a FINITE breathing halo: two damped pulses
/// after load, then still. `sin(t·2π·2)·(1−t)` gives two cycles that
/// fade out — alive on arrival, quiet afterwards (and pumpAndSettle-
/// safe, per the file-level rule).
class HuxPulseDot extends StatelessWidget {
  final Color color;
  final double size;

  const HuxPulseDot({super.key, required this.color, this.size = 12});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: HuxMotion.pulse,
      curve: Curves.linear,
      builder: (context, t, _) {
        final wave = math.sin(t * math.pi * 4) * (1 - t);
        final haloAlpha =
            (HuxOpacity.headerGlow * (0.6 + 0.4 * wave)).clamp(0.0, 1.0);
        final haloBlur = HuxSpacing.md * (1 + 0.5 * wave);
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: haloAlpha),
                blurRadius: haloBlur,
                spreadRadius: HuxSpacing.xs / 2,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One-shot grow-in for charts: drives a 0→1 factor the chart scales
/// its values by, so bars rise and lines draw up from the baseline on
/// first build. Data swaps afterwards are animated by fl_chart's own
/// implicit lerp (swapAnimationDuration).
class HuxChartGrowIn extends StatelessWidget {
  final Widget Function(BuildContext context, double t) builder;

  const HuxChartGrowIn({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: HuxMotion.slow,
      curve: HuxMotion.easeOut,
      builder: (context, t, _) => builder(context, t),
    );
  }
}
