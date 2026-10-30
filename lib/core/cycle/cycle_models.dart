/// Cycle data — period dates, flow, symptoms and settings.
///
/// PRIVACY: everything here lives in ONE local setting (`cycle_v1`) on
/// this phone. It is never synced, never put in share cards, and only
/// reaches the coach as a single phase word if the user turns that on.
library;

/// How the user's body works right now — decides what HUX predicts.
enum CycleMode { regular, irregular, hormonal, pregnant, perimenopause }

extension CycleModeX on CycleMode {
  String get label => switch (this) {
        CycleMode.regular => 'Regular cycles',
        CycleMode.irregular => 'Irregular or PCOS',
        CycleMode.hormonal => 'On hormonal birth control',
        CycleMode.pregnant => 'Pregnant',
        CycleMode.perimenopause => 'Perimenopause',
      };

  String get hint => switch (this) {
        CycleMode.regular => 'Periods come roughly every 3–5 weeks.',
        CycleMode.irregular => 'Wider, calmer predictions. No red warnings.',
        CycleMode.hormonal => 'Log bleeding only — the pill or similar changes your phases.',
        CycleMode.pregnant => 'Predictions paused. You can still log how you feel.',
        CycleMode.perimenopause => 'Cycles change — HUX keeps ranges wide.',
      };

  /// Predicts the next period at all.
  bool get predicts => this == CycleMode.regular || this == CycleMode.irregular || this == CycleMode.perimenopause;

  /// Shows a phase (and lets scores compare same-phase days).
  bool get hasPhases => predicts;

  /// Wider prediction ranges.
  bool get wide => this == CycleMode.irregular || this == CycleMode.perimenopause;
}

enum FlowLevel { spotting, light, medium, heavy }

extension FlowLevelX on FlowLevel {
  String get label => switch (this) {
        FlowLevel.spotting => 'Spotting',
        FlowLevel.light => 'Light',
        FlowLevel.medium => 'Medium',
        FlowLevel.heavy => 'Heavy',
      };
}

enum CyclePhase { period, follicular, ovulatory, luteal }

extension CyclePhaseX on CyclePhase {
  String get label => switch (this) {
        CyclePhase.period => 'Period',
        CyclePhase.follicular => 'Follicular',
        CyclePhase.ovulatory => 'Ovulatory',
        CyclePhase.luteal => 'Luteal',
      };
}

enum Symptom { cramps, bloating, headache, backPain, tender, acne, tired, lowMood, irritable, cravings, poorSleep, energetic }

extension SymptomX on Symptom {
  String get label => switch (this) {
        Symptom.cramps => 'Cramps',
        Symptom.bloating => 'Bloating',
        Symptom.headache => 'Headache',
        Symptom.backPain => 'Back pain',
        Symptom.tender => 'Tender breasts',
        Symptom.acne => 'Acne',
        Symptom.tired => 'Tired',
        Symptom.lowMood => 'Low mood',
        Symptom.irritable => 'Irritable',
        Symptom.cravings => 'Cravings',
        Symptom.poorSleep => 'Poor sleep',
        Symptom.energetic => 'Full of energy',
      };
}

// ---- dates (local calendar days, stored as yyyy-mm-dd) --------------------

DateTime dayOf(DateTime t) {
  final l = t.isUtc ? t.toLocal() : t;
  return DateTime(l.year, l.month, l.day);
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDay(String k) {
  final p = k.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Whole calendar days from [a] to [b] (DST-safe).
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

// ---- records ---------------------------------------------------------------

class PeriodRecord {
  final DateTime start;

  /// Last bleeding day; null while the period is still going.
  final DateTime? end;

  /// 'manual' or 'health' (imported).
  final String source;

  const PeriodRecord({required this.start, this.end, this.source = 'manual'});

  int? get lengthDays => end == null ? null : daysBetween(start, end!) + 1;

  PeriodRecord copyWith({DateTime? start, DateTime? end, bool clearEnd = false}) =>
      PeriodRecord(start: start ?? this.start, end: clearEnd ? null : (end ?? this.end), source: source);

  Map<String, Object?> toJson() => {
        's': dayKey(start),
        if (end != null) 'e': dayKey(end!),
        if (source != 'manual') 'src': source,
      };

  static PeriodRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return PeriodRecord(
        start: parseDay(j['s'] as String),
        end: j['e'] == null ? null : parseDay(j['e'] as String),
        source: (j['src'] as String?) ?? 'manual',
      );
    } catch (_) {
      return null;
    }
  }
}

class DayLog {
  final FlowLevel? flow;
  final Set<Symptom> symptoms;

  const DayLog({this.flow, this.symptoms = const {}});

  bool get isEmpty => flow == null && symptoms.isEmpty;

  Map<String, Object?> toJson() => {
        if (flow != null) 'f': flow!.name,
        if (symptoms.isNotEmpty) 'sy': [for (final s in symptoms) s.name],
      };

