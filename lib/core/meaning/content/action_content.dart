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

/// What kind of suggestion an action is, so the engine can filter by
/// context without touching the copy itself. An action can carry more
/// than one tag (e.g. a dinner-and-early-night suggestion is both
/// `eveningFood` and `sleep`).
///
/// `daytimeFood` is the one Fasting Companion cares about: on an active
/// fast day, any action naming a daytime meal/snack/chai gets filtered
/// out (see [pickActions]'s `excludeDaytimeFood`) rather than telling
/// someone observing a fast to have lunch.
enum ActionTag { daytimeFood, eveningFood, activity, sleep, breathing, neutral }

class _Action {
  final String text;
  final Set<ActionTag> tags;
  const _Action(this.text, this.tags);
}

class ActionContent {
  const ActionContent._();

  static const Map<RecoveryState, Map<DominantSignal, List<_Action>>>
      _library = {
    RecoveryState.recharged: {
      DominantSignal.none: [
        _Action(
          "Good day for that harder session or the long walk you postponed",
          {ActionTag.activity},
        ),
        _Action(
          "Use the extra energy today — tackle the task you've been "
              'putting off',
          {ActionTag.neutral},
        ),
        _Action(
          'A good day to batch-cook something wholesome for the week — '
              'dal and sabzi now save you tonight',
          {ActionTag.eveningFood},
        ),
      ],
      DominantSignal.temp: [
        _Action(
          'Still a good day to move, but keep a bottle of water within '
              'reach',
          {ActionTag.activity},
        ),
        _Action(
          'Take the workout outdoors if you can — fresh air, easy pace',
          {ActionTag.activity},
        ),
        _Action(
          'Add a slice of lemon to your water today and keep meals light',
          {ActionTag.daytimeFood},
        ),
      ],
    },
    RecoveryState.steady: {
      DominantSignal.none: [
        _Action(
          'Stick with your regular routine today — nothing to change',
          {ActionTag.neutral},
        ),
        _Action(
          'A good day for a simple home-cooked thali and your usual walk',
          {ActionTag.daytimeFood, ActionTag.activity},
        ),
        _Action(
          "Keep tonight's bedtime consistent with your usual",
          {ActionTag.sleep},
        ),
      ],
      DominantSignal.temp: [
        _Action(
          'Keep today low-key — a light khichdi dinner and an early '
              'night',
          {ActionTag.eveningFood, ActionTag.sleep},
        ),
        _Action(
          'Sip water through the day and skip the extra chai today',
          {ActionTag.daytimeFood},
        ),
        _Action(
          'A gentle walk instead of an intense workout today',
          {ActionTag.activity},
        ),
      ],
    },
    RecoveryState.stretched: {
      DominantSignal.hrv: [
        _Action(
          "Swap the gym for a slow walk today — let your body catch up",
          {ActionTag.activity},
        ),
        _Action(
          '10 minutes of slow breathing after dinner — anulom-vilom pace',
          {ActionTag.breathing},
        ),
        _Action(
          'Keep dinner light tonight — moong dal khichdi over something '
              'heavy',
          {ActionTag.eveningFood},
        ),
      ],
      DominantSignal.sleep: [
        _Action(
          'Aim for lights-out 30-45 minutes earlier tonight',
          {ActionTag.sleep},
        ),
        _Action(
          "Skip the afternoon chai — it'll only push bedtime later",
          {ActionTag.daytimeFood},
        ),
        _Action(
          'A 20-minute nap after lunch beats pushing through the '
              'afternoon slump',
          {ActionTag.sleep},
        ),
      ],
      DominantSignal.hr: [
        _Action(
          'Dial back workout intensity — a light walk over a hard '
              'session',
          {ActionTag.activity},
        ),
        _Action(
          'Swap evening chai for haldi doodh or tulsi tea tonight',
          {ActionTag.eveningFood},
        ),
        _Action(
          'Keep dinner early and light tonight — give your body time to '
              'wind down',
          {ActionTag.eveningFood, ActionTag.sleep},
        ),
      ],
      DominantSignal.temp: [
        _Action(
          'Prioritize rest today — keep meals light and hydration up',
          {ActionTag.neutral},
        ),
        _Action(
          'Swap the workout for a slow walk and an early night',
          {ActionTag.activity, ActionTag.sleep},
        ),
        _Action(
          'Keep today unhurried — dal-chawal and an early wind-down',
          {ActionTag.daytimeFood, ActionTag.sleep},
        ),
      ],
      DominantSignal.none: [
        _Action(
          'Ease off the intensity today — a light walk over a hard '
              'session',
          {ActionTag.activity},
        ),
        _Action(
          "Keep tonight's wind-down simple: dim the lights, put the "
              'phone down early',
          {ActionTag.sleep},
        ),
        _Action(
          'A lighter dinner tonight — khichdi or soup over something '
              'heavy',
          {ActionTag.eveningFood},
        ),
      ],
    },
    RecoveryState.rundown: {
      DominantSignal.hrv: [
        _Action(
          'Skip intense training today — a short walk is plenty',
          {ActionTag.activity},
        ),
        _Action(
          'A slow, extended anulom-vilom session before bed tonight',
          {ActionTag.breathing, ActionTag.sleep},
        ),
        _Action(
          'Keep meals simple today — moong dal khichdi is easy on the '
              'body',
          {ActionTag.daytimeFood},
        ),
      ],
      DominantSignal.sleep: [
        _Action(
          'Get to bed earlier tonight — even 30 extra minutes helps',
          {ActionTag.sleep},
        ),
        _Action(
          'Skip the late-night screen time and wind down with a book '
              'instead',
          {ActionTag.sleep},
        ),
        _Action(
          "A short nap today is fine — you're running on a sleep deficit",
          {ActionTag.sleep},
        ),
      ],
      DominantSignal.hr: [
        _Action(
          'Skip the workout today — a short walk is enough',
          {ActionTag.activity},
        ),
        _Action(
          'Swap coffee for tulsi tea today and keep hydration up',
          {ActionTag.daytimeFood},
        ),
        _Action(
          'Keep dinner early and light — give your heart rate room to '
              'settle',
          {ActionTag.eveningFood},
        ),
      ],
      DominantSignal.temp: [
        _Action(
          'Take it easy today — prioritize rest and stay hydrated',
          {ActionTag.neutral},
        ),
        _Action(
          'Keep meals light — khichdi or dal-rice over anything heavy',
          {ActionTag.daytimeFood},
        ),
        _Action(
          'Skip the gym today; a short, slow walk is plenty',
          {ActionTag.activity},
        ),
      ],
      DominantSignal.none: [
        _Action(
          'Skip intense training today and prioritize rest',
          {ActionTag.activity},
        ),
        _Action(
          'Get to bed earlier and keep hydration up through the day',
          {ActionTag.sleep},
        ),
        _Action(
          'Keep today light — simple meals and an early night',
          {ActionTag.sleep},
        ),
      ],
    },
  };

