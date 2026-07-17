/// Tests for the Desi Plate content library. Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/meaning/content/action_content.dart';
import 'package:hux_app/core/meaning/daily_readout.dart';

const _forbiddenWords = [
  'diagnos', // diagnose, diagnosis, diagnostic
  'disease',
  'illness',
  'infection',
  'sick',
  'fever',
  'condition',
  'symptom',
  'disorder',
  'medical',
];

void main() {
  group('Determinism', () {
    test('the same date always picks the same variants', () {
      final date = DateTime(2026, 7, 16);
      final first = ActionContent.pickActions(
          RecoveryState.stretched, DominantSignal.hrv, date);
      final second = ActionContent.pickActions(
          RecoveryState.stretched, DominantSignal.hrv, date);

      expect(second, equals(first));
    });

    test('two different DateTime instances on the same day-of-month match',
        () {
      final a = ActionContent.pickActions(RecoveryState.rundown,
          DominantSignal.hr, DateTime(2026, 3, 16, 8, 0));
      final b = ActionContent.pickActions(RecoveryState.rundown,
          DominantSignal.hr, DateTime(2026, 9, 16, 22, 45));

      expect(a, equals(b),
          reason: 'the variant seed is date.day, by design (see the file '
              'doc comment on the day-of-month trade-off)');
    });
  });

  group('Variety', () {
    test('consecutive dates pick different variants for the same bucket',
        () {
      final day1 = ActionContent.pickActions(
          RecoveryState.rundown, DominantSignal.sleep, DateTime(2026, 7, 16));
      final day2 = ActionContent.pickActions(
          RecoveryState.rundown, DominantSignal.sleep, DateTime(2026, 7, 17));

      expect(day1, isNot(equals(day2)));
    });

    test('the two picked actions are never duplicates of each other', () {
      for (var day = 1; day <= 28; day++) {
        final picks = ActionContent.pickActions(
            RecoveryState.stretched, DominantSignal.hr, DateTime(2026, 7, day));
        expect(picks.toSet().length, picks.length,
            reason: 'day $day picked duplicate actions: $picks');
      }
    });
  });

  group('Fallback', () {
    test('a state/signal combo with no dedicated bucket falls back to none',
        () {
      final date = DateTime(2026, 7, 16);
      final picks = ActionContent.pickActions(
          RecoveryState.recharged, DominantSignal.hrv, date);
      final fallback = ActionContent.pickActions(
          RecoveryState.recharged, DominantSignal.none, date);

      expect(picks, equals(fallback));
    });

    test('learning has no action bucket and returns nothing, never throws',
        () {
      final picks = ActionContent.pickActions(
          RecoveryState.learning, DominantSignal.none, DateTime(2026, 7, 16));

      expect(picks, isEmpty);
    });
  });

  group('Content register', () {
    test('the entire library is free of medical/diagnostic language', () {
      for (final text in ActionContent.allStrings) {
        final lower = text.toLowerCase();
        for (final word in _forbiddenWords) {
          expect(lower.contains(word), isFalse,
              reason: '"$word" reads as medical/diagnostic, found in: $text');
        }
      }
    });

    test('is a substantial, non-duplicated library', () {
      final all = ActionContent.allStrings;
      expect(all.length, greaterThanOrEqualTo(30));
      expect(all.toSet().length, all.length,
          reason: 'every action should be distinct copy, not a repeat');
    });

    test('never advises breaking a fast', () {
      for (final text in ActionContent.allStrings) {
        expect(text.toLowerCase().contains('break your fast'), isFalse);
        expect(text.toLowerCase().contains('break a fast'), isFalse);
      }
    });
  });

  group('Fasting Companion filter (excludeDaytimeFood)', () {
    // Every string this codebase tags ActionTag.daytimeFood — a fasting
    // user must never see one of these picked for them.
    const daytimeFoodTexts = [
      'Add a slice of lemon to your water today and keep meals light',
      'A good day for a simple home-cooked thali and your usual walk',
      'Sip water through the day and skip the extra chai today',
      "Skip the afternoon chai — it'll only push bedtime later",
      'Keep today unhurried — dal-chawal and an early wind-down',
      'Keep meals simple today — moong dal khichdi is easy on the body',
      'Swap coffee for tulsi tea today and keep hydration up',
      'Keep meals light — khichdi or dal-rice over anything heavy',
    ];

    test('no daytime-food action is ever picked when excluded, across '
        'every state, signal, and day of the month', () {
      for (final state in RecoveryState.values) {
        if (state == RecoveryState.learning) continue;
        for (final signal in DominantSignal.values) {
          for (var day = 1; day <= 31; day++) {
            final picks = ActionContent.pickActions(
                state, signal, DateTime(2026, 1, day),
                excludeDaytimeFood: true);
            for (final pick in picks) {
              expect(daytimeFoodTexts, isNot(contains(pick)),
                  reason: '$state/$signal/day $day picked a daytime-food '
                      'action while excludeDaytimeFood was true: $pick');
            }
          }
        }
      }
    });

    test('filtering never empties a bucket out entirely', () {
      for (final state in RecoveryState.values) {
        if (state == RecoveryState.learning) continue;
        for (final signal in DominantSignal.values) {
          final picks = ActionContent.pickActions(
              state, signal, DateTime(2026, 7, 16),
              excludeDaytimeFood: true);
          expect(picks, isNotEmpty, reason: '$state/$signal');
        }
      }
    });

    test('without the flag, daytime-food actions can still appear '
        '(the library is unfiltered by default)', () {
      final everAppears = List.generate(31, (i) => i + 1).any((day) {
        final picks = ActionContent.pickActions(
            RecoveryState.steady, DominantSignal.temp, DateTime(2026, 1, day));
        return picks.any(daytimeFoodTexts.contains);
      });
      expect(everAppears, isTrue,
          reason: 'steady/temp has a daytime-food variant that should '
              'surface on some day when not excluded');
    });
  });
}
