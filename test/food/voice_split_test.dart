/// Spoken meals have no commas — split them into foods.
/// Run with: flutter test test/food/voice_split_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/food/meal_text_parser.dart';

void main() {
  test('run-on English speech', () {
    expect(MealTextParser.splitRunOn('I had two roti dal and a glass of milk for lunch'), 'two roti, dal, a glass of milk');
  });

  test('Hinglish and Tenglish', () {
    expect(MealTextParser.splitRunOn('do paratha aur dahi'), 'do paratha, dahi');
    expect(MealTextParser.splitRunOn('rendu idli sambar'), 'rendu idli, sambar');
  });

  test('unknown words stay together for the AI look-up', () {
    final out = MealTextParser.splitRunOn('two roti and mutton kola urundai');
    expect(out, 'two roti, mutton kola urundai');
    final parsed = MealTextParser.parse(out);
    expect(parsed.entries.single.foodId, 'roti');
    expect(parsed.unknown, isNotEmpty);
  });
}
