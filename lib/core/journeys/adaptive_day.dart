/// Adaptive journey days: the plan bends to today's body.
///
/// - Charge under [AdaptiveDay.moveBelow]: offer to MOVE today's workout
///   to tomorrow and do easy recovery now ("Legs & balance moved to
///   tomorrow"). Never on challenge days, never twice in a row.
/// - Charge under [AdaptiveDay.lighterBelow] (or a short night): a lighter
///   version — one round fewer, a little more rest.
///
/// Pure: no Flutter, no I/O.
library;

import 'journey_models.dart';

enum AdaptKind { move, lighter }

class DayAdapt {
  final AdaptKind kind;

  /// One line for the card: why HUX suggests this.
  final String note;

  /// What the button does, in plain words.
  final String action;

  const DayAdapt({required this.kind, required this.note, required this.action});
}

class AdaptiveDay {
  AdaptiveDay._();

  static const moveBelow = 30;
  static const lighterBelow = 50;

  /// [w] with one round fewer (min 1) and +10 s rest between moves.
  /// Same moves, so the user still "did the day".
  static Workout lighter(Workout w) {
    List<MoveStep> rest(List<MoveStep> steps) => [
          for (final s in steps)
            MoveStep(s.moveId, seconds: s.seconds, reps: s.reps, restSeconds: s.restSeconds == 0 ? 0 : s.restSeconds + 10),
        ];
    return Workout(
      title: w.title,
      warmup: w.warmup,
      main: rest(w.main),
      rounds: w.rounds > 1 ? w.rounds - 1 : 1,
      cooldown: w.cooldown,
    );
  }

  /// True when a lighter version changes anything.
  static bool canLighten(Workout w) => w.rounds > 1;

  /// The suggestion for today, or null when the plan stands.
  ///
  /// [canMove] = the service allows moving today (not a challenge or
  /// recovery day, tomorrow isn't a challenge, not moved yesterday).
  static DayAdapt? suggest({
    required Workout planned,
    required int? charge,
    bool shortSleep = false,
    required bool canMove,
  }) {
    if (charge == null && !shortSleep) return null;
    final c = charge ?? 100;
    if (c < moveBelow && canMove) {
      return DayAdapt(
        kind: AdaptKind.move,
        note: 'Charge $c — your body is asking for an easy day. '
            'Do gentle recovery now; ${planned.title} moves to tomorrow.',
        action: 'Move to tomorrow',
      );
    }
    if ((c < lighterBelow || shortSleep) && canLighten(planned)) {
      final why = charge != null && c < lighterBelow ? 'Charge $c' : 'Short night';
      return DayAdapt(
        kind: AdaptKind.lighter,
        note: '$why — a lighter version: ${planned.rounds - 1} round${planned.rounds - 1 == 1 ? '' : 's'} '
            'instead of ${planned.rounds}, a bit more rest. Still counts.',
        action: 'Use lighter version',
      );
    }
    return null;
  }
}
