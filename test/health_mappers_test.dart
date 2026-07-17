/// Tests for the pure health-store mappers. Run with: flutter test
///
/// Every `HealthDataPoint` here is hand-built (no real HealthKit/Health
/// Connect connection involved) — that's the point of keeping
/// health_mappers.dart pure.

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart' as hk;
import 'package:hux_app/core/ring/health_adapter/health_mappers.dart';
import 'package:hux_app/core/ring/ring_models.dart';

hk.HealthDataPoint point({
  required hk.HealthDataType type,
  required DateTime from,
  DateTime? to,
  num value = 0,
}) {
  return hk.HealthDataPoint(
    uuid: 'test-${type.name}-${from.microsecondsSinceEpoch}',
    value: hk.NumericHealthValue(numericValue: value),
    type: type,
    unit: hk.HealthDataUnit.UNKNOWN_UNIT,
    dateFrom: from,
    dateTo: to ?? from,
    sourcePlatform: hk.HealthPlatformType.appleHealth,
    sourceDeviceId: 'test-device',
    sourceId: 'test-source',
    sourceName: 'test',
  );
}

void main() {
  group('bucketStart', () {
    test('rounds down to the nearest 10-minute boundary', () {
      expect(bucketStart(DateTime(2026, 7, 16, 10, 7)), DateTime(2026, 7, 16, 10, 0));
      expect(bucketStart(DateTime(2026, 7, 16, 10, 19)), DateTime(2026, 7, 16, 10, 10));
      expect(bucketStart(DateTime(2026, 7, 16, 10, 59)), DateTime(2026, 7, 16, 10, 50));
    });

    test('a time already on the boundary is unchanged', () {
      expect(bucketStart(DateTime(2026, 7, 16, 10, 0)), DateTime(2026, 7, 16, 10, 0));
      expect(bucketStart(DateTime(2026, 7, 16, 10, 20)), DateTime(2026, 7, 16, 10, 20));
    });
  });

  group('mapHrSamples', () {
    test('empty input produces no snapshots', () {
      expect(mapHrSamples([]), isEmpty);
    });

    test('a single point becomes one snapshot with only heartRateBpm set', () {
      final snapshots = mapHrSamples([
        point(type: hk.HealthDataType.HEART_RATE, from: DateTime(2026, 7, 16, 8, 3), value: 62),
      ]);

      expect(snapshots, hasLength(1));
      expect(snapshots.first.timestamp, DateTime(2026, 7, 16, 8, 0));
      expect(snapshots.first.heartRateBpm, 62);
      expect(snapshots.first.hrvMs, isNull);
      expect(snapshots.first.spo2Percent, isNull);
      expect(snapshots.first.steps, isNull);
    });

    test('multiple readings in the same 10-minute bucket are averaged', () {
      final snapshots = mapHrSamples([
        point(type: hk.HealthDataType.HEART_RATE, from: DateTime(2026, 7, 16, 8, 1), value: 60),
        point(type: hk.HealthDataType.HEART_RATE, from: DateTime(2026, 7, 16, 8, 5), value: 64),
      ]);

      expect(snapshots, hasLength(1));
      expect(snapshots.first.heartRateBpm, 62); // (60+64)/2
    });

    test('readings in different buckets stay separate, sorted by time', () {
      final snapshots = mapHrSamples([
        point(type: hk.HealthDataType.HEART_RATE, from: DateTime(2026, 7, 16, 9, 5), value: 70),
        point(type: hk.HealthDataType.HEART_RATE, from: DateTime(2026, 7, 16, 8, 5), value: 60),
      ]);

      expect(snapshots, hasLength(2));
      expect(snapshots[0].timestamp, DateTime(2026, 7, 16, 8, 0));
      expect(snapshots[1].timestamp, DateTime(2026, 7, 16, 9, 0));
    });
  });

  group('mapHrvSamples', () {
    test('buckets onto hrvMs, leaving other fields null', () {
      final snapshots = mapHrvSamples([
        point(
            type: hk.HealthDataType.HEART_RATE_VARIABILITY_SDNN,
            from: DateTime(2026, 7, 16, 2, 0),
            value: 48),
      ]);

      expect(snapshots.single.hrvMs, 48);
      expect(snapshots.single.heartRateBpm, isNull);
    });
  });

  group('mapSpo2', () {
    test('a fractional 0.0-1.0 reading is normalized to a whole percent', () {
      final snapshots = mapSpo2([
        point(type: hk.HealthDataType.BLOOD_OXYGEN, from: DateTime(2026, 7, 16, 3, 0), value: 0.97),
      ]);

      expect(snapshots.single.spo2Percent, 97);
    });

    test('a reading already given as a whole percent is left alone', () {
      final snapshots = mapSpo2([
        point(type: hk.HealthDataType.BLOOD_OXYGEN, from: DateTime(2026, 7, 16, 3, 0), value: 95),
      ]);

      expect(snapshots.single.spo2Percent, 95);
    });
  });

  group('mapBodyTemp', () {
    test('averages readings in a bucket to two decimal places', () {
      final snapshots = mapBodyTemp([
        point(type: hk.HealthDataType.BODY_TEMPERATURE, from: DateTime(2026, 7, 16, 3, 1), value: 33.6),
        point(type: hk.HealthDataType.BODY_TEMPERATURE, from: DateTime(2026, 7, 16, 3, 4), value: 33.8),
      ]);

      expect(snapshots.single.skinTempCelsius, 33.7);
    });
  });

  group('mapSteps', () {
    test('accumulates cumulatively across a day\'s buckets, in order', () {
      final day = DateTime(2026, 7, 16);
      final snapshots = mapSteps([
        point(type: hk.HealthDataType.STEPS, from: day.add(const Duration(hours: 8)), value: 100),
        point(type: hk.HealthDataType.STEPS, from: day.add(const Duration(hours: 8, minutes: 30)), value: 50),
        point(type: hk.HealthDataType.STEPS, from: day.add(const Duration(hours: 9)), value: 200),
      ]);

      expect(snapshots, hasLength(3));
      expect(snapshots[0].steps, 100);
      expect(snapshots[1].steps, 150); // 100 + 50
      expect(snapshots[2].steps, 350); // 150 + 200
    });

    test('resets at each calendar-day boundary rather than carrying over',
        () {
      final day1 = DateTime(2026, 7, 16, 22);
      final day2 = DateTime(2026, 7, 17, 1);
      final snapshots = mapSteps([
        point(type: hk.HealthDataType.STEPS, from: day1, value: 500),
        point(type: hk.HealthDataType.STEPS, from: day2, value: 20),
      ]);

      expect(snapshots, hasLength(2));
      expect(snapshots[0].steps, 500);
      expect(snapshots[1].steps, 20, reason: 'day 2 must not inherit day 1\'s total');
    });

    test('multiple points in the same bucket sum before accumulating', () {
      final day = DateTime(2026, 7, 16, 8);
      final snapshots = mapSteps([
        point(type: hk.HealthDataType.STEPS, from: day, value: 30),
        point(type: hk.HealthDataType.STEPS, from: day.add(const Duration(minutes: 2)), value: 20),
      ]);

      expect(snapshots, hasLength(1));
      expect(snapshots.single.steps, 50);
    });
  });

  group('mergeSnapshots', () {
    test('combines per-metric snapshots that share a bucket', () {
      final bucket = DateTime(2026, 7, 16, 8, 0);
      final hr = [HealthSnapshot(timestamp: bucket, heartRateBpm: 60)];
      final hrv = [HealthSnapshot(timestamp: bucket, hrvMs: 50)];

      final merged = mergeSnapshots([hr, hrv]);

      expect(merged, hasLength(1));
      expect(merged.single.heartRateBpm, 60);
      expect(merged.single.hrvMs, 50);
    });

    test('buckets that only one metric touched keep just that field', () {
      final hrBucket = DateTime(2026, 7, 16, 8, 0);
      final hrvBucket = DateTime(2026, 7, 16, 9, 0);
      final hr = [HealthSnapshot(timestamp: hrBucket, heartRateBpm: 60)];
      final hrv = [HealthSnapshot(timestamp: hrvBucket, hrvMs: 50)];

      final merged = mergeSnapshots([hr, hrv]);

      expect(merged, hasLength(2));
      expect(merged[0].heartRateBpm, 60);
      expect(merged[0].hrvMs, isNull);
      expect(merged[1].hrvMs, 50);
      expect(merged[1].heartRateBpm, isNull);
    });

    test('empty input produces no snapshots', () {
      expect(mergeSnapshots([]), isEmpty);
      expect(mergeSnapshots([[], []]), isEmpty);
    });
  });

  group('mapSleepSessions — basic night', () {
    test('a single night with all four stages becomes one session', () {
      final bedtime = DateTime(2026, 7, 15, 23, 0);
      final points = [
        point(
            type: hk.HealthDataType.SLEEP_AWAKE,
            from: bedtime,
            to: bedtime.add(const Duration(minutes: 10))),
        point(
            type: hk.HealthDataType.SLEEP_LIGHT,
            from: bedtime.add(const Duration(minutes: 10)),
            to: bedtime.add(const Duration(minutes: 40))),
        point(
            type: hk.HealthDataType.SLEEP_DEEP,
            from: bedtime.add(const Duration(minutes: 40)),
            to: bedtime.add(const Duration(hours: 2))),
        point(
            type: hk.HealthDataType.SLEEP_REM,
            from: bedtime.add(const Duration(hours: 2)),
            to: bedtime.add(const Duration(hours: 3))),
      ];

      final result = mapSleepSessions(points);

      expect(result, hasLength(1));
      final mapped = result.single;
      expect(mapped.hadRealStages, isTrue);
      expect(mapped.session.bedtime, bedtime);
      expect(mapped.session.wakeTime, bedtime.add(const Duration(hours: 3)));
      expect(mapped.session.segments, hasLength(4));
      expect(mapped.session.stageTotal(SleepStage.deep),
          const Duration(hours: 1, minutes: 20));
      expect(mapped.session.stageTotal(SleepStage.rem), const Duration(hours: 1));
    });

    test('empty input produces no sessions, never throws', () {
      expect(mapSleepSessions([]), isEmpty);
    });
  });

  group('mapSleepSessions — clustering into distinct nights', () {
    test('a gap at/above the threshold splits into two sessions', () {
      final night1Start = DateTime(2026, 7, 15, 23, 0);
      final night2Start = DateTime(2026, 7, 17, 0, 0); // well over a day later
      final points = [
        point(
            type: hk.HealthDataType.SLEEP_LIGHT,
            from: night1Start,
            to: night1Start.add(const Duration(hours: 7))),
        point(
            type: hk.HealthDataType.SLEEP_LIGHT,
            from: night2Start,
            to: night2Start.add(const Duration(hours: 6))),
      ];

      final result = mapSleepSessions(points);

      expect(result, hasLength(2));
      expect(result[0].session.bedtime, night1Start);
      expect(result[1].session.bedtime, night2Start);
    });

    test('a short in-night gap (a brief awakening) stays one session', () {
      final bedtime = DateTime(2026, 7, 15, 23, 0);
      final points = [
        point(
            type: hk.HealthDataType.SLEEP_LIGHT,
            from: bedtime,
            to: bedtime.add(const Duration(hours: 3))),
        // 15-minute gap: a brief, unrecorded awakening — not a new night.
        point(
            type: hk.HealthDataType.SLEEP_DEEP,
            from: bedtime.add(const Duration(hours: 3, minutes: 15)),
            to: bedtime.add(const Duration(hours: 6))),
      ];

      final result = mapSleepSessions(points);

      expect(result, hasLength(1));
      expect(result.single.session.wakeTime, bedtime.add(const Duration(hours: 6)));
    });

    test('genuinely irrelevant sleep types (e.g. SLEEP_SESSION, a '
        'summary record, not a stage) do not fragment or otherwise '
        'affect clustering', () {
      final bedtime = DateTime(2026, 7, 15, 23, 0);
      final points = [
        point(
            type: hk.HealthDataType.SLEEP_SESSION,
            from: bedtime,
            to: bedtime.add(const Duration(hours: 8))),
        point(
            type: hk.HealthDataType.SLEEP_LIGHT,
            from: bedtime,
            to: bedtime.add(const Duration(hours: 7))),
      ];

      final result = mapSleepSessions(points);

      expect(result, hasLength(1));
      expect(result.single.session.segments, hasLength(1),
          reason: 'SLEEP_SESSION is a summary record, not a stage, and '
              'must be filtered out');
    });
  });

  group('mapSleepSessions — midnight-spanning night', () {
    test('a night crossing midnight is one session, not split by '
        'calendar date', () {
      final bedtime = DateTime(2026, 7, 15, 23, 30);
      final points = [
        point(
            type: hk.HealthDataType.SLEEP_LIGHT,
            from: bedtime,
            to: bedtime.add(const Duration(hours: 2))), // still July 15
        point(
            type: hk.HealthDataType.SLEEP_DEEP,
            from: bedtime.add(const Duration(hours: 2)),
            to: bedtime.add(const Duration(hours: 5))), // now July 16
      ];

      final result = mapSleepSessions(points);

      expect(result, hasLength(1));
      expect(result.single.session.bedtime, DateTime(2026, 7, 15, 23, 30));
      expect(result.single.session.wakeTime, DateTime(2026, 7, 16, 4, 30));
    });
  });

  group('mapSleepSessions — stage-less sources', () {
    test('a night with only SLEEP_ASLEEP maps to one light segment and '
        'flags hadRealStages false', () {
      final bedtime = DateTime(2026, 7, 15, 23, 0);
      final points = [
        point(
            type: hk.HealthDataType.SLEEP_ASLEEP,
            from: bedtime,
            to: bedtime.add(const Duration(hours: 7))),
      ];

      final result = mapSleepSessions(points);

      expect(result, hasLength(1));
      expect(result.single.hadRealStages, isFalse);
      expect(result.single.session.segments.single.stage, SleepStage.light);
      expect(result.single.session.totalSleep, const Duration(hours: 7));
    });

    test('a night with even one real stage point is NOT flagged '
        'stage-less', () {
      final bedtime = DateTime(2026, 7, 15, 23, 0);
      final points = [
        point(
            type: hk.HealthDataType.SLEEP_ASLEEP,
            from: bedtime,
            to: bedtime.add(const Duration(hours: 6))),
        point(
            type: hk.HealthDataType.SLEEP_DEEP,
            from: bedtime.add(const Duration(hours: 6)),
            to: bedtime.add(const Duration(hours: 7))),
      ];

      final result = mapSleepSessions(points);

      expect(result.single.hadRealStages, isTrue);
    });

    test('a night with only SLEEP_IN_BED (a plain manually-entered '
        'Apple Health sleep span — see README) also maps to one light '
        'segment and flags hadRealStages false', () {
      final bedtime = DateTime(2026, 7, 15, 23, 0);
      final points = [
        point(
            type: hk.HealthDataType.SLEEP_IN_BED,
            from: bedtime,
            to: bedtime.add(const Duration(hours: 7))),
      ];

      final result = mapSleepSessions(points);

      expect(result, hasLength(1));
      expect(result.single.hadRealStages, isFalse);
      expect(result.single.session.segments.single.stage, SleepStage.light);
      expect(result.single.session.totalSleep, const Duration(hours: 7));
    });

    test('never fabricates deep/REM for a stage-less night', () {
      final bedtime = DateTime(2026, 7, 15, 23, 0);
      final points = [
        point(
            type: hk.HealthDataType.SLEEP_ASLEEP,
            from: bedtime,
            to: bedtime.add(const Duration(hours: 7))),
      ];

      final result = mapSleepSessions(points);

      expect(result.single.session.stageTotal(SleepStage.deep), Duration.zero);
      expect(result.single.session.stageTotal(SleepStage.rem), Duration.zero);
    });
  });

  group('mapSleepSessions — averages from other metrics', () {
    test('only points inside [bedtime, wakeTime) contribute to averages',
        () {
      final bedtime = DateTime(2026, 7, 15, 23, 0);
      final wakeTime = bedtime.add(const Duration(hours: 7));
      final sleepPoints = [
        point(type: hk.HealthDataType.SLEEP_LIGHT, from: bedtime, to: wakeTime),
      ];
      final hrPoints = [
        point(
            type: hk.HealthDataType.HEART_RATE,
            from: bedtime.add(const Duration(hours: 1)),
            value: 58), // inside
        point(
            type: hk.HealthDataType.HEART_RATE,
            from: bedtime.subtract(const Duration(hours: 2)),
            value: 90), // before bedtime — must be excluded
        point(
            type: hk.HealthDataType.HEART_RATE,
            from: wakeTime.add(const Duration(hours: 1)),
            value: 95), // after wake — must be excluded
      ];

      final result = mapSleepSessions(sleepPoints, hrPoints: hrPoints);

      expect(result.single.session.avgHeartRateBpm, 58);
    });

    test('minSpo2Percent takes the minimum, normalized like mapSpo2', () {
      final bedtime = DateTime(2026, 7, 15, 23, 0);
      final wakeTime = bedtime.add(const Duration(hours: 7));
      final sleepPoints = [
        point(type: hk.HealthDataType.SLEEP_LIGHT, from: bedtime, to: wakeTime),
      ];
      final spo2Points = [
        point(
            type: hk.HealthDataType.BLOOD_OXYGEN,
            from: bedtime.add(const Duration(hours: 1)),
            value: 0.97),
        point(
            type: hk.HealthDataType.BLOOD_OXYGEN,
            from: bedtime.add(const Duration(hours: 2)),
            value: 0.93),
      ];

      final result = mapSleepSessions(sleepPoints, spo2Points: spo2Points);

      expect(result.single.session.minSpo2Percent, 93);
    });

    test('no matching metric points leaves the averages null, not zero', () {
      final bedtime = DateTime(2026, 7, 15, 23, 0);
      final sleepPoints = [
        point(
            type: hk.HealthDataType.SLEEP_LIGHT,
            from: bedtime,
            to: bedtime.add(const Duration(hours: 7))),
      ];

      final result = mapSleepSessions(sleepPoints);

      expect(result.single.session.avgHeartRateBpm, isNull);
      expect(result.single.session.avgHrvMs, isNull);
      expect(result.single.session.minSpo2Percent, isNull);
      expect(result.single.session.avgSkinTempCelsius, isNull);
    });
  });
}
