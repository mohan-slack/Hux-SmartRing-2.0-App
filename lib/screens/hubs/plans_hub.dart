/// Plans tab (UI 2.0): one dark Journeys tile on top, four plan tiles
/// (two words + a small shape each), then nudges as a short list.
/// Details live one tap deeper, not in paragraphs here.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/profile/feature_catalog.dart';
import '../../theme/hux_tokens.dart';
import '../../widgets/hux/hux_3d.dart';
import '../../widgets/hux/hux_kit.dart';

class PlansHub extends StatelessWidget {
  final void Function(FeatureId id) onOpenFeature;
  final VoidCallback onOpenModes;
  final VoidCallback? onSeeAll;

  /// Guided multi-day programs (sleep, food, movement); null hides it.
  final VoidCallback? onOpenJourneys;

  const PlansHub({super.key, required this.onOpenFeature, required this.onOpenModes, this.onSeeAll, this.onOpenJourneys});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxGlass.navClearance),
      children: [
        const Text('Plans', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: huxInk)),
        const SizedBox(height: 16),
        if (onOpenJourneys != null) ...[
          _JourneysTile(onTap: onOpenJourneys!),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: _PlanTile(
                label: 'Walk & run',
                value: '5 plans',
                shape: _Shape.climb,
                object: Hux3D.steps,
                color: HuxColors.ringSteps,
                onTap: () => onOpenFeature(FeatureId.beginnerWalkPlan),
                extra: _Link('Zero to 5K', () => onOpenFeature(FeatureId.zeroTo5k)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PlanTile(
                label: 'Food',
                value: 'Protein',
                shape: _Shape.plate,
                object: Hux3D.bowl,
                color: HuxColors.ringFood,
                onTap: () => onOpenFeature(FeatureId.proteinGap),
                extra: _Link('Log a meal', () => onOpenFeature(FeatureId.proteinGap)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _PlanTile(
                label: 'Habits',
                value: 'Journal',
                shape: _Shape.week,
                object: Hux3D.book,
                color: HuxColors.ringHabit,
                onTap: () => onOpenFeature(FeatureId.indianJournal),
                extra: _Link('Streaks', () => onOpenFeature(FeatureId.streaksMonthly)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PlanTile(
                label: 'Life modes',
                value: '5 modes',
                shape: _Shape.countdown,
                object: Hux3D.cube,
                color: HuxColors.accentPurple,
                onTap: onOpenModes,
                extra: _Link('Choose a mode', onOpenModes),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const HuxTileLabel('Nudges'),
        const SizedBox(height: 10),
        HuxTile(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _NudgeRow('After meals', 'Short walk', () => onOpenFeature(FeatureId.walkAfterMeal)),
              const Divider(height: 1, indent: 16, endIndent: 16, color: HuxColors.hairline),
              _NudgeRow('Sit too long', 'Desk days', () => onOpenFeature(FeatureId.sitTooLong)),
              const Divider(height: 1, indent: 16, endIndent: 16, color: HuxColors.hairline),
              _NudgeRow('Air & heat', 'Your city', () => onOpenFeature(FeatureId.airAndHeatAlerts)),
            ],
          ),
        ),
        if (onSeeAll != null) ...[
          const SizedBox(height: 12),
          Center(child: TextButton(onPressed: onSeeAll, child: const Text('All features'))),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _JourneysTile extends StatelessWidget {
  final VoidCallback onTap;

  const _JourneysTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget program(String name, int days, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(color: huxNightTrack, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 2),
                Text('$days days', style: const TextStyle(fontSize: 13, color: huxNightMuted)),
                const SizedBox(height: 10),
                _DayDots(days: days, color: color),
              ],
            ),
          ),
        );

    return Semantics(
      button: true,
      label: 'Journeys: Sleep Reset, 21 days. Fit in 30, 30 days.',
      excludeSemantics: true,
      child: Material(
        color: huxNight,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Journeys',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                          Text('One card a day', style: TextStyle(fontSize: 13, color: huxNightMuted)),
                        ],
                      ),
                    ),
                    Hux3DObject(Hux3D.moon, color: HuxColors.ringSleep, size: 50),
                    SizedBox(width: 4),
                    Hux3DObject(Hux3D.flame, color: Color(0xFFF567B5), size: 50),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    program('Sleep Reset', 21, HuxColors.ringSleep),
                    const SizedBox(width: 10),
                    program('Fit in 30', 30, const Color(0xFFF567B5)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One dot per day of the program, in rows of up to 10.
class _DayDots extends StatelessWidget {
  final int days;
  final Color color;

  const _DayDots({required this.days, required this.color});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (var i = 0; i < days; i++)
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == 0 ? color : color.withValues(alpha: 0.28),
                shape: BoxShape.circle,
              ),
            ),
        ],
      );
}

class _Link {
  final String label;
  final VoidCallback onTap;

  const _Link(this.label, this.onTap);
}

enum _Shape { climb, plate, week, countdown }

class _PlanTile extends StatelessWidget {
  final String label;
  final String value;
  final _Shape shape;
  final Hux3D object;
  final Color color;
  final VoidCallback onTap;
  final _Link extra;

  const _PlanTile({
    required this.label,
    required this.value,
    required this.shape,
    required this.object,
    required this.color,
    required this.onTap,
    required this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color.alphaBlend(color.withValues(alpha: 0.12), Colors.white),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
      onTap: onTap,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HuxTileLabel(label),
                      const SizedBox(height: 4),
                      Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: huxInk)),
                    ],
                  ),
                ),
                Hux3DObject(object, color: color, size: 52),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 30,
            width: double.infinity,
            child: CustomPaint(painter: _ShapePainter(shape, color)),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: extra.onTap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              minimumSize: const Size(0, 40),
              foregroundColor: huxInk,
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(extra.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
        ],
      ),
      ),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  final _Shape shape;
  final Color color;

  _ShapePainter(this.shape, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()..color = color.withValues(alpha: 0.22);
    final full = Paint()..color = color;
    switch (shape) {
      case _Shape.climb:
        // Weeks getting longer: five rising bars.
        const n = 5;
        final w = (size.width - (n - 1) * 6) / n;
        for (var i = 0; i < n; i++) {
          final h = size.height * (0.3 + 0.7 * i / (n - 1));
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(i * (w + 6), size.height - h, w, h), const Radius.circular(4)),
            i == n - 1 ? full : soft,
          );
        }
      case _Shape.plate:
        // A protein ring two-thirds full, then the plate's other parts.
        final r = size.height / 2 - 3;
        final c = Offset(r + 3, size.height / 2);
        final stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round;
        canvas.drawCircle(c, r, stroke..color = color.withValues(alpha: 0.22));
        canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, math.pi * 1.35, false, stroke..color = color);
        final x0 = c.dx + r + 12;
        final bw = size.width - x0;
        for (var i = 0; i < 3; i++) {
          final y = 4.0 + i * 9;
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x0, y, bw, 5), const Radius.circular(3)), soft);
          canvas.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTWH(x0, y, bw * [0.7, 0.45, 0.85][i], 5), const Radius.circular(3)), full);
        }
      case _Shape.week:
        // Seven days, five kept.
        const n = 7;
        final d = math.min(size.height, (size.width - (n - 1) * 6) / n);
        for (var i = 0; i < n; i++) {
          canvas.drawCircle(Offset(d / 2 + i * (d + 6), size.height / 2), d / 2, i < 5 ? full : soft);
        }
      case _Shape.countdown:
        // Days to the big day, the last one marked.
        const n = 8;
        final w = (size.width - (n - 1) * 4) / n;
        for (var i = 0; i < n; i++) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(i * (w + 4), 4, w, size.height - 8), const Radius.circular(4)),
            i == n - 1 ? full : soft,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_ShapePainter o) => o.shape != shape || o.color != color;
}

class _NudgeRow extends StatelessWidget {
  final String title;
  final String detail;
  final VoidCallback onTap;

  const _NudgeRow(this.title, this.detail, this.onTap);

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          child: Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: huxInk))),
              Text(detail, style: const TextStyle(fontSize: 14, color: huxMuted)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: huxMuted, size: 20),
            ],
          ),
        ),
      );
}
