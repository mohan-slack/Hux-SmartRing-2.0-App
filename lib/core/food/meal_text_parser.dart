/// Type-to-log: "2 roti, 1 katori dal and curd" -> food entries, offline
/// and instant, using the HUX food table (170 dishes). Hinglish and
/// regional number words work ("do roti", "rendu idli", "aadha katori
/// rice"), small spelling slips are forgiven ("chcken noodles"), sizes
/// adjust the portion ("big plate biryani"), and grams work wherever a
/// portion has a known weight ("150 g rice"). Anything still not
/// recognised is returned so the UI can offer an AI estimate.
library;

import 'indian_food_db.dart';
import 'nutrients.dart';

class ParsedMeal {
  final List<FoodEntry> entries;

  /// Parts of the text that matched nothing in the food table.
  final List<String> unknown;

  const ParsedMeal(this.entries, this.unknown);
}

class MealTextParser {
  const MealTextParser._();

  static const _numberWords = {
    'half': 0.5, 'aadha': 0.5, 'adha': 0.5, 'ardha': 0.5,
    'one': 1.0, 'a': 1.0, 'an': 1.0, 'ek': 1.0, 'oka': 1.0, 'ondu': 1.0,
    'two': 2.0, 'do': 2.0, 'rendu': 2.0, 'eradu': 2.0,
    'three': 3.0, 'teen': 3.0, 'moodu': 3.0, 'mooru': 3.0,
    'four': 4.0, 'char': 4.0, 'naalugu': 4.0, 'naalku': 4.0,
    'five': 5.0, 'paanch': 5.0, 'aidu': 5.0, 'ainthu': 5.0,
    'six': 6.0, 'chhe': 6.0, 'aaru': 6.0,
    'quarter': 0.25,
  };

  /// Size words scale the portion.
  static const _sizeWords = {
    'small': 0.75, 'chota': 0.75, 'chhota': 0.75, 'little': 0.75, 'half-plate': 0.5,
    'big': 1.5, 'large': 1.5, 'bada': 1.5, 'full': 1.0, 'double': 2.0, 'extra': 1.25,
  };

  /// Unit words people use; all map onto the food's own unit (a "bowl"
  /// of dal is a katori). Grams are only honoured for paneer, whose
  /// portion is defined as 100 g.
  static const _unitWords = {
    'katori', 'katoris', 'bowl', 'bowls', 'cup', 'cups', 'glass', 'glasses',
    'piece', 'pieces', 'pc', 'pcs', 'plate', 'plates', 'spoon', 'spoons',
    'tbsp', 'tsp', 'handful', 'handfuls', 'serving', 'servings', 'packet', 'packets', 'pack', 'slice', 'slices',
    'scoop', 'scoops', 'g', 'gm', 'gms', 'grams',
  };

  static ParsedMeal parse(String text) {
    final chunks = text
        .toLowerCase()
        .split(RegExp(r',|\+|\n|;|\band\b|\baur\b|\bwith\b'))
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty);

    final entries = <FoodEntry>[];
    final unknown = <String>[];

    for (final chunk in chunks) {
      final words = chunk.split(RegExp(r'\s+')).toList();
      var qty = 1.0;
      var grams = false;

      // Leading quantity: "2", "1.5", "½", or a number word.
      if (words.isNotEmpty) {
        final first = words.first.replaceAll('½', '0.5');
        final asNum = double.tryParse(first);
        final gramMatch = RegExp(r'^(\d+(?:\.\d+)?)(g|gm|gms|grams)$').firstMatch(first);
        if (gramMatch != null) {
          qty = double.parse(gramMatch.group(1)!);
          grams = true;
          words.removeAt(0);
        } else if (asNum != null) {
          qty = asNum;
          words.removeAt(0);
        } else if (_numberWords.containsKey(first)) {
          qty = _numberWords[first]!;
          words.removeAt(0);
        }
      }
      // "big plate", "small katori", "double" — anywhere before the dish.
      for (final w in [...words]) {
        final f = _sizeWords[w];
        if (f != null) {
          qty *= f;
          words.remove(w);
        }
      }
      // "2 x roti", "roti x 2", "roti 2"
      if (words.length > 1 && double.tryParse(words.last) != null) {
        qty *= double.parse(words.removeLast());
      }
      words.removeWhere((w) => w == 'x');
      if (words.isNotEmpty && _unitWords.contains(words.first)) {
        if ({'g', 'gm', 'gms', 'grams'}.contains(words.first)) grams = true;
        words.removeAt(0);
      }
      if (words.isNotEmpty && words.first == 'of') words.removeAt(0);

      final name = words.join(' ');
      // Only log what we're sure of; a half-match ("chicken manchurian"
      // → chicken curry) goes to "unknown" so it can be estimated instead.
      final m = IndianFoodDb.bestMatch(name);
      final food = m != null && m.confident ? m.food : null;
      if (food == null || qty <= 0) {
        unknown.add(chunk);
        continue;
      }
      if (grams) {
        final per = IndianFoodDb.gramsPerUnit(food);
        if (per == null) {
          unknown.add(chunk); // counted in pieces; grams can't be converted
          continue;
        }
        qty = qty / per;
      }
      entries.add(FoodEntry(
        name: food.name,
        foodId: food.id,
        quantity: qty,
        unit: food.unit,
        nutrients: food.perUnit * qty,
        source: NutrientSource.database,
      ));
    }
    return ParsedMeal(entries, unknown);
  }
}
