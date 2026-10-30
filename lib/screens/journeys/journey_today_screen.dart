/// Today in a journey: 3 things only — sleep, food, move. Each fits one
/// card; ticking all three finishes the day. "Not today" uses a weekly
/// rest pass; pause/stop are one tap away.
library;

import 'package:flutter/material.dart';

import '../../core/cycle/cycle_service.dart';

import '../../core/journeys/journey_content.dart';
import '../../core/journeys/journey_models.dart';
import '../../core/journeys/journey_service.dart';
import '../../core/nudges/nudge_service.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import '../../theme/hux_ui.dart';
import '../../widgets/share_card.dart';
import 'journey_visuals.dart';
import 'journey_workout_screen.dart';

class JourneyTodayScreen extends StatefulWidget {
  final JourneyService journeys;
  final NudgeService? nudges;

  /// Optional: offers a gentle workout + iron tip on period days.
  final CycleService? cycle;

  const JourneyTodayScreen({super.key, required this.journeys, this.nudges, this.cycle});

  @override
  State<JourneyTodayScreen> createState() => _JourneyTodayScreenState();
}

enum _Menu { pause, remindersOff, stop }

class _JourneyTodayScreenState extends State<JourneyTodayScreen> {
  JourneyState? _s;
  bool _loading = true;
  bool _busy = false;

