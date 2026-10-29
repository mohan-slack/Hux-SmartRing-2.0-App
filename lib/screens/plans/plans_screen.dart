/// Guided plans: recommended for you first, then all six.
library;

import 'package:flutter/material.dart';

import '../../core/plans/plan_library.dart';
import '../../core/plans/plan_models.dart';
import '../../core/plans/plan_progress.dart';
import '../../core/plans/speaker.dart';
import '../../core/plans/voice_cues.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import '../../theme/hux_ui.dart';
import 'plan_detail_screen.dart';
import 'plan_visuals.dart';

class PlansScreen extends StatefulWidget {
  final PlanProgressService progress;
  final List<String> recommended;
  final CueLanguage language;
  final Speaker Function() speakerFactory;

  const PlansScreen({
    super.key,
    required this.progress,
    required this.recommended,
    required this.language,
    required this.speakerFactory,
  });

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  Map<String, PlanProgress> _progress = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await widget.progress.allProgress();
    if (mounted) setState(() => _progress = p);
  }

  Future<void> _open(Plan plan) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlanDetailScreen(
        plan: plan,
        progress: widget.progress,
        language: widget.language,
        speakerFactory: widget.speakerFactory,
      ),
    ));
    await _load();
  }

  Widget _card(Plan plan) {
    final text = Theme.of(context).textTheme;
    final p = _progress[plan.id];
    final done = p?.completed.length ?? 0;
    final color = planColor(plan.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: HuxSpacing.md),
      child: HuxCard(
        onTap: () => _open(plan),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HuxIconBadge(icon: planIcon(plan.id), color: color, size: 48),
                const SizedBox(width: HuxSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plan.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(plan.tagline, style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: HuxColors.mutedText),
              ],
            ),
            const SizedBox(height: HuxSpacing.md),
            Wrap(
              spacing: HuxSpacing.sm,
              runSpacing: HuxSpacing.sm,
              children: [
                HuxPill(label: plan.level.label, color: color),
                HuxPill(label: '${plan.weeks} weeks', color: HuxColors.mutedText, icon: Icons.calendar_today_rounded),
                HuxPill(
                  label: plan.id == 'stair_snacks' ? '3 snacks a day' : '${plan.sessionsPerWeek} sessions a week',
                  color: HuxColors.mutedText,
                  icon: Icons.repeat_rounded,
                ),
              ],
            ),
            if (done > 0) ...[
              const SizedBox(height: HuxSpacing.md),
              Row(
                children: [
                  Expanded(child: HuxProgressBar(value: done / plan.sessions.length, color: color, height: 6)),
                  const SizedBox(width: HuxSpacing.sm),
                  Text('$done of ${plan.sessions.length} done', style: text.labelSmall),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.recommended.map(planById).whereType<Plan>().toList();
    final others = planLibrary.where((p) => !widget.recommended.contains(p.id)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Guided plans')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
        children: [
          if (rec.isNotEmpty) ...[
            const HuxSectionTitle('Recommended for you', icon: Icons.auto_awesome),
            for (final p in rec) _card(p),
            const SizedBox(height: HuxSpacing.md),
          ],
          const HuxSectionTitle('All plans', icon: Icons.grid_view_rounded),
          for (final p in others) _card(p),
        ],
      ),
    );
  }
}
