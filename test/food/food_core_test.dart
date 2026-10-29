/// Food: table matching, type-to-log, protein gap, AI JSON handling.
/// Run with: flutter test

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/food/indian_food_db.dart';
import 'package:hux_app/core/food/meal_analyzer.dart';
import 'package:hux_app/core/food/meal_text_parser.dart';
import 'package:hux_app/core/food/nutrients.dart';
import 'package:hux_app/core/food/protein_gap.dart';
import 'package:hux_app/core/profile/user_profile.dart';

void main() {
  group('IndianFoodDb.match', () {
    test('exact names and regional aliases', () {
      expect(IndianFoodDb.match('chapati')?.id, 'roti');
      expect(IndianFoodDb.match('Pappu')?.id, 'dal');
      expect(IndianFoodDb.match('idly')?.id, 'idli');
      expect(IndianFoodDb.match('dahi')?.id, 'curd');
    });

    test('longest alias wins inside a phrase', () {
      expect(IndianFoodDb.match('2 aloo paratha with butter')?.id, 'aloo_paratha');
      expect(IndianFoodDb.match('chicken biryani')?.id, 'chicken_biryani');
      expect(IndianFoodDb.match('masala dosa')?.id, 'masala_dosa');
    });

    test('unknown dish -> null, never a wrong guess', () {
      expect(IndianFoodDb.match('thukpa'), isNull);
      expect(IndianFoodDb.match(''), isNull);
    });

    test('every row is still marked unverified (until a nutritionist reviews)', () {
      expect(indianFoods.every((f) => !f.verified), isTrue);
      expect(indianFoods.map((f) => f.id).toSet().length, indianFoods.length, reason: 'unique ids');
    });
  });

  group('MealTextParser', () {
    test('numbers, units and "and"', () {
      final p = MealTextParser.parse('2 roti, 1 katori dal and curd');
      expect(p.entries.map((e) => e.foodId), ['roti', 'dal', 'curd']);
      expect(p.entries.first.quantity, 2);
      expect(p.entries.first.nutrients.proteinG, closeTo(6, 0.01));
      expect(p.unknown, isEmpty);
    });

    test('Hinglish number words and halves', () {
      final p = MealTextParser.parse('do roti aur aadha katori rice');
      expect(p.entries.map((e) => e.quantity), [2, 0.5]);
    });

    test('grams only for paneer', () {
      final p = MealTextParser.parse('200g paneer, 100 g rice');
      expect(p.entries.single.foodId, 'paneer');
      expect(p.entries.single.quantity, 2);
      expect(p.unknown, ['100 g rice']);
    });

    test('unknown parts are reported, not dropped silently', () {
      final p = MealTextParser.parse('1 katori dal, 2 momos');
      expect(p.entries.single.foodId, 'dal');
      expect(p.unknown, ['2 momos']);
    });
  });

  group('ProteinGap', () {
    test('veg user: suggests dal first, in katoris', () {
      final gap = ProteinGap.compute(
        eaten: const Nutrients(kcal: 0, proteinG: 40, carbsG: 0, fatG: 0),
        goalG: 50,
        diet: Diet.veg,
      );
      expect(gap.remainingG, 10);
      expect(gap.suggestions.first.food.id, 'dal');
      expect(gap.suggestions.first.quantity, 2);
      expect(gap.suggestions.first.text, contains('katoris'));
    });

    test('never suggests meat or egg to vegetarians', () {
      for (final diet in [Diet.veg, Diet.jain, null]) {
        final gap = ProteinGap.compute(eaten: Nutrients.zero, goalG: 80, diet: diet);
        expect(gap.suggestions.every((s) => s.food.veg && !s.food.egg), isTrue);
      }
    });

    test('non-veg user can get chicken first', () {
      final gap = ProteinGap.compute(eaten: Nutrients.zero, goalG: 50, diet: Diet.nonVeg);
      expect(gap.suggestions.first.food.id, 'chicken_curry');
    });

    test('within 3 g of the goal counts as done', () {
      final gap = ProteinGap.compute(
        eaten: const Nutrients(kcal: 0, proteinG: 48, carbsG: 0, fatG: 0),
        goalG: 50,
      );
      expect(gap.done, isTrue);
      expect(gap.suggestions, isEmpty);
    });
  });

  group('MealAnalysisParser', () {
    test('table numbers win over AI numbers for known dishes', () {
      final a = MealAnalysisParser.parse({
        'items': [
          {
            'name': 'Dal Tadka',
            'portion': {'qty': 1, 'unit': 'katori'},
            'confidence': 0.9,
            'estimate': {'kcal': 999, 'protein': 99, 'carbs': 0, 'fat': 0, 'fiber': 0},
          },
        ],
      });
      final dal = a.items.single;
      expect(dal.source, NutrientSource.database);
      expect(dal.nutrients.proteinG, 7);
    });

    test('unknown dishes keep the AI estimate, labelled as such', () {
      final a = MealAnalysisParser.parse({
        'items': [
          {
            'name': 'thukpa',
            'portion': {'qty': 1, 'unit': 'plate'},
            'confidence': 0.7,
            'estimate': {'kcal': 350, 'protein': 14, 'carbs': 50, 'fat': 9, 'fiber': 3},
          },
        ],
      });
      expect(a.items.single.source, NutrientSource.aiEstimate);
      expect(a.items.single.nutrients.proteinG, 14);
      expect(a.items.single.name, 'Thukpa');
    });

    test('bad items and questions are dropped, max 2 questions', () {
      final a = MealAnalysisParser.parse({
        'items': [
          {'name': 'roti', 'portion': {'qty': 2, 'unit': 'roti'}},
          {'name': ''},
          'garbage',
        ],
        'questions': [
          {'itemIndex': 0, 'kind': 'quantity', 'text': 'How many rotis?', 'options': ['1', '2', '3']},
          {'itemIndex': 5, 'kind': 'quantity', 'text': 'Bad index', 'options': ['1', '2']},
          {'itemIndex': 0, 'kind': 'identity', 'text': 'One option only', 'options': ['x']},
          {'itemIndex': 0, 'kind': 'identity', 'text': 'Roti or paratha?', 'options': ['Roti', 'Paratha']},
          {'itemIndex': 0, 'kind': 'quantity', 'text': 'Third valid', 'options': ['1', '2']},
        ],
      });
      expect(a.items.length, 1);
      expect(a.questions.map((q) => q.text), ['How many rotis?', 'Roti or paratha?']);
    });

    test('answers update the meal without another AI call', () {
      var a = MealAnalysisParser.parse({
        'items': [
          {'name': 'roti', 'portion': {'qty': 2, 'unit': 'roti'}},
          {'name': 'paneer curry', 'portion': {'qty': 1, 'unit': 'katori'}},
        ],
        'questions': [
          {'itemIndex': 0, 'kind': 'quantity', 'text': 'How many rotis?', 'options': ['2', '3', '4']},
          {'itemIndex': 1, 'kind': 'identity', 'text': 'Paneer or chicken?', 'options': ['paneer curry', 'chicken curry']},
        ],
      });
      a = a.answer(a.questions.first, '3');
      expect(a.items[0].quantity, 3);
      expect(a.items[0].nutrients.proteinG, closeTo(9, 0.01));
      expect(a.questions.length, 1);

      a = a.answer(a.questions.first, 'chicken curry');
      expect(a.items[1].foodId, 'chicken_curry');
      expect(a.questions, isEmpty);
    });
  });

  group('RemoteMealAnalyzer', () {
    final jpeg = Uint8List.fromList(List.filled(100, 1));

    test('sends photo + description to the backend function', () async {
      String? calledName;
      Map<String, Object?>? sent;
      final analyzer = RemoteMealAnalyzer((name, body) async {
        calledName = name;
        sent = body;
        return {
          'items': [
            {'name': 'idli', 'portion': {'qty': 3, 'unit': 'piece'}},
          ],
        };
      });
      final a = await analyzer.analyze(imageJpeg: jpeg, description: '  idli sambar ');
      expect(calledName, 'analyze-meal');
      expect(sent!['description'], 'idli sambar');
      expect(sent!['image'], isA<String>());
      expect(a.items.single.foodId, 'idli');
    });

    test('network failure -> friendly error', () async {
      final analyzer = RemoteMealAnalyzer((_, __) async => throw Exception('offline'));
      expect(analyzer.analyze(imageJpeg: jpeg), throwsA(isA<MealAnalysisException>()));
    });

    test('no food found -> friendly error', () async {
      final analyzer = RemoteMealAnalyzer((_, __) async => {'items': [], 'questions': []});
      expect(analyzer.analyze(imageJpeg: jpeg), throwsA(isA<MealAnalysisException>()));
    });

    test('daily limit -> clear message', () async {
      final analyzer = RemoteMealAnalyzer((_, __) async => {'error': 'daily_limit'});
      await expectLater(
        analyzer.analyze(imageJpeg: jpeg),
        throwsA(isA<MealAnalysisException>().having((e) => e.message, 'message', contains("today's photo"))),
      );
    });

    test('too-large photo is refused before upload', () async {
      var called = false;
      final analyzer = RemoteMealAnalyzer((_, __) async {
        called = true;
        return null;
      });
      final huge = Uint8List(RemoteMealAnalyzer.maxImageBytes + 1);
      await expectLater(analyzer.analyze(imageJpeg: huge), throwsA(isA<MealAnalysisException>()));
      expect(called, isFalse);
    });
  });
}
