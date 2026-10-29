/// Plans tab (OxeAI's "Plans" view): activity, nutrition, habits, life
/// modes and reminders as cards with a coloured accent bar.
library;

import 'package:flutter/material.dart';

import '../../core/profile/feature_catalog.dart';
import '../../theme/hux_glass.dart';
import '../../theme/hux_tokens.dart';

class PlansHub extends StatelessWidget {
  final void Function(FeatureId id) onOpenFeature;
  final VoidCallback onOpenModes;
  final VoidCallback? onSeeAll;

  const PlansHub({super.key, required this.onOpenFeature, required this.onOpenModes, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxGlass.navClearance),
      children: [
        Text('Plans', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        Text('Built around your goals. Change them anytime.', style: text.bodySmall),
        const SizedBox(height: HuxSpacing.lg),
        _PlanCard(
          color: HuxColors.ringSteps,
          icon: Icons.directions_run_rounded,
          title: 'Activity plan',
          body: 'Guided walking and running plans with voice cues — First Steps, Brisk 100, '
              'Japanese interval walking, Zero to 5K, Steady & Strong 60+.',
          actions: [
            _PlanAction('Open plans', () => onOpenFeature(FeatureId.beginnerWalkPlan)),
            _PlanAction('Zero to 5K', () => onOpenFeature(FeatureId.zeroTo5k)),
          ],
        ),
        _PlanCard(
          color: HuxColors.ringFood,
          icon: Icons.restaurant_rounded,
          title: 'Nutrition plan',
          body: 'Log meals in katoris or with a photo. See your protein gap and what to add today.',
          actions: [_PlanAction('Log a meal', () => onOpenFeature(FeatureId.proteinGap))],
        ),
        _PlanCard(
          color: HuxColors.ringHabit,
          icon: Icons.thumb_up_alt_rounded,
          title: 'Habits',
          body: 'One-tap daily journal — chai, late dinner, sweets — and a forgiving streak.',
          actions: [
            _PlanAction('Journal', () => onOpenFeature(FeatureId.indianJournal)),
            _PlanAction('Streaks', () => onOpenFeature(FeatureId.streaksMonthly)),
          ],
        ),
        _PlanCard(
          color: HuxColors.accentPurple,
          icon: Icons.flag_rounded,
          title: 'Life modes',
          body: 'Shaadi or a big day, exam season, night shift and fasting — plans that fit your life.',
          actions: [_PlanAction('Choose a mode', onOpenModes)],
        ),
        _PlanCard(
          color: HuxColors.ringCharge,
          icon: Icons.notifications_active_rounded,
          title: 'Reminders',
          body: 'Gentle nudges that keep you moving.',
          actions: [
            _PlanAction('Walk after meals', () => onOpenFeature(FeatureId.walkAfterMeal)),
            _PlanAction('Sit-too-long', () => onOpenFeature(FeatureId.sitTooLong)),
            _PlanAction('Air & heat', () => onOpenFeature(FeatureId.airAndHeatAlerts)),
          ],
        ),
        if (onSeeAll != null)
          Center(
            child: TextButton.icon(
              onPressed: onSeeAll,
              icon: const Icon(Icons.apps_rounded),
              label: const Text('See all features'),
            ),
          ),
      ],
    );
  }
}

class _PlanAction {
  final String label;
  final VoidCallback onTap;
  const _PlanAction(this.label, this.onTap);
}

class _PlanCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String body;
  final List<_PlanAction> actions;

  const _PlanCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: HuxSpacing.md),
      child: GlassPanel(
        padding: EdgeInsets.zero,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                margin: const EdgeInsets.symmetric(vertical: HuxSpacing.lg),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(HuxSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, color: color, size: 20),
                          const SizedBox(width: HuxSpacing.sm),
                          Text(title.toUpperCase(),
                              style: text.labelLarge?.copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: HuxSpacing.sm),
                      Text(body, style: text.bodyMedium?.copyWith(color: HuxColors.mutedText, height: 1.35)),
                      const SizedBox(height: HuxSpacing.sm),
                      Wrap(
                        spacing: HuxSpacing.sm,
                        runSpacing: HuxSpacing.xs,
                        children: [
                          for (final a in actions)
                            ActionChip(
                              label: Text(a.label),
                              onPressed: a.onTap,
                              side: BorderSide(color: color.withValues(alpha: 0.35)),
                              backgroundColor: color.withValues(alpha: 0.08),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
