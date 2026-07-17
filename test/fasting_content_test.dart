/// Tests for the Fasting Companion content library. Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/meaning/content/fasting_content.dart';
import 'package:hux_app/core/modes/mode.dart';

const _forbiddenWords = [
  // Medical/diagnostic — same ban as the rest of the app.
  'diagnos', 'disease', 'illness', 'infection', 'sick', 'fever',
  'condition', 'symptom', 'disorder', 'medical',
  // Overpromising.
  'guarantee',
];

// The hard, fasting-specific rule: never advise breaking, shortening,
// or skipping the fast, and no fear language about it.
const _breakTheFastPhrases = [
  'break your fast',
  'break the fast',
  'skip your fast',
  'skip the fast',
  'shorten your fast',
  'end your fast early',
  'eat something',
  "you shouldn't fast",
  'stop fasting',
];

void main() {
  group('Determinism', () {
    test('the same date always picks the same category strings', () {
      final date = DateTime(2026, 3, 5);
      expect(
        FastingContent.pickSleepHonesty(FastType.roza, date),
        FastingContent.pickSleepHonesty(FastType.roza, date),
      );
      expect(
        FastingContent.pickDayAcknowledgement(FastType.roza, 5, date),
        FastingContent.pickDayAcknowledgement(FastType.roza, 5, date),
      );
    });
  });

  group('Variety', () {
    test('consecutive dates pick different sleep-honesty variants', () {
      final a = FastingContent.pickSleepHonesty(
          FastType.roza, DateTime(2026, 3, 5));
      final b = FastingContent.pickSleepHonesty(
          FastType.roza, DateTime(2026, 3, 6));
      expect(a, isNot(equals(b)));
    });

    test('Roza gets suhoor/sehri-specific sleep-honesty copy', () {
      final text =
          FastingContent.pickSleepHonesty(FastType.roza, DateTime(2026, 3, 5));
      expect(
        text.toLowerCase(),
        anyOf(contains('suhoor'), contains('sehri')),
      );
    });

    test('non-Roza types share generic, displayName-based phrasing', () {
      for (final type in FastType.values) {
        if (type == FastType.roza) continue;
        final text = FastingContent.pickSleepHonesty(type, DateTime(2026, 3, 5));
        expect(text.toLowerCase().contains('suhoor'), isFalse);
        expect(text.toLowerCase().contains('sehri'), isFalse);
        expect(text.contains(type.displayName), isTrue,
            reason: '$type sleep-honesty copy should name the fast '
                'generically: $text');
      }
    });
  });

  group('Hydration guidance', () {
    test('mentions the eating-window hours when one is set', () {
      final withWindow = FastingContent.pickHydration(
        FastType.roza,
        DateTime(2026, 3, 5),
        eatingWindowStartHour: 18,
        eatingWindowEndHour: 4,
      );
      expect(withWindow, contains('6pm'));
    });

    test('falls back to generic guidance with no window set', () {
      final noWindow =
          FastingContent.pickHydration(FastType.roza, DateTime(2026, 3, 5));
      expect(noWindow.contains('pm'), isFalse);
      expect(noWindow.contains('am'), isFalse);
    });

    test('the two variants differ for the same date', () {
      final date = DateTime(2026, 3, 5);
      final withWindow = FastingContent.pickHydration(FastType.roza, date,
          eatingWindowStartHour: 18, eatingWindowEndHour: 4);
      final withoutWindow = FastingContent.pickHydration(FastType.roza, date);
      expect(withWindow, isNot(equals(withoutWindow)));
    });
  });

  group('Day acknowledgement', () {
    test('names the day number and the fast, never as a problem', () {
      final text = FastingContent.pickDayAcknowledgement(
          FastType.navratri, 4, DateTime(2026, 9, 25));
      expect(text, contains('4'));
      expect(text, contains('Navratri fast'));
    });
  });

  group('pickForDay', () {
    test('always returns something non-empty for every fast type', () {
      for (final type in FastType.values) {
        final text = FastingContent.pickForDay(type, 3, DateTime(2026, 3, 5));
        expect(text, isNotEmpty);
      }
    });
  });

  group('Content register', () {
    test('the entire pack is free of medical and overpromising language',
        () {
      for (final text in FastingContent.allStrings) {
        final lower = text.toLowerCase();
        for (final word in _forbiddenWords) {
          expect(lower.contains(word), isFalse,
              reason: '"$word" found in: $text');
        }
      }
    });

    test('never advises breaking, shortening, or skipping the fast', () {
      for (final text in FastingContent.allStrings) {
        final lower = text.toLowerCase();
        for (final phrase in _breakTheFastPhrases) {
          expect(lower.contains(phrase), isFalse,
              reason: '"$phrase" found in: $text');
        }
      }
    });

    test('is a substantial library', () {
      final all = FastingContent.allStrings;
      expect(all.length, greaterThanOrEqualTo(15));
      // Unlike Desi Plate / Event Content, this pack deliberately shares
      // generic phrasing across fast types ("Navratri/Ekadashi phrasing
      // kept generic enough to share") — so duplication across types is
      // expected, not a bug. Just check there's real variety, not that
      // every single string is unique.
      expect(all.toSet().length, greaterThanOrEqualTo(10));
    });
  });
}
