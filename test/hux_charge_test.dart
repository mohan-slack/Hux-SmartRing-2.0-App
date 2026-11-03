/// HUX Charge: morning charge vs your own baseline, then daytime drain.
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/meaning/baseline.dart';
import 'package:hux_app/core/meaning/hux_charge.dart';
import 'package:hux_app/core/ring/ring_models.dart';

void main() {
  const calc = HuxChargeCalculator();

  const baseline = PersonalBaseline(
    medianHrvMs: 50,
    medianRestingHeartRateBpm: 60,
    medianTotalSleep: Duration(minutes: 420),
    medianSkinTempCelsius: 33.6,
    daysOfData: 14,
  );

  final wake = DateTime.utc(2026, 7, 20, 1, 30); // 07:00 IST
  SleepSession night({int minutes = 420, int? hrv = 50, int? hr = 60}) {
    final bed = wake.subtract(Duration(minutes: minutes));
    return SleepSession(
      bedtime: bed,
      wakeTime: wake,
      segments: [SleepSegment(start: bed, end: wake, stage: SleepStage.light)],
      avgHrvMs: hrv,
      avgHeartRateBpm: hr,
    );
  }

  HuxCharge at(DateTime now, {SleepSession? lastNight, List<HealthSnapshot> snaps = const []}) =>
      calc.calculate(
        baseline: baseline,
        lastNight: lastNight ?? night(),
        todaySnapshots: snaps,
        now: now,
      );

  test('a usual night, right at wake-up, reads 70 and "Good to go"', () {
    final c = at(wake);
    expect(c.morningCharge, 70);
    expect(c.value, 70);
    expect(c.level, ChargeLevel.good);
    expect(c.label, 'Good to go');
    expect(c.reason, 'A normal night for you.');
  });

  test('a better-than-usual night charges higher', () {
    final c = at(wake, lastNight: night(minutes: 504, hrv: 62, hr: 55));
    expect(c.morningCharge, greaterThan(85));
    expect(c.level, ChargeLevel.full);
  });

  test('a short, hard night charges lower and says why', () {
    final c = at(wake, lastNight: night(minutes: 240, hrv: 50, hr: 60));
    expect(c.morningCharge, lessThan(55));
    expect(c.reason, 'You slept less than usual.');
  });

  test('energy drains through the day', () {
    final morning = at(wake).value!;
    final evening = at(wake.add(const Duration(hours: 12))).value!;
    expect(evening, lessThan(morning));
    expect(morning - evening, 15); // (12 h − 2 h grace) × 1.5
    expect(at(wake.add(const Duration(hours: 2))).value, morning); // grace
  });

  test('stress drains extra; walking never does', () {
    final now = wake.add(const Duration(hours: 4));
    final quiet = at(now).value!;
    final walked = at(now, snaps: [HealthSnapshot(timestamp: now, activeEnergyKcal: 600)]).value!;
    expect(walked, quiet);
    final stressed = at(now, snaps: [HealthSnapshot(timestamp: now, stressIndex: 100)]).value!;
    expect(quiet - stressed, 10);
  });

  test('a usual short sleeper is not "Good to go" (7 h floor)', () {
    const shortBase = PersonalBaseline(
      medianHrvMs: 50,
      medianRestingHeartRateBpm: 60,
      medianTotalSleep: Duration(hours: 5),
      medianSkinTempCelsius: 33.6,
      daysOfData: 14,
    );
    HuxCharge usualNight(int minutes) =>
        calc.calculate(baseline: shortBase, lastNight: night(minutes: minutes), todaySnapshots: const [], now: wake);
    final five = usualNight(300);
    expect(five.morningCharge, 45); // capped: 70 − 2 h × 25 + 25
    expect(five.level, ChargeLevel.low);
    expect(five.shortSleep, isTrue);
    expect(five.reason, contains('under the 7 hours'));
    // A usual 6 h sleeper: a small penalty only (70 − 8).
    final sixHourUsual = calc.calculate(
      baseline: const PersonalBaseline(
        medianHrvMs: 50,
        medianRestingHeartRateBpm: 60,
        medianTotalSleep: Duration(hours: 6),
        medianSkinTempCelsius: 33.6,
        daysOfData: 14,
      ),
      lastNight: night(minutes: 360),
      todaySnapshots: const [],
      now: wake,
    );
    expect(sixHourUsual.morningCharge, 62);
    expect(sixHourUsual.level, ChargeLevel.good);
    // And the 5 h sleeper who got 6 h is still capped at 70, not "full".
    expect(usualNight(360).morningCharge, 70);
    // 7 h+: no penalty.
    expect(at(wake).shortSleep, isFalse);
  });

  test('a long day after a good night reads "Winding down", not "Running low"', () {
    final late = wake.add(const Duration(hours: 15));
    final c = at(late, snaps: [HealthSnapshot(timestamp: late, stressIndex: 100)]);
    expect(c.level, ChargeLevel.low);
    expect(c.label, 'Winding down');
  });

  test('a stale wake time stops draining after a normal day', () {
    final day = at(wake.add(const Duration(hours: 17))).value!;
    final stale = at(wake.add(const Duration(hours: 40))).value!;
    expect(stale, day);
  });

  test('never drops below the floor, never above 100', () {
    final exhausted = at(wake.add(const Duration(hours: 17)), lastNight: night(minutes: 120, hrv: 10, hr: 90), snaps: [
      HealthSnapshot(timestamp: wake.add(const Duration(hours: 17)), activeEnergyKcal: 2000, stressIndex: 100),
    ]).value!;
    expect(exhausted, HuxChargeCalculator.floor);
    final great = at(wake, lastNight: night(minutes: 700, hrv: 200, hr: 30)).value!;
    expect(great, lessThanOrEqualTo(100));
    // Over 10 h is not a bonus: the sleep signal reads as usual (70).
    expect(great, 88); // (100×0.4 + 70×0.4 + 100×0.2)
  });

  test('a long night alone does not raise the charge', () {
    expect(at(wake, lastNight: night(minutes: 660)).morningCharge, 70);
  });

  test('still learning -> no number, honest label', () {
    final c = calc.calculate(
      baseline: const PersonalBaseline(
        medianHrvMs: null,
        medianRestingHeartRateBpm: null,
        medianTotalSleep: null,
        medianSkinTempCelsius: null,
        daysOfData: 1,
      ),
      lastNight: night(),
      todaySnapshots: const [],
      now: wake,
    );
    expect(c.value, isNull);
    expect(c.label, contains('Learning'));
  });

  test('no usable last night -> no number, never a guess', () {
    final c = calc.calculate(
      baseline: baseline,
      lastNight: null,
      todaySnapshots: const [],
      now: wake,
    );
    expect(c.value, isNull);
    expect(c.label, 'No sleep data last night');
  });

  test('works with only some signals (e.g. no HRV)', () {
    final c = at(wake, lastNight: night(hrv: null));
    expect(c.value, 70);
  });
}
