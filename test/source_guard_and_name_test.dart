/// Demo/real data never mix; the greeting name comes from the user.
/// Run with: flutter test test/source_guard_and_name_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/profile/user_profile.dart';
import 'package:hux_app/core/ring/data_source.dart';
import 'package:hux_app/core/ring/ring_models.dart';
import 'package:hux_app/core/storage/source_guard.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('switching mock -> health clears readings, keeps settings', () async {
    final store = await SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
    final wake = DateTime.utc(2026, 11, 2, 2);
    final bed = wake.subtract(const Duration(hours: 7));
    await store.saveSleepSessions([
      SleepSession(bedtime: bed, wakeTime: wake, segments: [SleepSegment(start: bed, end: wake, stage: SleepStage.light)]),
    ]);
    await store.setLastSyncedUpTo(wake);
    await store.writeSetting('user_profile', '{"v":1}');

    expect(await guardDataSource(store, RingDataSource.mock), isFalse); // first run: just remembers
    expect(await guardDataSource(store, RingDataSource.mock), isFalse); // same source: nothing
    expect(await store.latestSleepSession(), isNotNull);

    expect(await guardDataSource(store, RingDataSource.health), isTrue); // switched
    expect(await store.latestSleepSession(), isNull);
    expect(await store.lastSyncedUpTo(), isNull); // next open syncs fresh
    expect(await store.readSetting('user_profile'), '{"v":1}'); // answers kept
    await store.close();
  });

  test('names are cleaned, capped, and survive save/load', () {
    expect(UserProfile.cleanName('  priya   sharma '), 'priya sharma');
    expect(UserProfile.cleanName('Mohan123!'), 'Mohan');
    expect(UserProfile.cleanName('   '), isNull);
    expect(UserProfile.cleanName('ప్రియ'), 'ప్రియ'); // Telugu letters kept
    expect(UserProfile.cleanName('A' * 40)!.length, UserProfile.maxNameLength);
    final p = const UserProfile(goals: [Goal.sleepBetter]).withName('Priya');
    final back = UserProfile.fromJson(p.toJson());
    expect(back.name, 'Priya');
    expect(back.goals, [Goal.sleepBetter]);
    expect(const UserProfile().withName('Priya').isEmpty, isTrue); // a name alone isn't "answers"
  });
}
