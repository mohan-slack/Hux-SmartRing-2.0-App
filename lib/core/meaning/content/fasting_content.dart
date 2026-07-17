/// HUX Fasting Companion — Content Library
/// -----------------------------------------
/// Extra, context-aware copy shown in today's readout while a Fasting
/// lifestyle mode is active (Roza, Navratri, Ekadashi, Karwa Chauth, or
/// a custom observance) — layered in by [ReadoutService], never by
/// [MeaningEngine] itself (see the doc comment on `evaluate`'s
/// `excludeDaytimeFood` parameter for why the pure engine stays generic).
///
/// Pure Dart, same conventions as Desi Plate: deterministic by
/// `date.day`, wellness wording only.
///
/// Hard rule, specific to this pack (enforced by the guardrail scan in
/// test/fasting_content_test.dart, not by code): NEVER advises
/// breaking, shortening, or skipping the fast, and never uses fear
/// language about fasting. Any "check with your doctor"-style phrasing
/// must stay generic and calm — this pack doesn't use that phrasing at
/// all, since there's nothing here that would call for it.
///
/// Roza gets its own suhoor/sehri-specific sleep-honesty copy, since
/// that's a real, named part of the observance; every other bucket
/// (and every other fast type's sleep-honesty variant) stays generic
/// enough to share across types — "your fast" + [FastTypeDisplay].

import '../../modes/mode.dart';

class FastingContent {
  const FastingContent._();

  static String _hour12(int hour24) {
    final period = hour24 >= 12 ? 'pm' : 'am';
    var h = hour24 % 12;
    if (h == 0) h = 12;
    return '$h$period';
  }

  /// Suhoor/sehri disruption is normal — Roza gets the specific term,
  /// every other fast type gets the generic equivalent.
  static String pickSleepHonesty(FastType type, DateTime date) {
    final variants = type == FastType.roza
        ? const [
            'A broken night around suhoor is normal — a short afternoon '
                'rest can help make up the difference',
            "Sehri disrupts sleep for most people — an afternoon nap "
                "isn't cheating, it's the smart move during Roza",
            "If suhoor is cutting your sleep short, that's expected "
                'during Roza — protect your afternoon rest instead',
          ]
        : [
            'Broken sleep around ${type.displayName} hours is normal — a '
                'short afternoon rest can help make up the difference',
            "If ${type.displayName} is disrupting your usual sleep, an "
                "afternoon nap isn't cheating — it's the smart move",
            'Disrupted sleep is common during ${type.displayName} — '
                'lean on an afternoon rest instead of pushing through',
          ];
    return variants[date.day % variants.length];
  }

  /// Hydration guidance, relative to the eating window when the user
  /// has set one.
  static String pickHydration(
    FastType type,
    DateTime date, {
    int? eatingWindowStartHour,
    int? eatingWindowEndHour,
  }) {
    final hasWindow = eatingWindowStartHour != null && eatingWindowEndHour != null;
    final variants = hasWindow
        ? [
            'Once your eating window opens at ${_hour12(eatingWindowStartHour)}, '
                'sip water steadily rather than all at once',
            'Spread your hydration across the '
                '${_hour12(eatingWindowStartHour)}–${_hour12(eatingWindowEndHour)} '
                'window instead of front-loading it all right away',
            'Use the ${_hour12(eatingWindowStartHour)}–'
                '${_hour12(eatingWindowEndHour)} window to rehydrate '
                'steadily, not just at the very start',
          ]
        : [
            'Prioritize water and something light as soon as your fast '
                'opens for the day',
            'Rehydrate steadily once you can eat again — little and '
                'often beats one large glass',
            'Keep something to drink within reach for as soon as '
                '${type.displayName} allows it',
          ];
    return variants[date.day % variants.length];
  }

  /// Gentle energy pacing, no guilt about lower energy.
  static String pickPacing(FastType type, DateTime date) {
    final variants = [
      'Lower energy today is expected during ${type.displayName} — pace '
          'your afternoon instead of pushing through it',
      "However today feels, that's normal for ${type.displayName} — go "
          'at whatever pace your body asks for',
      'Ease off anything strenuous today and let ${type.displayName} '
          'set the pace, not your usual routine',
    ];
    return variants[date.day % variants.length];
  }

  /// Wind-down guidance for the evening.
  static String pickWindDown(FastType type, DateTime date) {
    final variants = [
      'Keep tonight calm and unhurried — an early wind-down helps make '
          'up for a disrupted sleep schedule',
      'A quiet, early night tonight goes a long way during '
          '${type.displayName}',
      'Wind down early tonight — your body is doing extra work during '
          '${type.displayName}',
    ];
    return variants[date.day % variants.length];
  }

  /// Day-N acknowledgement — reads the numbers as reflecting the
  /// observance, never as a problem.
  static String pickDayAcknowledgement(
      FastType type, int dayNumber, DateTime date) {
    final variants = [
      'Day $dayNumber of ${type.displayName} — your numbers reflect the '
          'observance, not a problem',
      "You're $dayNumber day${dayNumber == 1 ? '' : 's'} into "
          '${type.displayName} — steady is the goal, not your usual '
          'pace',
      "Day $dayNumber — however today's numbers read, that's normal "
          'for ${type.displayName}',
    ];
    return variants[date.day % variants.length];
  }

  /// One deterministic pick across all five categories — what
  /// [ReadoutService] actually slots into today's readout.
  static String pickForDay(
    FastType type,
    int dayNumber,
    DateTime date, {
    int? eatingWindowStartHour,
    int? eatingWindowEndHour,
  }) {
    final options = [
      pickSleepHonesty(type, date),
      pickHydration(type, date,
          eatingWindowStartHour: eatingWindowStartHour,
          eatingWindowEndHour: eatingWindowEndHour),
      pickPacing(type, date),
      pickWindDown(type, date),
      pickDayAcknowledgement(type, dayNumber, date),
    ];
    return options[date.day % options.length];
  }

  /// Every string this pack can produce, flattened — for the
  /// forbidden-words and break-the-fast content scans. Not used by
  /// [pickForDay] itself.
  static List<String> get allStrings {
    final strings = <String>[];
    for (final type in FastType.values) {
      for (var day = 1; day <= 3; day++) {
        final date = DateTime(2026, 1, day);
        strings.add(pickSleepHonesty(type, date));
        strings.add(pickHydration(type, date));
        strings.add(pickHydration(type, date,
            eatingWindowStartHour: 18, eatingWindowEndHour: 4));
        strings.add(pickPacing(type, date));
        strings.add(pickWindDown(type, date));
        strings.add(pickDayAcknowledgement(type, day, date));
      }
    }
    return strings;
  }
}
