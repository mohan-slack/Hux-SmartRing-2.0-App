/// Plate shares (petal chart): merge, order, "Other", and sum to 100.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/food/nutrients.dart';
import 'package:hux_app/core/food/plate_shares.dart';
import 'package:hux_app/widgets/petal_chart.dart';

FoodEntry food(String name, double kcal, {double qty = 1}) => FoodEntry(
      name: name,
      foodId: null,
      quantity: qty,
      unit: FoodUnit.katori,
      nutrients: Nutrients(kcal: kcal, proteinG: kcal / 20, carbsG: kcal / 10, fatG: kcal / 40),
      source: NutrientSource.values.first,
    );

void main() {
  test('biggest first, percentages add up to 100', () {
    final s = PlateShares.of([food('Curd', 90), food('Rice', 195), food('Dal', 150)]);
    expect(s.map((e) => e.name), ['Rice', 'Dal', 'Curd']);
    expect(s.fold<int>(0, (a, e) => a + e.percent), 100);
    expect(s.first.percent, 45); // 195 of 435
    expect(s.first.portion, '1 katori');
  });

  test('the same food logged twice becomes one petal', () {
    final s = PlateShares.of([food('Roti', 200, qty: 2), food('roti', 200, qty: 2), food('Dal', 100)]);
    expect(s, hasLength(2));
    expect(s.first.name, 'Roti');
    expect(s.first.percent, 80);
    expect(s.first.nutrients.kcal, 400);
  });

  test('more than 8 foods: the smallest are grouped as Other', () {
    final s = PlateShares.of([for (var i = 1; i <= 11; i++) food('Food $i', i * 10)]);
    expect(s, hasLength(PlateShares.maxPetals));
    expect(s.last.name, 'Other');
    expect(s.last.portion, '4 more');
    expect(s.last.nutrients.kcal, 10 + 20 + 30 + 40);
    expect(s.fold<int>(0, (a, e) => a + e.percent), 100);
  });

  test('no calories known: equal petals, still 100', () {
    final s = PlateShares.of([food('A', 0), food('B', 0), food('C', 0)]);
    expect(s.map((e) => e.percent).toList()..sort(), [33, 33, 34]);
  });

  test('nothing logged: nothing to draw', () {
    expect(PlateShares.of(const []), isEmpty);
  });

  testWidgets('petal chart shows every share', (tester) async {
    final shares = PlateShares.of([food('Rice', 195), food('Dal', 150), food('Curd', 90), food('Sabzi', 120)]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: PetalChart(shares: shares)))));
    await tester.pumpAndSettle();
    for (final s in shares) {
      expect(find.text(s.name), findsOneWidget);
      expect(find.text('${s.percent}%'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
