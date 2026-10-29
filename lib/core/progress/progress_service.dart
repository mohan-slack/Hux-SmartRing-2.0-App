/// Builds day records (steps + logged actions) from what is already on
/// the phone, and turns them into streaks and monthly reports.
library;

import '../food/food_log_service.dart';
import '../journal/journal.dart';
import '../meaning/step_target.dart';
import '../storage/health_store.dart';
import '../trends/night_row.dart';
import 'activity_log.dart';
import 'monthly_report.dart';
import 'streaks.dart';

class ProgressService {
  /// How far back streaks look.
  static const historyDays = ActivityLog.keepDays;

  final HealthStore _store;
  final Duration? _utcOffset;
  final DateTime Function() _now;

  ProgressService(this._store, {Duration? utcOffset, DateTime Function()? now})
      : _utcOffset = utcOffset,
        _now = now ?? DateTime.now;

  DateTime today() => localDayKey(_now(), utcOffset: _utcOffset);

  /// One record per local day from [from] (a day label) to today.
  Future<Map<DateTime, DayRecord>> records(DateTime from) async {
    final log = ActivityLog(_store, utcOffset: _utcOffset);
    await _backfill(log);
    final kinds = await log.loadAll();

    final now = _now();
    final todayKey = today();
    // A wide window: 7 days of history before [from] for step goals,
    // plus a day either side so no timezone ever cuts a day short.
    final snapshots = await _store.snapshotsBetween(
      from.subtract(const Duration(days: StepTargetCalculator.historyDays + 1)),
      now.toUtc().add(const Duration(days: 1)),
    );
    final totals = StepTargetCalculator.dailyTotals(snapshots, utcOffset: _utcOffset);

    final out = <DateTime, DayRecord>{};
    for (var d = from; !d.isAfter(todayKey); d = DateTime.utc(d.year, d.month, d.day + 1)) {
      final k = kinds[d] ?? const <ActivityKind>{};
      final steps = totals[d];
      if (k.isEmpty && steps == null) continue;
      out[d] = DayRecord(
        day: d,
        steps: steps,
        // Past goals are re-worked from the week before, without that
        // day's effort level (not stored) — close to what Today showed.
        stepGoal: StepTargetCalculator.targetFor(StepTargetCalculator.usualFor(totals, d), null),
        planSession: k.contains(ActivityKind.planSession),
        meal: k.contains(ActivityKind.meal),
        journal: k.contains(ActivityKind.journal),
      );
    }
    return out;
  }

  Future<StreakSummary> streaks() async {
    final t = today();
    final recs = await records(t.subtract(const Duration(days: historyDays)));
    return const StreakCalculator().calculate(recs, t);
  }

  Future<MonthlyReport> monthly(int year, int month) async {
    final from = DateTime.utc(year, month - 1); // the month before, for comparison
    final recs = await records(from);
    final sleep = await _store.sleepSessionsBetween(
      from.subtract(const Duration(days: 1)),
      _now().toUtc().add(const Duration(days: 1)),
    );
    final journal = await JournalService(_store, utcOffset: _utcOffset).loadAll();
    return const MonthlyReportBuilder().build(
      year: year,
      month: month,
      today: today(),
      records: recs,
      sleep: sleep,
      journal: journal,
      utcOffset: _utcOffset,
    );
  }

  /// Journal and meal days saved before the activity log existed.
  Future<void> _backfill(ActivityLog log) async {
    final journal = await JournalService(_store, utcOffset: _utcOffset).loadAll();
    final meals = await FoodLogService(_store, utcOffset: _utcOffset).daysWithMeals();
    final found = <DateTime, Set<ActivityKind>>{};
    for (final d in journal.keys) {
      (found[d] ??= {}).add(ActivityKind.journal);
    }
    for (final d in meals) {
      (found[d] ??= {}).add(ActivityKind.meal);
    }
    if (found.isNotEmpty) await log.backfill(found, now: _now());
  }
}
