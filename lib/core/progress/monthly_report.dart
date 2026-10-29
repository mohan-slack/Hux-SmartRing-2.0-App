/// One month at a glance, compared with the month before, ending in ONE
/// thing to try next month.
///
/// What it looks at, and why:
/// - Days with 7,000+ steps: in a 2025 Lancet Public Health meta-analysis
///   (Ding et al.), ~7,000 steps a day was linked to 47% lower risk of
///   death than ~2,000 — a realistic target, not the 10,000 myth.
/// - Bedtime spread: in UK Biobank data (Windred et al., 2024, SLEEP),
///   going to bed at regular times predicted health better than sleep
///   length. So the report shows how much your bedtime moved.
/// - Active days, move days and guided sessions from the streak data.
library;

import '../journal/journal.dart';
import '../ring/ring_models.dart';
import '../trends/night_row.dart';
import 'streaks.dart';

class MonthStats {
  final int year;
  final int month;

  /// Days counted: the whole month, or up to today for the current month.
  final int days;
  final int activeDays;
  final int moveDays;
  final int stepGoalDays;
  final int days7k;
  final int sessionDays;
  final int mealDays;
  final int journalDays;

  /// Median of days with steps; null when no step data.
  final int? medianSteps;
  final DateTime? bestDay;
  final int? bestDaySteps;

  final int nights;
  final int? medianSleepMinutes;

  /// Typical distance (minutes) of a bedtime from your usual bedtime.
  final int? bedtimeSpreadMinutes;

  const MonthStats({
    required this.year,
    required this.month,
    required this.days,
    required this.activeDays,
    required this.moveDays,
    required this.stepGoalDays,
    required this.days7k,
    required this.sessionDays,
    required this.mealDays,
    required this.journalDays,
    required this.medianSteps,
    required this.bestDay,
    required this.bestDaySteps,
    required this.nights,
    required this.medianSleepMinutes,
    required this.bedtimeSpreadMinutes,
  });

  bool get isEmpty => activeDays == 0 && medianSteps == null && nights == 0;
}

class MonthlyReport {
  final MonthStats stats;
  final MonthStats? previous;
  final String headline;

  /// Plain comparisons with last month ("Steps: 6,200 a day, up 800").
  final List<String> changes;
  final JournalInsight? pattern;
  final String tryNext;

  /// This month's day records, for the calendar.
  final Map<DateTime, DayRecord> days;

  const MonthlyReport({
    required this.stats,
    required this.previous,
    required this.headline,
    required this.changes,
    required this.pattern,
    required this.tryNext,
    required this.days,
  });
}

class MonthlyReportBuilder {
  static const stepsTarget = 7000;
  static const regularBedtimeMinutes = 45;

  const MonthlyReportBuilder();

  /// [records]/[sleep]/[journal] may cover more than the month; only the
  /// month (and the one before, for comparison) is used. [today] is the
  /// local-day label; months after it count nothing.
  MonthlyReport build({
    required int year,
    required int month,
    required DateTime today,
    required Map<DateTime, DayRecord> records,
    required List<SleepSession> sleep,
    required Map<DateTime, Set<JournalTag>> journal,
    Duration? utcOffset,
  }) {
    final stats = statsFor(year, month, today, records, sleep, utcOffset);
    final prevMonth = DateTime.utc(year, month - 1);
    final prev = statsFor(prevMonth.year, prevMonth.month, today, records, sleep, utcOffset);
    final previous = prev.isEmpty ? null : prev;

    final monthStart = DateTime.utc(year, month);
    final monthEnd = DateTime.utc(year, month + 1);
    bool inMonth(DateTime d) => !d.isBefore(monthStart) && d.isBefore(monthEnd);
    final insights = JournalInsights.compute(
      entries: {
        for (final e in journal.entries)
          if (inMonth(e.key)) e.key: e.value,
      },
      sessions: [
        for (final s in sleep)
          if (inMonth(nightKeyFor(s.bedtime, utcOffset: utcOffset))) s,
      ],
      utcOffset: utcOffset,
    );

    return MonthlyReport(
      stats: stats,
      previous: previous,
      headline: _headline(stats),
      changes: _changes(stats, previous),
      pattern: insights.isEmpty ? null : insights.first,
      tryNext: _tryNext(stats),
      days: {
        for (final e in records.entries)
          if (inMonth(e.key)) e.key: e.value,
      },
    );
  }

