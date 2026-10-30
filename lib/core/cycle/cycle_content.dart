/// Plain words for each phase. Kept short, kind and practical.
/// UNREVIEWED: have a gynaecologist read this before launch.
library;

import 'cycle_models.dart';
import 'cycle_predictor.dart';

class PhaseTips {
  final String body;
  final String move;
  final String food;
  final String sleep;

  const PhaseTips({required this.body, required this.move, required this.food, required this.sleep});
}

class CycleContent {
  const CycleContent._();

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String date(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  /// "12–15 Nov" / "30 Nov – 3 Dec".
  static String range(DateTime a, DateTime b) =>
      a.month == b.month ? '${a.day}–${b.day} ${_months[b.month - 1]}' : '${date(a)} – ${date(b)}';

  static PhaseTips tips(CyclePhase p) => switch (p) {
        CyclePhase.period => const PhaseTips(
            body: 'Energy can dip and cramps are common. Go easy on yourself.',
            move: 'Gentle walks, stretching or yoga. Rest is fine too.',
            food: 'Iron helps: ragi, rajma, chana with jaggery, palak. Add lemon or amla to absorb more.',
            sleep: 'A warm water bottle on your tummy can ease cramps at night.',
          ),
        CyclePhase.follicular => const PhaseTips(
            body: 'Energy often climbs after your period.',
            move: 'Good days to push a little — try the harder version.',
            food: 'Protein builds strength: dal, paneer, curd, eggs, sprouts.',
            sleep: 'Keep the same wake time — it makes the next weeks easier.',
          ),
        CyclePhase.ovulatory => const PhaseTips(
            body: 'Many feel their strongest and most social now.',
            move: 'Great for a challenge day or a longer brisk walk.',
            food: 'Fibre and water: fruit, salad, buttermilk, plenty of water.',
            sleep: 'Stay steady — late nights catch up with you next week.',
          ),
        CyclePhase.luteal => const PhaseTips(
            body: 'Resting heart rate and body temperature rise a little. That is normal, not you failing.',
            move: 'Steady, moderate workouts. It is fine if they feel harder.',
            food: 'Cravings are normal. Seeds, nuts, banana and leafy greens help; go easy on salt to ease bloating.',
            sleep: 'Sleep can be lighter — a cooler room and an earlier wind-down help.',
          ),
      };

  /// One line for Home / the hero card.
  static String statusLine(CycleForecast f) {
    if (f.mode == CycleMode.pregnant) return 'Predictions paused';
    if (f.lastStart == null) return 'Log your last period to see predictions';
    if (f.periodOpen) return 'Period day ${f.dayOfCycle} · tap to log flow';
    if (!f.mode.predicts) return 'Last period ${date(f.lastStart!)}';
    if (f.isLate) {
      final days = f.likely == null ? 0 : daysBetween(f.likely!, f.today);
      return days > 0 ? 'Period is $days ${days == 1 ? 'day' : 'days'} later than usual' : 'Period may start soon';
    }
    final d = f.daysToWindow ?? 99;
    if (d <= 0) return 'Period likely any day now';
    return 'Next period likely ${range(f.from!, f.to!)}';
  }

  /// Under scores: why a dip may be fine this week.
  static String? scoreNote(CyclePhase? p) => p == CyclePhase.luteal
      ? 'Your Charge this week is compared with your own past luteal days.'
      : p == null
          ? null
          : 'Your Charge is compared with your own days at a similar point in your cycle.';
}
