/// Next-step targets: a little above your usual, adjusted by effort.
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/meaning/day_plan.dart';
import 'package:hux_app/core/meaning/step_target.dart';
import 'package:hux_app/core/ring/ring_models.dart';

void main() {
  const calc = StepTargetCalculator();
  const ist = Duration(hours: 5, minutes: 30);

  // "Now" = Jul 20, 18:00 IST.
  final now = DateTime.utc(2026, 7, 20, 12, 30);

  /// Cumulative snapshots for one IST day: a morning reading and the
  /// day's final total (the max is what counts).
  List<HealthSnapshot> dayOf(int daysAgo, int total) {
    final noonIst = DateTime.utc(2026, 7, 20, 6, 30).subtract(Duration(days: daysAgo));
    return [
      HealthSnapshot(timestamp: noonIst.subtract(const Duration(hours: 3)), steps: total ~/ 3),
      HealthSnapshot(timestamp: noonIst.add(const Duration(hours: 8)), steps: total),
    ];
  }

  List<HealthSnapshot> week(List<int> totals, {int today = 0}) => [
        for (var i = 0; i < totals.length; i++) ...dayOf(i + 1, totals[i]),
        if (today > 0) HealthSnapshot(timestamp: now, steps: today),
      ];

  test('steady day: a little above the usual, rounded', () {
    final t = calc.calculate(
      snapshots: week([6000, 6000, 6000, 6000, 6000]),
      now: now,
      effort: EffortLevel.steady,
      utcOffset: ist,
    );
    expect(t.usual, 6000);
    expect(t.target, 6500); // 6000 × 1.08 = 6480 -> 6500
    expect(t.reason, contains('6,000'));
  });

  test('easy and rest days lower the goal', () {
    final snaps = week([8000, 8000, 8000, 8000]);
    expect(calc.calculate(snapshots: snaps, now: now, effort: EffortLevel.easy, utcOffset: ist).target, 7250);
    expect(calc.calculate(snapshots: snaps, now: now, effort: EffortLevel.rest, utcOffset: ist).target, 5500);
  });

  test('push day goes up, but never more than +1,500 in one day', () {
    final t = calc.calculate(
      snapshots: week([15000, 15000, 15000]),
      now: now,
      effort: EffortLevel.push,
      utcOffset: ist,
    );
    expect(t.target, 16500); // 15000 × 1.15 = 17250, capped at +1500
  });

  test('uses the median, so one huge day does not inflate the goal', () {
    final t = calc.calculate(
      snapshots: week([5000, 5200, 30000, 5100, 4900]),
      now: now,
      effort: EffortLevel.steady,
      utcOffset: ist,
    );
    expect(t.usual, 5100);
  });

  test('fewer than 3 days of history -> gentle starter goal', () {
    final t = calc.calculate(snapshots: week([9000, 9000]), now: now, utcOffset: ist);
    expect(t.target, StepTargetCalculator.starterTarget);
    expect(t.usual, isNull);
  });

  test("today's progress and minutes to go", () {
    final t = calc.calculate(
      snapshots: week([6000, 6000, 6000], today: 3500),
      now: now,
      effort: EffortLevel.steady,
      utcOffset: ist,
    );
    expect(t.today, 3500);
    expect(t.remaining, 3000);
    expect(t.minutesToGo, 30);
    expect(t.done, isFalse);
    expect(t.progress, closeTo(3500 / 6500, 0.001));
  });

  test('goal reached', () {
    final t = calc.calculate(
      snapshots: week([4000, 4000, 4000], today: 9000),
      now: now,
      effort: EffortLevel.steady,
      utcOffset: ist,
    );
    expect(t.done, isTrue);
    expect(t.remaining, 0);
    expect(t.progress, 1.0);
  });

  test('never below the minimum goal', () {
    final t = calc.calculate(
      snapshots: week([1000, 1200, 900]),
      now: now,
      effort: EffortLevel.rest,
      utcOffset: ist,
    );
    expect(t.target, StepTargetCalculator.minTarget);
  });

  test('ignores days older than a week', () {
    final snaps = [
      ...dayOf(10, 20000),
      ...dayOf(11, 20000),
      ...dayOf(12, 20000),
    ];
    final t = calc.calculate(snapshots: snaps, now: now, utcOffset: ist);
    expect(t.usual, isNull); // all too old -> starter goal
  });

  test('formatSteps', () {
    expect(StepTargetCalculator.formatSteps(950), '950');
    expect(StepTargetCalculator.formatSteps(6500), '6,500');
    expect(StepTargetCalculator.formatSteps(16500), '16,500');
  });
}
