/// Tests for [WeeklyStoryService]. Run with: flutter test
///
/// Each scenario is seeded via direct store writes (not the mock ring)
/// for precise control over exactly what each week looked like.
///
/// Window layout relative to `now` (2026-07-20 08:00 UTC):
///   last week: [now-14d, now-7d)  i.e. Jul 6 08:00 .. Jul 13 08:00
///   this week: [now-7d,  now)     i.e. Jul 13 08:00 .. Jul 20 08:00
/// Nights are placed at 23:00 on a given day, so "daysAgo" for a night
/// in the LAST week must be 8-14 (bedtime stays before Jul 13 08:00)
/// and for THIS week must be 1-7 (bedtime stays at/after Jul 13 08:00).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hux_app/core/meaning/weekly_story.dart';
import 'package:hux_app/core/ring/ring_models.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';

void main() {
  sqfliteFfiInit();

  Future<SqliteHealthStore> openStore() =>
      SqliteHealthStore.open(inMemoryDatabasePath,
          factory: databaseFactoryFfi);

  final now = DateTime.utc(2026, 7, 20, 8, 0);

  DateTime nightsAgoAt23(int daysAgo) {
    final d = now.subtract(Duration(days: daysAgo));
    return DateTime.utc(d.year, d.month, d.day, 23);
  }

  DateTime daysAgoAtNoon(int daysAgo) {
    final d = now.subtract(Duration(days: daysAgo));
    return DateTime.utc(d.year, d.month, d.day, 12);
  }

  SleepSession nightAt(
    DateTime bedtime, {
    required int sleepMinutes,
    int? avgHrv,
    int? avgHr,
  }) {
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

  /// [nights] sessions, one per day, counting back from [startDaysAgo]
  /// towards now (e.g. startDaysAgo: 7, nights: 7 -> daysAgo 7..1).
  List<SleepSession> weekOf({
    required int startDaysAgo,
    required int nights,
    required int sleepMinutes,
    int? avgHrv,
    int? avgHr,
  }) {
    return [
      for (var i = 0; i < nights; i++)
        nightAt(
          nightsAgoAt23(startDaysAgo - i),
          sleepMinutes: sleepMinutes,
          avgHrv: avgHrv,
          avgHr: avgHr,
        ),
    ];
  }

  /// One snapshot per day counting back from [startDaysAgo], with the
  /// first [activeDays] of them over the active-steps threshold.
  List<HealthSnapshot> activeDaysOf({
    required int startDaysAgo,
    required int totalDays,
    required int activeDays,
  }) {
    return [
      for (var i = 0; i < totalDays; i++)
        HealthSnapshot(
          timestamp: daysAgoAtNoon(startDaysAgo - i),
          steps: i < activeDays ? 8000 : 2000,
        ),
    ];
  }

  group('Improving week', () {
    test('more sleep, higher HRV, lower HR, more active days -> affirming '
        'suggestion', () async {
      final store = await openStore();

      await store.saveSleepSessions([
        ...weekOf(
            startDaysAgo: 14, nights: 7, sleepMinutes: 400, avgHrv: 45,
            avgHr: 62),
        ...weekOf(
            startDaysAgo: 7, nights: 7, sleepMinutes: 430, avgHrv: 50,
            avgHr: 58),
      ]);
      await store.saveSnapshots([
        ...activeDaysOf(startDaysAgo: 14, totalDays: 7, activeDays: 2),
        ...activeDaysOf(startDaysAgo: 7, totalDays: 7, activeDays: 4),
      ]);

      final story = await WeeklyStoryService(store).buildStory(now: now);

      expect(story.thinData, isFalse);
      expect(story.title, 'Your week, in plain words');
      expect(story.observations.length, inInclusiveRange(3, 5));
      expect(story.observations.any((o) => o.contains('more sleep')), isTrue);
      expect(
        story.observations
            .any((o) => o.contains('HRV') && o.contains('higher')),
        isTrue,
      );
      expect(
        story.observations
            .any((o) => o.contains('heart rate') && o.contains('lower')),
        isTrue,
      );
      expect(
        story.observations.any((o) => o.contains('more active day')),
        isTrue,
      );
      expect(story.suggestion, contains('keep the same'));

      await store.close();
    });
  });

  group('Worsening week', () {
    test('less sleep, lower HRV, higher HR -> points at the biggest '
        'mover', () async {
      final store = await openStore();

      await store.saveSleepSessions([
        ...weekOf(
            startDaysAgo: 14, nights: 7, sleepMinutes: 430, avgHrv: 50,
            avgHr: 58),
        ...weekOf(
            startDaysAgo: 7, nights: 7, sleepMinutes: 370, avgHrv: 40,
            avgHr: 70),
      ]);
      await store.saveSnapshots([
        ...activeDaysOf(startDaysAgo: 14, totalDays: 7, activeDays: 4),
        ...activeDaysOf(startDaysAgo: 7, totalDays: 7, activeDays: 2),
      ]);

      final story = await WeeklyStoryService(store).buildStory(now: now);

      expect(story.thinData, isFalse);
      expect(story.observations.any((o) => o.contains('less sleep')), isTrue);
      expect(
        story.observations
            .any((o) => o.contains('HRV') && o.contains('lower')),
        isTrue,
      );
      expect(
        story.observations
            .any((o) => o.contains('heart rate') && o.contains('higher')),
        isTrue,
      );
      expect(
        story.observations.any((o) => o.contains('fewer active day')),
        isTrue,
      );
      // Sleep moved the most (60 min vs 10ms HRV vs 12bpm HR) — the
      // suggestion should be sleep-focused.
      expect(story.suggestion, contains('bedtime'));

      await store.close();
    });
  });

  group('Thin-data week', () {
    test('fewer than 5 nights in one week -> honest coverage note, fewer '
        'claims', () async {
      final store = await openStore();

      await store.saveSleepSessions([
        ...weekOf(
            startDaysAgo: 14, nights: 7, sleepMinutes: 420, avgHrv: 48,
            avgHr: 60),
        // Only 2 nights logged this week.
        ...weekOf(
            startDaysAgo: 7, nights: 2, sleepMinutes: 400, avgHrv: 46,
            avgHr: 61),
      ]);

      final story = await WeeklyStoryService(store).buildStory(now: now);

      expect(story.thinData, isTrue);
      expect(story.observations, isNotEmpty);
      // Fewer claims: at most a coverage note plus one steady signal,
      // never the full HRV/HR/active-days stack a confident week gets.
      expect(story.observations.length, lessThanOrEqualTo(2));
      expect(
        story.observations.first.toLowerCase(),
        anyOf(contains('handful'), contains('not enough')),
      );
      expect(story.suggestion, contains('every night'));

      await store.close();
    });

    test('no nights at all in one week is safe and honest, never throws',
        () async {
      final store = await openStore();

      await store.saveSleepSessions([
        ...weekOf(
            startDaysAgo: 14, nights: 7, sleepMinutes: 420, avgHrv: 48,
            avgHr: 60),
        // Nothing logged this week at all.
      ]);

      final story = await WeeklyStoryService(store).buildStory(now: now);

      expect(story.thinData, isTrue);
      expect(story.observations, isNotEmpty);
      expect(story.observations.first.toLowerCase(), contains('not enough'));

      await store.close();
    });
  });
}
