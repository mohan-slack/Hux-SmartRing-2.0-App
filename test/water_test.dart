/// Water: goal from weight and heat, one tap per glass, per local day.
import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/environment/outlook.dart';
import 'package:hux_app/core/home/home_extras.dart';
import 'package:hux_app/core/journeys/workout_log.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:hux_app/core/water/water_log.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  Future<SqliteHealthStore> openStore() => SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);

  group('WaterGoal', () {
    test('8 glasses when weight is unknown', () {
      expect(WaterGoal.of().glasses, 8);
      expect(WaterGoal.of().why, isNull);
    });

    test('about 30 ml per kg, kept between 6 and 12', () {
      expect(WaterGoal.of(weightKg: 70).glasses, 8); // 2.1 L
      expect(WaterGoal.of(weightKg: 85).glasses, 10); // 2.55 L
      expect(WaterGoal.of(weightKg: 40).glasses, 6);
      expect(WaterGoal.of(weightKg: 140).glasses, 12);
    });

    test('hot days add glasses and say why', () {
      expect(WaterGoal.of(weightKg: 70, heat: HeatLevel.caution).glasses, 10);
      expect(WaterGoal.of(weightKg: 70, heat: HeatLevel.caution).why, contains('Hot day'));
      expect(WaterGoal.of(weightKg: 70, heat: HeatLevel.heatwave).glasses, 11);
      expect(WaterGoal.of(weightKg: 70, heat: HeatLevel.severe).glasses, 11);
    });
  });

  group('WaterLog', () {
    test('add, undo, never below zero, capped', () async {
      final log = WaterLog(await openStore(), now: () => DateTime(2026, 3, 1, 10));
      expect(await log.today(), 0);
      expect(await log.add(), 1);
      expect(await log.add(), 2);
      expect(await log.add(-1), 1);
      expect(await log.add(-5), 0);
      expect(await log.add(100), WaterLog.maxPerDay);
    });

    test('counts are per local day; last 7 days oldest first', () async {
      var clock = DateTime(2026, 11, 15, 23, 50);
      final log = WaterLog(await openStore(), now: () => clock);
      await log.add(3);
      clock = DateTime(2026, 11, 16, 0, 10);
      expect(await log.today(), 0);
      await log.add(2);
      expect(await log.lastDays(), [0, 0, 0, 0, 0, 3, 2]);
    });
  });

  test('Home extras carry water with the goal from the latest weight', () async {
    final store = await openStore();
    DateTime now() => DateTime(2026, 12, 20, 10);
    await WorkoutLog(store, now: now).addWeight(85);
    await WaterLog(store, now: now).add(4);
    final extras = await HomeExtrasLoader(store: store, now: now).load();
    expect(extras.water!.glasses, 4);
    expect(extras.water!.goal.glasses, 10);
  });
}
