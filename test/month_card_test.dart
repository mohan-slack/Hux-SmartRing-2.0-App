/// The shareable month card.
/// Run with: flutter test test/month_card_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/widgets/month_card.dart';

void main() {
  test('ordinals read naturally', () {
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 31].map(MonthCard.ordinal).toList(),
        ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '23rd', '31st']);
  });
}
