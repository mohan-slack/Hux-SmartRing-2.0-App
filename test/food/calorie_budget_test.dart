/// Calorie target (Mifflin-St Jeor + goal) and "a plate that fits".
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/food/calorie_budget.dart';
import 'package:hux_app/core/food/calorie_budget_service.dart';
import 'package:hux_app/core/profile/profile_service.dart';
import 'package:hux_app/core/profile/user_profile.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  const woman = BudgetInputs(sex: BodySex.female, age: 30, heightCm: 160, weightKg: 60, activity: ActivityLevel.light);
  const man = BudgetInputs(sex: BodySex.male, age: 30, heightCm: 175, weightKg: 80, activity: ActivityLevel.moderate);

  group('target', () {
    test('BMR follows Mifflin-St Jeor', () {
      expect(CalorieBudget.bmr(woman), closeTo(1289, 0.01));
      expect(CalorieBudget.bmr(man), closeTo(1748.75, 0.01));
    });

    test('maintenance when no weight goal, rounded to 50', () {
      final t = CalorieBudget.target(woman)!;
      expect(t.kcal, 1750);
      expect(t.maintenance, 1750);
      expect(t.kcal % 50, 0);
    });

    test('lose weight: 15% under, capped at 500 kcal', () {
      expect(CalorieBudget.target(man, goals: [Goal.loseWeight])!.kcal, 2300);
      const big = BudgetInputs(sex: BodySex.male, age: 30, heightCm: 190, weightKg: 120, activity: ActivityLevel.active);
      final t = CalorieBudget.target(big, goals: [Goal.loseWeight])!;
      expect(t.maintenance - t.kcal, lessThanOrEqualTo(500));
      expect(t.kcal, 3350);
    });

    test('lose weight never goes below the floor', () {
      const small = BudgetInputs(sex: BodySex.female, age: 60, heightCm: 150, weightKg: 45, activity: ActivityLevel.sitting);
      final t = CalorieBudget.target(small, goals: [Goal.loseWeight])!;
      expect(t.kcal, 1200);
      expect(t.why, contains('1200'));
    });

    test('get fit adds a little', () {
      expect(CalorieBudget.target(woman, goals: [Goal.getFit])!.kcal, 1850);
    });

    test('no target for under-18s or impossible numbers', () {
      const teen = BudgetInputs(sex: BodySex.male, age: 16, heightCm: 170, weightKg: 60, activity: ActivityLevel.light);
      expect(CalorieBudget.target(teen), isNull);
      const odd = BudgetInputs(sex: BodySex.male, age: 30, heightCm: 90, weightKg: 60, activity: ActivityLevel.light);
      expect(CalorieBudget.target(odd), isNull);
    });
  });

  group('plateFor', () {
    test('fits inside what is left, protein first', () {
      for (final left in [200.0, 400.0, 600.0, 900.0]) {
        for (final diet in [null, ...Diet.values]) {
          for (final rice in [false, true]) {
            final plate = CalorieBudget.plateFor(left, diet: diet, riceBase: rice);
            expect(plate, isNotEmpty);
            expect(CalorieBudget.kcalOf(plate), lessThanOrEqualTo(left + 1), reason: '$left $diet $rice');
          }
        }
      }
    });

    test('suits the diet', () {
      String first(Diet? d) => CalorieBudget.plateFor(700, diet: d).first.$1.id;
      expect(first(Diet.veg), 'dal');
      expect(first(Diet.egg), 'egg_curry');
      expect(first(Diet.nonVeg), 'chicken_curry');
      expect(first(Diet.jain), 'paneer');
    });

    test('nothing when almost no room left', () {
      expect(CalorieBudget.plateFor(100), isEmpty);
    });

    test('describe reads like a plate', () {
      final text = CalorieBudget.describe(CalorieBudget.plateFor(600));
      expect(text, startsWith('1 katori dal + '));
      expect(text, contains('roti'));
      expect(CalorieBudget.describe(CalorieBudget.plateFor(600, diet: Diet.jain)), contains('paneer (100 g)'));
    });
  });

  test('service: save, target follows profile goal and latest weight', () async {
    final store = await SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
    final s = CalorieBudgetService(store);
    expect(await s.target(), isNull);

    await s.save(sex: BodySex.male, age: 30, activity: ActivityLevel.moderate, heightCm: 175, weightKg: 80);
    expect((await s.answers())!.age, 30);
    expect(await s.heightCm(), 175);
    expect((await s.target())!.kcal, 2700);

    await ProfileService(store).saveProfile(const UserProfile(goals: [Goal.loseWeight]));
    expect((await s.target())!.kcal, 2300);

    await s.clear();
    expect(await s.target(), isNull);
  });
}
