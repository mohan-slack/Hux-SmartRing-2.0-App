/// Tonight's timing from the bedtime: last chai, dinner, screens.
/// Run with: flutter test test/evening_timing_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/meaning/evening_timing.dart';

void main() {
  test('10:30 PM bed: chai by 2:30 PM, dinner by 8:00, screens 10:00', () {
    final t = EveningTiming.forBed(DateTime(2026, 11, 3, 22, 30));
    expect(t.lastCaffeine, DateTime(2026, 11, 3, 14, 30));
    expect(t.lastMeal, DateTime(2026, 11, 3, 20, 0));
    expect(t.screensOff, DateTime(2026, 11, 3, 22, 0));
  });

  test('late sleeper (1:30 AM): caffeine still capped at 4 PM', () {
    final t = EveningTiming.forBed(DateTime(2026, 11, 4, 1, 30));
    expect(t.lastCaffeine, DateTime(2026, 11, 3, 16, 0)); // not 5:30 PM
    expect(t.lastMeal, DateTime(2026, 11, 3, 23, 0));
  });

  test('night shift (bed 9 AM): no evening cap — chai by 1 AM', () {
    final t = EveningTiming.forBed(DateTime(2026, 11, 4, 9, 0));
    expect(t.lastCaffeine, DateTime(2026, 11, 4, 1, 0));
    expect(t.lastMeal, DateTime(2026, 11, 4, 6, 30));
  });
}
