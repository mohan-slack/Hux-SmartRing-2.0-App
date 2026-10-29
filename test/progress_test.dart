/// Streaks (rest passes, move weeks), monthly report, and the service
/// that builds day records from steps + logged actions.
/// Run with: flutter test

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/journal/journal.dart';
import 'package:hux_app/core/plans/plan_progress.dart';
import 'package:hux_app/core/progress/activity_log.dart';
import 'package:hux_app/core/progress/monthly_report.dart';
import 'package:hux_app/core/progress/progress_service.dart';
import 'package:hux_app/core/progress/streaks.dart';
import 'package:hux_app/core/ring/ring_models.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const ist = Duration(hours: 5, minutes: 30);
DateTime oct(int d) => DateTime.utc(2026, 10, d);

Map<DateTime, DayRecord> activeOn(Iterable<int> days, {bool move = false}) => {
      for (final d in days) oct(d): DayRecord(day: oct(d), journal: !move, planSession: move),
    };

/// A night starting at [hour]:[minute] IST on October [d] (hour may be
/// 24+ for after midnight), 7 hours long.
SleepSession night(int d, int hour, [int minute = 0]) {
  final bed = DateTime.utc(2026, 10, d, hour, minute).subtract(ist);
  final wake = bed.add(const Duration(hours: 7));
  return SleepSession(
    bedtime: bed,
    wakeTime: wake,
    segments: [SleepSegment(start: bed, end: wake, stage: SleepStage.light)],
  );
}

