/// Tests for the event mode content library. Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/meaning/daily_readout.dart';
import 'package:hux_app/core/modes/content/event_content.dart';
import 'package:hux_app/core/modes/mode.dart';

const _forbiddenWords = [
  // Medical/diagnostic — same ban as the rest of the app.
  'diagnos', 'disease', 'illness', 'infection', 'sick', 'fever',
  'condition', 'symptom', 'disorder', 'medical',
  // Overpromising.
  'guarantee',
  // Fasting is the NEXT phase — must not appear yet.
  'fasting', 'vrat', 'upvas', 'roza', 'ekadashi',
];

const _appearanceWeightWords = [
  'slim', 'weight', 'skinny', 'figure', 'beautiful', 'handsome',
  'attractive', 'gorgeous', 'chubby', 'overweight',
];

void main() {
  group('Determinism', () {
    test('the same date always picks the same phase action', () {
      final date = DateTime(2026, 7, 16);
      final a = EventContent.pickPhaseAction(
          ModeId.shaadi, EventPhase.build, date);
      final b = EventContent.pickPhaseAction(
          ModeId.shaadi, EventPhase.build, date);
      expect(a, equals(b));
    });

    test('the same date always picks the same day-zero action', () {
      final date = DateTime(2026, 7, 16);
      final a = EventContent.pickDayZeroAction(
          ModeId.examSeason, RecoveryState.steady, date);
      final b = EventContent.pickDayZeroAction(
          ModeId.examSeason, RecoveryState.steady, date);
      expect(a, equals(b));
    });

    test('the same date always picks the same wrap-up', () {
      final date = DateTime(2026, 7, 16);
      final a = EventContent.pickWrapUp(ModeId.bigDay, date);
      final b = EventContent.pickWrapUp(ModeId.bigDay, date);
      expect(a, equals(b));
    });
  });

  group('Variety', () {
    test('consecutive dates pick different phase actions', () {
      final day1 = EventContent.pickPhaseAction(
          ModeId.examSeason, EventPhase.taper, DateTime(2026, 7, 16));
      final day2 = EventContent.pickPhaseAction(
          ModeId.examSeason, EventPhase.taper, DateTime(2026, 7, 17));
      expect(day1, isNot(equals(day2)));
    });

    test('day-zero action differs by readiness bucket', () {
      final date = DateTime(2026, 7, 16);
      final ready = EventContent.pickDayZeroAction(
          ModeId.shaadi, RecoveryState.recharged, date);
      final gentle = EventContent.pickDayZeroAction(
          ModeId.shaadi, RecoveryState.rundown, date);
      final neutral = EventContent.pickDayZeroAction(
          ModeId.shaadi, RecoveryState.learning, date);

      expect(ready, isNot(equals(gentle)));
      expect(ready, isNot(equals(neutral)));
      expect(gentle, isNot(equals(neutral)));
    });

    test('recharged and steady share the same "ready" bucket', () {
      final date = DateTime(2026, 7, 16);
      final recharged = EventContent.pickDayZeroAction(
          ModeId.bigDay, RecoveryState.recharged, date);
      final steady = EventContent.pickDayZeroAction(
          ModeId.bigDay, RecoveryState.steady, date);
      expect(recharged, equals(steady));
    });
  });

  group('Coverage', () {
    test('every mode has 3+ variants for every phase', () {
      for (final id in ModeId.values) {
        for (final phase in EventPhase.values) {
          final variants = <String>{
            for (var day = 1; day <= 3; day++)
              EventContent.pickPhaseAction(id, phase, DateTime(2026, 1, day)),
          };
          expect(variants.length, greaterThanOrEqualTo(3),
              reason: '$id / $phase should have at least 3 distinct '
                  'variants over 3 consecutive days');
        }
      }
    });

    test('every mode has content for every readiness bucket', () {
      for (final id in ModeId.values) {
        for (final state in RecoveryState.values) {
          if (state == RecoveryState.learning) continue;
          final action = EventContent.pickDayZeroAction(
              id, state, DateTime(2026, 7, 16));
          expect(action, isNotEmpty, reason: '$id / $state');
        }
      }
    });

    test('every mode has a wrap-up', () {
      for (final id in ModeId.values) {
        expect(EventContent.pickWrapUp(id, DateTime(2026, 7, 16)), isNotEmpty);
      }
    });
  });

  group('Content register', () {
    test('the entire library is free of medical, overpromising, and '
        'fasting language', () {
      for (final text in EventContent.allStrings) {
        final lower = text.toLowerCase();
        for (final word in _forbiddenWords) {
          expect(lower.contains(word), isFalse,
              reason: '"$word" found in: $text');
        }
      }
    });

    test('is free of appearance/weight language — the shaadi guardrail',
        () {
      for (final text in EventContent.allStrings) {
        final lower = text.toLowerCase();
        for (final word in _appearanceWeightWords) {
          expect(lower.contains(word), isFalse,
              reason: '"$word" reads as appearance/weight talk, found '
                  'in: $text');
        }
      }
    });

    test('is a substantial, non-duplicated library', () {
      final all = EventContent.allStrings;
      expect(all.length, greaterThanOrEqualTo(60));
      expect(all.toSet().length, all.length,
          reason: 'every action should be distinct copy, not a repeat');
    });
  });

  group('Big Day is event-agnostic', () {
    test('never assumes the event is an exam/study occasion', () {
      const studyWords = ['material', 'exam', 'study', 'revision', 'syllabus'];
      for (var day = 1; day <= 31; day++) {
        final date = DateTime(2026, 1, day);
        final strings = [
          EventContent.pickPhaseAction(ModeId.bigDay, EventPhase.foundation, date),
          EventContent.pickPhaseAction(ModeId.bigDay, EventPhase.build, date),
          EventContent.pickPhaseAction(ModeId.bigDay, EventPhase.taper, date),
          EventContent.pickPhaseAction(ModeId.bigDay, EventPhase.eve, date),
          EventContent.pickWrapUp(ModeId.bigDay, date),
          for (final state in RecoveryState.values)
            if (state != RecoveryState.learning)
              EventContent.pickDayZeroAction(ModeId.bigDay, state, date),
        ];
        for (final text in strings) {
          final lower = text.toLowerCase();
          for (final word in studyWords) {
            expect(lower.contains(word), isFalse,
                reason: '"$word" reads as exam-specific, found in: $text');
          }
        }
      }
    });

    test('reads correctly for a birthday, wedding function, interview, '
        'or match — a presentation-and-preparation register, not '
        'academic', () {
      final text = EventContent.pickPhaseAction(
          ModeId.bigDay, EventPhase.foundation, DateTime(2026, 1, 3));
      expect(text, isNot(contains('the material')));
    });
  });
}
