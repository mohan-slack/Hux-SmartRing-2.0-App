/// Air & heat: India AQI math, IMD-based heat levels, outlooks, alerts.
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/environment/environment_service.dart';
import 'package:hux_app/core/environment/india_aqi.dart';
import 'package:hux_app/core/environment/india_cities.dart';
import 'package:hux_app/core/environment/outlook.dart';
import 'package:hux_app/core/nudges/notifier.dart';
import 'package:hux_app/core/nudges/nudge_planner.dart';
import 'package:hux_app/core/nudges/sit_planner.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeNotifier implements Notifier {
  bool grant = true;
  final once = <int, ({DateTime at, String title})>{};

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => grant;
  @override
  Future<void> scheduleDaily(DailyNudge nudge) async {}
  @override
  Future<void> scheduleWeekly(WeeklyNudge nudge) async {}
  @override
  Future<void> scheduleOnce({required int id, required DateTime at, required String title, required String body}) async =>
      once[id] = (at: at, title: title);
  @override
  Future<void> cancel(int id) async => once.remove(id);
  @override
  Future<void> cancelAll() async => once.clear();
}

/// Two days of hourly forecast JSON in Open-Meteo's shape.
({Map<String, Object?> weather, Map<String, Object?> air}) forecast({
  required double Function(int dayIdx, int hour) temp,
  required double Function(int dayIdx, int hour) pm25,
}) {
  final times = <String>[];
  final t = <double>[];
  final f = <double>[];
  final p25 = <double>[];
  final p10 = <double>[];
  for (var d = 0; d < 2; d++) {
    for (var h = 0; h < 24; h++) {
      times.add('2026-05-${(20 + d).toString().padLeft(2, '0')}T${h.toString().padLeft(2, '0')}:00');
      t.add(temp(d, h));
      f.add(temp(d, h) + 1);
      p25.add(pm25(d, h));
      p10.add(pm25(d, h) * 1.5);
    }
  }
  return (
    weather: {'hourly': {'time': times, 'temperature_2m': t, 'apparent_temperature': f}},
    air: {'hourly': {'time': times, 'pm2_5': p25, 'pm10': p10}},
  );
}

