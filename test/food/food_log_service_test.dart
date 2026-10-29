/// Food log storage: per local day, goal, consent, wipe.
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/food/food_log_service.dart';
import 'package:hux_app/core/food/meal_text_parser.dart';
import 'package:hux_app/core/food/nutrients.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  const ist = Duration(hours: 5, minutes: 30);

  Future<SqliteHealthStore> openStore() =>
      SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);

  Meal meal(String text, DateTime at, {MealType type = MealType.lunch}) =>
      Meal(type: type, loggedAt: at, items: MealTextParser.parse(text).entries);

  test('meals save per local day, totals add up, round-trip intact', () async {
    final store = await openStore();
    final log = FoodLogService(store, utcOffset: ist);
    final lunch = DateTime.utc(2026, 7, 20, 7, 30); // 13:00 IST
    final dinner = DateTime.utc(2026, 7, 20, 15, 0); // 20:30 IST

    await log.addMeal(meal('2 roti, 1 katori dal', lunch), now: lunch);
    await log.addMeal(meal('1 katori curd', dinner, type: MealType.dinner), now: dinner);

    final meals = await log.mealsFor(dinner);
    expect(meals.length, 2);
    expect(meals.first.items.first.foodId, 'roti');
    expect(meals.last.type, MealType.dinner);
    final total = await log.totalFor(dinner);
    expect(total.proteinG, closeTo(6 + 7 + 5, 0.01));
    await store.close();
  });

  test('a meal after midnight IST belongs to the new day', () async {
    final store = await openStore();
    final log = FoodLogService(store, utcOffset: ist);
    final lateNight = DateTime.utc(2026, 7, 20, 19, 0); // 00:30 IST Jul 21
    await log.addMeal(meal('1 glass milk', lateNight), now: lateNight);
    expect(await log.mealsFor(DateTime.utc(2026, 7, 20, 10)), isEmpty);
    expect((await log.mealsFor(DateTime.utc(2026, 7, 21, 6))).length, 1);
    await store.close();
  });

  test('delete a meal', () async {
    final store = await openStore();
    final log = FoodLogService(store, utcOffset: ist);
    final t = DateTime.utc(2026, 7, 20, 7);
    await log.addMeal(meal('1 katori dal', t), now: t);
    await log.addMeal(meal('2 idli', t), now: t);
    await log.deleteMeal(t, 0, now: t);
    final meals = await log.mealsFor(t);
    expect(meals.single.items.single.foodId, 'idli');
    await store.close();
  });

  test('protein goal defaults to 50 g and can be changed (clamped)', () async {
    final store = await openStore();
    final log = FoodLogService(store);
    expect(await log.proteinGoal(), 50);
    await log.setProteinGoal(70);
    expect(await log.proteinGoal(), 70);
    await log.setProteinGoal(5);
    expect(await log.proteinGoal(), 20);
    await store.close();
  });

  test('photo consent is asked once and remembered', () async {
    final store = await openStore();
    final log = FoodLogService(store);
    expect(await log.hasPhotoConsent(), isFalse);
    await log.setPhotoConsent(true);
    expect(await log.hasPhotoConsent(), isTrue);
    await store.close();
  });

  test('delete-my-data wipes the food log', () async {
    final store = await openStore();
    final log = FoodLogService(store, utcOffset: ist);
    final t = DateTime.utc(2026, 7, 20, 7);
    await log.addMeal(meal('1 katori dal', t), now: t);
    await store.deleteAllData();
    expect(await log.mealsFor(t), isEmpty);
    await store.close();
  });

  test('protein goal from weight: 0.8 g/kg rounded to 5 g, weight remembered', () async {
    final store = await openStore();
    final log = FoodLogService(store, utcOffset: ist);
    expect(await log.bodyWeightKg(), isNull);
    expect(await log.setGoalFromWeight(68), 55); // 54.4 -> 55
    expect(await log.proteinGoal(), 55);
    expect(await log.bodyWeightKg(), 68);
    await store.close();
  });
}
