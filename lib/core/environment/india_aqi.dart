/// India's National Air Quality Index (CPCB) for PM2.5 and PM10.
///
/// Breakpoints (24-hour average, µg/m³):
///   AQI      Category      PM2.5      PM10
///   0–50     Good          0–30       0–50
///   51–100   Satisfactory  31–60      51–100
///   101–200  Moderate      61–90      101–250
///   201–300  Poor          91–120     251–350
///   301–400  Very poor     121–250    351–430
///   401–500  Severe        250+       430+
/// The overall index is the worse of the two sub-indices.
///
/// HUX computes this from FORECAST PM values (model data, not a CPCB
/// station), so the UI always labels it "estimated".
library;

enum AqiCategory { good, satisfactory, moderate, poor, veryPoor, severe }

extension AqiCategoryText on AqiCategory {
  String get label => switch (this) {
        AqiCategory.good => 'Good',
        AqiCategory.satisfactory => 'Satisfactory',
        AqiCategory.moderate => 'Moderate',
        AqiCategory.poor => 'Poor',
        AqiCategory.veryPoor => 'Very poor',
        AqiCategory.severe => 'Severe',
      };

  /// Plain, non-medical advice for outdoor exercise.
  String get advice => switch (this) {
        AqiCategory.good => 'Great air — enjoy your walk outside.',
        AqiCategory.satisfactory => 'Fine for most people outdoors.',
        AqiCategory.moderate => 'OK for a walk; keep hard workouts short if you feel it.',
        AqiCategory.poor => 'Prefer indoor exercise today, or keep outdoor time short.',
        AqiCategory.veryPoor => 'Exercise indoors today.',
        AqiCategory.severe => 'Stay indoors as much as you can today.',
      };

  /// From [poor] up, HUX suggests moving workouts indoors.
  bool get moveIndoors => index >= AqiCategory.poor.index;
}

class IndiaAqi {
  const IndiaAqi._();

  // [concLow, concHigh, aqiLow, aqiHigh]
  static const _pm25 = [
    [0.0, 30.0, 0.0, 50.0],
    [30.0, 60.0, 50.0, 100.0],
    [60.0, 90.0, 100.0, 200.0],
    [90.0, 120.0, 200.0, 300.0],
    [120.0, 250.0, 300.0, 400.0],
    [250.0, 380.0, 400.0, 500.0],
  ];
  static const _pm10 = [
    [0.0, 50.0, 0.0, 50.0],
    [50.0, 100.0, 50.0, 100.0],
    [100.0, 250.0, 100.0, 200.0],
    [250.0, 350.0, 200.0, 300.0],
    [350.0, 430.0, 300.0, 400.0],
    [430.0, 510.0, 400.0, 500.0],
  ];

  static int _sub(double c, List<List<double>> table) {
    if (c <= 0) return 0;
    for (final row in table) {
      if (c <= row[1]) {
        return (row[2] + (c - row[0]) * (row[3] - row[2]) / (row[1] - row[0])).round();
      }
    }
    return 500;
  }

  static int subIndexPm25(double c) => _sub(c, _pm25);
  static int subIndexPm10(double c) => _sub(c, _pm10);

  /// Overall index from 24-hour average concentrations (either may be null).
  static int? index({double? pm25, double? pm10}) {
    final a = pm25 == null ? null : subIndexPm25(pm25);
    final b = pm10 == null ? null : subIndexPm10(pm10);
    if (a == null) return b;
    if (b == null) return a;
    return a > b ? a : b;
  }

  static AqiCategory category(int aqi) {
    if (aqi <= 50) return AqiCategory.good;
    if (aqi <= 100) return AqiCategory.satisfactory;
    if (aqi <= 200) return AqiCategory.moderate;
    if (aqi <= 300) return AqiCategory.poor;
    if (aqi <= 400) return AqiCategory.veryPoor;
    return AqiCategory.severe;
  }
}
