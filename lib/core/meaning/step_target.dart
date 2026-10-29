/// HUX Next-Step Target
/// --------------------
/// A daily step goal a LITTLE above what the user usually does, adjusted
/// by today's HUX Charge — never a fixed 10,000. Works for phone-only
/// users too (phones count steps).
///
/// PURE DART, deterministic, no I/O.
library;

import '../ring/ring_models.dart';
import '../trends/night_row.dart';
import 'day_plan.dart';

class StepTarget {
  /// Today's goal.
  final int target;

  /// Steps so far today (0 when none recorded yet).
  final int today;

  /// The user's usual day (median of recent days), or null when there
  /// isn't enough history yet and a starter goal is used.
  final int? usual;

  /// One line on why this number.
  final String reason;

  const StepTarget({
    required this.target,
    required this.today,
    required this.usual,
    required this.reason,
  });

  int get remaining => target > today ? target - today : 0;
  bool get done => today >= target;

  /// Fraction 0–1 for a progress bar.
  double get progress => target == 0 ? 1 : (today / target).clamp(0.0, 1.0);

  /// Rough walking time for the remaining steps (~100 steps/min).
  int get minutesToGo => (remaining / StepTargetCalculator.stepsPerMinute).ceil();
}

class StepTargetCalculator {
  /// Days of history looked at.
  static const historyDays = 7;

  /// Below this many days with steps, use [starterTarget].
  static const minDaysForUsual = 3;

  /// First-week goal: gentle and achievable.
  static const starterTarget = 4000;

  /// How much above (or below) usual, by today's effort level.
  static const factorByEffort = {
    EffortLevel.push: 1.15,
    EffortLevel.steady: 1.08,
    EffortLevel.easy: 0.90,
    EffortLevel.rest: 0.70,
  };

  /// No charge number yet (learning / no sleep data): a small nudge up.
  static const defaultFactor = 1.05;

  /// Never raise the goal more than this above usual in one day.
  static const maxStepUp = 1500;

  static const minTarget = 2000;
  static const maxTarget = 20000;

  /// Goals are rounded to this ("6,500", not "6,437").
  static const roundTo = 250;

  static const stepsPerMinute = 100;

  const StepTargetCalculator();

  /// [snapshots]: the last [historyDays] days PLUS today (any order).
  /// Steps are cumulative per day, so each day's total is its maximum.
  /// [effort]: today's effort from [DayPlanner], or null.
  StepTarget calculate({
    required List<HealthSnapshot> snapshots,
    required DateTime now,
    EffortLevel? effort,
    Duration? utcOffset,
  }) {
    final todayKey = localDayKey(now, utcOffset: utcOffset);
    final totals = dailyTotals(snapshots, utcOffset: utcOffset);
    final today = totals[todayKey] ?? 0;
    final usual = usualFor(totals, todayKey);

    if (usual == null) {
      return StepTarget(
        target: starterTarget,
        today: today,
        usual: null,
        reason: 'A starter goal while HUX learns your usual day.',
      );
    }

    final target = targetFor(usual, effort);

    final why = switch (effort) {
      EffortLevel.push => 'a push day — a bit more than your usual',
      EffortLevel.steady => 'a little above your usual',
      EffortLevel.easy => 'an easy day — a bit less than usual is fine',
      EffortLevel.rest => 'a rest day — keep it light',
      null => 'a little above your usual',
    };

    return StepTarget(
      target: target,
      today: today,
      usual: usual,
      reason: 'Your usual is ${formatSteps(usual)} — $why.',
    );
  }

  /// Each local day's step total. Steps are cumulative per day, so a
  /// day's total is its largest reading.
  static Map<DateTime, int> dailyTotals(List<HealthSnapshot> snapshots, {Duration? utcOffset}) {
    final totals = <DateTime, int>{};
    for (final s in snapshots) {
      final steps = s.steps;
      if (steps == null) continue;
      final key = localDayKey(s.timestamp, utcOffset: utcOffset);
      if (steps > (totals[key] ?? -1)) totals[key] = steps;
    }
    return totals;
  }

  /// The usual (median) steps of the [historyDays] days before [day],
  /// or null with fewer than [minDaysForUsual] days of steps.
  static int? usualFor(Map<DateTime, int> totals, DateTime day) {
    final past = <int>[];
    for (var i = 1; i <= historyDays; i++) {
      final v = totals[day.subtract(Duration(days: i))] ?? 0;
      if (v > 0) past.add(v);
    }
    past.sort();
    if (past.length < minDaysForUsual) return null;
    return past[past.length ~/ 2]; // median (upper middle)
  }

  /// The goal for a day whose usual is [usual]; null usual = starter goal.
  static int targetFor(int? usual, EffortLevel? effort) {
    if (usual == null) return starterTarget;
    final factor = effort == null ? defaultFactor : factorByEffort[effort]!;
    var raw = (usual * factor).round();
    if (raw > usual + maxStepUp) raw = usual + maxStepUp;
    return ((raw / roundTo).round() * roundTo).clamp(minTarget, maxTarget).toInt();
  }

  /// "6,500" — Indian grouping is the same as Western up to 99,999.
  static String formatSteps(int n) {
    final s = n.toString();
    if (s.length <= 3) return s;
    return '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
  }
}
