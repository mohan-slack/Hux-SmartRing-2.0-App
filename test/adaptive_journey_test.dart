/// Adaptive journeys: low Charge → lighter or "move to tomorrow";
/// big meal earlier → lighter dinner ideas.
import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/food/dinner_advice.dart';
import 'package:hux_app/core/food/nutrients.dart';
import 'package:hux_app/core/journeys/adaptive_day.dart';
import 'package:hux_app/core/journeys/journey_content.dart';
import 'package:hux_app/core/journeys/journey_models.dart';
import 'package:hux_app/core/journeys/journey_service.dart';
import 'package:hux_app/core/nudges/nudge_planner.dart';
import 'package:hux_app/core/profile/user_profile.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  Future<SqliteHealthStore> openStore() => SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);

  group('AdaptiveDay', () {
    final w = journeyDay(JourneyId.fitIn30, 1, FitnessLevel.beginner).workout; // 2 rounds

    test('lighter: one round fewer, more rest, same moves', () {
      final l = AdaptiveDay.lighter(w);
      expect(l.rounds, w.rounds - 1);
      expect(l.main.map((s) => s.moveId), w.main.map((s) => s.moveId));
      expect(l.main.first.restSeconds, w.main.first.restSeconds + 10);
      expect(l.minutes, lessThan(w.minutes));
      expect(AdaptiveDay.lighter(l).rounds, 1, reason: 'never below 1 round');
    });

    test('suggest by Charge', () {
      expect(AdaptiveDay.suggest(planned: w, charge: 25, canMove: true)!.kind, AdaptKind.move);
      expect(AdaptiveDay.suggest(planned: w, charge: 25, canMove: false)!.kind, AdaptKind.lighter);
      expect(AdaptiveDay.suggest(planned: w, charge: 45, canMove: true)!.kind, AdaptKind.lighter);
      expect(AdaptiveDay.suggest(planned: w, charge: 70, canMove: true), isNull);
      expect(AdaptiveDay.suggest(planned: w, charge: null, canMove: true), isNull);
      final short = AdaptiveDay.suggest(planned: w, charge: 70, shortSleep: true, canMove: true)!;
      expect(short.kind, AdaptKind.lighter);
      expect(short.note, startsWith('Short night'));
      expect(AdaptiveDay.suggest(planned: w, charge: 25, canMove: true)!.note, contains(w.title));
    });

    test('nothing to lighten on a 1-round workout', () {
      expect(AdaptiveDay.suggest(planned: recoveryWorkout, charge: 40, canMove: false), isNull);
    });
  });

  group('move to tomorrow', () {
    var clock = DateTime(2026, 11, 2, 8);
    JourneyService service(SqliteHealthStore store) => JourneyService(store, now: () => clock);

    Future<void> finishDay(JourneyService j) async {
      for (final i in DayItem.values) {
        await j.toggle(i);
      }
    }

    test('today becomes recovery; tomorrow does the moved workout', () async {
      clock = DateTime(2026, 11, 2, 8);
      final j = service(await openStore());
      await j.start(const JourneySetup(id: JourneyId.fitIn30, wake: TimeOfDayHm(6, 30)));
      var s = (await j.active())!;
      final planned = j.today(s).workout.title;
      expect(j.canMoveToday(s), isTrue);

      s = (await j.moveToTomorrow())!;
      expect(j.isMovedDay(s), isTrue);
      expect(j.today(s).workout.title, 'Easy recovery');
      expect(j.today(s).focus, contains(planned));

      await finishDay(j);
      clock = clock.add(const Duration(days: 1));
      s = (await j.active())!;
      expect(s.currentDay, 2);
      expect(j.today(s).workout.title, planned);
      expect(j.canMoveToday(s), isFalse, reason: 'never twice in a row');
      expect((await j.homeSummary())!.line, startsWith(planned));
    });

    test('undo restores the plan', () async {
      clock = DateTime(2026, 11, 2, 8);
      final j = service(await openStore());
      await j.start(const JourneySetup(id: JourneyId.fitIn30, wake: TimeOfDayHm(6, 30)));
      final planned = j.today((await j.active())!).workout.title;
      await j.moveToTomorrow();
      final s = (await j.undoMove())!;
      expect(s.movedDay, isNull);
      expect(j.today(s).workout.title, planned);
    });

    test('no moving before a challenge day, on recovery days, or in Sleep Reset', () async {
      clock = DateTime(2026, 11, 2, 8);
      final j = service(await openStore());
      await j.start(const JourneySetup(id: JourneyId.fitIn30, wake: TimeOfDayHm(6, 30)));
      final base = (await j.active())!;
      expect(j.canMoveToday(base.copyWith(daysDone: 5)), isFalse, reason: 'day 6, tomorrow is a challenge');
      expect(j.canMoveToday(base.copyWith(daysDone: 3)), isFalse, reason: 'day 4 is recovery');
      expect(j.canMoveToday(base.copyWith(daysDone: 2)), isTrue, reason: 'day 3, tomorrow recovery is fine');

      await j.start(const JourneySetup(id: JourneyId.sleepReset21, wake: TimeOfDayHm(6, 30)));
      expect(j.canMoveToday((await j.active())!), isFalse);
    });

    test('moved day survives save/load', () {
      const s = JourneyState(
        setup: JourneySetup(id: JourneyId.fitIn30, wake: TimeOfDayHm(6, 30)),
        startedOn: '2026-11-02',
        movedDay: 3,
      );
      expect(JourneyState.fromJson(s.toJson()).movedDay, 3);
      expect(s.copyWith(clearMoved: true).movedDay, isNull);
    });
  });

  group('DinnerAdvice', () {
    Meal meal(MealType type, double kcal) => Meal(type: type, loggedAt: DateTime(2026, 11, 2, 13), items: [
          FoodEntry(
            name: 'x',
            foodId: null,
            quantity: 1,
            unit: FoodUnit.plate,
            nutrients: Nutrients(kcal: kcal, proteinG: 0, carbsG: 0, fatG: 0),
            source: NutrientSource.values.first,
          ),
        ]);

    test('one big meal (no target)', () {
      final a = DinnerAdvice.check([meal(MealType.lunch, 1100)])!;
      expect(a.note, startsWith('Big lunch today (≈1100 kcal)'));
      expect(a.note, contains('No need to skip'));
      expect(DinnerAdvice.check([meal(MealType.lunch, 600)]), isNull);
    });

    test('with a target: share eaten before dinner', () {
      final day = [meal(MealType.breakfast, 500), meal(MealType.lunch, 850)];
      expect(DinnerAdvice.check(day, targetKcal: 2000)!.note, contains('1,350 kcal logged before dinner'));
      expect(DinnerAdvice.check(day, targetKcal: 2500), isNull);
    });

    test('nothing once dinner is logged, or nothing logged', () {
      expect(DinnerAdvice.check([meal(MealType.lunch, 1100), meal(MealType.dinner, 400)]), isNull);
      expect(DinnerAdvice.check(const []), isNull);
    });

    test('light dinner ideas when asked', () {
      final light = mealsForDay(day: 1, diet: Diet.veg, budget: Budget.high, lightDinner: true);
      for (final m in light[MealSlot.dinner] ?? const <MealOption>[]) {
        expect(m.kcal, lessThanOrEqualTo(450));
      }
    });
  });
}