  // Cycle (only when the user has it on).
  bool _gentleOffered = false;
  bool _useGentle = true;
  bool _periodToday = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    JourneyState? s;
    var gentle = false, period = false;
    try {
      s = await widget.journeys.active();
    } catch (_) {}
    try {
      gentle = await widget.cycle?.gentleToday() ?? false;
      period = await widget.cycle?.periodToday() ?? false;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _s = s;
      _loading = false;
      _gentleOffered = gentle;
      _periodToday = period;
    });
  }

  Future<void> _syncReminders(JourneyState? s) async {
    try {
      await widget.nudges?.setJourneyReminders(s == null ? const [] : widget.journeys.reminders(s));
    } catch (_) {}
  }

  Future<void> _toggle(DayItem item) async {
    if (_busy) return;
    setState(() => _busy = true);
    final before = _s?.daysDone ?? 0;
    final s = await widget.journeys.toggle(item);
    await _syncReminders(s); // bedtime may have moved
    if (!mounted) return;
    setState(() {
      _s = s;
      _busy = false;
    });
    if (s != null && s.daysDone > before && !s.finished) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Day ${s.daysDone} done. See you tomorrow!')));
    }
  }

  Future<void> _skip() async {
    final ok = await widget.journeys.skipToday();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Rest day taken — no streak lost. Back tomorrow.'
          : 'Your rest pass is used this week. Do any one small thing today instead.'),
    ));
    await _load();
  }

  Future<void> _menu(_Menu m) async {
    final s = _s;
    if (s == null) return;
    switch (m) {
      case _Menu.pause:
        final next = await widget.journeys.setPaused(!s.paused);
        await _syncReminders(next);
      case _Menu.remindersOff:
        final setup = s.setup;
        await widget.journeys.updateSetup(JourneySetup(
          id: setup.id,
          wake: setup.wake,
          usualBedtime: setup.usualBedtime,
          diet: setup.diet,
          budget: setup.budget,
          level: setup.level,
          remindWake: false,
          remindMove: false,
          remindWindDown: false,
          moveAt: setup.moveAt,
        ));
        await _syncReminders(null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Journey reminders are off.')));
        }
      case _Menu.stop:
        final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Stop this journey?'),
            content: const Text('Your progress for this journey will be cleared. You can start again any time.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep going')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Stop')),
            ],
          ),
        );
        if (yes != true) return;
        await widget.journeys.stop();
        await _syncReminders(null);
        if (mounted) Navigator.of(context).pop();
        return;
    }
    await _load();
  }

  Future<void> _startWorkout(Workout workout) async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => JourneyWorkoutScreen(workout: workout, color: journeyColor(_s!.setup.id)),
    ));
    if (done == true && !(_s?.ticks.contains(DayItem.move) ?? true)) await _toggle(DayItem.move);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Journey')),
        body: const Center(child: Text('No journey running.')),
      );
    }
    final color = journeyColor(s.setup.id);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.def.title),
        actions: [
          PopupMenuButton<_Menu>(
            onSelected: _menu,
            itemBuilder: (_) => [
              PopupMenuItem(value: _Menu.pause, child: Text(s.paused ? 'Resume' : 'Pause')),
              const PopupMenuItem(value: _Menu.remindersOff, child: Text('Turn reminders off')),
              const PopupMenuItem(value: _Menu.stop, child: Text('Stop journey')),
            ],
          ),
        ],
      ),
      body: s.finished ? _Finished(state: s, color: color) : _body(context, s, color),
    );
  }

  Widget _body(BuildContext context, JourneyState s, Color color) {
    final text = Theme.of(context).textTheme;
    final day = widget.journeys.today(s);
    final doneToday = widget.journeys.doneToday(s);
    final quiet = widget.journeys.quietDays(s);
    final bed = widget.journeys.bedtimeFor(s);
    final meals = widget.journeys.mealsToday(s);
    final locked = doneToday || s.paused;
    final gentle = _gentleOffered && _useGentle && s.setup.id == JourneyId.fitIn30;
    final workout = gentle ? gentleWorkout : day.workout;

    return ListView(
      padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
      children: [
        HuxHeroCard(
          icon: journeyIcon(s.setup.id),
          color: color,
          eyebrow: s.paused
              ? 'Paused'
              : doneToday
                  ? 'Day ${s.daysDone} done'
                  : 'Day ${s.currentDay} of ${s.def.days}${day.challenge ? ' · Challenge' : ''}',
          title: day.focus,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HuxProgressBar(value: s.daysDone / s.def.days, color: color),
              const SizedBox(height: HuxSpacing.xs),
              Text('${s.ticks.length} of 3 done today', style: text.labelSmall),
            ],
          ),
        ),
        if (quiet >= 2 && !doneToday && !s.paused) ...[
          const SizedBox(height: HuxSpacing.md),
          HuxCard(
            child: Row(
              children: [
                const HuxIconBadge(icon: Icons.waving_hand_rounded, color: HuxColors.ringHabit, size: 36),
                const SizedBox(width: HuxSpacing.md),
                Expanded(
                  child: Text('Welcome back! Continue from day ${s.currentDay} — nothing is lost.',
                      style: text.bodyMedium),
                ),
              ],
            ),
          ),
        ],
        if (s.paused) ...[
          const SizedBox(height: HuxSpacing.md),
          FilledButton.icon(
            onPressed: () => _menu(_Menu.pause),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Resume journey'),
          ),
        ],
        const SizedBox(height: HuxSpacing.lg),

        // ---- 1. sleep ----
        _ItemCard(
          icon: Icons.bedtime_rounded,
          color: HuxColors.ringSleep,
          title: 'Sleep',
          done: s.ticks.contains(DayItem.sleep),
          locked: locked,
          tickLabel: 'In bed on time',
          onTick: () => _toggle(DayItem.sleep),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: HuxSpacing.sm,
                runSpacing: HuxSpacing.xs,
                children: [
                  HuxPill(label: 'Wake ${s.setup.wake.label}', color: HuxColors.ringSteps, icon: Icons.alarm_rounded),
                  HuxPill(label: 'In bed by ${bed.label}', color: HuxColors.ringSleep, icon: Icons.bedtime_outlined),
                ],
              ),
              const SizedBox(height: HuxSpacing.xs),
              Text('Wind down from ${bed.plusMinutes(-30).label}: lights low, phone away.',
                  style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
            ],
          ),
        ),
        const SizedBox(height: HuxSpacing.md),

        // ---- 2. food ----
        _ItemCard(
          icon: Icons.restaurant_rounded,
          color: HuxColors.ringFood,
          title: 'Food',
          done: s.ticks.contains(DayItem.food),
          locked: locked,
          tickLabel: 'Ate one of these',
          onTick: () => _toggle(DayItem.food),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in meals.entries) ...[
                Text(e.key.label.toUpperCase(),
                    style: text.labelSmall?.copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w700)),
                for (final m in e.value)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m.budget.symbol}  ', style: text.labelMedium?.copyWith(color: HuxColors.ringFood)),
                        Expanded(
                          child: Text.rich(TextSpan(children: [
                            TextSpan(text: m.name, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            TextSpan(
                              text: '  ${m.portion} · ${m.proteinG.round()} g protein · ${m.kcal.round()} kcal'
                                  ' · C ${m.carbsG.round()} / F ${m.fatG.round()} g',
                              style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
                            ),
                          ])),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: HuxSpacing.sm),
              ],
              if (_periodToday) ...[
                Text('Period days: add iron — ragi, rajma, chana with jaggery, palak. Lemon or amla helps absorb it.',
                    style: text.bodySmall?.copyWith(color: HuxColors.ringFood)),
                const SizedBox(height: HuxSpacing.xs),
              ],
              Text('Approximate home-style values. Pick one per meal.',
                  style: text.labelSmall?.copyWith(color: HuxColors.mutedText)),
            ],
          ),
        ),
        const SizedBox(height: HuxSpacing.md),

        // ---- 3. move ----
        _ItemCard(
          icon: Icons.fitness_center_rounded,
          color: color,
          title: 'Move',
          done: s.ticks.contains(DayItem.move),
          locked: locked,
          tickLabel: 'Done',
          onTick: () => _toggle(DayItem.move),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_gentleOffered && s.setup.id == JourneyId.fitIn30)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _useGentle,
                  onChanged: locked ? null : (v) => setState(() => _useGentle = v),
                  title: const Text('Period day: gentle version'),
                  subtitle: const Text('Still counts for today. Turn off if you feel strong.'),
                ),
              Text('${workout.title} · about ${workout.minutes} min',
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: HuxSpacing.xs),
              Text(
                'Warm-up ${workout.warmup.length} moves · main ${workout.main.length} moves'
                '${workout.rounds > 1 ? ' × ${workout.rounds} rounds' : ''} · cool-down',
                style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
              ),
              const SizedBox(height: HuxSpacing.sm),
              if (!locked)
                FilledButton.icon(
                  onPressed: () => _startWorkout(workout),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start workout'),
                ),
            ],
          ),
        ),
        const SizedBox(height: HuxSpacing.lg),
        if (!locked)
          Center(
            child: TextButton(
              onPressed: _skip,
              child: Text(widget.journeys.restPassAvailable(s) ? 'Not today (use rest pass)' : 'Not today'),
            ),
          ),
        const SizedBox(height: HuxSpacing.sm),
        Text('Stop any move that hurts. Wellness program, not medical advice.',
            textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final bool done;
  final bool locked;
  final String tickLabel;
  final VoidCallback onTick;
  final Widget child;

  const _ItemCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.done,
    required this.locked,
    required this.tickLabel,
    required this.onTick,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return HuxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HuxIconBadge(icon: done ? Icons.check_rounded : icon, color: done ? HuxColors.recharged : color, size: 36),
              const SizedBox(width: HuxSpacing.md),
              Expanded(child: Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              FilterChip(
                label: Text(tickLabel),
                selected: done,
                onSelected: locked ? null : (_) => onTick(),
              ),
            ],
          ),
          const SizedBox(height: HuxSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _Finished extends StatelessWidget {
  final JourneyState state;
  final Color color;

  const _Finished({required this.state, required this.color});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(HuxSpacing.lg),
      children: [
        ShareCapture(
          fileName: 'hux-journey.png',
          shareText: 'I finished ${state.def.title} on HUX',
          buttonLabel: 'Share',
          child: HuxHeroCard(
            icon: Icons.emoji_events_rounded,
            color: color,
            eyebrow: 'Journey complete',
            title: '${state.def.title} — ${state.def.days} days done',
            subtitle: 'Pick the 2 habits you\'ll keep. Your next journey starts only when you choose.',
          ),
        ),
        const SizedBox(height: HuxSpacing.lg),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to journeys')),
        const SizedBox(height: HuxSpacing.sm),
        Text('Available journeys: ${journeys.map((j) => j.title).join(', ')}',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