  /// Picks up to [count] deterministic variants for (state, signal).
  /// Falls back to [DominantSignal.none] when there's no dedicated
  /// bucket for the combination (e.g. recharged + hrv). Returns an
  /// empty list for [RecoveryState.learning], which has no bucket —
  /// that state's copy comes from [DailyReadout.learning] instead.
  ///
  /// [excludeDaytimeFood] drops any action tagged [ActionTag.daytimeFood]
  /// before picking — set by [MeaningEngine] when a Fasting Companion
  /// window is active today, so a fasting user never gets told to have
  /// lunch or afternoon chai. Every bucket keeps at least one non-food
  /// variant, so this never empties a bucket out entirely.
  static List<String> pickActions(
    RecoveryState state,
    DominantSignal signal,
    DateTime date, {
    int count = 2,
    bool excludeDaytimeFood = false,
  }) {
    final buckets = _library[state];
    if (buckets == null) return const [];
    final variants =
        buckets[signal] ?? buckets[DominantSignal.none] ?? const [];
    if (variants.isEmpty) return const [];

    final eligible = excludeDaytimeFood
        ? variants.where((a) => !a.tags.contains(ActionTag.daytimeFood)).toList()
        : variants;
    if (eligible.isEmpty) return const [];

    return [
      for (var i = 0; i < count && i < eligible.length; i++)
        eligible[(date.day + i) % eligible.length].text,
    ];
  }

  /// Every string in the library, flattened — for the forbidden-words
  /// content scan. Not used by the engine itself.
  static List<String> get allStrings => _library.values
      .expand((bySignal) => bySignal.values)
      .expand((variants) => variants)
      .map((a) => a.text)
      .toList();
}
