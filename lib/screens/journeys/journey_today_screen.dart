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
import '../../widgets/hux/hux_kit.dart';
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
    final day = widget.journeys.today(s);
    final doneToday = widget.journeys.doneToday(s);
    final quiet = widget.journeys.quietDays(s);
    final bed = widget.journeys.bedtimeFor(s);
    final meals = widget.journeys.mealsToday(s);
    final locked = doneToday || s.paused;
    final gentle = _gentleOffered && _useGentle && s.setup.id == JourneyId.fitIn30;
    final workout = gentle ? gentleWorkout : day.workout;

    // Food tile shows the meal that's next by the clock.
    final hour = DateTime.now().hour;
    final wanted = hour < 11
        ? MealSlot.breakfast
        : hour < 16
            ? MealSlot.lunch
            : hour < 18
                ? MealSlot.snack
                : MealSlot.dinner;
    final slot = meals.containsKey(wanted) && meals[wanted]!.isNotEmpty
        ? wanted
        : meals.keys.firstWhere((k) => meals[k]!.isNotEmpty, orElse: () => wanted);
    final nextMeal = meals[slot]?.isNotEmpty == true ? meals[slot]!.first : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
      children: [
        Text(s.def.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
        Text(
          s.paused
              ? 'Paused'
              : doneToday
                  ? 'Day ${s.daysDone} done'
                  : 'Day ${s.currentDay}${day.challenge ? ' · challenge' : ''}',
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: huxInk),
        ),
        const SizedBox(height: 14),
        _DayDots(total: s.def.days, done: s.daysDone, today: doneToday ? null : s.currentDay, color: color),
        if (quiet >= 2 && !doneToday && !s.paused) ...[
          const SizedBox(height: 12),
          const HuxStatChip('Welcome back · nothing is lost', tone: HuxTone.good),
        ],
        if (s.paused) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _menu(_Menu.pause),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Resume journey'),
          ),
        ],
        const SizedBox(height: 18),

        _ItemTile(
          icon: Icons.bedtime_outlined,
          color: HuxColors.ringSleep,
          label: 'Sleep',
          value: 'In bed by ${bed.label}',
          done: s.ticks.contains(DayItem.sleep),
          locked: locked,
          onTick: () => _toggle(DayItem.sleep),
          onDetails: () => _details(context, 'Sleep', [
            _DetailRow('Wake', s.setup.wake.label),
            _DetailRow('In bed by', bed.label),
            _DetailRow('Wind down from', bed.plusMinutes(-30).label),
            _DetailNote(day.focus),
          ]),
        ),
        const SizedBox(height: 12),
        _ItemTile(
          icon: Icons.restaurant_outlined,
          color: HuxColors.ringFood,
          label: 'Food',
          value: nextMeal == null ? 'See today\'s meals' : '${slot.label}: ${nextMeal.name}',
          done: s.ticks.contains(DayItem.food),
          locked: locked,
          onTick: () => _toggle(DayItem.food),
          onDetails: () => _details(context, 'Today\'s meals', [
            for (final e in meals.entries)
              for (final m in e.value)
                _DetailRow('${e.key.label} · ${m.budget.symbol}', m.name,
                    sub: '${m.portion} · ${m.proteinG.round()} g protein · ${m.kcal.round()} kcal'),
            if (_periodToday)
              const _DetailNote('Period days: add iron — ragi, rajma, chana with jaggery, palak.'),
            const _DetailNote('Approximate home-style values. Pick one per meal.'),
          ]),
        ),
        const SizedBox(height: 12),
        _ItemTile(
          icon: Icons.fitness_center_outlined,
          color: color,
          label: 'Move · ${workout.minutes} min',
          value: workout.title,
          done: s.ticks.contains(DayItem.move),
          locked: locked,
          onTick: () => _toggle(DayItem.move),
          onDetails: () => _details(context, workout.title, [
            _DetailRow('Warm-up', '${workout.warmup.length} moves'),
            _DetailRow('Main', '${workout.main.length} moves${workout.rounds > 1 ? ' × ${workout.rounds}' : ''}'),
            const _DetailRow('Cool-down', 'stretch + breathing'),
          ]),
          extra: Row(
            children: [
              if (!locked)
                FilledButton.icon(
                  onPressed: () => _startWorkout(workout),
                  style: FilledButton.styleFrom(backgroundColor: huxInk, minimumSize: const Size(0, 44), shape: const StadiumBorder()),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start'),
                ),
              if (_gentleOffered && s.setup.id == JourneyId.fitIn30) ...[
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Gentle day'),
                  selected: _useGentle,
                  onSelected: locked ? null : (v) => setState(() => _useGentle = v),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (!locked)
          Center(
            child: TextButton(
              onPressed: _skip,
              child: Text(widget.journeys.restPassAvailable(s) ? 'Not today (use rest pass)' : 'Not today'),
            ),
          ),
        const Text('Stop any move that hurts.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: huxMuted)),
      ],
    );
  }

  Future<void> _details(BuildContext context, String title, List<Widget> rows) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.8),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: huxInk)),
                const SizedBox(height: 12),
                ...rows,
              ],
            ),
          ),
        ),
      );
}

/// One dot per day: done (filled), today (ring), challenge days tinted.
class _DayDots extends StatelessWidget {
  final int total;
  final int done;
  final int? today;
  final Color color;

  const _DayDots({required this.total, required this.done, required this.today, required this.color});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$done of $total days done',
      child: LayoutBuilder(builder: (context, box) {
        const perRow = 10, gap = 8.0;
        final size = (box.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var d = 1; d <= total; d++)
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: d <= done
                      ? color
                      : d == today
                          ? Colors.white
                          : (d % 7 == 0 || d == total)
                              ? const Color(0xFFFCE8F3)
                              : const Color(0xFFE4E0EC),
                  border: d == today ? Border.all(color: color, width: 3) : null,
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool done;
  final bool locked;
  final VoidCallback onTick;
  final VoidCallback onDetails;
  final Widget? extra;

  const _ItemTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.done,
    required this.locked,
    required this.onTick,
    required this.onDetails,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return HuxTile(
      onTap: onDetails,
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: huxMuted)),
                    Text(value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: huxInk)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                toggled: done,
                label: done ? '$label done' : 'Mark $label done',
                excludeSemantics: true,
                child: InkWell(
                  onTap: locked ? null : onTick,
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 64, minHeight: 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: done ? const Color(0xFFE7F6EE) : Colors.white,
                      border: done ? null : Border.all(color: const Color(0xFFD9D4E2), width: 2),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(done ? 'Done' : 'Tick',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: done ? const Color(0xFF17804B) : huxMuted,
                        )),
                  ),
                ),
              ),
            ],
          ),
          if (extra != null) ...[const SizedBox(height: 12), extra!],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;

  const _DetailRow(this.label, this.value, {this.sub});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: huxMuted)),
            Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: huxInk)),
            if (sub != null) Text(sub!, style: const TextStyle(fontSize: 14, color: huxMuted)),
          ],
        ),
      );
}

class _DetailNote extends StatelessWidget {
  final String text;

  const _DetailNote(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(text, style: const TextStyle(fontSize: 14, color: huxMuted, height: 1.4)),
      );
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
