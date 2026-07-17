/// HUX Modes — model
/// -------------------
/// "Modes" re-aim the same Meaning engine at a life moment: a target
/// date, phased coaching leading up to it, and a readiness message on
/// the day itself. This file is the shared model for every EVENT mode
/// (Big Day, Shaadi, Exam Season, and whatever comes after) — pure
/// Dart, no Flutter, no storage.
///
/// At most ONE event mode is active at a time. Starting a new one
/// replaces the old (the UI confirms this with the user first;
/// [ModeService] just does the replace).

/// Every event mode this app knows about. Extensible: adding a new
/// life moment is a new enum value plus a content pack, not a new
/// mechanic — see event_mode_engine.dart and content/event_content.dart.
enum ModeId { bigDay, shaadi, examSeason }

/// One active mode's configuration: which mode, aimed at which date,
/// with an optional user label ("Priya's wedding", "Board exam").
class EventModeConfig {
  final ModeId id;

  /// The date the mode is counting down to. Compared as a calendar
  /// date (time-of-day is ignored) wherever "days to go" is computed.
  final DateTime targetDate;

  final String? label;

  /// When the user started this mode — not shown to the user anywhere
  /// yet, but useful for a future "how long was I in this mode" story.
  final DateTime startedAt;

  const EventModeConfig({
    required this.id,
    required this.targetDate,
    this.label,
    required this.startedAt,
  });

  Map<String, Object?> toJson() => {
        'id': id.name,
        'targetDate': targetDate.toUtc().toIso8601String(),
        'label': label,
        'startedAt': startedAt.toUtc().toIso8601String(),
      };

  factory EventModeConfig.fromJson(Map<String, Object?> json) =>
      EventModeConfig(
        id: ModeId.values.byName(json['id'] as String),
        targetDate: DateTime.parse(json['targetDate'] as String),
        label: json['label'] as String?,
        startedAt: DateTime.parse(json['startedAt'] as String),
      );
}

/// The active mode, or none. A thin wrapper so callers don't juggle a
/// bare nullable [EventModeConfig] everywhere.
class ModeState {
  final EventModeConfig? active;

  const ModeState({this.active});

  const ModeState.none() : active = null;

  bool get hasActive => active != null;
}

/// LIFESTYLE modes vs the EVENT modes above: an event mode counts down
/// to a date. A lifestyle mode describes how the user lives right now,
/// and changes the app's voice and advice while it's active — no
/// target date, no phases, no auto-complete. At most one of EACH kind
/// (night shift, fasting) is active at a time, but a lifestyle mode CAN
/// coexist with an active event mode (they answer different questions:
/// "what am I building toward" vs "how do I live day to day").
///
/// Persisted as their own rows in the same `mode_state` table as event
/// modes (keyed by [LifestyleModeId.name], a different key space to
/// [ModeId.name]) — no schema migration needed, see
/// sqlite_health_store.dart.
enum LifestyleModeId { nightShift, fasting }

/// Night Shift: the user's main sleep happens in the daytime, not
/// overnight. The engine doesn't need to know WHY (rotational shift
/// work, a newborn, whatever) — only that "last night" is the wrong
/// word for their most recent sleep. See sleep_wording.dart for the
/// wording swap this drives.
class NightShiftConfig {
  /// 24h clock hour (0-23) the user's main sleep usually starts.
  final int usualSleepStartHour;

  /// 24h clock hour (0-23) the user's main sleep usually ends.
  final int usualSleepEndHour;

  final DateTime startedAt;

  const NightShiftConfig({
    required this.usualSleepStartHour,
    required this.usualSleepEndHour,
    required this.startedAt,
  });

  Map<String, Object?> toJson() => {
        'usualSleepStartHour': usualSleepStartHour,
        'usualSleepEndHour': usualSleepEndHour,
        'startedAt': startedAt.toUtc().toIso8601String(),
      };

  factory NightShiftConfig.fromJson(Map<String, Object?> json) =>
      NightShiftConfig(
        usualSleepStartHour: json['usualSleepStartHour'] as int,
        usualSleepEndHour: json['usualSleepEndHour'] as int,
        startedAt: DateTime.parse(json['startedAt'] as String),
      );
}

