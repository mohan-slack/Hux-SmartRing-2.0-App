/// Walk-after-meal nudges: planning rules + keeping the OS schedule in sync.
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/nudges/notifier.dart';
import 'package:hux_app/core/nudges/nudge_planner.dart';
import 'package:hux_app/core/nudges/nudge_service.dart';
import 'package:hux_app/core/nudges/sit_planner.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeNotifier implements Notifier {
  bool grant = true;
  final daily = <int, DailyNudge>{};
  final once = <int, DateTime>{};
  final cancelled = <int>[];

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => grant;

  @override
  Future<void> scheduleDaily(DailyNudge nudge) async => daily[nudge.id] = nudge;

  final weekly = <int, WeeklyNudge>{};

  @override
  Future<void> scheduleWeekly(WeeklyNudge nudge) async => weekly[nudge.id] = nudge;

  @override
  Future<void> scheduleOnce({required int id, required DateTime at, required String title, required String body}) async =>
      once[id] = at;

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    daily.remove(id);
    weekly.remove(id);
    once.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    daily.clear();
    weekly.clear();
    once.clear();
  }
}

void main() {
  sqfliteFfiInit();
  const planner = NudgePlanner();
  final enabledSettings = WalkNudgeSettings.defaults.copyWith(enabled: true);

  group('NudgePlanner', () {
    test('off by default: nothing scheduled', () {
      expect(planner.dailyWalkNudges(WalkNudgeSettings.defaults), isEmpty);
    });

    test('nudges 20 minutes after usual lunch and dinner', () {
      final nudges = planner.dailyWalkNudges(enabledSettings);
      expect(nudges.map((n) => n.at), const [TimeOfDayHm(13, 50), TimeOfDayHm(20, 50)]);
      expect(nudges.map((n) => n.id), [NudgeIds.walkLunch, NudgeIds.walkDinner]);
    });

    test('a late dinner nudge falling in quiet hours is skipped', () {
      final lateDinner = enabledSettings.copyWith(dinner: const TimeOfDayHm(22, 30)); // nudge 22:50
      final nudges = planner.dailyWalkNudges(lateDinner);
      expect(nudges.map((n) => n.id), [NudgeIds.walkLunch]);
    });

    test('quiet hours wrap midnight', () {
      expect(NudgePlanner.inQuietHours(const TimeOfDayHm(23, 0), enabledSettings), isTrue);
      expect(NudgePlanner.inQuietHours(const TimeOfDayHm(6, 59), enabledSettings), isTrue);
      expect(NudgePlanner.inQuietHours(const TimeOfDayHm(7, 0), enabledSettings), isFalse);
      expect(NudgePlanner.inQuietHours(const TimeOfDayHm(22, 29), enabledSettings), isFalse);
    });

    test('after a logged meal: +10 min, unless a fixed nudge is near', () {
      // Breakfast logged 08:30 -> nudge 08:40 (no fixed nudge near).
      expect(planner.afterLoggedMeal(DateTime(2026, 7, 20, 8, 30), enabledSettings), DateTime(2026, 7, 20, 8, 40));
      // Lunch logged 13:30 -> 13:40, but the 13:50 fixed nudge is near.
      expect(planner.afterLoggedMeal(DateTime(2026, 7, 20, 13, 30), enabledSettings), isNull);
    });

    test('no after-log nudge in quiet hours or when switched off', () {
      expect(planner.afterLoggedMeal(DateTime(2026, 7, 20, 23, 0), enabledSettings), isNull);
      expect(planner.afterLoggedMeal(DateTime(2026, 7, 20, 8, 30), enabledSettings.copyWith(afterLoggedMeal: false)), isNull);
      expect(planner.afterLoggedMeal(DateTime(2026, 7, 20, 8, 30), WalkNudgeSettings.defaults), isNull);
    });

    test('settings JSON round-trips; bad values fall back to defaults', () {
      final s = enabledSettings.copyWith(lunch: const TimeOfDayHm(12, 45));
      final back = WalkNudgeSettings.fromJson(s.toJson());
      expect(back.enabled, isTrue);
      expect(back.lunch, const TimeOfDayHm(12, 45));
      final bad = WalkNudgeSettings.fromJson({'lunch': '99:99', 'enabled': 'yes'});
      expect(bad.lunch, WalkNudgeSettings.defaults.lunch);
      expect(bad.enabled, isFalse);
    });

    test('time labels', () {
      expect(const TimeOfDayHm(13, 5).label, '1:05 PM');
      expect(const TimeOfDayHm(0, 0).label, '12:00 AM');
      expect(const TimeOfDayHm(23, 50).plusMinutes(20), const TimeOfDayHm(0, 10));
    });
  });

  group('NudgeService', () {
    Future<SqliteHealthStore> openStore() =>
        SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);

    test('turning on schedules both meal nudges', () async {
      final store = await openStore();
      final n = FakeNotifier();
      final service = NudgeService(store, n);
      expect(await service.saveWalkSettings(enabledSettings), isTrue);
      expect(n.daily.keys.toSet(), {NudgeIds.walkLunch, NudgeIds.walkDinner});
      expect((await service.walkSettings()).enabled, isTrue);
      await store.close();
    });

    test('permission refused -> stays off, nothing scheduled, reports false', () async {
      final store = await openStore();
      final n = FakeNotifier()..grant = false;
      final service = NudgeService(store, n);
      expect(await service.saveWalkSettings(enabledSettings), isFalse);
      expect(n.daily, isEmpty);
      expect((await service.walkSettings()).enabled, isFalse);
      await store.close();
    });

    test('changing lunch time replaces, never duplicates', () async {
      final store = await openStore();
      final n = FakeNotifier();
      final service = NudgeService(store, n);
      await service.saveWalkSettings(enabledSettings);
      await service.saveWalkSettings(enabledSettings.copyWith(lunch: const TimeOfDayHm(12, 0)));
      expect(n.daily[NudgeIds.walkLunch]!.at, const TimeOfDayHm(12, 20));
      expect(n.daily.length, 2);
      await store.close();
    });

    test('turning off cancels everything', () async {
      final store = await openStore();
      final n = FakeNotifier();
      final service = NudgeService(store, n);
      await service.saveWalkSettings(enabledSettings);
      await service.saveWalkSettings(enabledSettings.copyWith(enabled: false));
      expect(n.daily, isEmpty);
      expect(n.cancelled, containsAll(NudgeIds.allWalk));
      await store.close();
    });

    test('morning briefing: off by default, on schedules one daily nudge with the streak', () async {
      final store = await openStore();
      final n = FakeNotifier();
      final service = NudgeService(store, n);
      expect((await service.briefingSettings()).enabled, isFalse);
      await service.refreshBriefing(streakDays: 5);
      expect(n.daily.containsKey(NudgeIds.morningBriefing), isFalse);

      await service.saveBriefingSettings(BriefingSettings.defaults.copyWith(enabled: true));
      final b = n.daily[NudgeIds.morningBriefing]!;
      expect(b.at.hour, 7);
      expect(b.title, contains('5-day streak'));

      await service.saveBriefingSettings(BriefingSettings.defaults);
      expect(n.daily.containsKey(NudgeIds.morningBriefing), isFalse);
      await store.close();
    });

    test('resync rebuilds the schedule from saved settings', () async {
      final store = await openStore();
      await NudgeService(store, FakeNotifier()).saveWalkSettings(enabledSettings);
      final fresh = FakeNotifier(); // e.g. after reinstall
      await NudgeService(store, fresh).resync();
      expect(fresh.daily.length, 2);
      await store.close();
    });

    test('logging a meal schedules a one-off nudge when appropriate', () async {
      final store = await openStore();
      final n = FakeNotifier();
      final service = NudgeService(store, n);
      await service.saveWalkSettings(enabledSettings);
      await service.onMealLogged(DateTime(2026, 7, 20, 8, 30));
      expect(n.once[NudgeIds.walkAfterLogged], DateTime(2026, 7, 20, 8, 40));
      await store.close();
    });
  });

  group('SitPlanner', () {
    const sit = SitPlanner();
    final sitOn = SitNudgeSettings.defaults.copyWith(enabled: true);

    test('hourly from 10 AM to 6 PM -> 8 slots, first one hour after start', () {
      final slots = sit.slots(sitOn);
      expect(slots.length, 8);
      expect(slots.first, const TimeOfDayHm(11, 0));
      expect(slots.last, const TimeOfDayHm(18, 0));
    });

    test('skips slots near walk-after-meal nudges (13:50) to avoid doubles', () {
      final slots = sit.slots(sitOn, walk: enabledSettings);
      expect(slots, isNot(contains(const TimeOfDayHm(14, 0))));
      expect(slots.length, 7);
    });

    test('weekdays only by default, unique ids, one per day per slot', () {
      final nudges = sit.weeklyNudges(sitOn);
      expect(nudges.length, 8 * 5);
      expect(nudges.map((n) => n.weekday).toSet(), {1, 2, 3, 4, 5});
      expect(nudges.map((n) => n.id).toSet().length, nudges.length);
    });

    test('capped so the phone limit is never exceeded', () {
      final every45AllWeek = sitOn.copyWith(
        intervalMinutes: 45,
        start: const TimeOfDayHm(8, 0),
        end: const TimeOfDayHm(20, 0),
        days: {1, 2, 3, 4, 5, 6, 7},
      );
      expect(sit.exceedsLimit(every45AllWeek), isTrue);
      expect(sit.weeklyNudges(every45AllWeek).length, SitPlanner.maxScheduled);
    });

    test('off, no days, or end before start -> nothing', () {
      expect(sit.weeklyNudges(SitNudgeSettings.defaults), isEmpty);
      expect(sit.weeklyNudges(sitOn.copyWith(days: {})), isEmpty);
      expect(sit.slots(sitOn.copyWith(start: const TimeOfDayHm(18, 0), end: const TimeOfDayHm(9, 0))), isEmpty);
    });

    test('settings JSON round-trips; unknown interval falls back to 60', () {
      final s = sitOn.copyWith(intervalMinutes: 45, days: {1, 3, 5});
      final back = SitNudgeSettings.fromJson(s.toJson());
      expect(back.intervalMinutes, 45);
      expect(back.days, {1, 3, 5});
      expect(SitNudgeSettings.fromJson({'interval': 7}).intervalMinutes, 60);
    });
  });

  group('NudgeService (sit)', () {
    Future<SqliteHealthStore> openStore() =>
        SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
    final sitOn = SitNudgeSettings.defaults.copyWith(enabled: true);

    test('turning on schedules weekly reminders; turning off cancels exactly those', () async {
      final store = await openStore();
      final n = FakeNotifier();
      final service = NudgeService(store, n);
      expect(await service.saveSitSettings(sitOn), isTrue);
      expect(n.weekly.length, 40);
      await service.saveSitSettings(sitOn.copyWith(enabled: false));
      expect(n.weekly, isEmpty);
      await store.close();
    });

    test('changing the interval replaces the old set (no leftovers)', () async {
      final store = await openStore();
      final n = FakeNotifier();
      final service = NudgeService(store, n);
      await service.saveSitSettings(sitOn);
      await service.saveSitSettings(sitOn.copyWith(intervalMinutes: 90));
      expect(n.weekly.length, 5 * 5); // 11:30, 13:00, 14:30, 16:00, 17:30
      await store.close();
    });

    test('turning on walk nudges re-plans sit slots around them', () async {
      final store = await openStore();
      final n = FakeNotifier();
      final service = NudgeService(store, n);
      await service.saveSitSettings(sitOn);
      await service.saveWalkSettings(enabledSettings);
      expect(n.weekly.length, 7 * 5);
      await store.close();
    });

    test('permission refused -> sit stays off', () async {
      final store = await openStore();
      final n = FakeNotifier()..grant = false;
      final service = NudgeService(store, n);
      expect(await service.saveSitSettings(sitOn), isFalse);
      expect(n.weekly, isEmpty);
      await store.close();
    });
  });
}
