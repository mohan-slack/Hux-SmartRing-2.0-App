/// Tonight's timing, worked back from the target bedtime:
/// - Last chai / coffee: 8 h before bed. Caffeine's half-life is ~5 h,
///   so a 4 PM chai is still half-active at 9 PM; most sleep guidance
///   says stop at least 6–8 h before bed. Never later than 4 PM for an
///   evening bedtime.
/// - Last big meal: 2 h 30 before bed (lying down full makes sleep
///   lighter and reflux likelier).
/// - Screens away: 30 min before bed.
/// Pure: give it the bedtime, get times back.
library;

class EveningTiming {
  final DateTime lastCaffeine;
  final DateTime lastMeal;
  final DateTime screensOff;
  final DateTime bed;

  const EveningTiming({required this.lastCaffeine, required this.lastMeal, required this.screensOff, required this.bed});

  static const caffeineBefore = Duration(hours: 8);
  static const mealBefore = Duration(hours: 2, minutes: 30);
  static const screensBefore = Duration(minutes: 30);

  /// Latest caffeine cut-off for a normal (evening/night) bedtime.
  static const latestCaffeineHour = 16;

  factory EveningTiming.forBed(DateTime bed) {
    var caffeine = bed.subtract(caffeineBefore);
    // Evening/night bedtime (6 PM–5 AM): cap the cut-off at 4 PM that day.
    final eveningBed = bed.hour >= 18 || bed.hour < 5;
    if (eveningBed && caffeine.hour >= latestCaffeineHour && caffeine.hour < 22) {
      caffeine = DateTime(caffeine.year, caffeine.month, caffeine.day, latestCaffeineHour);
    }
    return EveningTiming(
      lastCaffeine: caffeine,
      lastMeal: bed.subtract(mealBefore),
      screensOff: bed.subtract(screensBefore),
      bed: bed,
    );
  }
}
