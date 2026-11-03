/// The three Home plan cards (step target, today's effort, bedtime) as
/// sheets: one big picture of the number, the why in one line, and the
/// one thing to do. Opened from "For you" and from All features.
library;

import 'package:flutter/material.dart';

import '../../core/meaning/day_plan.dart';
import '../../core/meaning/evening_timing.dart';
import '../../core/meaning/step_target.dart';
import '../../core/profile/feature_catalog.dart';
import '../../theme/hux_tokens.dart';
import '../../widgets/hux/hux_3d.dart';
import '../../widgets/hux/hux_kit.dart';

/// Shows the sheet for [id] from [plan]. Returns false when [id] isn't
/// one of the plan features.
Future<bool> showPlanSheet(
  BuildContext context, {
  required FeatureId id,
  required DayPlan? plan,
  VoidCallback? onOpenWalks,
  bool? eveningReminders,
  Future<bool> Function(bool on)? onEveningReminders,
}) async {
  final Widget body;
  switch (id) {
    case FeatureId.nextStepTargets:
      body = _StepsBody(steps: plan?.steps, onOpenWalks: onOpenWalks);
    case FeatureId.effortTarget:
      body = _EffortBody(effort: plan?.effort);
    case FeatureId.targetBedtime:
      body = _BedBody(bed: plan?.bedtime, reminders: eveningReminders, onReminders: onEveningReminders);
    default:
      return false;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: HuxColors.bg,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: body),
    ),
  );
  return true;
}

class _Header extends StatelessWidget {
  final Hux3D object;
  final Color color;
  final String title;
  final String? sub;

  const _Header({required this.object, required this.color, required this.title, this.sub});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Hux3DObject(object, color: color, size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: huxInk)),
                if (sub != null) Text(sub!, style: const TextStyle(fontSize: 15, color: huxMuted)),
              ],
            ),
          ),
        ],
      );
}

class _Why extends StatelessWidget {
  final String text;

  const _Why(this.text);

  @override
  Widget build(BuildContext context) => HuxTile(
        child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4, color: huxInk)),
      );
}

const _empty = 'HUX needs a few nights and days of data first. It fills in by itself.';

class _StepsBody extends StatelessWidget {
  final StepTarget? steps;
  final VoidCallback? onOpenWalks;

  const _StepsBody({required this.steps, this.onOpenWalks});

  @override
  Widget build(BuildContext context) {
    final s = steps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          object: Hux3D.steps,
          color: HuxColors.ringSteps,
          title: 'Today\'s step target',
          sub: s == null ? null : 'A little above your usual, never a jump',
        ),
        const SizedBox(height: 18),
        if (s == null)
          const _Why(_empty)
        else ...[
          HuxTile(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    HuxTileValue(StepTargetCalculator.formatSteps(s.today), size: 40),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('of ${StepTargetCalculator.formatSteps(s.target)}',
                          style: const TextStyle(fontSize: 17, color: huxMuted)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                HuxSegmentBar(value: s.today.toDouble(), max: s.target.toDouble(), segments: 10, color: HuxColors.ringSteps),
                const SizedBox(height: 10),
                Text(
                  s.done
                      ? 'Done for today.'
                      : '${StepTargetCalculator.formatSteps(s.remaining)} to go — about ${s.minutesToGo} min of walking.',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: huxInk),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _Why(s.reason),
          if (!s.done && onOpenWalks != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                onOpenWalks!();
              },
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
              child: Text('Start a ${s.minutesToGo.clamp(5, 30)}-min walk',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ],
        ],
      ],
    );
  }
}

class _EffortBody extends StatelessWidget {
  final EffortTarget? effort;

  const _EffortBody({required this.effort});

  @override
  Widget build(BuildContext context) {
    final e = effort;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(object: Hux3D.ring, color: HuxColors.accentPink, title: 'Today\'s effort', sub: e?.label),
        const SizedBox(height: 18),
        if (e == null)
          const _Why(_empty)
        else ...[
          HuxTile(
            semanticLabel: 'Effort ${e.range} out of 10',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HuxTileValue(e.range, unit: 'of 10', size: 40),
                  const SizedBox(height: 14),
                  // 0–10 scale; today's range lit up.
                  Row(
                    children: [
                      for (var i = 1; i <= 10; i++)
                        Expanded(
                          child: Container(
                            height: 26,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: i >= e.min && i <= e.max
                                  ? Color.lerp(const Color(0xFF5B6CF0), HuxColors.accentPink, i / 10)
                                  : huxTrack,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('easy', style: TextStyle(fontSize: 13, color: huxMuted)),
                      Text('all out', style: TextStyle(fontSize: 13, color: huxMuted)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _Why(e.suggestion),
          const SizedBox(height: 10),
          const _Why('Effort 3 = you can sing. 5 = you can talk in full sentences. 7 = only a few words.'),
        ],
      ],
    );
  }
}

class _BedBody extends StatefulWidget {
  final TargetBedtime? bed;

  /// Current state of the evening reminders (null = not offered).
  final bool? reminders;
  final Future<bool> Function(bool on)? onReminders;

  const _BedBody({required this.bed, this.reminders, this.onReminders});

  @override
  State<_BedBody> createState() => _BedBodyState();
}

class _BedBodyState extends State<_BedBody> {
  late bool? _on = widget.reminders;

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bed;
    final at = b?.bedtime.toLocal();
    final t = at == null ? null : EveningTiming.forBed(at);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header(object: Hux3D.bed, color: HuxColors.ringSleep, title: 'Bed tonight'),
        const SizedBox(height: 18),
        if (b == null || at == null)
          const _Why(_empty)
        else ...[
          HuxTile(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HuxTileValue(_clock(at), size: 40),
                const SizedBox(height: 6),
                Text('for ${b.sleepGoal.inHours}h ${(b.sleepGoal.inMinutes % 60).toString().padLeft(2, '0')}m of sleep',
                    style: const TextStyle(fontSize: 16, color: huxMuted)),
                const SizedBox(height: 14),
                for (final (time, what) in [
                  (t!.lastCaffeine, 'Last chai or coffee'),
                  (t.lastMeal, 'Dinner done'),
                  (t.screensOff, 'Phone away, lights low'),
                  (at, 'In bed'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 92,
                          child: Text(_clock(time),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: huxInk)),
                        ),
                        Expanded(child: Text(what, style: const TextStyle(fontSize: 16, color: huxInk))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _Why(b.reason),
          const SizedBox(height: 6),
          const _Why('Caffeine stays in the body for hours — a 4 PM chai is still half-active at 9 PM.'),
          if (_on != null && widget.onReminders != null) ...[
            const SizedBox(height: 10),
            HuxTile(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _on!,
                title: const Text('Remind me', style: TextStyle(fontWeight: FontWeight.w700, color: huxInk)),
                subtitle: const Text('30 min before the last chai and before dinner, moving with your bedtime.'),
                onChanged: (v) async {
                  final ok = await widget.onReminders!(v);
                  if (mounted) setState(() => _on = v && ok);
                },
              ),
            ),
          ],
        ],
      ],
    );
  }
}
