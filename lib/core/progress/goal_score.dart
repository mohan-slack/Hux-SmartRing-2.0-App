/// Week score: what built this week, out of 100, from four parts the
/// user can act on — Sleep, Energy (recovery vs your usual), Move and
/// Food. Each part is 0–100; the week score is their average over the
/// parts that have data, so a phone-only user isn't punished for having
/// no ring. Pure: no storage, no Flutter.
library;

import 'dart:math' as math;

import '../food/nutrients.dart';
import '../meaning/baseline.dart';
import '../ring/ring_models.dart';
import 'streaks.dart';

enum ScorePart { sleep, energy, move, food }

extension ScorePartLabel on ScorePart {
  String get label => switch (this) {
        ScorePart.sleep => 'Sleep',
        ScorePart.energy => 'Energy',
        ScorePart.move => 'Move',
        ScorePart.food => 'Food',
      };

  /// How the part is worked out, in one line.
  String get how => switch (this) {
        ScorePart.sleep => '70% hours vs 7.5 h, 30% steady bedtime',
        ScorePart.energy => 'Night HRV and resting heart vs your usual',
        ScorePart.move => 'Step goal reached, or a guided session done',
        ScorePart.food => 'Days logged, and protein vs your goal',
      };
}

/// One day of one part (0–1), for the detail bars. Null = no data.
class ScoreDay {
  final DateTime day;
  final double? value;

  /// Short label under the bar, e.g. "7h 10m", "6.2k", "42 g".
  final String? caption;

  const ScoreDay(this.day, this.value, [this.caption]);
}

class PartScore {
  final ScorePart part;

  /// 0–100, or null when there's no data for this part this week.
  final int? score;
  final List<ScoreDay> days;

  /// Plain facts behind the score (2–3 short lines).
  final List<String> facts;

  const PartScore(this.part, this.score, this.days, this.facts);

  bool get hasData => score != null;
}

class WeekScore {
  final Map<ScorePart, PartScore> parts;

  /// Same score for the 7 days before, for "+6 vs last week".
  final int? lastWeek;

  const WeekScore(this.parts, {this.lastWeek});

  /// Average of the parts with data; null when none have data.
  int? get overall => _average(parts.values.map((p) => p.score));

  int? get change => overall == null || lastWeek == null ? null : overall! - lastWeek!;

  /// Points each part adds to [overall] (they sum to it).
  Map<ScorePart, double> get contributions {
    final withData = parts.values.where((p) => p.hasData).toList();
    if (withData.isEmpty) return const {};
    return {for (final p in withData) p.part: p.score! / withData.length};
  }

  static int? _average(Iterable<int?> v) {
    final k = v.whereType<int>().toList();
    if (k.isEmpty) return null;
    return (k.reduce((a, b) => a + b) / k.length).round();
  }
}

class WeekScoreCalculator {
  const WeekScoreCalculator();

  static const sleepNeedMin = 450; // 7.5 h

  /// [today] is a `DateTime.utc(y, m, d)` day label. The week is the 7
  /// days BEFORE today (today is unfinished). [sessions] should cover
  /// ~28 days so "your usual" has history; [records] and [mealsByDay] use
  /// the same day labels.
  WeekScore calculate({
    required DateTime today,
    required List<SleepSession> sessions,
    required Map<DateTime, DayRecord> records,
    required Map<DateTime, List<Meal>> mealsByDay,
    required double proteinGoalG,
  }) {
    final main = PersonalBaseline.mainSleepPerDay(sessions);
    // Night that ended on wake-day D belongs to day D.
    final byWake = <DateTime, SleepSession>{
      for (final s in main) _label(s.wakeTime.toLocal()): s,
    };
    final usualHrv = _median([for (final s in main) if (s.avgHrvMs != null) s.avgHrvMs!.toDouble()]);
    final usualRhr = _median([for (final s in main) if (s.avgHeartRateBpm != null) s.avgHeartRateBpm!.toDouble()]);

    Map<ScorePart, PartScore> week(int endOffset) {
      final days = [for (var i = endOffset + 6; i >= endOffset; i--) today.subtract(Duration(days: i))];
      return {
        ScorePart.sleep: _sleep(days, byWake),
        ScorePart.energy: _energy(days, byWake, usualHrv, usualRhr),
        ScorePart.move: _move(days, records),
        ScorePart.food: _food(days, mealsByDay, proteinGoalG),
      };
    }

    final now = week(1);
    final before = WeekScore(week(8));
    return WeekScore(now, lastWeek: before.overall);
  }

  static DateTime _label(DateTime local) => DateTime.utc(local.year, local.month, local.day);

