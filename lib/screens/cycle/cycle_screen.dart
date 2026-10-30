/// Cycle: where you are, what's next, one big log button, how you feel
/// today, and what helps in this phase. Quiet, plain, private.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/cycle/cycle_content.dart';
import '../../core/cycle/cycle_models.dart';
import '../../core/cycle/cycle_predictor.dart';
import '../../core/cycle/cycle_service.dart';
import '../../core/nudges/nudge_service.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import '../../widgets/hux/hux_kit.dart';
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
    final day = d.settings.mode.hasPhases ? f.dayOfCycle : null;
    final today = d.dayLog(widget.cycle.today);
    final showFlow = f.periodOpen || f.phase == CyclePhase.period;
    final phase = f.phase;
    final tips = phase == null ? null : CycleContent.tips(phase);
    final short = phase == null ? null : CycleContent.short(phase);
    final history = d.periods.reversed.take(6).toList();
    final nextText = f.mode == CycleMode.pregnant
        ? 'Paused'
        : f.isLate
            ? 'Late'
            : (f.from != null && f.to != null)
                ? CycleContent.range(f.from!, f.to!)
                : '—';

    void tip(String title, String body) => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (c) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: huxInk)),
                  const SizedBox(height: 8),
                  Text(body, style: const TextStyle(fontSize: 16, height: 1.45, color: Color(0xFF3A3646))),
                ],
              ),
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
      children: [
        Center(
          child: _PhaseDial(
            day: day,
            cycleDays: f.avgCycleDays,
            periodDays: f.periodDays,
            centerTitle: day == null ? (f.isLate ? 'Late' : '—') : '$day',
            centerSub: phase?.label ?? d.settings.mode.label,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _MiniStat(label: 'Next period', value: nextText)),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniStat(
                label: 'Confidence',
                value: f.confidence == Confidence.none ? '—' : f.confidence.name[0].toUpperCase() + f.confidence.name.substring(1),
              ),
            ),
          ],
        ),

        if (tips != null && short != null) ...[
          const SizedBox(height: 18),
          const HuxTileLabel('This week, what helps'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _HelpTile(label: 'Move', value: short.move, color: const Color(0xFFC25E00), onTap: () => tip('Move', tips.move))),
              const SizedBox(width: 10),
              Expanded(child: _HelpTile(label: 'Food', value: short.food, color: const Color(0xFF1E8746), onTap: () => tip('Food', tips.food))),
              const SizedBox(width: 10),
              Expanded(child: _HelpTile(label: 'Sleep', value: short.sleep, color: HuxColors.accentIndigo, onTap: () => tip('Sleep', tips.sleep))),
            ],
          ),
        ],

        const SizedBox(height: 18),
        const HuxTileLabel('Today'),
        const SizedBox(height: 8),
        if (showFlow)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final fl in FlowLevel.values)
                ChoiceChip(
                  label: Text(fl.label),
                  selected: today.flow == fl,
                  onSelected: (on) => _setToday(DayLog(flow: on ? fl : null, symptoms: today.symptoms)),
                ),
            ],
          ),
        if (showFlow) const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
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

        for (final n in f.notes) ...[
          const SizedBox(height: 12),
          HuxTile(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: HuxColors.accentPurple),
                const SizedBox(width: 10),
                Expanded(child: Text(n, style: const TextStyle(fontSize: 15, color: huxInk, height: 1.4))),
              ],
            ),
          ),
        ],

        // ---- the ONE big action ----
        const SizedBox(height: 20),
        if (f.mode != CycleMode.pregnant) ...[
          FilledButton(
            onPressed: _busy ? null : () => f.periodOpen ? _logEnd() : _logStart(),
            style: FilledButton.styleFrom(
              backgroundColor: HuxColors.accentPink,
              minimumSize: const Size.fromHeight(56),
              shape: const StadiumBorder(),
            ),
            child: Text(f.periodOpen ? 'Period ended today' : 'Period started today',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          TextButton(
            onPressed: _busy ? null : () => f.periodOpen ? _logEnd(pick: true) : _logStart(pick: true),
            child: Text(f.periodOpen ? 'Ended on another day' : 'Started on another day'),
          ),
        ],

        if (history.isNotEmpty) ...[
          const SizedBox(height: 12),
          const HuxTileLabel('Recent periods'),
          const SizedBox(height: 4),
          for (final p in history) _HistoryRow(period: p, data: d, onRemove: () => _remove(p)),
        ],
        if (CycleContent.scoreNote(phase) != null) ...[
          const SizedBox(height: 12),
          Text(CycleContent.scoreNote(phase)!, style: const TextStyle(fontSize: 13, color: huxMuted)),
        ],
        const SizedBox(height: 16),
        const CyclePrivacyNote(),
      ],
    );
  }
}

/// The cycle as a dial: one arc per phase, a marker on today.
class _PhaseDial extends StatelessWidget {
  final int? day;
  final int cycleDays;
  final int periodDays;
  final String centerTitle;
  final String centerSub;

