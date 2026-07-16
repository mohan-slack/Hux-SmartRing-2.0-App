/// Tests for [EventModeEngine]. Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/meaning/daily_readout.dart';
import 'package:hux_app/core/modes/event_mode_engine.dart';
import 'package:hux_app/core/modes/mode.dart';

void main() {
  const engine = EventModeEngine();

  DailyReadout readoutWith(RecoveryState state) => DailyReadout(
        date: DateTime(2026, 7, 16),
        state: state,
        headline: 'test',
        meaning: 'test',
        actions: const ['test'],
        dataQuality: DataQuality.full,
      );

  EventModeConfig configTargeting(DateTime targetDate) => EventModeConfig(
        id: ModeId.shaadi,
        targetDate: targetDate,
        startedAt: DateTime(2026, 1, 1),
      );

  DateTime daysFromToday(DateTime today, int days) =>
      DateTime.utc(today.year, today.month, today.day + days);

  group('Phase boundaries', () {
    final today = DateTime.utc(2026, 7, 16);
    final readout = readoutWith(RecoveryState.steady);

    final expected = {
      22: ModePhase.foundation,
      21: ModePhase.build,
      8: ModePhase.build,
      7: ModePhase.taper,
      2: ModePhase.taper,
      1: ModePhase.eve,
      0: ModePhase.theDay,
    };

    expected.forEach((daysToGo, expectedPhase) {
      test('$daysToGo days to go -> $expectedPhase', () {
        final config = configTargeting(daysFromToday(today, daysToGo));
        final strip =
            engine.evaluate(config: config, today: today, readout: readout);

        expect(strip.phase, expectedPhase);
        expect(strip.daysToGo, daysToGo);
      });
    });

    test('phase labels and focus text are set for every phase', () {
      for (final entry in expected.entries) {
        final config = configTargeting(daysFromToday(today, entry.key));
        final strip =
            engine.evaluate(config: config, today: today, readout: readout);
        expect(strip.phaseLabel, isNotEmpty);
        expect(strip.focus, isNotEmpty);
        expect(strip.themedAction, isNotEmpty);
      }
    });
  });

  group('Day zero', () {
    test('themed action reflects the readout state, warm tone', () {
      final today = DateTime.utc(2026, 7, 16);
      final config = configTargeting(today);

      final recharged = engine.evaluate(
          config: config, today: today, readout: readoutWith(RecoveryState.recharged));
      final rundown = engine.evaluate(
          config: config, today: today, readout: readoutWith(RecoveryState.rundown));

      expect(recharged.phase, ModePhase.theDay);
      expect(recharged.daysToGo, 0);
      expect(recharged.themedAction, isNot(equals(rundown.themedAction)));
    });
  });

  group('Auto-complete', () {
    test('a target date 3 days past reads as completed with a wrap-up',
        () {
      final today = DateTime.utc(2026, 7, 16);
      final config = configTargeting(daysFromToday(today, -3));

      final strip = engine.evaluate(
          config: config, today: today, readout: readoutWith(RecoveryState.steady));

      expect(strip.phase, ModePhase.completed);
      expect(strip.daysToGo, -3);
      expect(strip.isWrapUp, isTrue);
      expect(strip.themedAction, isNotEmpty);
    });

    test('the day right after the target date also completes', () {
      final today = DateTime.utc(2026, 7, 16);
      final config = configTargeting(daysFromToday(today, -1));

      final strip = engine.evaluate(
          config: config, today: today, readout: readoutWith(RecoveryState.steady));

      expect(strip.phase, ModePhase.completed);
      expect(strip.isWrapUp, isTrue);
    });
  });

  group('Determinism', () {
    test('the same inputs produce an identical strip', () {
      final today = DateTime.utc(2026, 7, 16);
      final config = configTargeting(daysFromToday(today, 5));
      final readout = readoutWith(RecoveryState.stretched);

      final first = engine.evaluate(config: config, today: today, readout: readout);
      final second = engine.evaluate(config: config, today: today, readout: readout);

      expect(second.phase, first.phase);
      expect(second.phaseLabel, first.phaseLabel);
      expect(second.daysToGo, first.daysToGo);
      expect(second.focus, first.focus);
      expect(second.themedAction, first.themedAction);
    });
  });

  group('Calendar-date comparison, not 24h windows', () {
    test('time-of-day on the target date does not shift days-to-go', () {
      // Local times on purpose (not .utc): "days to go" compares
      // calendar dates in the device's own timezone (see the doc
      // comment on EventModeEngine._dateOnly), so the boundary this
      // test cares about — crossing midnight — has to be a LOCAL
      // midnight to be timezone-independent for whoever runs this.
      final today = DateTime(2026, 7, 16, 23, 59);
      final config = EventModeConfig(
        id: ModeId.bigDay,
        targetDate: DateTime(2026, 7, 17, 0, 1), // technically <1h away
        startedAt: DateTime(2026, 1, 1),
      );

      final strip = engine.evaluate(
          config: config, today: today, readout: readoutWith(RecoveryState.steady));

      expect(strip.daysToGo, 1, reason: 'the calendar day after, not "<24h"');
      expect(strip.phase, ModePhase.eve);
    });
  });
}
