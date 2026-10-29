/// Type-to-log: "2 roti, 1 katori dal and curd" -> food entries, offline
/// and instant, using the HUX food table. Hinglish number words work
/// ("do roti", "aadha katori rice"). Anything not recognised is returned
/// so the UI can say so — never silently dropped or guessed.
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
    'five': 5.0, 'paanch': 5.0,
  };

  /// Unit words people use; all map onto the food's own unit (a "bowl"
  /// of dal is a katori). Grams are only honoured for paneer, whose
  /// portion is defined as 100 g.
  static const _unitWords = {
    'katori', 'katoris', 'bowl', 'bowls', 'cup', 'cups', 'glass', 'glasses',
    'piece', 'pieces', 'pc', 'pcs', 'plate', 'plates', 'spoon', 'spoons',
    'tbsp', 'handful', 'handfuls', 'serving', 'servings', 'g', 'gm', 'gms', 'grams',
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
      if (words.isNotEmpty && _unitWords.contains(words.first)) {
        if ({'g', 'gm', 'gms', 'grams'}.contains(words.first)) grams = true;
        words.removeAt(0);
      }
      if (words.isNotEmpty && words.first == 'of') words.removeAt(0);

      final name = words.join(' ');
      final food = IndianFoodDb.match(name);
      if (food == null || qty <= 0) {
        unknown.add(chunk);
        continue;
      }
      if (grams) {
        if (food.id != 'paneer') {
          unknown.add(chunk); // can't convert grams for household units
          continue;
        }
        qty = qty / 100; // paneer portion = 100 g
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
