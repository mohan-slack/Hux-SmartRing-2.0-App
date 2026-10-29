/// Streaks & monthly report: your streak (with rest passes), move weeks,
/// a month calendar, and the month compared with the one before.
library;

import 'package:flutter/material.dart';

import '../../core/progress/monthly_report.dart';
import '../../core/progress/progress_service.dart';
import '../../core/progress/streaks.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import '../../theme/hux_ui.dart';
import '../../widgets/share_card.dart';

class ProgressScreen extends StatefulWidget {
  final ProgressService progress;

  /// True inside the Progress tab: no app bar, transparent background,
  /// extra bottom space for the floating nav bar.
  final bool embedded;

  /// Pinged when the Progress tab becomes visible: recomputes the streak
  /// and report (a meal or session logged elsewhere changes them).
  final Listenable? refreshSignal;

  const ProgressScreen({super.key, required this.progress, this.embedded = false, this.refreshSignal});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// How many months back the report can go.
  static const _maxMonthsBack = 12;

  late DateTime _month; // DateTime.utc(year, month)
  StreakSummary? _streak;
  MonthlyReport? _report;
  bool _loading = true;
  String? _error;

  DateTime get _thisMonth {
    final t = widget.progress.today();
    return DateTime.utc(t.year, t.month);
  }

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_refresh);
    _month = _thisMonth;
    _load(refreshStreak: true);
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!_loading) _load(refreshStreak: true);
  }

  /// Month arrows reuse the streak (it doesn't depend on the month);
  /// a tab refresh recomputes it.
  Future<void> _load({bool refreshStreak = false}) async {
    setState(() => _loading = true);
    try {
      final streak = refreshStreak || _streak == null ? await widget.progress.streaks() : _streak!;
      final report = await widget.progress.monthly(_month.year, _month.month);
      if (!mounted) return;
      setState(() {
        _streak = streak;
        _report = report;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load your progress. Please try again.";
      });
    }
  }

  void _shiftMonth(int by) {
    setState(() => _month = DateTime.utc(_month.year, _month.month + by));
    _load();
  }

  int get _monthsBack => (_thisMonth.year - _month.year) * 12 + _thisMonth.month - _month.month;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final streak = _streak;
    final report = _report;
    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : null,
      appBar: widget.embedded ? null : AppBar(title: const Text('Streaks & monthly report')),
      body: _loading && report == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                  HuxSpacing.lg, HuxSpacing.lg, HuxSpacing.lg, widget.embedded ? HuxGlass.navClearance : HuxSpacing.lg),
              children: [
                if (_error != null) ...[
                  Text(_error!, style: text.bodyMedium),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
                if (streak != null)
                  streak.current >= 2
                      ? ShareCapture(
                          fileName: 'hux-streak.png',
                          shareText: 'My ${streak.current}-day streak on HUX',
                          buttonLabel: 'Share my streak',
                          child: _StreakPanel(streak: streak),
                        )
                      : _StreakPanel(streak: streak),
                const SizedBox(height: HuxSpacing.xl),
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Previous month',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _monthsBack >= _maxMonthsBack || _loading ? null : () => _shiftMonth(-1),
                    ),
                    Expanded(
                      child: Text(
                        '${_monthNames[_month.month - 1]} ${_month.year}',
                        textAlign: TextAlign.center,
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Next month',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _monthsBack == 0 || _loading ? null : () => _shiftMonth(1),
                    ),
                  ],
                ),
                const SizedBox(height: HuxSpacing.sm),
                if (report != null) ...[
                  _MonthCalendar(month: _month, report: report, today: widget.progress.today()),
                  const SizedBox(height: HuxSpacing.lg),
                  _ReportBody(report: report),
                ],
                const SizedBox(height: HuxSpacing.lg),
                Text(
                  'Wellness insights from your own data — not medical advice.',
                  style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
                ),
              ],
            ),
    );
  }
}

class _StreakPanel extends StatelessWidget {
  final StreakSummary streak;
  const _StreakPanel({required this.streak});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = streak;
    final next = s.nextMilestone;
    const flame = HuxColors.ringSteps;
    return HuxHeroCard(
      icon: Icons.local_fire_department_rounded,
      color: s.current > 0 ? flame : HuxColors.mutedText,
      eyebrow: s.todayDone ? 'Today counted ✓' : 'Your streak',
      title: '${s.current} day streak',
      subtitle: s.message,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (next != null && s.current > 0) ...[
            Row(
              children: [
                Expanded(child: HuxProgressBar(value: s.current / next, color: flame)),
                const SizedBox(width: HuxSpacing.sm),
                Text('${next - s.current} to go to $next days', style: text.labelSmall),
              ],
            ),
            const SizedBox(height: HuxSpacing.md),
          ],
          Wrap(
            spacing: HuxSpacing.sm,
            runSpacing: HuxSpacing.sm,
            children: [
              HuxPill(icon: Icons.emoji_events_outlined, label: 'Best: ${s.best} days', color: HuxColors.ringHabit),
              HuxPill(
                icon: Icons.calendar_view_week_rounded,
                label: '${s.moveWeeks} move week${s.moveWeeks == 1 ? '' : 's'} in a row',
                color: HuxColors.ringFood,
              ),
              HuxPill(
                icon: Icons.directions_walk_rounded,
                label: '${s.moveDaysThisWeek} of ${StreakCalculator.moveDaysPerWeek} move days this week',
                color: HuxColors.ringSleep,
              ),
              HuxPill(
                icon: Icons.bedtime_outlined,
                label: s.restPassReady ? 'Rest pass ready' : 'Rest pass used this week',
                color: HuxColors.accentPurple,
              ),
            ],
          ),
          const SizedBox(height: HuxSpacing.md),
          Text(
            'A day counts when you reach your step goal, do a guided session, log a meal or '
            'use the journal. Miss one day and a rest pass covers it (one a week). '
            'A move week = ${StreakCalculator.moveDaysPerWeek}+ days with your step goal or a session.',
            style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
          ),
        ],
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  final DateTime month;
  final MonthlyReport report;
  final DateTime today;
  const _MonthCalendar({required this.month, required this.report, required this.today});

