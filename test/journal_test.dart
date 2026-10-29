/// Daily journal: saving tags, and honest patterns from the user's nights.
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/journal/journal.dart';
import 'package:hux_app/core/ring/ring_models.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  const ist = Duration(hours: 5, minutes: 30);

  Future<SqliteHealthStore> openStore() =>
      SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);

  /// A night starting 23:00 IST on [day] (date label), lasting [minutes].
  SleepSession nightOf(DateTime day, int minutes, {int? hrv}) {
    final bed = DateTime.utc(day.year, day.month, day.day, 17, 30); // 23:00 IST
    final wake = bed.add(Duration(minutes: minutes));
    return SleepSession(
      bedtime: bed,
      wakeTime: wake,
      segments: [SleepSegment(start: bed, end: wake, stage: SleepStage.light)],
      avgHrvMs: hrv,
    );
  }

  DateTime day(int d) => DateTime.utc(2026, 7, d);

  group('JournalService', () {
    test('tags save per local day and read back', () async {
      final store = await openStore();
      final journal = JournalService(store, utcOffset: ist);
      // 20:00 UTC on Jul 19 is 01:30 IST on Jul 20 -> belongs to Jul 20.
      final lateNight = DateTime.utc(2026, 7, 19, 20, 0);

      await journal.setTags(lateNight, {JournalTag.lateDinner, JournalTag.sweets},
          now: lateNight);

      expect(await journal.tagsFor(DateTime.utc(2026, 7, 20, 6)),
          {JournalTag.lateDinner, JournalTag.sweets});
      expect(await journal.tagsFor(DateTime.utc(2026, 7, 19, 6)), isEmpty);
      expect(await journal.loggedDays(), 1);
      await store.close();
    });

    test('clearing all tags removes the day', () async {
      final store = await openStore();
      final journal = JournalService(store, utcOffset: ist);
      final t = DateTime.utc(2026, 7, 20, 6);
      await journal.setTags(t, {JournalTag.chai3plus}, now: t);
      await journal.setTags(t, {}, now: t);
      expect(await journal.loggedDays(), 0);
      await store.close();
    });

    test('entries older than the keep window are dropped', () async {
      final store = await openStore();
      final journal = JournalService(store, utcOffset: ist);
      final old = DateTime.utc(2026, 1, 1, 6);
      final now = DateTime.utc(2026, 7, 20, 6);
      await journal.setTags(old, {JournalTag.travel}, now: old);
      await journal.setTags(now, {JournalTag.yoga}, now: now);
      expect(await journal.loggedDays(), 1);
      await store.close();
    });

    test('deleting all data wipes the journal too', () async {
      final store = await openStore();
      final journal = JournalService(store, utcOffset: ist);
      final t = DateTime.utc(2026, 7, 20, 6);
      await journal.setTags(t, {JournalTag.workout}, now: t);
      await store.deleteAllData();
      expect(await journal.loggedDays(), 0);
      await store.close();
    });
  });

  group('JournalInsights', () {
    test('late dinners -> less sleep, shown with night counts', () {
      final entries = <DateTime, Set<JournalTag>>{};
      final sessions = <SleepSession>[];
      for (var d = 1; d <= 8; d++) {
        final isLate = d.isEven;
        entries[day(d)] = isLate ? {JournalTag.lateDinner} : {JournalTag.yoga};
        sessions.add(nightOf(day(d), isLate ? 380 : 430));
      }

      final insights = JournalInsights.compute(entries: entries, sessions: sessions, utcOffset: ist);

      final lateInsight = insights.firstWhere((i) => i.tag == JournalTag.lateDinner);
      expect(lateInsight.sleepDiffMinutes, -50);
      expect(lateInsight.text, contains('dinner after 10 PM'));
      expect(lateInsight.text, contains('50 min less'));
      expect(lateInsight.text, contains('4 nights'));
    });

    test('HRV differences are reported as percentages', () {
      final entries = <DateTime, Set<JournalTag>>{};
      final sessions = <SleepSession>[];
      for (var d = 1; d <= 8; d++) {
        final drank = d <= 4;
        entries[day(d)] = drank ? {JournalTag.alcohol} : {JournalTag.walkAfterMeal};
        sessions.add(nightOf(day(d), 420, hrv: drank ? 40 : 50));
      }
      final insights = JournalInsights.compute(entries: entries, sessions: sessions, utcOffset: ist);
      final alcohol = insights.firstWhere((i) => i.tag == JournalTag.alcohol);
      expect(alcohol.sleepDiffMinutes, isNull); // same sleep length
      expect(alcohol.text, contains('20% less'));
    });

    test('too few nights on either side -> no insight (never from 1-2 days)', () {
      final entries = {
        day(1): {JournalTag.sweets},
        day(2): {JournalTag.sweets},
        day(3): {JournalTag.yoga},
        day(4): {JournalTag.yoga},
        day(5): {JournalTag.yoga},
      };
      final sessions = [
        nightOf(day(1), 300),
        nightOf(day(2), 300),
        nightOf(day(3), 480),
        nightOf(day(4), 480),
        nightOf(day(5), 480),
      ];
      final insights = JournalInsights.compute(entries: entries, sessions: sessions, utcOffset: ist);
      expect(insights.where((i) => i.tag == JournalTag.sweets), isEmpty);
    });

    test('small differences are treated as noise', () {
      final entries = <DateTime, Set<JournalTag>>{};
      final sessions = <SleepSession>[];
      for (var d = 1; d <= 8; d++) {
        entries[day(d)] = d.isEven ? {JournalTag.chai3plus} : {JournalTag.yoga};
        sessions.add(nightOf(day(d), d.isEven ? 420 : 425));
      }
      final insights = JournalInsights.compute(entries: entries, sessions: sessions, utcOffset: ist);
      expect(insights, isEmpty);
    });

    test('days without any journal entry are not counted as "other" days', () {
      final entries = <DateTime, Set<JournalTag>>{};
      final sessions = <SleepSession>[];
      for (var d = 1; d <= 3; d++) {
        entries[day(d)] = {JournalTag.travel};
        sessions.add(nightOf(day(d), 360));
      }
      // 10 un-logged nights: must NOT become the comparison group.
      for (var d = 4; d <= 13; d++) {
        sessions.add(nightOf(day(d), 480));
      }
      final insights = JournalInsights.compute(entries: entries, sessions: sessions, utcOffset: ist);
      expect(insights, isEmpty);
    });

    test('at most 3 insights, strongest first', () {
      final entries = <DateTime, Set<JournalTag>>{};
      final sessions = <SleepSession>[];
      // Odd days: four habits + short sleep; even days: none + long sleep.
      for (var d = 1; d <= 10; d++) {
        final rough = d.isOdd;
        entries[day(d)] = rough
            ? {JournalTag.lateDinner, JournalTag.sweets, JournalTag.screenInBed, JournalTag.coffeeLate}
            : {JournalTag.yoga};
        sessions.add(nightOf(day(d), rough ? 360 : 450));
      }
      final insights = JournalInsights.compute(entries: entries, sessions: sessions, utcOffset: ist);
      expect(insights.length, 3);
    });
  });
}
