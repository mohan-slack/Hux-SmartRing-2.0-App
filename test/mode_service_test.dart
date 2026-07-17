/// Tests for [ModeService]. Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hux_app/core/meaning/daily_readout.dart';
import 'package:hux_app/core/modes/event_mode_engine.dart';
import 'package:hux_app/core/modes/mode.dart';
import 'package:hux_app/core/modes/mode_service.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';

void main() {
  sqfliteFfiInit();

  Future<SqliteHealthStore> openStore() =>
      SqliteHealthStore.open(inMemoryDatabasePath,
          factory: databaseFactoryFfi);

  DailyReadout readoutWith(RecoveryState state) => DailyReadout(
        date: DateTime(2026, 7, 16),
        state: state,
        headline: 'test',
        meaning: 'test',
        actions: const ['test'],
        dataQuality: DataQuality.full,
      );

  group('Start / replace', () {
    test('no mode active until one is started', () async {
      final store = await openStore();
      final service = ModeService(store);

      expect(await service.activeConfig(), isNull);

      await store.close();
    });

    test('starting a mode while another is active replaces it', () async {
      final store = await openStore();
      final service = ModeService(store);

      await service.startMode(EventModeConfig(
        id: ModeId.shaadi,
        targetDate: DateTime.utc(2026, 8, 1),
        startedAt: DateTime.utc(2026, 7, 1),
      ));
      await service.startMode(EventModeConfig(
        id: ModeId.examSeason,
        targetDate: DateTime.utc(2026, 9, 1),
        startedAt: DateTime.utc(2026, 7, 15),
      ));

      final active = await service.activeConfig();
      expect(active!.id, ModeId.examSeason,
          reason: 'replacing must leave exactly one mode active');

      await store.close();
    });
  });

  group('End mode', () {
    test('endMode clears the active mode', () async {
      final store = await openStore();
      final service = ModeService(store);

      await service.startMode(EventModeConfig(
        id: ModeId.bigDay,
        targetDate: DateTime.utc(2026, 8, 1),
        startedAt: DateTime.utc(2026, 7, 1),
      ));
      await service.endMode();

      expect(await service.activeConfig(), isNull);
      await store.close();
    });
  });

  group('currentStrip', () {
    test('null when no mode is active', () async {
      final store = await openStore();
      final service = ModeService(store);

      final strip =
          await service.currentStrip(readout: readoutWith(RecoveryState.steady));
      expect(strip, isNull);

      await store.close();
    });

    test('reflects the active mode while its target date is still ahead',
        () async {
      final store = await openStore();
      final service = ModeService(store);
      final now = DateTime.utc(2026, 7, 16);

      await service.startMode(EventModeConfig(
        id: ModeId.shaadi,
        targetDate: DateTime.utc(2026, 7, 26), // 10 days out
        startedAt: now,
      ));

      final strip = await service.currentStrip(
          readout: readoutWith(RecoveryState.steady), now: now);

      expect(strip, isNotNull);
      expect(strip!.phase, ModePhase.build);
      expect(strip.daysToGo, 10);
      // Still active — currentStrip must not clear a live mode.
      expect(await service.activeConfig(), isNotNull);

      await store.close();
    });

    test('auto-completes and clears itself once the target date has '
        'passed', () async {
      final store = await openStore();
      final service = ModeService(store);
      final now = DateTime.utc(2026, 7, 16);

      await service.startMode(EventModeConfig(
        id: ModeId.examSeason,
        targetDate: DateTime.utc(2026, 7, 13), // 3 days past
        startedAt: DateTime.utc(2026, 6, 1),
      ));

      final strip = await service.currentStrip(
          readout: readoutWith(RecoveryState.steady), now: now);

      expect(strip, isNotNull);
      expect(strip!.isWrapUp, isTrue);

      // The whole point: it cleared itself after producing the
      // wrap-up, so a second call finds nothing.
      expect(await service.activeConfig(), isNull);
      final second = await service.currentStrip(
          readout: readoutWith(RecoveryState.steady), now: now);
      expect(second, isNull);

      await store.close();
    });
  });

  group('Lifestyle modes', () {
    test('activeContext is all-inactive with nothing started', () async {
      final store = await openStore();
      final service = ModeService(store);

      final context = await service.activeContext();
      expect(context.nightShiftActive, isFalse);
      expect(context.fasting, isNull);
      expect(context.fastDayNumber, isNull);

      await store.close();
    });

    test('starting night shift is reflected in activeContext', () async {
      final store = await openStore();
      final service = ModeService(store);

      await service.startNightShift(NightShiftConfig(
        usualSleepStartHour: 9,
        usualSleepEndHour: 16,
        startedAt: DateTime.utc(2026, 7, 1),
      ));

      final context = await service.activeContext();
      expect(context.nightShiftActive, isTrue);
      expect(context.nightShift!.usualSleepStartHour, 9);

      await service.endNightShift();
      expect((await service.activeContext()).nightShiftActive, isFalse);

      await store.close();
    });

    test('activeContext computes fastDayNumber only on active fast days',
        () async {
      final store = await openStore();
      final service = ModeService(store);
      final now = DateTime.utc(2026, 3, 5);

      await service.startFasting(FastingConfig(
        type: FastType.roza,
        start: DateTime.utc(2026, 3, 1),
        end: DateTime.utc(2026, 3, 30),
        startedAt: DateTime.utc(2026, 2, 28),
      ));

      final inside = await service.activeContext(now: now);
      expect(inside.fastDayNumber, 5);

      final outside =
          await service.activeContext(now: DateTime.utc(2026, 4, 1));
      expect(outside.fastDayNumber, isNull,
          reason: 'fasting config still exists but today is outside it');
      expect(outside.fasting, isNotNull,
          reason: 'the config itself is still there, just not active today');

      await store.close();
    });

    test('night shift and an active event mode coexist in activeConfig '
        'and activeContext', () async {
      final store = await openStore();
      final service = ModeService(store);

      await service.startMode(EventModeConfig(
        id: ModeId.bigDay,
        targetDate: DateTime.utc(2026, 8, 1),
        startedAt: DateTime.utc(2026, 7, 1),
      ));
      await service.startNightShift(NightShiftConfig(
        usualSleepStartHour: 9,
        usualSleepEndHour: 16,
        startedAt: DateTime.utc(2026, 7, 1),
      ));

      expect((await service.activeConfig())?.id, ModeId.bigDay);
      expect((await service.activeContext()).nightShiftActive, isTrue);

      await store.close();
    });
  });
}
