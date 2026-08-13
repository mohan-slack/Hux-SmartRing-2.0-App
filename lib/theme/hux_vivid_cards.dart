/// HUX Vivid Cards
/// -----------------
/// A small, deliberately separate "highlight reel" of saturated gradient
/// cards for the Today screen — Heart Rate, Sleep Scores, Calories.
/// Everywhere else in this app is the dark "liquid glass" system
/// (hux_glass.dart); these three are solid gradient fills on purpose,
/// styled after a common fitness-dashboard reference. They live
/// ALONGSIDE the glass system, not in place of it — see hux_cards.dart
/// for the translucent glass catalog these complement.
///
/// SCOPE, deliberately narrower than the reference this was styled
/// after: only three cards exist here, because only three of the
/// reference's metrics have a real, non-fabricated data source in this
/// app — a live heart-rate reading, a real sleep-efficiency + stage
/// breakdown, and today's active-energy total. Body fat %, a step
/// distance in Km, and a workout/hiking session have NO backing data
/// anywhere in [HealthSnapshot] or [SleepSession] — HUX rings don't
/// measure body composition or GPS distance, and this app does no food
/// logging — so building those three would mean showing invented
/// numbers. Per this app's one non-negotiable rule (never fabricate a
/// reading), they simply don't exist here. [VividCaloriesCard] also
/// drops the reference's "Eaten"/"Left" ring-gauge framing for the same
/// reason: that implies a calorie goal and food log this app has
/// neither of — only a plain "burned since midnight" total is real.
///
/// NULL RULE, same convention as hux_cards.dart: a null value never
/// renders as if it were a confirmed zero. Each widget's doc comment
/// below spells out its null case.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hux_glass.dart';
import 'hux_motion.dart';
import 'hux_tokens.dart';

/// Shared gradient-card shell: rounded corners, solid gradient fill,
/// consistent padding. Not [GlassPanel] — these cards are opaque by
/// design, not translucent. A decorative [HuxGlassCorner] sheen sits on
/// top of the gradient, and the whole card lifts on hover via
/// [HuxHoverLift].
class _VividCardShell extends StatelessWidget {
  final Gradient gradient;
  final Widget child;

  const _VividCardShell({required this.gradient, required this.child});

  static final _radius = BorderRadius.circular(HuxRadii.vividCard);

