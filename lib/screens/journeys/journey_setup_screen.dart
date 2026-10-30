/// Start a journey in one screen: wake time, (usual bedtime), food,
/// level, and which reminders — then Start. Defaults are quiet: only
/// wake + wind-down reminders.
library;

import 'package:flutter/material.dart';

import '../../core/journeys/journey_models.dart';
import '../../core/journeys/journey_service.dart';
import '../../core/nudges/nudge_planner.dart';
import '../../core/nudges/nudge_service.dart';
import '../../core/profile/user_profile.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import '../../theme/hux_ui.dart';
import 'journey_visuals.dart';

class JourneySetupScreen extends StatefulWidget {
  final JourneyDef def;
  final JourneyService journeys;
  final NudgeService? nudges;
  final Diet? diet;

  const JourneySetupScreen({super.key, required this.def, required this.journeys, this.nudges, this.diet});

  @override
  State<JourneySetupScreen> createState() => _JourneySetupScreenState();
}

class _JourneySetupScreenState extends State<JourneySetupScreen> {
  TimeOfDayHm _wake = const TimeOfDayHm(6, 30);
  TimeOfDayHm _usualBed = const TimeOfDayHm(23, 30);
  late Diet _diet = widget.diet ?? Diet.veg;
  Budget _budget = Budget.low;
  FitnessLevel _level = FitnessLevel.beginner;
  bool _rWake = true;
  bool _rMove = false;
  bool _rWind = true;
  TimeOfDayHm _moveAt = const TimeOfDayHm(18, 30);
  bool _starting = false;

  bool get _isSleep => widget.def.id == JourneyId.sleepReset21;

  Future<TimeOfDayHm?> _pick(TimeOfDayHm t) async {
    final p = await showTimePicker(context: context, initialTime: TimeOfDay(hour: t.hour, minute: t.minute));
    return p == null ? null : TimeOfDayHm(p.hour, p.minute);
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    final setup = JourneySetup(
      id: widget.def.id,
      wake: _wake,
      usualBedtime: _isSleep ? _usualBed : null,
      diet: _diet,
      budget: _budget,
      level: _level,
      remindWake: _rWake,
      remindMove: _rMove && !_isSleep,
      remindWindDown: _rWind,
      moveAt: _moveAt,
    );
    try {
      final s = await widget.journeys.start(setup);
      final ok = await widget.nudges?.setJourneyReminders(widget.journeys.reminders(s)) ?? true;
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Journey started. Reminders are off — notifications aren\'t allowed for HUX.')));
      }
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't start — try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = journeyColor(widget.def.id);
    Widget timeRow(IconData icon, String title, String? sub, TimeOfDayHm t, ValueChanged<TimeOfDayHm> set) =>
        HuxListRow(
          icon: icon,
          color: color,
          title: title,
          subtitle: sub,
          trailing: HuxPill(label: t.label, color: color),
          onTap: () async {
            final p = await _pick(t);
            if (p != null) setState(() => set(p));
          },
        );
    Widget chips<T>(List<T> values, T selected, String Function(T) label, ValueChanged<T> onSel) => Wrap(
          spacing: HuxSpacing.sm,
          runSpacing: HuxSpacing.sm,
          children: [
            for (final v in values)
              ChoiceChip(label: Text(label(v)), selected: v == selected, onSelected: (_) => setState(() => onSel(v))),
          ],
        );

    return Scaffold(
      appBar: AppBar(title: Text(widget.def.title)),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.lg),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _starting ? null : _start,
            child: Text(_starting ? 'Starting…' : 'Start day 1'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xl),
        children: [
          HuxHeroCard(
            icon: journeyIcon(widget.def.id),
            color: color,
            eyebrow: '${widget.def.days} days',
            title: widget.def.subtitle,
          ),
          const SizedBox(height: HuxSpacing.xl),
          const HuxSectionTitle('Your day', icon: Icons.wb_sunny_rounded),
          HuxCard(
            padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
            child: Column(
              children: [
                timeRow(Icons.alarm_rounded, 'Wake-up time', 'Keep it the same every day', _wake, (v) => _wake = v),
                if (_isSleep) ...[
                  const Divider(height: 1, color: HuxColors.hairline),
                  timeRow(Icons.bedtime_outlined, 'When you usually fall asleep', 'We move it 15 min every 3 days',
                      _usualBed, (v) => _usualBed = v),
                ],
              ],
            ),
          ),
          const SizedBox(height: HuxSpacing.xl),
          const HuxSectionTitle('Food', icon: Icons.restaurant_rounded),
          Text('You eat', style: text.labelLarge),
          const SizedBox(height: HuxSpacing.xs),
          chips(Diet.values, _diet, (d) => d.label, (v) => _diet = v),
          const SizedBox(height: HuxSpacing.md),
          Text('Budget per meal', style: text.labelLarge),
          const SizedBox(height: HuxSpacing.xs),
          chips(Budget.values, _budget, (b) => '${b.symbol}  ${b.range}', (v) => _budget = v),
          if (!_isSleep) ...[
            const SizedBox(height: HuxSpacing.xl),
            const HuxSectionTitle('Fitness', icon: Icons.fitness_center_rounded),
            chips(FitnessLevel.values, _level, (l) => l.label, (v) => _level = v),
          ],
          const SizedBox(height: HuxSpacing.xl),
          const HuxSectionTitle('Reminders (max 3)', icon: Icons.notifications_none_rounded),
          HuxCard(
            padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
            child: Column(
              children: [
                HuxListRow(
                  icon: Icons.alarm_rounded,
                  color: color,
                  title: 'Wake-up',
                  trailing: Switch(value: _rWake, onChanged: (v) => setState(() => _rWake = v)),
                ),
                if (!_isSleep) ...[
                  const Divider(height: 1, color: HuxColors.hairline),
                  HuxListRow(
                    icon: Icons.fitness_center_rounded,
                    color: color,
                    title: 'Workout',
                    subtitle: _rMove ? 'At ${_moveAt.label} — tap to change' : null,
                    onTap: _rMove
                        ? () async {
                            final p = await _pick(_moveAt);
                            if (p != null) setState(() => _moveAt = p);
                          }
                        : null,
                    trailing: Switch(value: _rMove, onChanged: (v) => setState(() => _rMove = v)),
                  ),
                ],
                const Divider(height: 1, color: HuxColors.hairline),
                HuxListRow(
                  icon: Icons.nights_stay_outlined,
                  color: color,
                  title: 'Wind-down',
                  subtitle: '30 minutes before bed',
                  trailing: Switch(value: _rWind, onChanged: (v) => setState(() => _rWind = v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: HuxSpacing.sm),
          Text('Change or pause these any time from the journey.',
              style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
        ],
      ),
    );
  }
}
