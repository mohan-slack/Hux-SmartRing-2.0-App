/// Daily calorie target and "what's left" portion ideas.
///
/// Target: Mifflin-St Jeor resting energy × activity, then the goal:
/// - Lose weight: −15% (at most −500 kcal/day ≈ 0.5 kg a week), never
///   below 1,200 kcal (women / not said) or 1,500 kcal (men).
/// - Build strength / get fit: maintenance + 5%.
/// - Otherwise: maintenance.
/// Under 18 → no target (growing bodies shouldn't diet by app).
///
/// Portions: for the calories left today, a plate of familiar foods in
/// katori / roti / pieces, fitted to the diet and meal time. Values are
/// HUX's food-table estimates — a guide, not a prescription. Pure.
library;

import '../profile/user_profile.dart';
import 'indian_food_db.dart';
import 'nutrients.dart';

enum BodySex { female, male, unsaid }

enum ActivityLevel { sitting, light, moderate, active }

extension ActivityLevelInfo on ActivityLevel {
  double get factor => switch (this) {
        ActivityLevel.sitting => 1.2,
        ActivityLevel.light => 1.375,
        ActivityLevel.moderate => 1.55,
        ActivityLevel.active => 1.725,
      };

  String get label => switch (this) {
        ActivityLevel.sitting => 'Mostly sitting',
        ActivityLevel.light => 'Some walking',
        ActivityLevel.moderate => 'On my feet / exercise 3×',
        ActivityLevel.active => 'Very active',
      };

  /// From usual daily steps, when the user hasn't picked.
  static ActivityLevel fromSteps(int? steps) => steps == null || steps < 5000
      ? ActivityLevel.sitting
      : steps < 7500
          ? ActivityLevel.light
          : steps < 10000
              ? ActivityLevel.moderate
              : ActivityLevel.active;
}

class BudgetInputs {
  final BodySex sex;
  final int age;
  final double heightCm;
  final double weightKg;
  final ActivityLevel activity;

  const BudgetInputs({
    required this.sex,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.activity,
  });

  Map<String, Object?> toJson() =>
      {'sex': sex.name, 'age': age, 'h': heightCm, 'w': weightKg, 'act': activity.name};

  static BudgetInputs? fromJson(Object? j) {
    if (j is! Map) return null;
    final sex = BodySex.values.where((s) => s.name == j['sex']).firstOrNull;
    final act = ActivityLevel.values.where((a) => a.name == j['act']).firstOrNull;
    final age = j['age'], h = j['h'], w = j['w'];
    if (sex == null || act == null || age is! int || h is! num || w is! num) return null;
    return BudgetInputs(sex: sex, age: age, heightCm: h.toDouble(), weightKg: w.toDouble(), activity: act);
  }
}

class CalorieTarget {
  final int kcal;
  final int maintenance;

  /// Plain words: why this number.
  final String why;

  const CalorieTarget({required this.kcal, required this.maintenance, required this.why});
}

class CalorieBudget {
  const CalorieBudget._();

  static const minAge = 18;

  /// Resting energy (Mifflin-St Jeor). "Not said" uses the midpoint.
  static double bmr(BudgetInputs i) {
    final base = 10 * i.weightKg + 6.25 * i.heightCm - 5 * i.age;
    return switch (i.sex) {
      BodySex.male => base + 5,
      BodySex.female => base - 161,
      BodySex.unsaid => base - 78,
    };
  }

  /// Null for under-18s or impossible inputs.
  static CalorieTarget? target(BudgetInputs i, {List<Goal> goals = const []}) {
    if (i.age < minAge || i.age > 100 || i.heightCm < 120 || i.heightCm > 230 || i.weightKg < 30 || i.weightKg > 250) {
      return null;
    }
    final maintain = bmr(i) * i.activity.factor;
    final floor = i.sex == BodySex.male ? 1500.0 : 1200.0;
    double kcal;
    String why;
    if (goals.contains(Goal.loseWeight)) {
      final cut = (maintain * 0.15).clamp(0, 500).toDouble();
      kcal = maintain - cut;
      why = 'About ${_round(cut)} kcal under what you burn — roughly 0.5 kg a week at most, the pace that lasts.';
      if (kcal < floor) {
        kcal = floor;
        why = 'Kept at ${floor.round()} kcal — going lower makes it hard to get enough protein and nutrients.';
      }
    } else if (goals.contains(Goal.getFit)) {
      kcal = maintain * 1.05;
      why = 'A little above what you burn, to fuel training and build strength.';
    } else {
      kcal = maintain;
      why = 'About what you burn in a day, to keep your weight steady.';
    }
    return CalorieTarget(kcal: _round(kcal), maintenance: _round(maintain), why: why);
  }

  static int _round(double v) => (v / 50).round() * 50;

  /// A plate that fits [kcalLeft]: a base (roti or rice), a protein that
  /// suits [diet], then a vegetable and curd if there's room. Empty when
  /// under ~150 kcal (then: "a light snack, or nothing more today").
  static List<(FoodItem food, double qty)> plateFor(double kcalLeft, {Diet? diet, bool riceBase = false}) {
    if (kcalLeft < 150) return const [];
    FoodItem f(String id) => IndianFoodDb.byId(id)!;
    final protein = switch (diet) {
      Diet.nonVeg => f('chicken_curry'),
      Diet.egg => f('egg_curry'),
      Diet.jain => f('paneer'), // plain paneer: no onion or garlic
      _ => f('dal'),
    };
    final base = riceBase ? f('rice') : f('roti');
    final plate = <(FoodItem, double)>[];
    var left = kcalLeft;
    void add(FoodItem item, double qty) {
      plate.add((item, qty));
      left -= item.perUnit.kcal * qty;
    }

    // Protein first: it's what most Indian plates are short of.
    final pQty = left >= protein.perUnit.kcal ? 1.0 : 0.5;
    add(protein, pQty);
    // Then the base, as many as fit (roti 1–3, rice ½–1½ katori).
    final step = riceBase ? 0.5 : 1.0;
    final maxBase = riceBase ? 1.5 : 3.0;
    var b = 0.0;
    while (b + step <= maxBase && left - base.perUnit.kcal * step >= 60) {
      b += step;
      left -= base.perUnit.kcal * step;
    }
    if (b > 0) plate.add((base, b));
    // Vegetables and curd if there's room.
    final sabzi = f('mixed_sabzi'), curd = f('curd');
    if (left >= sabzi.perUnit.kcal) add(sabzi, 1);
    if (left >= curd.perUnit.kcal) add(curd, 1);
    return plate;
  }

  /// "2 roti + 1 katori dal + …" with the total.
  static String describe(List<(FoodItem food, double qty)> plate) {
    String q(double v) => v == v.roundToDouble() ? v.round().toString() : (v == 0.5 ? '½' : v.toString());
    return plate.map((e) {
      final (food, qty) = e;
      final unit = switch (food.unit) {
        FoodUnit.katori => ' katori',
        FoodUnit.roti || FoodUnit.piece => '',
        _ => ' ${food.unit.name}',
      };
      // Keep "(100 g)" on pieces like paneer so the amount is clear.
      final keepNote = food.unit == FoodUnit.piece && food.name.contains('(');
      final name = (keepNote ? food.name : food.name.split('(').first).split('/').first.trim().toLowerCase();
      return '${q(qty)}$unit $name';
    }).join(' + ');
  }

  static double kcalOf(List<(FoodItem food, double qty)> plate) =>
      plate.fold(0.0, (s, e) => s + e.$1.perUnit.kcal * e.$2);
}
