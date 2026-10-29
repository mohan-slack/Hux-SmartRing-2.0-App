/// ProfileService: persistence, usage window, votes.
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/profile/feature_catalog.dart';
import 'package:hux_app/core/profile/profile_service.dart';
import 'package:hux_app/core/profile/user_profile.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<SqliteHealthStore> openStore() =>
      SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);

  test('no profile until onboarding is done, then it round-trips', () async {
    final store = await openStore();
    final service = ProfileService(store);

    expect(await service.loadProfile(), isNull);

    await service.saveProfile(const UserProfile(dayType: DayType.student));
    final loaded = await service.loadProfile();
    expect(loaded?.dayType, DayType.student);
    await store.close();
  });

  test('skipping everything still counts as onboarded', () async {
    final store = await openStore();
    final service = ProfileService(store);
    await service.saveProfile(const UserProfile());
    expect(await service.loadProfile(), isNotNull);
    await store.close();
  });

  test('only opens in the last 7 days count', () async {
    final store = await openStore();
    final service = ProfileService(store);
    final now = DateTime.utc(2026, 10, 20, 12);

    await service.recordOpen(FeatureId.walkAfterMeal, now: now.subtract(const Duration(days: 10)));
    await service.recordOpen(FeatureId.walkAfterMeal, now: now.subtract(const Duration(days: 2)));
    await service.recordOpen(FeatureId.walkAfterMeal, now: now);

    final opens = await service.recentOpens(now: now);
    expect(opens[FeatureId.walkAfterMeal], 2);
    await store.close();
  });

  test('featured uses the saved answers', () async {
    final store = await openStore();
    final service = ProfileService(store);
    await service.saveProfile(const UserProfile(dayType: DayType.nightShift));
    final featured = await service.featured();
    expect(featured.first, FeatureId.nightShiftMode);
    await store.close();
  });

  test('votes persist and are de-duplicated', () async {
    final store = await openStore();
    final service = ProfileService(store);
    await service.vote(FeatureId.aiCoach);
    await service.vote(FeatureId.aiCoach);
    await service.vote(FeatureId.proteinGap);
    expect(await service.votedFeatures(), {FeatureId.aiCoach, FeatureId.proteinGap});
    await store.close();
  });

  test('deleting all data clears the answers too (new account = fresh start)', () async {
    final store = await openStore();
    final service = ProfileService(store);
    await service.saveProfile(const UserProfile(dayType: DayType.desk));
    await store.deleteAllData();
    expect(await service.loadProfile(), isNull);
    await store.close();
  });
}
