/// Sleep debt, coach notes, "your usual" meals.
/// Run with: flutter test test/feature_depth_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/coach/coach_context.dart';
import 'package:hux_app/core/coach/coach_notes.dart';
import 'package:hux_app/core/food/food_log_service.dart';
import 'package:hux_app/core/food/nutrients.dart';
import 'package:hux_app/core/meaning/sleep_debt.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  Future<SqliteHealthStore> open() => SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
  const need = Duration(hours: 7, minutes: 30);

  group('SleepDebt', () {
    test('adds up the week; a long night pays back half', () {
      // 7 nights of 7 h against 7 h 30 → 7 × 30 min = 3h 30m.
      final d = SleepDebt.of(List.filled(7, 420), need: need)!;
      expect(d.minutes, 210);
      expect(d.label, '3h 30m');
      expect(d.hasDebt, isTrue);
      // One 9 h 30 night (2 h over → pays back 1 h).
      expect(SleepDebt.of([...List.filled(6, 420), 570], need: need)!.minutes, 6 * 30 - 60);
    });

    test('never negative; too few or bad nights -> null', () {
      expect(SleepDebt.of(List.filled(7, 540), need: need)!.minutes, 0);
      expect(SleepDebt.of([420, null, null, 20, 1000], need: need), isNull); // only 1 plausible night
      expect(SleepDebt.of([null, 420, 420, 420], need: need)!.nights, 3);
    });
  });

  group('CoachNotes', () {
    test('add, dedupe, clean, cap at 5, remove', () async {
      final store = await open();
      final n = CoachNotes(store);
      expect(await n.add('  Knee   pain — no <b>jumping</b> '), isTrue);
      expect((await n.all()).single, 'Knee pain — no bjumping/b');
      expect(await n.add('knee pain — no bjumping/b'), isFalse); // duplicate (any case)
      expect(await n.add('   '), isFalse);
      for (var i = 0; i < 10; i++) {
        await n.add('note $i');
      }
      expect(await n.all(), hasLength(CoachNotes.maxNotes));
      await n.remove(0);
      expect(await n.all(), hasLength(CoachNotes.maxNotes - 1));
      expect((await n.add('x' * 200)), isTrue);
      expect((await n.all()).last.length, CoachNotes.maxChars);
      await store.close();
    });

    test('notes and sleep debt travel with the coach summary', () {
      const c = CoachContext(partOfDay: 'evening', sleepDebtMin: 150, notes: ['Vegetarian on Tuesdays']);
      expect(c.toJson()['notes'], ['Vegetarian on Tuesdays']);
      expect(c.toJson()['sleepDebtMin'], 150);
      expect(c.preview(), containsAll(['Sleep debt this week: 2h 30m', 'You told the coach: Vegetarian on Tuesdays']));
      expect(const CoachContext(partOfDay: 'evening').toJson().containsKey('notes'), isFalse);
    });
  });

  group('Your usuals', () {
    FoodEntry e(String id, double q, FoodUnit u, double p) => FoodEntry(
          name: id,
          foodId: id,
          quantity: q,
          unit: u,
          nutrients: Nutrients(kcal: p * 10, proteinG: p, carbsG: 10, fatG: 2),
          source: NutrientSource.database,
        );

    test('a meal logged on 2+ days becomes a usual; one-offs do not', () async {
      final store = await open();
      final log = FoodLogService(store);
      final breakfast = [e('idli', 3, FoodUnit.piece, 6), e('sambar', 1, FoodUnit.katori, 5)];
      for (final d in [1, 2, 4]) {
        await log.addMeal(Meal(type: MealType.breakfast, loggedAt: DateTime(2026, 11, d, 8), items: breakfast));
      }
      // Same items, different order = same meal.
      await log.addMeal(Meal(type: MealType.breakfast, loggedAt: DateTime(2026, 11, 5, 8), items: breakfast.reversed.toList()));
      await log.addMeal(Meal(type: MealType.dinner, loggedAt: DateTime(2026, 11, 4, 20), items: [e('biryani', 1, FoodUnit.plate, 22)]));

      final u = await log.usuals(now: DateTime(2026, 11, 6, 8));
      expect(u, hasLength(1));
      expect(u.single.timesLogged, 4);
      expect(u.single.label, '3 idli + sambar');
      expect(u.single.total.proteinG, 11);
      // Logged again at 1 PM, it counts as lunch.
      expect(u.single.again(DateTime(2026, 11, 6, 13)).type, MealType.lunch);
      await store.close();
    });
  });
}