  static DayLog fromJson(Object? j) {
    if (j is! Map) return const DayLog();
    FlowLevel? flow;
    for (final f in FlowLevel.values) {
      if (f.name == j['f']) flow = f;
    }
    final names = (j['sy'] is List) ? (j['sy'] as List).map((e) => '$e').toSet() : <String>{};
    return DayLog(flow: flow, symptoms: {for (final s in Symptom.values) if (names.contains(s.name)) s});
  }
}

class CycleSettings {
  final bool enabled;
  final CycleMode mode;
  final int usualCycleDays;
  final int usualPeriodDays;

  /// One discreet "Heads-up from HUX" 2 days before the likely window.
  final bool headsUp;

  /// Send ONE word (the phase) to the coach. Off by default.
  final bool useInCoach;

  /// Offer the gentle workout on the first period days (Journeys).
  final bool gentleMoves;

  /// The small card on Home.
  final bool showOnHome;

  /// Ask for Face ID / fingerprint / phone PIN before showing Cycle.
  final bool lock;

  const CycleSettings({
    this.enabled = false,
    this.mode = CycleMode.regular,
    this.usualCycleDays = 28,
    this.usualPeriodDays = 5,
    this.headsUp = false,
    this.useInCoach = false,
    this.gentleMoves = true,
    this.showOnHome = true,
    this.lock = false,
  });

  CycleSettings copyWith({
    bool? enabled,
    CycleMode? mode,
    int? usualCycleDays,
    int? usualPeriodDays,
    bool? headsUp,
    bool? useInCoach,
    bool? gentleMoves,
    bool? showOnHome,
    bool? lock,
  }) =>
      CycleSettings(
        enabled: enabled ?? this.enabled,
        mode: mode ?? this.mode,
        usualCycleDays: usualCycleDays ?? this.usualCycleDays,
        usualPeriodDays: usualPeriodDays ?? this.usualPeriodDays,
        headsUp: headsUp ?? this.headsUp,
        useInCoach: useInCoach ?? this.useInCoach,
        gentleMoves: gentleMoves ?? this.gentleMoves,
        showOnHome: showOnHome ?? this.showOnHome,
        lock: lock ?? this.lock,
      );

  Map<String, Object?> toJson() => {
        'on': enabled,
        'mode': mode.name,
        'cycle': usualCycleDays,
        'period': usualPeriodDays,
        'headsUp': headsUp,
        'coach': useInCoach,
        'gentle': gentleMoves,
        'home': showOnHome,
        'lock': lock,
      };

  static CycleSettings fromJson(Object? j) {
    if (j is! Map) return const CycleSettings();
    var mode = CycleMode.regular;
    for (final m in CycleMode.values) {
      if (m.name == j['mode']) mode = m;
    }
    int intOr(Object? v, int d, int lo, int hi) => v is int ? v.clamp(lo, hi) : d;
    return CycleSettings(
      enabled: j['on'] == true,
      mode: mode,
      usualCycleDays: intOr(j['cycle'], 28, 18, 60),
      usualPeriodDays: intOr(j['period'], 5, 2, 10),
      headsUp: j['headsUp'] == true,
      useInCoach: j['coach'] == true,
      gentleMoves: j['gentle'] != false,
      showOnHome: j['home'] != false,
      lock: j['lock'] == true,
    );
  }
}

class CycleData {
  final CycleSettings settings;

  /// Oldest first.
  final List<PeriodRecord> periods;

  /// yyyy-mm-dd → flow / symptoms.
  final Map<String, DayLog> days;

  const CycleData({this.settings = const CycleSettings(), this.periods = const [], this.days = const {}});

  static const empty = CycleData();

  CycleData copyWith({CycleSettings? settings, List<PeriodRecord>? periods, Map<String, DayLog>? days}) {
    final p = [...(periods ?? this.periods)]..sort((a, b) => a.start.compareTo(b.start));
    return CycleData(settings: settings ?? this.settings, periods: p, days: days ?? this.days);
  }

  DayLog dayLog(DateTime d) => days[dayKey(d)] ?? const DayLog();

  Map<String, Object?> toJson() => {
        'v': 1,
        'settings': settings.toJson(),
        'periods': [for (final p in periods) p.toJson()],
        'days': {for (final e in days.entries) if (!e.value.isEmpty) e.key: e.value.toJson()},
      };

  static CycleData fromJson(Object? j) {
    if (j is! Map) return empty;
    final periods = (j['periods'] is List ? (j['periods'] as List) : const [])
        .map(PeriodRecord.fromJson)
        .whereType<PeriodRecord>()
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final days = <String, DayLog>{};
    if (j['days'] is Map) {
      (j['days'] as Map).forEach((k, v) => days['$k'] = DayLog.fromJson(v));
    }
    return CycleData(settings: CycleSettings.fromJson(j['settings']), periods: periods, days: days);
  }
}
