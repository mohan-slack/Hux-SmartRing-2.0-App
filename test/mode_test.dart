/// Tests for the shared modes model (lib/core/modes/mode.dart), focused
/// on the lifestyle-mode additions: NightShiftConfig, FastingConfig, and
/// ActiveContext. Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/modes/mode.dart';

void main() {
  group('NightShiftConfig JSON round-trip', () {
    test('survives toJson/fromJson unchanged', () {
      final config = NightShiftConfig(
        usualSleepStartHour: 9,
        usualSleepEndHour: 16,
        startedAt: DateTime.utc(2026, 7, 1, 8),
      );
      final restored = NightShiftConfig.fromJson(config.toJson());

      expect(restored.usualSleepStartHour, 9);
      expect(restored.usualSleepEndHour, 16);
      expect(restored.startedAt, config.startedAt);
    });
  });

  group('FastType display names', () {
    test('every type has a non-empty, generic-enough display name', () {
      for (final type in FastType.values) {
        expect(type.displayName, isNotEmpty);
      }
      expect(FastType.custom.displayName, 'your fast');
    });
  });

  group('FastingConfig JSON round-trip', () {
    test('survives toJson/fromJson, including a null eating window', () {
      final config = FastingConfig(
        type: FastType.navratri,
        start: DateTime.utc(2026, 9, 22),
        end: DateTime.utc(2026, 9, 30),
        startedAt: DateTime.utc(2026, 9, 20),
      );
      final restored = FastingConfig.fromJson(config.toJson());

      expect(restored.type, FastType.navratri);
      expect(restored.start, config.start);
      expect(restored.end, config.end);
      expect(restored.eatingWindowStartHour, isNull);
      expect(restored.eatingWindowEndHour, isNull);
    });

    test('survives toJson/fromJson with an eating window set', () {
      final config = FastingConfig(
        type: FastType.roza,
        start: DateTime.utc(2026, 3, 1),
        end: DateTime.utc(2026, 3, 30),
        eatingWindowStartHour: 18,
        eatingWindowEndHour: 4,
        startedAt: DateTime.utc(2026, 2, 28),
      );
      final restored = FastingConfig.fromJson(config.toJson());

      expect(restored.eatingWindowStartHour, 18);
      expect(restored.eatingWindowEndHour, 4);
    });
  });

  group('FastingConfig.isActiveOn', () {
    final config = FastingConfig(
      type: FastType.roza,
      start: DateTime(2026, 3, 1),
      end: DateTime(2026, 3, 10),
      startedAt: DateTime(2026, 2, 28),
    );

    test('the start and end dates are both inclusive', () {
      expect(config.isActiveOn(DateTime(2026, 3, 1, 23, 59)), isTrue);
      expect(config.isActiveOn(DateTime(2026, 3, 10, 0, 1)), isTrue);
    });

    test('the day before start and the day after end are not active', () {
      expect(config.isActiveOn(DateTime(2026, 2, 28)), isFalse);
      expect(config.isActiveOn(DateTime(2026, 3, 11)), isFalse);
    });

    test('every day in between is active', () {
      for (var day = 1; day <= 10; day++) {
        expect(config.isActiveOn(DateTime(2026, 3, day)), isTrue,
            reason: 'March $day should be inside the fast window');
      }
    });
  });

  group('FastingConfig.dayNumberOn', () {
    test('the start date is day 1, counting up from there', () {
      final config = FastingConfig(
        type: FastType.ekadashi,
        start: DateTime(2026, 5, 5),
        end: DateTime(2026, 5, 15),
        startedAt: DateTime(2026, 5, 1),
      );

      expect(config.dayNumberOn(DateTime(2026, 5, 5)), 1);
      expect(config.dayNumberOn(DateTime(2026, 5, 6)), 2);
      expect(config.dayNumberOn(DateTime(2026, 5, 15)), 11);
    });
  });

  group('ActiveContext', () {
    test('defaults to nothing active', () {
      const context = ActiveContext();
      expect(context.nightShiftActive, isFalse);
      expect(context.nightShift, isNull);
      expect(context.fasting, isNull);
      expect(context.fastDayNumber, isNull);
      expect(context.fastingActiveOn(DateTime(2026, 1, 1)), isFalse);
    });

    test('fastingActiveOn defers to the FastingConfig date range', () {
      final fasting = FastingConfig(
        type: FastType.karwaChauth,
        start: DateTime(2026, 10, 10),
        end: DateTime(2026, 10, 10),
        startedAt: DateTime(2026, 10, 1),
      );
      final context = ActiveContext(fasting: fasting, fastDayNumber: 1);

      expect(context.fastingActiveOn(DateTime(2026, 10, 10)), isTrue);
      expect(context.fastingActiveOn(DateTime(2026, 10, 11)), isFalse);
    });
  });
}
