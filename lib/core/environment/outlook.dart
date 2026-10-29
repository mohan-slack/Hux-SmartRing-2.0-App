/// Air & heat outlook for one day — pure Dart, from hourly forecasts.
///
/// Heat thresholds follow IMD's heat-wave criteria based on ACTUAL
/// maximum temperature (no "normal" climatology needed):
///   plains:  caution from 40 °C, heat wave 45 °C, severe heat wave 47 °C
///   coastal: caution from 37 °C;  hills: caution from 30 °C
/// IMD also declares heat waves from departure-from-normal, which HUX
/// can't compute without station normals — so HUX's levels are guidance,
/// never an official IMD warning. Humid "feels like" heat raises caution.
/// Advice (avoid 12–3 PM outdoors, drink water) follows NDMA guidance.
library;

import 'india_aqi.dart';
import 'india_cities.dart';

enum HeatLevel { none, caution, heatwave, severe }

class HourPoint {
  /// Local wall-clock hour start (as returned by the forecast, tz=auto).
  final DateTime time;
  final double? tempC;
  final double? feelsC;
  final double? pm25;
  final double? pm10;
  const HourPoint({required this.time, this.tempC, this.feelsC, this.pm25, this.pm10});
}

class WalkWindow {
  final int startHour; // local, e.g. 6 = 6 AM
  final String label; // "6–7 AM"
  const WalkWindow(this.startHour, this.label);
}

class DayOutlook {
  final DateTime day;
  final int? aqi;
  final AqiCategory? aqiCategory;
  final double? maxTempC;
  final double? maxFeelsC;
  final HeatLevel heat;
  final WalkWindow? bestWalk;

  /// The one-line advice shown to the user.
  final String advice;

  const DayOutlook({
    required this.day,
    required this.aqi,
    required this.aqiCategory,
    required this.maxTempC,
    required this.maxFeelsC,
    required this.heat,
    required this.bestWalk,
    required this.advice,
  });

  /// Worth a morning alert: air Poor or worse, or any heat caution.
  bool get alertWorthy => (aqiCategory?.moveIndoors ?? false) || heat != HeatLevel.none;
}

class OutlookCalculator {
  /// Feels-like at or above this raises at least a caution (humid heat).
  static const feelsCautionC = 42.0;

  /// Walk windows considered (local hours). Midday is never suggested.
  static const morningHours = [5, 6, 7, 8];
  static const eveningHours = [17, 18, 19];

  /// Too hot to suggest walking in that hour.
  static const walkMaxFeelsC = 36.0;

  const OutlookCalculator();

  static HeatLevel heatLevel(double? maxTemp, double? maxFeels, Terrain terrain) {
    var level = HeatLevel.none;
    if (maxTemp != null) {
      switch (terrain) {
        case Terrain.plains:
          if (maxTemp >= 47) {
            level = HeatLevel.severe;
          } else if (maxTemp >= 45) {
            level = HeatLevel.heatwave;
          } else if (maxTemp >= 40) {
            level = HeatLevel.caution;
          }
        case Terrain.coastal:
          if (maxTemp >= 37) level = HeatLevel.caution;
        case Terrain.hills:
          if (maxTemp >= 30) level = HeatLevel.caution;
      }
    }
    if (level == HeatLevel.none && maxFeels != null && maxFeels >= feelsCautionC) {
      level = HeatLevel.caution;
    }
    return level;
  }

  DayOutlook forDay(DateTime day, List<HourPoint> hours, Terrain terrain) {
    final mine = hours
        .where((h) => h.time.year == day.year && h.time.month == day.month && h.time.day == day.day)
        .toList();

    double? avg(Iterable<double?> v) {
      final xs = v.whereType<double>().toList();
      return xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;
    }

    double? max(Iterable<double?> v) {
      final xs = v.whereType<double>().toList();
      return xs.isEmpty ? null : xs.reduce((a, b) => a > b ? a : b);
    }

    // CPCB uses 24-hour averages for PM; a day's mean of hourly
    // forecasts is the closest equivalent.
    final aqi = IndiaAqi.index(pm25: avg(mine.map((h) => h.pm25)), pm10: avg(mine.map((h) => h.pm10)));
    final category = aqi == null ? null : IndiaAqi.category(aqi);
    final maxTemp = max(mine.map((h) => h.tempC));
    final maxFeels = max(mine.map((h) => h.feelsC));
    final heat = heatLevel(maxTemp, maxFeels, terrain);

    // Best walk: cleanest air among cool-enough morning/evening hours.
    HourPoint? best;
    for (final h in mine) {
      final hr = h.time.hour;
      if (!morningHours.contains(hr) && !eveningHours.contains(hr)) continue;
      if (h.feelsC != null && h.feelsC! > walkMaxFeelsC) continue;
      if (best == null || (h.pm25 ?? 999) < (best.pm25 ?? 999)) best = h;
    }
    final window = best == null ? null : WalkWindow(best.time.hour, _hourLabel(best.time.hour));

    return DayOutlook(
      day: DateTime(day.year, day.month, day.day),
      aqi: aqi,
      aqiCategory: category,
      maxTempC: maxTemp,
      maxFeelsC: maxFeels,
      heat: heat,
      bestWalk: window,
      advice: _advice(category, heat, window),
    );
  }

  static String _hourLabel(int h) {
    String fmt(int x) => '${x % 12 == 0 ? 12 : x % 12}';
    final ampm = (h + 1) < 12 || (h + 1) == 24 ? 'AM' : 'PM';
    return '${fmt(h)}–${fmt(h + 1)} $ampm';
  }

  static String _advice(AqiCategory? aqi, HeatLevel heat, WalkWindow? walk) {
    final parts = <String>[];
    switch (heat) {
      case HeatLevel.severe:
      case HeatLevel.heatwave:
        parts.add('Very hot day: stay indoors 12–3 PM, drink water often, and skip outdoor workouts');
      case HeatLevel.caution:
        parts.add('Hot day: avoid the sun 12–3 PM and keep water with you');
      case HeatLevel.none:
        break;
    }
    if (aqi != null && (aqi.moveIndoors || parts.isEmpty)) parts.add(aqi.advice.replaceAll(RegExp(r'\.$'), ''));
    if (walk != null && !(aqi?.moveIndoors ?? false) && heat.index < HeatLevel.heatwave.index) {
      parts.add('Best time for a walk: ${walk.label}');
    }
    if (parts.isEmpty) return 'No air or heat data for today.';
    return '${parts.join('. ')}.';
  }
}
