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
    expect(morning - evening, 30); // 12 h × 2.5
  });

  test('activity and stress drain extra', () {
    final now = wake.add(const Duration(hours: 4));
    final quiet = at(now).value!;
    final busy = at(now, snaps: [
      HealthSnapshot(timestamp: now, activeEnergyKcal: 400, stressIndex: 100),
    ]).value!;
    expect(quiet - busy, 30); // 400/20 + 10
  });

  test('never drops below the floor, never above 100', () {
    final exhausted = at(wake.add(const Duration(hours: 40))).value!;
    expect(exhausted, HuxChargeCalculator.floor);
    final great = at(wake, lastNight: night(minutes: 900, hrv: 200, hr: 30)).value!;
    expect(great, 100);
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