/// A dated observance window during which food/drink advice must adapt
/// — Roza, Navratri, Ekadashi, Karwa Chauth, or a custom fast.
enum FastType { roza, navratri, ekadashi, karwaChauth, custom }

/// User-facing name for each [FastType] — kept generic enough to slot
/// into shared copy ("your fast" + displayName), see fasting_content.dart.
extension FastTypeDisplay on FastType {
  String get displayName => switch (this) {
        FastType.roza => 'Roza',
        FastType.navratri => 'Navratri fast',
        FastType.ekadashi => 'Ekadashi',
        FastType.karwaChauth => 'Karwa Chauth',
        FastType.custom => 'your fast',
      };
}

class FastingConfig {
  final FastType type;

  /// First and last calendar day of the observance (inclusive),
  /// compared as LOCAL calendar dates wherever "is today a fast day"
  /// or "which day of the fast is this" is computed — same convention
  /// as EventModeEngine._dateOnly, for the same reason: these round-
  /// trip through storage as UTC, but the question is a wall-clock one.
  final DateTime start;
  final DateTime end;

  /// Optional daily eating window (24h clock hours), when the user
  /// knows it in advance (e.g. iftar time). Null means "not specified"
  /// — content falls back to generic hydration guidance rather than
  /// naming hours it doesn't have.
  final int? eatingWindowStartHour;
  final int? eatingWindowEndHour;

  final DateTime startedAt;

  const FastingConfig({
    required this.type,
    required this.start,
    required this.end,
    this.eatingWindowStartHour,
    this.eatingWindowEndHour,
    required this.startedAt,
  });

  static DateTime _dateOnly(DateTime dt) {
    final local = dt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// Whether `day` falls within [start, end], inclusive, by local
  /// calendar date.
  bool isActiveOn(DateTime day) {
    final d = _dateOnly(day);
    return !d.isBefore(_dateOnly(start)) && !d.isAfter(_dateOnly(end));
  }

  /// 1-based day number within the fast (the start date is day 1).
  /// Only meaningful when [isActiveOn] is true for `day`.
  int dayNumberOn(DateTime day) =>
      _dateOnly(day).difference(_dateOnly(start)).inDays + 1;

  Map<String, Object?> toJson() => {
        'type': type.name,
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        'eatingWindowStartHour': eatingWindowStartHour,
        'eatingWindowEndHour': eatingWindowEndHour,
        'startedAt': startedAt.toUtc().toIso8601String(),
      };

  factory FastingConfig.fromJson(Map<String, Object?> json) => FastingConfig(
        type: FastType.values.byName(json['type'] as String),
        start: DateTime.parse(json['start'] as String),
        end: DateTime.parse(json['end'] as String),
        eatingWindowStartHour: json['eatingWindowStartHour'] as int?,
        eatingWindowEndHour: json['eatingWindowEndHour'] as int?,
        startedAt: DateTime.parse(json['startedAt'] as String),
      );
}

/// Everything the Meaning engine and the screens need to know about
/// which lifestyle modes are active right now — built fresh by
/// [ModeService.activeContext] on each read, never persisted itself.
class ActiveContext {
  final bool nightShiftActive;
  final NightShiftConfig? nightShift;

  /// The active fasting config, if a Fasting Companion window has been
  /// set up — regardless of whether TODAY falls inside it (a window
  /// can be scheduled ahead or linger after it ends until the user
  /// clears it). Use [fastingActiveOn] to ask about a specific day.
  final FastingConfig? fasting;

  /// [fasting]'s day number for the day this context was built for, or
  /// null if that day isn't inside the fast window.
  final int? fastDayNumber;

  const ActiveContext({
    this.nightShiftActive = false,
    this.nightShift,
    this.fasting,
    this.fastDayNumber,
  });

  bool fastingActiveOn(DateTime day) =>
      fasting != null && fasting!.isActiveOn(day);
}
