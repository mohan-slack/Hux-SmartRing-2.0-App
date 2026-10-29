/// Day plan: today's effort + tonight's target bedtime.
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/meaning/baseline.dart';
import 'package:hux_app/core/meaning/day_plan.dart';
import 'package:hux_app/core/meaning/hux_charge.dart';
import 'package:hux_app/core/ring/ring_models.dart';

void main() {
  const planner = DayPlanner();
  const ist = Duration(hours: 5, minutes: 30);

  const baseline = PersonalBaseline(
    medianHrvMs: 50,
    medianRestingHeartRateBpm: 60,
    medianTotalSleep: Duration(minutes: 450), // 7.5 h usual
    medianSkinTempCelsius: 33.6,
    daysOfData: 14,
  );

  // Woke 07:00 IST on Jul 20 (= 01:30 UTC).
  final wake = DateTime.utc(2026, 7, 20, 1, 30);
  final noonIst = DateTime.utc(2026, 7, 20, 6, 30);

  SleepSession night(int minutes) {
    final bed = wake.subtract(Duration(minutes: minutes));
    return SleepSession(
      bedtime: bed,
      wakeTime: wake,
      segments: [SleepSegment(start: bed, end: wake, stage: SleepStage.light)],
    );
  }

  HuxCharge charge(int? morning) => HuxCharge(
        value: morning,
        morningCharge: morning,
        level: null,
        label: '',
      );

  group('effort', () {
    test('maps the morning charge to four simple levels', () {
      expect(DayPlanner.effortFor(90).level, EffortLevel.push);
      expect(DayPlanner.effortFor(75).level, EffortLevel.push);
      expect(DayPlanner.effortFor(70).level, EffortLevel.steady);
      expect(DayPlanner.effortFor(50).level, EffortLevel.steady);
      expect(DayPlanner.effortFor(40).level, EffortLevel.easy);
      expect(DayPlanner.effortFor(10).level, EffortLevel.rest);
    });

    test('no charge number -> no effort target (never a guess)', () {
      final plan = planner.plan(
        charge: charge(null),
        baseline: baseline,
        lastNight: night(450),
        now: noonIst,
        utcOffset: ist,
      );
      expect(plan.effort, isNull);
    });
  });

  group('bedtime', () {
    test('usual night -> usual sleep, to wake at the same time', () {
      final plan = planner.plan(
        charge: charge(70),
        baseline: baseline,
        lastNight: night(450),
        now: noonIst,
        utcOffset: ist,
      );
      final b = plan.bedtime!;
      expect(b.sleepGoal, const Duration(minutes: 450));
      expect(DayPlanner.clock(b.bedtime), '11:30 PM'); // 07:00 - 7h30
      expect(b.reason, contains('7:00 AM'));
    });

    test('short night adds catch-up time, capped at 60 min', () {
      final plan = planner.plan(
        charge: charge(70),
        baseline: baseline,
        lastNight: night(300), // 2.5 h short
        now: noonIst,
        utcOffset: ist,
      );
      final b = plan.bedtime!;
      expect(b.sleepGoal, const Duration(minutes: 510));
      expect(DayPlanner.clock(b.bedtime), '10:30 PM');
      expect(b.reason, contains('catch up'));
    });

    test('low charge adds a little extra', () {
      final plan = planner.plan(
        charge: charge(40),
        baseline: baseline,
        lastNight: night(450),
        now: noonIst,
        utcOffset: ist,
      );
      expect(plan.bedtime!.sleepGoal, const Duration(minutes: 465));
      expect(DayPlanner.clock(plan.bedtime!.bedtime), '11:15 PM');
    });

    test('bedtime is rounded down to a quarter hour', () {
      final plan = planner.plan(
        charge: charge(70),
        baseline: baseline,
        lastNight: night(440), // 10 min short -> goal 7h40
        now: noonIst,
        utcOffset: ist,
      );
      expect(DayPlanner.clock(plan.bedtime!.bedtime), '11:15 PM'); // 11:20 -> 11:15
    });

    test('night shift: day sleep gives a daytime bedtime', () {
      // Slept 08:30–15:30 IST; it's now 18:00 IST.
      final dayWake = DateTime.utc(2026, 7, 20, 10, 0);
      final bed = dayWake.subtract(const Duration(minutes: 420));
      final plan = planner.plan(
        charge: charge(70),
        baseline: baseline,
        lastNight: SleepSession(
          bedtime: bed,
          wakeTime: dayWake,
          segments: [SleepSegment(start: bed, end: dayWake, stage: SleepStage.light)],
        ),
        now: DateTime.utc(2026, 7, 20, 12, 30),
        utcOffset: ist,
      );
      // Wake 3:30 PM tomorrow, 7h30 + 30 min catch-up -> 7:30 AM.
      expect(DayPlanner.clock(plan.bedtime!.bedtime), '7:30 AM');
    });

    test('no last night -> no bedtime', () {
      final plan = planner.plan(
        charge: charge(70),
        baseline: baseline,
        lastNight: null,
        now: noonIst,
        utcOffset: ist,
      );
      expect(plan.bedtime, isNull);
    });
  });

  test('formatting helpers', () {
    expect(DayPlanner.duration(const Duration(minutes: 465)), '7h 45m');
    expect(DayPlanner.duration(const Duration(hours: 8)), '8h');
    expect(DayPlanner.clock(DateTime(2026, 1, 1, 0, 5)), '12:05 AM');
    expect(DayPlanner.clock(DateTime(2026, 1, 1, 12, 0)), '12:00 PM');
  });
}
