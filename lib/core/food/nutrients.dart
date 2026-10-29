/// HUX Food — core types.
/// Portions are Indian household units (katori, roti, piece, glass…),
/// never grams-first: that is how people actually eat and remember.
library;

class Nutrients {
  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;

  const Nutrients({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.fiberG = 0,
  });

  static const zero = Nutrients(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0);

  Nutrients operator +(Nutrients o) => Nutrients(
        kcal: kcal + o.kcal,
        proteinG: proteinG + o.proteinG,
        carbsG: carbsG + o.carbsG,
        fatG: fatG + o.fatG,
        fiberG: fiberG + o.fiberG,
      );

  Nutrients operator *(double k) => Nutrients(
        kcal: kcal * k,
        proteinG: proteinG * k,
        carbsG: carbsG * k,
        fatG: fatG * k,
        fiberG: fiberG * k,
      );

  Map<String, Object?> toJson() => {
        'kcal': kcal,
        'protein': proteinG,
        'carbs': carbsG,
        'fat': fatG,
        'fiber': fiberG,
      };

  factory Nutrients.fromJson(Map<String, Object?> j) {
    double n(String k) => (j[k] as num?)?.toDouble() ?? 0;
    return Nutrients(
      kcal: n('kcal'),
      proteinG: n('protein'),
      carbsG: n('carbs'),
      fatG: n('fat'),
      fiberG: n('fiber'),
    );
  }
}

/// Household units. A "katori" here is a standard ~150 ml bowl.
enum FoodUnit { katori, piece, roti, glass, cup, plate, spoon, handful, grams }

extension FoodUnitLabel on FoodUnit {
  String label(num qty) {
    final one = qty == 1;
    return switch (this) {
      FoodUnit.katori => one ? 'katori' : 'katoris',
      FoodUnit.piece => one ? 'piece' : 'pieces',
      FoodUnit.roti => one ? 'roti' : 'rotis',
      FoodUnit.glass => one ? 'glass' : 'glasses',
      FoodUnit.cup => one ? 'cup' : 'cups',
      FoodUnit.plate => one ? 'plate' : 'plates',
      FoodUnit.spoon => one ? 'spoon' : 'spoons',
      FoodUnit.handful => one ? 'handful' : 'handfuls',
      FoodUnit.grams => 'g',
    };
  }
}

/// Where an item's numbers came from — shown to the user, never hidden.
enum NutrientSource {
  /// HUX's own food table (see indian_food_db.dart).
  database,

  /// The AI's estimate for a dish not in our table.
  aiEstimate,
}

/// One item in a meal, e.g. "2 roti" or "1 katori dal".
class FoodEntry {
  final String name;

  /// Food-table id when matched, else null (AI-estimated dish).
  final String? foodId;
  final double quantity;
  final FoodUnit unit;

  /// Totals for [quantity] (already multiplied).
  final Nutrients nutrients;
  final NutrientSource source;

  const FoodEntry({
    required this.name,
    required this.foodId,
    required this.quantity,
    required this.unit,
    required this.nutrients,
    required this.source,
  });

  /// Same item with a new quantity, nutrients scaled to match.
  FoodEntry withQuantity(double q) => FoodEntry(
        name: name,
        foodId: foodId,
        quantity: q,
        unit: unit,
        nutrients: quantity == 0 ? nutrients : nutrients * (q / quantity),
        source: source,
      );

  String get portionText {
    final q = quantity == quantity.roundToDouble()
        ? quantity.toInt().toString()
        : quantity.toStringAsFixed(1);
    return unit == FoodUnit.grams ? '$q g' : '$q ${unit.label(quantity)}';
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'foodId': foodId,
        'qty': quantity,
        'unit': unit.name,
        'n': nutrients.toJson(),
        'src': source.name,
      };

  static FoodEntry? fromJson(Map<String, Object?> j) {
    final unit = FoodUnit.values.where((u) => u.name == j['unit']).firstOrNull;
    final src = NutrientSource.values.where((s) => s.name == j['src']).firstOrNull;
    final n = j['n'];
    if (unit == null || src == null || n is! Map<String, Object?> || j['name'] is! String) return null;
    return FoodEntry(
      name: j['name'] as String,
      foodId: j['foodId'] as String?,
      quantity: (j['qty'] as num?)?.toDouble() ?? 1,
      unit: unit,
      nutrients: Nutrients.fromJson(n),
      source: src,
    );
  }
}

enum MealType { breakfast, lunch, snack, dinner }

extension MealTypeLabel on MealType {
  String get label => switch (this) {
        MealType.breakfast => 'Breakfast',
        MealType.lunch => 'Lunch',
        MealType.snack => 'Snack',
        MealType.dinner => 'Dinner',
      };

  /// A sensible default from the local time of day.
  static MealType forHour(int hour) {
    if (hour < 11) return MealType.breakfast;
    if (hour < 16) return MealType.lunch;
    if (hour < 19) return MealType.snack;
    return MealType.dinner;
  }
}

class Meal {
  final MealType type;
  final DateTime loggedAt;
  final List<FoodEntry> items;

  const Meal({required this.type, required this.loggedAt, required this.items});

  Nutrients get total => items.fold(Nutrients.zero, (sum, e) => sum + e.nutrients);

  Map<String, Object?> toJson() => {
        'type': type.name,
        'at': loggedAt.toUtc().toIso8601String(),
        'items': [for (final i in items) i.toJson()],
      };

  static Meal? fromJson(Map<String, Object?> j) {
    final type = MealType.values.where((t) => t.name == j['type']).firstOrNull;
    final at = DateTime.tryParse('${j['at']}');
    final rawItems = j['items'];
    if (type == null || at == null || rawItems is! List) return null;
    final items = <FoodEntry>[];
    for (final r in rawItems) {
      if (r is! Map<String, Object?>) continue;
      final entry = FoodEntry.fromJson(r);
      if (entry != null) items.add(entry);
    }
    return Meal(type: type, loggedAt: at, items: items);
  }
}
