/// "Big lunch today — keep dinner light." Looks at what's logged before
/// dinner and, when it's a lot, says so and asks the meal ideas for a
/// lighter dinner. Pure.
library;

import 'nutrients.dart';

class DinnerAdvice {
  /// One line for the user.
  final String note;
  final double kcalSoFar;

  const DinnerAdvice({required this.note, required this.kcalSoFar});

  /// One meal this big counts as a big meal (no target set).
  static const bigMealKcal = 900;

  /// With a calorie target: this share eaten before dinner = big day.
  static const targetShare = 0.65;

  /// Null when dinner is already logged or nothing stands out.
  static DinnerAdvice? check(List<Meal> today, {int? targetKcal}) {
    if (today.isEmpty || today.any((m) => m.type == MealType.dinner)) return null;
    final total = today.fold<double>(0, (s, m) => s + m.total.kcal);
    final biggest = today.reduce((a, b) => a.total.kcal >= b.total.kcal ? a : b);
    final big = targetKcal != null && targetKcal > 0
        ? total >= targetKcal * targetShare
        : biggest.total.kcal >= bigMealKcal;
    if (!big) return null;
    final n = ((total / 50).round() * 50).toString();
    final kcal = n.length > 3 ? '${n.substring(0, n.length - 3)},${n.substring(n.length - 3)}' : n;
    final what = targetKcal != null && targetKcal > 0
        ? '≈$kcal kcal logged before dinner'
        : 'Big ${biggest.type.label.toLowerCase()} today (≈${biggest.total.kcal.round()} kcal)';
    return DinnerAdvice(
      note: '$what — a light dinner balances it: dal or curd with sabzi, one roti. No need to skip it.',
      kcalSoFar: total,
    );
  }
}
