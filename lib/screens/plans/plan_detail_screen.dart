/// One plan: why it works, safety, next session, all weeks.
library;

import 'package:flutter/material.dart';

import '../../core/plans/plan_models.dart';
import '../../core/plans/plan_progress.dart';
import '../../core/plans/speaker.dart';
import '../../core/plans/voice_cues.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import '../../theme/hux_ui.dart';
import 'plan_visuals.dart';
import 'session_player_screen.dart';

class PlanDetailScreen extends StatefulWidget {
  final Plan plan;
  final PlanProgressService progress;
  final CueLanguage language;
  final Speaker Function() speakerFactory;

  const PlanDetailScreen({
    super.key,
    required this.plan,
    required this.progress,
    required this.language,
    required this.speakerFactory,
  });

  @override
  State<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends State<PlanDetailScreen> {
  PlanProgress? _p;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await widget.progress.progress(widget.plan.id);
    if (mounted) setState(() => _p = p);
  }

  /// Simple readiness questions (not a medical clearance). Any "yes"
  /// means: talk to a doctor first.
  Future<bool> _readiness() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Before you start'),
        content: const SingleChildScrollView(
          child: Text(
            'This plan gets you breathing hard. Please check with a doctor first if any of these apply:\n\n'
            '• A doctor has said you have a heart condition or high blood pressure\n'
            '• You get chest pain, or feel faint or dizzy, when active\n'
            '• You have a bone or joint problem that activity could make worse\n'
            '• You are pregnant, or recovering from illness or surgery\n\n'
            'Stop straight away if you feel chest pain, severe breathlessness or dizziness.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('One applies to me')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('None apply — start')),
        ],
      ),
    );
    if (ok == true) await widget.progress.confirmReadiness(widget.plan.id);
    return ok == true;
  }

  Future<void> _start(int index) async {
    final p = _p;
    if (p == null) return;
    if (widget.plan.needsReadinessCheck && !p.readinessConfirmed) {
      if (!await _readiness()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Good call. Ask your doctor — or try First Steps, a gentler plan.'),
        ));
        return;
      }
    }
    if (!mounted) return;
    final finished = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => SessionPlayerScreen(
        plan: widget.plan,
        session: widget.plan.sessions[index],
        language: widget.language,
        speaker: widget.speakerFactory(),
      ),
    ));
    if (finished == true) await widget.progress.markDone(widget.plan.id, index);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final plan = widget.plan;
    final p = _p;
    final next = p?.nextIndex;
    final color = planColor(plan.id);
    return Scaffold(
      appBar: AppBar(title: Text(plan.name)),
      bottomNavigationBar: p == null || next == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.lg),
              child: SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => _start(next),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text('Start week ${plan.sessions[next].week}, '
                      'session ${plan.sessions[next].day} (${plan.sessions[next].minutes} min)'),
                ),
              ),
            ),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
              children: [
                HuxHeroCard(
                  icon: planIcon(plan.id),
                  color: color,
                  eyebrow: '${plan.level.label} · ${plan.weeks} weeks',
                  title: plan.tagline,
                  child: Row(
                    children: [
                      HuxScoreRing(
                        progress: p.fraction,
                        centerText: '${(p.fraction * 100).round()}%',
                        color: color,
                        size: 64,
                      ),
                      const SizedBox(width: HuxSpacing.lg),
                      Expanded(
                        child: Text(
                          next == null
                              ? 'Plan complete — brilliant work!'
                              : '${p.completed.length} of ${plan.sessions.length} sessions done',
                          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: HuxSpacing.md),
                HuxCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const HuxIconBadge(icon: Icons.science_outlined, color: HuxColors.ringSleep, size: 36),
                      const SizedBox(width: HuxSpacing.md),
                      Expanded(child: Text(plan.evidence, style: text.bodyMedium)),
                    ],
                  ),
                ),
                if (plan.safetyNote != null) ...[
                  const SizedBox(height: HuxSpacing.sm),
                  HuxCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const HuxIconBadge(icon: Icons.health_and_safety_outlined, color: HuxColors.stretched, size: 36),
                        const SizedBox(width: HuxSpacing.md),
                        Expanded(child: Text(plan.safetyNote!, style: text.bodySmall)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: HuxSpacing.xl),
                const HuxSectionTitle('Week by week', icon: Icons.calendar_month_rounded),
                HuxCard(
                  padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
                  child: Column(
                    children: [
                      for (var w = 1; w <= plan.weeks; w++) ...[
                        if (w > 1) const Divider(height: 1, color: HuxColors.hairline),
                        _WeekRow(
                          week: w,
                          detail: _describe(plan.sessions.firstWhere((s) => s.week == w)),
                          done: [
                            for (var i = 0; i < plan.sessions.length; i++)
                              if (plan.sessions[i].week == w) p.completed.contains(i),
                          ],
                          color: color,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  static String _describe(Session s) {
    String name(SegmentKind k) => switch (k) {
          SegmentKind.warmup => 'warm-up',
          SegmentKind.walk => 'walk',
          SegmentKind.brisk => 'brisk walk',
          SegmentKind.fast => 'fast',
          SegmentKind.slow => 'easy',
          SegmentKind.run => 'run',
          SegmentKind.snack => 'all-out burst',
          SegmentKind.exercise => 'exercise',
          SegmentKind.cooldown => 'cool-down',
        };
    String dur(int sec) => sec % 60 == 0 ? '${sec ~/ 60} min' : (sec < 60 ? '$sec s' : '${(sec / 60).toStringAsFixed(1)} min');
    // Collapse repeats: "run 1 min / walk 1.5 min ×8".
    final parts = <String>[];
    var i = 0;
    final segs = s.segments;
    while (i < segs.length) {
      if (i + 1 < segs.length &&
          (segs[i].kind == SegmentKind.run || segs[i].kind == SegmentKind.fast)) {
        final a = segs[i];
        final b = segs[i + 1];
        var reps = 0;
        var j = i;
        while (j < segs.length && segs[j].kind == a.kind && segs[j].seconds == a.seconds) {
          reps++;
          j++;
          final recovery = b.kind == SegmentKind.walk || b.kind == SegmentKind.slow;
          if (recovery && j < segs.length && segs[j].kind == b.kind && segs[j].seconds == b.seconds) j++;
        }
        if (reps > 1) {
          parts.add('${name(a.kind)} ${dur(a.seconds)} / ${name(b.kind)} ${dur(b.seconds)} ×$reps');
          i = j;
        } else {
          parts.add('${name(a.kind)} ${dur(a.seconds)}');
          i++;
        }
      } else {
        parts.add('${name(segs[i].kind)} ${dur(segs[i].seconds)}');
        i++;
      }
    }
    return '${parts.join(' · ')} — about ${s.minutes} min';
  }
}

class _WeekRow extends StatelessWidget {
  final int week;
  final String detail;
  final List<bool> done;
  final Color color;

  const _WeekRow({required this.week, required this.detail, required this.done, required this.color});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final all = done.isNotEmpty && done.every((d) => d);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HuxSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: all ? color : color.withValues(alpha: 0.12),
            ),
            child: all
                ? const Icon(Icons.check_rounded, size: 18, color: HuxColors.onVivid)
                : Text('$week', style: text.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: HuxSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Week $week', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
                    for (final d in done)
                      Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: Icon(d ? Icons.circle : Icons.circle_outlined, size: 9, color: color),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(detail, style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
