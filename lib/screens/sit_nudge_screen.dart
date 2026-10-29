/// Sit-too-long nudges: work hours, how often, which days.
library;

import 'package:flutter/material.dart';

import '../core/nudges/nudge_planner.dart';
import '../core/nudges/nudge_service.dart';
import '../core/nudges/sit_planner.dart';
import '../theme/hux_page.dart';
import '../theme/hux_tokens.dart';
import '../theme/hux_ui.dart';

class SitNudgeScreen extends StatefulWidget {
  final NudgeService nudges;

  const SitNudgeScreen({super.key, required this.nudges});

  @override
  State<SitNudgeScreen> createState() => _SitNudgeScreenState();
}

class _SitNudgeScreenState extends State<SitNudgeScreen> {
  SitNudgeSettings? _s;
  WalkNudgeSettings? _walk;
  bool _saving = false;
  bool _permissionDenied = false;

  static const _dayLetters = {1: 'M', 2: 'T', 3: 'W', 4: 'T', 5: 'F', 6: 'S', 7: 'S'};

  @override
  void initState() {
    super.initState();
    () async {
      final s = await widget.nudges.sitSettings();
      final w = await widget.nudges.walkSettings();
      if (mounted) {
        setState(() {
          _s = s;
          _walk = w;
        });
      }
    }();
  }

  Future<void> _save(SitNudgeSettings next) async {
    setState(() {
      _s = next;
      _saving = true;
    });
    try {
      final ok = await widget.nudges.saveSitSettings(next);
      final saved = await widget.nudges.sitSettings();
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
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sit-too-long nudge')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    const planner = SitPlanner();
    final perDay = planner.slots(s, walk: _walk).length;
    final capped = planner.exceedsLimit(s, walk: _walk);
    final editable = s.enabled && !_saving;

    const color = HuxColors.ringSteps;
    return Scaffold(
      appBar: AppBar(title: const Text('Sit-too-long nudge')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
        children: [
          HuxHeroCard(
            icon: Icons.chair_alt_rounded,
            color: color,
            eyebrow: s.enabled ? '$perDay reminder${perDay == 1 ? '' : 's'} a day' : 'Off',
            title: 'Get up and move',
            subtitle: 'Long hours at a desk? Getting up for a few minutes regularly helps your body '
                'handle meals and keeps your energy up. In one study, a 5-minute walk every '
                '30 minutes worked best — even small breaks help.',
          ),
          const SizedBox(height: HuxSpacing.md),
          HuxCard(
            padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
            child: HuxListRow(
              icon: Icons.notifications_active_outlined,
              color: color,
              title: 'Remind me to get up',
              trailing: Switch(
                value: s.enabled,
                onChanged: _saving ? null : (v) => _save(s.copyWith(enabled: v)),
              ),
            ),
          ),
          if (_permissionDenied) ...[
            const SizedBox(height: HuxSpacing.sm),
            Text(
              'Notifications are off for HUX. Turn them on in your phone\'s Settings, then try again.',
              style: text.bodySmall?.copyWith(color: HuxColors.stretched),
            ),
          ],
          const SizedBox(height: HuxSpacing.xl),
          const HuxSectionTitle('Work hours', icon: Icons.work_outline_rounded, iconColor: color),
          Opacity(
            opacity: s.enabled ? 1 : 0.5,
            child: HuxCard(
              padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
              child: Column(
                children: [
                  HuxListRow(
                    icon: Icons.wb_sunny_outlined,
                    color: HuxColors.ringHabit,
                    title: 'Work starts',
                    trailing: HuxPill(label: s.start.label, color: HuxColors.ringSteps),
                    onTap: editable ? () => _pickTime(s.start, (t) => _save(s.copyWith(start: t))) : null,
                  ),
                  const Divider(height: 1, color: HuxColors.hairline),
                  HuxListRow(
                    icon: Icons.nights_stay_outlined,
                    color: HuxColors.ringSleep,
                    title: 'Work ends',
                    trailing: HuxPill(label: s.end.label, color: HuxColors.ringSleep),
                    onTap: editable ? () => _pickTime(s.end, (t) => _save(s.copyWith(end: t))) : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: HuxSpacing.xl),
          const HuxSectionTitle('Every', icon: Icons.timer_outlined, iconColor: color),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: [
                for (final m in SitNudgeSettings.intervals)
                  ButtonSegment(value: m, label: Text(m == 90 ? '1.5 h' : (m == 60 ? '1 h' : '$m min'))),
              ],
              selected: {s.intervalMinutes},
              onSelectionChanged: editable ? (v) => _save(s.copyWith(intervalMinutes: v.first)) : null,
            ),
          ),
          const SizedBox(height: HuxSpacing.xl),
          const HuxSectionTitle('On', icon: Icons.calendar_today_rounded, iconColor: color),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final d in [1, 2, 3, 4, 5, 6, 7])
                _DayDot(
                  letter: _dayLetters[d]!,
                  selected: s.days.contains(d),
                  color: color,
                  onTap: editable
                      ? () {
                          final days = {...s.days};
                          if (!days.remove(d)) days.add(d);
                          _save(s.copyWith(days: days));
                        }
                      : null,
                ),
            ],
          ),
          const SizedBox(height: HuxSpacing.lg),
          Text(
            s.enabled
                ? '$perDay reminder${perDay == 1 ? '' : 's'} a day'
                    '${(_walk?.enabled ?? false) ? ', skipping times near your walk-after-meal nudges' : ''}.'
                    '${capped ? ' Your phone limits how many reminders an app can set, so some later days are left out — try a longer gap or fewer days.' : ''}'
                : 'Off.',
            style: text.bodySmall?.copyWith(color: capped ? HuxColors.stretched : HuxColors.mutedText),
          ),
          const SizedBox(height: HuxSpacing.md),
          Text(
            'Reminders are time-based for now. A future update can skip a reminder when '
            'your phone or ring sees you already moving.',
            style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  final String letter;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  const _DayDot({required this.letter, required this.selected, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: letter,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: HuxMotion.quick,
            width: huxMinTapTarget,
            height: huxMinTapTarget,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? color : HuxColors.card,
              border: Border.all(color: selected ? color : HuxColors.glassStroke),
            ),
            child: Text(letter,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected ? HuxColors.onVivid : HuxColors.ink,
                    )),
          ),
        ),
      );
}
