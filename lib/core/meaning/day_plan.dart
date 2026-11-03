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

  /// A usual night shorter than the healthy minimum is NOT copied as the
  /// goal: the goal steps up by at most this much toward the minimum, so
  /// a 5 h sleeper is asked for 5 h 30, not an impossible 7 h 30.
  static const stepUpToward = Duration(minutes: 30);

  /// The sleep need for [usual], never below [minimum]
  /// (see [ProfileTuning] for how the profile sets [minimum]).
  static Duration needFor(Duration? usual, {Duration minimum = HuxChargeCalculator.minHealthySleep}) {
    final u = usual ?? defaultSleepNeed;
    if (u >= minimum) return u;
    final stepped = u + stepUpToward;
    return stepped < minimum ? stepped : minimum;
  }

  const DayPlanner();

  DayPlan plan({
    required HuxCharge charge,
    required PersonalBaseline baseline,
    required SleepSession? lastNight,
    required DateTime now,
    Duration? utcOffset,
    Duration minSleep = HuxChargeCalculator.minHealthySleep,
    int? usualWakeMinute,
    bool gentle = false,
  }) {
    // Effort follows the MORNING charge (what the night gave you), not
    // the drained evening value — the plan shouldn't flip at 6 PM.
    final morning = charge.morningCharge;
    final effort = morning == null ? null : effortFor(morning, gentle: gentle);
    final bedtime = _bedtime(
      baseline: baseline,
      lastNight: lastNight,
      now: now,
      lowCharge: morning != null && morning < HuxChargeCalculator.goodAt,
      utcOffset: utcOffset,
      minSleep: minSleep,
      usualWakeMinute: usualWakeMinute,
    );
    return DayPlan(effort: effort, bedtime: bedtime);
  }

  /// [gentle] = older adults (retired, "stay active", or a parent's
  /// profile): same levels, softer suggestions — no "hardest workout".
  static EffortTarget effortFor(int morningCharge, {bool gentle = false}) {
    if (morningCharge >= HuxChargeCalculator.fullAt) {
      return EffortTarget(
        level: EffortLevel.push,
        min: 7,
        max: 9,
        label: 'Push day',
        suggestion: gentle
            ? 'Good day for a longer walk or your yoga — at a pace you can still talk at.'
            : 'Good day for your hardest workout or a long brisk walk.',
      );
    }
    if (morningCharge >= HuxChargeCalculator.goodAt) {
      return EffortTarget(
        level: EffortLevel.steady,
        min: 4,
        max: 6,
        label: 'Steady day',
        suggestion: gentle
            ? 'A 20–30 minute walk at a comfortable pace, plus some stretching.'
            : 'Your usual workout, or a 30-minute brisk walk.',
      );
    }
    if (morningCharge >= HuxChargeCalculator.lowAt) {
      return EffortTarget(
        level: EffortLevel.easy,
        min: 2,
        max: 3,
        label: 'Easy day',
        suggestion: gentle
            ? 'A short, slow walk and gentle stretches are plenty today.'
            : 'Keep it light — a relaxed walk or gentle yoga.',
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
    Duration minSleep = HuxChargeCalculator.minHealthySleep,
    int? usualWakeMinute,
  }) {
    if (lastNight == null) return null;

    final usual = baseline.medianTotalSleep;
    final need = needFor(usual, minimum: minSleep);
    final steppedUp = usual != null && need > usual;
    final slept = lastNight.segments.isEmpty ? Duration.zero : lastNight.totalSleep;
    // Catch-up is for a night shorter than your USUAL; the step toward
    // 7 h is already in [need], so it isn't counted twice.
    var shortfall = (usual ?? need) - slept;
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
    // Anchor on the USUAL wake time when known, so one late Sunday
    // doesn't slide Monday's bedtime later.
    final wh = usualWakeMinute == null ? wokeLocal.hour : usualWakeMinute ~/ 60;
    final wm = usualWakeMinute == null ? wokeLocal.minute : usualWakeMinute % 60;
    // Same DateTime kind (UTC-tagged wall clock vs local) on both sides,
    // so isAfter compares wall-clock times, not mixed zones.
    var wake = nowLocal.isUtc
        ? DateTime.utc(nowLocal.year, nowLocal.month, nowLocal.day, wh, wm)
        : DateTime(nowLocal.year, nowLocal.month, nowLocal.day, wh, wm);
    if (!wake.isAfter(nowLocal)) wake = wake.add(const Duration(days: 1));

    final bedtime = _roundDown(wake.subtract(goal));

    final parts = <String>[];
    if (steppedUp) parts.add('${stepUpToward.inMinutes} min more than your usual, a step toward 7 hours');
    if (catchUp >= const Duration(minutes: 15)) {
      parts.add('includes ${catchUp.inMinutes} min to catch up on last night');
    }
    if (lowCharge) parts.add('a little extra because your charge is low');
    final reason = parts.isEmpty
        ? 'Your usual sleep, to wake at ${_clock(wake)}${usualWakeMinute == null ? '' : ' (your usual)'}.'
        : 'To wake at ${_clock(wake)} — ${parts.join(', ')}.';

    return TargetBedtime(bedtime: bedtime, sleepGoal: goal, reason: reason);
  }

  /// The usual (median) local wake time from recent main sleeps, as
  /// minutes after midnight; null with fewer than 3 nights. Works for
  /// night-shift day sleepers too: times are compared around last
  /// night's wake, so 23:30 and 00:30 count as an hour apart, not 23.
  static int? usualWakeMinute(List<SleepSession> sessions, {Duration? utcOffset}) {
    final main = PersonalBaseline.mainSleepPerDay(sessions);
    if (main.length < 3) return null;
    int minuteOf(DateTime t) {
      final w = utcOffset == null ? t.toLocal() : t.toUtc().add(utcOffset);
      return w.hour * 60 + w.minute;
    }

    final recent = main.length > 14 ? main.sublist(main.length - 14) : main;
    final pivot = minuteOf(recent.last.wakeTime);
    // Offsets from the pivot in −720…+719, so midnight doesn't split them.
    final offsets = [for (final s in recent) ((minuteOf(s.wakeTime) - pivot + 720) % 1440) - 720]..sort();
    final mid = offsets[offsets.length ~/ 2];
    return (pivot + mid + 1440) % 1440;
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
