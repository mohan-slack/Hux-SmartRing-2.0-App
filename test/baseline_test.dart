/// Tests for [PersonalBaseline]. Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/meaning/baseline.dart';
import 'package:hux_app/core/ring/ring_models.dart';

SleepSession _session({
  required DateTime bedtime,
  required Duration totalSleep,
  int? avgHrv,
  int? avgHr,
  double? avgTemp,
}) {
  final wake = bedtime.add(totalSleep);
  return SleepSession(
    bedtime: bedtime,
    wakeTime: wake,
    segments: [
      SleepSegment(start: bedtime, end: wake, stage: SleepStage.light),
    ],
    avgHeartRateBpm: avgHr,
    avgHrvMs: avgHrv,
    avgSkinTempCelsius: avgTemp,
  );
}

void main() {
  group('PersonalBaseline.fromSleepSessions', () {
    test('14 synthetic nights produce correct medians', () {
      final base = DateTime.utc(2026, 7, 1, 23);
      final sessions = List.generate(14, (i) {
        final n = i + 1; // 1..14
        return _session(
          bedtime: base.add(Duration(days: n)),
          totalSleep: Duration(minutes: 300 + n * 10), // 310..440
          avgHrv: n, // 1..14
          avgHr: 100 - n, // 99..86
          avgTemp: 36.0 + n * 0.1, // 36.1..37.4
        );
      });

      final baseline = PersonalBaseline.fromSleepSessions(sessions);

      expect(baseline.daysOfData, 14);
      expect(baseline.insufficient, isFalse);
      expect(baseline.medianHrvMs, 7.5);
      expect(baseline.medianRestingHeartRateBpm, 92.5);
      expect(baseline.medianTotalSleep, const Duration(minutes: 375));
      expect(baseline.medianSkinTempCelsius, closeTo(36.75, 0.0001));
    });

    test('fewer than 3 days is insufficient', () {
      final base = DateTime.utc(2026, 7, 1, 23);
      final sessions = List.generate(
        2,
        (i) => _session(
          bedtime: base.add(Duration(days: i)),
          totalSleep: const Duration(hours: 7),
          avgHrv: 50,
          avgHr: 60,
          avgTemp: 33.6,
        ),
      );

      final baseline = PersonalBaseline.fromSleepSessions(sessions);

      expect(baseline.daysOfData, 2);
      expect(baseline.insufficient, isTrue);
    });

    test('exactly 3 days is sufficient (boundary)', () {
      final base = DateTime.utc(2026, 7, 1, 23);
      final sessions = List.generate(
        3,
        (i) => _session(
          bedtime: base.add(Duration(days: i)),
          totalSleep: const Duration(hours: 7),
          avgHrv: 50,
          avgHr: 60,
          avgTemp: 33.6,
        ),
      );

      final baseline = PersonalBaseline.fromSleepSessions(sessions);

      expect(baseline.insufficient, isFalse);
    });

    test('no history at all is insufficient, never throws', () {
      final baseline = PersonalBaseline.fromSleepSessions(const []);

      expect(baseline.daysOfData, 0);
      expect(baseline.insufficient, isTrue);
      expect(baseline.medianHrvMs, isNull);
      expect(baseline.medianTotalSleep, isNull);
    });

    test('a null vendor field in some nights does not spoil other medians',
        () {
      final base = DateTime.utc(2026, 7, 1, 23);
      final sessions = [
        _session(
            bedtime: base,
            totalSleep: const Duration(hours: 7),
            avgHrv: null, // ring failed to compute HRV this night
            avgHr: 60,
            avgTemp: 33.6),
        _session(
            bedtime: base.add(const Duration(days: 1)),
            totalSleep: const Duration(hours: 7),
            avgHrv: 50,
            avgHr: 60,
            avgTemp: 33.6),
        _session(
            bedtime: base.add(const Duration(days: 2)),
            totalSleep: const Duration(hours: 7),
            avgHrv: 52,
            avgHr: 60,
            avgTemp: 33.6),
      ];

      final baseline = PersonalBaseline.fromSleepSessions(sessions);

      expect(baseline.daysOfData, 3);
      expect(baseline.medianHrvMs, 51); // only the two non-null nights
      expect(baseline.medianRestingHeartRateBpm, 60);
    });
  });
}
