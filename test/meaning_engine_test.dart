/// Tests for [MeaningEngine]. Run with: flutter test
///
/// The engine is pure Dart, so every test constructs its inputs by hand
/// rather than syncing from a ring — that's the point.

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/meaning/baseline.dart';
import 'package:hux_app/core/meaning/daily_readout.dart';
import 'package:hux_app/core/meaning/meaning_engine.dart';
import 'package:hux_app/core/ring/ring_models.dart';

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

void _expectNoMedicalLanguage(DailyReadout r) {
  final text = ('${r.headline} ${r.meaning} ${r.actions.join(' ')}')
      .toLowerCase();
  for (final word in _forbiddenWords) {
    expect(text.contains(word), isFalse,
        reason: '"$word" reads as medical/diagnostic, found in: $text');
  }
}

void main() {
  const engine = MeaningEngine();
  final today = DateTime(2026, 7, 16);

  // A well-established baseline: 14 days of history, unremarkable numbers.
  const baseline = PersonalBaseline(
    medianHrvMs: 50,
    medianRestingHeartRateBpm: 60,
    medianTotalSleep: Duration(minutes: 420),
    medianSkinTempCelsius: 33.6,
    daysOfData: 14,
  );

  SleepSession night({
    required List<MapEntry<SleepStage, Duration>> stagePlan,
    int? avgHrv,
    int? avgHr,
    double? avgTemp,
  }) {
    final bedtime = DateTime(2026, 7, 15, 23);
    var cursor = bedtime;
    final segments = <SleepSegment>[];
    for (final entry in stagePlan) {
      final end = cursor.add(entry.value);
      segments.add(SleepSegment(start: cursor, end: end, stage: entry.key));
      cursor = end;
    }
    return SleepSession(
      bedtime: bedtime,
      wakeTime: cursor,
      segments: segments,
      avgHrvMs: avgHrv,
      avgHeartRateBpm: avgHr,
      avgSkinTempCelsius: avgTemp,
    );
  }

  group('Insufficient baseline', () {
    test('fewer than 3 days of history returns the learning state', () {
      const thin = PersonalBaseline(
        medianHrvMs: 50,
        medianRestingHeartRateBpm: 60,
        medianTotalSleep: Duration(minutes: 420),
        medianSkinTempCelsius: 33.6,
        daysOfData: 2,
      );
      final readout = engine.evaluate(
        date: today,
        baseline: thin,
        lastNight: null,
        todaySnapshots: const [],
      );

      expect(readout.state, RecoveryState.learning);
      expect(readout.dataQuality, DataQuality.sparse);
      _expectNoMedicalLanguage(readout);
    });
  });

  group('Great night', () {
    test('HRV above baseline and full sleep reads as recharged or steady',
        () {
      final lastNight = night(
        stagePlan: [
          const MapEntry(SleepStage.light, Duration(minutes: 200)),
          const MapEntry(SleepStage.deep, Duration(minutes: 100)),
          const MapEntry(SleepStage.rem, Duration(minutes: 170)),
        ],
        avgHrv: 60, // +20% vs baseline 50
        avgHr: 58, // essentially normal
        avgTemp: 33.6, // no deviation
      );

      final readout = engine.evaluate(
        date: today,
        baseline: baseline,
        lastNight: lastNight,
        todaySnapshots: const [],
      );

      expect(
        readout.state,
        anyOf(RecoveryState.recharged, RecoveryState.steady),
      );
      expect(readout.dataQuality, DataQuality.full);
      expect(readout.actions, isNotEmpty);
      expect(readout.actions.length, lessThanOrEqualTo(2));
      expect(
        readout.actions.any((a) =>
            a.toLowerCase().contains('workout') ||
            a.toLowerCase().contains('energy') ||
            a.toLowerCase().contains('routine')),
        isTrue,
        reason: 'a good night should not suggest recovery actions',
      );
      _expectNoMedicalLanguage(readout);
    });
  });

  group('Rough night', () {
    test('HRV -30%, short sleep, elevated HR reads as rundown or stretched',
        () {
      final lastNight = night(
        stagePlan: [
          const MapEntry(SleepStage.light, Duration(minutes: 200)),
          const MapEntry(SleepStage.deep, Duration(minutes: 40)),
          const MapEntry(SleepStage.rem, Duration(minutes: 54)),
        ], // total 294 min = 30% below the 420 min baseline
        avgHrv: 35, // -30% vs baseline 50
        avgHr: 69, // +15% vs baseline 60
        avgTemp: 33.6,
      );

      final readout = engine.evaluate(
        date: today,
        baseline: baseline,
        lastNight: lastNight,
        todaySnapshots: const [],
      );

      expect(
        readout.state,
        anyOf(RecoveryState.rundown, RecoveryState.stretched),
      );
      expect(readout.dataQuality, DataQuality.full);
      expect(
        readout.actions.any((a) =>
            a.toLowerCase().contains('rest') ||
            a.toLowerCase().contains('ease') ||
            a.toLowerCase().contains('bed') ||
            a.toLowerCase().contains('recover') ||
            a.toLowerCase().contains('skip') ||
            a.toLowerCase().contains('short') ||
            a.toLowerCase().contains('light') ||
            a.toLowerCase().contains('slow') ||
            a.toLowerCase().contains('simple') ||
            a.toLowerCase().contains('early')),
        isTrue,
        reason: 'a rough night should suggest recovery-focused actions',
      );
      _expectNoMedicalLanguage(readout);
    });
  });

  group('Temperature deviation', () {
    test('a deviation from baseline nudges toward rest, no medical wording',
        () {
      final lastNight = night(
        stagePlan: [
          const MapEntry(SleepStage.light, Duration(minutes: 200)),
          const MapEntry(SleepStage.deep, Duration(minutes: 100)),
          const MapEntry(SleepStage.rem, Duration(minutes: 120)),
        ], // 420 min, matches baseline exactly
        avgHrv: 50,
        avgHr: 60,
        avgTemp: 34.4, // +0.8C vs baseline 33.6
      );

      final readout = engine.evaluate(
        date: today,
        baseline: baseline,
        lastNight: lastNight,
        todaySnapshots: const [],
      );

      expect(
        readout.actions.any((a) =>
            a.toLowerCase().contains('rest') ||
            a.toLowerCase().contains('easy') ||
            a.toLowerCase().contains('gentle') ||
            a.toLowerCase().contains('light') ||
            a.toLowerCase().contains('low-key') ||
            a.toLowerCase().contains('unhurried') ||
            a.toLowerCase().contains('slow') ||
            a.toLowerCase().contains('early')),
        isTrue,
      );
      _expectNoMedicalLanguage(readout);
    });
  });

  group('Missing data', () {
    test('no session at all and no snapshots returns learning/sparse, '
        'never throws', () {
      final readout = engine.evaluate(
        date: today,
        baseline: baseline,
        lastNight: null,
        todaySnapshots: const [],
      );

      expect(readout.state, RecoveryState.learning);
      expect(readout.dataQuality, DataQuality.sparse);
      _expectNoMedicalLanguage(readout);
    });

    test('a session with every vendor field null and no segments is safe',
        () {
      final blankNight = SleepSession(
        bedtime: DateTime(2026, 7, 15, 23),
        wakeTime: DateTime(2026, 7, 16, 6),
        segments: const [],
      );

      final readout = engine.evaluate(
        date: today,
        baseline: baseline,
        lastNight: blankNight,
        todaySnapshots: const [],
      );

      expect(readout.state, RecoveryState.learning);
      expect(readout.dataQuality, DataQuality.sparse);
      _expectNoMedicalLanguage(readout);
    });

    test('a session with some fields present and some null degrades to '
        'partial, not full', () {
      final partialNight = night(
        stagePlan: [
          const MapEntry(SleepStage.light, Duration(minutes: 300)),
          const MapEntry(SleepStage.deep, Duration(minutes: 60)),
          const MapEntry(SleepStage.rem, Duration(minutes: 60)),
        ],
        avgHrv: null, // ring failed to compute HRV
        avgHr: null,
        avgTemp: 33.6,
      );

      final readout = engine.evaluate(
        date: today,
        baseline: baseline,
        lastNight: partialNight,
        todaySnapshots: const [],
      );

      expect(readout.dataQuality, DataQuality.partial);
      expect(readout.state, isNot(RecoveryState.learning));
    });
  });

  group('Night Shift wording', () {
    test('never says "last night"/"overnight"/"tonight" when active, '
        'across every recovery state', () {
      final scenarios = <SleepSession>[
        night(
          stagePlan: [
            const MapEntry(SleepStage.light, Duration(minutes: 200)),
            const MapEntry(SleepStage.deep, Duration(minutes: 100)),
            const MapEntry(SleepStage.rem, Duration(minutes: 170)),
          ],
          avgHrv: 60,
          avgHr: 58,
          avgTemp: 33.6,
        ), // recharged/steady
        night(
          stagePlan: [
            const MapEntry(SleepStage.light, Duration(minutes: 200)),
            const MapEntry(SleepStage.deep, Duration(minutes: 40)),
            const MapEntry(SleepStage.rem, Duration(minutes: 54)),
          ],
          avgHrv: 35,
          avgHr: 69,
          avgTemp: 34.4,
        ), // stretched/rundown, plus a temperature deviation
      ];

      for (final lastNight in scenarios) {
        final readout = engine.evaluate(
          date: today,
          baseline: baseline,
          lastNight: lastNight,
          todaySnapshots: const [],
          nightShiftActive: true,
        );

        final text = '${readout.headline} ${readout.meaning}'.toLowerCase();
        expect(text.contains('last night'), isFalse,
            reason: 'found "last night" in: $text');
        expect(text.contains('overnight'), isFalse,
            reason: 'found "overnight" in: $text');
        expect(text.contains('tonight'), isFalse,
            reason: 'found "tonight" in: $text');
        expect(text.contains('sleep'), isTrue,
            reason: 'the day-sleeper wording should still mention sleep');
      }
    });

    test('a day-sleeper (main sleep 9am-4pm) gets a normal readout, not '
        'a scolding — baseline and staleness are session-based, not '
        'clock-hour-based, so this needs no scoring changes', () {
      final dayLastNight = SleepSession(
        bedtime: DateTime(2026, 7, 16, 9),
        wakeTime: DateTime(2026, 7, 16, 16),
        segments: [
          SleepSegment(
              start: DateTime(2026, 7, 16, 9),
              end: DateTime(2026, 7, 16, 12),
              stage: SleepStage.light),
          SleepSegment(
              start: DateTime(2026, 7, 16, 12),
              end: DateTime(2026, 7, 16, 14),
              stage: SleepStage.deep),
          SleepSegment(
              start: DateTime(2026, 7, 16, 14),
              end: DateTime(2026, 7, 16, 16),
              stage: SleepStage.rem),
        ],
        avgHrvMs: 52, // in line with baseline
        avgHeartRateBpm: 59,
        avgSkinTempCelsius: 33.6,
      );

      final readout = engine.evaluate(
        date: today,
        baseline: baseline,
        lastNight: dayLastNight,
        todaySnapshots: const [],
        nightShiftActive: true,
      );

      expect(
        readout.state,
        anyOf(RecoveryState.recharged, RecoveryState.steady),
        reason: 'a full, on-baseline 7h sleep should never read as '
            'rundown just because it happened during the day',
      );
      expect(readout.dataQuality, DataQuality.full);
      _expectNoMedicalLanguage(readout);
    });
  });

  group('Fasting Companion filter (excludeDaytimeFood)', () {
    // Short sleep (well below baseline), everything else on-baseline:
    // sleep is the clear dominant negative signal, landing on the
    // stretched/sleep action bucket, whose day-4 pick would normally
    // include the daytime "afternoon chai" suggestion.
    SleepSession stretchedSleepNight() => night(
          stagePlan: [
            const MapEntry(SleepStage.light, Duration(minutes: 150)),
            const MapEntry(SleepStage.deep, Duration(minutes: 60)),
            const MapEntry(SleepStage.rem, Duration(minutes: 40)),
          ], // 250 min, ~40% below the 420 min baseline
          avgHrv: 48,
          avgHr: 60,
          avgTemp: 33.6,
        );

    test('without the flag, the daytime-food action can appear', () {
      final readout = engine.evaluate(
        date: DateTime(2026, 7, 4),
        baseline: baseline,
        lastNight: stretchedSleepNight(),
        todaySnapshots: const [],
      );

      expect(readout.state, RecoveryState.stretched);
      expect(
        readout.actions.any((a) => a.contains('afternoon chai')),
        isTrue,
        reason: 'sanity check: day 4 should pick the daytime-food '
            'variant when nothing filters it out — got ${readout.actions}',
      );
    });

    test('with the flag, the same day never surfaces it', () {
      final readout = engine.evaluate(
        date: DateTime(2026, 7, 4),
        baseline: baseline,
        lastNight: stretchedSleepNight(),
        todaySnapshots: const [],
        excludeDaytimeFood: true,
      );

      expect(readout.state, RecoveryState.stretched);
      expect(readout.actions.any((a) => a.contains('afternoon chai')), isFalse);
      expect(readout.actions, isNotEmpty,
          reason: 'filtering must not empty the actions out entirely');
    });
  });

  group('Determinism', () {
    test('the same inputs produce an identical readout', () {
      final lastNight = night(
        stagePlan: [
          const MapEntry(SleepStage.light, Duration(minutes: 200)),
          const MapEntry(SleepStage.deep, Duration(minutes: 40)),
          const MapEntry(SleepStage.rem, Duration(minutes: 54)),
        ],
        avgHrv: 35,
        avgHr: 69,
        avgTemp: 33.6,
      );

      final first = engine.evaluate(
        date: today,
        baseline: baseline,
        lastNight: lastNight,
        todaySnapshots: const [],
      );
      final second = engine.evaluate(
        date: today,
        baseline: baseline,
        lastNight: lastNight,
        todaySnapshots: const [],
      );

      expect(second.state, first.state);
      expect(second.headline, first.headline);
      expect(second.meaning, first.meaning);
      expect(second.actions, equals(first.actions));
      expect(second.dataQuality, first.dataQuality);
    });
  });
}
