/// Tests for the pure Trends helpers in lib/core/trends/night_row.dart.
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/meaning/baseline.dart';
import 'package:hux_app/core/ring/ring_models.dart';
import 'package:hux_app/core/trends/night_row.dart';

void main() {
  group('buildNightRows', () {
    SleepSession sessionOn(DateTime bedtime,
        {int sleepMinutes = 420, int? avgHrv, int? avgHr}) {
      final wake = bedtime.add(Duration(minutes: sleepMinutes));
      return SleepSession(
        bedtime: bedtime,
        wakeTime: wake,
        segments: [
          SleepSegment(start: bedtime, end: wake, stage: SleepStage.light),
        ],
        avgHrvMs: avgHrv,
        avgHeartRateBpm: avgHr,
      );
    }

    test('produces one row per calendar day, including missing nights', () {
      final from = DateTime.utc(2026, 7, 1);
      final to = DateTime.utc(2026, 7, 6); // 5 days: Jul 1-5

      final sessions = [
        sessionOn(DateTime.utc(2026, 7, 1, 23), avgHrv: 50, avgHr: 60),
        // Jul 2 and 3: no session synced — must render as gaps.
        sessionOn(DateTime.utc(2026, 7, 4, 23), avgHrv: 52, avgHr: 58),
      ];

      final rows = buildNightRows(from: from, to: to, sessions: sessions);

      expect(rows.length, 5);
      expect(rows[0].night, DateTime.utc(2026, 7, 1));
      expect(rows[0].sleepDuration, const Duration(minutes: 420));
      expect(rows[0].avgHrvMs, 50);

      expect(rows[1].sleepDuration, isNull);
      expect(rows[1].avgHrvMs, isNull);
      expect(rows[2].sleepDuration, isNull);

      expect(rows[3].night, DateTime.utc(2026, 7, 4));
      expect(rows[3].avgHeartRateBpm, 58);

      expect(rows[4].sleepDuration, isNull,
          reason: 'Jul 5 has no session either');
    });

    test('a session with a null vendor field leaves just that field null',
        () {
      final from = DateTime.utc(2026, 7, 1);
      final to = DateTime.utc(2026, 7, 2);
      final rows = buildNightRows(
        from: from,
        to: to,
        sessions: [
          sessionOn(DateTime.utc(2026, 7, 1, 23), avgHrv: null, avgHr: 60),
        ],
      );

      expect(rows.single.sleepDuration, isNotNull);
      expect(rows.single.avgHrvMs, isNull);
      expect(rows.single.avgHeartRateBpm, 60);
    });

    test('an empty range produces an empty list, never throws', () {
      final rows = buildNightRows(
        from: DateTime.utc(2026, 7, 1),
        to: DateTime.utc(2026, 7, 1),
        sessions: const [],
      );
      expect(rows, isEmpty);
    });
  });

  group('SleepTargetBand.fromBaseline', () {
    test('is the baseline median ±10%', () {
      const baseline = PersonalBaseline(
        medianHrvMs: 50,
        medianRestingHeartRateBpm: 60,
        medianTotalSleep: Duration(minutes: 420),
        medianSkinTempCelsius: 33.6,
        daysOfData: 14,
      );

      final band = SleepTargetBand.fromBaseline(baseline);

      expect(band, isNotNull);
      expect(band!.low, const Duration(minutes: 378)); // 420 * 0.9
      expect(band.high, const Duration(minutes: 462)); // 420 * 1.1
    });

    test('is null when the baseline has no median sleep yet', () {
      const baseline = PersonalBaseline(
        medianHrvMs: null,
        medianRestingHeartRateBpm: null,
        medianTotalSleep: null,
        medianSkinTempCelsius: null,
        daysOfData: 0,
      );

      expect(SleepTargetBand.fromBaseline(baseline), isNull);
    });
  });

  group('contiguousRuns', () {
    test('splits a series into runs separated by gaps', () {
      final values = [1.0, 2.0, null, null, 5.0, 6.0, 7.0, null, 9.0];
      final runs = contiguousRuns(values);

      expect(runs.length, 3);
      expect(runs[0].map((e) => e.key), [0, 1]);
      expect(runs[0].map((e) => e.value), [1.0, 2.0]);
      expect(runs[1].map((e) => e.key), [4, 5, 6]);
      expect(runs[2].map((e) => e.key), [8]);
    });

    test('all-null input produces no runs at all', () {
      expect(contiguousRuns([null, null, null]), isEmpty);
    });

    test('all-present input produces a single run', () {
      final runs = contiguousRuns([1.0, 2.0, 3.0]);
      expect(runs.length, 1);
      expect(runs.single.length, 3);
    });

    test('an empty series produces no runs, never throws', () {
      expect(contiguousRuns(const []), isEmpty);
    });
  });
}
