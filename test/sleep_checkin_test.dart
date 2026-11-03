/// Morning check-in: phone-only Charge, "how rested" for everyone.
/// Run with: flutter test test/sleep_checkin_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/checkin/sleep_checkin.dart';
import 'package:hux_app/core/meaning/readout_service.dart';
import 'package:hux_app/core/ring/ring_models.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<SqliteHealthStore> open() => SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);

  SleepCheckIn night(int wakeDay, {int hours = 8, Rested feel = Rested.good}) {
    final wake = DateTime(2026, 11, wakeDay, 7);
    return SleepCheckIn(bed: wake.subtract(Duration(hours: hours)), wake: wake, feel: feel);
  }

  test('save, replace same day, feel lookup, bad lengths rejected', () async {
    final store = await open();
    final s = SleepCheckInService(store, now: () => DateTime(2026, 11, 5, 8));
    await s.save(night(5, feel: Rested.poor));
    await s.save(night(5, feel: Rested.great)); // same wake day replaces
    expect((await s.all()).single.feel, Rested.great);
    expect(await s.feelFor(DateTime(2026, 11, 5, 8)), Rested.great); // within 3 h
    expect(await s.feelFor(DateTime(2026, 11, 4, 7)), isNull);
    expect(() => s.save(night(4, hours: 20)), throwsArgumentError);
    await store.close();
  });

  test('asks only in the morning, once a day', () async {
    final store = await open();
    var now = DateTime(2026, 11, 5, 8);
    final s = SleepCheckInService(store, now: () => now);
    expect(await s.shouldAsk(), isTrue);
    await s.save(night(5));
    expect(await s.shouldAsk(), isFalse);
    now = DateTime(2026, 11, 6, 18);
    expect(await s.shouldAsk(), isFalse); // evening
    await store.close();
  });

  test('synced nights win over check-ins for the same night', () {
    final c = night(5);
    final synced = SleepSession(
      bedtime: c.bed.add(const Duration(minutes: 20)),
      wakeTime: c.wake.subtract(const Duration(minutes: 20)),
      segments: const [],
    );
    expect(SleepCheckInService.merge([synced], [c]), [synced]);
    expect(SleepCheckInService.merge(const [], [c]).single.wakeTime, c.wake);
    // A feel-only check-in for a device night never becomes a night.
    final feelOnly = SleepCheckIn(bed: c.bed, wake: c.wake, feel: Rested.okay, fromDevice: true);
    expect(SleepCheckInService.merge(const [], [feelOnly]), isEmpty);
  });

  test('phone-only: 4 check-ins give a Charge, and "rested" lifts it', () async {
    final store = await open();
    final now = DateTime(2026, 11, 5, 9);
    final s = SleepCheckInService(store, now: () => now);
    for (final d in [2, 3, 4, 5]) {
      await s.save(night(d));
    }
    final readout = await ReadoutService(store).today(now: now);
    // Usual 8 h night (70) + feeling rested (78, weight 0.3) → 73.
    expect(readout.charge?.morningCharge, 73);
    expect((await ReadoutService(store).lastNight(now: now))?.wakeTime.isAtSameMomentAs(DateTime(2026, 11, 5, 7)), isTrue);
    await store.close();
  });

  test('nightsBetween: check-in nights show up wherever nights are read', () async {
    final store = await open();
    final s = SleepCheckInService(store, now: () => DateTime(2026, 11, 5, 8));
    await s.save(night(4));
    await s.save(night(5));
    final synced = SleepSession(
      bedtime: DateTime(2026, 11, 2, 23),
      wakeTime: DateTime(2026, 11, 3, 7),
      segments: [SleepSegment(start: DateTime(2026, 11, 2, 23), end: DateTime(2026, 11, 3, 7), stage: SleepStage.light)],
    );
    await store.saveSleepSessions([synced]);
    final nights = await SleepCheckInService.nightsBetween(store, DateTime(2026, 11, 1), DateTime(2026, 11, 6));
    expect(nights, hasLength(3));
    // Window is by bedtime: the Nov 5 night (bed Nov 4, 23:00) is outside [Nov 1, Nov 4 12:00).
    expect(await SleepCheckInService.nightsBetween(store, DateTime(2026, 11, 1), DateTime(2026, 11, 4, 12)), hasLength(2));
    await store.close();
  });

  test('"Not now" lasts the day; a newer check-in beats an older watch night', () async {
    final store = await open();
    var now = DateTime(2026, 11, 5, 8);
    final s = SleepCheckInService(store, now: () => now);
    expect(await s.shouldAsk(), isTrue);
    await s.skipToday();
    expect(await s.shouldAsk(), isFalse);
    now = DateTime(2026, 11, 6, 8);
    expect(await s.shouldAsk(), isTrue); // next morning asks again

    // Watch synced the night ending Nov 5; it missed Nov 6 — the check-in stands in.
    final w = DateTime(2026, 11, 5, 7);
    await store.saveSleepSessions([
      SleepSession(
          bedtime: w.subtract(const Duration(hours: 7)),
          wakeTime: w,
          segments: [SleepSegment(start: w.subtract(const Duration(hours: 7)), end: w, stage: SleepStage.light)]),
    ]);
    await s.save(night(6));
    final last = await ReadoutService(store).lastNight(now: DateTime(2026, 11, 6, 9));
    expect(last!.wakeTime.isAtSameMomentAs(DateTime(2026, 11, 6, 7)), isTrue);
    await store.close();
  });
}