  @override
  Widget build(BuildContext context) {
    return HuxHoverLift(
      borderRadius: _radius,
      child: ClipRRect(
        borderRadius: _radius,
        child: Container(
          padding: const EdgeInsets.all(HuxSpacing.lg),
          decoration: BoxDecoration(gradient: gradient),
          child: Stack(
            children: [
              child,
              HuxGlassCorner(borderRadius: _radius),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle? _vividLabelStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .bodySmall
    ?.copyWith(color: HuxColors.ink.withValues(alpha: HuxOpacity.vividSecondaryText));

TextStyle? _vividNumeralStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .titleLarge
    ?.copyWith(fontSize: HuxType.numeralLarge, fontWeight: FontWeight.w700, color: HuxColors.ink);

/// A purely decorative double-wave squiggle — NOT a rendering of real
/// waveform data (this app has no intra-day heart-rate time series, only
/// point readings). Static, not animated: chrome, never mistakable for a
/// live signal.
class _HeartWavePainter extends CustomPainter {
  final Color color;
  const _HeartWavePainter({required this.color});

  Path _wave(Size size, double phase) {
    final path = Path();
    const steps = 40;
    for (var i = 0; i <= steps; i++) {
      final x = size.width * i / steps;
      final y = size.height / 2 +
          math.sin((i / steps) * 4 * math.pi + phase) * size.height / 2 * (1 - (i / steps - 0.5).abs() * 1.4);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawPath(_wave(size, 0), paint);
    canvas.drawPath(_wave(size, math.pi), paint..color = color.withValues(alpha: 0.5));
  }

  @override
  bool shouldRepaint(covariant _HeartWavePainter oldDelegate) => color != oldDelegate.color;
}

/// A live instantaneous heart-rate reading (NOT last night's overnight
/// average — see [averageBpm] for that) on a saturated red gradient.
///
/// NULL: [bpm] null shows an em-dash and hides the decorative wave (a
/// wave under no reading would read as a live signal that isn't there).
/// [averageBpm] null shows an em-dash in the footer rather than omitting
/// the line, so the card's height never jumps once a reading arrives.
class VividHeartRateCard extends StatelessWidget {
  final double? bpm;
  final double? averageBpm;

  const VividHeartRateCard({super.key, required this.bpm, this.averageBpm});

  @override
  Widget build(BuildContext context) {
    return _VividCardShell(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [HuxColors.accentCherry, HuxColors.vividCherryEnd],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Heart Rate', style: _vividLabelStyle(context)),
          const SizedBox(height: HuxSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              bpm == null
                  ? Text('—', style: _vividNumeralStyle(context))
                  : HuxCountUp(value: bpm!, format: (v) => v.round().toString(), style: _vividNumeralStyle(context)),
              if (bpm != null)
                Padding(
                  padding: const EdgeInsets.only(left: HuxSpacing.xs, bottom: HuxSpacing.xs),
                  child: Text('bpm', style: _vividLabelStyle(context)),
                ),
            ],
          ),
          const SizedBox(height: HuxSpacing.md),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: bpm == null
                ? null
                : const CustomPaint(painter: _HeartWavePainter(color: HuxColors.vividHeartWave)),
          ),
          const SizedBox(height: HuxSpacing.md),
          Text(
            'Average : ${averageBpm == null ? '—' : averageBpm!.round().toString()} bpm',
            style: _vividLabelStyle(context),
          ),
        ],
      ),
    );
  }
}

/// One stage's share of a night's sleep, as a fraction of TOTAL SLEEP
/// (never total time in bed) — matches [SleepSession.stageTotal]'s own
/// convention.
class VividSleepSegment {
  final String label;
  final double? percentOfSleep;
  final Color color;

  const VividSleepSegment({required this.label, required this.percentOfSleep, required this.color});
}

/// Sleep efficiency (time asleep / time in bed, a real, standard sleep-
/// tracking metric — never a fabricated "quality score") plus a stacked
/// bar of [segments], on a green gradient.
///
/// NULL: when [efficiencyPercent] is null or every segment's
/// [VividSleepSegment.percentOfSleep] is null (no sleep data at all —
/// same guard [_LastNightStats] already applies before rendering
/// anything from a night), the bar renders as a single flat grey block
/// with no boundary labels, and the headline shows an em-dash — never a
/// zero-filled bar, which would misrepresent "no data" as "no sleep."
class VividSleepScoreCard extends StatelessWidget {
  final double? efficiencyPercent;
  final List<VividSleepSegment> segments;

  const VividSleepScoreCard({super.key, required this.efficiencyPercent, required this.segments});

  bool get _hasData => efficiencyPercent != null && segments.any((s) => (s.percentOfSleep ?? 0) > 0);

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (sum, s) => sum + (s.percentOfSleep ?? 0));
    // Cumulative boundary fractions (0.0..1.0) for the labels under the
    // bar — derived from the REAL segment percentages, never hardcoded.
    final boundaries = <double>[0];
    var running = 0.0;
    for (final s in segments) {
      running += (s.percentOfSleep ?? 0);
      boundaries.add(total == 0 ? 0 : (running / total).clamp(0.0, 1.0));
    }

    return _VividCardShell(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [HuxColors.accentPink, HuxColors.accentPurple],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Sleep Scores', style: _vividLabelStyle(context)),
          const SizedBox(height: HuxSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _hasData
                  ? HuxCountUp(
                      value: efficiencyPercent!, format: (v) => v.round().toString(), style: _vividNumeralStyle(context))
                  : Text('—', style: _vividNumeralStyle(context)),
              if (_hasData)
                Padding(
                  padding: const EdgeInsets.only(left: HuxSpacing.xs, bottom: HuxSpacing.xs),
                  child: Text('%', style: _vividLabelStyle(context)),
                ),
            ],
          ),
          const SizedBox(height: HuxSpacing.lg),
          if (!_hasData)
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: HuxColors.ink.withValues(alpha: HuxOpacity.vividEmptyTrack),
                borderRadius: BorderRadius.circular(HuxSpacing.xs),
              ),
            )
          else ...[
            // Absolute pixel positioning (LayoutBuilder + Positioned),
            // not Row+Expanded+flex: flex must be >= 1 in Flutter, which
            // would force even a genuinely zero-minute stage to draw a
            // visible sliver. Positioned widths can be exactly zero.
            LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth;
                return SizedBox(
                  height: 16,
                  child: Stack(
                    children: [
                      for (var i = 0; i < segments.length; i++)
                        if (boundaries[i + 1] > boundaries[i])
                          Positioned(
                            left: boundaries[i] * trackWidth,
                            child: Text(
                              segments[i].label,
                              style: _vividLabelStyle(context),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: HuxSpacing.xs),
            LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(HuxSpacing.xs),
                  child: SizedBox(
                    height: 10,
                    child: Stack(
                      children: [
                        for (var i = 0; i < segments.length; i++)
                          Positioned(
                            left: boundaries[i] * trackWidth,
                            width: (boundaries[i + 1] - boundaries[i]) * trackWidth,
                            top: 0,
                            bottom: 0,
                            child: Container(color: segments[i].color),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: HuxSpacing.xs),
            LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                height: 16,
                child: Stack(
                  children: [
                    for (final b in boundaries)
                      Positioned(
                        left: (b * constraints.maxWidth - 14).clamp(0.0, constraints.maxWidth - 28),
                        child: SizedBox(
                          width: 28,
                          child: Text(
                            '${(b * 100).round()}%',
                            textAlign: TextAlign.center,
                            style: _vividLabelStyle(context),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Today's cumulative active-energy total, same Cherry red-orange
/// family as [VividHeartRateCard] (matching the reference's Cherry
/// Apple/Breath Volume pairing) — no "Left"/"Eaten" ring, since this
/// app has no calorie goal or food log to back that framing (see this
/// file's header).
///
/// NULL: em-dash, flame icon dims to the muted-text color.
class VividCaloriesCard extends StatelessWidget {
  final double? kcal;

  const VividCaloriesCard({super.key, required this.kcal});

  @override
  Widget build(BuildContext context) {
    return _VividCardShell(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [HuxColors.accentCherry, HuxColors.vividCherryEnd],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Calories', style: _vividLabelStyle(context)),
              Icon(
                Icons.local_fire_department,
                color: kcal == null ? HuxColors.mutedText : HuxColors.ink,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: HuxSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              kcal == null
                  ? Text('—', style: _vividNumeralStyle(context))
                  : HuxCountUp(value: kcal!, format: (v) => v.round().toString(), style: _vividNumeralStyle(context)),
              Padding(
                padding: const EdgeInsets.only(left: HuxSpacing.xs, bottom: HuxSpacing.xs),
                child: Text('kcal', style: _vividLabelStyle(context)),
              ),
            ],
          ),
          const SizedBox(height: HuxSpacing.xs),
          Text('Active energy since midnight', style: _vividLabelStyle(context)),
        ],
      ),
    );
  }
}
