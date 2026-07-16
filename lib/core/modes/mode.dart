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
