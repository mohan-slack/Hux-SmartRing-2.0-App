/// Guards the food table's numbers, and the protein goal per profile.
/// Run with: flutter test test/food/food_data_check_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/food/food_log_service.dart';
import 'package:hux_app/core/food/indian_food_db.dart';
import 'package:hux_app/core/profile/user_profile.dart';

void main() {
  test('every food: kcal ≈ 4·protein + 4·carbs + 9·fat (within 15%)', () {
    final off = <String>[];
    for (final f in indianFoods) {
      if (f.id == 'beer') continue; // alcohol adds 7 kcal/g
      final n = f.perUnit;
      final atwater = 4 * n.proteinG + 4 * n.carbsG + 9 * n.fatG;
      if (atwater < 10) continue; // tea, black coffee
      if (((n.kcal - atwater) / atwater).abs() > 0.15) off.add('${f.id}: ${n.kcal} vs ${atwater.round()}');
    }
    expect(off, isEmpty);
  });

  test('no impossible rows: fibre ≤ carbs, no negatives, unique ids', () {
    final ids = <String>{};
    for (final f in indianFoods) {
      final n = f.perUnit;
      expect(n.fiberG <= n.carbsG + 0.01, isTrue, reason: f.id);
      expect([n.kcal, n.proteinG, n.carbsG, n.fatG, n.fiberG].every((v) => v >= 0), isTrue, reason: f.id);
      expect(ids.add(f.id), isTrue, reason: 'duplicate ${f.id}');
    }
  });

  test('staples match reference values (IFCT 2017 / USDA, per household unit)', () {
    FoodItemCheck at(String id) => FoodItemCheck(indianFoods.firstWhere((f) => f.id == id));
    at('egg').protein(6.3).kcal(75); // 1 boiled egg, 50 g
    at('milk').protein(7.5).kcal(145); // 250 ml toned
    at('paneer').protein(18).kcal(265); // 100 g
    at('chicken_breast').protein(31).kcal(165); // 100 g cooked
    at('peanuts').protein(7.5).kcal(170); // 30 g
    at('walnuts').kcal(195); // 30 g
    at('rice').kcal(195); // 150 g cooked
  });

  test('protein per kg follows the goal', () {
    double perKg(UserProfile? p) => FoodLogService.proteinPerKgFor(p).perKg;
    expect(perKg(null), 0.8);
    expect(perKg(const UserProfile(goals: [Goal.loseWeight])), 1.0);
    expect(perKg(const UserProfile(goals: [Goal.getFit])), 1.2);
    expect(perKg(const UserProfile(dayType: DayType.retired)), 1.0);
    expect(perKg(const UserProfile(audience: Audience.parent)), 1.0);
    // Diabetes/BP: don't raise protein without a doctor.
    expect(perKg(const UserProfile(goals: [Goal.sugarBp, Goal.getFit])), 0.8);
  });
}

class FoodItemCheck {
  final FoodItem f;
  FoodItemCheck(this.f);

  FoodItemCheck protein(double g) {
    expect(f.perUnit.proteinG, closeTo(g, g * 0.1), reason: '${f.id} protein');
    return this;
  }

  FoodItemCheck kcal(double k) {
    expect(f.perUnit.kcal, closeTo(k, k * 0.1), reason: '${f.id} kcal');
    return this;
  }
}
