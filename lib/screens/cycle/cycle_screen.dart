/// Cycle: where you are, what's next, one big log button, how you feel
/// today, and what helps in this phase. Quiet, plain, private.
library;

import 'package:flutter/material.dart';

import '../../core/cycle/cycle_content.dart';
import '../../core/cycle/cycle_models.dart';
import '../../core/cycle/cycle_predictor.dart';
import '../../core/cycle/cycle_service.dart';
import '../../core/nudges/nudge_service.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import '../../theme/hux_ui.dart';
import 'cycle_settings_screen.dart';
import 'cycle_setup_screen.dart';
import 'cycle_widgets.dart';

class CycleScreen extends StatefulWidget {
  final CycleService cycle;
  final NudgeService? nudges;

  /// Injectable for tests; defaults to Face ID / fingerprint / PIN.
  final Future<bool> Function()? unlock;

  const CycleScreen({super.key, required this.cycle, this.nudges, this.unlock});

  @override
  State<CycleScreen> createState() => _CycleScreenState();
}

class _CycleScreenState extends State<CycleScreen> {
  CycleData? _d;
  bool _loading = true;
  bool _unlocked = false;
  bool _triedUnlock = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    CycleData d;
    try {
      d = await widget.cycle.load();
    } catch (_) {
      d = CycleData.empty;
    }
    if (!mounted) return;
    setState(() {
      _d = d;
      _loading = false;
    });
    if (d.settings.enabled && d.settings.lock && !_unlocked && !_triedUnlock) {
      _triedUnlock = true;
      await _unlock();
    }
  }

  Future<void> _unlock() async {
    final ok = await (widget.unlock ?? CycleLock.unlock)();
    if (mounted && ok) setState(() => _unlocked = true);
  }

  Future<void> _setup() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CycleSetupScreen(cycle: widget.cycle, nudges: widget.nudges),
    ));
    if (ok == true) {
      _unlocked = true; // just set up — don't ask straight away
      await _load();
    }
  }

  Future<void> _settings() async {
    final result = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => CycleSettingsScreen(cycle: widget.cycle, nudges: widget.nudges),
    ));
    if (!mounted) return;
    if (result == 'deleted') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cycle data deleted.')));
      Navigator.of(context).pop();
      return;
    }
    await _load();
  }

  Future<DateTime?> _pickDay(String help) async {
    final today = widget.cycle.today;
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: addDays(today, -60),
      lastDate: today,
      helpText: help,
    );
    return picked == null ? null : dayOf(picked);
  }

  Future<void> _logStart({bool pick = false}) async {
    final day = pick ? await _pickDay('Period started on') : widget.cycle.today;
    if (day == null || _busy) return;
    setState(() => _busy = true);
    await widget.cycle.logStart(day);
    await widget.cycle.applyHeadsUp(widget.nudges);
    _busy = false;
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Logged: period started ${CycleContent.date(day)}.')));
    }
  }

  Future<void> _logEnd({bool pick = false}) async {
    final day = pick ? await _pickDay('Period ended on') : widget.cycle.today;
    if (day == null || _busy) return;
    setState(() => _busy = true);
    final ok = await widget.cycle.logEnd(day);
    await widget.cycle.applyHeadsUp(widget.nudges);
    _busy = false;
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok == null ? 'Pick a day within 2 weeks of the start.' : 'Logged: period ended.'),
      ));
    }
  }

  Future<void> _setToday(DayLog log) async {
    await widget.cycle.setDay(widget.cycle.today, log);
    await _load();
  }

  Future<void> _remove(PeriodRecord p) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove this period?'),
        content: Text('Started ${CycleContent.date(p.start)}. Predictions will update.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true) return;
    await widget.cycle.removePeriod(p.start);
    await widget.cycle.applyHeadsUp(widget.nudges);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (_loading || d == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!d.settings.enabled) {
      return Scaffold(appBar: AppBar(title: const Text('Cycle')), body: _Intro(onStart: _setup));
    }
    if (d.settings.lock && !_unlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cycle')),
        body: const HuxEmptyState(
          icon: Icons.lock_outline_rounded,
          color: cycleColor,
          title: 'Cycle is locked',
          body: 'Use Face ID, fingerprint or your phone PIN to open it.',
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(HuxSpacing.lg),
          child: FilledButton.icon(
            onPressed: _unlock,
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('Unlock'),
          ),
        ),
      );
    }
    final f = widget.cycle.forecastFor(d);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cycle'),
        actions: [
          IconButton(tooltip: 'Cycle settings', onPressed: _settings, icon: const Icon(Icons.tune_rounded)),
        ],
      ),
      body: _body(context, d, f),
    );
  }

  Widget _body(BuildContext context, CycleData d, CycleForecast f) {
    final text = Theme.of(context).textTheme;
    final day = f.dayOfCycle;
    final today = d.dayLog(widget.cycle.today);
    final showFlow = f.periodOpen || f.phase == CyclePhase.period;
    final tips = f.phase == null ? null : CycleContent.tips(f.phase!);
    final history = d.periods.reversed.take(6).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
      children: [
        HuxHeroCard(
          icon: Icons.water_drop_rounded,
          color: cycleColor,
          eyebrow: day == null ? d.settings.mode.label : 'Day $day of about ${f.avgCycleDays}',
          title: f.phase?.label ?? (f.isLate ? 'Waiting for your period' : d.settings.mode.label),
          subtitle: [
            CycleContent.statusLine(f),
            if (f.confidence != Confidence.none && f.from != null && !f.isLate) f.confidence.label,
          ].join(' · '),
          trailing: day == null
              ? null
              : HuxScoreRing(
                  progress: (day / f.avgCycleDays).clamp(0.0, 1.0),
                  centerText: '$day',
                  color: cycleColor,
                  size: 56,
                  stroke: 6,
                ),
        ),
        const SizedBox(height: HuxSpacing.md),

        // ---- the ONE big action ----
        if (f.periodOpen) ...[
          FilledButton.icon(
            onPressed: _busy ? null : () => _logEnd(),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Period ended today'),
          ),
          TextButton(onPressed: _busy ? null : () => _logEnd(pick: true), child: const Text('Ended on another day')),
        ] else ...[
          FilledButton.icon(
            onPressed: _busy ? null : () => _logStart(),
            icon: const Icon(Icons.water_drop_outlined),
            label: const Text('Period started today'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _logStart(pick: true),
            child: const Text('Started on another day'),
          ),
        ],

        // ---- today ----
        const SizedBox(height: HuxSpacing.sm),
        HuxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How are you today?', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (showFlow) ...[
                const SizedBox(height: HuxSpacing.sm),
                Wrap(
                  spacing: HuxSpacing.sm,
                  runSpacing: HuxSpacing.xs,
                  children: [
                    for (final fl in FlowLevel.values)
                      ChoiceChip(
                        label: Text(fl.label),
                        selected: today.flow == fl,
                        onSelected: (on) => _setToday(DayLog(flow: on ? fl : null, symptoms: today.symptoms)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: HuxSpacing.sm),
              Wrap(
                spacing: HuxSpacing.sm,
                runSpacing: HuxSpacing.xs,
                children: [
                  for (final s in Symptom.values)
                    FilterChip(
                      label: Text(s.label),
                      selected: today.symptoms.contains(s),
                      onSelected: (on) => _setToday(DayLog(
                        flow: today.flow,
                        symptoms: on ? {...today.symptoms, s} : ({...today.symptoms}..remove(s)),
                      )),
                    ),
                ],
              ),
            ],
          ),
        ),

        // ---- what helps now ----
        if (tips != null) ...[
          const SizedBox(height: HuxSpacing.md),
          HuxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This phase', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: HuxSpacing.xs),
                Text(tips.body, style: text.bodyMedium),
                const SizedBox(height: HuxSpacing.sm),
                _Tip(icon: Icons.directions_walk_rounded, color: HuxColors.ringSteps, text: tips.move),
                _Tip(icon: Icons.restaurant_rounded, color: HuxColors.ringFood, text: tips.food),
                _Tip(icon: Icons.bedtime_rounded, color: HuxColors.ringSleep, text: tips.sleep),
                if (CycleContent.scoreNote(f.phase) != null) ...[
                  const SizedBox(height: HuxSpacing.xs),
                  Text(CycleContent.scoreNote(f.phase)!,
                      style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
                ],
              ],
            ),
          ),
        ],

        // ---- gentle pattern notes ----
        for (final n in f.notes) ...[
          const SizedBox(height: HuxSpacing.md),
          HuxCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: HuxColors.accentPurple),
                const SizedBox(width: HuxSpacing.sm),
                Expanded(child: Text(n, style: text.bodyMedium)),
              ],
            ),
          ),
        ],

        // ---- history ----
        if (history.isNotEmpty) ...[
          const SizedBox(height: HuxSpacing.lg),
          Text('Recent periods', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: HuxSpacing.xs),
          for (final p in history) _HistoryRow(period: p, data: d, onRemove: () => _remove(p)),
        ],
        const SizedBox(height: HuxSpacing.lg),
        const CyclePrivacyNote(),
      ],
    );
  }
}

