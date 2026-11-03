/// Progress → Score: the week out of 100 and what built it. Overall
/// shows a donut of the four parts; each part has its own tab with the
/// 7 days as bars and the plain facts behind the number.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/progress/goal_score.dart';
import '../../core/progress/progress_service.dart';
import '../../core/progress/week_score_loader.dart';
import '../../core/storage/health_store.dart';
import '../../theme/hux_tokens.dart';
import '../../widgets/hux/hux_3d.dart';
import '../../widgets/hux/hux_kit.dart';

({Hux3D object, Color color}) scorePartLook(ScorePart p) => switch (p) {
      ScorePart.sleep => (object: Hux3D.bed, color: HuxColors.ringSleep),
      ScorePart.energy => (object: Hux3D.heart, color: HuxColors.ringCharge),
      ScorePart.move => (object: Hux3D.shoe, color: HuxColors.ringSteps),
      ScorePart.food => (object: Hux3D.bowl, color: HuxColors.ringFood),
    };

class ScoreScreen extends StatefulWidget {
  final HealthStore store;
  final ProgressService progress;
  final Listenable? refreshSignal;
  final DateTime Function()? now;

  const ScoreScreen({super.key, required this.store, required this.progress, this.refreshSignal, this.now});

  @override
  State<ScoreScreen> createState() => _ScoreScreenState();
}

class _ScoreScreenState extends State<ScoreScreen> {
  late Future<WeekScore> _future = _load();

  /// null = Overall.
  ScorePart? _tab;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_reload);
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    final next = _load();
    setState(() {
      _future = next;
    });
  }

  Future<WeekScore> _load() => loadWeekScore(widget.store, widget.progress, now: (widget.now ?? DateTime.now)());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WeekScore>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final score = snap.data;
        if (score == null) {
          return const Center(child: Text("Couldn't work out the score right now."));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, 0, HuxSpacing.lg, HuxGlass.navClearance),
          children: [
            _Tabs(selected: _tab, onSelect: (t) => setState(() => _tab = t)),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey(_tab),
                child: _tab == null
                    ? _Overall(score: score, onOpen: (p) => setState(() => _tab = p))
                    : _PartView(part: score.parts[_tab]!),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Tabs extends StatelessWidget {
  final ScorePart? selected;
  final ValueChanged<ScorePart?> onSelect;

  const _Tabs({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, ScorePart? value) {
      final on = value == selected;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: on,
          showCheckmark: false,
          onSelected: (_) => onSelect(value),
          labelStyle: TextStyle(fontWeight: FontWeight.w700, color: on ? Colors.white : huxInk),
          selectedColor: huxInk,
          backgroundColor: HuxColors.card,
          shape: const StadiumBorder(side: BorderSide(color: HuxColors.glassStroke)),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip('Overall', null),
        for (final p in ScorePart.values) chip(p.label, p),
      ]),
    );
  }
}

class _Overall extends StatelessWidget {
  final WeekScore score;
  final ValueChanged<ScorePart> onOpen;

  const _Overall({required this.score, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final overall = score.overall;
    final change = score.change;
    final contrib = score.contributions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HuxTile(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          semanticLabel: overall == null ? 'Week score not ready yet' : 'Week score $overall out of 100',
          child: Column(
            children: [
              const Align(alignment: Alignment.centerLeft, child: HuxTileLabel('This week')),
              const SizedBox(height: 10),
              SizedBox(
                width: 200,
                height: 200,
                child: CustomPaint(
                  painter: _DonutPainter({
                    for (final e in contrib.entries) scorePartLook(e.key).color: e.value,
                  }),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(overall?.toString() ?? '–',
                            style: const TextStyle(
                                fontSize: 52, fontWeight: FontWeight.w800, height: 1, color: huxInk)),
                        const Text('out of 100', style: TextStyle(fontSize: 13, color: huxMuted)),
                        if (change != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (change >= 0 ? HuxColors.ringFood : HuxColors.ringHeart).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('${change >= 0 ? '+' : '−'}${change.abs()} vs last week',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color.lerp(change >= 0 ? HuxColors.ringFood : HuxColors.ringHeart, huxInk, 0.3))),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                overall == null
                    ? 'Your score starts after 3 days of sleep, steps or meals.'
                    : 'Each colour is the points that part added. Tap a part to see its 7 days.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 1.35, color: huxMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final p in ScorePart.values) ...[
          _PartRow(part: score.parts[p]!, points: contrib[p], onTap: () => onOpen(p)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PartRow extends StatelessWidget {
  final PartScore part;
  final double? points;
  final VoidCallback onTap;

  const _PartRow({required this.part, required this.points, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final look = scorePartLook(part.part);
    return HuxTile(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      semanticLabel: '${part.part.label}: ${part.score == null ? 'no data yet' : '${part.score} out of 100'}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Hux3DObject(look.object, color: look.color, size: 40, animate: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(part.part.label,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: huxInk)),
                  const SizedBox(height: 2),
                  Text(part.facts.first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: huxMuted)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (part.score ?? 0) / 100,
                      minHeight: 6,
                      color: look.color,
                      backgroundColor: huxTrack,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(part.score?.toString() ?? '–',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: huxInk)),
                Text(points == null ? 'no data' : '+${points!.round()} pts',
                    style: const TextStyle(fontSize: 12, color: huxMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PartView extends StatelessWidget {
  final PartScore part;

  const _PartView({required this.part});

  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final look = scorePartLook(part.part);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HuxTile(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Hux3DObject(look.object, color: look.color, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${part.part.label} this week',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: huxMuted)),
                        Text(part.score == null ? 'Not enough data' : '${part.score} / 100',
                            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: huxInk)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 150,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final d in part.days)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(d.caption ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: huxMuted)),
                              const SizedBox(height: 4),
                              Container(
                                height: d.value == null ? 6 : math.max(6.0, 100 * d.value!),
                                decoration: BoxDecoration(
                                  color: d.value == null ? huxTrack : look.color.withValues(alpha: 0.35 + 0.65 * d.value!),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(_days[d.day.weekday - 1],
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: huxInk)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        HuxTile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const HuxTileLabel('What built it'),
              const SizedBox(height: 8),
              for (final f in part.facts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 7),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: look.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(f, style: const TextStyle(fontSize: 15, height: 1.35, color: huxInk))),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Text('How it works: ${part.part.how}.', style: const TextStyle(fontSize: 13, color: huxMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Coloured arcs (points per part) on a grey track out of 100.
class _DonutPainter extends CustomPainter {
  final Map<Color, double> segments;

  _DonutPainter(this.segments);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = huxTrack;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, track);
    var start = -math.pi / 2;
    const gap = 0.04;
    for (final e in segments.entries) {
      final sweep = (e.value / 100) * math.pi * 2;
      if (sweep <= gap) continue;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = e.key;
      canvas.drawArc(arcRect, start + gap / 2, sweep - gap, false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.segments != segments;
}
