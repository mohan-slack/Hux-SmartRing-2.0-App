/// Fetches hourly weather + air-quality forecasts and turns them into
/// today/tomorrow outlooks; saves the chosen city and alert setting; and
/// schedules a morning alert for tomorrow when it looks bad.
///
/// DATA SOURCE: Open-Meteo (weather models + CAMS air-quality model),
/// CC-BY 4.0 — the screen shows the attribution. Open-Meteo's FREE API
/// is for NON-COMMERCIAL use only: before a paid HUX launch, buy an
/// Open-Meteo API plan (pass [apiKey]) or route calls through the HUX
/// backend.
library;

import 'dart:convert';
import 'dart:io';

import '../nudges/notifier.dart';
import '../storage/health_store.dart';
import 'india_aqi.dart';
import 'india_cities.dart';
import 'outlook.dart';

typedef JsonFetcher = Future<Map<String, Object?>> Function(Uri uri);

/// Plain dart:io GET returning decoded JSON (no extra package needed).
Future<Map<String, Object?>> httpGetJson(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(uri);
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final body = await res.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, Object?>;
  } finally {
    client.close();
  }
}

class EnvironmentException implements Exception {
  final String message;
  const EnvironmentException(this.message);
  @override
  String toString() => message;
}

class Outlooks {
  final IndiaCity city;
  final DayOutlook today;
  final DayOutlook tomorrow;
  const Outlooks(this.city, this.today, this.tomorrow);
}

class EnvironmentService {
  static const _cityKey = 'env_city';
  static const _alertsKey = 'env_alerts';
  static const alertId = 1101;

  /// Morning alert time (local).
  static const alertHour = 7;

  final HealthStore _store;
  final Notifier? _notifier;
  final JsonFetcher _fetch;
  final String? apiKey;
  final DateTime Function() _now;

  EnvironmentService(this._store,
      {Notifier? notifier, JsonFetcher fetch = httpGetJson, this.apiKey, DateTime Function()? now})
      : _notifier = notifier,
        _fetch = fetch,
        _now = now ?? DateTime.now;

  Future<IndiaCity?> city() async => cityNamed(await _store.readSetting(_cityKey));
  Future<void> setCity(IndiaCity c) => _store.writeSetting(_cityKey, c.name);

  Future<bool> alertsOn() async => (await _store.readSetting(_alertsKey)) == 'yes';

  /// Turning on asks notification permission; returns the final state.
  Future<bool> setAlerts(bool on) async {
    var enabled = on;
    if (enabled && _notifier != null) enabled = await _notifier.requestPermission();
    if (_notifier == null) enabled = false;
    await _store.writeSetting(_alertsKey, enabled ? 'yes' : 'no');
    if (!enabled) await _notifier?.cancel(alertId);
    return enabled;
  }

  Uri _uri(String host, String path, IndiaCity c, String hourly) {
    final paid = apiKey != null && apiKey!.isNotEmpty;
    return Uri.https(paid ? 'customer-$host' : host, path, {
      'latitude': c.lat.toString(),
      'longitude': c.lon.toString(),
      'hourly': hourly,
      'timezone': 'auto',
      'forecast_days': '2',
      if (paid) 'apikey': apiKey!,
    });
  }

  Future<Outlooks> outlooks(IndiaCity c, {DateTime? now}) async {
    final Map<String, Object?> weather;
    final Map<String, Object?> air;
    try {
      weather = await _fetch(_uri('api.open-meteo.com', '/v1/forecast', c, 'temperature_2m,apparent_temperature'));
      air = await _fetch(_uri('air-quality-api.open-meteo.com', '/v1/air-quality', c, 'pm2_5,pm10'));
    } catch (_) {
      throw const EnvironmentException("Couldn't get today's air and heat — check your connection.");
    }
    final hours = mergeHourly(weather, air);
    if (hours.isEmpty) throw const EnvironmentException('No forecast available for this city right now.');

    // Forecast times are the city's local wall clock (timezone=auto).
    final today = hours.first.time;
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    const calc = OutlookCalculator();
    return Outlooks(c, calc.forDay(today, hours, c.terrain), calc.forDay(tomorrow, hours, c.terrain));
  }

  /// Joins the two hourly responses on their timestamps.
  static List<HourPoint> mergeHourly(Map<String, Object?> weather, Map<String, Object?> air) {
    List<String> times(Map<String, Object?> j) {
      final h = j['hourly'];
      final t = h is Map ? h['time'] : null;
      return t is List ? t.whereType<String>().toList() : const [];
    }

    List<double?> series(Map<String, Object?> j, String key) {
      final h = j['hourly'];
      final v = h is Map ? h[key] : null;
      return v is List ? [for (final x in v) x is num ? x.toDouble() : null] : const [];
    }

    final wTimes = times(weather);
    final temp = series(weather, 'temperature_2m');
    final feels = series(weather, 'apparent_temperature');
    final aIndex = <String, int>{for (final (i, t) in times(air).indexed) t: i};
    final pm25 = series(air, 'pm2_5');
    final pm10 = series(air, 'pm10');

    T? at<T>(List<T?> list, int i) => i >= 0 && i < list.length ? list[i] : null;

    final result = <HourPoint>[];
    for (final (i, t) in wTimes.indexed) {
      final time = DateTime.tryParse(t);
      if (time == null) continue;
      final ai = aIndex[t] ?? -1;
      result.add(HourPoint(
        time: time,
        tempC: at(temp, i),
        feelsC: at(feels, i),
        pm25: at(pm25, ai),
        pm10: at(pm10, ai),
      ));
    }
    return result;
  }

  /// On app open: refresh tomorrow's outlook and (re)schedule the 7 AM
  /// alert if tomorrow looks bad. Quietly does nothing when off/offline.
  Future<void> refreshAlert() async {
    if (!await alertsOn() || _notifier == null) return;
    final c = await city();
    if (c == null) return;
    final o = await outlooks(c);
    // Opened before 7 AM? The next alert is TODAY's — scheduling only
    // tomorrow's (as before) cancelled the one due in a few hours.
    final now = _now();
    final todayAlert = DateTime(o.today.day.year, o.today.day.month, o.today.day.day, alertHour);
    final t = now.isBefore(todayAlert) ? o.today : o.tomorrow;
    await _notifier.cancel(alertId);
    if (!t.alertWorthy) return;
    final at = DateTime(t.day.year, t.day.month, t.day.day, alertHour);
    await _notifier.scheduleOnce(
      id: alertId,
      at: at,
      title: _alertTitle(t),
      body: t.advice,
    );
  }

  static String _alertTitle(DayOutlook d) {
    if (d.heat == HeatLevel.heatwave || d.heat == HeatLevel.severe) return 'Very hot day ahead';
    if (d.heat == HeatLevel.caution) return 'Hot day ahead';
    return 'Air is ${d.aqiCategory?.label.toLowerCase() ?? 'poor'} today';
  }
}
