/// Walk after meals: one switch, your usual meal times, done.
library;

import 'package:flutter/material.dart';

import '../core/nudges/nudge_planner.dart';
import '../core/nudges/nudge_service.dart';
import '../theme/hux_page.dart';
import '../theme/hux_tokens.dart';
import '../theme/hux_ui.dart';

class WalkNudgeScreen extends StatefulWidget {
  final NudgeService nudges;

  const WalkNudgeScreen({super.key, required this.nudges});

  @override
  State<WalkNudgeScreen> createState() => _WalkNudgeScreenState();
}

class _WalkNudgeScreenState extends State<WalkNudgeScreen> {
  WalkNudgeSettings? _s;
  bool _saving = false;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    widget.nudges.walkSettings().catchError((Object _) => WalkNudgeSettings.defaults).then((s) {
      if (mounted) setState(() => _s = s);
    });
  }

  Future<void> _save(WalkNudgeSettings next) async {
    setState(() {
      _s = next;
      _saving = true;
    });
    try {
      final ok = await widget.nudges.saveWalkSettings(next);
      final saved = await widget.nudges.walkSettings();
      if (!mounted) return;
      setState(() {
        _s = saved;
        _permissionDenied = !ok && next.enabled;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't update reminders — try again.")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(TimeOfDayHm current, void Function(TimeOfDayHm) apply) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked != null) apply(TimeOfDayHm(picked.hour, picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = _s;
    const color = HuxColors.ringFood;
    return Scaffold(
      appBar: AppBar(title: const Text('Walk after meals')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
              children: [
                HuxHeroCard(
                  icon: Icons.directions_walk_rounded,
                  color: color,
                  eyebrow: s.enabled ? 'On' : 'Off',
                  title: 'A 10-minute walk after meals',
                  subtitle: 'A light walk soon after eating is one of the simplest '
                      'healthy habits — research shows it helps your body handle the '
                      'meal better than sitting. HUX can give you a gentle nudge.',
                ),
                const SizedBox(height: HuxSpacing.md),
                HuxCard(
                  padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
                  child: HuxListRow(
                    icon: Icons.notifications_active_outlined,
                    color: color,
                    title: 'Remind me to walk after meals',
                    trailing: Switch(
                      value: s.enabled,
                      onChanged: _saving ? null : (v) => _save(s.copyWith(enabled: v)),
                    ),
                  ),
                ),
                if (_permissionDenied) ...[
                  const SizedBox(height: HuxSpacing.sm),
                  Text(
                    'Notifications are off for HUX. Turn them on in your phone\'s '
                    'Settings > Apps > HUX > Notifications, then try again.',
                    style: text.bodySmall?.copyWith(color: HuxColors.stretched),
                  ),
                ],
                const SizedBox(height: HuxSpacing.xl),
                const HuxSectionTitle('Your meal times', icon: Icons.schedule_rounded, iconColor: color),
                Opacity(
                  opacity: s.enabled ? 1 : 0.5,
                  child: HuxCard(
                    padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
                    child: Column(
                      children: [
                        HuxListRow(
                          icon: Icons.lunch_dining_outlined,
                          color: HuxColors.ringSteps,
                          title: 'Usual lunch time',
                          subtitle: 'Nudge at ${s.lunch.plusMinutes(NudgePlanner.walkDelay).label}',
                          trailing: HuxPill(label: s.lunch.label, color: HuxColors.ringSteps),
                          onTap: s.enabled && !_saving
                              ? () => _pickTime(s.lunch, (t) => _save(s.copyWith(lunch: t)))
                              : null,
                        ),
                        const Divider(height: 1, color: HuxColors.hairline),
                        HuxListRow(
                          icon: Icons.dinner_dining_outlined,
                          color: HuxColors.ringSleep,
                          title: 'Usual dinner time',
                          subtitle: NudgePlanner.inQuietHours(s.dinner.plusMinutes(NudgePlanner.walkDelay), s)
                              ? 'Too late — falls in quiet hours, no nudge'
                              : 'Nudge at ${s.dinner.plusMinutes(NudgePlanner.walkDelay).label}',
                          trailing: HuxPill(label: s.dinner.label, color: HuxColors.ringSleep),
                          onTap: s.enabled && !_saving
                              ? () => _pickTime(s.dinner, (t) => _save(s.copyWith(dinner: t)))
                              : null,
                        ),
                        const Divider(height: 1, color: HuxColors.hairline),
                        HuxListRow(
                          icon: Icons.restaurant_rounded,
                          color: color,
                          title: 'Also nudge 10 min after I log a meal',
                          subtitle: 'Skipped if a meal-time nudge is already close',
                          trailing: Switch(
                            value: s.afterLoggedMeal,
                            onChanged:
                                !s.enabled || _saving ? null : (v) => _save(s.copyWith(afterLoggedMeal: v)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: HuxSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.bedtime_outlined, size: 16, color: HuxColors.mutedText),
                    const SizedBox(width: HuxSpacing.sm),
                    Expanded(
                      child: Text(
                        'Quiet hours: no nudges between ${s.quietStart.label} and ${s.quietEnd.label}. '
                        'Times may vary by a few minutes so your battery is spared.',
                        style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
