/// UI 2.0 Home shapes: sleep windows, resting HR, steps by hour, Why.
import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/home/home_insights.dart';
import 'package:hux_app/core/ring/ring_models.dart';

SleepSession _night(DateTime bed, Duration asleep, {int hr = 58, int hrv = 45, double rr = 14}) => SleepSession(
      bedtime: bed,
      wakeTime: bed.add(asleep),
      segments: [SleepSegment(start: bed, end: bed.add(asleep), stage: SleepStage.light)],
      avgHeartRateBpm: hr,
      avgHrvMs: hrv,
      avgRespiratoryRateBrpm: rr,
    );

void main() {
  final now = DateTime(2026, 10, 30, 11, 10);

  test('seven nights, oldest first, with resting HR', () {
    final sessions = [
      for (var i = 7; i >= 1; i--) _night(DateTime(2026, 10, 30 - i, 23, 0), const Duration(hours: 7)),
    ];
    final ins = HomeInsights.compute(sessions: sessions, todaySnapshots: const [], now: now);
    expect(ins.nights7, hasLength(7));
    expect(ins.nights7.last!.wake.day, 30);
    expect(ins.restingHr7.whereType<int>(), everyElement(58));
    expect(ins.hasWeek, isTrue);
  });

  test('steps per hour from cumulative readings', () {
    HealthSnapshot s(int h, int m, int steps) => HealthSnapshot(timestamp: DateTime(2026, 10, 30, h, m), steps: steps);
    final ins = HomeInsights.compute(
      sessions: const [],
      todaySnapshots: [s(7, 10, 200), s(7, 50, 600), s(9, 30, 2600), s(10, 5, 3000)],
      now: now,
    );
    // Hours 6..11: 0, 600, 0, 2000, 400, 0
    expect(ins.stepsByHour, [0, 600, 0, 2000, 400, 0]);
  });

  test('why: short sleep and low HRV read as "watch", usual RHR as neutral', () {
    final sessions = [
      for (var i = 10; i >= 2; i--) _night(DateTime(2026, 10, 30 - i, 23, 0), const Duration(hours: 7, minutes: 20)),
      _night(DateTime(2026, 10, 29, 23, 40), const Duration(hours: 6, minutes: 40), hrv: 38),
    ];
    final ins = HomeInsights.compute(sessions: sessions, todaySnapshots: const [], now: now);
    final byLabel = {for (final f in ins.why) f.label: f};
    expect(byLabel['HRV']!.tone, WhyTone.watch);
    expect(byLabel['HRV']!.value, '−16%');
    expect(byLabel['Sleep']!.tone, WhyTone.watch);
    expect(byLabel['Sleep']!.value, '−40m');
    expect(byLabel['Resting HR']!.value, 'usual');
    expect(byLabel['Resting HR']!.tone, WhyTone.neutral);
  });

  test('late nights count against the target bedtime', () {
    final sessions = [
      _night(DateTime(2026, 10, 27, 22, 40), const Duration(hours: 8)),
      _night(DateTime(2026, 10, 28, 23, 30), const Duration(hours: 7)),
      _night(DateTime(2026, 10, 29, 0, 30).add(const Duration(days: 1)), const Duration(hours: 6)),
    ];
    final ins = HomeInsights.compute(sessions: sessions, todaySnapshots: const [], now: now);
    expect(ins.lateNights(DateTime(2026, 10, 30, 22, 45)), 2);
  });
}