  static const _moved = HuxColors.ringFood;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final first = DateTime.utc(month.year, month.month);
    final daysInMonth = DateTime.utc(month.year, month.month + 1).difference(first).inDays;
    final lead = first.weekday - 1; // Monday-first grid
    final cells = <Widget>[
      for (final l in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
        Center(child: Text(l, style: text.labelSmall?.copyWith(color: HuxColors.mutedText))),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++) _dayCell(context, DateTime.utc(month.year, month.month, d)),
    ];
    return HuxCard(
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: HuxSpacing.xs,
            crossAxisSpacing: HuxSpacing.xs,
            children: cells,
          ),
          const SizedBox(height: HuxSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(_moved, filled: true),
              Text(' Moved   ', style: text.bodySmall),
              _legendDot(_moved, filled: false),
              Text(' Logged', style: text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color c, {required bool filled}) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? c : null,
          border: Border.all(color: c, width: 1.5),
        ),
      );

  Widget _dayCell(BuildContext context, DateTime day) {
    final r = report.days[day];
    final future = day.isAfter(today);
    final isToday = day == today;
    final moved = r?.moved ?? false;
    final active = r?.active ?? false;
    final label = '${day.day}';
    return Semantics(
      label: '$label: ${moved ? 'moved' : active ? 'logged' : future ? 'upcoming' : 'nothing logged'}',
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: moved ? _moved : (active ? _moved.withValues(alpha: 0.12) : null),
          border: Border.all(
            color: isToday
                ? HuxColors.ink
                : active
                    ? _moved
                    : Colors.transparent,
            width: isToday ? 2 : 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: ExcludeSemantics(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isToday || moved ? FontWeight.w700 : FontWeight.w400,
              color: moved
                  ? HuxColors.onVivid
                  : future
                      ? HuxColors.mutedText.withValues(alpha: 0.5)
                      : HuxColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  final MonthlyReport report;
  const _ReportBody({required this.report});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = report.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(report.headline, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: HuxSpacing.md),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.9,
          mainAxisSpacing: HuxSpacing.sm,
          crossAxisSpacing: HuxSpacing.sm,
          children: [
            _Stat(
              icon: Icons.event_available_rounded,
              color: HuxColors.ringFood,
              value: '${s.activeDays}/${s.days}',
              label: 'active days',
              progress: s.days == 0 ? null : s.activeDays / s.days,
            ),
            _Stat(
              icon: Icons.directions_walk_rounded,
              color: HuxColors.ringSteps,
              value: '${s.days7k}',
              label: 'days with 7,000+ steps',
              progress: s.days == 0 ? null : s.days7k / s.days,
            ),
            _Stat(
              icon: Icons.fitness_center_rounded,
              color: HuxColors.ringCharge,
              value: '${s.sessionDays}',
              label: 'guided session days',
            ),
            _Stat(
              icon: Icons.bedtime_outlined,
              color: HuxColors.ringSleep,
              value: s.medianSleepMinutes == null ? '—' : MonthlyReportBuilder.hm(s.medianSleepMinutes!),
              label: 'usual sleep (${s.nights} nights)',
            ),
          ],
        ),
        if (report.changes.isNotEmpty) ...[
          const SizedBox(height: HuxSpacing.lg),
          const HuxSectionTitle('Compared with last month', icon: Icons.compare_arrows_rounded),
          HuxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in report.changes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: HuxSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.trending_flat_rounded, size: 18, color: HuxColors.accentPurple),
                        const SizedBox(width: HuxSpacing.sm),
                        Expanded(child: Text(c, style: text.bodyMedium)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (s.bestDaySteps != null && s.bestDay != null) ...[
          const SizedBox(height: HuxSpacing.sm),
          Text(
            'Best day: ${s.bestDay!.day} ${_ProgressScreenState._monthNames[s.bestDay!.month - 1].substring(0, 3)} '
            '— ${_fmt(s.bestDaySteps!)} steps.',
            style: text.bodyMedium,
          ),
        ],
        if (report.pattern != null) ...[
          const SizedBox(height: HuxSpacing.lg),
          const HuxSectionTitle('A pattern this month', icon: Icons.insights_rounded),
          HuxCard(child: Text(report.pattern!.text, style: text.bodyMedium)),
        ],
        const SizedBox(height: HuxSpacing.lg),
        HuxHeroCard(
          icon: Icons.lightbulb_rounded,
          color: HuxColors.accentPink,
          eyebrow: 'Try next',
          title: report.tryNext,
        ),
      ],
    );
  }

  static String _fmt(int n) {
    final s = n.toString();
    if (s.length <= 3) return s;
    return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final double? progress;
  const _Stat({required this.icon, required this.color, required this.value, required this.label, this.progress});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return HuxCard(
      padding: const EdgeInsets.all(HuxSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: HuxSpacing.xs),
              Expanded(child: Text(value, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
            ],
          ),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
          if (progress != null) ...[
            const SizedBox(height: HuxSpacing.xs),
            HuxProgressBar(value: progress!, color: color, height: 5),
          ],
        ],
      ),
    );
  }
}