void main() {
  sqfliteFfiInit();
  const calc = StreakCalculator();

  group('StreakCalculator — daily streak', () {
    test('consecutive days up to today', () {
      final s = calc.calculate(activeOn([1, 2, 3, 4, 5]), oct(5));
      expect(s.current, 5);
      expect(s.best, 5);
      expect(s.todayDone, isTrue);
      expect(s.restPassesUsed, 0);
      expect(s.nextMilestone, 7);
    });

    test('today not done yet does not break the streak', () {
      final s = calc.calculate(activeOn([1, 2, 3, 4]), oct(5));
      expect(s.current, 4);
      expect(s.todayDone, isFalse);
      expect(s.message, contains('keeps it going'));
    });

    test('one missed day is covered by a rest pass', () {
      final s = calc.calculate(activeOn([1, 2, 3, 5, 6]), oct(6));
      expect(s.current, 6);
      expect(s.restPassesUsed, 1);
      expect(s.restPassReady, isFalse); // used 2 days ago
    });

    test('two misses in a row end the streak; best is kept', () {
      final s = calc.calculate(activeOn([1, 2, 3, 6]), oct(6));
      expect(s.current, 1);
      expect(s.best, 3);
    });

    test('only one rest pass per 7 days', () {
      final s = calc.calculate(activeOn([1, 2, 4, 5, 7]), oct(7));
      expect(s.current, 4); // 7, pass on 6, 5, 4 — the miss on 3 is too soon
      expect(s.restPassesUsed, 1);
    });

    test('missed yesterday, today still open: streak alive via a pass', () {
      final s = calc.calculate(activeOn([1, 2, 3]), oct(5));
      expect(s.current, 4);
      expect(s.restPassReady, isFalse);
      expect(s.message, contains('rest pass is used'));
    });

    test('a pass is ready again a week later', () {
      final s = calc.calculate(activeOn([1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12]), oct(12));
      expect(s.current, 12);
      expect(s.restPassReady, isTrue);
    });

    test('friendly messages: first time, and welcome back with best', () {
      expect(calc.calculate({}, oct(7)).message, contains('start your streak'));
      final back = calc.calculate(activeOn([1, 2, 3, 4]), oct(10));
      expect(back.current, 0);
      expect(back.message, contains('Welcome back'));
      expect(back.message, contains('your best is 4 days'));
    });

    test('a step goal reached counts; below goal alone does not', () {
      final recs = {
        oct(4): DayRecord(day: oct(4), steps: 5000, stepGoal: 4000),
        oct(5): DayRecord(day: oct(5), steps: 3000, stepGoal: 4000),
      };
      final s = calc.calculate(recs, oct(5));
      expect(recs[oct(4)]!.moved, isTrue);
      expect(recs[oct(5)]!.active, isFalse);
      expect(s.current, 1);
    });
  });

  group('StreakCalculator — move weeks', () {
    test('weeks with 3+ move days in a row; this week in progress never breaks', () {
      final recs = activeOn([5, 7, 9, 12, 13, 14, 19], move: true)
        ..addAll({
          DateTime.utc(2026, 9, 28): DayRecord(day: DateTime.utc(2026, 9, 28), planSession: true),
          DateTime.utc(2026, 9, 30): DayRecord(day: DateTime.utc(2026, 9, 30), planSession: true),
        });
      final s = calc.calculate(recs, oct(21)); // Wednesday
      expect(s.moveDaysThisWeek, 1);
      expect(s.moveWeeks, 2); // weeks of 12 Oct and 5 Oct; 28 Sep had only 2
    });

    test('logging a meal is active but not a move day', () {
      final recs = {oct(19): DayRecord(day: oct(19), meal: true)};
      final s = calc.calculate(recs, oct(19));
      expect(s.current, 1);
      expect(s.moveDaysThisWeek, 0);
    });
  });

  group('MonthlyReportBuilder', () {
    const builder = MonthlyReportBuilder();

    Map<DateTime, DayRecord> steps(int year, int month, int days, int Function(int d) f) => {
          for (var d = 1; d <= days; d++)
            DateTime.utc(year, month, d):
                DayRecord(day: DateTime.utc(year, month, d), steps: f(d), stepGoal: 6000),
        };

    test('counts only up to today in the current month', () {
      final recs = steps(2026, 10, 31, (d) => d.isEven ? 8000 : 4000);
      final s = builder.statsFor(2026, 10, oct(10), recs, const [], ist);
      expect(s.days, 10);
      expect(s.days7k, 5);
      expect(s.stepGoalDays, 5);
      expect(s.activeDays, 5);
      expect(s.medianSteps, 8000); // upper middle of 5×4000, 5×8000
      expect(s.bestDaySteps, 8000);
    });

    test('compares with last month and spots irregular bedtimes', () {
      final recs = {
        ...steps(2026, 9, 30, (_) => 5000),
        ...steps(2026, 10, 20, (_) => 6000),
      };
      final sleep = [
        for (var d = 1; d <= 10; d++) night(d, d.isEven ? 22 : 25), // 10 PM / 1 AM
      ];
      final r = builder.build(
        year: 2026,
        month: 10,
        today: oct(20),
        records: recs,
        sleep: sleep,
        journal: const {},
        utcOffset: ist,
      );
      expect(r.previous, isNotNull);
      expect(r.changes.first, contains('6,000'));
      expect(r.changes.first, contains('up 1,000'));
      expect(r.stats.nights, 10);
      expect(r.stats.medianSleepMinutes, 420);
      expect(r.stats.bedtimeSpreadMinutes, 180);
      expect(r.tryNext, contains('same 30 minutes'));
      expect(r.days.length, 20);
    });

    test('regular sleep, few 7k days -> step suggestion', () {
      final recs = steps(2026, 10, 10, (d) => d == 1 ? 9000 : 5000);
      final sleep = [for (var d = 1; d <= 6; d++) night(d, 23, d.isEven ? 0 : 15)];
      final r = builder.build(
        year: 2026, month: 10, today: oct(10), records: recs, sleep: sleep, journal: const {}, utcOffset: ist);
      expect(r.stats.bedtimeSpreadMinutes, lessThanOrEqualTo(45));
      expect(r.changes.any((c) => c.contains('regular')), isTrue);
      expect(r.tryNext, contains('7,000 steps on 4 more days'));
    });

    test('empty month', () {
      final r = builder.build(
          year: 2026, month: 10, today: oct(10), records: const {}, sleep: const [], journal: const {});
      expect(r.stats.isEmpty, isTrue);
      expect(r.previous, isNull);
      expect(r.headline, contains('Nothing logged'));
    });
  });

  group('ActivityLog + ProgressService', () {
    Future<SqliteHealthStore> openStore() =>
        SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);

    test('mark / unmark a day', () async {
      final store = await openStore();
      final log = ActivityLog(store, utcOffset: ist);
      await log.markDay(oct(3), ActivityKind.meal, now: oct(3));
      await log.markDay(oct(3), ActivityKind.journal, now: oct(3));
      await log.markDay(oct(3), ActivityKind.meal, done: false, now: oct(3));
      expect((await log.loadAll())[oct(3)], {ActivityKind.journal});
      await store.close();
    });

    test('steps, plan sessions, journal and old journal data become records and a streak', () async {
      final store = await openStore();
      final now = DateTime.utc(2026, 10, 15, 6, 30); // 12:00 IST, 15 Oct
      // 6,000 steps a day on 5–14 Oct (8 PM IST), 8,000 so far today.
      await store.saveSnapshots([
        for (var d = 5; d <= 14; d++) HealthSnapshot(timestamp: DateTime.utc(2026, 10, d, 14, 30), steps: 6000),
        HealthSnapshot(timestamp: DateTime.utc(2026, 10, 15, 6), steps: 8000),
      ]);
      await PlanProgressService(store, utcOffset: ist)
          .markDone('first_steps', 0, at: DateTime.utc(2026, 10, 12, 3));
      await JournalService(store, utcOffset: ist).setTags(now, {JournalTag.chai3plus}, now: now);
      // Journal saved before the activity log existed (backfilled).
      final raw = jsonDecode((await store.readSetting('journal_v1'))!) as Map<String, Object?>;
      raw['2026-10-13'] = ['sweets'];
      await store.writeSetting('journal_v1', jsonEncode(raw));

      final svc = ProgressService(store, utcOffset: ist, now: () => now);
      final recs = await svc.records(oct(1));
      expect(recs[oct(5)]!.stepGoal, 4000); // starter goal, little history
      expect(recs[oct(5)]!.moved, isTrue);
      expect(recs[oct(9)]!.stepGoal, 6250); // usual 6,000 × 1.05, rounded
      expect(recs[oct(9)]!.active, isFalse);
      expect(recs[oct(12)]!.planSession, isTrue);
      expect(recs[oct(13)]!.journal, isTrue);
      expect(recs[oct(15)]!.stepGoalMet, isTrue);

      final streak = await svc.streaks();
      expect(streak.current, 4); // 15, rest pass on 14, 13, 12
      expect(streak.best, 4);
      expect(streak.todayDone, isTrue);

      final report = await svc.monthly(2026, 10);
      expect(report.stats.days, 15);
      expect(report.stats.activeDays, 6); // 5, 6, 7, 12, 13, 15
      expect(report.stats.sessionDays, 1);
      expect(report.stats.days7k, 1);
      await store.close();
    });

    test('resetting a plan keeps its session days in the streak', () async {
      final store = await openStore();
      final plans = PlanProgressService(store, utcOffset: ist);
      await plans.markDone('first_steps', 0, at: DateTime.utc(2026, 10, 15, 3));
      await plans.reset('first_steps');
      final svc = ProgressService(store, utcOffset: ist, now: () => DateTime.utc(2026, 10, 15, 6));
      expect((await svc.streaks()).current, 1);
      await store.close();
    });
  });
}
