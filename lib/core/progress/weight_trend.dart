/// Weight trend in plain words: latest, change, pace per week, and one
/// calm line about what it means. One weigh-in means little (water and
/// salt swing 1–2 kg), so the pace needs entries a week or more apart.
/// Pure.
library;

import '../journeys/workout_log.dart';

class WeightTrend {
  final double latestKg;
  final DateTime latestAt;

  /// Change since the first entry in the window (null = one entry).
  final double? changeKg;
  final int? overDays;

  /// kg per week over the window (null = entries under a week apart).
  final double? perWeekKg;

  /// One line for the card.
  final String line;

  /// Days since the last weigh-in.
  final int daysSince;

  const WeightTrend({
    required this.latestKg,
    required this.latestAt,
    required this.changeKg,
    required this.overDays,
    required this.perWeekKg,
    required this.line,
    required this.daysSince,
  });

  /// A weekly weigh-in is due.
  bool get due => daysSince >= dueAfterDays;

  static const dueAfterDays = 7;

  /// The pace is measured over this many days back.
  static const windowDays = 35;

  /// Under this many kg a week counts as "holding steady".
  static const steadyKg = 0.2;

  /// Losing faster than this is too fast to last.
  static const fastKg = 1.0;

  static String _kg(double v) => v.abs().toStringAsFixed(1);

  /// Null when there are no entries. [losing] = the user's goal is to
  /// lose weight; [heightCm] guards against chasing a low weight.
  static WeightTrend? of(List<WeightEntry> entries, {required DateTime now, bool losing = false, double? heightCm}) {
    if (entries.isEmpty) return null;
    final sorted = [...entries]..sort((a, b) => a.at.compareTo(b.at));
    final last = sorted.last;
    final window = sorted.where((e) => now.difference(e.at).inDays <= windowDays).toList();
    final first = window.isEmpty ? last : window.first;
    final span = last.at.difference(first.at).inDays;
    final change = identical(first, last) ? null : last.kg - first.kg;
    final perWeek = change == null || span < 7 ? null : change / (span / 7);

    final bmi = Bmi.of(kg: last.kg, cm: heightCm);
    final String line;
    if (bmi != null && Bmi.band(bmi) == BmiBand.under) {
      line = 'You are at a low weight for your height — no need to lose more. Regular meals with protein help.';
    } else if (perWeek == null) {
      line = 'Weigh in once a week, same time of day — morning, before food, works best.';
    } else if (perWeek <= -fastKg) {
      line = 'Down ${_kg(perWeek)} kg a week — faster than lasts. Eat a little more and keep protein up.';
    } else if (perWeek <= -steadyKg) {
      line = losing ? 'Down ${_kg(perWeek)} kg a week — a steady pace that lasts.' : 'Down ${_kg(perWeek)} kg a week.';
    } else if (perWeek < steadyKg) {
      line = losing
          ? 'Holding steady for ${(span / 7).round()} weeks. Plateaus are normal — keep protein up, add a short walk.'
          : 'Holding steady.';
    } else {
      line = losing
          ? 'Up ${_kg(perWeek)} kg a week. Water and salt swing 1–2 kg — watch the trend, not one day.'
          : 'Up ${_kg(perWeek)} kg a week.';
    }
    return WeightTrend(
      latestKg: last.kg,
      latestAt: last.at,
      changeKg: change,
      overDays: change == null ? null : span,
      perWeekKg: perWeek,
      line: line,
      daysSince: now.difference(last.at).inDays.clamp(0, 100000),
    );
  }
}