  static double? _median(List<double> v) {
    if (v.length < 3) return null;
    final s = [...v]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  static String _hm(int m) => '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';

  static double _clamp01(num v) => v.clamp(0, 1).toDouble();

  PartScore _sleep(List<DateTime> days, Map<DateTime, SleepSession> byWake) {
    final out = <ScoreDay>[];
    final beds = <int>[];
    final mins = <int>[];
    for (final d in days) {
      final s = byWake[d];
      final m = s?.totalSleep.inMinutes;
      // Under 1 h or over 14 h is almost always bad data.
      if (s == null || m == null || m < 60 || m > 14 * 60) {
        out.add(ScoreDay(d, null));
        continue;
      }
      mins.add(m);
      final b = s.bedtime.toLocal();
      beds.add(((b.hour * 60 + b.minute) - 18 * 60 + 24 * 60) % (24 * 60)); // minutes after 6 PM
      out.add(ScoreDay(d, _clamp01(m / sleepNeedMin), _hm(m)));
    }
    if (mins.length < 3) return PartScore(ScorePart.sleep, null, out, const ['Needs 3 nights with sleep data.']);
    final dur = mins.map((m) => _clamp01(m / sleepNeedMin)).reduce((a, b) => a + b) / mins.length;
    final mean = beds.reduce((a, b) => a + b) / beds.length;
    final sd = math.sqrt(beds.map((b) => (b - mean) * (b - mean)).reduce((a, b) => a + b) / beds.length);
    final steady = _clamp01(1 - sd / 90);
    final avg = (mins.reduce((a, b) => a + b) / mins.length).round();
    return PartScore(ScorePart.sleep, (100 * (0.7 * dur + 0.3 * steady)).round(), out, [
      'Average ${_hm(avg)} a night (${mins.length} nights)',
      sd <= 30
          ? 'Bedtime steady — within ~${sd.round()} min'
          : 'Bedtime moves around by ~${sd.round()} min',
      '${mins.where((m) => m >= 420).length} of ${mins.length} nights were 7 h or more',
    ]);
  }

  PartScore _energy(List<DateTime> days, Map<DateTime, SleepSession> byWake, double? hrv0, double? rhr0) {
    final out = <ScoreDay>[];
    final vals = <double>[];
    var better = 0;
    for (final d in days) {
      final s = byWake[d];
      final parts = <double>[];
      if (s?.avgHrvMs != null && hrv0 != null && hrv0 > 0) {
        parts.add(_clamp01(0.5 + (s!.avgHrvMs! / hrv0 - 1) * 2.5));
      }
      if (s?.avgHeartRateBpm != null && rhr0 != null) {
        parts.add(_clamp01(0.5 - (s!.avgHeartRateBpm! - rhr0) / 10));
      }
      if (parts.isEmpty) {
        out.add(ScoreDay(d, null));
        continue;
      }
      final v = parts.reduce((a, b) => a + b) / parts.length;
      vals.add(v);
      if (v >= 0.5) better++;
      out.add(ScoreDay(d, v, v >= 0.6 ? 'fresh' : v >= 0.4 ? 'usual' : 'low'));
    }
    if (vals.length < 3) {
      return PartScore(ScorePart.energy, null, out, const ['Needs 3 nights of ring data and a week of history.']);
    }
    final avg = vals.reduce((a, b) => a + b) / vals.length;
    return PartScore(ScorePart.energy, (100 * avg).round(), out, [
      '$better of ${vals.length} nights at or above your usual recovery',
      if (hrv0 != null) 'Your usual night HRV: ${hrv0.round()} ms',
      if (rhr0 != null) 'Your usual resting heart: ${rhr0.round()} bpm',
    ]);
  }

  PartScore _move(List<DateTime> days, Map<DateTime, DayRecord> records) {
    final out = <ScoreDay>[];
    var known = 0, met = 0, sessions = 0;
    var total = 0.0;
    for (final d in days) {
      final r = records[d];
      if (r == null || (r.steps == null && !r.planSession)) {
        out.add(ScoreDay(d, null));
        continue;
      }
      known++;
      final goal = r.stepGoal ?? 0;
      final ratio = r.planSession ? 1.0 : (goal > 0 && r.steps != null ? _clamp01(r.steps! / goal) : 0.0);
      if (r.stepGoalMet) met++;
      if (r.planSession) sessions++;
      total += ratio;
      final st = r.steps;
      out.add(ScoreDay(d, ratio, st == null ? 'session' : st >= 1000 ? '${(st / 1000).toStringAsFixed(1)}k' : '$st'));
    }
    if (known < 3) return PartScore(ScorePart.move, null, out, const ['Needs 3 days of steps or sessions.']);
    return PartScore(ScorePart.move, (100 * total / 7).round(), out, [
      'Step goal reached on $met of 7 days',
      if (sessions > 0) '$sessions guided session${sessions == 1 ? '' : 's'} done',
      if (known < 7) '${7 - known} day${7 - known == 1 ? '' : 's'} without step data count as 0',
    ]);
  }

  PartScore _food(List<DateTime> days, Map<DateTime, List<Meal>> mealsByDay, double goal) {
    final out = <ScoreDay>[];
    var logged = 0;
    var total = 0.0;
    var protein = 0.0;
    for (final d in days) {
      final meals = mealsByDay[d] ?? const <Meal>[];
      if (meals.isEmpty) {
        out.add(ScoreDay(d, null));
        continue;
      }
      logged++;
      final p = meals.fold<double>(0, (s, m) => s + m.total.proteinG);
      protein += p;
      final v = 0.4 + 0.6 * (goal > 0 ? _clamp01(p / goal) : 0.5);
      total += v;
      out.add(ScoreDay(d, v, '${p.round()} g'));
    }
    // No meals this week = no data (not 0): a quiet logging week
    // shouldn't drag the whole score to zero.
    if (logged == 0) {
      final anyEver = mealsByDay.values.any((m) => m.isNotEmpty);
      return PartScore(ScorePart.food, null, out,
          [anyEver ? 'No meals logged this week.' : 'Log a meal to start this part.']);
    }
    return PartScore(ScorePart.food, (100 * total / 7).round(), out, [
      'Food logged on $logged of 7 days',
      if (logged > 0) 'Protein ~${(protein / logged).round()} g a day on logged days${goal > 0 ? ' (goal ${goal.round()} g)' : ''}',
    ]);
  }
}