  const _PhaseDial({
    required this.day,
    required this.cycleDays,
    required this.periodDays,
    required this.centerTitle,
    required this.centerSub,
  });

  @override
  Widget build(BuildContext context) {
    final len = cycleDays.clamp(18, 60);
    return Semantics(
      label: day == null ? 'Cycle dial, no day yet' : 'Cycle day $day of about $len, $centerSub',
      excludeSemantics: true,
      child: SizedBox(
        width: 240,
        height: 240,
        child: CustomPaint(
          painter: _DialPainter(day: day, len: len, periodDays: periodDays),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Day', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: huxMuted)),
                HuxTileValue(centerTitle, size: 58),
                const SizedBox(height: 4),
                Text(centerSub, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: HuxColors.accentPurple)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final int? day;
  final int len;
  final int periodDays;

  _DialPainter({required this.day, required this.len, required this.periodDays});

  static Color _color(CyclePhase p) => switch (p) {
        CyclePhase.period => const Color(0xFFE5484D),
        CyclePhase.follicular => const Color(0xFFF7B6D9),
        CyclePhase.ovulatory => const Color(0xFFC9B8F5),
        CyclePhase.luteal => const Color(0xFF8B3FD0),
      };

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 24.0;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - stroke / 2 - 4;
    final rect = Rect.fromCircle(center: c, radius: r);
    final per = 2 * math.pi / len;
    const gapA = 0.035;
    // Merge consecutive days of the same phase into one arc.
    var start = 1;
    for (var dd = 2; dd <= len + 1; dd++) {
      final prev = CyclePredictor.phaseForDay(dd - 1, len, periodDays);
      final cur = dd > len ? null : CyclePredictor.phaseForDay(dd, len, periodDays);
      if (cur == prev) continue;
      final a0 = -math.pi / 2 + (start - 1) * per + gapA;
      final a1 = -math.pi / 2 + (dd - 1) * per - gapA;
      canvas.drawArc(rect, a0, a1 - a0, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = _color(prev));
      start = dd;
    }
    final d = day;
    if (d != null && d >= 1 && d <= len) {
      final a = -math.pi / 2 + (d - 0.5) * per;
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      canvas.drawCircle(p, stroke * 0.78, Paint()..color = const Color(0x401C0D30));
      canvas.drawCircle(p, stroke * 0.72, Paint()..color = Colors.white);
      canvas.drawCircle(p, stroke * 0.72, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFF8B3FD0));
    }
  }

  @override
  bool shouldRepaint(_DialPainter o) => o.day != day || o.len != len || o.periodDays != periodDays;
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => HuxTile(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HuxTileLabel(label),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: huxInk)),
          ],
        ),
      );
}

class _HelpTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  const _HelpTile({required this.label, required this.value, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => HuxTile(
        onTap: onTap,
        semanticLabel: '$label: $value. Tap for more.',
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: ExcludeSemantics(
          child: Column(
            children: [
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(height: 6),
              Text(value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: huxInk)),
            ],
          ),
        ),
      );
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

  static const _points = [
    ('Fair scores', 'A lower Charge before your period is often normal. HUX compares you with your own same-phase days.'),
    ('A range, not a date', 'Predictions show a likely window that gets sharper each cycle. Irregular cycles welcome.'),
    ('Tips by phase', 'Simple move, food and sleep ideas for each phase, Indian-kitchen friendly.'),
    ('On this phone', 'Stays on this phone. Optional lock. Delete everything in one tap.'),
  ];

  void _howItWorks(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (c) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          const Text('How Cycle works', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: huxInk)),
          const SizedBox(height: 12),
          for (final (title, body) in _points)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: huxInk)),
                  const SizedBox(height: 2),
                  Text(body, style: const TextStyle(fontSize: 15, height: 1.4, color: huxMuted)),
                ],
              ),
            ),
          const CyclePrivacyNote(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget fact(String value, String label) => Expanded(
          child: HuxTile(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: huxInk)),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontSize: 13, color: huxMuted)),
              ],
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
      children: [
        const Text('Your phase, in your scores',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: huxInk, height: 1.15)),
        const SizedBox(height: 20),
        const Center(
          child: _PhaseDial(day: 9, cycleDays: 28, periodDays: 5, centerTitle: '9', centerSub: 'Follicular'),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            fact('Fair', 'scores'),
            const SizedBox(width: 8),
            fact('Range', 'not a date'),
            const SizedBox(width: 8),
            fact('Private', 'this phone'),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onStart,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
          child: const Text('Set up Cycle', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 4),
        Center(child: TextButton(onPressed: () => _howItWorks(context), child: const Text('How it works'))),
        const SizedBox(height: 8),
        const Text('Wellness estimates. Not for contraception or diagnosis.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: huxMuted)),
      ],
    );
  }
}
