/// WhatsApp summary text: only real data, never a near-empty message.
import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/progress/goal_score.dart';
import 'package:hux_app/core/share/summary_text.dart';

void main() {
  final now = DateTime(2026, 11, 16, 20);

  test('daily: full day', () {
    final t = SummaryText.daily(
      now: now,
      name: 'Mohan',
      charge: 72,
      chargeLabel: 'Good to go',
      sleepMin: 430,
      steps: 6240,
      stepGoal: 8000,
      proteinG: 48,
      proteinGoalG: 70,
      kcal: 1450,
      waterGlasses: 6,
      waterGoal: 9,
      streakDays: 5,
    )!;
    expect(t.split('\n'), [
      "*Mohan's day with HUX* — Mon 16 Nov",
      '⚡ Charge 72 · Good to go',
      '😴 Sleep 7 h 10 min',
      '👣 Steps 6,240 of 8,000',
      '🍛 Protein 48 of 70 g · 1,450 kcal',
      '💧 Water 6 of 9 glasses',
      '🔥 5-day streak',
      SummaryText.footer,
    ]);
  });

  test('daily: skips what has no data; no name', () {
    final t = SummaryText.daily(now: now, charge: 60, steps: 0, waterGlasses: 3, sleepMin: 480)!;
    expect(t, startsWith('*My day with HUX*'));
    expect(t, contains('😴 Sleep 8 h'));
    expect(t, contains('💧 Water 3 glasses'));
    expect(t, isNot(contains('Steps')));
    expect(t, isNot(contains('Protein')));
  });

  test('daily: too little data, nothing to send', () {
    expect(SummaryText.daily(now: now, steps: 4000), isNull);
    expect(SummaryText.daily(now: now), isNull);
  });

  test('weekly: score, parts with data, weight change', () {
    const w = WeekScore({
      ScorePart.sleep: PartScore(ScorePart.sleep, 80, [], ['x']),
      ScorePart.energy: PartScore(ScorePart.energy, null, [], []),
      ScorePart.move: PartScore(ScorePart.move, 64, [], ['y']),
      ScorePart.food: PartScore(ScorePart.food, null, [], []),
    }, lastWeek: 66);
    final t = SummaryText.weekly(w, weightChangeKg: -0.6)!;
    final lines = t.split('\n');
    expect(lines.first, '*My week with HUX: 72/100* (up 6)');
    expect(lines, hasLength(5));
    expect(t, contains('⚖️ Weight −0.6 kg'));
    expect(t, isNot(contains('Food')));
  });

  test('weekly: one part only, nothing to send', () {
    const w = WeekScore({ScorePart.sleep: PartScore(ScorePart.sleep, 80, [], ['x'])});
    expect(SummaryText.weekly(w), isNull);
  });
}
