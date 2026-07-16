/// HUX Desi Plate — Action Content Library
/// -----------------------------------------
/// Concrete, doable-today suggestions in an Indian, vegetarian-first
/// register. Pure Dart — no Flutter, no I/O, no randomness. This is the
/// only file [MeaningEngine] pulls action text from.
///
/// Content rules (enforced by review + the forbidden-words test that
/// scans every string in this file, not by code):
/// - Vegetarian-first food examples only.
/// - No supplement or food "boosts immunity"-style efficacy claims.
/// - Never advises breaking a fast.
/// - Wellness wording only — same medical-language ban as the rest of
///   the app.
///
/// Variant selection is deterministic, seeded by `date.day` (1-31):
/// the same calendar day always picks the same variants, and the next
/// day's index shifts by one, so consecutive days read differently.
/// Trade-off, accepted for v1: two dates with the same day-of-month
/// (e.g. Jan 15 and Feb 15) pick the same variant — day-of-month is
/// the seed on purpose, not the full date, per product spec.

import '../daily_readout.dart';

/// The signal most worth talking about today. `none` covers a state
/// with no single standout negative signal — a good day, or a
/// stretched/rundown day driven by several mild signals together.
enum DominantSignal { hrv, sleep, hr, temp, none }

class ActionContent {
  const ActionContent._();

  static const Map<RecoveryState, Map<DominantSignal, List<String>>>
      _library = {
    RecoveryState.recharged: {
      DominantSignal.none: [
        "Good day for that harder session or the long walk you postponed",
        "Use the extra energy today — tackle the task you've been "
            'putting off',
        'A good day to batch-cook something wholesome for the week — '
            'dal and sabzi now save you tonight',
      ],
      DominantSignal.temp: [
        'Still a good day to move, but keep a bottle of water within '
            'reach',
        'Take the workout outdoors if you can — fresh air, easy pace',
        'Add a slice of lemon to your water today and keep meals light',
      ],
    },
    RecoveryState.steady: {
      DominantSignal.none: [
        'Stick with your regular routine today — nothing to change',
        'A good day for a simple home-cooked thali and your usual walk',
        "Keep tonight's bedtime consistent with your usual",
      ],
      DominantSignal.temp: [
        'Keep today low-key — a light khichdi dinner and an early '
            'night',
        'Sip water through the day and skip the extra chai today',
        'A gentle walk instead of an intense workout today',
      ],
    },
    RecoveryState.stretched: {
      DominantSignal.hrv: [
        "Swap the gym for a slow walk today — let your body catch up",
        '10 minutes of slow breathing after dinner — anulom-vilom pace',
        'Keep dinner light tonight — moong dal khichdi over something '
            'heavy',
      ],
      DominantSignal.sleep: [
        'Aim for lights-out 30-45 minutes earlier tonight',
        "Skip the afternoon chai — it'll only push bedtime later",
        'A 20-minute nap after lunch beats pushing through the '
            'afternoon slump',
      ],
      DominantSignal.hr: [
        'Dial back workout intensity — a light walk over a hard '
            'session',
        'Swap evening chai for haldi doodh or tulsi tea tonight',
        'Keep dinner early and light tonight — give your body time to '
            'wind down',
      ],
      DominantSignal.temp: [
        'Prioritize rest today — keep meals light and hydration up',
        'Swap the workout for a slow walk and an early night',
        'Keep today unhurried — dal-chawal and an early wind-down',
      ],
      DominantSignal.none: [
        'Ease off the intensity today — a light walk over a hard '
            'session',
        "Keep tonight's wind-down simple: dim the lights, put the "
            'phone down early',
        'A lighter dinner tonight — khichdi or soup over something '
            'heavy',
      ],
    },
    RecoveryState.rundown: {
      DominantSignal.hrv: [
        'Skip intense training today — a short walk is plenty',
        'A slow, extended anulom-vilom session before bed tonight',
        'Keep meals simple today — moong dal khichdi is easy on the '
            'body',
      ],
      DominantSignal.sleep: [
        'Get to bed earlier tonight — even 30 extra minutes helps',
        'Skip the late-night screen time and wind down with a book '
            'instead',
        "A short nap today is fine — you're running on a sleep deficit",
      ],
      DominantSignal.hr: [
        'Skip the workout today — a short walk is enough',
        'Swap coffee for tulsi tea today and keep hydration up',
        'Keep dinner early and light — give your heart rate room to '
            'settle',
      ],
      DominantSignal.temp: [
        'Take it easy today — prioritize rest and stay hydrated',
        'Keep meals light — khichdi or dal-rice over anything heavy',
        'Skip the gym today; a short, slow walk is plenty',
      ],
      DominantSignal.none: [
        'Skip intense training today and prioritize rest',
        'Get to bed earlier and keep hydration up through the day',
        'Keep today light — simple meals and an early night',
      ],
    },
  };

  /// Picks up to [count] deterministic variants for (state, signal).
  /// Falls back to [DominantSignal.none] when there's no dedicated
  /// bucket for the combination (e.g. recharged + hrv). Returns an
  /// empty list for [RecoveryState.learning], which has no bucket —
  /// that state's copy comes from [DailyReadout.learning] instead.
  static List<String> pickActions(
    RecoveryState state,
    DominantSignal signal,
    DateTime date, {
    int count = 2,
  }) {
    final buckets = _library[state];
    if (buckets == null) return const [];
    final variants =
        buckets[signal] ?? buckets[DominantSignal.none] ?? const [];
    if (variants.isEmpty) return const [];

    return [
      for (var i = 0; i < count && i < variants.length; i++)
        variants[(date.day + i) % variants.length],
    ];
  }

  /// Every string in the library, flattened — for the forbidden-words
  /// content scan. Not used by the engine itself.
  static List<String> get allStrings => _library.values
      .expand((bySignal) => bySignal.values)
      .expand((variants) => variants)
      .toList();
}