  MonthStats statsFor(
    int year,
    int month,
    DateTime today,
    Map<DateTime, DayRecord> records,
    List<SleepSession> sleep,
    Duration? utcOffset,
  ) {
    final start = DateTime.utc(year, month);
    final monthEnd = DateTime.utc(year, month + 1);
    final end = today.isBefore(monthEnd) ? DateTime.utc(today.year, today.month, today.day + 1) : monthEnd;
    final days = end.isAfter(start) ? end.difference(start).inDays : 0;

    var active = 0, moved = 0, goal = 0, k7 = 0, sessions = 0, meals = 0, journals = 0;
    final steps = <int>[];
    DateTime? bestDay;
    int? bestSteps;
    for (var i = 0; i < days; i++) {
      final day = DateTime.utc(year, month, 1 + i);
      final r = records[day];
      if (r == null) continue;
      if (r.active) active++;
      if (r.moved) moved++;
      if (r.stepGoalMet) goal++;
      if (r.planSession) sessions++;
      if (r.meal) meals++;
      if (r.journal) journals++;
      final s = r.steps;
      if (s != null && s > 0) {
        steps.add(s);
        if (s >= stepsTarget) k7++;
        if (bestSteps == null || s > bestSteps) {
          bestSteps = s;
          bestDay = day;
        }
      }
    }

    // One main sleep per night (the longest), like the Trends screen.
    final nights = <DateTime, SleepSession>{};
    for (final s in sleep) {
      final key = nightKeyFor(s.bedtime, utcOffset: utcOffset);
      if (key.isBefore(start) || !key.isBefore(end)) continue;
      final cur = nights[key];
      if (cur == null || s.totalSleep > cur.totalSleep) nights[key] = s;
    }
    final sleepMins = [for (final s in nights.values) s.totalSleep.inMinutes]..sort();
    // Bedtime as minutes after 6 PM, so 11:30 PM and 12:30 AM are close.
    final bedMins = [
      for (final s in nights.values) _minutesAfter6pm(s.bedtime, utcOffset),
    ]..sort();
    int? spread;
    if (bedMins.length >= 5) {
      final mid = bedMins[bedMins.length ~/ 2];
      final dev = [for (final b in bedMins) (b - mid).abs()]..sort();
      spread = dev[dev.length ~/ 2];
    }

    return MonthStats(
      year: year,
      month: month,
      days: days,
      activeDays: active,
      moveDays: moved,
      stepGoalDays: goal,
      days7k: k7,
      sessionDays: sessions,
      mealDays: meals,
      journalDays: journals,
      medianSteps: steps.isEmpty ? null : (steps..sort())[steps.length ~/ 2],
      bestDay: bestDay,
      bestDaySteps: bestSteps,
      nights: nights.length,
      medianSleepMinutes: sleepMins.isEmpty ? null : sleepMins[sleepMins.length ~/ 2],
      bedtimeSpreadMinutes: spread,
    );
  }

  static int _minutesAfter6pm(DateTime t, Duration? utcOffset) {
    final local = utcOffset == null ? t.toLocal() : t.toUtc().add(utcOffset);
    return (local.hour * 60 + local.minute - 18 * 60) % (24 * 60);
  }

  static String _headline(MonthStats s) {
    if (s.isEmpty) return 'Nothing logged this month yet.';
    final pct = s.days == 0 ? 0 : (s.activeDays * 100 / s.days).round();
    if (pct >= 80) return 'You showed up on ${s.activeDays} of ${s.days} days. Outstanding month.';
    if (pct >= 50) return 'You showed up on ${s.activeDays} of ${s.days} days. A solid month.';
    return 'You showed up on ${s.activeDays} of ${s.days} days. Every one of them counts.';
  }

  static List<String> _changes(MonthStats s, MonthStats? p) {
    final out = <String>[];
    String diff(int now, int before, String unit) {
      final d = now - before;
      if (d == 0) return 'same as last month';
      return '${d > 0 ? 'up' : 'down'} ${_fmt(d.abs())}$unit from last month';
    }

    if (s.medianSteps != null) {
      out.add('Steps: ${_fmt(s.medianSteps!)} on a usual day'
          '${p?.medianSteps != null ? ', ${diff(s.medianSteps!, p!.medianSteps!, '')}' : ''}.');
    }
    if (s.medianSleepMinutes != null) {
      out.add('Sleep: ${hm(s.medianSleepMinutes!)} on a usual night'
          '${p?.medianSleepMinutes != null ? ', ${diff(s.medianSleepMinutes!, p!.medianSleepMinutes!, ' min')}' : ''}.');
    }
    if (s.bedtimeSpreadMinutes != null) {
      out.add(s.bedtimeSpreadMinutes! <= regularBedtimeMinutes
          ? 'Bedtime: regular — usually within ${s.bedtimeSpreadMinutes} min of your normal time.'
          : 'Bedtime: moved around — often ${s.bedtimeSpreadMinutes} min from your normal time.');
    }
    if (p != null) {
      out.add('Active days: ${s.activeDays} (last month ${p.activeDays}).');
    }
    return out;
  }

  static String _tryNext(MonthStats s) {
    if (s.isEmpty) return 'Start small: one walk, one meal log, or one journal tap.';
    final spread = s.bedtimeSpreadMinutes;
    if (spread != null && spread > regularBedtimeMinutes) {
      return 'Next month: try going to bed within the same 30 minutes most nights. '
          'Regular bedtimes matter as much as long ones.';
    }
    // Goal: 7,000+ steps on at least half the days.
    if (s.medianSteps != null && s.days7k * 2 < s.days) {
      final more = ((s.days / 2).ceil() - s.days7k).clamp(1, 31).toInt();
      return 'Next month: reach 7,000 steps on $more more day${more == 1 ? '' : 's'} — '
          'a 10-minute walk after lunch and dinner adds about 2,000.';
    }
    if (s.moveDays < s.days / 2) {
      return 'Next month: add one guided session a week — Japanese interval walking takes 30 minutes.';
    }
    return 'Next month: keep the rhythm. Try one harder session a week to keep improving.';
  }

  static String hm(int minutes) => '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';

  static String _fmt(int n) {
    final s = n.toString();
    if (s.length <= 3) return s;
    return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
  }
}
