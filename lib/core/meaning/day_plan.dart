/// HUX Day Plan
/// ------------
/// Two simple answers built on HUX Charge:
/// - TODAY'S EFFORT: how hard to go today (0–10 range + one suggestion).
/// - TARGET BEDTIME: when to sleep tonight, from your usual sleep need,
///   last night's shortfall and today's charge.
///
/// PURE DART, deterministic, no I/O. Wellness wording only.
library;

import '../ring/ring_models.dart';
import 'baseline.dart';
import 'hux_charge.dart';
import 'step_target.dart';

enum EffortLevel { push, steady, easy, rest }

class EffortTarget {
  final EffortLevel level;

  /// Suggested effort on a 0–10 scale, e.g. 4–6.
  final int min;
  final int max;

  /// Short label: "Steady day".
  final String label;

  /// One doable suggestion.
  final String suggestion;

  const EffortTarget({
    required this.level,
    required this.min,
    required this.max,
    required this.label,
    required this.suggestion,
  });

  String get range => '$min–$max';
}

class TargetBedtime {
  /// Local wall-clock time to be in bed tonight (date included).
  final DateTime bedtime;

  /// How long to aim to sleep.
  final Duration sleepGoal;

  /// One line on why, e.g. "Includes 30 min to catch up on last night."
  final String reason;

  const TargetBedtime({
    required this.bedtime,
    required this.sleepGoal,
    required this.reason,
  });
}

class DayPlan {
  /// Null when there's no HUX Charge number yet (learning / no data).
  final EffortTarget? effort;

  /// Null when we don't know the user's wake time or sleep need.
  final TargetBedtime? bedtime;

  /// Today's step goal (see step_target.dart). Null when not computed.
  final StepTarget? steps;

  const DayPlan({this.effort, this.bedtime, this.steps});

  bool get isEmpty => effort == null && bedtime == null && steps == null;

  DayPlan withSteps(StepTarget? steps) =>
      DayPlan(effort: effort, bedtime: bedtime, steps: steps);
}

class DayPlanner {
  /// Used when the baseline has no usual sleep length yet.
  static const defaultSleepNeed = Duration(minutes: 450); // 7.5 h

  /// At most this much of last night's shortfall is added tonight —
  /// catching up all at once is unrealistic.
  static const maxCatchUp = Duration(minutes: 60);

  /// Extra time in bed when today's charge is low.
  static const lowChargeExtra = Duration(minutes: 15);

  /// Bedtimes are rounded to this, so they read naturally ("10:30 PM").
  static const roundTo = 15;

  const DayPlanner();

  DayPlan plan({
    required HuxCharge charge,
    required PersonalBaseline baseline,
    required SleepSession? lastNight,
    required DateTime now,
    Duration? utcOffset,
  }) {
    // Effort follows the MORNING charge (what the night gave you), not
    // the drained evening value — the plan shouldn't flip at 6 PM.
    final morning = charge.morningCharge;
    final effort = morning == null ? null : effortFor(morning);
    final bedtime = _bedtime(
      baseline: baseline,
      lastNight: lastNight,
      now: now,
      lowCharge: morning != null && morning < HuxChargeCalculator.goodAt,
      utcOffset: utcOffset,
    );
    return DayPlan(effort: effort, bedtime: bedtime);
  }

  static EffortTarget effortFor(int morningCharge) {
    if (morningCharge >= HuxChargeCalculator.fullAt) {
      return const EffortTarget(
        level: EffortLevel.push,
        min: 7,
        max: 9,
        label: 'Push day',
        suggestion: 'Good day for your hardest workout or a long brisk walk.',
      );
    }
    if (morningCharge >= HuxChargeCalculator.goodAt) {
      return const EffortTarget(
        level: EffortLevel.steady,
        min: 4,
        max: 6,
        label: 'Steady day',
        suggestion: 'Your usual workout, or a 30-minute brisk walk.',
      );
    }
    if (morningCharge >= HuxChargeCalculator.lowAt) {
      return const EffortTarget(
        level: EffortLevel.easy,
        min: 2,
        max: 3,
        label: 'Easy day',
        suggestion: 'Keep it light — a relaxed walk or gentle yoga.',
      );
    }
    return const EffortTarget(
      level: EffortLevel.rest,
      min: 0,
      max: 2,
      label: 'Rest day',
      suggestion: 'Rest and stretch today; your body is recharging.',
    );
  }

  TargetBedtime? _bedtime({
    required PersonalBaseline baseline,
    required SleepSession? lastNight,
    required DateTime now,
    required bool lowCharge,
    Duration? utcOffset,
  }) {
    if (lastNight == null) return null;

    final need = baseline.medianTotalSleep ?? defaultSleepNeed;
    final slept = lastNight.segments.isEmpty ? Duration.zero : lastNight.totalSleep;
    var shortfall = need - slept;
    if (shortfall.isNegative) shortfall = Duration.zero;
    final catchUp = shortfall > maxCatchUp ? maxCatchUp : shortfall;

    var goal = need + catchUp;
    if (lowCharge) goal += lowChargeExtra;

    // Tomorrow's wake time = the same local time you woke today.
    // Wall-clock fields only: the device's zone, or UTC + [utcOffset]
    // (tests pin it so they pass in any timezone).
    DateTime wall(DateTime t) => utcOffset == null ? t.toLocal() : t.toUtc().add(utcOffset);
    final wokeLocal = wall(lastNight.wakeTime);
    final nowLocal = wall(now);
    // Same DateTime kind (UTC-tagged wall clock vs local) on both sides,
    // so isAfter compares wall-clock times, not mixed zones.
    var wake = nowLocal.isUtc
        ? DateTime.utc(nowLocal.year, nowLocal.month, nowLocal.day, wokeLocal.hour, wokeLocal.minute)
        : DateTime(nowLocal.year, nowLocal.month, nowLocal.day, wokeLocal.hour, wokeLocal.minute);
    if (!wake.isAfter(nowLocal)) wake = wake.add(const Duration(days: 1));

    final bedtime = _roundDown(wake.subtract(goal));

    final parts = <String>[];
    if (catchUp >= const Duration(minutes: 15)) {
      parts.add('includes ${catchUp.inMinutes} min to catch up on last night');
    }
    if (lowCharge) parts.add('a little extra because your charge is low');
    final reason = parts.isEmpty
        ? 'Your usual sleep, to wake at ${_clock(wake)}.'
        : 'To wake at ${_clock(wake)} — ${parts.join(', ')}.';

    return TargetBedtime(bedtime: bedtime, sleepGoal: goal, reason: reason);
  }

  static DateTime _roundDown(DateTime t) {
    final minutes = t.minute - (t.minute % roundTo);
    return t.isUtc
        ? DateTime.utc(t.year, t.month, t.day, t.hour, minutes)
        : DateTime(t.year, t.month, t.day, t.hour, minutes);
  }

  /// "10:30 PM" — 12-hour clock, the way most Indian users read time.
  static String clock(DateTime t) => _clock(t);

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  /// "7h 45m".
  static String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
