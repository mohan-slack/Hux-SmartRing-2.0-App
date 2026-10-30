/// Journeys: content, day logic, bedtime shift, meals, reminders.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hux_app/core/journeys/journey_content.dart';
import 'package:hux_app/core/journeys/journey_models.dart';
import 'package:hux_app/core/journeys/journey_service.dart';
import 'package:hux_app/core/nudges/nudge_planner.dart';
import 'package:hux_app/core/profile/user_profile.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';

void main() {
  sqfliteFfiInit();
  Future<SqliteHealthStore> openStore() => SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);

  group('content', () {
    test('every step points at a real move; every move has cues and safety text', () {
      for (final m in moves) {
        expect(m.cues.length, inInclusiveRange(2, 3), reason: m.id);
        expect(m.stopIf, isNotEmpty, reason: m.id);
      }
      for (final def in journeys) {
        for (var d = 1; d <= def.days; d++) {
          for (final level in FitnessLevel.values) {
            final day = journeyDay(def.id, d, level);
            expect(day.workout.warmup, isNotEmpty, reason: '${def.id} day $d warm-up first');
            for (final s in day.workout.allSteps) {
              expect(() => moveById(s.moveId), returnsNormally, reason: s.moveId);
            }
            expect(day.workout.minutes, inInclusiveRange(5, 30), reason: '${def.id} day $d');
          }
        }
      }
    });

    test('meals respect diet and budget, 2 options per slot', () {
      final plan = mealsForDay(day: 3, diet: Diet.jain, budget: Budget.low);
      for (final options in plan.values) {
        expect(options.length, lessThanOrEqualTo(2));
        for (final m in options) {
          expect(m.diets, contains(Diet.jain));
          expect(m.budget, Budget.low);
        }
      }
      final veg = mealsForDay(day: 1, diet: Diet.veg, budget: Budget.high);
      for (final options in veg.values) {
        for (final m in options) {
          expect(m.diets, contains(Diet.veg), reason: 'no meat or egg for veg: ${m.id}');
        }
      }
    });

    test('Fit in 30: weekly challenge days and a final challenge', () {
      expect(journeyDay(JourneyId.fitIn30, 7, FitnessLevel.beginner).challenge, isTrue);
      expect(journeyDay(JourneyId.fitIn30, 30, FitnessLevel.beginner).challenge, isTrue);
      expect(journeyDay(JourneyId.fitIn30, 5, FitnessLevel.beginner).challenge, isFalse);
    });
  });

  group('JourneyService', () {
    var clock = DateTime(2026, 11, 2, 9);
    JourneyService service(SqliteHealthStore store) => JourneyService(store, now: () => clock);

    test('3 ticks finish the day — only one day per calendar day', () async {
      clock = DateTime(2026, 11, 2, 9);
      final store = await openStore();
      final j = service(store);
      await j.start(const JourneySetup(id: JourneyId.fitIn30, wake: TimeOfDayHm(6, 30)));
      await j.toggle(DayItem.sleep);
      await j.toggle(DayItem.food);
      var s = await j.toggle(DayItem.move);
      expect(s!.daysDone, 1);
      expect(j.doneToday(s), isTrue);

      // Same day: ticks are ignored.
      s = await j.toggle(DayItem.sleep);
      expect(s!.ticks, isEmpty);
      expect(s.daysDone, 1);

      // Next day: day 2.
      clock = DateTime(2026, 11, 3, 9);
      s = await j.active();
      expect(s!.currentDay, 2);
      await store.close();
    });

    test('missed days never fail; rest pass once a week', () async {
      clock = DateTime(2026, 11, 2, 9);
      final store = await openStore();
      final j = service(store);
      await j.start(const JourneySetup(id: JourneyId.sleepReset21, wake: TimeOfDayHm(6, 30)));
      clock = DateTime(2026, 11, 6, 9); // 4 quiet days
      var s = await j.active();
      expect(s!.currentDay, 1);
      expect(j.quietDays(s), greaterThanOrEqualTo(2));

      expect(await j.skipToday(), isTrue);
      clock = DateTime(2026, 11, 7, 9);
      expect(await j.skipToday(), isFalse, reason: 'one pass per 7 days');
      s = await j.active();
      expect(s!.daysDone, 1);
      await store.close();
    });

    test('bedtime moves 15 min every 3 days toward the target, never past it', () async {
      final store = await openStore();
      final j = service(store);
      final s = await j.start(const JourneySetup(
        id: JourneyId.sleepReset21,
        wake: TimeOfDayHm(6, 30),
        usualBedtime: TimeOfDayHm(0, 30), // 12:30 AM, target 10:45 PM
      ));
      expect(j.bedtimeFor(s, day: 1).encode(), '0:30');
      expect(j.bedtimeFor(s, day: 4).encode(), '0:15');
      expect(j.bedtimeFor(s, day: 7).encode(), '0:0');
      // 105 min late: 15 min per 3 days reaches 11:00 PM by day 21.
      expect(j.bedtimeFor(s, day: 21).encode(), '23:0');

      // A smaller gap stops exactly at the target, never earlier.
      final s2 = await j.start(const JourneySetup(
        id: JourneyId.sleepReset21,
        wake: TimeOfDayHm(6, 30),
        usualBedtime: TimeOfDayHm(23, 30),
      ));
      expect(j.bedtimeFor(s2, day: 21).encode(), '22:45');
      await store.close();
    });

    test('reminders: max 3, none when paused', () async {
      final store = await openStore();
      final j = service(store);
      var s = await j.start(const JourneySetup(
        id: JourneyId.fitIn30,
        wake: TimeOfDayHm(6, 30),
        remindMove: true,
      ));
      expect(j.reminders(s).length, 3);
      s = (await j.setPaused(true))!;
      expect(j.reminders(s), isEmpty);
      await store.close();
    });

    test('home summary is one line; null when nothing runs', () async {
      final store = await openStore();
      final j = service(store);
      expect(await j.homeSummary(), isNull);
      await j.start(const JourneySetup(id: JourneyId.sleepReset21, wake: TimeOfDayHm(6, 30)));
      final h = await j.homeSummary();
      expect(h!.day, 1);
      expect(h.line, contains('in bed by'));
      await store.close();
    });
  });
}
