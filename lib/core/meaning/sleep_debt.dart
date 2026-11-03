/// Sleep debt: how far the last 7 nights fell short of your sleep need,
/// in total. One short night is noise; a week of 30-minute shortfalls is
/// 3.5 hours — and that's what makes people tired on Friday.
///
/// Net, not gross: a long night pays some back (as research on recovery
/// sleep suggests, only partly — so surplus counts at half). Never below
/// zero ("sleep credit" isn't a thing worth showing). Pure.
library;

class SleepDebt {
  /// Total shortfall in minutes (0 = none).
  final int minutes;

  /// Nights with data among the last 7.
  final int nights;

  /// The nightly need it was measured against.
  final Duration need;

  const SleepDebt({required this.minutes, required this.nights, required this.need});

  /// Fewer known nights than this: no debt shown (too little to say).
  static const minNights = 3;

  /// Debts above this are capped in the wording (data gaps, not reality).
  static const maxShown = 20 * 60;

  /// Extra sleep pays back at this rate.
  static const surplusPayback = 0.5;

  bool get hasDebt => minutes >= 30;

  String get label {
    final m = minutes > maxShown ? maxShown : minutes;
    return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
  }

  /// [nightMinutes]: the last nights' sleep in minutes (null = no data),
  /// any order; only the last 7 entries are used.
  static SleepDebt? of(List<int?> nightMinutes, {required Duration need}) {
    final recent = nightMinutes.length > 7 ? nightMinutes.sublist(nightMinutes.length - 7) : nightMinutes;
    // Under 1 h or over 14 h is almost always bad data.
    final known = recent.whereType<int>().where((m) => m >= 60 && m <= 14 * 60).toList();
    if (known.length < minNights) return null;
    var debt = 0.0;
    for (final m in known) {
      final diff = need.inMinutes - m;
      debt += diff > 0 ? diff : diff * surplusPayback;
    }
    return SleepDebt(minutes: debt <= 0 ? 0 : debt.round(), nights: known.length, need: need);
  }
}