void main() {
  sqfliteFfiInit();

  group('IndiaAqi (CPCB breakpoints)', () {
    test('band edges map to the right index', () {
      expect(IndiaAqi.subIndexPm25(30), 50);
      expect(IndiaAqi.subIndexPm25(60), 100);
      expect(IndiaAqi.subIndexPm25(90), 200);
      expect(IndiaAqi.subIndexPm25(120), 300);
      expect(IndiaAqi.subIndexPm25(250), 400);
      expect(IndiaAqi.subIndexPm10(100), 100);
      expect(IndiaAqi.subIndexPm10(250), 200);
    });

    test('interpolates inside a band', () {
      expect(IndiaAqi.subIndexPm25(75), 150); // halfway Moderate
    });

    test('overall index is the worse pollutant', () {
      expect(IndiaAqi.index(pm25: 20, pm10: 300), IndiaAqi.subIndexPm10(300));
      expect(IndiaAqi.index(pm25: null, pm10: null), isNull);
    });

    test('categories', () {
      expect(IndiaAqi.category(45), AqiCategory.good);
      expect(IndiaAqi.category(150), AqiCategory.moderate);
      expect(IndiaAqi.category(250), AqiCategory.poor);
      expect(IndiaAqi.category(350), AqiCategory.veryPoor);
      expect(IndiaAqi.category(450), AqiCategory.severe);
      expect(AqiCategory.poor.moveIndoors, isTrue);
      expect(AqiCategory.moderate.moveIndoors, isFalse);
    });
  });

  group('Heat levels (IMD actual-temperature thresholds)', () {
    test('plains: 40 caution, 45 heat wave, 47 severe', () {
      expect(OutlookCalculator.heatLevel(39, 39, Terrain.plains), HeatLevel.none);
      expect(OutlookCalculator.heatLevel(41, 41, Terrain.plains), HeatLevel.caution);
      expect(OutlookCalculator.heatLevel(45.5, 46, Terrain.plains), HeatLevel.heatwave);
      expect(OutlookCalculator.heatLevel(47.2, 48, Terrain.plains), HeatLevel.severe);
    });

    test('coastal from 37, hills from 30', () {
      expect(OutlookCalculator.heatLevel(37.5, 38, Terrain.coastal), HeatLevel.caution);
      expect(OutlookCalculator.heatLevel(31, 31, Terrain.hills), HeatLevel.caution);
    });

    test('humid "feels like" heat raises a caution', () {
      expect(OutlookCalculator.heatLevel(35, 43, Terrain.coastal), HeatLevel.caution);
    });
  });

  group('Day outlook', () {
    test('clean, mild day: good air and a walk suggestion', () {
      final f = forecast(temp: (d, h) => 24 + (h == 14 ? 6 : 0), pm25: (d, h) => h == 6 ? 10 : 20);
      final hours = EnvironmentService.mergeHourly(f.weather, f.air);
      final o = const OutlookCalculator().forDay(DateTime(2026, 5, 20), hours, Terrain.plains);
      expect(o.aqiCategory, AqiCategory.good);
      expect(o.heat, HeatLevel.none);
      expect(o.bestWalk?.startHour, 6);
      expect(o.advice, contains('Best time for a walk: 6–7 AM'));
      expect(o.alertWorthy, isFalse);
    });

    test('poor air: move indoors, no walk suggestion, alert-worthy', () {
      final f = forecast(temp: (d, h) => 25, pm25: (d, h) => 110);
      final hours = EnvironmentService.mergeHourly(f.weather, f.air);
      final o = const OutlookCalculator().forDay(DateTime(2026, 5, 20), hours, Terrain.plains);
      expect(o.aqiCategory, AqiCategory.poor);
      expect(o.advice, contains('indoor'));
      expect(o.advice, isNot(contains('Best time')));
      expect(o.alertWorthy, isTrue);
    });

    test('hot day: never suggests a hot hour, warns about 12–3 PM', () {
      final f = forecast(temp: (d, h) => h >= 9 && h <= 18 ? 42 : 30, pm25: (d, h) => 25);
      final hours = EnvironmentService.mergeHourly(f.weather, f.air);
      final o = const OutlookCalculator().forDay(DateTime(2026, 5, 20), hours, Terrain.plains);
      expect(o.heat, HeatLevel.caution);
      expect(o.advice, contains('12–3 PM'));
      expect(o.bestWalk!.startHour, anyOf(5, 6, 7, 8, 19));
    });
  });

  group('EnvironmentService', () {
    Future<SqliteHealthStore> openStore() =>
        SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);

    test('free tier uses public hosts; an API key switches to customer hosts', () async {
      final store = await openStore();
      final seen = <Uri>[];
      final f = forecast(temp: (d, h) => 25, pm25: (d, h) => 20);
      Future<Map<String, Object?>> fetch(Uri u) async {
        seen.add(u);
        return u.host.contains('air-quality') ? f.air : f.weather;
      }

      final city = cityNamed('Hyderabad')!;
      await EnvironmentService(store, fetch: fetch).outlooks(city);
      expect(seen.map((u) => u.host), ['api.open-meteo.com', 'air-quality-api.open-meteo.com']);
      expect(seen.first.queryParameters['timezone'], 'auto');

      seen.clear();
      await EnvironmentService(store, fetch: fetch, apiKey: 'k').outlooks(city);
      expect(seen.first.host, 'customer-api.open-meteo.com');
      expect(seen.first.queryParameters['apikey'], 'k');
      await store.close();
    });

    test('network failure -> friendly error', () async {
      final store = await openStore();
      final env = EnvironmentService(store, fetch: (_) async => throw Exception('offline'));
      expect(env.outlooks(cityNamed('Delhi')!), throwsA(isA<EnvironmentException>()));
      await store.close();
    });

    test('bad day tomorrow -> 7 AM alert scheduled; good day -> none', () async {
      final store = await openStore();
      final n = _FakeNotifier();
      final bad = forecast(temp: (d, h) => 25, pm25: (d, h) => d == 1 ? 130 : 20);
      final env = EnvironmentService(store,
          notifier: n,
          fetch: (u) async => u.host.contains('air-quality') ? bad.air : bad.weather,
          now: () => DateTime(2026, 5, 20, 12));
      await env.setCity(cityNamed('Delhi')!);
      expect(await env.setAlerts(true), isTrue);

      await env.refreshAlert();
      final alert = n.once[EnvironmentService.alertId]!;
      expect(alert.at, DateTime(2026, 5, 21, 7));
      expect(alert.title, contains('very poor'));

      final good = forecast(temp: (d, h) => 25, pm25: (d, h) => 20);
      final env2 = EnvironmentService(store,
          notifier: n,
          fetch: (u) async => u.host.contains('air-quality') ? good.air : good.weather,
          now: () => DateTime(2026, 5, 20, 12));
      await env2.refreshAlert();
      expect(n.once.containsKey(EnvironmentService.alertId), isFalse);
      await store.close();
    });

    test('alerts stay off when notification permission is refused', () async {
      final store = await openStore();
      final env = EnvironmentService(store, notifier: _FakeNotifier()..grant = false);
      expect(await env.setAlerts(true), isFalse);
      expect(await env.alertsOn(), isFalse);
      await store.close();
    });
  });
}
