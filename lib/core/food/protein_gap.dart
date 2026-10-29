/// Protein gap: how much protein is left for today, and what to add —
/// in katoris and pieces, matched to the user's diet.
library;

import '../profile/user_profile.dart';
import 'indian_food_db.dart';
import 'nutrients.dart';

class ProteinSuggestion {
  final FoodItem food;
  final double quantity;

  const ProteinSuggestion(this.food, this.quantity);

  double get proteinG => food.perUnit.proteinG * quantity;

  String get text {
    final q = quantity == quantity.roundToDouble() ? quantity.toInt().toString() : quantity.toString();
    return '$q ${food.unit.label(quantity)} ${food.name.toLowerCase()} (+${proteinG.round()} g)';
  }
}

class ProteinGap {
  /// Default daily goal when the user hasn't set one. ICMR-NIN's 2020
  /// RDA for adults is about 0.83 g per kg body weight (roughly 46–54 g
  /// for reference adults); 50 g is a middle default the user can edit.
  static const defaultGoalG = 50;

  /// Gaps smaller than this are "done" — no nagging over 2–3 g.
  static const doneWithinG = 3.0;

  static const maxSuggestions = 2;

  /// Everyday protein foods to suggest, most familiar first, per diet.
  static const _vegOrder = ['dal', 'curd', 'paneer', 'sprouts', 'chole', 'soya_chunks', 'milk', 'peanuts'];
  static const _eggExtra = ['egg'];
  static const _nonVegExtra = ['chicken_curry', 'egg', 'fish_curry'];

  final double goalG;
  final double eatenG;
  final List<ProteinSuggestion> suggestions;

  const ProteinGap._(this.goalG, this.eatenG, this.suggestions);

  double get remainingG => (goalG - eatenG) > 0 ? goalG - eatenG : 0;
  bool get done => remainingG <= doneWithinG;

  factory ProteinGap.compute({
    required Nutrients eaten,
    required double goalG,
    Diet? diet,
  }) {
    final remaining = goalG - eaten.proteinG;
    if (remaining <= doneWithinG) return ProteinGap._(goalG, eaten.proteinG, const []);

    final order = switch (diet) {
      Diet.nonVeg => [..._nonVegExtra, ..._vegOrder],
      Diet.egg => [..._eggExtra, ..._vegOrder],
      _ => _vegOrder, // veg, jain, or not answered: vegetarian is safest
    };

    final picks = <ProteinSuggestion>[];
    var left = remaining;
    for (final id in order) {
      if (picks.length >= maxSuggestions || left <= doneWithinG) break;
      final food = IndianFoodDb.byId(id);
      if (food == null) continue;
      final per = food.perUnit.proteinG;
      if (per <= 0) continue;
      // Whole units, at most 2 of any one food — realistic portions.
      final units = (left / per).ceil().clamp(1, 2).toDouble();
      picks.add(ProteinSuggestion(food, units));
      left -= per * units;
    }
    return ProteinGap._(goalG, eaten.proteinG, picks);
  }
}
