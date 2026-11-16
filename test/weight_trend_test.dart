/// Weight trend: change, pace per week, and the line shown on the card.
import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/journeys/workout_log.dart';
import 'package:hux_app/core/progress/weight_trend.dart';

void main() {
  final now = DateTime(2026, 11, 16, 9);
  WeightEntry e(int daysAgo, double kg) => WeightEntry(now.subtract(Duration(days: daysAgo)), kg);

  test('no entries: nothing', () {
    expect(WeightTrend.of(const [], now: now), isNull);
  });

  test('one entry: no pace yet, asks for a weekly weigh-in', () {
    final t = WeightTrend.of([e(2, 72)], now: now)!;
    expect(t.latestKg, 72);
    expect(t.changeKg, isNull);
    expect(t.perWeekKg, isNull);
    expect(t.line, contains('once a week'));
    expect(t.due, isFalse);
  });

  test('entries under a week apart give a change but no pace', () {
    final t = WeightTrend.of([e(3, 72), e(0, 71.4)], now: now)!;
    expect(t.changeKg, closeTo(-0.6, 0.001));
    expect(t.perWeekKg, isNull);
  });

  test('steady loss reads as a pace that lasts', () {
    final t = WeightTrend.of([e(28, 74), e(14, 73), e(0, 72)], now: now, losing: true)!;
    expect(t.perWeekKg, closeTo(-0.5, 0.001));
    expect(t.overDays, 28);
    expect(t.line, 'Down 0.5 kg a week — a steady pace that lasts.');
  });

  test('too fast is flagged, whatever the goal', () {
    final t = WeightTrend.of([e(14, 76), e(0, 73)], now: now, losing: true)!;
    expect(t.perWeekKg, closeTo(-1.5, 0.001));
    expect(t.line, contains('faster than lasts'));
  });

  test('plateau and gain lines for a lose-weight goal', () {
    expect(WeightTrend.of([e(21, 72), e(0, 72.1)], now: now, losing: true)!.line, startsWith('Holding steady for 3 weeks'));
    expect(WeightTrend.of([e(14, 72), e(0, 73)], now: now, losing: true)!.line, contains('watch the trend'));
    expect(WeightTrend.of([e(21, 72), e(0, 72.1)], now: now)!.line, 'Holding steady.');
  });

  test('only the last 5 weeks set the pace', () {
    final t = WeightTrend.of([e(200, 90), e(28, 74), e(0, 72)], now: now)!;
    expect(t.overDays, 28);
    expect(t.changeKg, closeTo(-2, 0.001));
  });

  test('low weight for height: never cheer more loss', () {
    final t = WeightTrend.of([e(14, 48), e(0, 46)], now: now, losing: true, heightCm: 165)!;
    expect(t.line, contains('no need to lose more'));
  });

  test('weigh-in is due after a week', () {
    expect(WeightTrend.of([e(7, 72)], now: now)!.due, isTrue);
    expect(WeightTrend.of([e(6, 72)], now: now)!.due, isFalse);
  });
}