class _Tip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Tip({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HuxSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: HuxSpacing.sm),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final PeriodRecord period;
  final CycleData data;
  final VoidCallback onRemove;

  const _HistoryRow({required this.period, required this.data, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final i = data.periods.indexOf(period);
    final next = i >= 0 && i + 1 < data.periods.length ? data.periods[i + 1] : null;
    final cycle = next == null ? null : daysBetween(period.start, next.start);
    final parts = [
      if (period.lengthDays != null) '${period.lengthDays}-day period',
      if (cycle != null) '$cycle-day cycle',
      if (period.source == 'health') 'from health app',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.water_drop_rounded, size: 16, color: cycleColor),
          const SizedBox(width: HuxSpacing.sm),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: CycleContent.date(period.start), style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              if (parts.isNotEmpty)
                TextSpan(text: '  ${parts.join(' · ')}', style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
            ])),
          ),
          IconButton(
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 18, color: HuxColors.mutedText),
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  final VoidCallback onStart;

  const _Intro({required this.onStart});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget point(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: HuxSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HuxIconBadge(icon: icon, color: cycleColor, size: 36),
              const SizedBox(width: HuxSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(body, style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
                  ],
                ),
              ),
            ],
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
      children: [
        Text('Your cycle, inside HUX', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: HuxSpacing.xs),
        Text('Not another tracker. HUX uses your phase to explain your energy, sleep and scores.',
            style: text.bodyMedium?.copyWith(color: HuxColors.mutedText)),
        const SizedBox(height: HuxSpacing.lg),
        point(Icons.insights_rounded, 'Scores that understand you',
            'A lower Charge before your period is often normal. HUX compares you with your own same-phase days.'),
        point(Icons.date_range_rounded, 'Honest predictions', 'A likely range that gets sharper each cycle — irregular cycles welcome.'),
        point(Icons.spa_rounded, 'What helps this week', 'Simple move, food and sleep tips for each phase, Indian-kitchen friendly.'),
        point(Icons.lock_outline_rounded, 'Private by default', 'Stays on this phone. Optional lock. Delete in one tap.'),
        const SizedBox(height: HuxSpacing.md),
        FilledButton(onPressed: onStart, child: const Text('Set up Cycle')),
        const SizedBox(height: HuxSpacing.md),
        const CyclePrivacyNote(),
      ],
    );
  }
}
